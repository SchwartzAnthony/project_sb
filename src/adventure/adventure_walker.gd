class_name AdventureWalker
extends Node2D

# =============================================================
#  ONE PLAYER ON THE RUN
#
#  The scrolling part of Adventure needs a much simpler unit than the pitch
#  does. A PlayerUnit knows about marking, zones, leashes and home positions,
#  none of which mean anything here — the party runs right, peels off for a
#  pickup, and forms up when something blocks the way.
#
#  So this is its own small node. What it shares with the pitch is the LOOK:
#  the same artwork, and a drawn placeholder when there is none, so the two
#  halves of the game do not look like different projects.
#
#  ============ IT DRAWS ITSELF UNTIL YOU GIVE IT ART ============
#
#  With no artwork it is a coloured disc with its power in the middle and a
#  stamina bar underneath — tinted by tier, so you can read a formation at a
#  glance. Give the card artwork in your unit CSV and the disc is replaced.
#  Nothing else changes. Same rule as the keeper on the pitch.
# =============================================================

const RADIUS := 17.0
const BAR_WIDTH := 38.0
const BAR_HEIGHT := 5.0

## Who this is. Never written to — see adventure_run.gd for why.
var card: PlayerData = null

## Where it is trying to stand. It eases towards this every frame.
var target: Vector2 = Vector2.ZERO

## 0 to 1. Only for drawing; the real number lives on the run.
var stamina_fraction: float = 1.0
var knocked_out: bool = false

## True while it has broken formation to fetch something off the ground.
var fetching: bool = false

var _speed: float = 260.0
var _bob: float = 0.0
var _art: TextureRect = null


func setup(player: PlayerData, walk_speed: float = 260.0) -> void:
	card = player
	_speed = maxf(20.0, walk_speed)
	_bob = randf() * TAU        # so they do not all bounce in step

	if card != null and card.artwork != null:
		_art = TextureRect.new()
		_art.texture = card.artwork
		_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_art.custom_minimum_size = Vector2(RADIUS * 2.4, RADIUS * 2.4)
		_art.size = _art.custom_minimum_size
		_art.position = -_art.size * 0.5
		_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_art)


func _process(delta: float) -> void:
	# Ease towards the target rather than snapping, so peeling off for a
	# pickup and falling back into line both read as running.
	var to_target := target - position
	var step := _speed * delta
	if to_target.length() <= step:
		position = target
	else:
		position += to_target.normalized() * step

	# A gentle bob while moving. Standing still, it settles.
	_bob += delta * (9.0 if to_target.length() > 2.0 else 2.0)
	if _art != null:
		_art.position.y = -_art.size.y * 0.5 + sin(_bob) * 2.0

	queue_redraw()


## Has it arrived where it was sent?
func is_settled() -> bool:
	return position.distance_to(target) < 3.0


func _draw() -> void:
	if card == null:
		return

	var tint := MenuSupport.colour_for_tier(card.get_tier_clean())
	if knocked_out:
		tint = tint.darkened(0.6)

	# --- The body, only when there is no artwork ---
	if _art == null:
		var lift := sin(_bob) * 2.0
		var middle := Vector2(0.0, lift)
		draw_circle(middle, RADIUS, tint.darkened(0.25))
		draw_arc(middle, RADIUS, 0.0, TAU, 24,
			MenuSupport.COLOUR_ACCENT if not knocked_out else MenuSupport.COLOUR_TEXT_DIM,
			2.0, true)

		var font := ThemeDB.fallback_font
		var label := str(card.get_attack_power())
		var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16).x
		draw_string(font, middle + Vector2(-width * 0.5, 6.0), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, MenuSupport.COLOUR_TEXT)

	# --- The stamina bar, always ---
	var bar := Rect2(Vector2(-BAR_WIDTH * 0.5, RADIUS + 6.0),
		Vector2(BAR_WIDTH, BAR_HEIGHT))
	draw_rect(bar, Color(0.10, 0.11, 0.14), true)
	if not knocked_out and stamina_fraction > 0.0:
		var filled := bar
		filled.size.x = BAR_WIDTH * clampf(stamina_fraction, 0.0, 1.0)
		# Green when healthy, amber, then red. Read at a glance, no numbers.
		var colour := Color(0.45, 0.78, 0.45)
		if stamina_fraction < 0.34:
			colour = Color(0.85, 0.35, 0.32)
		elif stamina_fraction < 0.67:
			colour = Color(0.88, 0.68, 0.32)
		draw_rect(filled, colour, true)

	if knocked_out:
		# A plain cross, so a downed player is obvious without reading a bar.
		var span := RADIUS * 0.6
		var dead := MenuSupport.COLOUR_TEXT_DIM
		draw_line(Vector2(-span, -span), Vector2(span, span), dead, 2.0)
		draw_line(Vector2(-span, span), Vector2(span, -span), dead, 2.0)
