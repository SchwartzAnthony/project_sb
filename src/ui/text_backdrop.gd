class_name TextBackdrop
extends RefCounted

# =============================================================
#  A SEE-THROUGH BLACK BACKDROP BEHIND EVERY WORD IN THE MATCH
#
#  ROUND AN (Anthony, 6 Oct): with the village round the pitch, the score,
#  the clock, the keeper's odds and the zone map's words were sitting on
#  roofs, fans and stripes of grass, and could not be read. So every word
#  in the match now sits on a dark see-through plate.
#
#  ONE RULE, NOT ONE FIX PER LABEL. main_scene calls watch(self) once; every
#  Label and RichTextLabel already in the match, and every one added later
#  (a keeper's plate, a goal banner), gets the plate. Words that already
#  have a backdrop are left alone: anything inside a Button, a Panel, a
#  PanelContainer or a player's NamePlate (it draws its own), and any label
#  that already sets its own "normal" box.
#
#  Words painted straight onto the grass (the zone map) use draw_behind().
#
#  Tuning.csv:  text_backdrop_alpha   how dark (0 = off)
#               text_backdrop_pad     how far the plate reaches past the words
# =============================================================

const DEFAULT_ALPHA := 0.55
const DEFAULT_PAD := 6.0


static func alpha() -> float:
	var db := CardDatabase.get_db()
	if db == null:
		return DEFAULT_ALPHA
	return clampf(db.tune_float("text_backdrop_alpha", DEFAULT_ALPHA), 0.0, 1.0)


static func pad() -> float:
	var db := CardDatabase.get_db()
	if db == null:
		return DEFAULT_PAD
	return maxf(0.0, db.tune_float("text_backdrop_pad", DEFAULT_PAD))


static func plate() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, alpha())
	box.set_corner_radius_all(4)
	var p := pad()
	box.content_margin_left = p
	box.content_margin_right = p
	box.content_margin_top = p * 0.5
	box.content_margin_bottom = p * 0.5
	return box


## Give every word under `root` a plate, now and whenever one is added.
static func watch(root: Node) -> void:
	if alpha() <= 0.0:
		return
	for node in root.find_children("*", "", true, false):
		give(node)
	var tree := root.get_tree()
	if tree == null:
		return
	var on_added := func(node: Node) -> void:
		if is_instance_valid(root) and root.is_ancestor_of(node):
			# Deferred: the node is added before its maker sets it up.
			give.call_deferred(node)
	tree.node_added.connect(on_added)
	# Let go when the match closes, or every match would leave one behind.
	root.tree_exiting.connect(func() -> void:
		if tree.node_added.is_connected(on_added):
			tree.node_added.disconnect(on_added), CONNECT_ONE_SHOT)


## One label. Safe to call on anything; it ignores what is not a label or
## already has a backdrop. Takes a Variant on purpose: it is called a frame
## late, and a node freed in between must be skipped, not crash the call.
static func give(node: Variant) -> void:
	if node == null or not is_instance_valid(node):
		return
	if not (node is Label or node is RichTextLabel):
		return
	var control := node as Control
	if control.has_theme_stylebox_override("normal") or control.has_meta("text_backdrop"):
		return
	if _has_own_backdrop(control):
		return
	var box := plate()
	control.set_meta("text_backdrop", box)
	_sync(control)
	# A label with no words yet (a note that fills in later) shows no empty
	# plate: the plate comes and goes with the words.
	control.draw.connect(_sync.bind(control))


static func _sync(control: Control) -> void:
	if not is_instance_valid(control) or not control.has_meta("text_backdrop"):
		return
	var words := String(control.get("text")).strip_edges()
	var showing := control.has_theme_stylebox_override("normal")
	if words == "" and showing:
		control.remove_theme_stylebox_override("normal")
	elif words != "" and not showing:
		control.add_theme_stylebox_override("normal", control.get_meta("text_backdrop"))


static func _has_own_backdrop(control: Control) -> bool:
	var up := control.get_parent()
	while up != null:
		if up is Button or up is Panel or up is PanelContainer or up is NamePlate:
			return true
		up = up.get_parent()
	return false


## For words drawn with draw_string(): the same plate, behind the text.
## `at` is the baseline start, exactly as draw_string() takes it.
static func draw_behind(canvas: CanvasItem, font: Font, at: Vector2, text: String,
		width: float, size: int) -> void:
	var a := alpha()
	if a <= 0.0 or font == null or text == "":
		return
	var room := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, width, size)
	var p := pad()
	var top := at.y - font.get_ascent(size)
	canvas.draw_rect(Rect2(at.x - p, top - p * 0.5, room.x + p * 2.0, room.y + p),
		Color(0, 0, 0, a), true)
