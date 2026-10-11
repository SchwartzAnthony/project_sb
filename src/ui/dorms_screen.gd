class_name DormsScreen
extends Control

# =============================================================
#  THE DORMS — rooms of beds, and who is asleep in them
#
#  ROUND AN (Anthony, 10 Oct): "a background that feels like the inside of a
#  1980s soccer dorm for resting ... the beds, 10 per room, each bed a
#  picture like the base buildings and the brewery machines ... buy more
#  beds and rooms ... each extra room adds a tab." Then, the same day:
#  "still looks very AI and generic" - so it became LOOK A, THE CLUB
#  NOTICEBOARD (his pick of three drafts):
#
#      the room          the cellar fills the whole screen, the beds stand
#                        on its floor (DormBeds.csv). No boxes.
#      room tabs         blue-and-white PENNANTS on a string, one per room;
#                        the room you are in hangs lower. A pennant slides
#                        to that room.
#      the shop          the club's wooden NOTICE BOARD on the wall: a camp
#                        bed and a door key to click, each with a price card
#                        pinned under it, and a Rest day card.
#      a sleeper         Z Z Z over his head and a row of MASS MUGS on the
#                        floor in front of his bed - one per fixture of his
#                        rest (his power: power 1 is one game, power 5 five),
#                        full for every fixture slept. He plays nothing -
#                        Adventure, Brewery or Match - until they are all
#                        full. Hover him: a LUGGAGE TAG with his name and
#                        power.
#      the words         one line on the wall; the explaining is the Head
#                        Coach's (Guide.csv dorms_explain).
#
#  WHERE THINGS LIVE (all data, no numbers in here):
#      data/DormsLayout.csv  every piece's picture, place and size
#      data/DormBeds.csv     where each bed stands in the room picture
#      data/Dorms.csv        the rooms and their prices
#      Tuning.csv dorm_*     beds a room, most rooms, a bed's price, the room
#                            and bed pictures
#      data/Recovery.csv · data/Resting.csv   how long, and what sends them
#  The rules are in base_rooms.gd and recovery_book.gd.
# =============================================================

const SPOTS_FILE := "res://data/DormBeds.csv"
const LAYOUT_FILE := "res://data/DormsLayout.csv"
## How long a message on the wall stays before it fades, in seconds.
const MESSAGE_SECONDS := 4.0
## The ink the words on paper (tags and cards) are written in.
const INK := Color(0.16, 0.10, 0.06)

var db: CardDatabase
var state: GameState

var _pager: Control
var _strip: Control
var _ui: Control
var _tabs: Control
var _line: Label
var _board: Control
var _message: Label
var _tag: NinePatchRect
var _tag_words: VBoxContainer

var _room := 0
var _tab_buttons: Array[Control] = []
var _slide: Tween
var _fade: Tween
var _spots: Array[Dictionary] = []
var _layout: Dictionary = {}
var _rooms: Array[Dictionary] = []
var _counts: Array[int] = []
var _sleepers: Array[Dictionary] = []


func _ready() -> void:
	var windowed := MenuSupport.in_a_window(self)
	if not windowed:
		MenuEscape.install(self)
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	db = CardDatabase.get_db()
	state = GameState.fetch(get_tree())
	AchievementBook.review(state)
	_load_spots()
	_load_layout()
	_build(windowed)
	_rebuild()
	# The Head Coach explains the Dorms (Guide.csv: the Tutorial's morning
	# after first, then dorms_explain the first time you come in).
	(func() -> void: Guide.check(self, "dorms", state)).call_deferred()


# =============================================================
#  THE DATA
# =============================================================

## The bed places out of DormBeds.csv: X and Y are where the FOOT of the
## bed stands, as a share of the room picture (0 = left / top, 1 = right /
## bottom); Size is how wide the bed is, as a share of the picture's width.
func _load_spots() -> void:
	_spots.clear()
	for row in MenuSupport.read_csv(SPOTS_FILE):
		if MenuSupport.field(row, "Place").strip_edges() == "":
			continue
		_spots.append({
			"x": clampf(MenuSupport.field_float(row, "X", 0.5), 0.0, 1.0),
			"y": clampf(MenuSupport.field_float(row, "Y", 0.8), 0.0, 1.0),
			"size": maxf(0.02, MenuSupport.field_float(row, "Size", 0.12)),
		})
	if _spots.size() < BaseRooms.beds_per_room():
		print("[dorms] DormBeds.csv has %d place(s) for %d beds a room - the rest stand in a row along the front." % [
			_spots.size(), BaseRooms.beds_per_room()])


## Place `index` in a room: from the CSV, or along the front if it has none.
func _spot(index: int) -> Dictionary:
	if index < _spots.size():
		return _spots[index]
	var per := BaseRooms.beds_per_room()
	return {"x": (index + 0.5) / float(per), "y": 0.93, "size": 0.8 / float(per)}


## DormsLayout.csv: one row per piece of the screen - Image, X, Y, Scale,
## Step. What X and Y are shares OF depends on the piece (see the CSV).
func _load_layout() -> void:
	_layout.clear()
	for row in MenuSupport.read_csv(LAYOUT_FILE):
		var part := MenuSupport.field(row, "Part").strip_edges().to_lower()
		if part == "":
			continue
		_layout[part] = {
			"image": MenuSupport.field(row, "Image").strip_edges(),
			"x": MenuSupport.field_float(row, "X", 0.0),
			"y": MenuSupport.field_float(row, "Y", 0.0),
			"scale": maxf(0.1, MenuSupport.field_float(row, "Scale", 1.0)),
			"step": MenuSupport.field_float(row, "Step", 0.0),
		}


func _part(part: String) -> Dictionary:
	return _layout.get(part, {"image": "", "x": 0.0, "y": 0.0, "scale": 1.0, "step": 0.0})


func _part_art(part: String) -> Texture2D:
	return _texture(String(_part(part)["image"]))


# =============================================================
#  THE FRAME: the room underneath, the wall's pieces on top
# =============================================================

func _build(windowed: bool) -> void:
	clip_contents = true
	var fill := ColorRect.new()
	fill.color = Color(0.07, 0.05, 0.04)
	fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fill)

	# THE ROOMS, side by side on one strip that the pennants slide.
	_pager = Control.new()
	_pager.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pager.clip_contents = true
	_pager.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_pager)
	_strip = Control.new()
	_strip.mouse_filter = Control.MOUSE_FILTER_PASS
	_pager.add_child(_strip)

	# THE WALL'S PIECES, over the rooms: they do not slide.
	_ui = Control.new()
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ui)
	_tabs = Control.new()
	_tabs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_tabs)
	_line = _plated("", 17, MenuSupport.COLOUR_TEXT)
	_ui.add_child(_line)
	_board = Control.new()
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_board)
	_message = _plated("", 17, MenuSupport.COLOUR_TEXT)
	_message.visible = false
	_ui.add_child(_message)

	if not windowed:
		var back := MenuSupport.icon_button("◇", "Back to the base", Vector2(200, 42))
		back.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		back.position = Vector2(-220, -60)
		back.pressed.connect(func() -> void:
			state.save_to_disk()
			ScenePaths.go_back(get_tree(), ScenePaths.BASE))
		_ui.add_child(back)

	# THE LUGGAGE TAG: who is under the mouse, or what a room costs.
	_tag = NinePatchRect.new()
	_tag.texture = _part_art("tag")
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

	resized.connect(_lay_out)


## Where the tag picture may stretch: a wide left end for the hole and the
## string, thin edges elsewhere. Shares of the picture, so any tag works.
func _tag_margins() -> Vector4i:
	var art := _tag.texture if _tag != null else null
	if art == null:
		return Vector4i(0, 0, 0, 0)
	var w := art.get_width()
	var h := art.get_height()
	return Vector4i(int(w * 0.3), int(w * 0.25), int(h * 0.3), int(h * 0.3))


# =============================================================
#  FILLING IT
# =============================================================

func _rebuild() -> void:
	_rooms = BaseRooms.rooms_owned(state)
	_counts = BaseRooms.beds_by_room(state)
	_sleepers = RecoveryBook.in_the_dorms(db, state)
	# THE SAME BED EVERY VISIT: by name, not by how long is left, so nobody
	# swaps beds when a fixture passes.
	_sleepers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["name"]).naturalnocasecmp_to(String(b["name"])) < 0)
	_room = clampi(_room, 0, maxi(_rooms.size() - 1, 0))
	_lay_out()


## Everything placed for the size the screen is now.
func _lay_out() -> void:
	if size.x < 8.0 or size.y < 8.0:
		return
	_build_rooms()
	_build_tabs()
	_build_board()
	_name_room()
	var at: Dictionary = _part("message")
	_message.position = Vector2(float(at["x"]) * size.x, float(at["y"]) * size.y)


## The room picture covering the screen, keeping its shape. When the screen
## is wider than the picture, the CEILING is what is cut, never the floor.
func _room_rect() -> Dictionary:
	var art := _texture(db.tune_text("dorm_background", "") if db != null else "")
	var aspect := float(art.get_width()) / float(art.get_height()) if art != null else 16.0 / 9.0
	var pic := Vector2(size.x, size.x / aspect)
	if pic.y < size.y:
		pic = Vector2(size.y * aspect, size.y)
	return {"art": art, "at": Vector2((size.x - pic.x) * 0.5, size.y - pic.y), "size": pic}


func _build_rooms() -> void:
	for child in _strip.get_children():
		_strip.remove_child(child)
		child.queue_free()
	var room := _room_rect()
	var art: Texture2D = room["art"]
	var at: Vector2 = room["at"]
	var pic: Vector2 = room["size"]
	var per := BaseRooms.beds_per_room()
	var asleep := 0
	for i in _rooms.size():
		var page := Control.new()
		page.position = Vector2(size.x * i, 0)
		page.size = size
		page.mouse_filter = Control.MOUSE_FILTER_PASS
		_strip.add_child(page)
		if art != null:
			var picture := TextureRect.new()
			picture.texture = art
			picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			picture.stretch_mode = TextureRect.STRETCH_SCALE
			picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
			picture.position = at
			picture.size = pic
			page.add_child(picture)
		var tiles: Dictionary = {}
		for place in per:
			var who: Dictionary = {}
			if place < _counts[i] and asleep < _sleepers.size():
				who = _sleepers[asleep]
				asleep += 1
			var spot := _spot(place)
			var wide := float(spot["size"]) * pic.x
			var tile := _bed(who, wide) if place < _counts[i] else _place_to_buy(wide)
			# THE FOOT OF THE BED ON THE SPOT: the bed picture's bottom edge
			# sits there, its mugs on the floor in front of it.
			var foot := at + Vector2(float(spot["x"]) * pic.x, float(spot["y"]) * pic.y)
			tile.position = Vector2(foot.x - wide * 0.5, foot.y - float(tile.get_meta("bed_height")))
			tiles[place] = tile
		# Back beds first, so a bed nearer the front is drawn over the wall
		# behind the one further back.
		var order: Array = tiles.keys()
		order.sort_custom(func(a: int, b: int) -> bool:
			return float(_spot(a)["y"]) < float(_spot(b)["y"]))
		for place in order:
			page.add_child(tiles[place])
	_strip.size = Vector2(size.x * maxi(_rooms.size(), 1), size.y)
	if _slide != null and _slide.is_running():
		_slide.kill()
	_strip.position = Vector2(-size.x * _room, 0)


# ---- THE PENNANTS --------------------------------------------

func _build_tabs() -> void:
	for child in _tabs.get_children():
		_tabs.remove_child(child)
		child.queue_free()
	_tab_buttons.clear()
	var lay := _part("pennant")
	var art := _part_art("pennant")
	var scale_by := float(lay["scale"])
	var start := Vector2(float(lay["x"]) * size.x, float(lay["y"]) * size.y)
	var step := maxf(float(lay["step"]) * size.x, 8.0)
	var count := _rooms.size()
	# THE STRING they hang from, a little slack in the middle.
	var string := StringLine.new()
	string.mouse_filter = Control.MOUSE_FILTER_IGNORE
	string.from = start + Vector2(-10, 4)
	string.to = start + Vector2(step * count + 10, 10)
	_tabs.add_child(string)
	for i in count:
		var tab := _pennant(i, art, scale_by)
		tab.position = start + Vector2(step * i, 0)
		_tabs.add_child(tab)
		_tab_buttons.append(tab)
	_paint_tabs(false)


func _pennant(index: int, art: Texture2D, scale_by: float) -> Control:
	var tab := MapBuilding.new()
	tab.flat = true
	tab.focus_mode = Control.FOCUS_ALL
	tab.add_theme_stylebox_override("focus", MenuSupport.focus_style())
	var box := Vector2(48, 64) * scale_by
	if art != null:
		box = Vector2(art.get_size()) * scale_by
		var picture := TextureRect.new()
		picture.texture = art
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_SCALE
		picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tab.add_child(picture)
		tab.use_picture(art)
	tab.size = box
	tab.custom_minimum_size = box
	# THE NUMBER in the pennant's cream circle (DormsLayout.csv number:
	# where the circle's middle is, as shares of the pennant).
	var circle := _part("number")
	var number := MenuSupport.heading(str(index + 1), int(16 * scale_by * 0.5) * 2, Color(0.13, 0.24, 0.55))
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	number.mouse_filter = Control.MOUSE_FILTER_IGNORE
	number.size = Vector2(box.x * 0.6, box.x * 0.6)
	number.position = Vector2(float(circle["x"]) * box.x, float(circle["y"]) * box.y) - number.size * 0.5
	tab.add_child(number)
	var room_name := String(_rooms[index]["name"]) if index < _rooms.size() else "Room %d" % (index + 1)
	tab.mouse_entered.connect(func() -> void:
		tab.modulate = Color(1.2, 1.2, 1.2)
		_show_tag([room_name, "%d of %d beds" % [_counts[index], BaseRooms.beds_per_room()]], tab))
	tab.mouse_exited.connect(func() -> void:
		_paint_tabs(false)
		_tag.visible = false)
	tab.pressed.connect(_show_room.bind(index))
	return tab


## The room you are in hangs lower and in full colour; the rest a little
## darker. `moving` = slide them there rather than jump.
func _paint_tabs(moving: bool) -> void:
	var lay := _part("pennant")
	var top := float(lay["y"]) * size.y
	var drop := float(_part("pennant_drop")["y"]) * size.y
	for i in _tab_buttons.size():
		var tab := _tab_buttons[i]
		var y := top + (drop if i == _room else 0.0)
		tab.modulate = Color.WHITE if i == _room else Color(0.78, 0.78, 0.82)
		if moving:
			tab.create_tween().tween_property(tab, "position:y", y, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		else:
			tab.position.y = y


func _show_room(index: int) -> void:
	if index == _room:
		return
	_room = index
	_paint_tabs(true)
	_name_room()
	if _slide != null:
		_slide.kill()
	_slide = create_tween()
	_slide.tween_property(_strip, "position:x", -size.x * _room, 0.32) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## The one line on the wall: which room, how many asleep, how many beds.
func _name_room() -> void:
	var lay := _part("status")
	_line.position = Vector2(float(lay["x"]) * size.x, float(lay["y"]) * size.y)
	if _rooms.is_empty():
		_line.text = "No room - Dorms.csv has no free first row"
		return
	var words := "%s    %d asleep    %d of %d beds" % [String(_rooms[_room]["name"]).to_upper(),
		_asleep_in(_room), _counts[_room], BaseRooms.beds_per_room()]
	var floor_count := _sleepers.size() - mini(_sleepers.size(), BaseRooms.beds(state))
	# MORE ASLEEP THAN BEDS: they sleep on the floor - they still rest
	# (Anthony, 10 Oct, Q266). The tag over the line names them.
	if floor_count > 0:
		words += "    %d on the floor" % floor_count
	if db == null or not db.tune_bool("recovery", false):
		words += "    RECOVERY IS OFF (Tuning.csv)"
	_line.text = words


## How many of the sleepers are in this room's beds.
func _asleep_in(index: int) -> int:
	var before := 0
	for k in index:
		before += _counts[k]
	return clampi(_sleepers.size() - before, 0, _counts[index] if index < _counts.size() else 0)


# ---- A BED ---------------------------------------------------

func _bed(who: Dictionary, big: float) -> Control:
	var tile := Control.new()
	tile.mouse_filter = Control.MOUSE_FILTER_PASS
	var asleep := not who.is_empty()
	var art := _texture(db.tune_text("dorm_bed_sleeper_art" if asleep else "dorm_bed_art", ""))
	if asleep and art == null:
		art = _texture(db.tune_text("dorm_bed_art", ""))
	var button := MapBuilding.new()
	button.flat = true
	# As tall as the picture is for this width, so its bottom edge - the
	# feet of the bed - is the bottom of the button.
	var tall := big * (float(art.get_height()) / float(art.get_width()) if art != null else 0.8)
	button.size = Vector2(big, tall)
	tile.size = Vector2(big, tall)
	tile.set_meta("bed_height", tall)
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_stylebox_override("focus", MenuSupport.focus_style())
	if art != null:
		var picture := TextureRect.new()
		picture.texture = art
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_SCALE
		picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		button.add_child(picture)
		button.use_picture(art)
	else:
		var drawn := PlainBed.new()
		drawn.asleep = asleep
		drawn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		drawn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(drawn)
	tile.add_child(button)

	# HOVER, like a building on the base: it brightens.
	button.mouse_entered.connect(func() -> void:
		button.modulate = Color(1.18, 1.18, 1.18)
		if asleep:
			_show_tag([String(who["name"]), "P:%d    %d to go" % [int(who["power"]), int(who["left"])]], button)
		else:
			_show_tag(["A free bed"], button))
	button.mouse_exited.connect(func() -> void:
		button.modulate = Color.WHITE
		_tag.visible = false)

	if not asleep:
		button.pressed.connect(func() -> void:
			_tell("A free bed. Whoever comes home tired next sleeps here.", true))
		return tile

	# Marked, so tools/dorms_screen_shot.gd can hover a sleeper.
	button.set_meta("sleeper", String(who["name"]))
	button.pressed.connect(func() -> void:
		_tell("%s - %s, %d fixture(s) to go." % [_who_words(who), who["why"], int(who["left"])], true))

	# Z Z Z, ALWAYS, over his head - drifting up and back.
	var snore := MenuSupport.heading("Z z z", 16, Color(0.85, 0.92, 1.0))
	snore.mouse_filter = Control.MOUSE_FILTER_IGNORE
	snore.position = Vector2(big * 0.1, -14)
	tile.add_child(snore)
	var drift := snore.create_tween().set_loops()
	drift.tween_property(snore, "position:y", -24.0, 1.1).set_trans(Tween.TRANS_SINE)
	drift.tween_property(snore, "position:y", -14.0, 1.1).set_trans(Tween.TRANS_SINE)

	var mugs := _mugs(who)
	mugs.position = Vector2((big - mugs.size.x) * 0.5, tall + 2.0)
	tile.add_child(mugs)
	return tile


## THE REST BAR: a Mass mug per fixture of his rest, full for every one he
## has slept. He plays again when they are all full.
func _mugs(who: Dictionary) -> Control:
	var bar_data := RecoveryBook.rest_bar(String(who["name"]), int(who["power"]), state, db)
	var full := maxi(1, int(bar_data["full"]))
	var done := int(bar_data["done"])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 1)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var full_art := _part_art("mug_full")
	var empty_art := _part_art("mug_empty")
	var scale_by := float(_part("mug_full")["scale"])
	var one := Vector2(full_art.get_size()) * scale_by if full_art != null else Vector2(10, 14)
	for i in full:
		var mug := TextureRect.new()
		mug.texture = full_art if i < done else empty_art
		mug.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		mug.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		mug.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		mug.custom_minimum_size = one
		mug.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(mug)
	row.size = Vector2(one.x * full + (full - 1), one.y)
	return row


## An empty place in the room: a faint patch of floor. Click it to buy a bed.
func _place_to_buy(big: float) -> Control:
	var tall := big * 0.75
	var place := Button.new()
	place.set_meta("bed_height", tall)
	place.size = Vector2(big, tall)
	place.text = "+ bed"
	place.add_theme_font_size_override("font_size", 16)
	var face := ThemeBook.font(String(ThemeBook.row_for("heading").get("font", "")))
	if face != null:
		place.add_theme_font_override("font", face)
	var empty := StyleBoxFlat.new()
	empty.bg_color = Color(0, 0, 0, 0.25)
	empty.border_color = Color(1, 1, 1, 0.22)
	empty.set_border_width_all(2)
	empty.set_corner_radius_all(6)
	var lit := empty.duplicate() as StyleBoxFlat
	lit.border_color = MenuSupport.COLOUR_ACCENT
	place.add_theme_stylebox_override("normal", empty)
	place.add_theme_stylebox_override("hover", lit)
	place.add_theme_stylebox_override("pressed", lit)
	place.add_theme_stylebox_override("focus", MenuSupport.focus_style())
	place.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	place.mouse_entered.connect(func() -> void:
		_show_tag(["An empty place", "A bed: %s" % _bed_price_words()], place))
	place.mouse_exited.connect(func() -> void: _tag.visible = false)
	place.pressed.connect(_buy_bed)
	return place


func _who_words(who: Dictionary) -> String:
	if bool(who.get("brewer", false)):
		return "%s  ·  Brewer, efficiency %d" % [who["name"], int(who["power"])]
	return "%s  ·  Tier %s  ·  P:%d" % [who["name"], who["tier"], int(who["power"])]


# ---- THE NOTICE BOARD -----------------------------------------

func _build_board() -> void:
	for child in _board.get_children():
		_board.remove_child(child)
		child.queue_free()
	var lay := _part("board")
	var art := _part_art("board")
	var box := Vector2(256, 160) * float(lay["scale"])
	if art != null:
		box = Vector2(art.get_size()) * float(lay["scale"])
		var picture := TextureRect.new()
		picture.texture = art
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_SCALE
		picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		picture.size = box
		_board.add_child(picture)
	_board.size = box
	_board.position = Vector2(float(lay["x"]) * size.x, float(lay["y"]) * size.y)

	# A SINGLE BED - the folded camp bed.
	var places_left := BaseRooms.bed_places(state) - BaseRooms.beds(state)
	var bed_ok := places_left > 0 and _can_pay(_bed_price(), _bed_currency())
	var bed_why := "" if bed_ok else ("Every room is full - buy a room first." if places_left <= 0
		else "Not enough money for a bed.")
	_board_item("buy_bed", ["A single bed: %s" % _bed_price_words(),
		"%d empty place(s) in your rooms" % places_left], bed_ok, bed_why, _buy_bed)
	_card("bed_card", "Bed  %s" % _short_price(_bed_price(), _bed_currency()), bed_ok, _buy_bed)

	# THE NEXT ROOM - the door key. Its tag lists EVERY room's price.
	var nxt := BaseRooms.next_room(state)
	var lines: Array[String] = []
	for room in BaseRooms.dorms():
		var mine := BaseRooms.owns_dorm(String(room["id"]), state)
		lines.append("%s   %s" % [room["name"], "yours" if mine
			else _price_words(int(room["price"]), String(room["currency"]))])
	if nxt.is_empty():
		_board_item("buy_room", ["Every room is yours"] + lines, false, "You have every room there is.", func() -> void: pass)
		_card("room_card", "All rooms", false, func() -> void: pass)
	else:
		var allowed := DialogueGrammar.test(String(nxt["requires"]), state)
		var price := int(nxt["price"])
		var cur := String(nxt["currency"])
		var room_ok := allowed and _can_pay(price, cur)
		var room_why := "" if room_ok else (DialogueGrammar.describe(String(nxt["requires"])) if not allowed
			else "Not enough money for %s." % nxt["name"])
		var id_text := String(nxt["id"])
		var head: Array[String] = ["%s: %s - a new pennant, %d more places" % [nxt["name"],
			_price_words(price, cur), BaseRooms.beds_per_room()]]
		if not allowed:
			head.append(DialogueGrammar.describe(String(nxt["requires"])))
		_board_item("buy_room", head + lines, room_ok, room_why, _buy_room.bind(id_text))
		_card("room_card", "%s  %s" % [String(nxt["name"]), _short_price(price, cur)], room_ok, _buy_room.bind(id_text))

	# THE REST DAY (rest_day_cost in Tuning.csv; below 0 hides it).
	var rest_price := db.tune_int("rest_day_cost", 0) if db != null else -1
	var on := db != null and db.tune_bool("recovery", false)
	if on and rest_price >= 0 and not _sleepers.is_empty():
		_card("rest_card", "Rest day  %s" % ("free" if rest_price == 0 else str(rest_price)),
			_can_pay(rest_price, "coins"), _rest_day)


## A picture on the board you click to buy: the camp bed, the door key.
func _board_item(part: String, tag_lines: Array, allowed: bool, why_not: String, what: Callable) -> void:
	var lay := _part(part)
	var art := _part_art(part)
	var item := MapBuilding.new()
	item.flat = true
	item.focus_mode = Control.FOCUS_ALL
	item.add_theme_stylebox_override("focus", MenuSupport.focus_style())
	var box := Vector2(64, 64) * float(lay["scale"])
	if art != null:
		box = Vector2(art.get_size()) * float(lay["scale"])
		var picture := TextureRect.new()
		picture.texture = art
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_SCALE
		picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		item.add_child(picture)
		item.use_picture(art)
	item.size = box
	item.position = Vector2(float(lay["x"]) * _board.size.x, float(lay["y"]) * _board.size.y) - box * 0.5
	var resting := Color.WHITE if allowed else Color(0.6, 0.6, 0.62)
	item.modulate = resting
	item.mouse_entered.connect(func() -> void:
		item.modulate = resting * 1.2
		_show_tag(tag_lines, item))
	item.mouse_exited.connect(func() -> void:
		item.modulate = resting
		_tag.visible = false)
	item.pressed.connect(func() -> void:
		if allowed:
			what.call()
		else:
			_tell(why_not, false))
	_board.add_child(item)


## A price card pinned to the board. It buys too.
func _card(part: String, words: String, allowed: bool, what: Callable) -> void:
	var lay := _part(part)
	var card := Button.new()
	card.flat = true
	card.focus_mode = Control.FOCUS_ALL
	var art := _part_art("card")
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
	card.add_child(plate)
	var label := MenuSupport.heading(words, 16, INK if allowed else Color(0.45, 0.4, 0.35))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.offset_top = 6.0
	card.add_child(label)
	var scale_by := float(lay["scale"])
	var high := (art.get_height() if art != null else 32) * scale_by
	var wide := maxf(label.get_minimum_size().x + 36.0, (art.get_width() if art != null else 64) * scale_by)
	card.size = Vector2(wide, high)
	card.position = Vector2(float(lay["x"]) * _board.size.x - wide * 0.5, float(lay["y"]) * _board.size.y)
	card.mouse_entered.connect(func() -> void: card.modulate = Color(1.15, 1.15, 1.15))
	card.mouse_exited.connect(func() -> void: card.modulate = Color.WHITE)
	card.pressed.connect(func() -> void:
		if allowed:
			what.call()
		else:
			_tell("Not now - hover the picture above to see why.", false))
	_board.add_child(card)


func _buy_bed() -> void:
	_say(BaseRooms.buy_bed(state))


func _buy_room(id_text: String) -> void:
	var before := BaseRooms.rooms_owned(state).size()
	var result := BaseRooms.buy_dorm(id_text, state)
	# A NEW ROOM IS A NEW PENNANT: go and look at it.
	if bool(result["ok"]):
		_room = before
	_say(result)


func _rest_day() -> void:
	_say(RecoveryBook.rest_day(state, db))


# =============================================================
#  SMALL PIECES
# =============================================================

## The luggage tag next to `over`: a few lines in ink.
func _show_tag(lines: Array, over: Control) -> void:
	for child in _tag_words.get_children():
		_tag_words.remove_child(child)
		child.queue_free()
	var widest := 0.0
	for i in lines.size():
		var label := MenuSupport.heading(String(lines[i]), 16, INK if i == 0 else Color(0.38, 0.2, 0.08))
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_tag_words.add_child(label)
		widest = maxf(widest, label.get_minimum_size().x)
	# The words start after the hole and the string at the tag's left end.
	var cut := _tag_margins()
	var high := 22.0 * lines.size() + 20.0
	# The words start clear of the string that loops from the tag's hole.
	var wide := widest + cut.x + cut.y + 40.0
	_tag.size = Vector2(wide, high)
	_tag_words.position = Vector2(cut.x + 32.0, 10.0)
	_tag.visible = true
	var at := over.get_global_rect()
	var spot := Vector2(at.position.x + at.size.x * 0.5 - wide * 0.3, at.position.y - high - 6.0)
	# Keep it on the screen.
	var room := get_global_rect()
	spot.x = clampf(spot.x, room.position.x + 4.0, room.end.x - wide - 4.0)
	if spot.y < room.position.y + 4.0:
		spot.y = at.end.y + 6.0
	_tag.global_position = spot


func _say(result: Dictionary) -> void:
	_tell(String(result["why"]), bool(result["ok"]))
	if bool(result["ok"]):
		state.save_to_disk()
	_rebuild()


## A message on the wall for a few seconds.
func _tell(words: String, good: bool) -> void:
	_message.text = words
	_message.add_theme_color_override("font_color",
		MenuSupport.COLOUR_TEXT if good else Color(1.0, 0.72, 0.4))
	_message.visible = true
	_message.modulate.a = 1.0
	if _fade != null:
		_fade.kill()
	_fade = create_tween()
	_fade.tween_interval(MESSAGE_SECONDS)
	_fade.tween_property(_message, "modulate:a", 0.0, 0.5)


## Words on the game's see-through black plate, in the pixel font.
func _plated(text: String, size_px: int, colour: Color) -> Label:
	var label := MenuSupport.heading(text, size_px, colour)
	label.add_theme_stylebox_override("normal", TextBackdrop.plate())
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _bed_price() -> int:
	return maxi(0, db.tune_int("dorm_bed_price", 25)) if db != null else 25


func _bed_currency() -> String:
	return db.tune_text("dorm_bed_currency", "coins") if db != null else "coins"


func _bed_price_words() -> String:
	return _price_words(_bed_price(), _bed_currency())


func _price_words(price: int, currency_id: String) -> String:
	if price <= 0:
		return "free"
	var cur := ShopBook.currency(currency_id)
	return "%d %s" % [price, cur.get("name", currency_id)]


## A price for a small card: the number alone when it is in coins.
func _short_price(price: int, currency_id: String) -> String:
	if price <= 0:
		return "free"
	return str(price) if currency_id == "coins" else _price_words(price, currency_id)


func _can_pay(price: int, currency_id: String) -> bool:
	if price <= 0:
		return true
	return ShopBook.purse(currency_id, state) >= price


func _texture(path: String) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


## The string the pennants hang from.
class StringLine:
	extends Control
	var from := Vector2.ZERO
	var to := Vector2.ZERO

	func _draw() -> void:
		var mid := (from + to) * 0.5 + Vector2(0, 8)
		draw_polyline(PackedVector2Array([from, mid, to]), Color(0.18, 0.12, 0.08), 3.0)


## A bed in plain shapes, for when there is no bed picture.
class PlainBed:
	extends Control
	var asleep := false

	func _draw() -> void:
		var w := size.x
		var h := size.y
		draw_rect(Rect2(w * 0.08, h * 0.25, w * 0.84, h * 0.55), Color(0.35, 0.36, 0.40))
		draw_rect(Rect2(w * 0.12, h * 0.30, w * 0.76, h * 0.40), Color(0.92, 0.90, 0.85))
		draw_rect(Rect2(w * 0.14, h * 0.32, w * 0.22, h * 0.16), Color(0.75, 0.82, 0.95))
		draw_rect(Rect2(w * 0.45, h * 0.30, w * 0.43, h * 0.40), Color(0.85, 0.25, 0.22))
		if asleep:
			draw_circle(Vector2(w * 0.25, h * 0.36), h * 0.11, Color(0.96, 0.72, 0.62))
