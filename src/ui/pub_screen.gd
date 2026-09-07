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


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	cards = CardDatabase.get_db()
	brews = BrewDB.get_db()
	state = GameState.fetch(get_tree())

	_build_ui()
	_rebuild_brews()
	_rebuild_cards()


# =============================================================
#  LAYOUT
# =============================================================

func _build_ui() -> void:
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
	header.add_child(title)

	_permanent = CheckBox.new()
	_permanent.text = "Make it permanent"
	_permanent.add_theme_font_size_override("font_size", 15)
	_permanent.tooltip_text = "Needs the Permanent Brews unlock, from the Master Brewer talent."
	_permanent.disabled = not state.is_unlocked(BrewDB.PERMANENT_UNLOCK)
	header.add_child(_permanent)

	var back := Button.new()
	back.text = "Back to the base"
	back.custom_minimum_size = Vector2(190, 44)
	back.add_theme_font_size_override("font_size", 16)
	back.add_theme_stylebox_override("normal",
		MenuSupport.panel_style(MenuSupport.COLOUR_PANEL, MenuSupport.COLOUR_ACCENT))
	back.add_theme_stylebox_override("hover",
		MenuSupport.panel_style(MenuSupport.COLOUR_SLOT_EMPTY, MenuSupport.COLOUR_ACCENT))
	back.pressed.connect(func() -> void:
		state.save_to_disk()
		ScenePaths.go_to(get_tree(), ScenePaths.BASE))
	header.add_child(back)

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
	return " · ".join(bits)


# =============================================================
#  THE CARD GRID
# =============================================================

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
	var pourable := not _selected.is_empty() and BrewDB.suits(_selected, card)

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
	if on_it != "":
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
	return button


func _on_card(card: PlayerData) -> void:
	# Clicking a card that already has a brew takes it off. That is how you
	# remove a permanent one, which you asked for.
	if BrewDB.brew_id_for(card, state) != "":
		BrewDB.clear_for(card, state)
		_detail.text = "%s is back to their old self." % card.player_name
		state.save_to_disk()
		_rebuild_cards()
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
