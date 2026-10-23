class_name InventoryScreen
extends CanvasLayer

# =============================================================
#  THE INVENTORY — one bag, opened from everywhere
#
#  A window with up to three tabs and a grid of square buttons. Each button is the
#  thing's picture with how many you have in the corner; pointing at one
#  writes what it is in the panel underneath. Nothing is labelled, because
#  forty labelled tiles is a wall of words and forty pictures is a bag.
#
#      ITEMS      things you USE — a bottled brew, a bandage, smelling salts
#      RESOURCES  things you SPEND — reed, bog iron, coins
#      KEYS       things you HOLD — a key, a token, a letter
#
#  WHICH TABS SHOW is Tuning.csv `inventory_tabs`. Round AN took the Keys tab
#  out on 7 Oct and put it back on 8 Oct: the keys to the buildings and the
#  Brewery machines are bought at the Club House and are listed there.
#
#  Which tab a row lands in is decided by Items.csv: the `Tab` column if you
#  filled it in, worked out from `Kind` if you did not. See
#  AdventureDB.tab_of(), which is the only place that rule is written down.
#
#  ============ IT IS THE SAME WINDOW EVERYWHERE ============
#
#  The base, the Bounty Board, an Adventure fight and the match draft all
#  open THIS. They differ only in what a click means, and that is one
#  argument:
#
#      open(on, state, Use.NOTHING)   a reckoning. Nothing is clickable
#      open(on, state, Use.ITEM)      an item may be used — `used` fires
#      open(on, state, Use.ON_CARD)   pick something to use ON A CARD, for
#                                     the draft. `used` fires and the caller
#                                     applies it to the card it had in mind
#
#  WHAT IS CLICKABLE IS DECIDED BY THE `Tags` COLUMN, not by the screen —
#  `adventure_consume` out in a fight, `match_consume` on a card. Most things
#  have neither and are taken at the bar before the team sets off.
#
#  ============ WHY THERE IS NO SEPARATE KIT SCREEN ============
#
#  There used to be one, called YOUR KIT, that listed usable items as lines
#  of text. It showed a third of what you were carrying and it was the only
#  place in the game that looked like that. Everything it did this does.
# =============================================================

enum Use { NOTHING, ITEM, ON_CARD }

## Somebody pressed a thing they can use. `entry` is the row out of Items.csv
## with `held` on top of it — how many you are carrying.
signal used(entry: Dictionary)

const TAB_WORDS := {
	"items": "ITEMS",
	"resources": "RESOURCES",
	"keys": "KEYS",
}

## ROUND AN: only these item ids show (the tutorial). Empty = all.
var only_ids: Array = []
var state: GameState
var mode: int = Use.NOTHING
## Words under the title. The draft puts the card's name here, so it is
## obvious what the brew is about to be poured on.
var subtitle := ""

var _bag: Dictionary = {}
var _tab := "items"
var _grid: GridContainer
var _tab_buttons: Dictionary = {}
var _words: Label
var _title_line: Label


# =============================================================
#  OPENING IT
# =============================================================

## Build it, fill it and show it. Returns the screen so the caller can
## connect to `used` and, if it wants, put a line under the title.
static func open(on: Node, save: GameState, how: int = Use.NOTHING,
		under_title: String = "", only: Array = []) -> InventoryScreen:
	var made := InventoryScreen.new()
	made.name = "InventoryScreen"
	made.state = save
	made.mode = how
	made.subtitle = under_title
	made.only_ids = only
	on.add_child(made)
	return made


## The tile of this item, for the Head Coach's gold box. null = not shown.
func tile_for(item_id: String) -> Control:
	if _grid == null:
		return null
	for child in _grid.get_children():
		if child.has_meta("item_id") and String(child.get_meta("item_id")) == item_id \
				and not child.is_queued_for_deletion():
			return child as Control
	return null


func _ready() -> void:
	layer = 70
	_build()
	refresh()


func close() -> void:
	queue_free()


# =============================================================
#  BUILDING IT
# =============================================================

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.06, 0.74)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The dim catches clicks, so a stray click outside the window does not
	# land on the screen behind it.
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	if mat_look():
		_build_mat(dim)
		return

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -360.0
	panel.offset_right = 360.0
	panel.offset_top = -280.0
	panel.offset_bottom = 280.0
	panel.add_theme_stylebox_override("panel", MenuSupport.panel_style(
		MenuSupport.COLOUR_PANEL, MenuSupport.COLOUR_ACCENT))
	dim.add_child(panel)

	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right"]:
		pad.add_theme_constant_override(side, 22)
	for side in ["margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 18)
	panel.add_child(pad)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	pad.add_child(column)

	column.add_child(MenuSupport.heading(
		Loc.text("inventory", "Inventory").to_upper(), 26, MenuSupport.COLOUR_ACCENT))

	_title_line = Label.new()
	_title_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_line.add_theme_font_size_override("font_size", 13)
	_title_line.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	_title_line.visible = subtitle != ""
	_title_line.text = subtitle
	column.add_child(_title_line)

	# --- the tabs (Tuning.csv inventory_tabs) ---
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 6)
	column.add_child(tabs)
	if not shown_tabs().has(_tab):
		_tab = shown_tabs()[0]
	for key in shown_tabs():
		var button := MenuSupport.tab_button(String(TAB_WORDS[key]), key == _tab)
		button.pressed.connect(_show_tab.bind(key))
		tabs.add_child(button)
		_tab_buttons[key] = button

	# --- the grid of things ---
	var scroller := ScrollContainer.new()
	scroller.custom_minimum_size = Vector2(0, 280)
	scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroller)

	# CENTRED, NOT LEFT-ALIGNED. Four things in a row seven wide would
	# otherwise huddle against the left edge of a window they do not fill.
	var centre_grid := CenterContainer.new()
	centre_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroller.add_child(centre_grid)

	_grid = GridContainer.new()
	_grid.columns = 7
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	centre_grid.add_child(_grid)

	# --- what you are pointing at ---
	var shelf := PanelContainer.new()
	shelf.custom_minimum_size = Vector2(0, 86)
	shelf.add_theme_stylebox_override("panel", MenuSupport.panel_style(
		MenuSupport.COLOUR_BACKGROUND, MenuSupport.COLOUR_TEXT_DIM))
	column.add_child(shelf)

	_words = Label.new()
	_words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_words.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_words.add_theme_font_size_override("font_size", 14)
	shelf.add_child(_words)

	var close_button := MenuSupport.icon_button("close|✕",
		Loc.text("close", "Close"), Vector2(200, 46))
	close_button.pressed.connect(close)
	var centre := CenterContainer.new()
	centre.add_child(close_button)
	column.add_child(centre)


# =============================================================
#  THE BEER MAT LOOK  (Anthony 23 Oct 2026, mock-up A)
#
#  "The first one is great! Lets use that one": the window is the cream
#  panel of the beer mat cards, the name is on the wooden sign board (only
#  the board: "just have the board and not the metal bar and chains"), the
#  tabs and Close are the blue wooden planks of every menu, and each thing
#  lies on a round Bavarian beer coaster with how many you have on a bottle
#  cap. Sizes are data/CardFace.csv inventory_ rows; inventory_style old
#  brings back the dark window.
# =============================================================

## A round beer coaster: blue rim with white diamonds, cream middle with a
## red ring, ink edge. Lit = pointed at (a gold ring).
class Coaster:
	extends Control
	var lit := false
	var ink := Color(0.1, 0.07, 0.04)
	var blue := Color(0.16, 0.43, 0.78)

	func _draw() -> void:
		var r := minf(size.x, size.y) / 2.0
		var centre := size / 2.0
		draw_circle(centre, r, blue)
		var count := 28
		var mid := r * 0.86
		var s := r * 0.075
		for k in count:
			var a := TAU * float(k) / float(count)
			var at := centre + Vector2(cos(a), sin(a)) * mid
			draw_colored_polygon(PackedVector2Array([at + Vector2(0, -s), at + Vector2(s, 0),
				at + Vector2(0, s), at + Vector2(-s, 0)]), Color(0.97, 0.97, 0.97))
		draw_circle(centre, r * 0.78, Color(0.96, 0.92, 0.82))
		draw_arc(centre, r * 0.78, 0.0, TAU, 64, Color(0.78, 0.16, 0.16), maxf(2.0, r * 0.04), true)
		draw_arc(centre, r - 2.0, 0.0, TAU, 64, ink, maxf(3.0, r * 0.05), true)
		if lit:
			draw_arc(centre, r - 1.0, 0.0, TAU, 64, Color(0.95, 0.75, 0.2), maxf(4.0, r * 0.07), true)


## The bottle cap with the count on it.
class Cap:
	extends Control
	var ink := Color(0.1, 0.07, 0.04)

	func _draw() -> void:
		var r := minf(size.x, size.y) / 2.0
		var centre := size / 2.0
		draw_circle(centre, r, Color(0.78, 0.63, 0.27))
		draw_circle(centre, r * 0.74, Color(0.96, 0.92, 0.82))
		draw_arc(centre, r - 1.5, 0.0, TAU, 40, ink, maxf(2.0, r * 0.14), true)


## The beer mat look is on (CardFace.csv inventory_style mat).
static func mat_look() -> bool:
	return BeerMatCard.value("inventory_style", "mat").strip_edges().to_lower() == "mat"


static func _pair(key: String, fallback: Vector2) -> Vector2:
	var parts := BeerMatCard.value(key, "").split(",")
	if parts.size() == 2:
		return Vector2(float(parts[0]), float(parts[1]))
	return fallback


## The cream panel of the beer mat card, stretched to `box`, its drawn edge
## `edge` pixels wide (drawn at scale `scale`).
static func _mat(box: Vector2, edge: int, scale: float) -> NinePatchRect:
	var frame_tex := load(BeerMatCard.value("frame")) as Texture2D
	var patch := NinePatchRect.new()
	patch.texture = frame_tex
	var full := frame_tex.get_size()
	var parts := BeerMatCard.value("sign").split(",")
	if parts.size() == 4:
		patch.region_rect = Rect2(Vector2(float(parts[0]), float(parts[1])) * full,
			Vector2(float(parts[2]), float(parts[3])) * full)
	patch.patch_margin_left = edge
	patch.patch_margin_right = edge
	patch.patch_margin_top = edge
	patch.patch_margin_bottom = edge
	patch.size = box / scale
	patch.scale = Vector2(scale, scale)
	patch.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	patch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return patch


## Every button the blue wooden plank, with the menu sounds (ScreenLook).
static func _plank(button: Button) -> void:
	var row := {MenuSupport.normalise("Image"): "res://assets/menu/button_plank_drawn.png",
		MenuSupport.normalise("Scale"): "1", MenuSupport.normalise("Colour"): "#ffffff"}
	ScreenLook._dress(button, row)


func _ink_label(words: String, text_size: int) -> Label:
	var ink := Color.from_string(BeerMatCard.value("ink", "#19110a"), Color(0.1, 0.07, 0.04))
	var label := Label.new()
	label.text = words
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", text_size)
	label.add_theme_color_override("font_color", ink)
	label.add_theme_constant_override("outline_size", 0)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	label.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	return label


func _build_mat(dim: Control) -> void:
	var box := _pair("inventory_window", Vector2(820, 680))
	var edge := int(BeerMatCard.number("inventory_edge", 60.0))
	var text_size := int(BeerMatCard.number("inventory_text_size", 18.0))

	var window := Control.new()
	window.set_anchors_preset(Control.PRESET_CENTER)
	window.offset_left = -box.x / 2.0
	window.offset_right = box.x / 2.0
	window.offset_top = -box.y / 2.0 + 30.0
	window.offset_bottom = box.y / 2.0 + 30.0
	window.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.add_child(window)
	window.add_child(_mat(box, edge, 0.9))

	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right"]:
		pad.add_theme_constant_override(side, 70)
	pad.add_theme_constant_override("margin_top", 62)
	pad.add_theme_constant_override("margin_bottom", 28)
	window.add_child(pad)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	pad.add_child(column)

	_title_line = _ink_label(subtitle, text_size)
	_title_line.visible = subtitle != ""
	column.add_child(_title_line)

	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 14)
	column.add_child(tabs)
	if not shown_tabs().has(_tab):
		_tab = shown_tabs()[0]
	for key in shown_tabs():
		var button := Button.new()
		button.text = String(TAB_WORDS[key])
		button.custom_minimum_size = Vector2(190, 52)
		button.add_theme_font_size_override("font_size", 22)
		button.pressed.connect(_show_tab.bind(key))
		_plank(button)
		tabs.add_child(button)
		_tab_buttons[key] = button

	var scroller := ScrollContainer.new()
	scroller.custom_minimum_size = Vector2(0, 250)
	scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroller)
	var centre_grid := CenterContainer.new()
	centre_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroller.add_child(centre_grid)
	_grid = GridContainer.new()
	_grid.columns = int(BeerMatCard.number("inventory_columns", 4.0))
	_grid.add_theme_constant_override("h_separation", 20)
	_grid.add_theme_constant_override("v_separation", 16)
	centre_grid.add_child(_grid)

	# The info box: a smaller piece of the same cream panel.
	var shelf := Control.new()
	shelf.custom_minimum_size = Vector2(0, 110)
	column.add_child(shelf)
	var shelf_mat := _mat(Vector2(box.x - 140.0, 110.0), edge, 0.6)
	shelf.add_child(shelf_mat)
	_words = _ink_label("", text_size)
	_words.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_words.position = Vector2(50, 14)
	_words.size = Vector2(box.x - 240.0, 82)
	shelf.add_child(_words)
	shelf.resized.connect(func() -> void:
		shelf_mat.size = shelf.size / shelf_mat.scale.x
		_words.size = Vector2(shelf.size.x - 100.0, shelf.size.y - 28.0))

	var close_button := Button.new()
	close_button.text = Loc.text("close", "Close").to_upper()
	close_button.custom_minimum_size = Vector2(230, 60)
	close_button.add_theme_font_size_override("font_size", 26)
	close_button.pressed.connect(close)
	_plank(close_button)
	var centre := CenterContainer.new()
	centre.add_child(close_button)
	column.add_child(centre)

	# The name on the wooden board, centred on the window's top edge.
	var sign := SignHeader.make(Loc.text("inventory", "Inventory").to_upper(),
		"res://data/MenuHeaderBoard.csv")
	window.add_child(sign)
	var lift := BeerMatCard.number("inventory_header_lift", 82.0)
	var centre_sign := func() -> void:
		sign.position = Vector2((box.x - sign.size.x) / 2.0, -lift)
	sign.resized.connect(centre_sign)
	centre_sign.call()


## One thing on its coaster, with how many on a bottle cap.
func _coaster_tile(entry: Dictionary, usable: bool) -> Button:
	var d := BeerMatCard.number("inventory_coaster", 150.0)
	var button := Button.new()
	button.custom_minimum_size = Vector2(d, d)
	button.focus_mode = Control.FOCUS_ALL
	for state_name in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(state_name, StyleBoxEmpty.new())
	var mat := Coaster.new()
	mat.size = Vector2(d, d)
	mat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(mat)
	var ink := Color.from_string(BeerMatCard.value("ink", "#19110a"), Color(0.1, 0.07, 0.04))
	var picture := MenuSupport.icon_texture(String(entry.get("art", "")))
	var icon_side := d * BeerMatCard.number("inventory_icon", 0.56)
	var spot := Rect2(Vector2(d - icon_side, d - icon_side) / 2.0, Vector2(icon_side, icon_side))
	if picture != null:
		var art := TextureRect.new()
		art.texture = picture
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		# Old small pixel icons stay sharp; drawn ones are drawn smooth.
		art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if picture.get_width() <= 96 \
			else CanvasItem.TEXTURE_FILTER_LINEAR
		art.position = spot.position
		art.size = spot.size
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(art)
	else:
		BeerMatCard.add_label(button, _glyph_for(entry), spot, ink, 0.8)
	var held := int(entry.get("held", 1))
	var cap := Cap.new()
	var cap_d := d * 0.27
	cap.size = Vector2(cap_d, cap_d)
	cap.position = Vector2(d * 0.86 - cap_d / 2.0, d * 0.82 - cap_d / 2.0)
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(cap)
	BeerMatCard.add_label(button, str(held), Rect2(cap.position + cap.size * 0.22, cap.size * 0.56), ink, 0.85)
	# Somewhere things can be used, the ones that cannot are greyed.
	if mode != Use.NOTHING and not usable:
		button.modulate = Color(0.6, 0.6, 0.6, 0.9)
	button.mouse_entered.connect(func() -> void:
		mat.lit = true
		mat.queue_redraw())
	button.mouse_exited.connect(func() -> void:
		mat.lit = false
		mat.queue_redraw())
	return button


## The tabs the window shows, in order: Tuning.csv `inventory_tabs`, words
## from AdventureDB.TABS split by `;`. Never empty - a blank or misspelt row
## shows all three, so the bag can never open with nothing to click.
static func shown_tabs() -> Array[String]:
	var out: Array[String] = []
	var said := "items;resources;keys"
	var book := CardDatabase.get_db()
	if book != null:
		said = book.tune_text("inventory_tabs", said)
	for part in said.split(";", false):
		var key := part.strip_edges().to_lower()
		if AdventureDB.TABS.has(key) and not out.has(key):
			out.append(key)
	if out.is_empty():
		out.assign(AdventureDB.TABS)
	return out


# =============================================================
#  FILLING IT
# =============================================================

## Read the save again and redraw. Called on open, and again after something
## has been used, so the count on a tile is never a lie.
func refresh() -> void:
	_bag = AdventureDB.get_db().bag(state)
	_show_tab(_tab)


func _show_tab(which: String) -> void:
	_tab = which if shown_tabs().has(which) else shown_tabs()[0]

	for key in _tab_buttons.keys():
		# The tab you are on is the lit one. Two looks, no third state.
		if mat_look():
			(_tab_buttons[key] as Button).modulate = Color.WHITE if String(key) == _tab \
				else Color(0.62, 0.62, 0.72)
		else:
			MenuSupport.paint_tab(_tab_buttons[key] as Button, String(key) == _tab)

	for child in _grid.get_children():
		child.queue_free()

	var things: Array = _bag.get(_tab, [])
	# ROUND AN (the tutorial): only these items show.
	if not only_ids.is_empty():
		things = things.filter(func(t) -> bool: return only_ids.has(String((t as Dictionary).get("id", ""))))
	if things.is_empty():
		_words.text = _nothing_here()
		return

	_words.text = "Point at something to read what it is."
	for thing in things:
		var tile := _tile(thing as Dictionary)
		tile.set_meta("item_id", String((thing as Dictionary).get("id", "")))
		_grid.add_child(tile)


## A line for an empty tab that says what WOULD be here, rather than the word
## "empty". An empty box that explains itself does not look broken.
func _nothing_here() -> String:
	match _tab:
		"items":
			return "Nothing to use yet. Brews are poured at the Pub; bandages and smelling salts drop from bosses."
		"resources":
			return "No materials yet. They come home from Adventure runs — that is what the runs are for."
		"keys":
			return "No keys yet. These are the things a story hands you and never takes back."
	return ""


func _tile(entry: Dictionary) -> Button:
	var usable := _can_use(entry)
	var tint := MenuSupport.COLOUR_ACCENT if usable else MenuSupport.COLOUR_TEXT_DIM
	var button: Button
	if mat_look():
		button = _coaster_tile(entry, usable)
	else:
		button = MenuSupport.slot_button(String(entry.get("art", "")),
			_glyph_for(entry), int(entry.get("held", 1)), Vector2(84, 84), tint)

	# ============ THE DESCRIPTION IS ON HOVER, NOT ON THE TILE ============
	#
	# Godot's own tooltip is a grey box that arrives a second late, over the
	# thing you are pointing at. This writes into the panel at the bottom of
	# the window instead: it is instant, it is always in the same place, and
	# it has room for a real sentence.
	var words := _describe(entry)
	button.mouse_entered.connect(func() -> void: _words.text = words)
	button.focus_entered.connect(func() -> void: _words.text = words)

	if not usable:
		return button

	button.pressed.connect(func() -> void:
		used.emit(entry)
		# THE CALLER DECIDES WHAT HAPPENS NEXT. On the draft it closes the
		# window and pours; in a fight it spends the item and stays open.
		# Either way the counts are re-read, so a tile can never show a
		# number that has already been spent.
		if is_instance_valid(self):
			refresh())
	return button


## ============ CAN THIS BE CLICKED HERE? ============
##
## Three things have to be true, and the third is the interesting one.
##
##   1. this screen allows using anything at all
##   2. the thing has a `Use`, and is therefore on the Items tab
##   3. it is TAGGED for the place you are standing
##
## Most things are taken at the bar before the team sets off, not in the
## middle of a wave and not out of a pocket during a match. So a bandage with
## no tag is a perfectly good item that simply cannot be used from here, and
## it is shown greyed with a line saying where it CAN be used rather than
## hidden or silently dead.
func _can_use(entry: Dictionary) -> bool:
	if mode == Use.NOTHING:
		return false
	if AdventureDB.tab_of(entry) != "items":
		return false
	if String(entry.get("use", "")).strip_edges() == "":
		return false
	if mode == Use.ITEM:
		return AdventureDB.has_tag(entry, "adventure_consume")
	return AdventureDB.has_tag(entry, "match_consume")


func _describe(entry: Dictionary) -> String:
	var lines: Array[String] = []
	var head := String(entry.get("name", "?"))
	var held := int(entry.get("held", 1))
	if held > 1:
		head += "   x%d" % held
	lines.append(head)

	var words := String(entry.get("description", "")).strip_edges()
	if words != "":
		lines.append(words)

	if _can_use(entry):
		lines.append("Click it to pour it on this card." if mode == Use.ON_CARD
			else "Click it to use it.")
	elif mode != Use.NOTHING and AdventureDB.tab_of(entry) == "items":
		lines.append(_where_it_goes(entry))
	return "\n".join(lines)


## Why a usable thing is not usable HERE. Never a bare "you cannot" — it says
## where it can be used instead, because that is the sentence the player
## actually needs.
func _where_it_goes(entry: Dictionary) -> String:
	var here := AdventureDB.has_tag(entry, "adventure_consume")
	var draft := AdventureDB.has_tag(entry, "match_consume")
	if mode == Use.ITEM and draft and not here:
		return "Not out here. This one goes on a player during a match."
	if mode == Use.ON_CARD and here and not draft:
		return "Not on a card. This one is used during an Adventure fight."
	return "Taken at the bar before the team sets off, not out on the pitch."


## The letter drawn on a tile whose art has not been made yet. It is not
## decoration — it is what makes a bag readable months before the icons exist.
func _glyph_for(entry: Dictionary) -> String:
	var name_text := String(entry.get("name", "?")).strip_edges()
	return name_text.substr(0, 1).to_upper() if name_text != "" else "?"
