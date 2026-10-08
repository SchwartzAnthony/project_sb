class_name LineUpParade
extends CanvasLayer

# =============================================================
#  THE LINE-UPS, ON THE GRASS  (round AN)
#
#  Anthony: "I don't want to have a top down list, but them standing on the
#  field and the camera goes from right to left for our team and then left
#  to right for their team showing the correct names and sprites, all of
#  them in the idle phase."
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
#  The real pitch, frozen, everyone on their own spot and standing in idle,
#  facing the camera. The camera pushes in and pans along YOUR side from
#  right to left, then along THEIRS from left to right. The side not being
#  shown is faded back. A sign at the bottom names whoever is in the middle
#  of the screen: name, tier, power and defence, a star for a Star Player.
#
#  It is the same figures and the same name plates you will play with, so
#  nothing here can show a different sprite from the match.
#
#  A click, space, enter or escape skips the whole thing.
#
#  ============ TUNING (Tuning.csv) ============
#
#      line_up_parade          false = straight from START to the countdown
#      line_up_pan_seconds     how long the pan along one side takes
#      line_up_hold            the pause at each end of a pan
#      line_up_between_sides   the pause between the two sides
#      line_up_zoom            how close, as a multiple of the whole-pitch shot
#      line_up_fade_other      how see-through the side not being shown is
#      line_up_facing          south = everyone faces the camera; ball = they
#                              keep looking at the ball
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
var _title: Label
var _sign: PanelContainer
var _sign_name: Label
var _sign_line: Label
var _shown: Object = null
var _hidden_layers: Array[CanvasLayer] = []


## Put it up over `scene` (the match) and return it. Await `finished`.
static func on_field(scene: Node, database: CardDatabase, view: MatchCamera,
		units: Array, keepers: Dictionary, your_title: String,
		other_title: String) -> LineUpParade:
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
	scene.add_child(made)
	return made


func _ready() -> void:
	# Above the pitch and the HUD, below a dialog.
	layer = 160
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_run()


# =============================================================
#  THE SIGNS
# =============================================================

func _build() -> void:
	# The whole screen catches a click, to skip.
	var catcher := Control.new()
	catcher.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	catcher.gui_input.connect(func(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click != null and click.pressed:
			skip())
	add_child(catcher)

	_title = MenuSupport.heading(my_name, 44, MenuSupport.COLOUR_ACCENT)
	_title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_title.offset_top = 36.0
	_title.offset_bottom = 110.0
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title)

	# The name sign at the bottom: who is in the middle of the screen.
	var bottom := CenterContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -190.0
	bottom.offset_bottom = -60.0
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom)

	_sign = PanelContainer.new()
	_sign.custom_minimum_size = Vector2(520, 0)
	_sign.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sign.add_theme_stylebox_override("panel", MenuSupport.panel_style(
		MenuSupport.COLOUR_PANEL, MenuSupport.COLOUR_ACCENT))
	bottom.add_child(_sign)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sign.add_child(column)

	_sign_name = MenuSupport.heading("", 34, MenuSupport.COLOUR_TEXT)
	_sign_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_sign_name)

	_sign_line = Label.new()
	_sign_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sign_line.add_theme_font_size_override("font_size", 20)
	_sign_line.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	column.add_child(_sign_line)
	_sign.modulate.a = 0.0

	var hint := Label.new()
	hint.text = Loc.text("line_up_skip", "Click, space or escape to skip")
	hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -46.0
	hint.offset_bottom = -16.0
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint)


func _say(who: Object, is_enemy: bool) -> void:
	if who == _shown:
		return
	_shown = who
	var card := (who as PlayerUnit).data if who is PlayerUnit else null
	var tint := Color(0.92, 0.55, 0.45) if is_enemy else MenuSupport.COLOUR_ACCENT
	if card != null:
		_sign_name.text = ("★ " if card.is_star() else "") + NamePlate.short_name(card)
		_sign_line.text = "Tier %s   ·   P %d   ·   D %d" % [card.get_tier_clean(),
			card.get_attack_power(), card.get_defense_power()]
	else:
		var keeper := (who as GoalieUnit).data if who is GoalieUnit else null
		_sign_name.text = keeper.goalie_name if keeper != null and keeper.goalie_name != "" \
			else Loc.text("keeper", "Keeper")
		_sign_line.text = Loc.text("goalkeeper", "Goalkeeper")
	_sign_name.add_theme_color_override("font_color", tint)
	_sign.add_theme_stylebox_override("panel", MenuSupport.panel_style(
		MenuSupport.COLOUR_PANEL, tint))
	_sign.modulate.a = 1.0
	# A small pop, so a new name reads as a new name.
	_sign.pivot_offset = _sign.size * 0.5
	_sign.scale = Vector2(1.06, 1.06)
	create_tween().tween_property(_sign, "scale", Vector2.ONE, 0.15)


# =============================================================
#  THE PANS
# =============================================================

func _run() -> void:
	if camera == null or not is_instance_valid(camera):
		_end()
		return
	var between := maxf(0.0, db.tune_float("line_up_between_sides", 0.9))

	_hide_the_hud(true)
	camera.script_shot(true)
	_face_the_camera(true)
	_hide_keeper_odds(true)

	# YOURS, right to left.
	await _pan(mine, my_keeper, my_name, false, true)
	if _done:
		return
	await _wait(between)
	if _done:
		return
	# THEIRS, left to right.
	await _pan(theirs, their_keeper, their_name, true, false)
	if _done:
		return
	await _wait(between * 0.5)
	_end()


## Pan along one side. `right_to_left` decides which end it starts at.
func _pan(units: Array[PlayerUnit], keeper: Node2D, title: String,
		is_enemy: bool, right_to_left: bool) -> void:
	_title.text = title
	_title.add_theme_color_override("font_color",
		Color(0.92, 0.55, 0.45) if is_enemy else MenuSupport.COLOUR_ACCENT)
	_shown = null

	var fade := clampf(db.tune_float("line_up_fade_other", 0.3), 0.0, 1.0)
	for unit in mine + theirs:
		unit.modulate.a = 1.0 if unit.is_enemy == is_enemy else fade
	for side_keeper in [my_keeper, their_keeper]:
		if side_keeper != null and is_instance_valid(side_keeper):
			side_keeper.modulate.a = 1.0 if side_keeper == keeper else fade

	# Everyone on this side, as points in the picture the camera moves over.
	var who: Array[Node2D] = []
	for unit in units:
		who.append(unit)
	if keeper != null and is_instance_valid(keeper):
		who.append(keeper)
	if who.is_empty():
		return
	var spots: Array[Vector2] = []
	for node in who:
		spots.append(camera.view_xform * node.global_position)

	# A STRAIGHT LINE THROUGH THE SIDE. The tilted pitch runs corner to
	# corner, so the side lies along a slope; the camera follows the best
	# straight line through them instead of jumping up and down from one
	# player to the next.
	var fit := _line_through(spots)
	var low := INF
	var high := -INF
	for spot in spots:
		low = minf(low, spot.x)
		high = maxf(high, spot.x)
	var from_x := high if right_to_left else low
	var to_x := low if right_to_left else high

	var zoom := camera.pitch_zoom * maxf(1.0, db.tune_float("line_up_zoom", 2.2))
	var seconds := maxf(0.5, db.tune_float("line_up_pan_seconds", 5.0))
	var hold := maxf(0.0, db.tune_float("line_up_hold", 0.6))

	var at := func(x: float) -> Vector2:
		return Vector2(x, fit.x + fit.y * x)
	camera.place_shot(at.call(from_x), zoom)
	_name_the_nearest(who, is_enemy)
	await _wait(hold)
	if _done:
		return

	var clock := 0.0
	while clock < seconds and not _done:
		clock += get_process_delta_time()
		var t := clampf(clock / seconds, 0.0, 1.0)
		# Eased at both ends, so it starts and stops like a camera operator.
		var eased := 0.5 - 0.5 * cos(PI * t)
		camera.place_shot(at.call(lerpf(from_x, to_x, eased)), zoom)
		_name_the_nearest(who, is_enemy)
		await get_tree().process_frame
	if _done:
		return
	await _wait(hold)


## y = a + b·x through the points, as Vector2(a, b). Least squares.
func _line_through(spots: Array[Vector2]) -> Vector2:
	var n := float(spots.size())
	var sx := 0.0
	var sy := 0.0
	var sxx := 0.0
	var sxy := 0.0
	for spot in spots:
		sx += spot.x
		sy += spot.y
		sxx += spot.x * spot.x
		sxy += spot.x * spot.y
	var spread := n * sxx - sx * sx
	if absf(spread) < 0.001:
		return Vector2(sy / n, 0.0)
	var b := (n * sxy - sx * sy) / spread
	return Vector2((sy - b * sx) / n, b)


## The sign names whoever stands nearest the middle of the screen.
func _name_the_nearest(who: Array[Node2D], is_enemy: bool) -> void:
	var middle := camera.global_position
	var best: Node2D = null
	var best_gap := INF
	for node in who:
		var gap := absf((camera.view_xform * node.global_position).x - middle.x)
		if gap < best_gap:
			best_gap = gap
			best = node
	if best != null:
		_say(best, is_enemy)


# =============================================================
#  WHILE IT RUNS: NO HUD, EVERYONE FACING US
# =============================================================

func _hide_the_hud(on: bool) -> void:
	if on:
		_hidden_layers.clear()
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
	else:
		for other in _hidden_layers:
			if is_instance_valid(other):
				other.visible = true
		_hidden_layers.clear()


## The keepers' save odds are match information, not part of a line-up.
func _hide_keeper_odds(on: bool) -> void:
	for keeper in [my_keeper, their_keeper]:
		if keeper == null or not is_instance_valid(keeper):
			continue
		var odds := keeper.get_node_or_null("ChanceLabel") as CanvasItem
		if odds != null:
			if on:
				odds.set_meta("line_up_was", odds.visible)
				odds.visible = false
			elif odds.has_meta("line_up_was"):
				odds.visible = bool(odds.get_meta("line_up_was"))
				odds.remove_meta("line_up_was")


func _face_the_camera(on: bool) -> void:
	var facing := db.tune_text("line_up_facing", "south").strip_edges().to_lower()
	var turn := PitchSprite.DIRECTIONS.find(facing)
	for unit in mine + theirs:
		if is_instance_valid(unit):
			unit.pose_facing = turn if on else -1


func _wait(seconds: float) -> void:
	if seconds <= 0.0 or _done:
		return
	await get_tree().create_timer(seconds, true, false, true).timeout


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
	for unit in mine + theirs:
		if is_instance_valid(unit):
			unit.modulate.a = 1.0
	for keeper in [my_keeper, their_keeper]:
		if keeper != null and is_instance_valid(keeper):
			keeper.modulate.a = 1.0
	_face_the_camera(false)
	_hide_keeper_odds(false)
	_hide_the_hud(false)
	if camera != null and is_instance_valid(camera):
		camera.script_shot(false)
	finished.emit()
	queue_free()
