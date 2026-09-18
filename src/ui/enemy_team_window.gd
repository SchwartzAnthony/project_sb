class_name EnemyTeamWindow
extends CanvasLayer

# =============================================================
#  ENEMY TEAM DATA — everything about the other side, in one window
#
#  Their whole squad, by tier: every unit, its power, and what its abilities
#  actually do. Stars are marked.
#
#  ============ WHY IT EXISTS ============
#
#  You are asked to draft one card per tier against a side you have never
#  seen. Without this the only way to learn what they do is to lose to them
#  and remember — which is a fine roguelike and a poor football game, and it
#  is not what the tier ladder is for. The ladder makes every legal team the
#  same total power on purpose, so the interesting question is what their
#  players DO, and that question deserves an answer you can go and read.
#
#  ============ IT OPENS FROM THREE PLACES ============
#
#      the team shelf   before you pick a side, against the next fixture
#      the match        a button on the HUD, any time
#      the team sheet   the three Stars' abilities, before kick-off
#
#  All three call open(). It does not know or care which one it is.
# =============================================================

var db: CardDatabase
var title := "ENEMY TEAM"
var subtitle := ""
## The squad to show. Anything that is not a PlayerData is skipped.
var squad: Array[PlayerData] = []
## Which of them are the Stars they will actually field, marked on the list.
var stars: Array[PlayerData] = []


## Build it and put it up. `cards` is the opposition squad; `who` is their
## name, for the title.
static func open(on: Node, database: CardDatabase, who: String,
		cards: Array[PlayerData], their_stars: Array[PlayerData] = [],
		under_title: String = "") -> EnemyTeamWindow:
	var made := EnemyTeamWindow.new()
	made.name = "EnemyTeamWindow"
	made.db = database
	made.title = "%s — TEAM DATA" % who.to_upper() if who != "" else "ENEMY TEAM DATA"
	made.subtitle = under_title
	made.squad = cards.duplicate()
	made.stars = their_stars.duplicate()
	on.add_child(made)
	return made


func _ready() -> void:
	layer = 72
	_build()


func close() -> void:
	queue_free()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()


# =============================================================
#  BUILDING IT
# =============================================================

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.06, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	# TALL ON PURPOSE. A squad is a dozen cards with two abilities each, and a
	# short box turns that into a scroll bar you have to discover.
	panel.offset_left = -470.0
	panel.offset_right = 470.0
	panel.offset_top = -400.0
	panel.offset_bottom = 400.0
	panel.add_theme_stylebox_override("panel", MenuSupport.panel_style(
		MenuSupport.COLOUR_PANEL, MenuSupport.COLOUR_ACCENT))
	dim.add_child(panel)

	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right"]:
		pad.add_theme_constant_override(side, 22)
	for side in ["margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 16)
	panel.add_child(pad)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	pad.add_child(column)

	column.add_child(MenuSupport.heading(title, 24, MenuSupport.COLOUR_ACCENT))

	var under := Label.new()
	under.text = subtitle if subtitle != "" \
		else "Everything they can put on the pitch. Escape closes this."
	under.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	under.add_theme_font_size_override("font_size", 13)
	under.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	column.add_child(under)

	var scroller := ScrollContainer.new()
	scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroller)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroller.add_child(list)

	if squad.is_empty():
		list.add_child(_quiet("Nobody is named yet. The opposition is chosen at kick-off in a friendly; a league fixture names them in Season.csv."))
	else:
		# BY TIER, in ladder order, because that is the order you draft in.
		for tier in TierLadder.TIERS:
			var of_tier: Array[PlayerData] = []
			for card in squad:
				if card != null and card.get_tier_clean() == tier:
					of_tier.append(card)
			if of_tier.is_empty():
				continue
			of_tier.sort_custom(func(a: PlayerData, b: PlayerData) -> bool:
				return a.get_attack_power() < b.get_attack_power())
			list.add_child(_tier_heading(tier))
			for card in of_tier:
				list.add_child(_card_line(card))

	var close_button := MenuSupport.icon_button("close|✕",
		Loc.text("close", "Close"), Vector2(220, 46))
	close_button.pressed.connect(close)
	var centre := CenterContainer.new()
	centre.add_child(close_button)
	column.add_child(centre)


func _tier_heading(tier: String) -> Control:
	var line := Label.new()
	line.text = "TIER %s" % tier
	line.add_theme_font_size_override("font_size", 15)
	line.add_theme_color_override("font_color",
		MenuSupport.colour_for_tier(tier).lightened(0.4))
	return line


## One player: who they are, what they are worth, and what they do.
func _card_line(card: PlayerData) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", MenuSupport.panel_style(
		MenuSupport.COLOUR_BACKGROUND,
		MenuSupport.COLOUR_ACCENT if stars.has(card) else MenuSupport.COLOUR_TEXT_DIM))

	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right"]:
		pad.add_theme_constant_override(side, 10)
	for side in ["margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 6)
	panel.add_child(pad)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 1)
	pad.add_child(column)

	var head := Label.new()
	head.text = "%s%s   ·   P: %d   ·   D: %d" % [
		card.player_name, "  ★" if card.is_star() else "",
		card.get_attack_power(), card.get_defense_power()]
	head.add_theme_font_size_override("font_size", 14)
	column.add_child(head)

	# ============ WHAT THEY DO, IN WORDS ============
	#
	# Out of Abilities.csv through describe(), so a new ability explains
	# itself here the day it is written and nothing has to be kept in step.
	for pair in [["Attack", card.active_attack_ability()],
			["Defend", card.active_defend_ability()]]:
		var line := _ability_line(String(pair[0]), String(pair[1]))
		if line != null:
			column.add_child(line)

	if card.active_attack_ability().strip_edges() == "" \
			and card.active_defend_ability().strip_edges() == "":
		column.add_child(_quiet("No abilities. A plain card — what you see is what it is worth."))
	return panel


func _ability_line(side: String, ability_id: String) -> Control:
	var clean := ability_id.strip_edges()
	if clean == "" or db == null:
		return null
	var ability: AbilityData = db.abilities.get(clean.to_lower())
	var line := Label.new()
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.add_theme_font_size_override("font_size", 12)
	if ability == null:
		# A NAMED ABILITY THAT IS NOT IN Abilities.csv. Say so rather than
		# leaving a blank line — this is exactly the sort of typo that is
		# invisible in the game and obvious here.
		line.text = "%s: %s — no row in Abilities.csv" % [side, clean]
		line.add_theme_color_override("font_color", Color(0.90, 0.55, 0.45))
		return line
	line.text = "%s — %s. %s" % [side, ability.display_name, ability.plain()]
	line.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	return line


func _quiet(text: String) -> Label:
	var made := Label.new()
	made.text = text
	made.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	made.add_theme_font_size_override("font_size", 12)
	made.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	return made
