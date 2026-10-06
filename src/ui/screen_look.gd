class_name ScreenLook
extends RefCounted

# =============================================================
#  WHAT A MENU SCREEN LOOKS AND SOUNDS LIKE  (round AL)
#
#  One spreadsheet, data/ScreenLook.csv, dresses any menu screen the way
#  MainMenu.csv dresses the title screen: painted LAYERS behind it, a dark
#  SHADE so the text stays readable, and every BUTTON on it turned into the
#  wooden plank with the menu's click sounds.
#
#  A screen opts in with one line in its _ready():
#      ScreenLook.install(self, "settings")
#  and from then on everything about it is the spreadsheet.
#
#  ============ data/ScreenLook.csv - one row per thing ============
#
#    Screen   which screen: settings, slot ... (the word in install())
#    Part     background   the back layer - fills the screen
#             picture      a layer on top, drawn in row order (back to front)
#             shade        a see-through dark box (Colour) behind the menu
#             margin       Width = how far the screen's content sits in from
#                          the left and right edges, Height = from the top
#                          and bottom, so the painted layers show round it
#             button       how EVERY button looks: Image = the plank,
#                          Colour = the text colour, and the three sounds
#    Image    the picture (res://...)
#    X, Y     the CENTRE, on a 1920 x 1080 screen
#    Width, Height   size; blank = the picture's pixels x Scale
#    Scale    2 = twice its pixels (every layer the same pixel size)
#    Flip     yes = mirrored
#    Colour   shade: #RRGGBBAA (AA = how solid, 00-ff); button: text colour
#    Hover Sound / Press Sound / Back Sound   Audio.csv rows (button row).
#             Back Sound is for buttons that say Back, Close or Quit.
#    Notes    anything
# =============================================================

const SHEET := "res://data/ScreenLook.csv"


static func install(screen: Control, screen_id: String) -> void:
	var rows: Array[Dictionary] = []
	for row in MenuSupport.read_csv(SHEET):
		if MenuSupport.field(row, "Screen").strip_edges().to_lower() == screen_id.to_lower():
			rows.append(row)
	if rows.is_empty():
		return

	# Layers go right above the screen's own flat background colour (its
	# first ColorRect), so all of the screen's own content stays in front.
	var at := 0
	for child in screen.get_children():
		if child is ColorRect:
			at = child.get_index() + 1
			break
	var button_row: Dictionary = {}
	for row in rows:
		var part := MenuSupport.field(row, "Part").strip_edges().to_lower()
		var node: Control = null
		match part:
			"background":
				node = _layer(row, true)
			"picture":
				node = _layer(row, false)
			"shade":
				node = _shade(row)
			"button":
				button_row = row
			"margin":
				# Pull the screen's content in from the edges so the painted
				# layers show round it: Width = left and right, Height = top
				# and bottom, in pixels.
				for box in screen.get_children():
					if box is MarginContainer:
						var side := MenuSupport.field_float(row, "Width", 40.0)
						var top := MenuSupport.field_float(row, "Height", 24.0)
						for key in ["margin_left", "margin_right"]:
							(box as MarginContainer).add_theme_constant_override(key, int(side))
						for key in ["margin_top", "margin_bottom"]:
							(box as MarginContainer).add_theme_constant_override(key, int(top))
			_:
				print("[look] ScreenLook.csv: Part '%s' is not background, picture, shade, margin or button." % part)
		if node != null:
			screen.add_child(node)
			screen.move_child(node, at)
			at += 1

	if button_row.is_empty():
		return
	# Every button, now and later (tabs rebuild their rows, windows open).
	_dress_all(screen, button_row)
	if screen.has_meta("screen_look_hooked"):
		return
	screen.set_meta("screen_look_hooked", true)
	var tree := screen.get_tree()
	var hook := func(node: Node) -> void:
		if node is Button and is_instance_valid(screen) and screen.is_ancestor_of(node):
			_dress.call_deferred(node as Button, button_row)
	tree.node_added.connect(hook)
	screen.tree_exiting.connect(func() -> void:
		if tree.node_added.is_connected(hook):
			tree.node_added.disconnect(hook))


## A picture, read even if Godot has not imported it yet.
static func picture(path: String) -> Texture2D:
	if path == "":
		return null
	# ROUND AL: the file itself first, so a picture you have just changed shows
	# at once even if Godot has not re-imported it yet (exported games have no
	# raw files, and fall through to the imported copy).
	if FileAccess.file_exists(path):
		var image := Image.load_from_file(path)
		if image != null and not image.is_empty():
			return ImageTexture.create_from_image(image)
	if ResourceLoader.exists(path):
		var imported := load(path) as Texture2D
		if imported != null:
			return imported
	print("[look] ScreenLook.csv: no picture at '%s' yet." % path)
	return null


static func _layer(row: Dictionary, full: bool) -> Control:
	var texture := picture(MenuSupport.field(row, "Image").strip_edges())
	if texture == null:
		return null
	var art := TextureRect.new()
	art.texture = texture
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.flip_h = MenuSupport.field(row, "Flip").strip_edges().to_lower() == "yes"
	if full:
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		return art
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var scale := MenuSupport.field_float(row, "Scale", 1.0)
	var w := MenuSupport.field_float(row, "Width", 0.0)
	var h := MenuSupport.field_float(row, "Height", 0.0)
	if w <= 0.0:
		w = float(texture.get_width()) * scale
	if h <= 0.0:
		h = float(texture.get_height()) * scale
	art.size = Vector2(w, h)
	art.position = Vector2(MenuSupport.field_float(row, "X", 960.0) - w * 0.5,
		MenuSupport.field_float(row, "Y", 540.0) - h * 0.5)
	return art


static func _shade(row: Dictionary) -> Control:
	var box := ColorRect.new()
	box.color = Color.from_string(MenuSupport.field(row, "Colour", "#00000088").strip_edges(), Color(0, 0, 0, 0.5))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var w := MenuSupport.field_float(row, "Width", 1920.0)
	var h := MenuSupport.field_float(row, "Height", 1080.0)
	box.size = Vector2(w, h)
	box.position = Vector2(MenuSupport.field_float(row, "X", 960.0) - w * 0.5,
		MenuSupport.field_float(row, "Y", 540.0) - h * 0.5)
	return box


static func _dress_all(node: Node, row: Dictionary) -> void:
	if node is Button:
		_dress(node as Button, row)
	for child in node.get_children():
		_dress_all(child, row)


## Only plain buttons become planks - tick boxes, sliders and drop-downs
## keep their own look so they still read as what they are.
static func _dress(button: Button, row: Dictionary) -> void:
	if not is_instance_valid(button) or button.has_meta("screen_look"):
		return
	if button.get_class() != "Button":
		return
	button.set_meta("screen_look", true)

	var plank := picture(MenuSupport.field(row, "Image").strip_edges())
	if plank != null:
		# The plank is pixel art: draw it at 2x and keep its corners, stretch
		# only its middle, so it fits a button of any size.
		var big := plank.get_image()
		if big != null:
			big = big.duplicate()
			big.resize(big.get_width() * 2, big.get_height() * 2, Image.INTERPOLATE_NEAREST)
			var tex := ImageTexture.create_from_image(big)
			var edge := float(big.get_height()) * 0.32
			var looks := {"normal": Color(1, 1, 1), "hover": Color(1.2, 1.14, 1.02),
				"pressed": Color(0.8, 0.76, 0.7), "focus": Color(1.2, 1.14, 1.02),
				"disabled": Color(0.55, 0.55, 0.55)}
			for state in looks:
				var style := StyleBoxTexture.new()
				style.texture = tex
				style.texture_margin_left = edge
				style.texture_margin_right = edge
				style.texture_margin_top = edge
				style.texture_margin_bottom = edge
				style.modulate_color = looks[state]
				button.add_theme_stylebox_override(state, style)
			button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		# The icon half of a two-part button gets no box of its own on wood.
		for part in button.find_children("*", "PanelContainer", true, false):
			(part as PanelContainer).add_theme_stylebox_override("panel", StyleBoxEmpty.new())

	var text_colour := Color.from_string(MenuSupport.field(row, "Colour", "#f6ead0").strip_edges(), Color("f6ead0"))
	button.add_theme_color_override("font_color", text_colour)
	button.add_theme_color_override("font_hover_color", Color("ffd36a"))
	button.add_theme_color_override("font_focus_color", Color("ffd36a"))
	button.add_theme_color_override("font_outline_color", Color("2a1608"))
	button.add_theme_constant_override("outline_size", 6)
	for label in button.find_children("*", "Label", true, false):
		(label as Label).add_theme_color_override("font_outline_color", Color("2a1608"))
		(label as Label).add_theme_constant_override("outline_size", 5)

	var hover := MenuSupport.field(row, "Hover Sound", "menu_hover").strip_edges()
	var press := MenuSupport.field(row, "Press Sound", "menu_click").strip_edges()
	var back := MenuSupport.field(row, "Back Sound", "menu_back").strip_edges()
	button.mouse_entered.connect(func() -> void: AudioDirector.play_cue(button.get_tree(), hover))
	button.focus_entered.connect(func() -> void: AudioDirector.play_cue(button.get_tree(), hover))
	button.pressed.connect(func() -> void:
		AudioDirector.play_cue(button.get_tree(), back if _is_back(button) else press))


static func _is_back(button: Button) -> bool:
	var words := button.text
	for label in button.find_children("*", "Label", true, false):
		words += " " + (label as Label).text
	words = words.to_lower()
	for word in ["back", "close", "quit", "cancel", "zurück"]:
		if words.contains(word):
			return true
	return false
