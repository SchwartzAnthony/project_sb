class_name GoalCelebration
extends CanvasLayer

# =============================================================
#  THE CONFETTI AND THE WINDOW
#
#  The two things a goal celebration needs that are not on the pitch. The
#  sliding and the swarming happen to real players and live in main_scene;
#  this is the paper in the air and the panel in the middle.
#
#  ============ THE CONFETTI ============
#
#  Drawn, not spawned, and drawn in ONE CALL. Two hundred and sixty nodes
#  would be that many nodes to build, steer and free at the exact moment the
#  game is already doing the most work it ever does — and two hundred and
#  sixty draw_rect() calls turned out to be just as bad. See _draw_paper(),
#  which has the measurement: 22 frames a second became 2.
#
#  They fall, drift sideways, spin, and are gone when the celebration ends.
#  Nothing about them is art you have to draw — the colours come from the two
#  teams, so your confetti is already in your club's colours.
#
#  ============ THE WINDOW ============
#
#  Not drawn here — it is `AnimWindow`, shared with the out-of-bounds
#  sequence. It shows a caption and, in the middle of it, ONE OF TWO THINGS:
#
#      an ANIMATION   a row of Animations.csv, played on the scorer's own
#                     spritesheet. `win` is the one you already have drawn
#      an IMAGE       whatever you name in the Art column, shown whole
#
#  Art wins if you fill in both, because an image is the more deliberate of
#  the two — you went and drew it.
#
#  If a row asks for an animation the scorer has no art for, the window still
#  opens with the caption and an empty stage. A celebration is not allowed to
#  be the thing that stops a match.
#
#  ============ SKIPPING ============
#
#  Click or space, if `celebration_skippable` is true. The twentieth goal of
#  an evening is not the first one.
# =============================================================

signal skipped

const FALLBACK_COLOURS: Array[Color] = [
	Color(0.98, 0.76, 0.33),
	Color(0.95, 0.35, 0.36),
	Color(0.40, 0.72, 0.95),
	Color(0.55, 0.88, 0.52),
	Color(0.95, 0.95, 0.97),
]

var db: CardDatabase

var _paper: Control
var _bits: Array[Dictionary] = []
var _colours: Array[Color] = FALLBACK_COLOURS
var _speed := 220.0
var _thickness := 6.0
var _raining := false

var _window: AnimWindow
var _skippable := true
var _cut := false


## Put it up over `on`. Nothing is visible until confetti() or show_panel().
static func open(on: Node, database: CardDatabase,
		tints: Array[Color] = []) -> GoalCelebration:
	var made := GoalCelebration.new()
	made.name = "GoalCelebration"
	made.db = database
	if not tints.is_empty():
		made._colours = tints
	on.add_child(made)
	return made


func _ready() -> void:
	# Over the pitch and over the side banner (120), under a dialog (180).
	layer = 150
	process_mode = Node.PROCESS_MODE_ALWAYS
	if db != null:
		_speed = maxf(20.0, db.tune_float("celebration_confetti_speed", 220.0))
		_thickness = maxf(1.0, db.tune_float("celebration_confetti_size", 6.0))
		_skippable = db.tune_bool("celebration_skippable", true)
	_build()


func _build() -> void:
	_paper = Control.new()
	_paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_paper.draw.connect(_draw_paper)
	add_child(_paper)

	# THE WINDOW IS NOT DRAWN HERE. It is AnimWindow, which the out-of-bounds
	# sequence also uses — two copies of a window is two windows that drift
	# apart, one gets a new corner style and the other does not, and a year
	# later the game has two looks for the same idea.
	_window = AnimWindow.open(self, db, layer + 1)


# =============================================================
#  THE CONFETTI
# =============================================================

## Start it. It falls until stop() or until the layer is freed.
func confetti() -> void:
	if _raining:
		return
	_raining = true
	var how_many := 140
	if db != null:
		how_many = int(clampf(db.tune_float("celebration_confetti_pieces", 260.0), 0.0, 2000.0))
	var screen := _screen_size()
	_bits.clear()
	for i in how_many:
		_bits.append(_new_bit(screen, true))


func stop() -> void:
	_raining = false
	_bits.clear()
	if _paper != null:
		_paper.queue_redraw()


## One piece of paper. `scattered` starts it anywhere above the screen rather
## than all on one line, which is what stops the first second looking like a
## curtain coming down.
func _new_bit(screen: Vector2, scattered: bool) -> Dictionary:
	var high := -screen.y * randf() if scattered else -20.0 - randf() * 120.0
	return {
		"pos": Vector2(randf() * screen.x, high),
		"fall": _speed * (0.55 + randf() * 0.9),
		"drift": (randf() - 0.5) * _speed * 0.5,
		"spin": (randf() - 0.5) * 9.0,
		"angle": randf() * TAU,
		"lean": randf() * TAU,          # which way this piece lies
		"long": 12.0 + randf() * 12.0,  # its length when flat-on
		"tint": _colours[randi() % _colours.size()],
	}


func _process(delta: float) -> void:
	if not _raining or _paper == null:
		return
	var screen := _screen_size()
	for bit in _bits:
		var pos: Vector2 = bit["pos"]
		pos.y += float(bit["fall"]) * delta
		# A SIDEWAYS SWAY, not a straight sideways push: paper does not travel
		# in one direction, it flutters. The angle is already turning, so
		# reusing it for the drift costs nothing and looks right.
		pos.x += float(bit["drift"]) * delta * sin(float(bit["angle"]))
		bit["angle"] = float(bit["angle"]) + float(bit["spin"]) * delta
		bit["lean"] = float(bit["lean"]) + float(bit["spin"]) * delta * 0.35
		if pos.y > screen.y + 30.0:
			# Back to the top. Recycling is what keeps it raining for as long
			# as the celebration runs without ever making another allocation.
			pos = Vector2(randf() * screen.x, -20.0 - randf() * 80.0)
		bit["pos"] = pos
	_paper.queue_redraw()


# ============ ONE DRAW CALL, NOT TWO HUNDRED AND SIXTY ============
#
# THIS IS THE MOST IMPORTANT TWENTY LINES IN THE FILE and it is worth knowing
# why, because it is the kind of thing that is invisible until you measure it.
#
# The first version drew each piece with its own draw_rect(). That is one
# draw call per piece, and I measured what it cost with the celebration
# running at 1920x1080:
#
#     22 frames a second before the confetti,   2 frames a second during it
#
# At the exact moment the game is supposed to feel best. Ten times slower, in
# the one second of a match that is the reason anybody is playing it.
#
# draw_multiline_colors() takes EVERY piece in one call: a pair of points and
# a colour each, one array, one command. Same picture, 260 times fewer calls.
#
# The picture is a short thick segment rather than a rectangle, which is what
# a rectangle at this size looks like anyway. It turns edge-on and back by
# getting shorter (the cosine of its own spin) and it lies at its own angle,
# so a screenful of them flutters instead of falling like a grid.
func _draw_paper() -> void:
	if _bits.is_empty():
		return
	var ends := PackedVector2Array()
	var tints := PackedColorArray()
	ends.resize(_bits.size() * 2)
	tints.resize(_bits.size())
	var i := 0
	for bit in _bits:
		var pos: Vector2 = bit["pos"]
		# EDGE-ON IS SHORT, FLAT-ON IS LONG. Never quite zero, because a piece
		# that vanishes for a frame reads as a flicker rather than as paper.
		var half: float = float(bit["long"]) * 0.5 \
			* maxf(0.14, absf(cos(float(bit["angle"]))))
		var lean: float = bit["lean"]
		var arm := Vector2(cos(lean), sin(lean)) * half
		ends[i * 2] = pos - arm
		ends[i * 2 + 1] = pos + arm
		tints[i] = bit["tint"]
		i += 1
	_paper.draw_multiline_colors(ends, tints, _thickness)


func _screen_size() -> Vector2:
	var view := get_viewport()
	return Vector2(view.get_visible_rect().size) if view != null else Vector2(1920, 1080)


# =============================================================
#  THE WINDOW
# =============================================================

## Show, or swap what is inside, the celebration window.
func show_panel(caption: String, art: String, animation: String,
		card: PlayerData) -> void:
	if _window != null and is_instance_valid(_window):
		_window.show_panel(caption, art, animation, card, ["win", "idle"])


func hide_panel() -> void:
	if _window != null and is_instance_valid(_window):
		_window.hide_panel()


# =============================================================
#  CUTTING IT SHORT
# =============================================================

func _unhandled_input(event: InputEvent) -> void:
	if not _skippable or _cut:
		return
	var click := event as InputEventMouseButton
	var key := event as InputEventKey
	var pressed := (click != null and click.pressed) \
		or (key != null and key.pressed and not key.echo \
			and key.keycode in [KEY_SPACE, KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER])
	if not pressed:
		return
	get_viewport().set_input_as_handled()
	_cut = true
	print("[celebration] skipped.")
	skipped.emit()


func was_cut() -> bool:
	return _cut


## Everything down at once: the paper stops, the window closes, the layer
## goes. Called at the end of the celebration however it ended.
func close() -> void:
	stop()
	if _window != null and is_instance_valid(_window):
		_window.close()
	queue_free()
