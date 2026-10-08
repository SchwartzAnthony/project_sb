class_name BreweryScreen
extends Control

# =============================================================
#  THE BREWERY — the map, on top of the chain
#
#  ============ WHAT YOU ASKED FOR ============
#
#  "The Brewery is a map with six sections. Each section must be unlocked.
#   At the top of the map there is a resources window and a brewery-materials
#   window."
#
#  So: two windows pinned along the top, and a yard underneath with the six
#  sections standing in it.
#
#      RESOURCES           what comes from outside — wheat, water, germs,
#                          hops, yeast — and the TOOLS, which are needed and
#                          not used up
#      BREWERY MATERIALS   what the Brewery itself makes: malt, mash, wort,
#                          brew, barrel, bottle
#
#  That split is not a decision this screen makes. It is the `Kind` column of
#  BreweryResources.csv: `raw` and `tool` go left, `made` goes right. Add a
#  resource tomorrow and it appears in the right window with no edit here.
#
#  ============ THE YARD IS NOT LAID OUT BY HAND EITHER ============
#
#  Every section has an X and a Y in BrewerySections.csv, as a fraction of
#  the yard — 0.5, 0.5 is the middle. The same two columns Buildings.csv
#  uses, so moving the Mill is a number you already know how to change.
#
#  ============ WHAT A SECTION LOOKS LIKE ============
#
#      LOCKED      greyed, and it SAYS WHAT WOULD OPEN IT. A locked door
#                  with no sign on it is just a wall
#      READY       its worker's name, what it takes, what it makes, and a
#                  button
#      SHORT       what you are missing, in words: "Germs 0/1"
#      WORKING     the cellar. How many turns until the barrel comes out
#
#  ============ WHAT IT DOES NOT DO ============
#
#  The five brewing mini-games. A mini-game decides how WELL a section runs;
#  BreweryBook decides what it costs and what it gives. Neither needs the
#  other, and this screen will not change when they arrive — a mini-game will
#  sit between pressing the button and the work being done.
# =============================================================

const SECTION_SIZE := Vector2(250.0, 172.0)
const ART_DIRS: Array[String] = ["res://assets/brewery/", "res://assets/base/", "res://assets/"]

var db: CardDatabase
var state: GameState

var _world: Control
var _resource_row: HBoxContainer
var _material_row: HBoxContainer
var _status: Label


func _ready() -> void:
	# Escape, controller navigation, key bindings, settings and language, all
	# from this one line. See menu_escape.gd.
	# THE WINDOW DOES ALL THREE when this screen is opened over the base:
	# the background, the Back button and Escape. See base_window.gd.
	var windowed := MenuSupport.in_a_window(self)
	if not windowed:
		MenuEscape.install(self)
		# A WINDOW SIZES THIS SCREEN ITSELF. Pinning it to the whole viewport
		# from in here would fight the container it has been put in.
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	db = CardDatabase.get_db()
	state = GameState.fetch(get_tree())
	# YOUR OPENING STOCK, ONCE PER SAVE. It leaves a flag behind, so walking
	# out and back in is not a refill — see brewery_book.gd.
	BreweryBook.stock_a_new_game(state)

	_build_chrome()
	_rebuild()
	# ROUND AN: the Head Coach's Guide.csv rows for the Brewery.
	(func() -> void: Guide.check(self, "brewery", state)).call_deferred()


# =============================================================
#  CHROME
# =============================================================

## ============ THE BREWERY'S OWN PICTURE (round AN, your note) ============
##
## The same background as the Brewer's scene (Dialogue.csv brewery-intro):
## the StoryArt.csv rows whose ID is Tuning.csv `brewery_background`
## (default `brewery`), stacked back to front, under a see-through black
## sheet so the windows read on it. No rows, or no picture yet = the screen
## looks exactly as it did before.
func _build_backdrop() -> void:
	StoryArt.add_backdrop(self, db.tune_text("brewery_background", "brewery"),
		db.tune_float("brewery_background_shade", 0.45))


func _build_chrome() -> void:
	# NO BACKGROUND OF ITS OWN IN A WINDOW — the window has one, and a second
	# opaque rectangle would paint over the dimmed base behind it.
	if not MenuSupport.in_a_window(self):
		var fill := ColorRect.new()
		fill.color = MenuSupport.COLOUR_BACKGROUND
		fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(fill)

	_build_backdrop()

	var title := MenuSupport.heading(
		Loc.text("brewery_title", "THE BREWERY"), 32, MenuSupport.COLOUR_ACCENT)
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_left = 36.0
	title.offset_top = 18.0
	title.offset_bottom = 58.0
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# THE WINDOW'S TITLE BAR ALREADY SAYS THIS. Hidden rather than removed,
	# so the layout below keeps the breathing room it was drawn with.
	title.visible = not MenuSupport.in_a_window(self)
	add_child(title)

	# ---- the two windows, side by side along the top ----
	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 36.0
	top.offset_right = -36.0
	top.offset_top = 62.0
	top.offset_bottom = 176.0
	top.add_theme_constant_override("separation", 20)
	add_child(top)

	_resource_row = _window_into(top, Loc.text("brewery_resources", "RESOURCES"))
	_material_row = _window_into(top, Loc.text("brewery_materials", "BREWERY MATERIALS"))

	# ---- the yard ----
	_world = Control.new()
	_world.name = "Yard"
	_world.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_world.offset_top = 186.0
	_world.offset_left = 24.0
	_world.offset_right = -24.0
	_world.offset_bottom = -74.0
	_world.clip_contents = true
	add_child(_world)
	_world.resized.connect(_rebuild)

	_status = Label.new()
	_status.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_status.offset_left = 36.0
	_status.offset_right = -260.0
	_status.offset_top = -64.0
	_status.offset_bottom = -18.0
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 16)
	_status.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_status)

	var back := MenuSupport.icon_button("◇", Loc.text("back_to_base", "Back to the base"),
		Vector2(200, 44))
	back.add_theme_font_size_override("font_size", 16)
	back.add_theme_stylebox_override("normal",
		MenuSupport.panel_style(MenuSupport.COLOUR_PANEL, MenuSupport.COLOUR_ACCENT))
	back.add_theme_stylebox_override("hover",
		MenuSupport.panel_style(MenuSupport.COLOUR_SLOT_EMPTY, MenuSupport.COLOUR_ACCENT))
	back.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	back.offset_left = -230.0
	back.offset_top = -66.0
	back.offset_right = -30.0
	back.offset_bottom = -22.0
	# THE WINDOW HAS A ✕. Two ways out of one screen is one too many.
	back.visible = not MenuSupport.in_a_window(self)
	back.pressed.connect(func() -> void:
		state.save_to_disk()
		ScenePaths.go_back(get_tree(), ScenePaths.BASE))
	add_child(back)


## One of the two windows. Returns the row its tiles go in.
func _window_into(parent: Control, words: String) -> HBoxContainer:
	var frame := PanelContainer.new()
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.add_theme_stylebox_override("panel", MenuSupport.styled(
		"window", "", MenuSupport.COLOUR_PANEL, MenuSupport.COLOUR_ACCENT))
	parent.add_child(frame)

	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right"]:
		pad.add_theme_constant_override(side, 14)
	for side in ["margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 10)
	frame.add_child(pad)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	pad.add_child(column)

	var heading := MenuSupport.heading(words, 16, MenuSupport.COLOUR_ACCENT)
	column.add_child(heading)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	column.add_child(row)
	return row


# =============================================================
#  DRAWING IT
# =============================================================

func _rebuild() -> void:
	_fill_windows()

	if _world == null:
		return
	for child in _world.get_children():
		child.queue_free()

	var sections := BreweryBook.sections()
	if sections.is_empty():
		var nothing := Label.new()
		nothing.text = "No BrewerySections.csv — the yard is empty."
		nothing.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
		_world.add_child(nothing)
		return

	# THE CHAIN IS DRAWN BEFORE THE BUILDINGS, so the arrows sit under them.
	var lines := BreweryLines.new()
	lines.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.points = _line_points(sections)
	_world.add_child(lines)

	for section in sections:
		_world.add_child(_make_section(section))


## Where the chain runs, section 1 to section 6, in screen coordinates.
## It is drawn because the Order column is the thing the whole file turns on
## and a list of numbers does not look like an order.
func _line_points(sections: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for section in sections:
		out.append(_spot(section) + SECTION_SIZE * 0.5)
	return out


func _spot(section: Dictionary) -> Vector2:
	var area := _world.size
	if area.x < 2.0 or area.y < 2.0:
		area = get_viewport_rect().size
	return Vector2(
		clampf(area.x * float(section["x"]) - SECTION_SIZE.x * 0.5,
			4.0, maxf(area.x - SECTION_SIZE.x - 4.0, 4.0)),
		clampf(area.y * float(section["y"]) - SECTION_SIZE.y * 0.5,
			4.0, maxf(area.y - SECTION_SIZE.y - 4.0, 4.0)))


func _make_section(section: Dictionary) -> Control:
	var id_text := String(section["id"])
	var open := BreweryBook.is_open(id_text, state)
	var waiting := BreweryBook.is_waiting(id_text, state)
	var full := BreweryBook.is_full(id_text, state)
	var short := BreweryBook.missing(id_text, state)

	# ============ THE MACHINE IS THE BUTTON (round AN, your note) ============
	#
	# With its picture in assets/brewery/ (the Art column), a section is
	# drawn the way a building is on the base: the machine itself, clickable,
	# with its name on a see-through black plate underneath. No picture yet
	# = the old panel below, so nothing breaks while the art is drawn.
	var machine_art := _find_texture(String(section["art"]))
	if machine_art != null:
		return _make_machine(section, machine_art, open, waiting, full, short)

	var edge := MenuSupport.COLOUR_SLOT_EMPTY
	if open:
		edge = MenuSupport.COLOUR_DEFEND if full \
			else (MenuSupport.COLOUR_ATTACK if short.is_empty() else MenuSupport.COLOUR_TEXT_DIM)

	var frame := PanelContainer.new()
	frame.position = _spot(section)
	frame.custom_minimum_size = SECTION_SIZE
	frame.size = SECTION_SIZE
	frame.add_theme_stylebox_override("panel", MenuSupport.panel_style(
		MenuSupport.COLOUR_PANEL if open else MenuSupport.COLOUR_BACKGROUND, edge))

	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 10)
	frame.add_child(pad)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	pad.add_child(column)

	var heading := MenuSupport.heading("%d. %s" % [int(section["order"]), section["name"]],
		16, MenuSupport.COLOUR_TEXT if open else MenuSupport.COLOUR_TEXT_DIM)
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(heading)

	var art := _find_texture(String(section["art"]))
	if art != null:
		var picture := TextureRect.new()
		picture.texture = art
		picture.custom_minimum_size = Vector2(0, 56)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not open:
			picture.modulate = Color(0.35, 0.35, 0.40, 1.0)
		column.add_child(picture)

	# ---- LOCKED: say what would open it ----
	if not open:
		# THE SIGN ON THE DOOR NAMES THE ACHIEVEMENT, not the unlock. "Needs
		# Mill" tells you nothing you can act on; "Clean Sheet — win a match
		# without conceding" is a thing to go and do. See opened_by().
		var door := BreweryBook.opened_by(id_text, state)
		if door.is_empty():
			column.add_child(_small("LOCKED — " + DialogueGrammar.describe(String(section["needs"]))))
		else:
			var sign_label := MenuSupport.heading("LOCKED — %s" % door["name"],
				13, MenuSupport.COLOUR_ACCENT)
			sign_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			column.add_child(sign_label)
			column.add_child(_small(String(door["description"])))
		return frame

	column.add_child(_small("%s  ·  %s" % [section["worker"], _recipe_words(section)]))

	# ---- THE CELLAR: how many vats, how many working ----
	#
	# Shown whenever a section HAS more than one vat, even when they are all
	# idle, because "1 of 3 vats" is the line that tells you the other two
	# were worth unlocking.
	var vats := BreweryBook.batches_for(id_text, state)
	if waiting:
		column.add_child(_small("%d of %d vat(s) working — next out in %d turn(s). A turn is a fixture." % [
			BreweryBook.busy(id_text, state), vats,
			BreweryBook.turns_left(id_text, state)]))
	elif vats > 1:
		column.add_child(_small("%d vats, all idle." % vats))

	if full:
		return frame

	# ---- SHORT: name what is missing ----
	if not short.is_empty():
		column.add_child(_small("Short of: " + ", ".join(short)))
		return frame

	# ---- READY ----
	var button := Button.new()
	button.text = "WORK IT"
	button.custom_minimum_size = Vector2(0.0, 30.0)
	button.add_theme_stylebox_override("normal",
		MenuSupport.panel_style(MenuSupport.COLOUR_PANEL, MenuSupport.COLOUR_ATTACK))
	button.add_theme_stylebox_override("hover",
		MenuSupport.panel_style(MenuSupport.COLOUR_SLOT_EMPTY, MenuSupport.COLOUR_ATTACK))
	button.add_theme_stylebox_override("pressed",
		MenuSupport.panel_style(MenuSupport.COLOUR_SLOT_EMPTY, MenuSupport.COLOUR_ACCENT))
	button.add_theme_stylebox_override("focus", MenuSupport.focus_style())
	button.add_theme_color_override("font_color", MenuSupport.COLOUR_ATTACK)
	button.pressed.connect(_work.bind(id_text))
	column.add_child(button)
	return frame


func _make_machine(section: Dictionary, art: Texture2D, open: bool, waiting: bool,
		full: bool, short: Array) -> Control:
	var id_text := String(section["id"])
	# How big a machine is drawn: Tuning.csv brewery_machine_size (pixels).
	var big := float(section.get("size", 0.0))
	if big <= 0.0:
		big = db.tune_float("brewery_machine_size", 200.0)
	# THE SAME PICTURE IN A SMALLER ROOM. Sizes are written for the yard of
	# the full-screen Brewery; opened as a window over the base the yard is
	# smaller, so every machine shrinks by the same share and the pyramid
	# keeps its shape.
	var reference := db.tune_float("brewery_yard_height", 776.0)
	var area := _world.size.y if _world != null and _world.size.y > 2.0 else reference
	big *= clampf(area / maxf(reference, 1.0), 0.3, 1.0)
	var box := Vector2(maxf(SECTION_SIZE.x, big), big + 44.0)
	var holder := Control.new()
	# Centred where the panel's centre would be, so the X / Y columns and
	# the chain lines between sections still meet the machine.
	holder.position = _spot(section) + SECTION_SIZE * 0.5 - box * 0.5
	holder.size = box
	holder.custom_minimum_size = box

	# ============ STANDING ON ITS PALLET (round AN, your note) ============
	#
	# The FOOT is the spot on the ground the machine stands on. The pallet is
	# centred on it, and the machine's DRAWING - not its square canvas, which
	# has more empty space on one side than the other - is centred on it too,
	# with its bottom edge a little in front of the pallet's middle.
	var foot := Vector2(box.x * 0.5, big * db.tune_float("brewery_foot_height", 0.86))
	var pallet_art := _find_texture(db.tune_text("brewery_pallet", ""))
	var pallet_h := 0.0
	if pallet_art != null:
		var pallet_cut := _content_of(pallet_art)
		var pallet := TextureRect.new()
		pallet.texture = pallet_cut["texture"]
		pallet.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pallet.stretch_mode = TextureRect.STRETCH_SCALE
		pallet.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		pallet.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var used: Rect2 = pallet_cut["rect"]
		var wide := big * db.tune_float("brewery_pallet_width", 1.1)
		pallet_h = wide * used.size.y / maxf(used.size.x, 1.0)
		pallet.size = Vector2(wide, pallet_h)
		pallet.position = foot - pallet.size * 0.5
		holder.add_child(pallet)

	var ready := open and not full and short.is_empty()
	var cut := _content_of(art)
	var drawn: Rect2 = cut["rect"]
	var scale_by := big / maxf(float(art.get_width()), 1.0)
	var machine_size := drawn.size * scale_by
	var button := Button.new()
	button.flat = true
	# The picture fills the button exactly (a Button's own icon is shrunk by
	# the skin's margins, which is what pushed machines off their pallets).
	var picture := TextureRect.new()
	picture.texture = cut["texture"]
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_SCALE
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button.add_child(picture)
	button.size = machine_size
	# Centred on the MACHINE'S WEIGHT, not its outline: a crank handle or a
	# hop pole sticking out to one side would otherwise drag it off its
	# platform. BrewerySections.csv `Shift X` (picture pixels, + = right)
	# nudges it further by hand.
	var weight_x: float = cut["weight_x"]
	var shift := (weight_x - drawn.size.x * 0.5 - float(section.get("shift_x", 0.0))) * scale_by
	button.position = Vector2(foot.x - machine_size.x * 0.5 - shift,
		foot.y + pallet_h * db.tune_float("brewery_foot_forward", 0.15) - machine_size.y
		+ float(section.get("shift_y", 0.0)) * scale_by)
	button.focus_mode = Control.FOCUS_ALL
	# The tooltip STARTS WITH THE NAME, which is how Guide.csv's Highlight
	# column finds this machine ("Steeping Tank").
	button.tooltip_text = "%s: %s" % [section["name"], _recipe_words(section)]
	if not open:
		button.modulate = Color(0.35, 0.35, 0.40, 1.0)
	elif not ready:
		button.modulate = Color(0.75, 0.75, 0.75, 1.0)
	button.pressed.connect(func() -> void:
		if ready:
			_work(id_text)
		elif not open:
			var door := BreweryBook.opened_by(id_text, state)
			_say("%s is locked. %s" % [section["name"], String(door.get("description", DialogueGrammar.describe(String(section["needs"]))))], false)
		elif full:
			_say("%s is full - wait for the cellar." % section["name"], false)
		else:
			_say("%s is short of: %s" % [section["name"], ", ".join(short)], false))
	holder.add_child(button)

	# The name, and what it needs, on a see-through black plate.
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", TextBackdrop.plate())
	plate.anchor_left = 0.5
	plate.anchor_right = 0.5
	plate.anchor_top = 1.0
	plate.anchor_bottom = 1.0
	plate.offset_left = -130.0
	plate.offset_right = 130.0
	plate.offset_top = -44.0
	plate.z_index = 2      # names always on top of a neighbouring machine
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 0)
	plate.add_child(words)
	var title := MenuSupport.heading(String(section["name"]), 15,
		MenuSupport.COLOUR_TEXT if open else MenuSupport.COLOUR_TEXT_DIM)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	words.add_child(title)
	var line := ""
	if not open:
		var door := BreweryBook.opened_by(id_text, state)
		line = "LOCKED - " + String(door.get("name", "")) if not door.is_empty() else "LOCKED"
	elif waiting:
		line = "Working - %d turn(s)" % BreweryBook.turns_left(id_text, state)
	elif full:
		line = "Full"
	elif not short.is_empty():
		line = "Short of: " + ", ".join(short)
	else:
		line = "Click to work it"
	var under := _small(line)
	under.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	words.add_child(under)
	holder.add_child(plate)
	return holder


## The part of a picture that is actually drawn: {"texture", "rect"}. A
## PixelLab object sits on a square canvas with uneven empty space round it;
## centring the canvas puts the drawing off-centre, so we centre this.
var _cuts: Dictionary = {}

func _content_of(art: Texture2D) -> Dictionary:
	if _cuts.has(art):
		return _cuts[art]
	var rect := Rect2(Vector2.ZERO, art.get_size())
	var image := art.get_image()
	if image != null:
		if image.is_compressed():
			image.decompress()
		var used := image.get_used_rect()
		if used.size.x > 0 and used.size.y > 0:
			rect = Rect2(used)
	var piece := AtlasTexture.new()
	piece.atlas = art
	piece.region = rect
	# Where its weight sits across: the average x of every drawn pixel,
	# measured from the left of the drawn part.
	var weight_x := rect.size.x * 0.5
	if image != null:
		var total := 0.0
		var count := 0
		for y in range(int(rect.position.y), int(rect.end.y)):
			for x in range(int(rect.position.x), int(rect.end.x)):
				if image.get_pixel(x, y).a > 0.5:
					total += x - rect.position.x
					count += 1
		if count > 0:
			weight_x = total / count
	var out := {"texture": piece, "rect": rect, "weight_x": weight_x}
	_cuts[art] = out
	return out


## "Wheat, Water, Germs -> Malt", in the resources' display names.
func _recipe_words(section: Dictionary) -> String:
	var takes: Array[String] = []
	for key in section["takes"]:
		var res := BreweryBook.resource(String(key))
		var name_text := String(res["name"]) if not res.is_empty() else String(key)
		var many := int(section["takes"][key])
		takes.append(name_text if many == 1 else "%d %s" % [many, name_text])
	var made := BreweryBook.resource(String(section["makes"]))
	var made_text := String(made["name"]) if not made.is_empty() else String(section["makes"])
	if int(section["how_many"]) > 1:
		made_text = "%d %s" % [int(section["how_many"]), made_text]
	return "%s → %s" % [", ".join(takes), made_text]


# =============================================================
#  THE TWO WINDOWS
# =============================================================

func _fill_windows() -> void:
	for row in [_resource_row, _material_row]:
		if row == null:
			continue
		for child in row.get_children():
			child.queue_free()

	# THE SPLIT IS THE `Kind` COLUMN and nothing else. See the note at the top.
	for res in BreweryBook.resources():
		var kind := String(res["kind"])
		var row := _material_row if kind == "made" else _resource_row
		if row != null:
			row.add_child(_stock_tile(res))


func _stock_tile(res: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.tooltip_text = "%s — %s" % [res["name"],
		"equipment: needed, not used up" if bool(res["kept"]) else String(res["kind"])]

	var picture := MenuSupport.icon_texture(String(res["icon"]))
	if picture != null:
		var art := TextureRect.new()
		art.texture = picture
		art.custom_minimum_size = Vector2(34, 34)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(art)

	var name_label := Label.new()
	name_label.text = String(res["name"])
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	box.add_child(name_label)

	var have := BreweryBook.stock(String(res["id"]), state)
	var count := MenuSupport.heading(
		"✔" if bool(res["kept"]) and have > 0 else str(have), 19,
		MenuSupport.COLOUR_TEXT if have > 0 else MenuSupport.COLOUR_TEXT_DIM)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(count)
	return box


# =============================================================
#  WORKING A SECTION
# =============================================================

func _work(section_id: String) -> void:
	# ROUND AN: a BREWER works it — see brewer_book.gd and data/Brewers.csv.
	var result := BrewerBook.work(section_id, state, CardDatabase.get_db())
	if not bool(result["ok"]):
		_say(String(result["why"]), false)
		_rebuild()
		return

	var made := BreweryBook.resource(String(result["made"]))
	var made_text := String(made["name"]) if not made.is_empty() else String(result["made"])
	var who := String(result.get("brewer", ""))
	var crew := ("%s (%d%%)" % [who, int(result["chance"])]) if who != "" \
		else "Nobody free to brew it (%d%%)" % int(result.get("chance", 100))
	var bed := ("  %s rests %d fixture(s) in the Dorms." % [who, int(result["rest"])]) \
		if int(result.get("rest", 0)) > 0 else ""
	if bool(result.get("spoiled", false)):
		_say("SPOILED. %s - the batch went wrong and the ingredients are gone.%s" % [crew, bed], false)
	elif bool(result["waiting"]):
		_say("%s: into the cellar. %d %s in %d turn(s) — a turn is a fixture.%s"
			% [crew, int(result["many"]), made_text, int(result["turns"]), bed], true)
	else:
		_say("%s: %d %s.%s" % [crew, int(result["many"]), made_text, bed], true)

	state.save_to_disk()
	_rebuild()
	(func() -> void: Guide.check(self, "brewery", state)).call_deferred()


func _say(words: String, good: bool) -> void:
	_status.text = words
	_status.add_theme_color_override("font_color",
		MenuSupport.COLOUR_TEXT if good else Color(1.0, 0.72, 0.4))


# =============================================================
#  SMALL PIECES
# =============================================================

func _small(words: String) -> Label:
	var label := Label.new()
	label.text = words
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	return label


func _find_texture(file_name: String) -> Texture2D:
	if file_name.strip_edges() == "":
		return null
	for folder in ART_DIRS:
		var path := folder + file_name
		if ResourceLoader.exists(path):
			return load(path) as Texture2D
	return null


# =============================================================
#  THE ARROWS
#
#  A thin line from each section to the next, in Order. It is the only thing
#  on this screen that is drawn rather than laid out, and it earns that:
#  `Order` is the column the whole spreadsheet turns on — it decides what may
#  feed what — and a column of numbers does not look like an order.
# =============================================================

class BreweryLines extends Control:
	var points := PackedVector2Array()

	func _draw() -> void:
		if points.size() < 2:
			return
		var ink := MenuSupport.COLOUR_ACCENT
		ink.a = 0.30
		for i in range(1, points.size()):
			draw_line(points[i - 1], points[i], ink, 3.0, true)
			# A LITTLE ARROWHEAD, because a line between two buildings does
			# not say which way the barley is going.
			var way := (points[i] - points[i - 1]).normalized()
			var tip := points[i] - way * 26.0
			var side := Vector2(-way.y, way.x) * 8.0
			draw_line(tip, tip - way * 12.0 + side, ink, 3.0, true)
			draw_line(tip, tip - way * 12.0 - side, ink, 3.0, true)
