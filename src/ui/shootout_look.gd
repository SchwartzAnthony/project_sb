class_name ShootoutLook
extends RefCounted

# =============================================================
#  THE SHOT WINDOW'S LOOK  (Anthony, 24 Oct 2026)
#
#  "A goalie window update in our new art and not just being empty boxes."
#  The window from shootout_view.tscn, dressed like the Inventory: a cream
#  beer mat panel with the wooden board on top, shot power and chance of a
#  goal on beer coasters, keeper stamina as a beer, the keeper standing in
#  the village goal, the shooter from behind, the words on a small cream
#  panel and a blue SKIP plank.
#
#  Everything is in data/ShootoutLook.csv; style old brings the dark
#  window back. The window's own nodes and numbers are not touched - this
#  only changes how they look.
# =============================================================

const PATH := "res://data/ShootoutLook.csv"
const BOARD := "res://data/MenuHeaderBoard.csv"
const BASE := "Dim/Center/Frame/Margin/VBox"

static var _rows: Dictionary = {}
static var _loaded := false


static func value(key: String, fallback: String = "") -> String:
	if not _loaded:
		_loaded = true
		for row in MenuSupport.read_csv(PATH):
			_rows[MenuSupport.field(row, "Key").strip_edges().to_lower()] = MenuSupport.field(row, "Value").strip_edges()
	var found := String(_rows.get(key, ""))
	return found if found != "" else fallback


static func number(key: String, fallback: float) -> float:
	var text := value(key)
	return float(text) if text.is_valid_float() else fallback


static func pair(key: String, fallback: Vector2) -> Vector2:
	var parts := value(key).split(",")
	if parts.size() == 2:
		return Vector2(float(parts[0]), float(parts[1]))
	return fallback


static func enabled() -> bool:
	return value("style", "mat").to_lower() == "mat"


static func ink() -> Color:
	return Color.from_string(value("ink", "#19110a"), Color(0.1, 0.07, 0.04))


## The goal inside the picture, as fractions: left, top, right, bottom.
static func goal_box() -> Rect2:
	var parts := value("goal_box", "0.2,0.14,0.8,0.8").split(",")
	if parts.size() != 4:
		return Rect2(0.2, 0.14, 0.6, 0.66)
	return Rect2(float(parts[0]), float(parts[1]),
		float(parts[2]) - float(parts[0]), float(parts[3]) - float(parts[1]))


static func _panel(path: String, edge: float) -> StyleBox:
	var tex := load(path) as Texture2D if ResourceLoader.exists(path) else null
	if tex == null:
		return null
	var style := StyleBoxTexture.new()
	style.texture = tex
	style.texture_margin_left = edge
	style.texture_margin_right = edge
	style.texture_margin_top = edge
	style.texture_margin_bottom = edge
	return style


static func _ink_label(label: Label, text_size: int) -> void:
	if label == null:
		return
	label.add_theme_color_override("font_color", ink())
	label.add_theme_font_size_override("font_size", text_size)
	label.add_theme_constant_override("outline_size", 0)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))


## Dress the window. Called once, after shootout_view.gd has found its nodes.
static func apply(view: ShootoutView) -> void:
	var dim := view.get_node_or_null("Dim") as ColorRect
	var frame := view.get_node_or_null("Dim/Center/Frame") as PanelContainer
	if dim == null or frame == null:
		return
	dim.color = Color(0, 0, 0, 0.55)
	frame.custom_minimum_size = pair("window", Vector2(1240, 800))
	var panel := _panel(value("panel"), number("panel_edge", 54.0))
	if panel != null:
		panel.set_content_margin_all(0.0)
		frame.add_theme_stylebox_override("panel", panel)
	var margin := view.get_node_or_null("Dim/Center/Frame/Margin") as MarginContainer
	if margin:
		margin.add_theme_constant_override("margin_left", 60)
		margin.add_theme_constant_override("margin_right", 60)
		margin.add_theme_constant_override("margin_top", 64)
		margin.add_theme_constant_override("margin_bottom", 36)
	var vbox := view.get_node_or_null(BASE) as VBoxContainer
	if vbox:
		vbox.add_theme_constant_override("separation", 10)

	# The title moves onto the wooden board (show_title); the label stays,
	# hidden, so everything that writes to it still works.
	var title := view.get_node_or_null(BASE + "/Title") as Label
	if title:
		title.visible = false

	var label_size := int(number("label_size", 24))
	var value_size := int(number("value_size", 52))
	for box_name in ["ShotBox", "StaminaBox", "ChanceBox"]:
		var box := view.get_node_or_null(BASE + "/Readouts/" + box_name) as VBoxContainer
		if box == null:
			continue
		box.custom_minimum_size.x = 330
		for child in box.get_children():
			if child is Label:
				_ink_label(child, label_size)
	for value_name in ["ShotBox/ShotValue", "StaminaBox/StaminaValue", "ChanceBox/ChanceValue"]:
		_ink_label(view.get_node_or_null(BASE + "/Readouts/" + value_name) as Label, value_size)
	_ink_label(view.get_node_or_null(BASE + "/Readouts/ChanceBox/ChanceNote") as Label, int(number("note_size", 17)))
	# 24 Oct 2026 (Anthony: "The % number of the chance for the goalie is too
	# large (is outside of the circle)"): "100%" has to fit inside the coaster.
	_ink_label(view.get_node_or_null(BASE + "/Readouts/ChanceBox/ChanceValue") as Label,
		int(number("chance_size", 32)))

	# Shot power and the chance sit on a beer coaster each.
	var across := number("coaster", 130.0)
	for value_name in ["ShotBox/ShotValue", "ChanceBox/ChanceValue"]:
		var number_label := view.get_node_or_null(BASE + "/Readouts/" + value_name) as Label
		if number_label == null:
			continue
		number_label.custom_minimum_size.y = across + 8
		number_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var coaster := InventoryScreen.Coaster.new()
		coaster.name = "Coaster"
		coaster.show_behind_parent = true
		coaster.mouse_filter = Control.MOUSE_FILTER_IGNORE
		coaster.set_anchors_preset(Control.PRESET_CENTER)
		coaster.offset_left = -across / 2.0
		coaster.offset_right = across / 2.0
		coaster.offset_top = -across / 2.0
		coaster.offset_bottom = across / 2.0
		number_label.add_child(coaster)

	# Keeper stamina is a glass of beer lying down: gold beer, white foam.
	var bar := view.get_node_or_null(BASE + "/Readouts/StaminaBox/StaminaBar") as ProgressBar
	if bar:
		bar.custom_minimum_size = Vector2(0, 34)
		var glass := StyleBoxFlat.new()
		glass.bg_color = Color(0.93, 0.89, 0.79)
		glass.border_color = ink()
		glass.set_border_width_all(4)
		glass.set_corner_radius_all(17)
		var beer := StyleBoxFlat.new()
		beer.bg_color = Color(0.91, 0.66, 0.15)
		beer.border_color = Color(0.99, 0.98, 0.94)
		beer.border_width_right = 10
		beer.set_corner_radius_all(15)
		beer.set_expand_margin_all(-4.0)
		bar.add_theme_stylebox_override("background", glass)
		bar.add_theme_stylebox_override("fill", beer)

	_dress_stage(view)
	_dress_caption(view)


static func _dress_stage(view: ShootoutView) -> void:
	var stage := view.get_node_or_null(BASE + "/Stage") as Control
	if stage == null:
		return
	var picture_path := value("stage")
	var picture := load(picture_path) as Texture2D if ResourceLoader.exists(picture_path) else null
	var box := pair("stage_size", Vector2(1040, 444))
	stage.custom_minimum_size = box
	stage.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stage.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stage.clip_contents = true

	if picture != null:
		var back := TextureRect.new()
		back.name = "Village"
		back.texture = picture
		back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		back.stretch_mode = TextureRect.STRETCH_SCALE
		back.set_anchors_preset(Control.PRESET_FULL_RECT)
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stage.add_child(back)
		stage.move_child(back, 0)

	# The keeper stands in the goal.
	var goal := goal_box()
	var keeper_stage := view.get_node_or_null(BASE + "/Stage/KeeperStage") as Control
	if keeper_stage:
		keeper_stage.anchor_left = goal.position.x
		keeper_stage.anchor_top = goal.position.y
		keeper_stage.anchor_right = goal.end.x
		keeper_stage.anchor_bottom = goal.end.y
		for side in ["offset_left", "offset_top", "offset_right", "offset_bottom"]:
			keeper_stage.set(side, 0.0)

	# The shooter from behind, bottom middle, cut by the frame (over his shoulder).
	var striker_box := pair("striker_box", Vector2(460, 380))
	var striker_stage := view.get_node_or_null(BASE + "/Stage/StrikerStage") as Control
	if striker_stage:
		var shift := number("striker_x", -150.0)
		var below := number("striker_below", 40.0)
		striker_stage.offset_left = -striker_box.x / 2.0 + shift
		striker_stage.offset_right = striker_box.x / 2.0 + shift
		striker_stage.offset_top = -striker_box.y + below
		striker_stage.offset_bottom = below

	# The ink edge and red line round the picture, like the card's window.
	var edge := Panel.new()
	edge.name = "Edge"
	var line := StyleBoxFlat.new()
	line.draw_center = false
	line.border_color = ink()
	line.set_border_width_all(5)
	line.set_corner_radius_all(12)
	edge.add_theme_stylebox_override("panel", line)
	edge.set_anchors_preset(Control.PRESET_FULL_RECT)
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(edge)
	var red := Panel.new()
	red.name = "RedLine"
	var red_line := StyleBoxFlat.new()
	red_line.draw_center = false
	red_line.border_color = Color(0.78, 0.16, 0.16)
	red_line.set_border_width_all(3)
	red_line.set_corner_radius_all(8)
	red_line.set_expand_margin_all(-9.0)
	red.add_theme_stylebox_override("panel", red_line)
	red.set_anchors_preset(Control.PRESET_FULL_RECT)
	red.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(red)


## A strip of pictures side by side, one shown at a time: the drawn keeper
## (picture 0 = ready, the rest = his dive).
class KeeperStrip:
	extends TextureRect
	var frames := 1
	var fps := 12.0
	var speed := 1.0
	var _atlas: AtlasTexture
	var _at := 0.0
	var _playing := false

	func setup(sheet: Texture2D, count: int, rate: float) -> void:
		frames = maxi(1, count)
		fps = rate
		_atlas = AtlasTexture.new()
		_atlas.atlas = sheet
		texture = _atlas
		show_frame(0)

	## The same keeper in another kit (a strip of the same size).
	func use_sheet(sheet: Texture2D) -> void:
		if sheet != null and _atlas.atlas != sheet:
			_atlas.atlas = sheet
			show_frame(0)

	func cell() -> Vector2:
		var full := _atlas.atlas.get_size()
		return Vector2(full.x / float(frames), full.y)

	func show_frame(i: int) -> void:
		var c := cell()
		_atlas.region = Rect2(Vector2(c.x * clampi(i, 0, frames - 1), 0), c)

	func ready_pose() -> void:
		_playing = false
		show_frame(0)

	func dive() -> void:
		_at = 1.0
		_playing = frames > 1
		show_frame(1)

	func _process(delta: float) -> void:
		if not _playing:
			return
		_at += delta * fps * speed
		if _at >= frames - 1:
			_at = frames - 1
			_playing = false
		show_frame(int(_at))


## The stand-in keeper: the drawn strip from ShootoutLook.csv inside the
## placeholder box (which turns see-through), feet on the goal line.
## Returns the strip, or null with no picture.
static func dress_keeper_placeholder(holder: ColorRect, _keeper_stage: Control) -> KeeperStrip:
	var path := value("keeper")
	var tex := load(path) as Texture2D if path != "" and ResourceLoader.exists(path) else null
	if tex == null or holder == null:
		return null
	var strip := KeeperStrip.new()
	strip.name = "Keeper"
	strip.setup(tex, int(number("keeper_frames", 1)), number("keeper_fps", 12.0))
	var goal := goal_box().size * pair("stage_size", Vector2(1040, 444))
	# Picture 0 stands about 0.69 of the strip's height (his feet at its bottom).
	var tall := goal.y * number("keeper_height", 0.9) / number("keeper_figure", 0.69)
	var c := strip.cell()
	var wide := tall * c.x / c.y
	holder.color = Color(0, 0, 0, 0)
	holder.custom_minimum_size = Vector2(wide, goal.y)
	strip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	strip.stretch_mode = TextureRect.STRETCH_SCALE
	strip.size = Vector2(wide, tall)
	strip.position = Vector2(0, goal.y - tall)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(strip)
	return strip


## Yours (yellow) or theirs (green) for this shot.
static func dress_keeper_kit(strip: KeeperStrip, theirs: bool) -> void:
	if strip == null:
		return
	var path := value("keeper_away") if theirs else ""
	if path == "" or not ResourceLoader.exists(path):
		path = value("keeper")
	strip.use_sheet(load(path) as Texture2D)


static func _dress_caption(view: ShootoutView) -> void:
	var caption := view.get_node_or_null(BASE + "/Caption") as Label
	var vbox := view.get_node_or_null(BASE) as VBoxContainer
	if caption == null or vbox == null:
		return
	_ink_label(caption, int(number("caption_size", 26)))
	var shelf := _panel(value("caption_panel"), number("caption_edge", 36.0))
	if shelf != null:
		shelf.content_margin_left = 44
		shelf.content_margin_right = 44
		shelf.content_margin_top = 16
		shelf.content_margin_bottom = 16
		caption.add_theme_stylebox_override("normal", shelf)
	caption.custom_minimum_size = Vector2(700, 70)
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	var row := HBoxContainer.new()
	row.name = "CaptionRow"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	var at := caption.get_index()
	vbox.remove_child(caption)
	row.add_child(caption)
	vbox.add_child(row)
	vbox.move_child(row, at)

	if value("skip", "yes").to_lower() in ["yes", "true", "1"]:
		var skip := Button.new()
		skip.name = "Skip"
		skip.text = Loc.text("skip", "Skip").to_upper()
		skip.custom_minimum_size = Vector2(170, 56)
		skip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		skip.add_theme_font_size_override("font_size", 24)
		skip.focus_mode = Control.FOCUS_NONE
		skip.pressed.connect(view.skip)
		InventoryScreen._plank(skip)
		row.add_child(skip)


## The title on the wooden board above the window. A new board each time,
## so it is as wide as the words.
static func show_title(view: ShootoutView, words: String) -> void:
	var dim := view.get_node_or_null("Dim") as Control
	var frame := view.get_node_or_null("Dim/Center/Frame") as Control
	if dim == null or frame == null:
		return
	var old := dim.get_node_or_null("SignHeader")
	if old != null:
		dim.remove_child(old)
		old.queue_free()
	var sign := SignHeader.make(words.to_upper(), BOARD)
	sign.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(sign)
	var lift := number("header_lift", 82.0)
	var place := func() -> void:
		if is_instance_valid(sign) and is_instance_valid(frame):
			sign.position = frame.global_position - dim.global_position \
				+ Vector2((frame.size.x - sign.size.x) / 2.0, -lift)
	sign.resized.connect(place)
	if dim.has_meta("sign_place"):
		var before: Callable = dim.get_meta("sign_place")
		if frame.item_rect_changed.is_connected(before):
			frame.item_rect_changed.disconnect(before)
	dim.set_meta("sign_place", place)
	frame.item_rect_changed.connect(place)
	place.call()
	place.call_deferred()
