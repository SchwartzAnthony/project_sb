@tool
class_name PlayerUnit
extends Area2D

# =============================================================
#  A single card living on the pitch
# =============================================================

@onready var artwork: Sprite2D = $Artwork
@onready var name_label: Label = $NameLabel
@onready var stats_label: Label = $StatsLabel

# --- Spritesheet layout (your sheet is 12 columns x 39 rows) ---
const SHEET_HFRAMES := 12
const SHEET_VFRAMES := 39
const IDLE_FRAME := 0

# --- Movement ------------------------------------------------
# Steering is per-frame in _physics_process, NOT tween-driven. Tweens and
# ball-chasing fight over `position`; a single integrator does not.
var home_position: Vector2
var roam_radius: float = 40.0
var is_roaming: bool = false
var movement_frozen: bool = false     # HOLD UP! substitution pauses everyone

@export var walk_speed: float = 30.0        # px/s ambling around home
@export var chase_speed: float = 66.0       # px/s closing on the ball
@export var dribble_speed: float = 44.0     # px/s carrying it upfield
@export var interest_radius: float = 190.0  # only react to a ball this close

# --- Crowding ------------------------------------------------
# Units used to walk straight through each other and settle into the same
# few pixels. These three turn that into a shove: everybody keeps a little
# room, EXCEPT near the ball, where fighting over it is the point.
## How close another unit has to be before this one starts giving way.
@export var separation_radius: float = 64.0
## Closer than this and two players are drawn on top of each other. The push
## apart at this range is at FULL strength however near the ball they are —
## crowding a tackle is football, standing inside somebody is not.
@export var personal_space: float = 34.0
## How much of the separation push survives right on top of the ball. 0.2 was
## too little and turned every loose ball into a pile.
@export var contest_crowding: float = 0.55
## How close to a target counts as arrived. Inside this the pull fades out,
## which is what stops a unit stepping back and forth across its own slot.
@export var arrive_radius: float = 14.0
## Below this much total force a unit simply stops. Without it, a player in
## balance shuffles on the spot for ever.
@export var still_threshold: float = 0.12
## How far past a unit the ball has to be before they turn round to look at
## it. Stops a flicker when the two are level.
@export var face_deadzone: float = 18.0
## How hard the shove is, relative to the pull of wherever they are heading.
@export var separation_strength: float = 0.9
## Inside this distance of the ball the shove fades out, so a loose ball is
## genuinely contested instead of politely orbited.
@export var contest_radius: float = 70.0
## A sideways bias on the run to the ball, its direction fixed per unit, so a
## group converging on it takes curved routes instead of forming one queue.
@export var swerve_strength: float = 0.35

## Assigned at spawn by main_scene.
var ball: Ball = null
var play_bounds: Rect2 = Rect2()
var attack_dir: float = 1.0                 # +1 attacks right, -1 attacks left

## Counts down after this unit is tackled. While it is above zero the unit
## stops chasing the ball and cannot win it back, which is what stops two
## opponents standing on the same spot trading possession forever.
var steal_cooldown: float = 0.0

var _roam_target: Vector2
var _roam_wait: float = 0.0
## +1 or -1, fixed for this unit's lifetime: which way it bends around traffic.
var _swerve_sign: float = 1.0

@export var data: PlayerData:
	set(new_data):
		data = new_data
		if is_node_ready():
			update_display()

# --- Match state ---------------------------------------------
var is_enemy: bool = false

## Set explicitly at spawn. Flipping it puts the Star badge up (or takes it
## down), so nothing else has to remember to keep the marker in sync.
var is_star_player: bool = false:
	set(value):
		is_star_player = value
		_refresh_star_badge()

## ROUND AN: true for whoever stands in the Stars' place - a Star, or the
## plain player who takes it in a side with no Stars (the first match). The
## STAR PLAYER SWITCH swaps this unit.
var stands_in_star_slot: bool = false
var is_playmaker: bool = false     # picked during the current round
## ROUND AN (Anthony, 8 Oct): true only while a PLAY MAKER is running, from
## the "PLAY MAKER!" call until the round's shot is over. Only then is anyone
## greyed - the ones not in it. Outside a Play Maker everybody is in colour.
## One switch for the whole pitch, set by main_scene.set_play_maker_live().
static var play_maker_live: bool = false
var is_exhausted: bool = false     # already used this cycle

# =============================================================
#  DISCIPLINE — see src/core/foul_book.gd
#
#  `yellow_cards` is how many bookings this man has in THIS MATCH. Two of
#  them is a red, if Tuning.csv says so.
#
#  `is_sent_off` is for the rest of the match, and NOTHING takes it back —
#  not the end of a cycle, not the Star rotation, not a new round. That is
#  the whole point of a red card, and the guard in reset_for_new_cycle()
#  below is the one line that makes it stick.
# =============================================================
var yellow_cards: int = 0
var is_sent_off: bool = false

## Which brew this unit drank at the Pub before the match, or "" for none.
## The Pub fills this in; the match reports it with every goal and duel, so
## Stats.csv rows like `goals_with_brew_{brew}` work with no code changes.
var active_brew: String = ""

## The little marker riding above a Star Player. Created on demand.
var _star_badge: StarBadge = null


func _ready() -> void:
	_plate = NamePlate.make()
	add_child(_plate)
	# Fixed for life, so this unit always bends the same way round traffic
	# rather than dithering left and right on the spot.
	_swerve_sign = 1.0 if randf() < 0.5 else -1.0
	update_display()
	_refresh_star_badge()


# =============================================================
#  STAR BADGE
#
#  Purely cosmetic, and deliberately a SIBLING of Artwork rather than a
#  child: set_highlight() dims Artwork.modulate down to 0.25 for a spent
#  unit, and the badge must stay readable through that.
#
#  Size and height come from Tuning.csv (star_badge_radius,
#  star_badge_offset_y); the art itself comes from a PNG — see star_badge.gd.
# =============================================================

func _refresh_star_badge() -> void:
	if Engine.is_editor_hint() or not is_node_ready():
		return

	if not is_star_player:
		if _star_badge != null:
			_star_badge.visible = false
		return

	if _star_badge == null:
		_star_badge = StarBadge.new()
		_star_badge.name = "StarBadge"
		add_child(_star_badge)

	var radius := 9.0
	var offset_y := -34.0
	var pulse := 0.08
	var db := CardDatabase.get_db()
	if db != null:
		radius = db.tune_float("star_badge_radius", radius)
		offset_y = db.tune_float("star_badge_offset_y", offset_y)
		pulse = db.tune_float("star_badge_pulse", pulse)

	_star_badge.is_enemy = is_enemy
	_star_badge.badge_radius = radius
	_star_badge.pulse_amount = pulse
	_star_badge.set_process(pulse > 0.0)
	_star_badge.position = Vector2(0.0, offset_y)
	_star_badge.visible = true


# =============================================================
#  DISPLAY
# =============================================================

func update_display() -> void:
	if data == null:
		return

	# ============ THE LABELS ARE DRAWN, NOT PLACED ============
	#
	# NameLabel and StatsLabel are two Label nodes sitting at fixed offsets
	# in player_unit.tscn — which put the name ACROSS THE PLAYER'S FACE and
	# the stats wherever the scene file happened to say. Adventure labelled
	# the same card completely differently, so one card read as two things
	# depending on which mode you were in.
	#
	# Both modes now draw the same plate out of name_plate.gd: the name over
	# the head, Tier at the feet on the left, Power at the feet on the right.
	# The two Label nodes are kept and kept up to date — anything else that
	# reads them still works — but they are hidden, because the plate is
	# drawn in _draw() instead. See name_plate.gd.
	if name_label:
		name_label.text = data.player_name
		name_label.visible = false
	if stats_label:
		stats_label.text = "T%s  %d/%d" % [
			data.get_tier_clean(),
			data.get_attack_power(),
			data.get_defense_power(),
		]
		stats_label.visible = false

	_apply_artwork()
	_measure()
	queue_redraw()


## ============ WHERE THE ARTWORK ACTUALLY IS ============
##
## The opaque rectangle inside one frame of the spritesheet, as a fraction of
## it. A frame is mostly transparent padding, and placing a label from the
## frame means placing it from the padding. Measured once per card.
var _box := Rect2(0, 0, 1, 1)
## The name over the head and the Tier/Power window at the feet. A node of
## its own, because Godot only keeps TEXT crisp at a smaller window size when
## it is a real Label — see name_plate.gd.
var _plate: NamePlate

## ============ THE TAG COMES OFF FOR A CELEBRATION ============
##
## Nine players in a huddle is nine name plates inside about a hundred
## pixels, and what that actually looks like is a black rectangle with bits
## of text sticking out of it. So for the length of a goal celebration
## everybody in the huddle loses their tag and THE SCORER KEEPS HIS — which
## is not only tidier, it is the point of the picture.
##
## Set back to false at the end of the celebration, however it ended.
var plate_hidden := false:
	set(value):
		plate_hidden = value
		if _plate != null and is_instance_valid(_plate):
			_plate.visible = not value
		queue_redraw()


func _measure() -> void:
	if data == null:
		return
	# ON A PITCH SHEET the plate is placed from the pitch figure itself,
	# standing facing the camera, not from the card's old sheet.
	if pitch_sheet and artwork != null and artwork.texture != null:
		var cell := artwork.texture.get_size() / Vector2(artwork.hframes, artwork.vframes)
		var idle := PitchSprite.anim("idle")
		var at := AtlasTexture.new()
		at.atlas = artwork.texture
		at.region = Rect2(Vector2(0.0, float(int(idle.get("row", 0)) + 2) * cell.y), cell)
		_box = NamePlate.box_of(at)
		return
	# The SAME frame the Adventure walker and the card faces use, so all
	# three measure the same picture and agree about where the body is.
	var face := MenuSupport.portrait_for(data, CardDatabase.get_db())
	if face != null:
		_box = NamePlate.box_of(face)


func _draw() -> void:
	if data == null or artwork == null or artwork.texture == null:
		return
	var frame := artwork.texture.get_size() / Vector2(
		maxf(1.0, float(artwork.hframes)), maxf(1.0, float(artwork.vframes)))
	frame *= artwork.scale
	# A Sprite2D is drawn centred on its own position.
	var at := artwork.position - frame * 0.5
	# NO STAMINA BAR IN A LEAGUE MATCH. Only the keeper has stamina here, so
	# there is nothing to draw one from — and twenty-two bars all reading
	# full would say nothing at all. -1 means "this mode has no bar".
	# NOT CREATED HERE. Adding a child from inside _draw() is a tree change
	# in the middle of drawing the tree; the plate is built in _ready().
	if _plate != null and is_instance_valid(_plate):
		if plate_hidden:
			_plate.visible = false
		else:
			_plate.place(NamePlate.edges(_box, at, frame), data, -1.0, is_exhausted)


func _apply_artwork() -> void:
	if artwork == null or data == null or data.active_artwork() == null:
		return
	# Always drive the sheet the same way, everywhere. The old
	# update_unit_data() built an AtlasTexture instead, which fought with
	# these hframes/vframes and shredded the sprite after a HOLD UP! swap.
	# ROUND AN: an isometric pitch sheet (data/PitchSprites.csv) if this card
	# has one. Picked once per player by name, so a look never changes.
	var pitch := PitchSprite.sheet_for(data, hash(data.player_name))
	pitch_sheet = pitch != null
	if pitch_sheet:
		var db := CardDatabase.get_db()
		var cell := 72.0
		var scale_by := 1.0
		var lift := 0.0
		if db != null:
			cell = maxf(1.0, db.tune_float("pitch_sheet_cell", cell))
			scale_by = db.tune_float("pitch_sprite_scale", scale_by)
			lift = db.tune_float("pitch_sprite_lift", lift)
		artwork.texture = pitch
		artwork.hframes = maxi(1, int(pitch.get_width() / cell))
		artwork.vframes = maxi(1, int(pitch.get_height() / cell))
		artwork.flip_h = false
		artwork.scale = Vector2.ONE * scale_by
		artwork.position = Vector2(0.0, -lift * scale_by)
		_anim_name = ""
		_last_spot = global_position
		_show_anim("idle")
		_tint_pitch_figure(is_playmaker)
		return
	artwork.scale = Vector2.ONE
	artwork.position = Vector2.ZERO
	artwork.material = null
	artwork.texture = data.active_artwork()
	artwork.hframes = SHEET_HFRAMES
	artwork.vframes = SHEET_VFRAMES
	artwork.frame = IDLE_FRAME
	# A starting direction only. _face_the_action() takes over the moment they
	# move, and turns them toward the ball.
	artwork.flip_h = is_enemy


## Swap this unit to a different card (used by the HOLD UP! star rotation).
func update_unit_data(new_data: PlayerData) -> void:
	data = new_data          # setter calls update_display() once ready
	if is_node_ready():
		update_display()


func set_highlight(is_highlighted: bool) -> void:
	if artwork == null:
		return
	if pitch_sheet:
		_tint_pitch_figure(is_highlighted or is_playmaker)
		return
	# Stay bright while locked in as this round's playmaker.
	if is_highlighted or is_playmaker:
		artwork.modulate = Color(1.2, 1.2, 1.2, 1.0)
	elif not play_maker_live:
		artwork.modulate = Color.WHITE   # no Play Maker on: everyone in colour
	elif is_exhausted:
		artwork.modulate = Color(0.25, 0.25, 0.3, 1.0)  # spent this cycle
	else:
		artwork.modulate = Color(0.4, 0.4, 0.4, 1.0)


const PITCH_COLOUR_SHADER := preload("res://assets/shaders/pitch_colour.gdshader")


## ROUND AN (Anthony: grey shows who is not in the Play Maker session, so
## the player can follow the play). An isometric figure in the session is in
## full colour; everybody else is drained of colour, and a spent one is dark
## as well. All three from Tuning.csv.
## 8 Oct: ONLY DURING A PLAY MAKER. When none is running (play_maker_live
## false) every figure is in its own colour, spent or not.
func _tint_pitch_figure(in_play: bool) -> void:
	var mat := artwork.material as ShaderMaterial
	if mat == null:
		mat = ShaderMaterial.new()
		mat.shader = PITCH_COLOUR_SHADER
		artwork.material = mat
	var db := CardDatabase.get_db()
	var rest := db.tune_float("pitch_sprite_rest_brightness", 1.0) if db != null else 1.0
	var grey := db.tune_float("pitch_sprite_rest_saturation", 0.0) if db != null else 0.0
	if in_play:
		mat.set_shader_parameter("saturation", 1.0)
		artwork.modulate = Color(1.15, 1.15, 1.15, 1.0)
	elif not play_maker_live:
		mat.set_shader_parameter("saturation", 1.0)
		artwork.modulate = Color.WHITE
	elif is_exhausted:
		mat.set_shader_parameter("saturation", grey)
		artwork.modulate = Color(0.45, 0.45, 0.45, 1.0)
	else:
		mat.set_shader_parameter("saturation", grey)
		artwork.modulate = Color(rest, rest, rest, 1.0)


func reset_for_new_cycle() -> void:
	# A SENT-OFF MAN DOES NOT COME BACK. Everything else about a new cycle is
	# a fresh start; this is the one thing that is not.
	if is_sent_off:
		is_exhausted = true
		is_playmaker = false
		return
	is_exhausted = false
	is_playmaker = false
	set_highlight(false)


## Off. For the rest of the match.
##
## He is marked exhausted as well as sent off, because every list in the game
## that offers cards already skips the exhausted — so a red card is obeyed by
## code that was written before red cards existed.
func send_off() -> void:
	is_sent_off = true
	is_exhausted = true
	is_playmaker = false
	visible = false
	set_physics_process(false)


func clear_round_flags() -> void:
	is_playmaker = false
	set_highlight(false)


# =============================================================
#  MOVEMENT
#
#  WHO DECIDES WHAT: main_scene picks the ROLE for every unit once per
#  physics frame (see _assign_roles there) and writes `role`, `role_target`
#  and `role_speed` onto each one. This file only does the driving — steer
#  toward that target, keep out of other people's space, stay in my quarter.
#
#  Deciding centrally is what makes "two of you press, the rest hold your
#  man" possible at all: a unit cannot see how many team-mates have already
#  gone to the ball, but the scene can.
#
#  ROLES
#    DRIBBLE  I have it — run at their goal
#    BALL     it is loose or in my quarter — go and win it
#    RECEIVE  the pass is aimed at me — go and meet it
#    PRESS    they have it and I am close enough — charge the carrier
#    MARK     they have it elsewhere — stay goal-side of my man
#    OPEN     we have it — get off my marker and show for the pass
#    HOLD     nothing doing — drift around my slot
#    SURGE    the break after the last duel — abandon the quarter and run
#             at their goal with everyone else
#    RECOVER  the other side of a break — drop back with your man instead of
#             standing on your post watching him run past you
# =============================================================

## ROUND AC: the "don't stand still" clock - see main_scene _keep_moving().
var linger_anchor := Vector2.INF
var linger_time := 0.0
var fresh_spot := Vector2.INF
var fresh_left := 0.0

enum Role { HOLD, MARK, OPEN, PRESS, BALL, RECEIVE, DRIBBLE, SURGE, RECOVER }

## Set every frame by main_scene. Left at HOLD when nothing is coordinating
## this unit, in which case it simply ambles around its slot as before.
var role: int = Role.HOLD
var role_target: Vector2 = Vector2.ZERO
var role_speed: float = 0.0
var has_role_target: bool = false

## The opponent this unit shadows. Assigned once, after both teams spawn.
var mark_target: PlayerUnit = null
## WHICH SHOULDER this unit is currently marking off, -1 or 1. Remembered
## rather than worked out fresh each frame: the side is decided by where the
## ball is, and a ball drifting across the marked man's exact height would
## otherwise flip it every frame and throw the marker back and forth. It only
## changes when the ball is CLEARLY on the other side — see _mark_point().
var mark_side: float = 0.0

## HAS THIS PLAYER GOT HOME YET during the current restart? Set once they
## arrive and cleared when the next restart begins. Without it the "am I
## home" test is asked fresh every frame and a player bounces on and off the
## edge of their own slack circle — see _assign_roles() in main_scene.
var restart_settled: bool = false

## This unit's Tier quarter, and the wider band it may chase into.
var tier_zone: Rect2 = Rect2()
var tier_soft_zone: Rect2 = Rect2()
## How hard it is pulled back to its quarter once outside it.
@export var zone_pull: float = 1.15
## How far from its slot a marking or showing unit may stray.
@export var leash: float = 210.0
## Spring back toward the slot when stretched past half the leash.
@export var slot_pull: float = 0.55

func set_home(pos: Vector2) -> void:
	position = pos
	home_position = pos
	_pick_roam_target()
	start_roaming()


func start_roaming() -> void:
	if Engine.is_editor_hint():
		return
	is_roaming = true


func stop_roaming() -> void:
	is_roaming = false


func has_ball() -> bool:
	return ball != null and is_instance_valid(ball) and ball.is_carried_by(self)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or movement_frozen or not is_roaming:
		return

	steal_cooldown = maxf(0.0, steal_cooldown - delta)

	var target: Vector2
	var speed: float

	if has_role_target:
		target = role_target
		speed = role_speed
	elif has_ball():
		# Nothing is coordinating us (main_scene not running, or a unit tested
		# on its own). Fall back to the old self-directed behaviour.
		target = _dribble_target()
		speed = dribble_speed
		role = Role.DRIBBLE
	elif _ball_is_in_range():
		target = ball.global_position
		speed = chase_speed
		role = Role.BALL
	else:
		_roam_wait -= delta
		if _roam_wait <= 0.0 or global_position.distance_to(_roam_target) < 5.0:
			_pick_roam_target()
		target = _roam_target
		speed = walk_speed
		role = Role.HOLD

	# ============ STEERING ============
	#
	# The pull toward the target is ONE FORCE AMONG FOUR, and the sum decides
	# both the heading and how fast to go.
	#
	# ---- WHY THEY USED TO SHAKE ----
	#
	# The old version normalised the sum and then stepped at FULL SPEED along
	# it, every frame, capped only by the distance to the target. So a player
	# standing exactly on their slot, with a team-mate a little too close,
	# still moved a whole frame's worth sideways — then the separation flipped
	# sign and they moved back. That is the shaking, and it is also why two
	# players ended up welded together: both were oscillating about the same
	# point instead of settling apart.
	#
	# ---- WHAT IT DOES NOW ----
	#
	#   * the pull toward the target FADES AS THEY ARRIVE rather than staying
	#     at full strength right up to the last pixel;
	#   * the step is scaled by HOW MUCH FORCE THERE IS, so a player in
	#     balance barely moves instead of moving flat out;
	#   * and under a small threshold they simply stop, which is what "arrived"
	#     should mean.
	#
	# Standing still is not the same as being STILL: a player with nothing to
	# do is given a wandering target by the match (see _drift_point), so they
	# amble around their own patch. The only things that stop the pitch are a
	# choice, a substitution and the pause menu.
	var to_target := target - global_position
	var distance := to_target.length()

	var want := Vector2.ZERO
	if distance > arrive_radius:
		want = to_target / distance
	elif distance > 0.001:
		# Inside the arrival circle the pull shrinks to nothing at the middle.
		want = (to_target / distance) * (distance / maxf(arrive_radius, 1.0))

	# Bend the run, hard when far out and straightening as they arrive, so a
	# group converging on the ball takes a spread of curved lines rather than
	# forming one queue.
	if _is_chasing() and not is_zero_approx(swerve_strength) and distance > 0.001:
		var bend := clampf(distance / maxf(interest_radius, 1.0), 0.0, 1.0)
		want += (to_target / distance).orthogonal() * _swerve_sign * swerve_strength * bend

	want += _separation() * separation_strength

	# The break is the ONE time a unit is allowed to leave its quarter for
	# good — the side breaking AND the side chasing them back.
	if role != Role.SURGE and role != Role.RECOVER:
		want += _zone_force() * zone_pull

	# Springing back to the slot is what keeps a formation a formation — but
	# it used to start at HALF a leash, which is about a hundred pixels, and
	# a player who is tugged homeward after a hundred pixels never gets
	# anywhere. It starts at a FULL leash now, so the slot is somewhere a
	# player comes back to rather than somewhere they are tied to.
	#
	# Only the positional roles get it at all: a unit going for the ball is
	# supposed to leave its post and not be reminded of it.
	if role == Role.HOLD or role == Role.MARK or role == Role.OPEN:
		var back := home_position - global_position
		var stretched := back.length()
		if stretched > leash:
			want += (back / stretched) * slot_pull \
				* minf((stretched - leash) / maxf(leash, 1.0), 1.5)

	# ---- ARRIVED ----
	var force := want.length()
	if force < still_threshold:
		return

	# The step is the speed scaled by the force, so a player being nudged by
	# one weak separation push takes a nudge-sized step rather than a stride.
	var step := speed * delta * minf(force, 1.0)
	# Never overshoot the target itself when that is the only thing pulling.
	if distance > 0.001 and force <= 1.0:
		step = minf(step, distance)
	global_position += (want / force) * step
	_face_the_action()
	_clamp_to_bounds()


## ============ WHICH WAY THEY ARE LOOKING ============
##
## At the ball, whenever the ball is worth looking at; otherwise up the pitch
## the way this side is attacking. It used to be fixed by side, so half the
## players spent the whole match with their back to the game.
func _face_the_action() -> void:
	if artwork == null or pitch_sheet:
		return
	var look_at := global_position.x + (1.0 if is_enemy else -1.0) * 100.0
	if ball != null and is_instance_valid(ball):
		look_at = ball.global_position.x
	var gap := look_at - global_position.x
	# A dead band, or a player standing level with the ball flickers between
	# facing left and facing right every frame.
	if absf(gap) < face_deadzone:
		return
	artwork.flip_h = gap < 0.0


## ============ KEEPING A TARGET SENSIBLE — NOT CAGING IT ============
##
## This used to CLAMP every target into a band a third of the pitch wide, and
## that one line is why nobody ever reached a touchline, nobody ever got near
## a goal, and a player at the edge of their band simply stopped dead.
##
## It no longer clamps to a zone at all. It does two much smaller things:
##
##   * a target more than `leash` from the player's slot is pulled in along
##     the same line, so an idle player does not wander off the map — and the
##     leash is IGNORED ENTIRELY while chasing, because a defender who gives
##     up at the end of a rope is not playing football;
##   * the target is kept on the pitch.
##
## The zone is applied as a gentle force in _zone_force() instead, which a
## player can lean against and walk straight through.
func leash_point(point: Vector2) -> Vector2:
	var out := point
	if not _is_chasing():
		var off := point - home_position
		var stretched := off.length()
		if stretched > leash and stretched > 0.001:
			out = home_position + off / stretched * leash

		# AND KEEP AN IDLE TARGET INSIDE THE ROAM BAND. Not as a cage — a
		# chasing player never reaches this line — but because _zone_force()
		# pushes back from outside the band, and a player sent to stand
		# somewhere the zone is pushing them out of walks into the push and
		# back out of it, forever. That argument is what a shake IS.
		if tier_soft_zone.size.x > 1.0:
			out.x = clampf(out.x, tier_soft_zone.position.x, tier_soft_zone.end.x)

	if play_bounds.size.x > 1.0:
		out.x = clampf(out.x, play_bounds.position.x + 16.0, play_bounds.end.x - 16.0)
	if play_bounds.size.y > 1.0:
		out.y = clampf(out.y, play_bounds.position.y + 20.0, play_bounds.end.y - 20.0)
	return out


func set_role(new_role: int, target: Vector2, speed: float) -> void:
	role = new_role
	role_target = target
	role_speed = speed
	has_role_target = true


## Going for the ball, in any sense. Nothing pulls a chasing player back.
func _is_chasing() -> bool:
	return role == Role.BALL or role == Role.PRESS or role == Role.RECEIVE \
		or role == Role.DRIBBLE or role == Role.SURGE


## A gentle push back toward home. ZERO anywhere inside the wide roam band,
## and zero at all times while chasing the ball.
##
## The band is sixty per cent of the pitch, so a Tier II has most of the grass
## to move about in before anything tugs at it, and even then the tug is a
## suggestion — it is summed with everything else pulling on the player and
## loses to a ball worth going for.
func _zone_force() -> Vector2:
	if _is_chasing():
		return Vector2.ZERO
	var band := tier_soft_zone if tier_soft_zone.size.x > 1.0 else tier_zone
	if band.size.x <= 1.0:
		return Vector2.ZERO
	if global_position.x >= band.position.x and global_position.x <= band.end.x:
		return Vector2.ZERO

	var edge: float = band.position.x
	if global_position.x > band.end.x:
		edge = band.end.x
	var over := absf(global_position.x - edge) / maxf(band.size.x, 1.0)
	return Vector2(signf(edge - global_position.x) * minf(over * 2.0, 1.0), 0.0)


## A push away from every other unit standing too close, strongest when they
## are almost touching and nothing at all at separation_radius.
func _separation() -> Vector2:
	var parent := get_parent()
	if parent == null or separation_radius <= 0.0:
		return Vector2.ZERO

	# Crowding round the ball is wanted, so the push fades as they close on it.
	# Without this the shove cancels the chase and nobody ever wins a tackle.
	var ease_off := 1.0
	if ball != null and is_instance_valid(ball) and contest_radius > 0.0:
		ease_off = clampf(
			global_position.distance_to(ball.global_position) / contest_radius,
			contest_crowding, 1.0)

	var push := Vector2.ZERO
	# ============ PERSONAL SPACE IS NOT NEGOTIABLE ============
	#
	# The ordinary push fades near the ball so a tackle can actually happen.
	# This one does not: inside `personal_space` two players are drawn on top
	# of each other, which is not a tackle, it is a bug you can see. It is
	# collected separately and added at full strength afterwards.
	var shove := Vector2.ZERO
	for sibling in parent.get_children():
		# Goalies share this container but are GoalieUnits, so they cast to
		# null here and stay out of the shoving.
		var other := sibling as PlayerUnit
		if other == null or other == self:
			continue

		var away := global_position - other.global_position
		var gap := away.length()
		if gap < 0.01:
			# Exactly superimposed. Break the tie by instance id so the two of
			# them always separate instead of pushing each other equally.
			push += Vector2(0.0, 1.0 if get_instance_id() > other.get_instance_id() else -1.0)
		elif gap < personal_space:
			# Hard. Nothing fades this one.
			shove += (away / gap) * (1.0 - gap / personal_space) * 2.0
		elif gap < separation_radius:
			push += (away / gap) * (1.0 - gap / separation_radius)

	return push * ease_off + shove


func _ball_is_in_range() -> bool:
	if ball == null or not is_instance_valid(ball) or steal_cooldown > 0.0:
		return false
	return global_position.distance_to(ball.global_position) <= interest_radius


func _dribble_target() -> Vector2:
	if play_bounds.size.x <= 1.0:
		return global_position + Vector2(attack_dir * 120.0, 0.0)
	var goal_x: float = play_bounds.end.x if attack_dir > 0.0 else play_bounds.position.x
	return Vector2(goal_x, global_position.y)


func _pick_roam_target() -> void:
	_roam_target = home_position + Vector2(
		randf_range(-roam_radius, roam_radius),
		randf_range(-roam_radius, roam_radius)
	)
	_roam_wait = randf_range(1.5, 4.0)


func _clamp_to_bounds() -> void:
	if play_bounds.size.x <= 1.0 or play_bounds.size.y <= 1.0:
		return
	global_position.x = clampf(global_position.x, play_bounds.position.x, play_bounds.end.x)
	global_position.y = clampf(global_position.y, play_bounds.position.y, play_bounds.end.y)


# --- Scripted moves (substitutions, pre-combat framing) ------
# These take over from the steering above by clearing is_roaming, so the
# two never fight over `position`.

func run_to(target: Vector2, duration: float = 0.6) -> void:
	var was_roaming := is_roaming
	is_roaming = false
	var tween := create_tween()
	tween.tween_property(self, "global_position", target, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished
	is_roaming = was_roaming


func return_home(duration: float = 0.35) -> void:
	# Used before a combat zoom-in so the camera frames a predictable spot.
	await run_to(home_position, duration)


# --- The goal celebration ------------------------------------
#
# ============ ONLY THE FIGURE GOES DOWN ============
#
# `artwork` is the sprite; the name plate is a separate child of this node.
# Tipping the WHOLE unit over would lay the name tag on its side, and a name
# you have to turn your head to read is worse than no name. So the sprite
# rotates and the plate stays upright — which is also what a television
# caption does, and for the same reason.

## He skids to `target` over `seconds`, on his side. See stand_up().
func slide_to(target: Vector2, seconds: float) -> void:
	if seconds <= 0.0:
		return
	var was_roaming := is_roaming
	is_roaming = false
	# A PITCH SHEET HAS ITS OWN SLIDE. No tipping the picture over.
	if pitch_sheet:
		play_once("tackle", target - global_position)
		var glide := create_tween()
		glide.tween_property(self, "global_position", target, seconds) \
			.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		await glide.finished
		is_roaming = was_roaming
		return
	# He falls toward whichever way he is facing, so a slide never looks like
	# it went through him.
	var tilt := deg_to_rad(76.0) * (-1.0 if is_enemy else 1.0)
	var skid := create_tween()
	skid.set_parallel(true)
	skid.tween_property(self, "global_position", target, seconds) \
		.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	if artwork != null:
		# THE FALL IS QUICK AND THE SKID IS LONG. Going down takes a quarter
		# of the time and the rest of it is him travelling along the grass,
		# which is the shape of a real one.
		skid.tween_property(artwork, "rotation", tilt, seconds * 0.25) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await skid.finished
	is_roaming = was_roaming


## Back on his feet. Called at the END of the celebration however it ended —
## including when it was skipped — so nobody is ever left lying on the grass
## for the rest of the match.
func stand_up(seconds: float = 0.3) -> void:
	if artwork == null or is_zero_approx(artwork.rotation):
		return
	var up := create_tween()
	up.tween_property(artwork, "rotation", 0.0, maxf(0.05, seconds)) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


# =============================================================
#  THE ISOMETRIC FIGURE  (round AN, src/core/pitch_sprite.gd)
#
#  On a pitch sheet the figure turns to one of 8 directions and plays idle,
#  run, kick, tackle, fall and cheer from data/PitchAnims.csv. It watches
#  where it actually moved each frame, so steering, tweens and the
#  celebration all animate without telling it anything.
#
#  Moving = run, toward where it went. Standing = idle, facing the ball (or
#  cheering, while `celebrating`). play_once() puts a kick, tackle or fall
#  over the top until it has played through.
# =============================================================

## True when this unit wears an isometric pitch sheet.
var pitch_sheet := false
## While true, standing still means cheering. Set by the goal celebration.
var celebrating := false
## 0-7 (PitchSprite.DIRECTIONS) to stand facing that way instead of the ball.
## The line-up before kick-off sets it so everyone faces the camera. -1 = off.
var pose_facing := -1

var _anim_name := ""
var _anim_time := 0.0
var _one_shot := ""
var _dir := 2            # south, facing the camera
var _last_spot := Vector2.ZERO
var _still_for := 0.0


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not pitch_sheet or artwork == null:
		return
	var moved := global_position - _last_spot
	_last_spot = global_position
	var speed := moved.length() / maxf(delta, 0.0001)
	var screen := get_canvas_transform().basis_xform(moved)

	if _one_shot != "":
		_anim_time += delta
		var spec := PitchSprite.anim(_one_shot)
		if spec.is_empty() or _anim_time * float(spec["fps"]) >= float(spec["frames"]):
			_one_shot = ""
		else:
			_draw_frame(_one_shot)
			return

	# A few px/s of shuffle is not running. A short grace stops a player who
	# pauses for one frame flickering between run and idle.
	if speed > 6.0:
		_still_for = 0.0
		var turned := PitchSprite.direction_of(screen, _squash())
		if turned >= 0:
			_dir = turned
		_show_anim("run")
	else:
		_still_for += delta
		if _still_for < 0.12 and _anim_name == "run":
			_anim_time += delta
			_draw_frame("run")
			return
		if pose_facing >= 0:
			_dir = posmod(pose_facing, 8)
		elif not celebrating:
			_look_at_ball()
		_show_anim("cheer" if celebrating and PitchSprite.has_anim("cheer") else "idle")
	_anim_time += delta
	_draw_frame(_anim_name)


## Play `anim_name` once, facing `toward` (a pitch direction) if given.
func play_once(anim_name: String, toward: Vector2 = Vector2.ZERO) -> void:
	if not pitch_sheet or not PitchSprite.has_anim(anim_name):
		return
	if toward.length_squared() > 0.0001:
		var turned := PitchSprite.direction_of(
			get_canvas_transform().basis_xform(toward), _squash())
		if turned >= 0:
			_dir = turned
	_one_shot = anim_name
	_anim_time = 0.0
	_draw_frame(anim_name)


func _show_anim(anim_name: String) -> void:
	if anim_name != _anim_name:
		_anim_name = anim_name
		_anim_time = 0.0
	_draw_frame(anim_name)


func _draw_frame(anim_name: String) -> void:
	var spec := PitchSprite.anim(anim_name)
	if spec.is_empty():
		spec = PitchSprite.anim("idle")
		if spec.is_empty():
			return
	var frames: int = spec["frames"]
	var step := int(_anim_time * float(spec["fps"]))
	step = posmod(step, frames) if bool(spec["loop"]) else mini(step, frames - 1)
	var row: int = int(spec["row"]) + _dir
	if row >= artwork.vframes:
		return
	artwork.frame = row * artwork.hframes + mini(step, artwork.hframes - 1)


func _look_at_ball() -> void:
	if ball == null or not is_instance_valid(ball):
		return
	var gap := ball.global_position - global_position
	if gap.length() < face_deadzone:
		return
	var turned := PitchSprite.direction_of(get_canvas_transform().basis_xform(gap), _squash())
	if turned >= 0:
		_dir = turned


func _squash() -> float:
	var db := CardDatabase.get_db()
	return db.tune_float("pitch_ground_squash", 2.0) if db != null else 2.0
