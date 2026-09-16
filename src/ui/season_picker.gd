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

	var widest := 0
	var tallest := 0
	for entry in book.seasons:
		widest = maxi(widest, int(entry["column"]))
		tallest = maxi(tallest, int(entry["row"]))

	# The canvas is sized from the furthest tile, so the shelf grows as you
	# add rows and the scroll bar appears on its own.
	_canvas.custom_minimum_size = Vector2(
		float(widest + 1) * (TILE.x + GAP.x) + GAP.x,
		float(tallest + 1) * (TILE.y + GAP.y) + GAP.y)

	for entry in book.seasons:
		_canvas.add_child(_tile(entry))
	_canvas.queue_redraw()


## Where a tile's top-left corner goes, from its Row and Column.
func _spot(entry: Dictionary) -> Vector2:
	return Vector2(
		GAP.x + float(int(entry["column"])) * (TILE.x + GAP.x),
		GAP.y + float(int(entry["row"])) * (TILE.y + GAP.y))


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
