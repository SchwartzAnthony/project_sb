class_name CardPopup
extends Control

# =============================================================
#  CARD POPUP — the full card, shown when you click a player
#
#  Built entirely in code, so there is no scene file to keep in sync.
#  Add it to any screen and call show_card(). Click the backdrop, press
#  Escape, or hit CLOSE to dismiss it.
#
#  Everything it shows comes from the CSVs:
#    name / tier / power       -> your unit CSV
#    Attack and Defend text    -> your unit CSV (the printed card text)
#    ability names and effects -> Abilities.csv, via the Attack Ability /
#                                 Defend Ability columns
# =============================================================

var db: CardDatabase = null

var _backdrop: ColorRect
var _panel: PanelContainer
var _body: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	hide()

	_backdrop = ColorRect.new()
	_backdrop.color = Color(0, 0, 0, 0.65)
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.gui_input.connect(_on_backdrop_input)
	add_child(_backdrop)

	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel",
		MenuSupport.panel_style(MenuSupport.COLOUR_PANEL, MenuSupport.COLOUR_ACCENT))
	_panel.custom_minimum_size = Vector2(520, 0)
	centre.add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	_panel.add_child(margin)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 10)
	margin.add_child(_body)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		hide()
		get_viewport().set_input_as_handled()


func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		hide()


# -------------------------------------------------------------
#  CONTENT
# -------------------------------------------------------------

func show_card(card: PlayerData) -> void:
	if card == null:
		return

	for child in _body.get_children():
		child.queue_free()

	# --- Header: portrait + name / tier / power ---
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	_body.add_child(header)

	var portrait := MenuSupport.portrait_rect(card, db, Vector2(140, 140))
	header.add_child(portrait)

	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 4)
	header.add_child(titles)

	titles.add_child(MenuSupport.heading(card.player_name, 26))

	var subtitle := "%s  ·  Tier %s" % [card.unit_type, card.get_tier_clean()]
	if card.is_star():
		subtitle += "  ·  ★ STAR"
	titles.add_child(MenuSupport.heading(subtitle, 15, MenuSupport.COLOUR_TEXT_DIM))

	titles.add_child(MenuSupport.heading(
		"Attack %d   Defense %d" % [card.get_attack_power(), card.get_defense_power()],
		20, MenuSupport.COLOUR_ACCENT))

	var priority := MenuSupport.heading(
		"Ability priority %d — lower resolves first" % card.get_ability_priority(),
		13, MenuSupport.COLOUR_TEXT_DIM)
	titles.add_child(priority)

	if card.element != "":
		titles.add_child(MenuSupport.heading("Element: %s" % card.element, 13,
			MenuSupport.COLOUR_TEXT_DIM))

	_body.add_child(HSeparator.new())

	# --- Card text and wired-up abilities ---
	_add_section("ATTACK", card.attack_text, card.attack_ability_id)
	_add_section("DEFEND", card.defend_text, card.defend_ability_id)

	_body.add_child(HSeparator.new())

	var close := Button.new()
	close.text = "CLOSE"
	close.pressed.connect(hide)
	_body.add_child(close)

	show()
	move_to_front()


func _add_section(title: String, prose: String, ability_id: String) -> void:
	_body.add_child(MenuSupport.heading(title, 16, MenuSupport.COLOUR_ACCENT))

	var text := prose.strip_edges()
	if text == "":
		text = "—"
	var prose_label := Label.new()
	prose_label.text = text
	prose_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prose_label.custom_minimum_size = Vector2(470, 0)
	prose_label.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT)
	_body.add_child(prose_label)

	# If the card points at a row in Abilities.csv, spell out what it does.
	if ability_id.strip_edges() == "" or db == null:
		return
	var ability := db.get_ability(ability_id)
	if ability == null:
		_body.add_child(MenuSupport.heading(
			"⚠ '%s' is not a row in Abilities.csv" % ability_id, 13, Color(1.0, 0.55, 0.45)))
		return

	var mechanics := Label.new()
	mechanics.text = "⚙ %s — %s" % [ability.display_name, _plain_english(ability)]
	mechanics.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mechanics.custom_minimum_size = Vector2(470, 0)
	mechanics.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	mechanics.add_theme_font_size_override("font_size", 13)
	_body.add_child(mechanics)


## Turn an Abilities.csv row into a sentence, so the popup reads like a card
## and not like a spreadsheet.
func _plain_english(ability: AbilityData) -> String:
	var when_text := {
		"on_attack": "when attacking",
		"on_defend": "when defending",
		"on_duel_start": "as the duel begins",
		"on_win_duel": "on winning the duel",
		"on_lose_duel": "on losing the duel",
		"passive": "always",
	}.get(ability.trigger, ability.trigger)

	var what_text := {
		"add_attack": "attack",
		"add_defense": "defense",
		"add_power": "power",
		"add_shot_power": "shot power",
		"drain_stamina": "keeper stamina",
		"restore_stamina": "keeper stamina",
	}.get(ability.effect, ability.effect)

	var sign_text := "+" if ability.value >= 0 else ""
	var lasts := {
		"duel": "for this duel",
		"round": "for the round",
		"cycle": "until the next HOLD UP!",
		"match": "for the rest of the match",
	}.get(ability.scope, ability.scope)

	return "%s, give %s %s%d %s, %s." % [
		when_text.capitalize(), ability.target, sign_text, ability.value, what_text, lasts]
