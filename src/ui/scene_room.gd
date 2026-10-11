class_name SceneRoom
extends Control

# =============================================================
#  A BUILDING AS A PICTURE YOU CLICK THINGS IN  (round AN, Anthony 10 Oct)
#
#  "Rework the Club House and the Training Ground like the Dorms": the whole
#  window is one PixelLab scene, and what you buy are THINGS in it - keys
#  on a rack, plaques on a wall, a goal, a vaulting horse. Hover a thing: it
#  lights up and a luggage tag says what it is and what it costs. Click it:
#  it is bought (or a paper list opens, for the things with choices).
#
#  This is the shared half. A screen extends it (clubhouse_screen.gd,
#  training_screen.gd), names its layout CSV, and fills the room in
#  _fill(). Everything the screen places comes from that CSV:
#
#      Part, Image, X, Y, Scale
#
#  X and Y are the MIDDLE of the thing, as a share of the room picture
#  (0 = left / top, 1 = right / bottom), so it stays on its spot at any
#  window size. Scale multiplies the picture's own pixel size: 1 = the same
#  pixel size as the room. The `background` row is the room itself; `tag`,
#  `card` and `padlock` are the shared pieces; `status` and `message` are
#  placed as shares of the SCREEN.
# =============================================================

## The words on paper (tags, cards, the list) are written in this ink.
const INK := Color(0.16, 0.10, 0.06)
const INK_SOFT := Color(0.38, 0.2, 0.08)
const MESSAGE_SECONDS := 4.0

var db: CardDatabase
var state: GameState

var _layout: Dictionary = {}
var _room: Control
var _things: Control
var _line: Label
var _message: Label
var _tag: NinePatchRect
var _tag_words: VBoxContainer
var _sheet: PanelContainer
var _fade: Tween
## Where the room picture is on screen, and how big one picture pixel is.
var _pic_at := Vector2.ZERO
var _pic_size := Vector2.ZERO
var _pixel := 1.0


## The screen's layout CSV. Overridden.
func _layout_file() -> String:
	return ""


## The Guide.csv screen word, for the Head Coach. Overridden.
func _guide_screen() -> String:
	return ""


## Put the room's things in. Overridden; called on every rebuild.
func _fill() -> void:
	pass


## The one line on the wall. Overridden.
func _status_words() -> String:
	return ""


func _ready() -> void:
	var windowed := MenuSupport.in_a_window(self)
	if not windowed:
		MenuEscape.install(self)
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	db = CardDatabase.get_db()
	state = GameState.fetch(get_tree())
	AchievementBook.review(state)
	_load_layout()
	_build(windowed)
	resized.connect(rebuild)
	rebuild()
	var screen := _guide_screen()
	if screen != "":
		(func() -> void: Guide.check(self, screen, state)).call_deferred()


func _load_layout() -> void:
	_layout.clear()
	for row in MenuSupport.read_csv(_layout_file()):
		var part := MenuSupport.field(row, "Part").strip_edges().to_lower()
		if part == "":
			continue
		_layout[part] = {
			"part": part,
			"image": MenuSupport.field(row, "Image").strip_edges(),
			"x": MenuSupport.field_float(row, "X", 0.5),
			"y": MenuSupport.field_float(row, "Y", 0.5),
			"scale": maxf(0.05, MenuSupport.field_float(row, "Scale", 1.0)),
		}


## A row of the layout CSV, or {} when it has none.
func part(name_text: String) -> Dictionary:
	return _layout.get(name_text.to_lower(), {})


func has_part(name_text: String) -> bool:
	return _layout.has(name_text.to_lower())


func part_art(name_text: String) -> Texture2D:
	return texture(String(part(name_text).get("image", "")))


func _build(windowed: bool) -> void:
	clip_contents = true
	var fill := ColorRect.new()
	fill.color = Color(0.07, 0.05, 0.04)
	fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fill)
	_room = Control.new()
	_room.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_room.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_room)
	_things = Control.new()
	_things.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_things.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_things)
	_line = plated("", 17, MenuSupport.COLOUR_TEXT)
	add_child(_line)
	_message = plated("", 17, MenuSupport.COLOUR_TEXT)
	_message.visible = false
	add_child(_message)
	if not windowed:
		var back := MenuSupport.icon_button("◇", "Back to the base", Vector2(200, 42))
		back.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		back.position = Vector2(-220, -60)
		back.pressed.connect(func() -> void:
			state.save_to_disk()
			ScenePaths.go_back(get_tree(), ScenePaths.BASE))
		add_child(back)

	_tag = NinePatchRect.new()
	_tag.texture = part_art("tag")
	_tag.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var cut := _tag_margins()
	_tag.patch_margin_left = cut.x
	_tag.patch_margin_right = cut.y
	_tag.patch_margin_top = cut.z
	_tag.patch_margin_bottom = cut.w
	_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tag.top_level = true
	_tag.z_index = 60
	_tag.visible = false
	add_child(_tag)
	_tag_words = VBoxContainer.new()
	_tag_words.add_theme_constant_override("separation", 0)
	_tag_words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tag.add_child(_tag_words)


## Everything again, for the size the screen is now and the save as it is.
func rebuild() -> void:
	if size.x < 8.0 or size.y < 8.0:
		return
	for child in _room.get_children():
		_room.remove_child(child)
		child.queue_free()
	for child in _things.get_children():
		_things.remove_child(child)
		child.queue_free()
	_tag.visible = false
	_place_room()
	_fill()
	var at := part("status")
	_line.position = Vector2(float(at.get("x", 0.012)) * size.x, float(at.get("y", 0.015)) * size.y)
	_line.text = _status_words()
	_line.visible = _line.text != ""
	var spot := part("message")
	_message.position = Vector2(float(spot.get("x", 0.012)) * size.x, float(spot.get("y", 0.93)) * size.y)


## The room picture covering the screen; the CEILING is cut when the screen
## is wider than the picture, never the floor.
func _place_room() -> void:
	var art := part_art("background")
	var aspect := float(art.get_width()) / float(art.get_height()) if art != null else 16.0 / 9.0
	var pic := Vector2(size.x, size.x / aspect)
	if pic.y < size.y:
		pic = Vector2(size.y * aspect, size.y)
	_pic_size = pic
	_pic_at = Vector2((size.x - pic.x) * 0.5, size.y - pic.y)
	_pixel = pic.x / float(art.get_width()) if art != null else 1.0
	if art == null:
		return
	var picture := TextureRect.new()
	picture.texture = art
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_SCALE
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.position = _pic_at
	picture.size = pic
	_room.add_child(picture)


## A point of the room picture, on screen.
func at(fx: float, fy: float) -> Vector2:
	return _pic_at + Vector2(fx * _pic_size.x, fy * _pic_size.y)


# =============================================================
#  THINGS
# =============================================================

## Put a thing in the room where its layout row says. `look` is "open"
## (lit, clickable), "dim" (greyed: locked, or nothing to do) or "done"
## (yours already: full colour, not lit). `lines` is its luggage tag.
## Returns the button, or null when the row or the picture is missing.
func thing(row_name: String, art: Texture2D, look: String, lines: Array,
		what: Callable, padlock: bool = false) -> MapBuilding:
	var row := part(row_name)
	if row.is_empty():
		return null
	if art == null:
		art = texture(String(row["image"]))
	if art == null:
		return null
	var button := MapBuilding.new()
	button.flat = true
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_stylebox_override("focus", MenuSupport.focus_style())
	var box := Vector2(art.get_size()) * _pixel * float(row["scale"])
	var picture := TextureRect.new()
	picture.texture = art
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_SCALE
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button.add_child(picture)
	button.use_picture(art)
	button.size = box
	button.position = at(float(row["x"]), float(row["y"])) - box * 0.5
	var resting := Color.WHITE
	if look == "dim":
		resting = Color(0.55, 0.55, 0.58)
	button.modulate = resting
	button.set_meta("look", look)
	button.mouse_entered.connect(func() -> void:
		button.modulate = resting * (1.25 if look == "open" else 1.1)
		show_tag(lines, button))
	button.mouse_exited.connect(func() -> void:
		button.modulate = resting
		_tag.visible = false)
	button.pressed.connect(what)
	_things.add_child(button)
	if padlock:
		var lock_art := part_art("padlock")
		if lock_art != null:
			var lock := TextureRect.new()
			lock.texture = lock_art
			lock.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			lock.stretch_mode = TextureRect.STRETCH_SCALE
			lock.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var lock_box := Vector2(lock_art.get_size()) * _pixel * float(part("padlock").get("scale", 0.5))
			lock.size = lock_box
			# The lock wears the thing's own dimming, so it reads as part of it.
			lock.modulate = Color(1.8, 1.8, 1.8)
			lock.position = box * 0.5 - lock_box * 0.5
			button.add_child(lock)
	return button


## A price card pinned under `over` (or at a layout row). It buys too.
func card(words: String, over: Control, allowed: bool, what: Callable) -> Button:
	var button := Button.new()
	button.flat = true
	button.focus_mode = Control.FOCUS_ALL
	var art := part_art("card")
	var plate := NinePatchRect.new()
	plate.texture = art
	plate.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if art != null:
		plate.patch_margin_left = int(art.get_width() * 0.2)
		plate.patch_margin_right = int(art.get_width() * 0.2)
		plate.patch_margin_top = int(art.get_height() * 0.4)
		plate.patch_margin_bottom = int(art.get_height() * 0.25)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button.add_child(plate)
	var label := MenuSupport.heading(words, 16, INK if allowed else Color(0.45, 0.4, 0.35))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.offset_top = 6.0
	button.add_child(label)
	var scale_by := float(part("card").get("scale", 1.4))
	var high := (art.get_height() if art != null else 32) * scale_by
	var wide := maxf(label.get_minimum_size().x + 30.0, (art.get_width() if art != null else 64) * scale_by * 0.8)
	button.size = Vector2(wide, high)
	if over != null:
		button.position = Vector2(over.position.x + over.size.x * 0.5 - wide * 0.5, over.position.y + over.size.y - 4.0)
	button.mouse_entered.connect(func() -> void: button.modulate = Color(1.15, 1.15, 1.15))
	button.mouse_exited.connect(func() -> void: button.modulate = Color.WHITE)
	button.pressed.connect(what)
	_things.add_child(button)
	return button


## Words written on a thing (a poster's name), in ink, centred on a share of it.
func write_on(over: Control, words: String, fy: float, size_px: int = 16, colour: Color = INK) -> Label:
	var label := MenuSupport.heading(words, size_px, colour)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size = Vector2(over.size.x, size_px + 6)
	label.position = Vector2(0, over.size.y * fy - (size_px + 6) * 0.5)
	over.add_child(label)
	return label


# =============================================================
#  THE LUGGAGE TAG, THE PAPER LIST, MESSAGES
# =============================================================

func _tag_margins() -> Vector4i:
	var art := _tag.texture if _tag != null else null
	if art == null:
		return Vector4i(0, 0, 0, 0)
	return Vector4i(int(art.get_width() * 0.3), int(art.get_width() * 0.25),
		int(art.get_height() * 0.3), int(art.get_height() * 0.3))


func show_tag(lines: Array, over: Control) -> void:
	if lines.is_empty():
		return
	for child in _tag_words.get_children():
		_tag_words.remove_child(child)
		child.queue_free()
	var widest := 0.0
	for i in lines.size():
		var label := MenuSupport.heading(String(lines[i]), 16, INK if i == 0 else INK_SOFT)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_tag_words.add_child(label)
		widest = maxf(widest, label.get_minimum_size().x)
	var cut := _tag_margins()
	var high := 22.0 * lines.size() + 20.0
	# The words start clear of the string that loops from the tag's hole.
	var wide := widest + cut.x + cut.y + 40.0
	_tag.size = Vector2(wide, high)
	_tag_words.position = Vector2(cut.x + 32.0, 10.0)
	_tag.visible = true
	var spot_rect := over.get_global_rect()
	var spot := Vector2(spot_rect.position.x + spot_rect.size.x * 0.5 - wide * 0.3, spot_rect.position.y - high - 6.0)
	var room := get_global_rect()
	spot.x = clampf(spot.x, room.position.x + 4.0, room.end.x - wide - 4.0)
	if spot.y < room.position.y + 4.0:
		spot.y = spot_rect.end.y + 6.0
	_tag.global_position = spot


## A sheet of paper over the room with a list on it: one row per entry,
##     {"words": "Name", "sub": "small line", "buttons": [{"label", "ok", "do"}]}
## Click outside it (or its Done card) to put it away.
func show_sheet(title: String, entries: Array) -> void:
	close_sheet()
	var shade := ColorRect.new()
	shade.name = "SheetShade"
	shade.color = Color(0, 0, 0, 0.35)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			close_sheet())
	add_child(shade)
	_sheet = PanelContainer.new()
	var paper := StyleBoxFlat.new()
	paper.bg_color = Color(0.94, 0.88, 0.74)
	paper.border_color = Color(0.35, 0.22, 0.1)
	paper.set_border_width_all(3)
	paper.set_corner_radius_all(4)
	paper.content_margin_left = 22
	paper.content_margin_right = 22
	paper.content_margin_top = 16
	paper.content_margin_bottom = 16
	_sheet.add_theme_stylebox_override("panel", paper)
	add_child(_sheet)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	_sheet.add_child(column)
	column.add_child(MenuSupport.heading(title, 22, INK))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(minf(size.x * 0.7, 880.0), minf(size.y * 0.62, 70.0 * maxi(entries.size(), 1)))
	column.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 6)
	scroll.add_child(rows)
	if entries.is_empty():
		rows.add_child(MenuSupport.heading("Nobody here.", 16, INK_SOFT))
	for entry in entries:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		rows.add_child(line)
		var words := VBoxContainer.new()
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		words.add_theme_constant_override("separation", 0)
		line.add_child(words)
		words.add_child(MenuSupport.heading(String(entry.get("words", "")), 17, INK))
		if String(entry.get("sub", "")) != "":
			words.add_child(MenuSupport.heading(String(entry["sub"]), 14, INK_SOFT))
		for b in entry.get("buttons", []):
			line.add_child(_sheet_button(String(b["label"]), bool(b["ok"]), b["do"]))
	var done := _sheet_button("Done", true, close_sheet)
	done.size_flags_horizontal = Control.SIZE_SHRINK_END
	column.add_child(done)
	_sheet.reset_size()
	_sheet.position = (size - _sheet.get_combined_minimum_size()) * 0.5


func _sheet_button(words: String, allowed: bool, what: Callable) -> Button:
	var button := Button.new()
	button.text = words
	button.disabled = not allowed
	button.custom_minimum_size = Vector2(120, 34)
	var face := ThemeBook.font(String(ThemeBook.row_for("heading").get("font", "")))
	if face != null:
		button.add_theme_font_override("font", face)
	button.add_theme_font_size_override("font_size", 15)
	var art := part_art("card")
	for kind in ["normal", "hover", "pressed", "disabled", "focus"]:
		var box := StyleBoxTexture.new()
		box.texture = art
		if art != null:
			box.texture_margin_left = art.get_width() * 0.2
			box.texture_margin_right = art.get_width() * 0.2
			box.texture_margin_top = art.get_height() * 0.4
			box.texture_margin_bottom = art.get_height() * 0.25
		box.content_margin_left = 12
		box.content_margin_right = 12
		box.content_margin_top = 8
		box.modulate_color = Color(1.12, 1.12, 1.12) if kind == "hover" else (
			Color(0.7, 0.7, 0.7) if kind == "disabled" else Color.WHITE)
		button.add_theme_stylebox_override(kind, box)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_disabled_color", Color(0.45, 0.4, 0.35))
	button.pressed.connect(what)
	return button


func close_sheet() -> void:
	if _sheet != null and is_instance_valid(_sheet):
		_sheet.queue_free()
	_sheet = null
	for child in get_children():
		if child.name == "SheetShade":
			child.queue_free()


## What happened, for a few seconds; on success the save is written and the
## room drawn again.
func say(result: Dictionary) -> void:
	tell(String(result["why"]), bool(result["ok"]))
	if bool(result["ok"]):
		state.save_to_disk()
	close_sheet()
	rebuild()


func tell(words: String, good: bool) -> void:
	_message.text = words
	_message.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT if good else Color(1.0, 0.72, 0.4))
	_message.visible = true
	_message.modulate.a = 1.0
	if _fade != null:
		_fade.kill()
	_fade = create_tween()
	_fade.tween_interval(MESSAGE_SECONDS)
	_fade.tween_property(_message, "modulate:a", 0.0, 0.5)


func plated(text: String, size_px: int, colour: Color) -> Label:
	var label := MenuSupport.heading(text, size_px, colour)
	label.add_theme_stylebox_override("normal", TextBackdrop.plate())
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func price_words(price: int, currency_id: String) -> String:
	if price <= 0:
		return "free"
	var cur := ShopBook.currency(currency_id)
	return "%d %s" % [price, cur.get("name", currency_id)]


func short_price(price: int, currency_id: String) -> String:
	if price <= 0:
		return "free"
	return str(price) if currency_id == "coins" else price_words(price, currency_id)


func can_pay(price: int, currency_id: String) -> bool:
	return price <= 0 or ShopBook.purse(currency_id, state) >= price


func texture(path: String) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D
