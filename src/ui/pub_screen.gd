class_name PubScreen
extends Control

# =============================================================
#  THE PUB
#
#  Pick a brew on the left, then click a card on the right to pour it.
#  Everything comes from res://data/Brews.csv.
#
#  Reached from the Pub on the base screen, or with  goto:pub .
#
#  Base cards have no abilities. A brew is where a card's ability comes
#  from, and it changes what class the card counts as, so a Lorelei who
#  drank a Fire Brew is hit by "give all Brandteufel +1 power".
#
#  ============ TONIGHT'S TEN ============
#
#  "Choose 10 players and give them drinks, else basic units."
#
#  So the Pub is TWO decisions. First who is in the room — ten of them, and
#  the number is `pub_capacity` in Tuning.csv. Then what each of them drinks,
#  which is what this screen already did. Anyone not in the room plays as
#  they are: printed power, no brew, no borrowed class.
#
#  RIGHT-CLICK a card to put it in the room or send it home. Left-click
#  still pours, and a card that is not in the room cannot be poured for.
#
#  It is OFF out of the box — `pub_ten` in Tuning.csv — because a room with
#  ten seats is only a choice once you have more than ten cards. While it is
#  false the room is everybody and nothing on this screen changes.
# =============================================================

const CARD_SIZE := Vector2(150.0, 176.0)

var cards: CardDatabase
var brews: BrewDB
var state: GameState

var _brew_list: VBoxContainer
var _card_grid: GridContainer
var _detail: Label
var _permanent: CheckBox
var _selected: Dictionary = {}
var _seats: Label


func _ready() -> void:
	# Escape, controller navigation, the key bindings, the player's
	# settings and the language — all five from this one line. See
	# menu_escape.gd.
	# THE WINDOW DOES ALL THREE when this screen is opened over the base:
	# the background, the Back button and Escape. See base_window.gd.
	var windowed := MenuSupport.in_a_window(self)
	if not windowed:
		MenuEscape.install(self)
		# A WINDOW SIZES THIS SCREEN ITSELF. Pinning it to the whole viewport
		# from in here would fight the container it has been put in.
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	cards = CardDatabase.get_db()
	brews = BrewDB.get_db()
	state = GameState.fetch(get_tree())
	# WHO HAS TURNED INTO WHAT, and any named recruits - before the grid is
	# drawn, so a turned Johannes shows as the Lorelei he now is.
	TransformBook.apply_all(cards, state)

	_build_ui()
	_rebuild_brews()
	_rebuild_cards()
	_refresh_seats()
	# ============ SHUT UNTIL TEAM BUILD IS DONE (round Y) ============
	# The base sends you to Team Build first, but a `goto:pub` from a story
	# line could still land here - so the Pub says it too, and pours nothing.
	var ready := TeamBuild.status(state, cards)
	if not bool(ready["ok"]) and not TutorialBase.active(get_tree()):
		_detail.text = "The Pub is shut. " + String(ready["why"])
		_selected = {}
		for child in _brew_list.get_children():
			child.queue_free()
		for child in _card_grid.get_children():
			child.queue_free()


# =============================================================
#  LAYOUT
# =============================================================

func _build_ui() -> void:
	# NO BACKGROUND OF ITS OWN IN A WINDOW — the window has one, and a second
	# opaque rectangle would paint over the dimmed base behind it.
	if not MenuSupport.in_a_window(self):
		var fill := ColorRect.new()
		fill.color = MenuSupport.COLOUR_BACKGROUND
		fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(fill)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	margin.add_child(page)

	# --- header ---
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	page.add_child(header)

	var title := MenuSupport.heading("THE PUB", 32, MenuSupport.COLOUR_ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# THE WINDOW'S TITLE BAR ALREADY SAYS THIS.
	title.visible = not MenuSupport.in_a_window(self)
	header.add_child(title)

	_permanent = CheckBox.new()
	_permanent.text = "Make it permanent"
	_permanent.add_theme_font_size_override("font_size", 15)
	_permanent.tooltip_text = "Needs the Permanent Brews unlock, from the Master Brewer talent."
	_permanent.disabled = not state.is_unlocked(BrewDB.PERMANENT_UNLOCK)
	header.add_child(_permanent)

	var back := MenuSupport.icon_button("◇", "Back to the base", Vector2(190, 44))
	back.add_theme_font_size_override("font_size", 16)
	back.add_theme_stylebox_override("normal",
		MenuSupport.panel_style(MenuSupport.COLOUR_PANEL, MenuSupport.COLOUR_ACCENT))
	back.add_theme_stylebox_override("hover",
		MenuSupport.panel_style(MenuSupport.COLOUR_SLOT_EMPTY, MenuSupport.COLOUR_ACCENT))
	# THE WINDOW HAS A ✕. Two ways out of one screen is one too many.
	back.visible = not MenuSupport.in_a_window(self)
	back.pressed.connect(func() -> void:
		state.save_to_disk()
		ScenePaths.go_back(get_tree(), ScenePaths.BASE))
	header.add_child(back)

	_seats = Label.new()
	_seats.add_theme_font_size_override("font_size", 14)
	_seats.add_theme_color_override("font_color", MenuSupport.COLOUR_ACCENT)
	page.add_child(_seats)

	_detail = Label.new()
	_detail.text = "Pick a brew on the left, then a card to pour it for."
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_theme_font_size_override("font_size", 16)
	_detail.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT)
	_detail.custom_minimum_size = Vector2(0, 44)
	page.add_child(_detail)

	# --- two columns ---
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 20)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(body)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(300, 0)
	left.add_theme_constant_override("separation", 8)
	body.add_child(left)
	left.add_child(MenuSupport.heading("ON TAP", 18, MenuSupport.COLOUR_TEXT_DIM))

	var brew_scroll := ScrollContainer.new()
	brew_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	brew_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(brew_scroll)

	_brew_list = VBoxContainer.new()
	_brew_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_brew_list.add_theme_constant_override("separation", 6)
	brew_scroll.add_child(_brew_list)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	body.add_child(right)
	right.add_child(MenuSupport.heading("YOUR CARDS", 18, MenuSupport.COLOUR_TEXT_DIM))

	var card_scroll := ScrollContainer.new()
	card_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(card_scroll)

	_card_grid = GridContainer.new()
	_card_grid.columns = 6
	_card_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card_grid.add_theme_constant_override("h_separation", 8)
	_card_grid.add_theme_constant_override("v_separation", 8)
	card_scroll.add_child(_card_grid)


# =============================================================
#  THE BREW LIST
# =============================================================

func _rebuild_brews() -> void:
	for child in _brew_list.get_children():
		child.queue_free()

	var pourable := brews.available_for(state)
	if pourable.is_empty():
		var empty := Label.new()
		empty.text = "Nothing on tap yet.\n\nBrews are unlocked by the Brewing talents at the Training Ground."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_font_size_override("font_size", 15)
		empty.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
		_brew_list.add_child(empty)
		return

	for entry in pourable:
		_brew_list.add_child(_make_brew_button(entry))


func _make_brew_button(entry: Dictionary) -> Control:
	var chosen := not _selected.is_empty() \
		and String(_selected["id"]) == String(entry["id"])

	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 74)
	button.tooltip_text = String(entry["description"])

	var edge := MenuSupport.COLOUR_ACCENT if chosen else MenuSupport.COLOUR_SLOT_EMPTY
	var fill := MenuSupport.COLOUR_LOCKED if chosen else MenuSupport.COLOUR_PANEL
	button.add_theme_stylebox_override("normal", MenuSupport.panel_style(fill, edge))
	button.add_theme_stylebox_override("hover",
		MenuSupport.panel_style(MenuSupport.COLOUR_SLOT_EMPTY, MenuSupport.COLOUR_ACCENT))

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 1)
	button.add_child(box)

	var name_label := Label.new()
	name_label.text = String(entry["name"])
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 17)
	name_label.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name_label)

	var under := Label.new()
	under.text = _summary(entry)
	under.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	under.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	under.add_theme_font_size_override("font_size", 12)
	under.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	under.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(under)

	button.pressed.connect(func() -> void:
		_selected = entry
		_detail.text = "%s — %s" % [entry["name"], entry["description"]]
		_rebuild_brews()
		_rebuild_cards())
	return button


## "Lorelei becomes Brandteufel · 2 abilities · can be permanent"
func _summary(entry: Dictionary) -> String:
	var bits: PackedStringArray = []

	var for_class := String(entry["for_class"]).strip_edges()
	var becomes := String(entry["becomes"]).strip_edges()
	if becomes != "":
		bits.append("%s becomes %s" % [for_class if for_class != "" else "anyone", becomes])
	elif for_class != "":
		bits.append("%s only" % for_class)

	var abilities := 0
	if String(entry["attack"]).strip_edges() != "":
		abilities += 1
	if String(entry["defend"]).strip_edges() != "":
		abilities += 1
	if abilities > 0:
		bits.append("%d abilit%s" % [abilities, "y" if abilities == 1 else "ies"])

	if bool(entry["permanent"]):
		bits.append("can be permanent")
	if TransformBook.is_turning(entry):
		bits.append("%d beers, for good" % TransformBook.drinks_needed(entry))
	var price := BrewDB.cost_text(entry)
	if price != "":
		bits.append(price)
	return " · ".join(bits)


# =============================================================
#  THE CARD GRID
# =============================================================

## "7 of 10 seats taken", or the line that says the system is off.
func _refresh_seats() -> void:
	if _seats != null:
		_seats.text = PubBook.words(state, cards) \
			+ ("  ·  right-click a card to seat it or send it home." if PubBook.on(cards) else "")


func _rebuild_cards() -> void:
	for child in _card_grid.get_children():
		child.queue_free()

	for card in cards.players:
		if card.is_star():
			continue          # Stars keep their own printed abilities
		_card_grid.add_child(_make_card(card))


func _make_card(card: PlayerData) -> Control:
	var on_it := BrewDB.brew_id_for(card, state)
	var permanent := BrewDB.is_permanent(card, state)
	# AFFORDABLE AS WELL AS SUITABLE. A brew you cannot pay for is shown but
	# cannot be poured, and the detail line says what it would cost.
	var seated := PubBook.allowed(card, state, cards)
	var pourable := seated and not _selected.is_empty() and BrewDB.suits(_selected, card) \
		and BrewDB.can_afford(_selected, state) \
		and TransformBook.refusal(card, _selected, state, cards) == ""

	var button := Button.new()
	button.custom_minimum_size = CARD_SIZE

	var edge := MenuSupport.COLOUR_SLOT_EMPTY
	if on_it != "":
		edge = MenuSupport.COLOUR_ACCENT
	elif pourable:
		edge = MenuSupport.colour_for_tier(card.get_tier_clean())
	button.add_theme_stylebox_override("normal",
		MenuSupport.panel_style(MenuSupport.COLOUR_PANEL, edge))
	button.add_theme_stylebox_override("hover",
		MenuSupport.panel_style(MenuSupport.COLOUR_SLOT_EMPTY, MenuSupport.COLOUR_ACCENT))

	# NOT IN THE ROOM = DIMMED, not hidden. You need to see who you left out.
	if not seated:
		button.modulate = Color(0.55, 0.55, 0.58, 1.0)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	button.add_child(box)

	var portrait := MenuSupport.portrait_rect(card, cards, Vector2(126, 96))
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(portrait)

	var name_label := Label.new()
	name_label.text = card.player_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT)
	name_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name_label)

	var footer := Label.new()
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_font_size_override("font_size", 11)
	# HALFWAY THROUGH HIS THREE BEERS: "Water ●●○". Shown before anything
	# else, because it is the thing you are in the middle of.
	var beers := TransformBook.progress(card, state)
	if String(beers["element"]) != "" and not TransformBook.has_turned(card, state):
		var need := 3
		for entry2 in brews.brews:
			if TransformBook.is_turning(entry2) and TransformBook.element_of(entry2) == String(beers["element"]):
				need = TransformBook.drinks_needed(entry2)
				break
		footer.text = "%s %s%s" % [String(beers["element"]).capitalize(),
			"●".repeat(int(beers["count"])), "○".repeat(maxi(0, need - int(beers["count"])))]
		footer.add_theme_color_override("font_color", MenuSupport.COLOUR_ACCENT)
	elif on_it != "":
		var entry := brews.find(on_it)
		var label := String(entry["name"]) if not entry.is_empty() else on_it
		footer.text = ("%s (kept)" % label) if permanent else label
		footer.add_theme_color_override("font_color", MenuSupport.COLOUR_ACCENT)
	else:
		footer.text = "T%s  %s" % [card.get_tier_clean(), card.unit_type]
		footer.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(footer)

	button.pressed.connect(_on_card.bind(card))
	button.gui_input.connect(_on_card_right_click.bind(card))
	return button


## Right-click seats a card or sends it home. It is the second decision on
## this screen and it needed a second gesture — a modal "choose ten" step in
## front of the brews would have made pouring one drink a three-click job.
func _on_card_right_click(event: InputEvent, card: PlayerData) -> void:
	if not PubBook.on(cards):
		return
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_RIGHT:
		return
	var result := PubBook.toggle(card, state, cards)
	_detail.text = String(result["why"])
	_detail.add_theme_color_override("font_color",
		MenuSupport.COLOUR_TEXT if bool(result["ok"]) else Color(1.0, 0.72, 0.4))
	if bool(result["ok"]):
		state.save_to_disk()
	_refresh_seats()
	_rebuild_cards()


func _on_card(card: PlayerData) -> void:
	# A TURNING BREW IS ITS OWN THING - a count towards a change for good,
	# not an overlay - so it is handled before anything below can take a
	# one-match brew off by accident.
	if TransformBook.is_turning(_selected):
		_pour_turning(card)
		return

	# Clicking a card that already has a brew takes it off. That is how you
	# remove a permanent one, which you asked for.
	if BrewDB.brew_id_for(card, state) != "":
		BrewDB.clear_for(card, state)
		_detail.text = "%s is back to their old self." % card.player_name
		state.save_to_disk()
		_rebuild_cards()
		return

	if not PubBook.allowed(card, state, cards):
		_detail.text = "%s is not in the room. Right-click to give them a seat — %s" % [
			card.player_name, PubBook.words(state, cards).to_lower()]
		return

	if _selected.is_empty():
		_detail.text = "Pick a brew on the left first."
		return

	if not BrewDB.suits(_selected, card):
		_detail.text = "%s is %s. %s is only for %s." % [
			card.player_name, card.unit_type,
			_selected["name"], _selected["for_class"]]
		return

	var permanent := _permanent.button_pressed
	BrewDB.pour(card, _selected, permanent, state)
	state.save_to_disk()

	var kept := BrewDB.is_permanent(card, state)
	_detail.text = "%s drinks the %s.%s" % [card.player_name, _selected["name"],
		"  It will stick until you remove it." if kept else "  It wears off after the next match."]
	_rebuild_cards()


# =============================================================
#  THREE BEERS (round X) - see transform_book.gd
# =============================================================

func _pour_turning(card: PlayerData) -> void:
	if not PubBook.allowed(card, state, cards):
		_detail.text = "%s is not in the room. Right-click to give them a seat." % card.player_name
		return
	if not BrewDB.suits(_selected, card):
		_detail.text = "%s is %s. %s is only for %s players." % [
			card.player_name, card.unit_type, _selected["name"], _selected["for_class"]]
		return
	var result := TransformBook.pour(card, _selected, state, cards)
	_detail.text = String(result["why"])
	if not bool(result["ok"]):
		return
	state.save_to_disk()
	_rebuild_cards()
	if bool(result["ready"]):
		_ask_who(card, _selected)


## "Who does Johannes become?" - one button per set. Closing it without
## choosing is fine: he keeps his three beers and the Pub asks again the
## next time you click him with the same brew.
func _ask_who(card: PlayerData, entry: Dictionary) -> void:
	var options := TransformBook.choices(card, entry, cards)
	if options.is_empty():
		return

	var shade := ColorRect.new()
	shade.name = "WhoDoesHeBecome"
	shade.color = Color(0, 0, 0, 0.6)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.add_child(centre)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 0)
	panel.add_theme_stylebox_override("panel", MenuSupport.styled("window"))
	centre.add_child(panel)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	panel.add_child(list)

	list.add_child(MenuSupport.heading("WHO DOES %s BECOME?" % card.player_name.to_upper(),
		24, MenuSupport.COLOUR_ACCENT))
	var line := Label.new()
	line.text = "Tier %s · Power %d · %s. He keeps his name; he takes the card's class, abilities and art." % [
		card.get_tier_clean(), card.base_power_left, String(entry["becomes"])]
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	list.add_child(line)

	for role in options:
		var pick := Button.new()
		pick.custom_minimum_size = Vector2(0, 64)
		pick.alignment = HORIZONTAL_ALIGNMENT_LEFT
		pick.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		pick.text = "%s set  —  %s\n    %s / %s" % [role.card_set, role.player_name,
			role.attack_text.strip_edges(), role.defend_text.strip_edges()]
		# STYLED AS A PANEL, like every other big button on this screen: the
		# button skin's brass inner rule would run straight through two lines
		# of ability text.
		pick.add_theme_stylebox_override("normal",
			MenuSupport.panel_style(MenuSupport.COLOUR_PANEL, MenuSupport.COLOUR_SLOT_EMPTY))
		pick.add_theme_stylebox_override("hover",
			MenuSupport.panel_style(MenuSupport.COLOUR_SLOT_EMPTY, MenuSupport.COLOUR_ACCENT))
		pick.add_theme_stylebox_override("pressed",
			MenuSupport.panel_style(MenuSupport.COLOUR_LOCKED, MenuSupport.COLOUR_ACCENT))
		pick.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT)
		pick.add_theme_font_size_override("font_size", 15)
		pick.pressed.connect(func() -> void:
			TransformBook.complete(card, role, state)
			state.save_to_disk()
			TransformBook.apply_all(cards, state)
			_detail.text = "%s is a %s now - the %s set. Same name, same tier, same power." % [
				card.player_name, role.unit_type, role.card_set]
			shade.queue_free()
			_rebuild_cards())
		list.add_child(pick)

	var later := Button.new()
	later.text = "Not yet - he keeps his beers"
	later.pressed.connect(shade.queue_free)
	list.add_child(later)
