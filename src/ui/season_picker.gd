class_name SeasonPicker
extends Control

# =============================================================
#  SEASONS — the shelf of competitions
#
#  Laid out like the talent tree: a tile per competition, joined by lines,
#  most of them locked. Clicking an open one starts playing it and opens the
#  table you already know.
#
#  ============ IT IS ALL res://data/Seasons.csv ============
#
#  Every tile, where it sits, what locks it and what it is called comes from
#  that spreadsheet — see season_book.gd for the columns. Add a row and a
#  tile appears; put it on Row 4 and the shelf grows a fourth row to hold it.
#  There is no limit and nothing here to edit.
#
#  ============ WHAT A LOCKED TILE DOES ============
#
#  It says what would open it, in the words of your Requires column, and it
#  cannot be clicked. That is the same treatment a locked building gets at
#  the base and a locked class gets on the class picker — one rule, learnt
#  once.
# =============================================================

const TILE := Vector2(230.0, 250.0)
const GAP := Vector2(34.0, 40.0)

var db: CardDatabase
var state: GameState
var book: SeasonBook

var _canvas: Control
var _detail: Label

## ============ WHERE EVERY TILE ACTUALLY SITS ============
##
## Worked out in _place_tiles() and read by everything else, including the
## joining lines. It is a dictionary rather than a sum done twice because the
## lines MUST agree with the tiles — when they were both working it out
## separately, one of them was always wrong after a resize.
##
## Season id -> the top-left corner of its tile.
var _places: Dictionary = {}

## Season id -> its Button, so a resize can move them without rebuilding.
var _tiles: Dictionary = {}
var _placing := false


func _ready() -> void:
	db = CardDatabase.get_db()
	state = GameState.fetch(get_tree())
	book = SeasonBook.get_db()
	MenuEscape.install(self)
	_build()


# =============================================================
#  LAYOUT
# =============================================================

func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = MenuSupport.COLOUR_BACKGROUND
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 36)
	margin.add_theme_constant_override("margin_right", 36)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 22)
	add_child(margin)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	margin.add_child(page)

	page.add_child(MenuSupport.heading(Loc.text("seasons", "SEASONS"), 34,
		MenuSupport.COLOUR_ACCENT))
	page.add_child(MenuSupport.heading(
		"Every competition in Seasons.csv. Pick one and its table opens.",
		14, MenuSupport.COLOUR_TEXT_DIM))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(scroll)

	# A plain Control rather than a container, because the tiles are placed
	# by their Row and Column columns and the joining lines are drawn between
	# them — neither of which a GridContainer would allow.
	_canvas = Control.new()
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(_canvas)
	_canvas.draw.connect(_draw_links)
	# CENTRING DEPENDS ON HOW WIDE THE SHELF IS, and nothing knows that until
	# Godot has laid the screen out — which is after this function has
	# finished. So the tiles are re-placed every time the canvas changes size:
	# once on the first frame, and again whenever the window is resized.
	_canvas.resized.connect(_place_tiles)

	_fill()

	# --- the standard footer, Back on the left like every other screen ---
	_detail = Label.new()
	var footer := MenuSupport.footer_bar(self, func() -> void:
		state.save_to_disk()
		ScenePaths.go_back(get_tree(), ScenePaths.BASE))
	footer.add_child(MenuSupport.footer_gap(_detail))
	page.add_child(footer)


func _fill() -> void:
	for child in _canvas.get_children():
		child.queue_free()

	# The canvas is sized from the furthest tile in _place_tiles(), so the
	# shelf grows as you add rows and the scroll bar appears on its own.
	_tiles.clear()
	for entry in book.seasons:
		var button := _tile(entry)
		_tiles[String(entry["id"])] = button
		_canvas.add_child(button)
	_place_tiles()


# =============================================================
#  CENTRING THE SHELF
#
#  ============ WHAT WAS WRONG ============
#
#  Tiles were placed straight from their Column: column 0 hard against the
#  left edge, column 1 beside it, and so on. With two seasons the shelf sat
#  in the left-hand third of the screen with a field of empty space beside
#  it, and it read as a mistake rather than as a layout.
#
#  ============ WHAT HAPPENS NOW ============
#
#  EVERY ROW IS CENTRED ON THE SCREEN, and the Column column decides the
#  ORDER and the SPACING within that row rather than the absolute position.
#  So three seasons side by side sit evenly across the middle; four do the
#  same and simply take more of the width; one sits in the centre on its own.
#
#  GAPS IN YOUR COLUMN NUMBERS STILL MEAN SOMETHING. A row using columns 0
#  and 2 keeps the hole in the middle, because the spacing is measured from
#  the row's own leftmost tile. That is what lets a branch fork and rejoin
#  and still look like a chart.
#
#  You do not have to renumber anything to get this. Rows 1, 2 and 3 of
#  Seasons.csv laid out as you already have them will simply be centred.
# =============================================================

## Put every tile where it belongs, and remember where that was.
##
## Called on the first layout and on every resize. It never creates or
## destroys anything, so it is cheap enough to run as often as it likes.
func _place_tiles() -> void:
	# A GUARD, because this function sets the canvas's minimum size and the
	# canvas is what calls it. Godot lays out on the next frame rather than
	# inside the assignment, so this should never actually trigger — it is
	# here so that a future change to either side cannot lock the game up.
	if _placing:
		return
	_placing = true
	_places.clear()
	if book == null:
		_placing = false
		return

	# --- how wide is each row, and where does it start? ---
	var lowest_column: Dictionary = {}   # row -> its leftmost Column
	var highest_column: Dictionary = {}  # row -> its rightmost Column
	var tallest := 0
	for entry in book.seasons:
		var row := int(entry["row"])
		var column := int(entry["column"])
		tallest = maxi(tallest, row)
		if not lowest_column.has(row):
			lowest_column[row] = column
			highest_column[row] = column
		lowest_column[row] = mini(int(lowest_column[row]), column)
		highest_column[row] = maxi(int(highest_column[row]), column)

	# THE WIDTH TO CENTRE IN is whatever the canvas actually has, and never
	# less than the widest row — otherwise a shelf too wide for the window
	# would be pushed off the left edge instead of scrolling.
	var widest_row := 0.0
	for row in lowest_column.keys():
		widest_row = maxf(widest_row, _row_span(
			int(lowest_column[row]), int(highest_column[row])))
	var width := maxf(_canvas.size.x, widest_row + GAP.x * 2.0)

	_canvas.custom_minimum_size = Vector2(
		widest_row + GAP.x * 2.0,
		float(tallest + 1) * (TILE.y + GAP.y) + GAP.y)

	for entry in book.seasons:
		var row := int(entry["row"])
		var span := _row_span(int(lowest_column[row]), int(highest_column[row]))
		var left := (width - span) * 0.5
		var step := float(int(entry["column"]) - int(lowest_column[row]))
		var at := Vector2(
			left + step * (TILE.x + GAP.x),
			GAP.y + float(row) * (TILE.y + GAP.y))
		_places[String(entry["id"])] = at
		var button := _tiles.get(String(entry["id"]), null) as Button
		if button != null and is_instance_valid(button):
			button.position = at

	_canvas.queue_redraw()
	_placing = false


## How wide a row is, from its leftmost Column to its rightmost.
func _row_span(first: int, last: int) -> float:
	return float(last - first) * (TILE.x + GAP.x) + TILE.x


## Where a tile's top-left corner ended up. Worked out once in
## _place_tiles(), so the tiles and the joining lines can never disagree.
func _spot(entry: Dictionary) -> Vector2:
	return _places.get(String(entry.get("id", "")), Vector2.ZERO)


# =============================================================
#  ONE TILE
# =============================================================

func _tile(entry: Dictionary) -> Control:
	var why := SeasonBook.locked_reason(entry, state)
	var open_now := why == ""
	var playing := SeasonBook.chosen_id() == String(entry["id"])

	var button := Button.new()
	button.position = _spot(entry)
	button.custom_minimum_size = TILE
	button.size = TILE
	button.disabled = not open_now
	button.focus_mode = Control.FOCUS_ALL if open_now else Control.FOCUS_NONE

	var edge: Color = entry["colour"]
	if playing:
		edge = MenuSupport.COLOUR_ACCENT
	elif not open_now:
		edge = MenuSupport.COLOUR_SLOT_EMPTY
	button.add_theme_stylebox_override("normal", MenuSupport.panel_style(
		MenuSupport.COLOUR_PANEL if open_now else MenuSupport.COLOUR_BACKGROUND, edge))
	button.add_theme_stylebox_override("hover", MenuSupport.panel_style(
		MenuSupport.COLOUR_SLOT_EMPTY, MenuSupport.COLOUR_ACCENT))
	button.add_theme_stylebox_override("disabled", MenuSupport.panel_style(
		MenuSupport.COLOUR_BACKGROUND, MenuSupport.COLOUR_SLOT_EMPTY))
	button.add_theme_stylebox_override("focus", MenuSupport.focus_style())

	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 4)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(column)

	# --- the crest: art if you have drawn one, a shield if not ---
	var art := MenuSupport.icon_texture(String(entry["art"]))
	if art != null:
		var picture := TextureRect.new()
		picture.texture = art
		picture.custom_minimum_size = Vector2(0, 118)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not open_now:
			picture.modulate = Color(0.32, 0.32, 0.38)
		column.add_child(picture)
	else:
		var crest := Control.new()
		crest.custom_minimum_size = Vector2(0, 118)
		crest.mouse_filter = Control.MOUSE_FILTER_IGNORE
		crest.draw.connect(func() -> void:
			SeasonBook.draw_crest(crest, entry,
				Rect2(Vector2.ZERO, crest.size), open_now))
		column.add_child(crest)

	var title := Label.new()
	title.text = String(entry["name"])
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color",
		MenuSupport.COLOUR_TEXT if open_now else MenuSupport.COLOUR_TEXT_DIM)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(title)

	var under := Label.new()
	if not open_now:
		under.text = "🔒  " + why
		under.add_theme_color_override("font_color", Color(0.86, 0.62, 0.45))
	elif playing:
		under.text = "You are playing this"
		under.add_theme_color_override("font_color", MenuSupport.COLOUR_ACCENT)
	else:
		var n := SeasonBook.match_count(entry)
		under.text = "%d fixture%s" % [n, "" if n == 1 else "s"]
		under.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	under.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	under.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	under.add_theme_font_size_override("font_size", 12)
	under.size_flags_vertical = Control.SIZE_EXPAND_FILL
	under.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(under)

	button.tooltip_text = String(entry["description"])
	button.mouse_entered.connect(func() -> void:
		_detail.text = String(entry["description"]))
	button.focus_entered.connect(func() -> void:
		_detail.text = String(entry["description"]))
	if open_now:
		button.pressed.connect(_enter.bind(entry))
	return button


func _enter(entry: Dictionary) -> void:
	SeasonBook.choose(state, String(entry["id"]))
	ScenePaths.go_to(get_tree(), ScenePaths.SEASON)


# =============================================================
#  THE JOINING LINES
#
#  Drawn from the After column, so the shelf reads as a path rather than as
#  a pile of tiles. Decoration only — Requires is what actually locks a
#  season, and a tile with no After is simply not joined to anything.
# =============================================================

func _draw_links() -> void:
	for entry in book.seasons:
		var after := String(entry["after"]).strip_edges()
		if after == "":
			continue
		var parent := book.find(after)
		if parent.is_empty():
			continue

		var from := _spot(parent) + Vector2(TILE.x * 0.5, TILE.y)
		var to := _spot(entry) + Vector2(TILE.x * 0.5, 0.0)
		var open_now := SeasonBook.locked_reason(entry, state) == ""
		var tint := MenuSupport.COLOUR_ACCENT if open_now \
			else MenuSupport.COLOUR_SLOT_EMPTY

		# An elbow rather than a diagonal: down out of the parent, across,
		# then down into the child. Reads as a chart, not as a cobweb.
		var midway := (from.y + to.y) * 0.5
		_canvas.draw_polyline(PackedVector2Array([
			from, Vector2(from.x, midway), Vector2(to.x, midway), to]),
			tint, 3.0, true)
