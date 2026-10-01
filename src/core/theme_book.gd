class_name ThemeBook
extends RefCounted

# =============================================================
#  THE SKIN — data/Theme.csv
#
#  ============ THE QUESTION THIS ANSWERS ============
#
#  "Right now people can tell it is an AI game. I need to be able to customise
#   the windows, the HUD, the lines, with images. Allow me to change the image
#   through CSV."
#
#  Every box the game draws — a card face, a tile, a dialog, the strip above
#  the card row, a button, the keeper's number — is drawn by ONE function:
#  MenuSupport.panel_style(). This file sits in front of it. Change the
#  `panel` row and you have changed every one of them at once, without
#  opening a single screen.
#
#  ============ WHAT A ROW IS ============
#
#      Element       what kind of thing this is. `panel`, `button`, `window`
#      State         blank, hover, pressed, disabled, focus, selected
#      Image         a 9-slice PNG in assets/ui/. Blank = a flat colour
#      Tint          `no` draws that image exactly as you drew it. See below
#      Slice         how far in from the edge of that image the corners are
#      Fill          the colour, when there is no image. #rrggbb
#      Border        the edge colour
#      Border Width  how thick the edge is, in pixels
#      Corner        how round the corners are, in pixels
#      Pad X / Pad Y how much space there is between the edge and the words
#      Font          a .ttf in assets/fonts/
#      Size          the font size
#      Text Colour   the colour of the words
#
#  ============ NINE-SLICE, AND WHY IT IS THE WHOLE POINT ============
#
#  A window is not one picture. If it were, a wide window would be a stretched
#  picture with oval corners. So an image is cut into nine: four corners that
#  never stretch, four edges that stretch one way, and a middle that stretches
#  both. `Slice` is how far in the cuts are.
#
#      Slice 6, on a 32 x 32 image:
#
#        +---+--------+---+      the 6px corners keep their shape
#        | 6 |   20   | 6 |      the top and bottom edges stretch sideways
#        +---+--------+---+      the left and right stretch up and down
#        |   |        |   |      the middle stretches both ways
#
#  So ONE 32 x 32 PNG draws every window in the game at every size.
#
#  ============ THE IMAGE IS TINTED ============
#
#  This is the trick that makes one image enough. `panel_style()` is called
#  with a colour by every screen in the game — a blue panel here, a warm one
#  there, a locked grey one over there — and those calls are not going away.
#  So the image is drawn MODULATED by that colour: draw one neutral grey
#  panel and it arrives in every screen wearing that screen's own colour.
#
#  Draw it light and desaturated. A dark image cannot be tinted brighter.
#
#  ============ AND IT SKINS SCENES NOBODY TOUCHED ============
#
#  `godot_theme()` builds a real Godot Theme from these rows and it is set on
#  the root window, so EVERY Button, Panel, Label and ProgressBar in every
#  .tscn in the project picks it up — including ones built in the editor that
#  never call MenuSupport at all. That is what makes this one file rather
#  than thirty-six.
#
#  ============ THE PALETTE ROWS ============
#
#  Rows whose Element starts with `colour ` set the base palette — only their
#  Fill is read. They are the shipped look. **The Colour tab of Settings
#  still wins**, because a colour-blind or high-contrast palette is a need
#  rather than a preference, and a designer's palette must not be able to
#  take it away.
#
#  ============ NOTHING BREAKS WHILE IT IS EMPTY ============
#
#  A missing file, a missing image, a colour it cannot read: every one of
#  them falls back to what the game looked like before this existed. You can
#  draw one button today and the rest next month.
# =============================================================

const FILE := "res://data/Theme.csv"
## Where a 9-slice image is looked for, in order. The first is the tidy home.
const IMAGE_DIRS: Array[String] = ["res://assets/ui/", "res://assets/menu/", "res://assets/"]
const FONT_DIRS: Array[String] = ["res://assets/fonts/", "res://assets/"]
const IMAGE_EXTENSIONS: Array[String] = [".png", ".jpg", ".jpeg", ".webp"]
const FONT_EXTENSIONS: Array[String] = [".ttf", ".otf", ".woff2", ".woff"]

## Element -> State -> row. State "" is the ordinary one.
static var _rows: Dictionary = {}
static var _palette: Dictionary = {}
static var _problems: Array[String] = []
static var _loaded := false
## Built styles, keyed by element|state|tint. Built once, handed out for ever.
static var _styles: Dictionary = {}
static var _theme: Theme = null


static func forget() -> void:
	_rows = {}
	_palette = {}
	_problems = []
	_styles = {}
	_theme = null
	_loaded = false


## Throw away the built boxes and the Godot theme, but KEEP the rows. Used
## after changing a row in memory — by `tools/theme_shot.gd`, which swaps the
## images in and out to photograph both — and it is what a live reload would
## call if you ever want one.
static func restyle() -> void:
	_styles = {}
	_theme = null


static func load_it() -> void:
	if _loaded:
		return
	_loaded = true
	_rows = {}
	_palette = {}
	_problems = []

	for row in MenuSupport.read_csv(FILE):
		var element := MenuSupport.field(row, "Element").strip_edges().to_lower()
		if element == "":
			continue

		# ---- a palette row ----
		if element.begins_with("colour ") or element.begins_with("color "):
			var key := element.split(" ", false)[-1]
			var tint := _colour_of(MenuSupport.field(row, "Fill"), Color(0, 0, 0, 0))
			if tint.a <= 0.0:
				_problems.append("Palette row '%s' has no readable Fill." % element)
				continue
			_palette[key] = tint
			continue

		# ---- an element row ----
		var state := MenuSupport.field(row, "State").strip_edges().to_lower()
		if not _rows.has(element):
			_rows[element] = {}
		_rows[element][state] = {
			"image": MenuSupport.field(row, "Image").strip_edges(),
			"tint": MenuSupport.field(row, "Tint", "yes").strip_edges().to_lower(),
			"slice": MenuSupport.field(row, "Slice").strip_edges(),
			"fill": MenuSupport.field(row, "Fill").strip_edges(),
			"border": MenuSupport.field(row, "Border").strip_edges(),
			"border_width": MenuSupport.field_float(row, "Border Width", -1.0),
			"corner": MenuSupport.field_float(row, "Corner", -1.0),
			"pad_x": MenuSupport.field_float(row, "Pad X", -1.0),
			"pad_y": MenuSupport.field_float(row, "Pad Y", -1.0),
			"font": MenuSupport.field(row, "Font").strip_edges(),
			"size": MenuSupport.field_float(row, "Size", -1.0),
			"text": MenuSupport.field(row, "Text Colour").strip_edges(),
		}

		# An image that is not there is the one mistake worth saying out loud,
		# because the row looks right and the screen looks wrong.
		var wanted := String(_rows[element][state]["image"])
		if wanted != "" and image(wanted) == null:
			_problems.append("%s%s wants the image '%s', which is not in assets/ui/."
				% [element, "" if state == "" else " (" + state + ")", wanted])
		var face := String(_rows[element][state]["font"])
		if face != "" and font(face) == null:
			_problems.append("%s%s wants the font '%s', which is not in assets/fonts/."
				% [element, "" if state == "" else " (" + state + ")", face])

	if _rows.is_empty() and _palette.is_empty():
		print("[theme] No Theme.csv — the game draws itself the way it always did.")
	else:
		print("[theme] %d element(s) and %d palette colour(s) from Theme.csv."
			% [_rows.size(), _palette.size()])
	for problem in _problems:
		print("[theme] %s" % problem)


static func problems() -> Array[String]:
	load_it()
	return _problems


static func elements() -> Dictionary:
	load_it()
	return _rows


static func palette() -> Dictionary:
	load_it()
	return _palette


# =============================================================
#  READING ONE ROW
# =============================================================

## The row for this element and state, falling back to the element's ordinary
## state, then to `panel`, then to nothing. So `button:hover` with no row of
## its own looks like a button, and a brand new element looks like a panel.
static func row_for(element: String, state: String = "") -> Dictionary:
	load_it()
	var name_text := element.to_lower()
	if _rows.has(name_text):
		var states: Dictionary = _rows[name_text]
		if states.has(state):
			return states[state]
		if states.has(""):
			return states[""]
	if name_text != "panel" and _rows.has("panel"):
		return _rows["panel"].get("", {})
	return {}


static func number(element: String, key: String, fallback: float,
		state: String = "") -> float:
	var row := row_for(element, state)
	var value := float(row.get(key, -1.0))
	return fallback if value < 0.0 else value


static func text_colour(element: String, fallback: Color, state: String = "") -> Color:
	return _colour_of(String(row_for(element, state).get("text", "")), fallback)


static func font_size(element: String, fallback: int, state: String = "") -> int:
	return int(number(element, "size", float(fallback), state))


# =============================================================
#  BUILDING A BOX
# =============================================================

## The StyleBox for one element and state.
##
## `tint` is the colour the CALLER wanted. With an image it becomes the
## image's modulate — which is what lets one grey PNG be every panel in the
## game. Without one it is the fill, unless the row names its own.
static func style(element: String, state: String = "",
		tint: Color = Color(0, 0, 0, 0), edge: Color = Color(0, 0, 0, 0)) -> StyleBox:
	load_it()
	var key := "%s|%s|%s|%s" % [element, state, tint.to_html(), edge.to_html()]
	if _styles.has(key):
		return _styles[key]

	var row := row_for(element, state)
	var made: StyleBox = _build(row, tint, edge)
	_styles[key] = made
	return made


static func _build(row: Dictionary, tint: Color, edge: Color) -> StyleBox:
	var pad_x := float(row.get("pad_x", 8.0))
	var pad_y := float(row.get("pad_y", 6.0))
	if pad_x < 0.0:
		pad_x = 8.0
	if pad_y < 0.0:
		pad_y = 6.0

	var art: Texture2D = image(String(row.get("image", "")))
	if art != null:
		var boxed := StyleBoxTexture.new()
		boxed.texture = art
		var cuts := _slice_of(String(row.get("slice", "")), art)
		boxed.texture_margin_left = cuts.x
		boxed.texture_margin_top = cuts.y
		boxed.texture_margin_right = cuts.z
		boxed.texture_margin_bottom = cuts.w
		# ============ THE TINT, AND WHEN TO TURN IT OFF ============
		#
		# Each screen already asks for its own colour and those calls are not
		# going away, so by default the image WEARS it: one light grey PNG
		# becomes every panel in the game in that panel's own colour.
		#
		# The catch is worth being honest about, because it will bite you the
		# first afternoon you spend drawing one. Tinting MULTIPLIES. A panel
		# colour of #23262f is dark, so whatever you drew comes out darker —
		# which means the difference between the lightest and darkest parts
		# of your image survives only in proportion. Draw it light and
		# desaturated, and keep the shape in the ALPHA rather than in the
		# brightness.
		#
		# `Tint` = no in the row hands the image over untouched, exactly as
		# you drew it. You then need one image per look instead of one for
		# all of them — which is the right trade the moment you are drawing a
		# finished frame rather than a tintable blank.
		var wears_it := String(row.get("tint", "yes")) != "no"
		boxed.modulate_color = tint if (wears_it and tint.a > 0.0) else Color.WHITE
		boxed.content_margin_left = pad_x
		boxed.content_margin_right = pad_x
		boxed.content_margin_top = pad_y
		boxed.content_margin_bottom = pad_y
		return boxed

	var flat := StyleBoxFlat.new()
	flat.bg_color = tint if tint.a > 0.0 else _colour_of(String(row.get("fill", "")), Color(0, 0, 0, 0))

	var corner := float(row.get("corner", 6.0))
	if corner < 0.0:
		corner = 6.0
	flat.corner_radius_top_left = int(corner)
	flat.corner_radius_top_right = int(corner)
	flat.corner_radius_bottom_left = int(corner)
	flat.corner_radius_bottom_right = int(corner)

	flat.content_margin_left = pad_x
	flat.content_margin_right = pad_x
	flat.content_margin_top = pad_y
	flat.content_margin_bottom = pad_y

	var line := edge if edge.a > 0.0 else _colour_of(String(row.get("border", "")), Color(0, 0, 0, 0))
	var thick := float(row.get("border_width", 2.0))
	if thick < 0.0:
		thick = 2.0
	if line.a > 0.0 and thick > 0.0:
		flat.border_width_left = int(thick)
		flat.border_width_right = int(thick)
		flat.border_width_top = int(thick)
		flat.border_width_bottom = int(thick)
		flat.border_color = line
	return flat


## `Slice` is one number for all four sides, or four — left top right bottom.
## A blank one is a quarter of the image, which is right for most small tiles
## and is at least never zero.
static func _slice_of(text: String, art: Texture2D) -> Vector4:
	var words := text.split(" ", false)
	if words.size() >= 4:
		return Vector4(float(words[0]), float(words[1]), float(words[2]), float(words[3]))
	if words.size() >= 1 and String(words[0]).is_valid_float():
		var all := float(words[0])
		return Vector4(all, all, all, all)
	var quarter := minf(art.get_width(), art.get_height()) * 0.25
	return Vector4(quarter, quarter, quarter, quarter)


# =============================================================
#  FINDING FILES
# =============================================================

static var _image_cache: Dictionary = {}

static func image(file_name: String) -> Texture2D:
	var clean := file_name.strip_edges()
	if clean == "":
		return null
	if _image_cache.has(clean):
		return _image_cache[clean]
	var found: Texture2D = _look_for(clean, IMAGE_DIRS, IMAGE_EXTENSIONS) as Texture2D
	_image_cache[clean] = found
	return found


static var _font_cache: Dictionary = {}

static func font(file_name: String) -> Font:
	var clean := file_name.strip_edges()
	if clean == "":
		return null
	if _font_cache.has(clean):
		return _font_cache[clean]
	var found: Font = _look_for(clean, FONT_DIRS, FONT_EXTENSIONS) as Font
	_font_cache[clean] = found
	return found


static func _look_for(clean: String, folders: Array[String],
		extensions: Array[String]) -> Resource:
	if clean.begins_with("res://"):
		return load(clean) if ResourceLoader.exists(clean) else null
	var names: Array[String] = [clean]
	if not clean.contains("."):
		for extension in extensions:
			names.append(clean + extension)
	for folder in folders:
		for candidate in names:
			var path: String = folder + candidate
			if ResourceLoader.exists(path):
				return load(path)
	return null


static func _colour_of(text: String, fallback: Color) -> Color:
	var clean := text.strip_edges()
	if clean == "":
		return fallback
	if not clean.begins_with("#"):
		clean = "#" + clean
	return Color.html(clean) if Color.html_is_valid(clean) else fallback


# =============================================================
#  THE PALETTE
# =============================================================

## Write the palette rows into MenuSupport, which is where every screen reads
## its colours from.
##
## CALLED BEFORE the Colour tab's palette, never after — see game_settings.gd.
## A designer's palette is the shipped look; a colour-blind palette is a need,
## and a need has to be able to win.
static func apply_palette() -> void:
	load_it()
	for key in _palette:
		var tint: Color = _palette[key]
		match String(key):
			"accent": MenuSupport.COLOUR_ACCENT = tint
			"background": MenuSupport.COLOUR_BACKGROUND = tint
			"panel": MenuSupport.COLOUR_PANEL = tint
			"slot_empty": MenuSupport.COLOUR_SLOT_EMPTY = tint
			"locked": MenuSupport.COLOUR_LOCKED = tint
			"text": MenuSupport.COLOUR_TEXT = tint
			"text_dim": MenuSupport.COLOUR_TEXT_DIM = tint
			"attack": MenuSupport.COLOUR_ATTACK = tint
			"defend": MenuSupport.COLOUR_DEFEND = tint
			"tier_1": MenuSupport.TIER_COLOURS[0] = tint
			"tier_2": MenuSupport.TIER_COLOURS[1] = tint
			"tier_3": MenuSupport.TIER_COLOURS[2] = tint
			"tier_4": MenuSupport.TIER_COLOURS[3] = tint
			_:
				pass   # a name nobody reads; harmless, and listed by the checker


# =============================================================
#  THE REAL GODOT THEME
#
#  This is the half that reaches the scenes nobody has touched. Set on the
#  root window, it is inherited by every Control in the project — including
#  the buttons laid out by hand in .tscn files that never call MenuSupport.
# =============================================================

static func godot_theme() -> Theme:
	load_it()
	if _theme != null:
		return _theme

	var made := Theme.new()
	var body_font := font(String(row_for("body").get("font", "")))
	var body_size := font_size("body", 16)
	if body_font != null:
		made.default_font = body_font
	made.default_font_size = body_size

	# ---- buttons, in all five states ----
	made.set_stylebox("normal", "Button", style("button"))
	made.set_stylebox("hover", "Button", style("button", "hover"))
	made.set_stylebox("pressed", "Button", style("button", "pressed"))
	made.set_stylebox("disabled", "Button", style("button", "disabled"))
	made.set_stylebox("focus", "Button", style("button", "focus"))
	made.set_color("font_color", "Button", text_colour("button", MenuSupport.COLOUR_TEXT))
	made.set_color("font_hover_color", "Button",
		text_colour("button", MenuSupport.COLOUR_TEXT, "hover"))
	made.set_color("font_pressed_color", "Button",
		text_colour("button", MenuSupport.COLOUR_ACCENT, "pressed"))
	made.set_color("font_disabled_color", "Button",
		text_colour("button", MenuSupport.COLOUR_TEXT_DIM, "disabled"))
	made.set_font_size("font_size", "Button", font_size("body", body_size))

	# ---- boxes ----
	made.set_stylebox("panel", "PanelContainer", style("panel"))
	made.set_stylebox("panel", "Panel", style("panel"))
	made.set_stylebox("panel", "PopupPanel", style("window"))
	made.set_stylebox("panel", "TooltipPanel", style("tooltip"))

	# ---- words ----
	made.set_color("font_color", "Label", text_colour("body", MenuSupport.COLOUR_TEXT))
	made.set_font_size("font_size", "Label", font_size("body", body_size))

	# ---- bars ----
	made.set_stylebox("background", "ProgressBar", style("bar_back"))
	made.set_stylebox("fill", "ProgressBar", style("bar_fill"))

	# ---- a line between things ----
	made.set_stylebox("separator", "HSeparator", style("divider"))
	made.set_stylebox("separator", "VSeparator", style("divider"))

	_theme = made
	return _theme


## Put the skin on. Called once a screen opens, from MenuEscape.install(),
## and from the match, so nothing has to remember to do it.
static func dress(tree: SceneTree) -> void:
	if tree == null or tree.root == null:
		return
	load_it()
	if _rows.is_empty():
		return
	var wanted := godot_theme()
	if tree.root.theme != wanted:
		tree.root.theme = wanted
	_dev_strip(tree)


## ============ THE RED STRIP ============
##
## It hangs off dressing the screen because dressing the screen is the one
## thing EVERY screen in the game does — MenuEscape.install() calls it on the
## way in and the match calls it in _ready(). So there is one place that puts
## it up and no screen has to remember to.
##
## It is parented to the ROOT and not to a screen, so changing scene does not
## take it away: there is no moment where dev mode is on and nothing says so.
static func _dev_strip(tree: SceneTree) -> void:
	var db := CardDatabase.get_db()
	var want := DevMode.on(db) and (db == null or db.tune_bool("dev_banner", true))
	var found := tree.root.get_node_or_null("DevStrip")

	if not want:
		if found != null:
			found.queue_free()
		return
	if found != null:
		return

	var layer := CanvasLayer.new()
	layer.name = "DevStrip"
	# ABOVE EVERYTHING. A window, a dialogue box and the pause menu all sit
	# under this, because the one thing it must never do is be hidden.
	layer.layer = 200
	tree.root.add_child(layer)

	var strip := ColorRect.new()
	strip.color = Color(0.78, 0.16, 0.16, 0.92)
	strip.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	strip.offset_bottom = 22.0
	# IT DOES NOT EAT CLICKS. It covers the top of every screen and a button
	# that happens to be under it still has to work.
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(strip)

	var says := Label.new()
	says.text = "DEV MODE — this build has the developer's door open"
	says.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	says.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	says.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	says.add_theme_font_size_override("font_size", 12)
	says.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	says.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(says)
