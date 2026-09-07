class_name StarBadge
extends Node2D

# =============================================================
#  STAR PLAYER BADGE
#
#  A small marker that rides above every Star Player, so you can always
#  tell at a glance which unit on the pitch is special. It shows up in
#  three places, all driven from this one file:
#
#    * on the pitch          — a Node2D child of the PlayerUnit
#    * on a selection card   — StarBadge.make_marker(), a Control
#    * in the duel cut-away  — the same make_marker()
#
#  CHANGING THE ART — no code, no editor:
#    Drop a PNG at res://assets/ui/star_badge.png and it is used
#    everywhere. Add res://assets/ui/star_badge_enemy.png and the enemy's
#    Stars wear that one instead; without it both sides share the ally art
#    and are told apart by tint.
#
#    To keep the art somewhere else, add a row to Tuning.csv:
#        star_badge_art,res://assets/whatever/my_star.png,
#        star_badge_enemy_art,res://assets/whatever/their_star.png,
#
#    With no PNG anywhere, a five-pointed star is drawn in code, so this
#    works before any art exists.
# =============================================================

const ALLY_TUNING_KEY := "star_badge_art"
const ENEMY_TUNING_KEY := "star_badge_enemy_art"

const ALLY_FILE := "star_badge.png"
const ENEMY_FILE := "star_badge_enemy.png"

## Folders searched, in order, for the files above.
const SEARCH_DIRS: Array[String] = [
	"res://assets/ui/",
	"res://assets/menu/",
	"res://assets/badges/",
	"res://assets/",
]

const ALLY_TINT := Color(1.0, 0.84, 0.32)      # gold
const ENEMY_TINT := Color(1.0, 0.46, 0.42)     # red
const OUTLINE := Color(0.05, 0.05, 0.08, 0.9)

## Texture lookups are cached per side, so a hundred badges cost one disk hit.
static var _texture_cache: Dictionary = {}
## Sides that ended up borrowing the ally PNG because they had none of their
## own. Those get a colour wash so the two teams still read apart.
static var _borrowed_art: Dictionary = {}

@export var is_enemy: bool = false:
	set(value):
		is_enemy = value
		queue_redraw()

## Radius in pixels. The drawn star is roughly twice this across.
@export var badge_radius: float = 9.0:
	set(value):
		badge_radius = maxf(1.0, value)
		queue_redraw()

## 0 turns the breathing animation off entirely.
@export var pulse_amount: float = 0.08
@export var pulse_speed: float = 2.4

var _pulse_time: float = 0.0


func _ready() -> void:
	z_index = 45          # above the unit artwork, below the ball (50)
	z_as_relative = false
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_process(pulse_amount > 0.0)


func _process(delta: float) -> void:
	# Scale is animated rather than the drawing, so this costs no redraws.
	_pulse_time += delta * pulse_speed
	var s := 1.0 + sin(_pulse_time) * pulse_amount
	scale = Vector2(s, s)


func tint() -> Color:
	return ENEMY_TINT if is_enemy else ALLY_TINT


# -------------------------------------------------------------
#  DRAWING
# -------------------------------------------------------------

func _draw() -> void:
	var tex := StarBadge.texture_for(is_enemy)
	if tex != null:
		var box := Vector2(badge_radius, badge_radius) * 2.0
		# Your own art is drawn exactly as you drew it. The one exception is an
		# enemy badge that had to borrow the ally PNG — that gets a red wash,
		# or both teams would be wearing the same marker.
		var wash := Color.WHITE
		if is_enemy and StarBadge.art_is_borrowed(true):
			wash = ENEMY_TINT
		draw_texture_rect(tex, Rect2(-box * 0.5, box), false, wash)
		return
	_draw_star()


func _draw_star() -> void:
	var outer := badge_radius
	var inner := badge_radius * 0.44

	var points := PackedVector2Array()
	for i in 10:
		var r: float = outer if i % 2 == 0 else inner
		var a: float = -PI * 0.5 + float(i) * PI / 5.0
		points.append(Vector2(cos(a), sin(a)) * r)

	var outline := PackedVector2Array()
	for p in points:
		outline.append(p * 1.22)

	_fill_polygon(outline, OUTLINE)
	_fill_polygon(points, tint())


## draw_colored_polygon() only renders convex shapes reliably, and a star is
## very much not convex — so triangulate first and draw the triangles.
func _fill_polygon(points: PackedVector2Array, colour: Color) -> void:
	var indices := Geometry2D.triangulate_polygon(points)
	if indices.is_empty():
		draw_circle(Vector2.ZERO, badge_radius * 0.8, colour)
		return

	var i := 0
	while i + 2 < indices.size():
		draw_colored_polygon(PackedVector2Array([
			points[indices[i]],
			points[indices[i + 1]],
			points[indices[i + 2]],
		]), colour)
		i += 3


# -------------------------------------------------------------
#  SHARED ART LOOKUP
# -------------------------------------------------------------

## The badge texture for one side, or null when no PNG was found (in which
## case callers draw the built-in star instead).
static func texture_for(enemy_side: bool) -> Texture2D:
	var key := "enemy" if enemy_side else "ally"
	if _texture_cache.has(key):
		return _texture_cache[key] as Texture2D
	var found := _locate_texture(enemy_side)
	_texture_cache[key] = found
	return found


## True when this side has no art of its own and is wearing the other side's,
## which is the cue to tint it. Only meaningful after texture_for().
static func art_is_borrowed(enemy_side: bool) -> bool:
	return bool(_borrowed_art.get("enemy" if enemy_side else "ally", false))


## Call after dropping in new art mid-session; the next badge re-reads disk.
static func forget_art() -> void:
	_texture_cache.clear()
	_borrowed_art.clear()


static func _locate_texture(enemy_side: bool) -> Texture2D:
	var key := "enemy" if enemy_side else "ally"
	_borrowed_art[key] = false

	# 1. An explicit path in Tuning.csv wins.
	var own: Array[String] = []
	var db := CardDatabase.get_db()
	if db != null:
		var tuned := db.tune_text(ENEMY_TUNING_KEY if enemy_side else ALLY_TUNING_KEY)
		if tuned != "":
			own.append(tuned if tuned.begins_with("res://") else "res://" + tuned)

	# 2. Then the conventional file name in each known folder.
	var wanted := ENEMY_FILE if enemy_side else ALLY_FILE
	for folder in SEARCH_DIRS:
		own.append(folder + wanted)

	var found := _first_texture(own)
	if found != null:
		return found

	# 3. The enemy falls back to the ally art rather than to nothing — and is
	#    flagged, so _draw() knows to wash it red.
	if enemy_side:
		var shared: Array[String] = []
		for folder in SEARCH_DIRS:
			shared.append(folder + ALLY_FILE)
		found = _first_texture(shared)
		if found != null:
			_borrowed_art[key] = true
			return found

	return null


static func _first_texture(paths: Array[String]) -> Texture2D:
	for path in paths:
		if ResourceLoader.exists(path):
			var res := load(path)
			if res is Texture2D:
				return res as Texture2D
	return null


# -------------------------------------------------------------
#  UI FLAVOUR — the same badge, as a Control for cards and cut-aways
# -------------------------------------------------------------

## A Control you can drop on any card or panel. Uses the PNG when there is
## one and a plain gold star glyph when there is not, so it never blanks out.
static func make_marker(enemy_side: bool = false, pixels: float = 26.0) -> Control:
	var colour := ENEMY_TINT if enemy_side else ALLY_TINT
	var tex := texture_for(enemy_side)

	if tex != null:
		var art := TextureRect.new()
		art.texture = tex
		if enemy_side and art_is_borrowed(true):
			art.modulate = colour
		art.custom_minimum_size = Vector2(pixels, pixels)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return art

	var glyph := Label.new()
	glyph.text = "★"
	glyph.custom_minimum_size = Vector2(pixels, pixels)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.add_theme_font_size_override("font_size", int(pixels * 0.86))
	glyph.add_theme_color_override("font_color", colour)
	glyph.add_theme_color_override("font_outline_color", OUTLINE)
	glyph.add_theme_constant_override("outline_size", 5)
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return glyph
