class_name MatchTracker
extends CanvasLayer

# =============================================================
#  THE MATCH TRACKER  (round Z, phase C2)
#
#  ============ WHAT YOU ASKED FOR ============
#
#  Ruling F3: "add a window that keeps track of how many more units they can
#  play that will get a buff. So if the next three fire get +1 power during
#  combat, show x fire get +1 power during combat as the player plays more of
#  the fire."
#
#  And phase C2 brought things a side HOLDS that nobody could see: the Ore
#  pool (ruling R12), the tokens you control, Belphegor's victory counters.
#  They all live here, one small panel down the left of the pitch:
#
#      YOU                         THEM
#      Ore 4   Tokens 1            Ore 0
#      WAITING
#        2 x next swan ally: 1 off their keeper
#        1 x next fire ally in the next tier: +1 burn counter
#
#  ============ IT OWNS NOTHING ============
#
#  Every number is read from the ability engine each refresh - the same rule
#  as the emblem bar. A side with nothing to show shows nothing, so a team
#  with no Ore and nothing waiting does not get a panel at all.
#
#  `match_tracker_on` FALSE in Tuning.csv hides it.
# =============================================================

var engine: AbilityEngine = null

var _box: VBoxContainer = null
var _frame: PanelContainer = null


static func open(on: Node, abilities: AbilityEngine) -> MatchTracker:
	var db := CardDatabase.get_db()
	if db != null and not db.tune_bool("match_tracker_on", true):
		return null
	var made := MatchTracker.new()
	made.name = "MatchTracker"
	# Round AA: under the duel and shot windows, like the emblem bar.
	made.layer = db.tune_int("emblem_bar_layer", 18) if db != null else 18
	made.engine = abilities
	on.add_child(made)
	made.refresh()
	return made


func _ready() -> void:
	var db := CardDatabase.get_db()
	var top := 126.0
	if db != null:
		top = db.tune_float("match_tracker_top", 126.0)
	_frame = PanelContainer.new()
	_frame.add_theme_stylebox_override("panel",
		MenuSupport.styled("panel", "", MenuSupport.COLOUR_PANEL, MenuSupport.COLOUR_TEXT_DIM))
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.position = Vector2(16.0, top)
	_frame.custom_minimum_size = Vector2(270.0, 0.0)
	add_child(_frame)
	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 8)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(pad)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 2)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(_box)


## Read everything again. main_scene calls it after every duel and draft pick.
func refresh() -> void:
	if _box == null or engine == null:
		return
	for child in _box.get_children():
		child.queue_free()
	var lines := 0
	for side in [false, true]:
		var bits: Array[String] = []
		var ore := engine.pool(side, "ore")
		if ore > 0:
			bits.append("Ore %d" % ore)
		var tokens := engine.token_count(side)
		if tokens > 0:
			bits.append("Tokens %d" % tokens)
		var wins := engine.pool(side, "victory")
		if wins > 0:
			bits.append("Victory %d" % wins)
		var waiting := engine.pending_lines(side)
		if bits.is_empty() and waiting.is_empty():
			continue
		_box.add_child(_line("YOU" if not side else "THEM", 14,
			MenuSupport.COLOUR_ATTACK if not side else MenuSupport.COLOUR_DEFEND))
		if not bits.is_empty():
			_box.add_child(_line("   ".join(PackedStringArray(bits)), 13, MenuSupport.COLOUR_TEXT))
		if not waiting.is_empty():
			_box.add_child(_line("WAITING", 11, MenuSupport.COLOUR_TEXT_DIM))
			for w in waiting:
				_box.add_child(_line("  " + w, 12, MenuSupport.COLOUR_TEXT))
		lines += 1
	_frame.visible = lines > 0


func _line(words: String, size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = words
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(254.0, 0)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
