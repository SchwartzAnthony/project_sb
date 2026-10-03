class_name CardStatsPanel
extends PanelContainer

# =============================================================
#  THE HOVER PANEL — everything about a card, before you commit
#
#  Hold the mouse over a card during a PLAY MAKER and this appears above
#  the row: attack, defence, tier, class, star, brew, and both abilities
#  written out in plain English. Move away and it goes.
#
#  WHY IT EXISTS
#  The cards showed a picture and a name and nothing else, so you were
#  choosing between four faces with no idea which was stronger — and then
#  the duel cut-away showed a number you had never seen before. Nothing was
#  wrong with the number; you simply had no way to know it in advance.
#
#  It reads the card and nothing else. No new data, no CSV to keep in step.
#  It is built in code rather than from a .tscn because it is a floating
#  overlay that follows the mouse, and there is only one of it.
# =============================================================

const WIDTH := 460.0

var db: CardDatabase

var _title: Label
var _line: Label
var _power: Label
var _attack: Label
var _defend: Label
var _footer: Label


static func make(database: CardDatabase) -> CardStatsPanel:
	var panel := CardStatsPanel.new()
	panel.name = "CardStatsPanel"
	panel.db = database
	return panel


func _ready() -> void:
	# It must never eat a click meant for the card underneath it.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(WIDTH, 0)
	z_index = 50
	hide()

	add_theme_stylebox_override("panel",
		MenuSupport.panel_style(Color(0.10, 0.11, 0.15, 0.97), MenuSupport.COLOUR_ACCENT))

	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right"]:
		pad.add_theme_constant_override(side, 14)
	for side2 in ["margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side2, 11)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(pad)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(box)

	_title = _label(box, 19, MenuSupport.COLOUR_ACCENT)
	_line = _label(box, 12, MenuSupport.COLOUR_TEXT_DIM)
	_power = _label(box, 26, MenuSupport.COLOUR_TEXT)
	_attack = _label(box, 13, MenuSupport.COLOUR_TEXT)
	_defend = _label(box, 13, MenuSupport.COLOUR_TEXT)
	_footer = _label(box, 11, MenuSupport.COLOUR_TEXT_DIM)


func _label(parent: Node, size: int, colour: Color) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


# =============================================================
#  SHOWING A CARD
# =============================================================

func show_card(card: PlayerData, near: Vector2) -> void:
	if card == null:
		hide()
		return

	# Back to the normal width; _place widens it again if it does not fit.
	custom_minimum_size = Vector2(WIDTH, 0)
	reset_size()
	_title.text = card.player_name

	# active_unit_type() rather than unit_type: a brewed card COUNTS AS its
	# new class, and that is what everything in combat reads, so that is what
	# this has to say or the panel would quietly disagree with the fight.
	var bits: Array[String] = ["Tier %s" % card.get_tier_clean(), card.active_unit_type()]
	if card.is_star():
		bits.append("STAR")
	if card.is_brewed():
		bits.append("brewed: %s" % card.brew_id)
	_line.text = "   ·   ".join(bits)

	_power.text = "%d attack     %d defence" % [
		card.get_attack_power(), card.get_defense_power()]

	# ============ A STAR HAS ONE ABILITY, NOT TWO ============
	#
	# "They only have one ability, and when you hover you get to see the
	# Ultimate." So a Star gets one line rather than an ATTACK line and a
	# DEFEND line that say the same sentence twice, and the second line is
	# spent on the thing worth reading: the other side of the card.
	if card.is_star() and card.has_ultimate():
		_attack.text = "ABILITY   " + _ability_words(card.active_attack_ability(), card.attack_text)
		_defend.text = _ultimate_words(card)
	else:
		_attack.text = "ATTACK   " + _ability_words(card.active_attack_ability(), card.attack_text)
		_defend.text = "DEFEND   " + _ability_words(card.active_defend_ability(), card.defend_text)

	var band := db.tier_band_text(card.get_tier_clean()) if db != null else ""
	# ---- and what it would take to turn it over ----
	var footer := band
	if card.is_star() and card.has_ultimate():
		var badge := EmblemBook.for_star(card)
		if badge != null:
			var need := badge.condition if badge.condition != "" \
				else DialogueGrammar.describe(badge.turns_on)
			var along := EmblemBook.progress(badge, GameState.fetch(get_tree()))
			var how := ""
			if int(along["need"]) > 0:
				how = "   (%d of %d)" % [int(along["have"]), int(along["need"])]
			footer = "%s ·  %s%s" % [badge.id.to_upper(), need, how]
	_footer.text = footer
	_footer.visible = footer != ""

	show()
	_place(near)


## The ability in plain English, or an honest "none".
##
## Base cards have NO abilities — that is the design, not a fault — so this
## says so out loud rather than leaving a blank line that reads like
## something failed to load.
func _ability_words(ability_id: String, printed_text: String) -> String:
	var id_text := ability_id.strip_edges()
	if id_text == "":
		if printed_text.strip_edges() != "":
			return printed_text.strip_edges()
		return "none — plain card, decided on power alone"

	if db == null:
		return id_text
	# ROUND AB: the printed sentence first (it is the card), then what the
	# game will DO, in words. A cell may name several rows (C_Fritz_A1;A2).
	var said: PackedStringArray = PackedStringArray()
	for piece in id_text.split(";"):
		var ability := db.get_ability(String(piece).strip_edges())
		if ability == null:
			said.append("%s (no such row)" % String(piece).strip_edges())
		else:
			said.append(ability.plain())
	var printed := printed_text.strip_edges()
	if printed != "":
		return "%s\n      %s" % [printed, "  ".join(said)]
	return "  ".join(said)


## ROUND AB: sit BELOW the card (`near` is the bottom of it), never off the
## screen, and never over the referee's bar at the bottom.
func _place(near: Vector2) -> void:
	# The panel has to be laid out before its height is known, so this waits
	# one frame. Without it the first card you hover is placed using last
	# card's height and jumps.
	await get_tree().process_frame
	if not visible:
		return

	var screen := get_viewport_rect().size
	var box := size
	var keep_clear := db.tune_float("hover_panel_keep_bottom", 170.0) if db != null else 170.0
	# ROUND AB: too tall to fit between the card and the foul bars? Then it
	# goes WIDE instead (shorter), rather than sliding up over the card.
	var room := screen.y - keep_clear - (near.y + 12.0)
	if box.y > room:
		var wide := db.tune_float("hover_panel_wide_width", 900.0) if db != null else 900.0
		custom_minimum_size = Vector2(minf(wide, screen.x - 16.0), 0)
		reset_size()
		await get_tree().process_frame
		if not visible:
			return
		reset_size()
		box = size
	var at := Vector2(near.x - box.x * 0.5, near.y + 12.0)
	at.x = clampf(at.x, 8.0, maxf(screen.x - box.x - 8.0, 8.0))
	at.y = clampf(at.y, 8.0, maxf(screen.y - box.y - keep_clear, 8.0))
	position = at


## THE OTHER SIDE OF A STAR, on hover, whether or not it has turned over.
##
## Shown all the time on purpose. The point of the change is that a player can
## always read what they are playing toward — an Ultimate you only see once
## you have earned it is one you never aimed at.
func _ultimate_words(card: PlayerData) -> String:
	var up := EmblemBook.star_is_ultimate(card, GameState.fetch(get_tree()))
	var head := "★ ULTIMATE   " if up else "ULTIMATE (locked)   "
	var body := card.ultimate_text.strip_edges()
	if body == "":
		body = "written, but the Ultimate Side column is empty."
	return head + body
