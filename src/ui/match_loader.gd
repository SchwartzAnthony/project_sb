class_name MatchLoader
extends CanvasLayer

# =============================================================
#  THE WAY INTO A MATCH — black at once, then a ball rolling into a goal
#
#  Anthony (round AN): "loading the first match stalls, shows a random part
#  of the base, then the loading screen." The match scene is big. It used to
#  be loaded in ONE frame by change_scene_to_file(), so the old screen froze,
#  and then the pitch and its village were drawn for a frame or two before
#  the team sheet covered them.
#
#  Now, the moment you ask for a match:
#
#    1. The screen fades to black (`match_loader_fade_in`, a blink).
#    2. The Alps come up, with a goal on the right. A ball rolls along the
#       bottom of the screen towards it while the match loads IN THE
#       BACKGROUND (a second thread), so nothing freezes.
#    3. The match is put in behind this curtain. The curtain lifts only when
#       the match says it is ready (the team sheet opening) — so the pitch
#       is never seen half-built.
#    4. The ball goes in, and the curtain fades away over
#       `match_loader_fade_out`, showing the team sheet.
#
#  The ball follows whichever is further behind — the real loading or the
#  `match_loader_seconds` clock — so it never jumps in at once on a fast
#  machine and never reaches the goal before the match is really there.
#
#  ============ TUNING (all in Tuning.csv) ============
#
#      match_loader              false = the old way: straight to the match
#      match_loader_fade_in      seconds to fade to black
#      match_loader_seconds      the shortest time the ball takes to roll
#      match_loader_fade_out     seconds for the curtain to lift
#      match_loader_background   the Alps picture (res:// path)
#      match_loader_goal         the goal picture
#      match_loader_ball         the ball picture
#      match_loader_ground       how far down the ball rolls, 0 top - 1 bottom
#      match_loader_ball_size    the ball, as a share of the screen height
#      match_loader_goal_size    the goal, as a share of the screen height
#
#  A missing picture is drawn as a plain shape instead, so a wrong path is
#  a plain-looking screen and a printed note, never a crash.
# =============================================================

const NODE_NAME := "MatchLoader"

## The furthest the ball goes while the match is still not ready, as a share
## of the way to the goal. It waits here rather than scoring early.
const WAIT_SHARE := 0.85
## If the match never says it is ready (an old scene, a crash in _ready),
## the curtain lifts by itself after this many seconds in the match.
const GIVE_UP_SECONDS := 4.0
## A curtain that was put up by cover() but never told which match to load
## (the next screen asked you to pick after all) lifts after this long.
const NOTHING_CAME_SECONDS := 1.5

var _path := ""
var _requested := false
var _swapped := false
var _ready_said := false
var _scored := false
var _leaving := false

var _clock := 0.0
var _art_up := false
var _shown := 0.0          # how far the ball is, 0 .. 1
var _since_swap := 0.0

var _seconds := 1.6
var _fade_in := 0.12
var _fade_out := 0.35
var _ground := 0.93
var _ball_share := 0.08
var _goal_share := 0.26

var _root: Control
var _black: ColorRect
var _art: Control
var _ball: TextureRect
var _goal: TextureRect


# -------------------------------------------------------------
#  WHAT OTHER SCRIPTS CALL
# -------------------------------------------------------------

## Is the loading screen switched on in Tuning.csv?
static func enabled() -> bool:
	return CardDatabase.get_db().tune_bool("match_loader", true)


## Go to the match at `path` through the loading screen. Called by
## ScenePaths.go_to() — nothing else needs to.
static func load_into(tree: SceneTree, path: String) -> void:
	var loader := _find_or_make(tree)
	loader._begin_loading(path)


## Black, now, before anything else happens. The base calls this when the
## next screen will step straight through to a match, so the very first
## frame after the click is already going dark.
static func cover(tree: SceneTree) -> void:
	_find_or_make(tree)


## The match calls this when it is ready to be seen (the team sheet is up).
static func match_ready(tree: SceneTree) -> void:
	if tree == null or tree.root == null:
		return
	if not tree.has_meta(NODE_NAME):
		return
	var loader: Variant = tree.get_meta(NODE_NAME)
	if is_instance_valid(loader):
		(loader as MatchLoader)._ready_said = true


## Is a curtain up right now?
static func is_up(tree: SceneTree) -> bool:
	return tree != null and tree.has_meta(NODE_NAME) \
		and is_instance_valid(tree.get_meta(NODE_NAME))


static func _find_or_make(tree: SceneTree) -> MatchLoader:
	# Kept on the tree as well as found by name: a curtain made this frame is
	# not in the tree yet, and asking twice must not make two.
	if tree.has_meta(NODE_NAME):
		var made: Variant = tree.get_meta(NODE_NAME)
		if is_instance_valid(made) and not (made as MatchLoader)._leaving:
			return made as MatchLoader
	var loader := MatchLoader.new()
	loader.name = NODE_NAME
	tree.set_meta(NODE_NAME, loader)
	# DEFERRED: this is very often called from inside a screen's _ready(),
	# while the root is still busy adding that screen.
	tree.root.add_child.call_deferred(loader)
	return loader


# -------------------------------------------------------------
#  BUILDING IT
# -------------------------------------------------------------

func _init() -> void:
	# Over everything, the pause menu and the team sheet included.
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS

	var db := CardDatabase.get_db()
	_seconds = maxf(0.1, db.tune_float("match_loader_seconds", 1.6))
	_fade_in = maxf(0.0, db.tune_float("match_loader_fade_in", 0.12))
	_fade_out = maxf(0.0, db.tune_float("match_loader_fade_out", 0.35))
	_ground = clampf(db.tune_float("match_loader_ground", 0.93), 0.0, 1.0)
	_ball_share = clampf(db.tune_float("match_loader_ball_size", 0.08), 0.01, 1.0)
	_goal_share = clampf(db.tune_float("match_loader_goal_size", 0.26), 0.01, 1.0)

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP   # no clicks through it
	add_child(_root)

	_black = ColorRect.new()
	_black.color = Color.BLACK
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_black.modulate.a = 0.0
	_root.add_child(_black)

	_art = Control.new()
	_art.set_anchors_preset(Control.PRESET_FULL_RECT)
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.modulate.a = 0.0
	_root.add_child(_art)

	var back := TextureRect.new()
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	back.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	back.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	back.texture = _picture("match_loader_background",
		"res://assets/loading/alps_background.png", _plain_alps())
	_art.add_child(back)

	_goal = _sprite(_picture("match_loader_goal",
		"res://assets/loading/goal.png", _plain_goal()))
	_art.add_child(_goal)
	_ball = _sprite(_picture("match_loader_ball",
		"res://assets/loading/ball.png", _plain_ball()))
	_art.add_child(_ball)


func _ready() -> void:
	# 1. BLACK, AT ONCE.
	var dark := create_tween()
	dark.tween_property(_black, "modulate:a", 1.0, _fade_in)
	# 2. THEN THE ALPS, out of the black.
	dark.tween_property(_art, "modulate:a", 1.0, maxf(0.1, _fade_in))
	dark.tween_callback(func() -> void: _art_up = true)
	get_viewport().size_changed.connect(_lay_out)
	_lay_out()


func _sprite(texture: Texture2D) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


## A picture named in Tuning.csv, or the stand-in shape when it is missing.
func _picture(key: String, fallback_path: String, stand_in: Texture2D) -> Texture2D:
	var path := CardDatabase.get_db().tune_text(key, fallback_path)
	if ResourceLoader.exists(path):
		var texture := load(path) as Texture2D
		if texture != null:
			return texture
	push_warning("[loading] %s: no picture at '%s' — drawing a plain one instead." % [key, path])
	return stand_in


func _lay_out() -> void:
	var size := get_viewport().get_visible_rect().size
	var ground_y := size.y * _ground

	var goal_h := size.y * _goal_share
	var goal_w := goal_h * _aspect(_goal.texture)
	_goal.size = Vector2(goal_w, goal_h)
	_goal.position = Vector2(size.x - goal_w - size.x * 0.03, ground_y - goal_h)

	var ball_side := size.y * _ball_share
	_ball.size = Vector2(ball_side, ball_side)
	_ball.pivot_offset = _ball.size * 0.5
	_place_ball()


func _aspect(texture: Texture2D) -> float:
	if texture == null or texture.get_height() == 0:
		return 1.0
	return float(texture.get_width()) / float(texture.get_height())


## The ball's way: from just off the left edge to the middle of the goal mouth.
func _place_ball() -> void:
	if _ball == null:
		return
	var size := get_viewport().get_visible_rect().size
	var side := _ball.size.x
	var start_x := -side
	var end_x := _goal.position.x + _goal.size.x * 0.5 - side * 0.5
	var x := lerpf(start_x, end_x, _shown)
	_ball.position = Vector2(x, size.y * _ground - side)
	# ROLLING, not sliding: turned by exactly the distance it has travelled.
	_ball.rotation = (x - start_x) / maxf(1.0, side * 0.5)


# -------------------------------------------------------------
#  LOADING
# -------------------------------------------------------------

func _begin_loading(path: String) -> void:
	if _path != "":
		return
	_path = path
	var err := ResourceLoader.load_threaded_request(path)
	_requested = err == OK
	if not _requested:
		push_warning("[loading] Could not load '%s' in the background (error %d) — loading it the old way." % [path, err])


func _process(delta: float) -> void:
	if _leaving:
		return
	if _art_up:
		_clock += delta

	# 3. INTO THE MATCH, as soon as it is loaded and the screen is dark.
	if _path != "" and not _swapped and _black.modulate.a >= 1.0:
		_try_swap()
	if _path == "" and _clock >= NOTHING_CAME_SECONDS:
		print("[loading] Covered for a match that never came — lifting.")
		_leaving = true
		_lift()
		return
	if _swapped:
		_since_swap += delta
		if _since_swap >= GIVE_UP_SECONDS and not _ready_said:
			print("[loading] The match never said it was ready — lifting anyway.")
			_ready_said = true

	# THE BALL. Whichever is further behind: the clock or the real work.
	var by_clock := clampf(_clock / _seconds, 0.0, 1.0)
	var by_work := WAIT_SHARE * _progress()
	if _ready_said:
		by_work = 1.0
	var target := minf(by_clock, by_work)
	_shown = move_toward(_shown, target, delta * 1.5 / _seconds)
	_place_ball()

	# 4. GOAL — and away.
	if _shown >= 1.0 and not _scored:
		_scored = true
		_score()


func _progress() -> float:
	if _path == "":
		return 0.0
	if _swapped:
		return 1.0
	if not _requested:
		return 0.5
	var share: Array = []
	ResourceLoader.load_threaded_get_status(_path, share)
	return float(share[0]) if not share.is_empty() else 0.0


func _try_swap() -> void:
	var tree := get_tree()
	if not _requested:
		_swapped = true
		tree.change_scene_to_file(_path)
		return
	var status := ResourceLoader.load_threaded_get_status(_path)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	_swapped = true
	var scene := ResourceLoader.load_threaded_get(_path) as PackedScene
	if scene == null:
		push_warning("[loading] '%s' did not load in the background — loading it the old way." % _path)
		tree.change_scene_to_file(_path)
		return
	tree.change_scene_to_packed(scene)


func _score() -> void:
	_leaving = true
	var pop := create_tween()
	# The net takes it: a little squash of the ball, then the curtain lifts.
	pop.tween_property(_ball, "scale", Vector2(1.25, 0.8), 0.08)
	pop.tween_property(_ball, "scale", Vector2.ONE, 0.08)
	pop.tween_callback(_lift)


func _lift() -> void:
	var away := create_tween()
	away.tween_property(_root, "modulate:a", 0.0, _fade_out)
	away.tween_callback(queue_free)


# -------------------------------------------------------------
#  STAND-INS, for when a picture is missing
# -------------------------------------------------------------

func _plain_alps() -> Texture2D:
	var image := Image.create(64, 36, false, Image.FORMAT_RGBA8)
	image.fill(Color("6fb7e6"))
	for x in 64:
		var peak := 14 + int(8.0 * absf(sin(x * 0.22)))
		for y in range(peak, 36):
			image.set_pixel(x, y, Color("8a9bb0") if y < 30 else Color("4f9a3c"))
	return ImageTexture.create_from_image(image)


func _plain_goal() -> Texture2D:
	var image := Image.create(16, 20, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for y in 20:
		image.set_pixel(0, y, Color.WHITE)
		image.set_pixel(15, y, Color.WHITE)
	for x in 16:
		image.set_pixel(x, 0, Color.WHITE)
	return ImageTexture.create_from_image(image)


func _plain_ball() -> Texture2D:
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for x in 8:
		for y in 8:
			if Vector2(x - 3.5, y - 3.5).length() <= 3.6:
				image.set_pixel(x, y, Color("8b5a2b") if (x + y) % 3 else Color.WHITE)
	return ImageTexture.create_from_image(image)
