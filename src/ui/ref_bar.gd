class_name RefBar
extends Control

# =============================================================
#  THE REFEREE'S ATTENTION, ALONG THE BOTTOM
#
#  ============ WHAT YOU ASKED FOR ============
#
#  "Add a bar to the UI in the normal soccer mode (so not adventure) that
#   keeps track of 1-5 sections that fill up the yellow and red."
#
#  Two bars, one per side, drawn as SEGMENTS rather than as a smooth meter —
#  because the rule is counted, not measured. Four of five lit means "four",
#  and a player can read four at a glance from across a room in a way they
#  can never read 78%.
#
#  ============ WHAT EACH PART MEANS ============
#
#      an empty segment      nothing. He has not noticed you
#      a lit segment         +Caught Per Segment to being seen next time
#      every segment lit     the next foul is a card, near enough
#      a yellow card drawn   he is watching you whatever the bar says
#      a red card drawn      that man is off
#
#  The side's own tier colour is NOT used. The bar is the referee's and not
#  the team's, so it goes from quiet grey through the warm accent to red —
#  one gradient, read left to right, the same for both sides.
#
#  ============ LEAGUE ONLY ============
#
#  An Adventure fight has no referee, no fouls and no cards, so it never
#  draws one. That is not a switch — the bar is only ever created by
#  main_scene.gd, and adventure_scene.gd does not know this file exists.
# =============================================================

## Set these and call refresh().
var db: CardDatabase = null
## Yellow cards shown so far, per side. {false: 0, true: 0}
var yellows := {false: 0, true: 0}
var reds := {false: 0, true: 0}

var _rows := {}      ## side -> the HBoxContainer of segments
var _labels := {}    ## side -> the Label under it


static func open(on_node: Node, database: CardDatabase) -> RefBar:
	if database != null and not database.tune_bool("ref_bar", true):
		return null
	if not Referee.on(database):
		return null
	var made := RefBar.new()
	made.name = "RefBar"
	made.db = database
	on_node.add_child(made)
	made._build()
	made.refresh()
	return made


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var up := 96.0
	if db != null:
		up = db.tune_float("ref_bar_bottom", 96.0)
	offset_top = -up - 54.0
	offset_bottom = -up

	var line := HBoxContainer.new()
	line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	line.alignment = BoxContainer.ALIGNMENT_CENTER
	line.add_theme_constant_override("separation", 34)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(line)

	# YOURS ON THE LEFT, THEIRS ON THE RIGHT, always, whichever way the pitch
	# is facing — a bar that swaps sides is a bar nobody trusts.
	for side_is_enemy in [false, true]:
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 3)
		column.alignment = BoxContainer.ALIGNMENT_CENTER
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(column)

		var pips := HBoxContainer.new()
		pips.add_theme_constant_override("separation", 3)
		pips.alignment = BoxContainer.ALIGNMENT_CENTER
		pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(pips)
		_rows[side_is_enemy] = pips

		var says := Label.new()
		says.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		says.add_theme_font_size_override("font_size", 11)
		says.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
		says.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(says)
		_labels[side_is_enemy] = says


## Read it again. Cheap, and called at the end of every round.
func refresh() -> void:
	if db == null:
		return
	var ref := Referee.on_duty(db)
	var wide := db.tune_float("ref_bar_segment", 34.0)

	for side_is_enemy in [false, true]:
		var pips: HBoxContainer = _rows[side_is_enemy]
		for child in pips.get_children():
			child.queue_free()

		var bits := Referee.segments(side_is_enemy, db)
		var many := int(bits["of"])
		var lit := int(bits["lit"])

		for i in many:
			var cell := ColorRect.new()
			cell.custom_minimum_size = Vector2(wide, 11.0)
			cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell.color = _colour_for(i, many, i < lit)
			pips.add_child(cell)

		# ---- the cards already shown, after the segments ----
		for i in int(yellows[side_is_enemy]):
			pips.add_child(_card_chip(Color(0.95, 0.80, 0.18)))
		for i in int(reds[side_is_enemy]):
			pips.add_child(_card_chip(Color(0.80, 0.16, 0.16)))

		var who := "THEM" if side_is_enemy else "YOU"
		(_labels[side_is_enemy] as Label).text = "%s  ·  %s" % [
			who, Referee.reading(side_is_enemy, int(yellows[side_is_enemy]), db)]
		(_labels[side_is_enemy] as Label).add_theme_color_override("font_color",
			MenuSupport.COLOUR_ATTACK if bool(bits["full"]) else MenuSupport.COLOUR_TEXT_DIM)

	# The referee's name, once, so a player knows whose afternoon this is.
	var first: Label = _labels[false]
	first.tooltip_text = String(ref["name"])


## Quiet grey, through the accent, to red. ONE GRADIENT read left to right,
## so the last segment looks like the last segment before you have ever been
## booked by it.
func _colour_for(index: int, many: int, lit: bool) -> Color:
	if not lit:
		return MenuSupport.COLOUR_SLOT_EMPTY
	var how_far := 0.0 if many <= 1 else float(index) / float(many - 1)
	return MenuSupport.COLOUR_ACCENT.lerp(Color(0.80, 0.16, 0.16), how_far)


func _card_chip(colour: Color) -> Control:
	var chip := ColorRect.new()
	chip.custom_minimum_size = Vector2(9.0, 13.0)
	chip.color = colour
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return chip
