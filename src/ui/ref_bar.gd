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
#  ============ THE DRAWN CARD BOX (24 Oct 2026) ============
#
#  Anthony's sketch, "Yes I love it": per side a wide beer mat box (the
#  Emblem box's cream panel), the segments inside it in a dark wooden slot,
#  a yellow card tilted out of the top on the left and a red card on the
#  right, each with how many of it that side has been shown. A card not yet
#  shown is faded. Tuning.csv ref_bar_look drawn | glass (the old dark glass),
#  ref_box_size, ref_box_bottom, ref_box_scale. Cards: tools/make_ref_cards.py.
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
var _boxes := {}     ## side -> the drawn card box (drawn look only)
var _cards := {}     ## side -> [yellow card, red card] (drawn look only)
var _drawn := false

const CARD_ART := "res://assets/ui/referee/"
const INK := Color(0.1, 0.067, 0.04)


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
	_drawn = db == null or db.tune_text("ref_bar_look", "drawn").strip_edges().to_lower() != "glass"
	if _drawn:
		_build_drawn()
		return
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var up := 96.0
	if db != null:
		up = db.tune_float("ref_bar_bottom", 96.0)
	offset_top = -up - 64.0
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
		# ROUND AB: "the text is not legible - a no-border dark see-through
		# background". Each side sits on its own dark glass, no edge.
		var glass := PanelContainer.new()
		var back := StyleBoxFlat.new()
		back.bg_color = Color(0.02, 0.03, 0.05, db.tune_float("ref_bar_glass", 0.62) if db != null else 0.62)
		back.set_corner_radius_all(6)
		back.content_margin_left = 12.0
		back.content_margin_right = 12.0
		back.content_margin_top = 6.0
		back.content_margin_bottom = 6.0
		glass.add_theme_stylebox_override("panel", back)
		glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(glass)
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 4)
		column.alignment = BoxContainer.ALIGNMENT_CENTER
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		glass.add_child(column)

		var pips := HBoxContainer.new()
		pips.add_theme_constant_override("separation", 3)
		pips.alignment = BoxContainer.ALIGNMENT_CENTER
		pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(pips)
		_rows[side_is_enemy] = pips

		var says := Label.new()
		says.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		says.add_theme_font_size_override("font_size", db.tune_int("ref_bar_text_size", 15) if db != null else 15)
		says.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT)
		says.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(says)
		_labels[side_is_enemy] = says


## ROUND AN: what the Head Coach points at (MatchTalk.csv Highlight
## referee / referee:you / referee:them) - one side's dark glass, or both.
func spots(which: String) -> Array:
	var out: Array = []
	for side_is_enemy in [false, true]:
		if which == "you" and side_is_enemy:
			continue
		if which == "them" and not side_is_enemy:
			continue
		if _drawn:
			if _boxes.has(side_is_enemy):
				out.append(_boxes[side_is_enemy])
			continue
		var pips := _rows.get(side_is_enemy) as Control
		if pips != null and pips.get_parent() != null:
			out.append(pips.get_parent().get_parent())
	return out


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

		if _drawn:
			_fill_drawn(side_is_enemy, pips, many, lit)
		for i in (0 if _drawn else many):
			var cell := ColorRect.new()
			cell.custom_minimum_size = Vector2(wide, 11.0)
			cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell.color = _colour_for(i, many, i < lit)
			pips.add_child(cell)

		# ---- the cards already shown, after the segments ----
		for i in (0 if _drawn else int(yellows[side_is_enemy])):
			pips.add_child(_card_chip(Color(0.95, 0.80, 0.18)))
		for i in (0 if _drawn else int(reds[side_is_enemy])):
			pips.add_child(_card_chip(Color(0.80, 0.16, 0.16)))

		var who := "THEM" if side_is_enemy else "YOU"
		if _drawn:
			(_labels[side_is_enemy] as Label).text = "%s:  %s" % [
				who, Referee.reading(side_is_enemy, int(yellows[side_is_enemy]), db)]
			(_labels[side_is_enemy] as Label).add_theme_color_override("font_color",
				Color(0.78, 0.16, 0.16) if bool(bits["full"]) else INK)
			_shrink_to_fit(_labels[side_is_enemy] as Label)
			continue
		(_labels[side_is_enemy] as Label).text = "%s  ·  %s" % [
			who, Referee.reading(side_is_enemy, int(yellows[side_is_enemy]), db)]
		(_labels[side_is_enemy] as Label).add_theme_color_override("font_color",
			MenuSupport.COLOUR_ATTACK if bool(bits["full"]) else MenuSupport.COLOUR_TEXT)

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


# =============================================================
#  THE DRAWN CARD BOX
# =============================================================

func _build_drawn() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box_size := _pair("ref_box_size", Vector2(372, 112))
	var grow := db.tune_float("ref_box_scale", 1.0) if db != null else 1.0
	var up := db.tune_float("ref_box_bottom", 40.0) if db != null else 40.0
	var lift := 64.0      # how far the cards stand out of the top
	offset_top = -up - (box_size.y + lift) * grow
	offset_bottom = -up

	var line := HBoxContainer.new()
	line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	line.alignment = BoxContainer.ALIGNMENT_CENTER
	line.add_theme_constant_override("separation", int(db.tune_float("ref_box_gap", 16.0)) if db != null else 16)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(line)

	for side_is_enemy in [false, true]:
		# A holder the HBox lays out; the box inside it is scaled.
		var holder := Control.new()
		holder.custom_minimum_size = Vector2(box_size.x, box_size.y + lift) * grow
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(holder)
		var box := Control.new()
		box.size = Vector2(box_size.x, box_size.y + lift)
		box.scale = Vector2(grow, grow)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(box)
		_boxes[side_is_enemy] = holder

		# The cards first, so the box covers their bottoms.
		var pair: Array = []
		for which in ["yellow", "red"]:
			var card := _drawn_card(which)
			var x := box_size.x * (0.30 if which == "yellow" else 0.70)
			card.position = Vector2(x, lift - 8.0) - card.size / 2.0
			card.rotation_degrees = -16.0 if which == "yellow" else 16.0
			box.add_child(card)
			pair.append(card)
		_cards[side_is_enemy] = pair

		var panel := InventoryScreen._mat(box_size, 60, 0.55)
		panel.position = Vector2(0, lift)
		box.add_child(panel)

		# The counter: a dark wooden slot, the segments inside it.
		var slot := Panel.new()
		var wood := StyleBoxFlat.new()
		wood.bg_color = Color8(92, 58, 30)
		wood.border_color = INK
		wood.set_border_width_all(5)
		wood.set_corner_radius_all(10)
		slot.add_theme_stylebox_override("panel", wood)
		slot.position = Vector2(32, lift + 22)
		slot.size = Vector2(box_size.x - 64, 36)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(slot)
		var pips := HBoxContainer.new()
		pips.position = Vector2(38, lift + 28)
		pips.size = Vector2(box_size.x - 76, 24)
		pips.add_theme_constant_override("separation", 6)
		pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(pips)
		_rows[side_is_enemy] = pips

		var says := Label.new()
		says.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		says.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		says.position = Vector2(20, lift + 64)
		says.size = Vector2(box_size.x - 40, 34)
		says.clip_text = true
		# Ink on cardboard: no see-through plate behind it (TextBackdrop).
		says.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		says.add_theme_font_size_override("font_size", db.tune_int("ref_box_text_size", 20) if db != null else 20)
		says.add_theme_color_override("font_color", INK)
		says.add_theme_constant_override("outline_size", 0)
		says.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
		says.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(says)
		_labels[side_is_enemy] = says


## One referee card: the drawn card and its count on top.
func _drawn_card(which: String) -> Control:
	var card := TextureRect.new()
	card.texture = load(CARD_ART + "card_%s.png" % which) as Texture2D
	card.size = card.texture.get_size() if card.texture != null else Vector2(94, 124)
	card.pivot_offset = card.size / 2.0
	card.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The count: white with a thick ink edge, like the mock-up. The comic
	# font is a picture font with no outline of its own, so the edge is eight
	# ink copies round it.
	var count := Control.new()
	count.name = "Count"
	count.position = Vector2(0, 8)
	count.size = Vector2(card.size.x, 56)
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(count)
	var edge := 3.0
	var offsets := [Vector2(-edge, 0), Vector2(edge, 0), Vector2(0, -edge), Vector2(0, edge),
		Vector2(-edge, -edge), Vector2(edge, -edge), Vector2(-edge, edge), Vector2(edge, edge), Vector2.ZERO]
	for at in offsets:
		var digit := Label.new()
		digit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		digit.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		digit.position = at
		digit.size = count.size
		digit.add_theme_font_size_override("font_size", db.tune_int("ref_box_count_size", 40) if db != null else 40)
		digit.add_theme_color_override("font_color", Color.WHITE if at == Vector2.ZERO else INK)
		digit.add_theme_constant_override("outline_size", 0)
		digit.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
		digit.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		digit.mouse_filter = Control.MOUSE_FILTER_IGNORE
		count.add_child(digit)
	card.set_meta("which", which)
	return card


func _fill_drawn(side_is_enemy: bool, pips: HBoxContainer, many: int, lit: int) -> void:
	var room := pips.size.x - 6.0 * float(maxi(0, many - 1))
	var wide := room / float(maxi(1, many))
	for i in many:
		var cell := Panel.new()
		var look := StyleBoxFlat.new()
		look.bg_color = _drawn_colour(i, many) if i < lit else Color8(214, 200, 172)
		look.border_color = INK
		look.set_border_width_all(3)
		look.set_corner_radius_all(4)
		cell.add_theme_stylebox_override("panel", look)
		cell.custom_minimum_size = Vector2(wide, 24)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if i < lit:
			var shine := ColorRect.new()
			shine.color = Color8(255, 245, 210)
			shine.position = Vector2(6, 4)
			shine.size = Vector2(maxf(4.0, wide - 16.0), 3)
			shine.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell.add_child(shine)
		pips.add_child(cell)
	var shown := [int(yellows[side_is_enemy]), int(reds[side_is_enemy])]
	var pair: Array = _cards.get(side_is_enemy, [])
	for k in pair.size():
		var card := pair[k] as TextureRect
		var which := String(card.get_meta("which"))
		var file := CARD_ART + "card_%s%s.png" % [which, "" if shown[k] > 0 else "_none"]
		if ResourceLoader.exists(file):
			card.texture = load(file) as Texture2D
		for digit in card.get_node("Count").get_children():
			(digit as Label).text = str(shown[k])


## Long readings ("booked already - 80% to be caught") get smaller words
## instead of being cut off.
func _shrink_to_fit(says: Label) -> void:
	var font := says.get_theme_font("font")
	var big := db.tune_int("ref_box_text_size", 20) if db != null else 20
	var room := says.size.x
	var fits := big
	while fits > 11 and font != null and font.get_string_size(says.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fits).x > room:
		fits -= 1
	says.add_theme_font_size_override("font_size", fits)


## Yellow through orange to red, left to right, like the drawn mock-up.
func _drawn_colour(index: int, many: int) -> Color:
	var how_far := 0.0 if many <= 1 else float(index) / float(many - 1)
	return Color8(247, 200, 38).lerp(Color8(206, 38, 38), how_far)


func _pair(key: String, fallback: Vector2) -> Vector2:
	if db == null:
		return fallback
	var parts := db.tune_text(key, "").split(" ", false)
	if parts.size() == 2:
		return Vector2(float(parts[0]), float(parts[1]))
	return fallback
