class_name RevealStrip
extends Control

# =============================================================
#  THE CARD ON THE TABLE — what a reveal actually looks like
#
#  ============ WHAT IT IS ============
#
#  A strip that sits ABOVE the row of cards you are choosing from and holds
#  whatever has been played face up in this tier: theirs on the left, yours on
#  the right, each with its power and what its ability does in plain words.
#
#      +--------------------------------------------------+
#      |  THEY SHOWED            |         YOU SHOWED      |
#      |  [card]  Hexflame       |     Cinderworks [card]  |
#      |  P: 4  D: 4             |          P: 1   D: 1    |
#      |  Called Shot. +3 on ... |   Open Hand. +2 att ... |
#      +--------------------------------------------------+
#              ( the four cards you are choosing from )
#
#  ============ WHY IT IS A SEPARATE THING ============
#
#  A reveal is not a card in your hand and it is not a card on the pitch — it
#  is a card ON THE TABLE, face up, that both sides can see while the choice
#  is still open. Nothing else in the game is that, so nothing else could be
#  reused for it.
#
#  It shows whichever sides have revealed. One side, both sides or neither —
#  when neither has, the strip is not there at all.
#
#  ============ IT IS TOLD, IT DOES NOT ASK ============
#
#  main_scene calls show_card() when somebody reveals and clear() when the
#  tier is over. It reads nothing and decides nothing, so there is no second
#  copy of "who has revealed what" to get out of step with the first.
# =============================================================

## The card each side has on the table for this tier, or null.
var _theirs: PlayerData = null
var _mine: PlayerData = null
var _db: CardDatabase = null

var _row: HBoxContainer
var _panel: PanelContainer


static func make(db: CardDatabase) -> RevealStrip:
	var made := RevealStrip.new()
	made.name = "RevealStrip"
	made._db = db
	return made


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	_repaint()


## Put a card on the table. `is_enemy` says whose it is.
func show_card(card: PlayerData, is_enemy: bool) -> void:
	if is_enemy:
		_theirs = card
	else:
		_mine = card
	_repaint()


## The tier is settled — take both cards off the table.
func clear() -> void:
	_theirs = null
	_mine = null
	_repaint()


func has_anything() -> bool:
	return _theirs != null or _mine != null


# =============================================================
#  DRAWING IT
# =============================================================

func _build() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override("panel", MenuSupport.panel_style(
		Color(0.06, 0.07, 0.10, 0.92), MenuSupport.COLOUR_ACCENT))
	add_child(_panel)

	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right"]:
		pad.add_theme_constant_override(side, 18)
	for side in ["margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 10)
	_panel.add_child(pad)

	_row = HBoxContainer.new()
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", 40)
	pad.add_child(_row)


func _repaint() -> void:
	if _row == null:
		return
	for child in _row.get_children():
		child.queue_free()

	visible = has_anything()
	if not visible:
		return

	if _theirs != null:
		_row.add_child(_side_block(_theirs, true))
	if _theirs != null and _mine != null:
		var bar := ColorRect.new()
		bar.color = MenuSupport.COLOUR_TEXT_DIM
		bar.custom_minimum_size = Vector2(2, 0)
		bar.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_row.add_child(bar)
	if _mine != null:
		_row.add_child(_side_block(_mine, false))


func _side_block(card: PlayerData, is_enemy: bool) -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	column.custom_minimum_size = Vector2(380, 0)

	var who := Label.new()
	who.text = "THEY PLAYED IT FACE UP" if is_enemy else "YOU PLAYED IT FACE UP"
	who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	who.add_theme_font_size_override("font_size", 12)
	who.add_theme_color_override("font_color",
		Color(0.92, 0.55, 0.45) if is_enemy else MenuSupport.COLOUR_ACCENT)
	column.add_child(who)

	var named := Label.new()
	named.text = "%s   ·   Tier %s   ·   P: %d   D: %d" % [
		NamePlate.short_name(card), card.get_tier_clean(),
		card.get_attack_power(), card.get_defense_power()]
	named.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	named.add_theme_font_size_override("font_size", 15)
	column.add_child(named)

	# WHAT IT DOES, in the same words the team sheet and the team window use,
	# out of Abilities.csv — so a new ability explains itself here too.
	var said := false
	for pair in [["Attack", card.active_attack_ability()],
			["Defend", card.active_defend_ability()]]:
		var line := _ability_line(String(pair[0]), String(pair[1]))
		if line != null:
			column.add_child(line)
			said = true
	if not said:
		column.add_child(_quiet("No abilities. What you see is what it is worth."))
	return column


func _ability_line(side: String, ability_id: String) -> Label:
	var clean := ability_id.strip_edges()
	if clean == "" or _db == null:
		return null
	var ability: AbilityData = _db.abilities.get(clean.to_lower())
	if ability == null:
		return null
	var line := Label.new()
	line.text = "%s — %s. %s" % [side, ability.display_name, ability.plain()]
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.add_theme_font_size_override("font_size", 12)
	line.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	return line


func _quiet(text: String) -> Label:
	var made := Label.new()
	made.text = text
	made.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	made.add_theme_font_size_override("font_size", 12)
	made.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	return made
