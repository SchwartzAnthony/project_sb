class_name IsoField
extends RefCounted

# =============================================================
#  THE ISOMETRIC FIELD  (adventure-look, 10 Oct 2026)
#
#  Anthony (QAL1): "full iso field". The run is played on an isometric
#  board of PixelLab tiles, like a 1980s Bavarian role-playing game from the
#  comics: a path through the marsh, grass either side, bog water beyond,
#  and reeds, willows and the rest going past.
#
#  ============ HOW, WITHOUT TOUCHING THE RULES ============
#
#  The run still thinks in two numbers: how far along (x) and where across
#  the lane (y). Nothing about pickups, waves or the fight changed. This file
#  only TILTS that flat world into the isometric view:
#
#      along the run  ->  up and to the right on screen
#      across the lane ->  down and to the right
#
#  Everything standing on the field (players, enemies, drops, the ball, the
#  numbers that float off a hit) is kept UPRIGHT and crisp: only where it
#  stands is tilted, never the picture. And it is drawn front to back, so
#  whoever is nearer the bottom of the screen is in front.
#
#  ============ WHAT YOU CAN CHANGE ============
#
#  Tuning.csv:
#    adventure_iso_field     false = the old flat lane
#    adventure_iso_squash    how flat the view is (0.5 = classic 2:1)
#    adventure_iso_scale     screen pixels per run pixel (0.8 = a bit closer)
#    adventure_iso_party_x/y where on screen the party runs
#    adventure_iso_tile_zoom how many times bigger each tile is drawn
#    adventure_iso_spawn_x   how far along things appear (off the top right)
#
#  data/AdventureTiles.csv  which tiles make each biome's ground, by zone:
#      path     the rows down the middle of the lane
#      lane     the rest of the lane (where the players run)
#      edge     the first rows outside the lane
#      outside  everything beyond
#    Several rows for one zone = picked at random by Weight.
#
#  data/AdventureDecor.csv  what goes past beside the lane (willows, reeds,
#    a sunken goal ...): which side, how far out, how often, how big.
# =============================================================

const TILES_PATH := "res://data/AdventureTiles.csv"
const DECOR_PATH := "res://data/AdventureDecor.csv"

## World to screen: x column = one step along the run, y column = one step
## across the lane, origin = where world (0, 0) lands.
var to_screen := Transform2D.IDENTITY
## The inverse of the tilt only (no origin): what keeps a picture upright.
var upright := Transform2D.IDENTITY
## How far along things appear and are let go of.
var spawn_x := 1900.0
var forget_x := -800.0

var _world: Node2D
var _tiles: Node2D
var _cell := 71.6
var _columns := 0
var _rows: Array[float] = []
var _first_column := 0.0
var _sprites: Array[Sprite2D] = []
var _column_of: Array[int] = []
var _row_of: Array[int] = []
var _base_column := -999999
var _zones: Dictionary = {}           # zone -> Array of {texture, weight}
var _zone_of_row: Array[String] = []
var _tile_zoom := 2.0
## How far the picture is moved down so its top diamond lands on the cell,
## in the tile's own pixels (Tuning adventure_iso_tile_lift).
var _tile_lift := 0.0

var _decor_rows: Array[Dictionary] = []
var _decor: Array[Node2D] = []
var _next_decor := {}                 # row index -> world distance of next one
var _lane_top := 0.0
var _lane_bottom := 0.0


## Builds the field under `world`. Returns null when Tuning turns it off, so
## the scene keeps its flat lane.
static func make(world: Node2D, db: CardDatabase, biome_id: String,
		lane_top: float, lane_bottom: float, party_x: float,
		screen: Vector2) -> IsoField:
	if db == null or not db.tune_bool("adventure_iso_field", true):
		return null
	var field := IsoField.new()
	field._setup(world, db, biome_id, lane_top, lane_bottom, party_x, screen)
	return field


func _setup(world: Node2D, db: CardDatabase, biome_id: String,
		lane_top: float, lane_bottom: float, party_x: float, screen: Vector2) -> void:
	_world = world
	_lane_top = lane_top
	_lane_bottom = lane_bottom
	var squash := clampf(db.tune_float("adventure_iso_squash", 0.5), 0.2, 1.0)
	# How many screen pixels one run pixel is. Below 1 brings the party and
	# the enemies closer together on screen; the pictures keep their size.
	var unit := clampf(db.tune_float("adventure_iso_scale", 0.8), 0.3, 2.0)
	var along := Vector2(1.0, -squash).normalized() * unit
	var across := Vector2(1.0, squash).normalized() * unit
	var middle := (lane_top + lane_bottom) * 0.5
	var party_at := Vector2(db.tune_float("adventure_iso_party_x", 660.0),
		db.tune_float("adventure_iso_party_y", 600.0))
	to_screen = Transform2D(along, across, party_at - along * party_x - across * middle)
	upright = Transform2D(along, across, Vector2.ZERO).affine_inverse()
	world.transform = to_screen
	spawn_x = db.tune_float("adventure_iso_spawn_x", 1900.0)
	forget_x = db.tune_float("adventure_iso_forget_x", -800.0)

	_tile_zoom = maxf(1.0, db.tune_float("adventure_iso_tile_zoom", 2.0))
	_tile_lift = db.tune_float("adventure_iso_tile_lift", 0.0)
	_read_tiles(biome_id)
	_build_tiles(screen, along, squash)
	_read_decor(biome_id)
	# Scenery already in place when the run opens, not only arriving.
	var x := forget_x
	while x < spawn_x:
		_place_decor_up_to(x, x)
		x += 40.0


# -------------------------------------------------------------
#  THE TILES
# -------------------------------------------------------------

func _read_tiles(biome_id: String) -> void:
	var wanted := biome_id.strip_edges().to_lower()
	for row in MenuSupport.read_csv(TILES_PATH):
		var biome := MenuSupport.field(row, "Biome").strip_edges().to_lower()
		if biome != wanted and biome != "*":
			continue
		var zone := MenuSupport.field(row, "Zone").strip_edges().to_lower()
		var art := MenuSupport.icon_texture(MenuSupport.field(row, "Image"))
		if zone == "" or art == null:
			continue
		if not _zones.has(zone):
			_zones[zone] = []
		(_zones[zone] as Array).append({"texture": art,
			"weight": maxf(0.01, MenuSupport.field_float(row, "Weight", 1.0))})


func _build_tiles(screen: Vector2, along: Vector2, squash: float) -> void:
	if _zones.is_empty():
		return
	# One cell of the board is one tile's diamond: its edge, tilted, is half
	# the tile wide and half the diamond high.
	var sample: Texture2D = ((_zones.values()[0] as Array)[0] as Dictionary)["texture"]
	var half_wide := sample.get_width() * _tile_zoom * 0.5
	_cell = half_wide / along.x

	_tiles = Node2D.new()
	_tiles.name = "Tiles"
	_tiles.z_index = -3000
	_tiles.z_as_relative = false
	_world.add_child(_tiles)

	# Which part of the flat world the screen can see, with a margin.
	var back := to_screen.affine_inverse()
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for corner in [Vector2.ZERO, Vector2(screen.x, 0.0), Vector2(0.0, screen.y), screen]:
		var flat: Vector2 = back * corner
		low = low.min(flat)
		high = high.max(flat)
	var margin := _cell * 2.0
	low -= Vector2(margin, margin)
	high += Vector2(margin, margin)

	# Rows are one tile apart (the tiles must meet exactly), starting on the
	# top edge of the lane.
	var lane_rows := maxi(1, int(roundf((_lane_bottom - _lane_top) / _cell)))
	var lane_cell := _cell
	var path_rows := 2 if lane_rows >= 4 else 1
	var y := _lane_top - lane_cell * ceilf((_lane_top - low.y) / lane_cell)
	var index := 0
	while y < high.y:
		var centre := y + lane_cell * 0.5
		_rows.append(centre)
		var zone := "outside"
		if centre > _lane_top and centre < _lane_bottom:
			var from_middle := absf(centre - (_lane_top + _lane_bottom) * 0.5)
			zone = "path" if from_middle < lane_cell * path_rows * 0.5 else "lane"
		elif centre > _lane_top - lane_cell * 1.5 and centre < _lane_bottom + lane_cell * 1.5:
			zone = "edge"
		_zone_of_row.append(zone)
		y += lane_cell
		index += 1

	_first_column = floorf(low.x / _cell)
	_columns = int(ceilf((high.x - low.x) / _cell)) + 2
	var screen_rect := Rect2(Vector2(-200.0, -200.0), screen + Vector2(400.0, 400.0))
	for column in _columns:
		for row in _rows.size():
			# Only cells that can ever be on screen while the board slides
			# one cell along.
			var flat := Vector2((_first_column + column) * _cell, _rows[row])
			var on_screen := to_screen * flat
			if not screen_rect.has_point(on_screen) \
					and not screen_rect.has_point(to_screen * (flat + Vector2(_cell, 0.0))):
				continue
			var sprite := Sprite2D.new()
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sprite.transform = Transform2D(upright.x * _tile_zoom, upright.y * _tile_zoom, flat)
			# A PixelLab block tile: its top diamond sits above the middle of
			# the picture (the sides hang below), so it is lifted onto the cell.
			sprite.offset = Vector2(0.0, _tile_lift)
			# Back to front, so a nearer tile covers the sides of the one
			# behind it. The order never changes as the board slides.
			sprite.z_index = int(on_screen.y * 0.5)
			_tiles.add_child(sprite)
			_sprites.append(sprite)
			_column_of.append(column)
			_row_of.append(row)


func _texture_for(zone: String, column: int, row: int) -> Texture2D:
	var choices: Array = _zones.get(zone, [])
	if choices.is_empty():
		choices = _zones.get("lane", _zones.values()[0])
	var total := 0.0
	for choice in choices:
		total += float(choice["weight"])
	# The same cell always gets the same tile, so the board does not flicker.
	var roll := float(absi(hash(Vector2i(column, row))) % 10000) / 10000.0 * total
	for choice in choices:
		roll -= float(choice["weight"])
		if roll <= 0.0:
			return choice["texture"]
	return (choices[0] as Dictionary)["texture"]


# -------------------------------------------------------------
#  EVERY FRAME
# -------------------------------------------------------------

func has_tiles() -> bool:
	return _tiles != null


## Slides the board and the scenery by how far the party has come, and
## keeps everything on the field upright and drawn front to back.
func update(travelled: float, step: float) -> void:
	if _tiles != null:
		_tiles.position.x = -fposmod(travelled, _cell)
		var base := int(floorf(travelled / _cell))
		if base != _base_column:
			_base_column = base
			for i in _sprites.size():
				var row := _row_of[i]
				_sprites[i].texture = _texture_for(_zone_of_row[row],
					base + int(_first_column) + _column_of[i], row)

	if step != 0.0:
		var still: Array[Node2D] = []
		for thing in _decor:
			if not is_instance_valid(thing):
				continue
			thing.position.x -= step
			if thing.position.x < forget_x:
				thing.queue_free()
			else:
				still.append(thing)
		_decor = still
		_place_decor_up_to(travelled + spawn_x, spawn_x)

	stand_up()


## Upright and front to back: everything standing on the field.
func stand_up() -> void:
	for child in _world.get_children():
		if child == _tiles or child.name == "Ground":
			continue
		if child is Node2D:
			var thing := child as Node2D
			thing.transform = Transform2D(upright.x, upright.y, thing.position)
			thing.z_as_relative = false
			# z_index stops at 4096, so the screen height is squeezed into it.
			thing.z_index = clampi(int((to_screen * thing.position).y), -1500, 1900) \
				+ (2000 if thing.has_meta("float_on_top") else 0)


# -------------------------------------------------------------
#  THE SCENERY GOING PAST
# -------------------------------------------------------------

func _read_decor(biome_id: String) -> void:
	var wanted := biome_id.strip_edges().to_lower()
	for row in MenuSupport.read_csv(DECOR_PATH):
		var biome := MenuSupport.field(row, "Biome").strip_edges().to_lower()
		if biome != wanted and biome != "*":
			continue
		var art := MenuSupport.icon_texture(MenuSupport.field(row, "Image"))
		if art == null:
			continue
		_decor_rows.append({
			"texture": art,
			"side": MenuSupport.field(row, "Side", "both").strip_edges().to_lower(),
			"out_min": MenuSupport.field_float(row, "Out Min", 60.0),
			"out_max": MenuSupport.field_float(row, "Out Max", 400.0),
			"gap": maxf(20.0, MenuSupport.field_float(row, "Gap", 300.0)),
			"zoom": maxf(0.25, MenuSupport.field_float(row, "Scale", 2.0)),
		})
	for i in _decor_rows.size():
		_next_decor[i] = forget_x + randf() * float(_decor_rows[i]["gap"])


## Puts down every piece of scenery due before `far` (a distance along the
## run), at `at_x` in the world plus however far past that point it is due.
func _place_decor_up_to(far: float, at_x: float) -> void:
	for i in _decor_rows.size():
		var entry: Dictionary = _decor_rows[i]
		while float(_next_decor[i]) <= far:
			var due := float(_next_decor[i])
			var x := at_x - (far - due)
			var side: String = entry["side"]
			var below := side == "below" or (side == "both" and randf() < 0.5)
			var out := randf_range(float(entry["out_min"]), float(entry["out_max"]))
			var y := _lane_bottom + out if below else _lane_top - out
			var sprite := Sprite2D.new()
			sprite.texture = entry["texture"]
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sprite.centered = true
			sprite.scale = Vector2.ONE * float(entry["zoom"])
			# Standing on its spot: its bottom edge at the holder's position.
			sprite.position = Vector2(0.0, -sprite.texture.get_height() * float(entry["zoom"]) * 0.5)
			if randf() < 0.5:
				sprite.flip_h = true
			var holder := Node2D.new()
			holder.name = "Decor"
			holder.position = Vector2(x, y)
			holder.add_child(sprite)
			_world.add_child(holder)
			_decor.append(holder)
			_next_decor[i] = due + float(entry["gap"]) * randf_range(0.6, 1.4)
