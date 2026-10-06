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

static var _scale: float = 1.0


static func current() -> float:
	return _scale


## Set the size and rescale every bit of text already on screen.
static func apply(tree: SceneTree, scale: float) -> void:
	_scale = clampf(scale, 0.5, 2.0)
	if tree == null or tree.root == null:
		return
	# Nothing to watch for until someone actually asks for a different size.
	if is_equal_approx(_scale, 1.0) and not tree.node_added.is_connected(_on_added):
		return
	if not tree.node_added.is_connected(_on_added):
		tree.node_added.connect(_on_added)
	_walk(tree.root)


static func _on_added(node: Node) -> void:
	# Deferred: a screen usually sets a label's size just after adding it.
	_fit.call_deferred(node)


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

	if not control.has_meta(BASE_META):
		# Nothing to remember for a node that has never been scaled and is
		# meant to stay at its normal size.
		if is_equal_approx(_scale, 1.0):
			return
		control.set_meta(BASE_META, control.get_theme_font_size(prop))
	var base := int(control.get_meta(BASE_META))
	control.add_theme_font_size_override(prop, maxi(1, roundi(base * _scale)))
