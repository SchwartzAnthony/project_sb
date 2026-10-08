class_name TextScale
extends RefCounted

# =============================================================
#  TEXT SIZE  (round AN)
#
#  Settings > Colour > Text size. It used to be saved and never read, so the
#  buttons did nothing at all.
#
#  Every label, button and text box in the game keeps the size its screen
#  gave it, and this multiplies that by the setting: 1.3 makes every bit of
#  writing 30% bigger, on every screen, without any screen knowing. It
#  watches for new text as screens are built (the tree's node_added signal),
#  so a screen added next year is covered too.
#
#  At 1.0 it does nothing and leaves every node exactly as it was built.
# =============================================================

## The size a node was built with, so changing the setting twice scales from
## the original rather than compounding.
const BASE_META := "text_scale_base"
## A label that already sized itself to fit its box (a banner title, a
## button's words) sets this meta, and the smallest size leaves it alone.
const FITTED_META := "text_fitted"

static var _scale: float = 1.0


## ROUND AN: no word in the game is drawn smaller than this
## (Tuning.csv text_min_size). Anthony: "hard to read" on every screen.
static func min_size() -> int:
	var db := CardDatabase.get_db()
	if db == null:
		return 14
	return int(db.tune_float("text_min_size", 14.0))


## Start watching every new bit of text, so the smallest size holds on every
## screen. Called by ThemeBook.dress(); safe to call again.
static func watch(tree: SceneTree) -> void:
	if tree == null or tree.root == null:
		return
	if not tree.node_added.is_connected(_on_added):
		tree.node_added.connect(_on_added)
		_walk(tree.root)


static func current() -> float:
	return _scale


## Set the size and rescale every bit of text already on screen.
static func apply(tree: SceneTree, scale: float) -> void:
	_scale = clampf(scale, 0.5, 2.0)
	if tree == null or tree.root == null:
		return
	# Nothing to watch for until someone actually asks for a different size.
	if not tree.node_added.is_connected(_on_added):
		tree.node_added.connect(_on_added)
	_walk(tree.root)


static func _on_added(node: Node) -> void:
	# Deferred: a screen usually sets a label's size just after adding it.
	# By its id, because a node freed in that same frame (a window rebuilt,
	# a dialog closed) cannot even be handed to a typed _fit(): the check
	# has to happen before the call.
	_fit_id.call_deferred(node.get_instance_id())


static func _fit_id(id: int) -> void:
	var node := instance_from_id(id) as Node
	if node != null:
		_fit(node)


static func _walk(node: Node) -> void:
	_fit(node)
	for child in node.get_children():
		_walk(child)


static func _fit(node: Node) -> void:
	if not is_instance_valid(node) or not (node is Control):
		return
	var prop := ""
	if node is Label or node is Button or node is LineEdit or node is TextEdit:
		prop = "font_size"
	elif node is RichTextLabel:
		prop = "normal_font_size"
	else:
		return
	var control := node as Control
	if not control.is_inside_tree():
		return

	# Words that wrap inside a designed box (an ability text in a narrow
	# column) keep their size: forcing them bigger makes the box run over.
	# They still get the smooth font and Settings > Text size.
	var wraps := (control is Label and (control as Label).autowrap_mode != TextServer.AUTOWRAP_OFF) \
		or control is RichTextLabel
	var floor_size := 1 if control.has_meta(FITTED_META) or wraps else min_size()
	if not control.has_meta(BASE_META):
		# Nothing to remember for a node that is already big enough and is
		# meant to stay at its normal size.
		var built := control.get_theme_font_size(prop)
		if is_equal_approx(_scale, 1.0) and built >= floor_size:
			return
		control.set_meta(BASE_META, built)
	var base := int(control.get_meta(BASE_META))
	control.add_theme_font_size_override(prop, maxi(floor_size, roundi(base * _scale)))
	# A label that cuts its words off at the edge of a fixed box (a name
	# plate, a combo tile) only grows as far as the box allows, so making
	# it bigger never hides more of it. Never smaller than it was built.
	if control is Label and ((control as Label).clip_text \
			or (control as Label).text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING):
		if not control.resized.is_connected(_keep_inside.bind(control)):
			control.resized.connect(_keep_inside.bind(control))
		_keep_inside(control)


static func _keep_inside(label: Label) -> void:
	if not is_instance_valid(label) or label.size.x < 2.0 or not label.has_meta(BASE_META):
		return
	var font := label.get_theme_font("font")
	if font == null:
		return
	var base := int(label.get_meta(BASE_META))
	var want := maxi(min_size(), roundi(base * _scale))
	var lowest := mini(want, roundi(base * _scale))
	var font_size := want
	while font_size > lowest and font.get_string_size(label.text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > label.size.x:
		font_size -= 1
	if label.get_theme_font_size("font_size") != font_size:
		label.add_theme_font_size_override("font_size", font_size)
