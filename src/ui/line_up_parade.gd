class_name LineUpParade
extends CanvasLayer

# =============================================================
#  THE LINE-UPS, SIDE BY SIDE  (round AN, 24 Oct 2026)
#
#  Anthony (24 Oct, with a photo of a team standing in a row, arm in arm):
#  "Add the team name on top and then go through each name (highlighting the
#  player) one by one and showing their power and tier lvl as well. When
#  they are transformed show them as they would appear on the field. Do
#  this for the player and the enemy team. Allow the player who is playing
#  the game to hit a skip button to get to the match sooner." "All in our
#  art style!"
#
#  ============ WHERE IT SITS ============
#
#      the loading curtain   the ball rolls into the goal (MatchLoader)
#      the VS screen         two beer menus and the six Stars (TeamSheet)
#      THE LINE-UPS          <- here, after START
#      the countdown         3 - 2 - 1 - START
#
#  ============ WHAT HAPPENS ============
#
#  Behind them, the village pitch seen from the side at eye level (the same
#  picture as the loading screen). Your team stands in one row on the grass,
#  shoulder to shoulder, facing us, under the team banner: a hanging club
#  banner with the team's symbol in a gold medallion and its name (blue for
#  you, red for them; Anthony 24 Oct: "not the wooden plank again, the
#  wooden plank is ONLY for the buildings"). One at a time, left to right, a
#  player steps forward in full colour while the rest stay dark, and the
#  beer mat under the banner names him: name, Tier and Power (a star for a
#  Star Player). Then the same for the other team.
#
#  Every figure is the drawn sprite that player wears on the pitch
#  (PitchSprite.window_sheet), so a transformed player — a brew on him —
#  stands here exactly as he will play.
#
#  The yellow SKIP plank bottom right (or space, enter, escape) goes
#  straight to the countdown.
#
#  ============ TUNING (Tuning.csv) ============
#
#      line_up_parade          false = straight from START to the countdown
#      line_up_each            seconds each player is highlighted
#      line_up_hold            the pause on the team name before the first
#      line_up_between_sides   the pause between the two teams
#      line_up_figure_height   how tall the figures stand, part of the screen
#      line_up_dim             how dark the players not highlighted are
#      line_up_background      the side view of the pitch behind the row
#      line_up_shade           how dark that picture is made
#      line_up_banner_mine / line_up_banner_theirs   the two banner pictures
#      line_up_banner_width    how wide the banner is, part of the screen
#      line_up_banner_symbol   where the medallion is in the banner picture
#      line_up_banner_words    where the name goes in the banner picture
# =============================================================

signal finished

var db: CardDatabase
var camera: MatchCamera
## The two sides, as on the pitch. Keepers are GoalieUnits and may be null.
var mine: Array[PlayerUnit] = []
var theirs: Array[PlayerUnit] = []
var my_keeper: Node2D = null
var their_keeper: Node2D = null
var my_name := "YOUR SIDE"
var their_name := "THEM"

var _done := false
var _stage: Control
var _row: Control
var _banner: Control
var my_symbol := ""
var their_symbol := ""
var _mat_box: Control
var _mat_name: Label
var _mat_line: Label
var _skip: Button
var _hidden_layers: Array[CanvasLayer] = []
var _hidden_nodes: Array[CanvasItem] = []
## Slows the whole line-up down; only tools/line_up_shot.gd changes it, to
## film it frame by frame. The line-up runs on real time, not game speed.
var clock_scale := 1.0


## Put it up over `scene` (the match) and return it. Await `finished`.
static func on_field(scene: Node, database: CardDatabase, view: MatchCamera,
		units: Array, keepers: Dictionary, your_title: String,
		other_title: String, your_symbol: String = "",
		other_symbol: String = "") -> LineUpParade:
	var made := LineUpParade.new()
	made.name = "LineUpParade"
	made.db = database
	made.camera = view
	for unit in units:
		var player := unit as PlayerUnit
		if player == null or player.data == null:
			continue
		(made.theirs if player.is_enemy else made.mine).append(player)
	made.my_keeper = keepers.get(false) as Node2D
	made.their_keeper = keepers.get(true) as Node2D
	if your_title != "":
		made.my_name = your_title
	if other_title != "":
		made.their_name = other_title
	made.my_symbol = your_symbol
	made.their_symbol = other_symbol
	scene.add_child(made)
	return made


func _ready() -> void:
	# Above the pitch and the HUD, below a dialog.
	layer = 160
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_run()


func _tune(key: String, otherwise: float) -> float:
	return db.tune_float(key, otherwise) if db != null else otherwise


func _ink() -> Color:
	return Color.from_string(BeerMatCard.value("ink", "#19110a"), Color(0.1, 0.07, 0.04))


# =============================================================
#  THE STAGE: DARK PITCH, SIGN, ROW, BEER MAT, SKIP
# =============================================================

func _build() -> void:
	_stage = Control.new()
	_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stage.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_stage)

	# The pitch from the side, filling the screen, its grass at the bottom.
	var field := TextureRect.new()
	field.texture = ScreenLook.picture(db.tune_text("line_up_background",
		"res://assets/loading/drawn/village.png") if db != null else "res://assets/loading/drawn/village.png")
	field.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	field.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	field.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	field.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	field.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(field)

	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.02, 0.04, clampf(_tune("line_up_shade", 0.15), 0.0, 1.0))
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(shade)

	_row = Control.new()
	_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_row)

	# The beer mat that names whoever is highlighted.
	_mat_box = Control.new()
	_mat_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat_box.size = Vector2(560, 150)
	_stage.add_child(_mat_box)
	_mat_box.add_child(InventoryScreen._mat(_mat_box.size,
		int(BeerMatCard.number("inventory_edge", 60.0)), 0.9))
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 40.0
	column.offset_right = -40.0
	column.offset_top = 22.0
	column.offset_bottom = -22.0
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 0)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat_box.add_child(column)
	_mat_name = _inked(MenuSupport.heading("", 40, _ink()))
	column.add_child(_mat_name)
	_mat_line = _inked(MenuSupport.heading("", 26, _ink()))
	column.add_child(_mat_line)
	_mat_box.modulate.a = 0.0

	# SKIP: the yellow match plank.
	_skip = MenuSupport.icon_button("play|▶", Loc.text("line_up_skip_button", "SKIP"),
		Vector2(220, 64))
	_skip.focus_mode = Control.FOCUS_NONE
	_skip.pressed.connect(skip)
	if not ScreenLook.plank(_skip, "match"):
		InventoryScreen._plank(_skip)
	_stage.add_child(_skip)
	MenuSupport.pin_bottom_right(_skip)

	get_viewport().size_changed.connect(_place_fixed)
	_place_fixed()


func _inked(label: Label) -> Label:
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", _ink())
	label.add_theme_constant_override("outline_size", 0)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	label.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.clip_text = true
	return label


func _screen() -> Vector2:
	return get_viewport().get_visible_rect().size


func _place_fixed() -> void:
	var screen := _screen()
	var under := 300.0
	if _banner != null and is_instance_valid(_banner):
		_banner.position = Vector2((screen.x - _banner.size.x) / 2.0, 6.0)
		under = _banner.position.y + _banner.size.y * 0.86
	_mat_box.position = Vector2((screen.x - _mat_box.size.x) / 2.0, under)


## Four numbers from Tuning.csv, "a,b,c,d".
func _tune_rect(key: String, otherwise: Rect2) -> Rect2:
	var parts := (db.tune_text(key, "") if db != null else "").split(",")
	if parts.size() != 4:
		return otherwise
	return Rect2(float(parts[0]), float(parts[1]),
		float(parts[2]) - float(parts[0]), float(parts[3]) - float(parts[1]))


## The team banner: the cloth, the team's symbol in the medallion, the name.
func _put_up_banner(words: String, symbol: String, theirs: bool) -> void:
	if _banner != null and is_instance_valid(_banner):
		_banner.queue_free()
	var art := ScreenLook.picture(db.tune_text(
		"line_up_banner_theirs" if theirs else "line_up_banner_mine",
		"res://assets/ui/line_up/team_banner_%s.png" % ("theirs" if theirs else "mine")))
	var screen := _screen()
	var wide := screen.x * clampf(_tune("line_up_banner_width", 0.5), 0.2, 1.0)
	var scale_by := wide / art.get_width() if art != null else 1.0
	_banner = Control.new()
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.size = (art.get_size() if art != null else Vector2(1060, 340)) * scale_by
	_stage.add_child(_banner)
	_stage.move_child(_banner, _row.get_index() + 1)
	if art != null:
		var cloth := TextureRect.new()
		cloth.texture = art
		cloth.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		cloth.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		cloth.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		cloth.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_banner.add_child(cloth)

	# The team's symbol, inside the medallion's cream middle.
	var medal := _tune_rect("line_up_banner_symbol", Rect2(92, 72, 156, 156))
	var picture := MenuSupport.icon_texture(symbol) if symbol != "" else null
	if picture != null:
		var crest := TextureRect.new()
		crest.texture = picture
		crest.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		crest.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		# Old pixel symbols stay sharp; drawn ones are smoothed.
		crest.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST \
			if picture.get_width() <= 128 else CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		var inset := medal.size * 0.04
		crest.position = (medal.position + inset) * scale_by
		crest.size = (medal.size - inset * 2.0) * scale_by
		crest.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_banner.add_child(crest)

	# The name, cream with an ink edge, as big as fits.
	var room := _tune_rect("line_up_banner_words", Rect2(290, 84, 670, 128))
	var box := Rect2(room.position * scale_by, room.size * scale_by)
	var text_size := int(box.size.y * 0.62)
	var font := MenuSupport.heading("x", 10).get_theme_font("font")
	while text_size > 16 and font != null and \
			font.get_string_size(words, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size).x > box.size.x:
		text_size -= 2
	var cream := Color("f6ead0")
	var ink := Color("19110a")
	var reach := maxf(2.0, text_size * 0.07)
	for i in 9:
		var edge := i < 8
		var label := MenuSupport.heading(words, text_size, ink if edge else cream)
		label.add_theme_constant_override("outline_size", 0)
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
		label.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.position = box.position
		label.size = box.size
		if edge:
			label.position += Vector2.RIGHT.rotated(TAU * i / 8.0) * reach
		_banner.add_child(label)
	_place_fixed()


# =============================================================
#  ONE TEAM IN A ROW
# =============================================================

## The order they stand in: the keeper, then by Tier, the Stars last.
func _order(units: Array[PlayerUnit]) -> Array[PlayerUnit]:
	var sorted := units.duplicate()
	sorted.sort_custom(func(a: PlayerUnit, b: PlayerUnit) -> bool:
		var star_a := 1 if a.data.shows_star() else 0
		var star_b := 1 if b.data.shows_star() else 0
		if star_a != star_b:
			return star_a < star_b
		return a.data.get_tier_index() < b.data.get_tier_index())
	return sorted


## A figure as it stands on the pitch: the drawn idle, facing us.
func _figure(card: PlayerData, tall: float) -> Control:
	var sheet := PitchSprite.window_sheet(card)
	var spec := PitchSprite.window_spec(sheet, "idle", 2) if sheet != null else null
	if spec == null:
		return MenuSupport.portrait_rect(card, db, Vector2(tall * 0.5, tall))
	var figure := SpriteAnimator.new()
	figure.play(sheet, spec)
	# One zoom for every sheet, so a tall player stands taller than a short
	# one, the same as on the pitch.
	var look := PitchSprite.look_of(sheet)
	var zoom := tall / float(look["cell"]) * float(look["size"]) * 1.25
	figure.custom_minimum_size = Vector2(figure.crop_size()) * zoom
	figure.size = figure.custom_minimum_size
	return figure


## The keeper's own picture from the pitch, standing still.
func _keeper_figure(keeper: Node2D, tall: float) -> Control:
	var art := keeper.get_node_or_null("Artwork") as Sprite2D
	if art == null or art.texture == null:
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = art.texture
	if art.region_enabled:
		atlas.region = art.region_rect
	else:
		var cell := art.texture.get_size() / Vector2(art.hframes, art.vframes)
		atlas.region = Rect2(Vector2(art.frame % art.hframes, art.frame / art.hframes) * cell, cell)
	var picture := TextureRect.new()
	picture.texture = atlas
	picture.texture_filter = art.texture_filter if art.texture_filter != \
		CanvasItem.TEXTURE_FILTER_PARENT_NODE else CanvasItem.TEXTURE_FILTER_NEAREST
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.flip_h = art.flip_h
	var wide := atlas.region.size.x / maxf(1.0, atlas.region.size.y) * tall * 0.8
	picture.custom_minimum_size = Vector2(wide, tall * 0.8)
	picture.size = picture.custom_minimum_size
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return picture


## Lay one team out in a row. Returns [{node, card, keeper}] left to right.
func _stand_up(units: Array[PlayerUnit], keeper: Node2D) -> Array[Dictionary]:
	for old in _row.get_children():
		old.queue_free()
	var screen := _screen()
	var tall := screen.y * clampf(_tune("line_up_figure_height", 0.36), 0.1, 0.8)
	var people: Array[Dictionary] = []
	if keeper != null and is_instance_valid(keeper):
		var picture := _keeper_figure(keeper, tall)
		if picture != null:
			people.append({"node": picture, "card": null, "keeper": keeper})
	for unit in _order(units):
		if is_instance_valid(unit) and unit.data != null:
			people.append({"node": _figure(unit.data, tall), "card": unit.data, "keeper": null})
	if people.is_empty():
		return people

	# Shoulder to shoulder: each figure overlaps the next a little, like the
	# arms round each other in the photo. Squeezed tighter if the row would
	# not fit across the screen.
	var widths := 0.0
	for person in people:
		widths += (person["node"] as Control).size.x
	var room := screen.x * 0.92
	var overlap := clampf(_tune("line_up_overlap", 0.22), 0.0, 0.6)
	var step_scale := 1.0 - overlap
	if widths * step_scale > room:
		step_scale = room / widths
	var x := (screen.x - widths * step_scale) / 2.0
	# Feet on the grass near the bottom of the picture.
	var feet := screen.y * clampf(_tune("line_up_feet", 0.92), 0.5, 1.0)
	for person in people:
		var node := person["node"] as Control
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var width := node.size.x
		node.position = Vector2(x + width * (step_scale - 1.0) / 2.0, feet - node.size.y)
		node.pivot_offset = Vector2(width / 2.0, node.size.y)
		node.modulate = _dark()
		_row.add_child(node)
		person["home"] = node.position
		x += width * step_scale
	return people


func _dark() -> Color:
	var dim := clampf(_tune("line_up_dim", 0.35), 0.0, 1.0)
	return Color(dim, dim, dim, 1.0)


## Light one up and name them on the beer mat.
func _highlight(people: Array[Dictionary], index: int) -> void:
	for i in people.size():
		var node := people[i]["node"] as Control
		if not is_instance_valid(node):
			continue
		var lit := i == index
		var tween := _tween().set_parallel(true)
		tween.tween_property(node, "modulate", Color.WHITE if lit else _dark(), 0.18)
		tween.tween_property(node, "scale", Vector2.ONE * (1.12 if lit else 1.0), 0.18)
		tween.tween_property(node, "position",
			Vector2(people[i]["home"]) + (Vector2(0, 14) if lit else Vector2.ZERO), 0.18)
	# The one stepping forward is drawn over his neighbours.
	var front := people[index]["node"] as Control
	_row.move_child(front, -1)

	var card := people[index]["card"] as PlayerData
	if card != null:
		_mat_name.text = ("★ " if card.shows_star() else "") + NamePlate.short_name(card)
		_mat_line.text = "%s %s   ·   %s %d" % [Loc.text("tier", "Tier"),
			card.get_tier_clean(), Loc.text("power", "Power"), card.get_attack_power()]
	else:
		var keeper := people[index]["keeper"] as GoalieUnit
		var named := keeper.data.goalie_name if keeper != null and keeper.data != null else ""
		_mat_name.text = named if named != "" else Loc.text("keeper", "Keeper")
		_mat_line.text = Loc.text("goalkeeper", "Goalkeeper")
	_mat_box.modulate.a = 1.0
	_mat_box.pivot_offset = _mat_box.size * 0.5
	_mat_box.scale = Vector2(1.06, 1.06)
	_tween().tween_property(_mat_box, "scale", Vector2.ONE, 0.15)


func _show_team(units: Array[PlayerUnit], keeper: Node2D, title: String,
		symbol: String, theirs: bool) -> void:
	_mat_box.modulate.a = 0.0
	_put_up_banner(title, symbol, theirs)
	var people := _stand_up(units, keeper)
	if people.is_empty():
		return
	_row.modulate.a = 0.0
	_tween().tween_property(_row, "modulate:a", 1.0, 0.3)
	await _wait(maxf(0.0, _tune("line_up_hold", 0.8)))
	var each := maxf(0.2, _tune("line_up_each", 0.8))
	for i in people.size():
		if _done:
			return
		_highlight(people, i)
		await _wait(each)


# =============================================================
#  THE RUN
# =============================================================

func _run() -> void:
	_hide_the_pitch_layers(true)
	await _show_team(mine, my_keeper, my_name, my_symbol, false)
	if _done:
		return
	await _wait(maxf(0.0, _tune("line_up_between_sides", 0.6)))
	if _done:
		return
	await _show_team(theirs, their_keeper, their_name, their_symbol, true)
	if _done:
		return
	await _wait(maxf(0.0, _tune("line_up_between_sides", 0.6)))
	_end()


## The HUD and the name ribbons over the pitch, out of the way.
func _hide_the_pitch_layers(on: bool) -> void:
	if on:
		_hidden_layers.clear()
		_hidden_nodes.clear()
		var scene := get_parent()
		if scene == null:
			return
		for layer_node in scene.find_children("*", "CanvasLayer", true, false):
			var other := layer_node as CanvasLayer
			if other == null or other == self or not other.visible:
				continue
			# Only the screens drawn OVER the pitch.
			if other.layer < 1 or other.layer >= layer:
				continue
			other.visible = false
			_hidden_layers.append(other)
		# Everyone on the pitch steps off it while they stand in the row:
		# the same players twice would only confuse.
		var on_pitch: Array = mine + theirs
		on_pitch.append_array([my_keeper, their_keeper])
		for node in on_pitch:
			var item := node as CanvasItem
			if item != null and is_instance_valid(item) and item.visible:
				item.visible = false
				_hidden_nodes.append(item)
	else:
		for other in _hidden_layers:
			if is_instance_valid(other):
				other.visible = true
		_hidden_layers.clear()
		for node in _hidden_nodes:
			if is_instance_valid(node):
				node.visible = true
		_hidden_nodes.clear()


func _wait(seconds: float) -> void:
	if seconds <= 0.0 or _done:
		return
	await get_tree().create_timer(seconds / clock_scale, true, false, true).timeout


func _tween() -> Tween:
	return create_tween().set_ignore_time_scale(true).set_speed_scale(clock_scale)


# =============================================================
#  GETTING OUT OF IT
# =============================================================

func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode in [KEY_ESCAPE, KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		get_viewport().set_input_as_handled()
		skip()


func skip() -> void:
	if _done:
		return
	print("[lineup] skipped.")
	_end()


func _end() -> void:
	if _done:
		return
	_done = true
	_hide_the_pitch_layers(false)
	finished.emit()
	queue_free()
