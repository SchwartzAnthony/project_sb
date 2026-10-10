class_name DormsScreen
extends Control

# =============================================================
#  THE DORMS — rooms of beds, and who is asleep in them
#
#  ROUND AN (Anthony, 10 Oct): "a background that feels like the inside of a
#  1980s soccer dorm for resting ... the beds, 10 per room, each bed a
#  picture like the base buildings and the brewery machines ... a window
#  below sells single beds and extra rooms ... each extra room adds a tab."
#
#  ============ THE SCREEN ============
#
#      the picture       Tuning.csv dorm_background, under a see-through sheet
#      THE BEDS          tabs 1, 2, 3 ... one per room you have. A tab slides
#                        to that room's beds, five a row, two rows.
#      BUY               a single bed, the next room, and every room's price
#
#  ============ A BED ============
#
#      asleep    the sleeper's picture, Z Z Z over his head, and under the
#                bed his REST BAR: one segment per fixture of his rest (his
#                power - power 1 is one game, power 5 five). He plays
#                nothing - Adventure, Brewery or Match - until it is full.
#                Hover him for his name and power.
#      free      a made bed nobody is in
#      to buy    an empty place in the room: click it to buy a bed
#
#  WHERE THE NUMBERS LIVE: data/Dorms.csv (the rooms and their prices),
#  Tuning.csv dorm_* (beds a room, most rooms, a bed's price, the art),
#  data/Recovery.csv (how long by power), data/Resting.csv (what sends a
#  player to bed). The rules are in base_rooms.gd and recovery_book.gd.
# =============================================================

const COLUMNS := 5
## The sleeper hover plate goes above everything, even another room's beds.
const HOVER_Z := 50

var db: CardDatabase
var state: GameState

var _intro: Label
var _tabs: HBoxContainer
var _room_title: Label
var _pager: Control
var _strip: HBoxContainer
var _shop: HBoxContainer
var _status: Label
var _hover: PanelContainer
var _hover_words: Label

var _room := 0
var _tab_buttons: Array[Button] = []
var _slide: Tween


func _ready() -> void:
	var windowed := MenuSupport.in_a_window(self)
	if not windowed:
		MenuEscape.install(self)
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	db = CardDatabase.get_db()
	state = GameState.fetch(get_tree())
	AchievementBook.review(state)
	_build(windowed)
	_rebuild()
	# The Tutorial's "morning after" explains the beds here (Guide.csv).
	(func() -> void: Guide.check(self, "dorms", state)).call_deferred()


# =============================================================
#  THE FRAME
# =============================================================

func _build(windowed: bool) -> void:
	clip_contents = true
	if not windowed:
		var fill := ColorRect.new()
		fill.color = MenuSupport.COLOUR_BACKGROUND
		fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(fill)
	_build_backdrop()

	var page := VBoxContainer.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.offset_left = 12.0
	page.offset_right = -12.0
	page.offset_top = 8.0
	page.offset_bottom = -8.0
	page.add_theme_constant_override("separation", 10)
	add_child(page)

	if not windowed:
		page.add_child(MenuSupport.heading("THE DORMS", 30, MenuSupport.COLOUR_ACCENT))

	_intro = _words("", 15, MenuSupport.COLOUR_TEXT)
	_intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(_intro)

	# ---- THE BEDS: tabs, then the sliding rooms ----
	var beds_box := _window(page, true)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	beds_box.add_child(bar)
	bar.add_child(MenuSupport.heading("THE BEDS", 17, MenuSupport.COLOUR_ACCENT))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(18, 0)
	bar.add_child(gap)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 4)
	bar.add_child(_tabs)
	var push := Control.new()
	push.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(push)
	_room_title = MenuSupport.heading("", 15, MenuSupport.COLOUR_TEXT_DIM)
	bar.add_child(_room_title)

	_pager = Control.new()
	_pager.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_pager.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pager.clip_contents = true
	# Two rows of beds, whatever the window: a bed, its rest bar and a gap.
	var bed_h := _bed_size() * 0.8 + 16.0 + 4.0
	_pager.custom_minimum_size = Vector2(0, bed_h * 2.0 + 14.0 + 24.0)
	beds_box.add_child(_pager)
	_strip = HBoxContainer.new()
	_strip.add_theme_constant_override("separation", 0)
	_pager.add_child(_strip)
	_pager.resized.connect(_lay_pages)

	# ---- BUY ----
	var shop_box := _window(page, false)
	shop_box.add_child(MenuSupport.heading("BUY", 17, MenuSupport.COLOUR_ACCENT))
	_shop = HBoxContainer.new()
	_shop.add_theme_constant_override("separation", 18)
	shop_box.add_child(_shop)

	_status = _words("", 15, MenuSupport.COLOUR_TEXT_DIM)
	_status.custom_minimum_size = Vector2(0, 26)
	page.add_child(_status)

	if not windowed:
		var back := MenuSupport.icon_button("◇", "Back to the base", Vector2(200, 42))
		back.pressed.connect(func() -> void:
			state.save_to_disk()
			ScenePaths.go_back(get_tree(), ScenePaths.BASE))
		page.add_child(back)

	# THE HOVER PLATE: name and power of the sleeper under the mouse.
	_hover = PanelContainer.new()
	_hover.add_theme_stylebox_override("panel", TextBackdrop.plate())
	_hover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover.z_index = HOVER_Z
	_hover.top_level = true
	_hover.visible = false
	_hover_words = MenuSupport.heading("", 15, MenuSupport.COLOUR_TEXT)
	_hover_words.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hover.add_child(_hover_words)
	add_child(_hover)


## The picture behind it all, under a see-through black sheet.
func _build_backdrop() -> void:
	var art := _texture(db.tune_text("dorm_background", "") if db != null else "")
	if art == null:
		return
	var picture := TextureRect.new()
	picture.texture = art
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(picture)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, clampf(db.tune_float("dorm_background_shade", 0.35), 0.0, 1.0))
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)


## One of the two windows. Returns the column its contents go in.
func _window(parent: Control, grow: bool) -> VBoxContainer:
	var frame := PanelContainer.new()
	# SEE-THROUGH, so the room shows through behind the beds: the same
	# black as the words' plates, with the window's gold edge.
	var look := StyleBoxFlat.new()
	look.bg_color = Color(0, 0, 0, TextBackdrop.alpha())
	look.border_color = MenuSupport.COLOUR_ACCENT
	look.set_border_width_all(3)
	look.set_corner_radius_all(6)
	frame.add_theme_stylebox_override("panel", look)
	if grow:
		frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(frame)
	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right"]:
		pad.add_theme_constant_override(side, 14)
	for side in ["margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 10)
	frame.add_child(pad)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	pad.add_child(column)
	return column


# =============================================================
#  FILLING IT
# =============================================================

func _rebuild() -> void:
	var rooms := BaseRooms.rooms_owned(state)
	var counts := BaseRooms.beds_by_room(state)
	var per := BaseRooms.beds_per_room()
	var on := db != null and db.tune_bool("recovery", false)
	var sleepers := RecoveryBook.in_the_dorms(db, state)
	# THE SAME BED EVERY VISIT: by name, not by how long is left, so nobody
	# swaps beds when a fixture passes.
	sleepers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["name"]).naturalnocasecmp_to(String(b["name"])) < 0)
	var beds := BaseRooms.beds(state)

	var head := "%d bed(s) in %d room(s), %d asleep. You are keeping %d player(s). " % [
		beds, rooms.size(), sleepers.size(), SquadBook.names(state).size()]
	if on:
		head += "Everybody rests here after a match, an Adventure or a shift at the Brewery: one fixture per point of power. A sleeper plays nothing until his bar is full."
	else:
		head += "RECOVERY IS OFF - `recovery` in Tuning.csv. Nobody gets tired, so nobody is in bed."
	_intro.text = head

	# ---- the tabs ----
	for child in _tabs.get_children():
		child.queue_free()
	_tab_buttons.clear()
	_room = clampi(_room, 0, maxi(rooms.size() - 1, 0))
	for i in rooms.size():
		var tab := MenuSupport.tab_button(str(i + 1), i == _room, Vector2(44, 36))
		tab.tooltip_text = "%s - %d of %d beds" % [rooms[i]["name"], counts[i], per]
		tab.pressed.connect(_show_room.bind(i))
		_tabs.add_child(tab)
		_tab_buttons.append(tab)

	# ---- the rooms, side by side on one strip ----
	for child in _strip.get_children():
		child.queue_free()
	var asleep := 0
	for i in rooms.size():
		var page := CenterContainer.new()
		var grid := GridContainer.new()
		grid.columns = COLUMNS
		grid.add_theme_constant_override("h_separation", 18)
		grid.add_theme_constant_override("v_separation", 14)
		page.add_child(grid)
		for place in per:
			if place < counts[i]:
				var who: Dictionary = sleepers[asleep] if asleep < sleepers.size() else {}
				if not who.is_empty():
					asleep += 1
				grid.add_child(_bed(who))
			else:
				grid.add_child(_place_to_buy())
		_strip.add_child(page)
	# MORE ASLEEP THAN BEDS: they sleep on the floor, and say so.
	if asleep < sleepers.size():
		var floor_names: Array[String] = []
		for k in range(asleep, sleepers.size()):
			floor_names.append(String(sleepers[k]["name"]))
		_intro.text += "  ON THE FLOOR (no bed for them): " + ", ".join(floor_names) + "."
	_lay_pages.call_deferred()
	_name_room()
	_fill_shop(sleepers.size(), on)


## Every page as wide as the window, the strip slid to the room you are on.
func _lay_pages() -> void:
	if _pager == null or _strip == null:
		return
	var box := _pager.size
	for page in _strip.get_children():
		(page as Control).custom_minimum_size = box
	_strip.size = Vector2(box.x * _strip.get_child_count(), box.y)
	if _slide == null or not _slide.is_running():
		_strip.position = Vector2(-box.x * _room, 0)


func _show_room(index: int) -> void:
	if index == _room:
		return
	_room = index
	for i in _tab_buttons.size():
		MenuSupport.paint_tab(_tab_buttons[i], i == _room)
	_name_room()
	if _slide != null:
		_slide.kill()
	_slide = create_tween()
	_slide.tween_property(_strip, "position:x", -_pager.size.x * _room, 0.28) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _name_room() -> void:
	var rooms := BaseRooms.rooms_owned(state)
	if rooms.is_empty():
		_room_title.text = "No room - Dorms.csv has no free first row"
		return
	var counts := BaseRooms.beds_by_room(state)
	_room_title.text = "%s  ·  %d of %d beds" % [rooms[_room]["name"], counts[_room],
		BaseRooms.beds_per_room()]


# ---- A BED ---------------------------------------------------

func _bed(who: Dictionary) -> Control:
	var big := _bed_size()
	var tile := VBoxContainer.new()
	tile.add_theme_constant_override("separation", 4)
	tile.custom_minimum_size = Vector2(big, 0)

	var asleep := not who.is_empty()
	var art := _texture(db.tune_text("dorm_bed_sleeper_art" if asleep else "dorm_bed_art", ""))
	if asleep and art == null:
		art = _texture(db.tune_text("dorm_bed_art", ""))
	var button := MapBuilding.new()
	button.flat = true
	button.custom_minimum_size = Vector2(big, big * 0.8)
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_stylebox_override("focus", MenuSupport.focus_style())
	if art != null:
		var picture := TextureRect.new()
		picture.texture = art
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
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
			_show_hover(who, button))
	button.mouse_exited.connect(func() -> void:
		button.modulate = Color.WHITE
		_hover.visible = false)

	if not asleep:
		button.tooltip_text = "A free bed"
		button.modulate = Color.WHITE
		button.pressed.connect(func() -> void:
			_say({"ok": true, "why": "A free bed. Whoever comes home tired next sleeps here."}, false))
		# No bar under a free bed - but the same height, so the rows line up.
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(0, 12)
		tile.add_child(spacer)
		return tile

	button.tooltip_text = _who_words(who)
	button.pressed.connect(func() -> void:
		_say({"ok": true, "why": "%s - %s, %d fixture(s) to go." % [
			_who_words(who), who["why"], int(who["left"])]}, false))

	# Z Z Z, ALWAYS, over his head - drifting up and back.
	var snore := MenuSupport.heading("Z z z", 16, Color(0.85, 0.92, 1.0))
	snore.mouse_filter = Control.MOUSE_FILTER_IGNORE
	snore.position = Vector2(big * 0.12, -6)
	button.add_child(snore)
	var drift := snore.create_tween().set_loops()
	drift.tween_property(snore, "position:y", -16.0, 1.1).set_trans(Tween.TRANS_SINE)
	drift.tween_property(snore, "position:y", -6.0, 1.1).set_trans(Tween.TRANS_SINE)

	tile.add_child(_rest_bar(who, big * 0.8))
	return tile


## One segment per fixture of his rest, `done` of them full.
func _rest_bar(who: Dictionary, wide: float) -> Control:
	var bar_data := RecoveryBook.rest_bar(String(who["name"]), int(who["power"]), state, db)
	var full := maxi(1, int(bar_data["full"]))
	var done := int(bar_data["done"])
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 3)
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.custom_minimum_size = Vector2(wide, 12)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var each := (wide - 3.0 * (full - 1)) / float(full)
	for i in full:
		var piece := Panel.new()
		piece.custom_minimum_size = Vector2(maxf(each, 4.0), 12)
		piece.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var box := StyleBoxFlat.new()
		# Full segments green; the ones still to sleep grey with a pale edge.
		box.bg_color = Color(0.45, 0.85, 0.42) if i < done else Color(0.22, 0.22, 0.26, 0.95)
		box.border_color = Color(0.05, 0.05, 0.05) if i < done else Color(0.85, 0.85, 0.85, 0.6)
		box.set_border_width_all(2)
		box.set_corner_radius_all(2)
		piece.add_theme_stylebox_override("panel", box)
		bar.add_child(piece)
	return bar


## An empty place in the room. Click it to buy a bed.
func _place_to_buy() -> Control:
	var big := _bed_size()
	var tile := VBoxContainer.new()
	tile.custom_minimum_size = Vector2(big, 0)
	var place := Button.new()
	place.custom_minimum_size = Vector2(big, big * 0.8)
	place.text = "+ bed"
	place.add_theme_font_size_override("font_size", 14)
	var face := ThemeBook.font(String(ThemeBook.row_for("heading").get("font", "")))
	if face != null:
		place.add_theme_font_override("font", face)
	var empty := StyleBoxFlat.new()
	empty.bg_color = Color(0, 0, 0, 0.35)
	empty.border_color = Color(1, 1, 1, 0.25)
	empty.set_border_width_all(2)
	empty.set_corner_radius_all(6)
	var lit := empty.duplicate() as StyleBoxFlat
	lit.border_color = MenuSupport.COLOUR_ACCENT
	place.add_theme_stylebox_override("normal", empty)
	place.add_theme_stylebox_override("hover", lit)
	place.add_theme_stylebox_override("pressed", lit)
	place.add_theme_stylebox_override("focus", MenuSupport.focus_style())
	place.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	place.tooltip_text = "An empty place - buy a bed for %s" % _bed_price_words()
	place.pressed.connect(_buy_bed)
	tile.add_child(place)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	tile.add_child(spacer)
	return tile


func _show_hover(who: Dictionary, over: Control) -> void:
	_hover_words.text = "%s\nP:%d  ·  %d to go" % [who["name"], int(who["power"]), int(who["left"])]
	_hover.reset_size()
	_hover.visible = true
	var at := over.get_global_rect()
	_hover.global_position = Vector2(at.position.x + at.size.x * 0.5 - _hover.size.x * 0.5,
		at.position.y - _hover.size.y - 4.0)


func _who_words(who: Dictionary) -> String:
	if bool(who.get("brewer", false)):
		return "%s  ·  Brewer, efficiency %d" % [who["name"], int(who["power"])]
	return "%s  ·  Tier %s  ·  P:%d" % [who["name"], who["tier"], int(who["power"])]


# ---- THE SHOP ------------------------------------------------

func _fill_shop(asleep: int, on: bool) -> void:
	for child in _shop.get_children():
		child.queue_free()
	var beds := BaseRooms.beds(state)
	var places := BaseRooms.bed_places(state)

	# A SINGLE BED.
	var bed_col := _shop_column("A SINGLE BED")
	var room_left := places - beds
	bed_col.add_child(_small("%s each. Goes in the next empty place. %d place(s) left in your rooms." % [
		_bed_price_words(), room_left]))
	bed_col.add_child(_buy_button("Buy a bed · " + _bed_price_words(),
		room_left > 0 and _can_pay(_bed_price(), _bed_currency()), _buy_bed))

	# THE NEXT ROOM.
	var nxt := BaseRooms.next_room(state)
	var room_col := _shop_column("AN EXTRA ROOM")
	if nxt.is_empty():
		room_col.add_child(_small("You have every room there is (dorm_max_rooms in Tuning.csv)."))
	else:
		var ok := DialogueGrammar.test(String(nxt["requires"]), state)
		room_col.add_child(_small("%s: room for %d more beds, a new tab above.%s" % [
			nxt["name"], BaseRooms.beds_per_room(),
			"" if ok else "  " + DialogueGrammar.describe(String(nxt["requires"]))]))
		room_col.add_child(_buy_button("Buy %s · %s" % [nxt["name"], _price_words(int(nxt["price"]), String(nxt["currency"]))],
			ok and _can_pay(int(nxt["price"]), String(nxt["currency"])),
			_buy_room.bind(String(nxt["id"]))))

	# EVERY ROOM'S PRICE, so you can see what is ahead.
	var list_col := _shop_column("ROOM PRICES")
	var lines: PackedStringArray = []
	for room in BaseRooms.dorms():
		var mine := BaseRooms.owns_dorm(String(room["id"]), state)
		lines.append("%s  %s" % [room["name"], "yours" if mine
			else _price_words(int(room["price"]), String(room["currency"]))])
	var listing := _small("\n".join(lines.slice(0, 5)))
	var listing2 := _small("\n".join(lines.slice(5)))
	listing.autowrap_mode = TextServer.AUTOWRAP_OFF
	listing2.autowrap_mode = TextServer.AUTOWRAP_OFF
	var two := HBoxContainer.new()
	two.add_theme_constant_override("separation", 22)
	two.add_child(listing)
	two.add_child(listing2)
	list_col.add_child(two)

	# THE REST DAY (rest_day_cost in Tuning.csv; below 0 hides it).
	var rest_price := db.tune_int("rest_day_cost", 0) if db != null else -1
	if on and rest_price >= 0 and asleep > 0:
		var day_col := _shop_column("A REST DAY")
		day_col.add_child(_small("Too many asleep to field a side? Everybody is one fixture nearer fit."))
		day_col.add_child(_buy_button("Rest day · " + ("free" if rest_price == 0 else "%d coins" % rest_price),
			_can_pay(rest_price, "coins"), _rest_day))


func _shop_column(title: String) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	col.add_child(MenuSupport.heading(title, 15, MenuSupport.COLOUR_TEXT))
	_shop.add_child(col)
	return col


func _buy_bed() -> void:
	_say(BaseRooms.buy_bed(state))


func _buy_room(id_text: String) -> void:
	var before := BaseRooms.rooms_owned(state).size()
	var result := BaseRooms.buy_dorm(id_text, state)
	# A NEW ROOM IS A NEW TAB: go and look at it.
	if bool(result["ok"]):
		_room = before
	_say(result)


func _rest_day() -> void:
	_say(RecoveryBook.rest_day(state, db))


# =============================================================
#  SMALL PIECES
# =============================================================

func _say(result: Dictionary, rebuild: bool = true) -> void:
	_status.text = String(result["why"])
	_status.add_theme_color_override("font_color",
		MenuSupport.COLOUR_TEXT if bool(result["ok"]) else Color(1.0, 0.72, 0.4))
	if not rebuild:
		return
	if bool(result["ok"]):
		state.save_to_disk()
	_rebuild()


func _bed_size() -> float:
	return maxf(32.0, db.tune_float("dorm_bed_size", 96.0) if db != null else 96.0)


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


func _can_pay(price: int, currency_id: String) -> bool:
	if price <= 0:
		return true
	return ShopBook.purse(currency_id, state) >= price


func _words(text: String, size: int, colour: Color) -> Label:
	var label := MenuSupport.heading(text, size, colour)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _small(text: String) -> Label:
	var label := MenuSupport.heading(text, 13, MenuSupport.COLOUR_TEXT_DIM)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _buy_button(words: String, allowed: bool, what: Callable) -> Button:
	var button := Button.new()
	button.text = words
	button.custom_minimum_size = Vector2(200.0, 38.0)
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.disabled = not allowed
	var tint := MenuSupport.COLOUR_ATTACK if allowed else MenuSupport.COLOUR_TEXT_DIM
	button.add_theme_stylebox_override("normal", MenuSupport.panel_style(MenuSupport.COLOUR_PANEL, tint))
	button.add_theme_stylebox_override("hover", MenuSupport.panel_style(MenuSupport.COLOUR_SLOT_EMPTY, tint))
	button.add_theme_stylebox_override("disabled", MenuSupport.panel_style(MenuSupport.COLOUR_BACKGROUND, tint))
	button.add_theme_stylebox_override("focus", MenuSupport.focus_style())
	button.add_theme_color_override("font_color", tint)
	button.add_theme_color_override("font_disabled_color", tint)
	var face := ThemeBook.font(String(ThemeBook.row_for("heading").get("font", "")))
	if face != null:
		button.add_theme_font_override("font", face)
	button.pressed.connect(what)
	return button


func _texture(path: String) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


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
