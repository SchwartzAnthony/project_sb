class_name BaseWindow
extends CanvasLayer

# =============================================================
#  A WINDOW OVER THE BASE — not a scene change
#
#  ============ WHAT YOU ASKED FOR ============
#
#  "Each of these should have a new window open (not a new whole scene cut
#   from the base) with each of the content presented that way."
#
#  So clicking the Brewery no longer takes the base away and puts a Brewery
#  in its place. The base stays where it is, dims, and the Brewery opens on
#  top of it. Close the window and you are already home — no loading, no
#  camera jump, and the building you just used is still under your cursor.
#
#  ============ HOW A SCREEN BECOMES A WINDOW ============
#
#  It does not get rewritten. The SAME scene file is instantiated inside the
#  frame, with one flag set on it first:
#
#      content.set_meta("windowed", true)
#
#  and every screen asks `MenuSupport.in_a_window(self)` in its _ready(). When
#  the answer is yes it skips three things and nothing else:
#
#      its own full-screen background   the window has one
#      its own "Back to the base"       the window has a ✕
#      MenuEscape.install()             the window handles Escape
#
#  That is the whole contract. It means every one of these screens still
#  works as a standalone scene — `goto:brewery` from a Progression row still
#  opens it full-screen — and there is one copy of each screen rather than a
#  windowed one and a full-screen one drifting apart.
#
#  ============ ONE AT A TIME ============
#
#  Opening a second window closes the first. "Please do not layer them" was
#  said about the visitors, and it is just as true here: two windows over a
#  base is a screen nobody can read.
# =============================================================

signal closed

## How much of the screen a window takes. The rest is the base, dimmed, so
## you can still see where you are.
const MARGIN := Vector2(90.0, 64.0)

var content: Control = null

static var _open_one: BaseWindow = null


## Put a screen up over `on`. `scene_path` is an ordinary .tscn — the same
## one ScenePaths would open full-screen.
static func open(on: Node, title: String, scene_path: String) -> BaseWindow:
	# ONE AT A TIME. See the note at the top.
	if _open_one != null and is_instance_valid(_open_one):
		_open_one.close()

	if not ResourceLoader.exists(scene_path):
		push_warning("[window] %s is not there." % scene_path)
		return null
	var made := BaseWindow.new()
	made.name = "BaseWindow"
	made.layer = 120
	on.add_child(made)
	made._build(title, scene_path)
	_open_one = made
	return made


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _build(title: String, scene_path: String) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# IT EATS CLICKS. Without this you can press a building THROUGH the
	# window, which opens a second one on top of the first.
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var frame := PanelContainer.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = MARGIN.x
	frame.offset_right = -MARGIN.x
	frame.offset_top = MARGIN.y
	frame.offset_bottom = -MARGIN.y
	frame.add_theme_stylebox_override("panel", MenuSupport.styled(
		"window", "", MenuSupport.COLOUR_BACKGROUND, MenuSupport.COLOUR_ACCENT))
	add_child(frame)
	# IT COMES UP INTO PLACE rather than appearing. `window_open` in
	# Motion.csv — fourteen pixels and six per cent over a sixth of a second,
	# which reads as a thing arriving. Delete the row and it simply appears.
	frame.call_deferred("set_pivot_offset", frame.size * 0.5)
	MotionBook.play(frame, "window_open")

	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right"]:
		pad.add_theme_constant_override(side, 18)
	for side in ["margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 14)
	frame.add_child(pad)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	pad.add_child(column)

	# ---- the title bar ----
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	column.add_child(bar)

	var heading := MenuSupport.heading(title.to_upper(), 26, MenuSupport.COLOUR_ACCENT)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(heading)

	var shut := Button.new()
	shut.text = "✕"
	shut.custom_minimum_size = Vector2(48.0, 40.0)
	shut.add_theme_font_size_override("font_size", 20)
	shut.add_theme_stylebox_override("normal",
		MenuSupport.panel_style(MenuSupport.COLOUR_PANEL, MenuSupport.COLOUR_ACCENT))
	shut.add_theme_stylebox_override("hover",
		MenuSupport.panel_style(MenuSupport.COLOUR_SLOT_EMPTY, MenuSupport.COLOUR_ACCENT))
	shut.add_theme_stylebox_override("focus", MenuSupport.focus_style())
	shut.add_theme_color_override("font_color", MenuSupport.COLOUR_ACCENT)
	shut.pressed.connect(close)
	bar.add_child(shut)

	column.add_child(HSeparator.new())

	# ---- the screen itself ----
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return
	content = packed.instantiate() as Control
	if content == null:
		return
	# SET BEFORE IT ENTERS THE TREE, so the screen's own _ready() can see it.
	content.set_meta("windowed", true)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(content)


func close() -> void:
	if _open_one == self:
		_open_one = null
	closed.emit()
	queue_free()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()
