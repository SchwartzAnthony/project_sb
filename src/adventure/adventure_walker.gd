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
#  ============ HOW IT MOVES, AND WHY ============
#
#  The first version put everyone on a fixed grid and they ran as a block of
#  rows, which read as a queue rather than a team. Three things changed:
#
#    1. EVERY PLAYER HAS ITS OWN SPEED. A little faster or slower than the
#       party's, so they slide past each other constantly.
#    2. EVERY PLAYER DRIFTS. A slow sine wander around its slot, at its own
#       rate, so nobody sits exactly where the formation says.
#    3. NOBODY LEAVES THE LANE. Whatever the drift or the errand, the final
#       position is clamped into the grass band. That is the fix for the
#       party standing on the black above the pitch.
#
#  The result is a loose group crossing over each other as they run, which is
#  what a team jogging up a pitch actually looks like.
#
#  ============ IT DRAWS ITSELF UNTIL YOU GIVE IT ART ============
#
#  With no artwork it is a coloured disc with its power in the middle and a
#  stamina bar underneath — tinted by tier, so you can read a formation at a
#  glance. Give the card artwork in your unit CSV and the disc is replaced.
#  Nothing else changes. Same rule as the keeper on the pitch.
# =============================================================

## HOW BIG A PLAYER IS ON THE SCROLL.
##
## It is a `static var` rather than a `const` because the number really lives
## in Tuning.csv under `adventure_player_size`, and adventure_scene.gd writes
## it here as a run opens. Change the spreadsheet, not this line.
##
## The stamina bar under a player grows with it, so a bigger player does not
## end up with a thread of a bar beneath it.
static var RADIUS := 26.0


static func bar_width() -> float:
	return RADIUS * 2.2


static func bar_height() -> float:
	return maxf(4.0, RADIUS * 0.22)

## Who this is. Never written to — see adventure_run.gd for why.
var card: PlayerData = null

## Where it is trying to stand, before its own drift is added.
var target: Vector2 = Vector2.ZERO

## The band it must stay inside, in world coordinates. Set by the scene from
## the biome's lane. Nothing may put a player outside this.
var lane_top: float = 0.0
var lane_bottom: float = 1000.0

## 0 to 1. Only for drawing; the real number lives on the run.
var stamina_fraction: float = 1.0
var knocked_out: bool = false

## ============ OUT OF STAMINA MEANS ON THE GROUND ============
##
## A player with nothing left used to go grey and carry on jogging along with
## everybody else, which read as a bug rather than as a state. Now they drop
## where they stood: the sprite turns on its side, the drift stops, and they
## stay there until the fight is over and the stretcher comes for them.
##
## `lying` is the flag. Nothing moves a lying player except carried_to(),
## which is what the two bearers use to take them off the pitch.
var lying: bool = false

## Set while somebody else is moving them. It turns off this walker's own
## steering so the two things never fight over the same position.
var being_carried: bool = false

## True while it has broken formation to fetch something off the ground.
var fetching: bool = false

## Multiplies the party's speed for this one player, so the group spreads.
var pace: float = 1.0

var _speed: float = 260.0
var _bob: float = 0.0
var _drift_clock: float = 0.0
var _drift_rate: float = 1.0
var _drift_reach: float = 18.0
var _art: TextureRect = null


func setup(player: PlayerData, walk_speed: float = 260.0,
		db: CardDatabase = null) -> void:
	card = player
	_speed = maxf(20.0, walk_speed)

	# The nameplate. Built here rather than in _draw(), because adding a child
	# from inside _draw() is a tree change in the middle of drawing the tree.
	if _plate == null or not is_instance_valid(_plate):
		_plate = NamePlate.make()
		add_child(_plate)

	# Everything below is per-player randomness. It is what stops ten units
	# moving as one rectangle.
	_bob = randf() * TAU
	_drift_clock = randf() * TAU
	_drift_rate = randf_range(0.5, 1.15)
	_drift_reach = randf_range(10.0, 28.0)
	pace = randf_range(0.82, 1.22)

	# ONE FRAME, NOT THE WHOLE SHEET.
	#
	# This used to hand `card.artwork` straight to a TextureRect. That is the
	# entire spritesheet — 1536x2496 of it — squashed into a 40 pixel box,
	# which is why the players were slivers and dashes rather than people.
	#
	# MenuSupport.portrait_for() slices the first frame out using
	# Animations.csv, exactly the way the team builder and the card popup do.
	# So all three screens now show the same picture of the same player.
	var working_db := db if db != null else CardDatabase.get_db()
	var face := MenuSupport.portrait_for(card, working_db)
	if face != null:
		_art = TextureRect.new()
		_art.texture = face
		_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

		# ============ WHY THE PLAYERS WERE TINY ============
		#
		# This used to put the art in a SQUARE box of RADIUS * 2.4 and let
		# KEEP_ASPECT_CENTERED fit it in. A player frame is tall and narrow —
		# roughly 128 wide by 208 high — so fitting it into a square meant
		# the HEIGHT filled the box and the width shrank to about 60% of it.
		# Raising adventure_player_size made the square bigger, and the art
		# still came out a sliver, which is why the CSV looked like it was
		# being ignored. It was not: the square was.
		#
		# The box is worked out from the frame's own shape now. You say how
		# TALL a player should be and the width follows from the artwork, so
		# the number in the spreadsheet is the number you see.
		var tall := RADIUS * working_db.tune_float("adventure_player_art_scale", 3.4)
		var frame := face.get_size()
		var ratio := 0.62
		if frame.y > 1.0:
			ratio = clampf(frame.x / frame.y, 0.25, 4.0)
		_art.custom_minimum_size = Vector2(tall * ratio, tall)
		_art.size = _art.custom_minimum_size
		# Standing ON the spot rather than centred over it: the feet sit at
		# the player's position, which is what makes a crowd read as a crowd
		# rather than as floating heads.
		_art.position = Vector2(-_art.size.x * 0.5, _feet_y())
		_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_art)

		# MEASURE THE FRAME ONCE. Everything this player is labelled with is
		# placed from the rectangle the drawing actually fills, so a label
		# hugs the body whatever padding the sheet has. See name_plate.gd.
		_box = NamePlate.box_of(face)


## Where the top of the sprite goes so that its FEET land on the player's
## own position. One place, used by setup() and by the bob, so the two can
## never disagree.
func _feet_y() -> float:
	if _art == null:
		return 0.0
	return -_art.size.y + RADIUS * 0.5


## ============ WHERE THE LABELS GO ============
##
## Everything a player is labelled with — their name, their tier, their power
## and their stamina bar — is placed from the RECTANGLE THE ARTWORK ACTUALLY
## FILLS, not from the frame it sits in.
##
## A spritesheet frame is mostly empty. The character is somewhere in the
## middle of it with a lot of transparent padding, and how much differs from
## sheet to sheet. Measuring the frame meant measuring the padding, which is
## why the stamina bar floated a long way beneath a player and the cross over
## a fallen one sat well above their head.
##
## name_plate.gd reads the frame once and remembers the answer. See the
## header there; this file only has to say WHERE the artwork is and HOW BIG,
## and the plate does the rest.

## The opaque rectangle inside the frame, as a fraction of it. Worked out in
## setup() and never again.
var _box := Rect2(0, 0, 1, 1)
## The nameplate node. See name_plate.gd — the words are Labels so they stay
## crisp when the window is made smaller.
var _plate: NamePlate


## The four edges of the drawn character, in this walker's own coordinates.
##
## LYING DOWN IS A DIFFERENT SHAPE. The sprite is turned a quarter-turn, so
## what was its height is now its width — and the plate has to follow it
## round or the name ends up over empty grass.
func _edges() -> Dictionary:
	if _art == null:
		# No artwork: the player is the drawn disc, and the disc is the body.
		return {
			"top": -RADIUS, "bottom": RADIUS,
			"left": -RADIUS, "right": RADIUS, "middle": 0.0,
		}

	var size := _art.size
	var at := Vector2(-size.x * 0.5, _feet_y())
	if not lying:
		return NamePlate.edges(_box, at, size)

	# TURNED ON ITS SIDE. The opaque box turns with it: what was the box's
	# vertical extent is now horizontal, and the other way round. The sprite
	# rotates about its own middle, so that is what everything is measured
	# from.
	var centre := Vector2(0.0, _lying_middle_y())
	var half_high := _box.size.x * size.x * 0.5
	var half_wide := _box.size.y * size.y * 0.5
	return {
		"top": centre.y - half_high, "bottom": centre.y + half_high,
		"left": centre.x - half_wide, "right": centre.x + half_wide,
		"middle": centre.x,
	}


## The middle of a lying player, which is what lie_down() tweened the sprite
## to. One function, used by the tween and by the labels, so the two can
## never disagree about where the body is.
func _lying_middle_y() -> float:
	if _art == null:
		return 0.0
	return -_art.size.x * 0.5 + RADIUS * 0.25


# =============================================================
#  GOING DOWN, AND BEING PICKED UP
# =============================================================

## Drop where you stand. Called the moment the run says this player is out.
##
## The sprite turns a quarter-turn about its own middle and settles onto the
## grass. It is one tween, so calling this twice on the same player is
## harmless — the second call sees `lying` and leaves.
func lie_down() -> void:
	if lying:
		return
	lying = true
	knocked_out = true
	fetching = false

	# LIE DOWN ON THE GRASS, not half off it. Lying makes a player much taller
	# on screen than standing, so the room they need changes the moment they
	# go over — and somebody who was legally placed standing can be off the
	# band lying down. Re-clamped here, once, rather than every frame.
	var room := _lane_room()
	position.y = clampf(position.y, room.x, room.y)
	target = position

	if _art != null:
		# PIVOT IN THE MIDDLE. A Control turns about its top-left corner out of
		# the box, which would swing the player off sideways instead of laying
		# them down.
		_art.pivot_offset = _art.size * 0.5
		var drop := create_tween()
		drop.set_parallel(true)
		drop.tween_property(_art, "rotation", -PI * 0.5, 0.42) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		drop.tween_property(_art, "position", _lying_art_position(), 0.42) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	queue_redraw()


## Back on your feet. Used when a run ends and everybody is patched up.
func get_up() -> void:
	if not lying:
		return
	lying = false
	being_carried = false
	if _art != null:
		_art.rotation = 0.0
		_art.position = Vector2(-_art.size.x * 0.5, _feet_y())
	queue_redraw()


## ============ HOW HIGH AND HOW LOW THIS PLAYER MAY STAND ============
##
## Returns the lowest and highest y the player's own position may take, so
## that THE WHOLE BODY stays on the grass.
##
## It has to be worked out from the body rather than from a fixed radius,
## because a player who is LYING DOWN is a completely different shape: turned
## a quarter-turn, a sprite that was thirty pixels wide and a hundred tall is
## a hundred wide and thirty tall, and it reaches up from the feet line by
## half its own WIDTH.
##
## That is what put a knocked-out Tier I on the black. Tier I stands in the
## top row of the running shape, a fixed radius of twenty-six pixels below
## the top of the band — and then lay down and reached ninety pixels further
## up, which is off the grass entirely.
func _lane_room() -> Vector2:
	var edge := _edges()
	var above := absf(float(edge["top"]))
	var below := absf(float(edge["bottom"]))
	var lowest := lane_top + maxf(RADIUS * 0.5, above)
	var highest := lane_bottom - maxf(RADIUS * 0.5, below)
	# A band shallower than the player is a band the player cannot fit in.
	# Centre them rather than letting the two clamps fight.
	if lowest > highest:
		var middle := (lane_top + lane_bottom) * 0.5
		return Vector2(middle, middle)
	return Vector2(lowest, highest)


## Where the sprite's top-left corner goes so that a player lying on their
## side rests ON the grass rather than hovering over it.
##
## Turned a quarter-turn, the sprite's height on screen is its WIDTH — so the
## middle of it wants to sit half a width above the feet line.
func _lying_art_position() -> Vector2:
	if _art == null:
		return Vector2.ZERO
	return Vector2(-_art.size.x * 0.5, _lying_middle_y() - _art.size.y * 0.5)


## Move a downed player, because somebody is carrying them. The scene drives
## this every frame while the stretcher is walking; the walker itself does
## nothing, which is what `being_carried` is for.
func carried_to(where: Vector2) -> void:
	being_carried = true
	place_at(where)


## PUT THIS PLAYER SOMEWHERE, ON THE GRASS. The one way to move a walker
## from outside, and the only one that is guaranteed to keep the whole body
## inside the band — setting `position` by hand does not, which is how a
## stand-in walked on above the top edge and then lay down on the black.
##
## `x` is left alone: the lane runs off both sides of the screen on purpose.
func place_at(where: Vector2) -> void:
	var room := _lane_room()
	position = Vector2(where.x, clampf(where.y, room.x, room.y))
	target = position


func _process(delta: float) -> void:
	# ON THE GROUND, NOTHING MOVES. No drift, no bob, no walking to a slot.
	# Being carried is the same as far as this walker is concerned — the two
	# bearers are the ones doing the moving.
	if lying or being_carried:
		queue_redraw()
		return

	_drift_clock += delta * _drift_rate

	# THE DRIFT. A slow figure-of-eight around the slot: different rates on
	# x and y so the path is a lazy loop rather than a straight wobble.
	var wander := Vector2(
		sin(_drift_clock * 1.3) * _drift_reach,
		cos(_drift_clock) * _drift_reach * 1.4)
	var wanted := target + (Vector2.ZERO if fetching else wander)

	# THE LANE IS ABSOLUTE. Whatever the drift wanted, the player stays on
	# the grass — this is the clamp that keeps them off the black.
	var room := _lane_room()
	wanted.y = clampf(wanted.y, room.x, room.y)

	var to_target := wanted - position
	var step := _speed * pace * delta
	if to_target.length() <= step:
		position = wanted
	else:
		position += to_target.normalized() * step
	position.y = clampf(position.y, room.x, room.y)

	# A gentle bob while moving. Standing still, it settles.
	#
	# It bobs around the FEET LINE set in setup(), not around the middle of
	# the sprite — otherwise every frame would undo the standing-on-the-spot
	# placement and the players would float again.
	_bob += delta * (9.0 if to_target.length() > 2.0 else 2.0)
	if _art != null:
		_art.position.y = _feet_y() + sin(_bob) * (RADIUS * 0.09)

	queue_redraw()


## Has it arrived where it was sent? Generous, because the drift means a
## walker is never exactly on its slot.
func is_settled() -> bool:
	return position.distance_to(target) < _drift_reach + 8.0


func _draw() -> void:
	if card == null:
		return

	var tint := MenuSupport.colour_for_tier(card.get_tier_clean())
	if knocked_out:
		tint = tint.darkened(0.6)

	# --- The body, only when there is no artwork ---
	if _art == null and lying:
		# ON THE GROUND WITH NO ARTWORK: a body lying on its side, drawn wide
		# and low so it reads as "down" at a glance rather than as a smaller
		# disc. The artwork case is handled by the quarter-turn in lie_down().
		draw_rect(Rect2(Vector2(-RADIUS * 1.35, -RADIUS * 0.55),
			Vector2(RADIUS * 2.2, RADIUS * 0.9)), tint.darkened(0.35), true)
		draw_circle(Vector2(RADIUS * 1.0, -RADIUS * 0.1), RADIUS * 0.46,
			tint.darkened(0.2))
		draw_line(Vector2(-RADIUS * 1.4, RADIUS * 0.4),
			Vector2(RADIUS * 1.4, RADIUS * 0.4), Color(0, 0, 0, 0.25), 3.0)
	elif _art == null:
		var lift := sin(_bob) * 2.0
		var middle := Vector2(0.0, lift)
		# A soft shadow on the grass, so a player reads as standing ON the
		# pitch rather than floating over it.
		draw_circle(Vector2(0.0, RADIUS * 0.85), RADIUS * 0.8, Color(0, 0, 0, 0.22))
		draw_circle(middle, RADIUS, tint.darkened(0.25))
		draw_arc(middle, RADIUS, 0.0, TAU, 24,
			MenuSupport.COLOUR_ACCENT if not knocked_out else MenuSupport.COLOUR_TEXT_DIM,
			2.0, true)

		var font := ThemeDB.fallback_font
		var label := str(card.get_attack_power())
		# The number grows with the disc, so raising adventure_player_size
		# does not leave tiny writing in the middle of a big circle.
		var text_size := int(clampf(RADIUS * 0.95, 12.0, 34.0))
		var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, text_size).x
		draw_string(font, middle + Vector2(-width * 0.5, text_size * 0.36), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, text_size, MenuSupport.COLOUR_TEXT)

	# --- The nameplate: name over the head, Tier and Power at the feet,
	#     and the stamina bar hugging them underneath.
	#
	# THE SAME PLATE THE LEAGUE PITCH DRAWS, out of name_plate.gd, so the
	# same card reads the same way in both modes. The only difference is the
	# bar: a league player has no stamina, so there it is left off.
	var edge := _edges()
	# NOT CREATED HERE — see player_unit.gd. setup() builds it.
	if _plate == null or not is_instance_valid(_plate):
		return
	_plate.place(edge, card, clampf(stamina_fraction, 0.0, 1.0), knocked_out)

	if knocked_out:
		# THE CROSS GOES OVER THE MIDDLE OF THEM, wherever the middle is.
		# Standing that is chest height; lying down it is the middle of the
		# body on the grass. _edges() already worked out which.
		var middle := Vector2(float(edge["middle"]),
			(float(edge["top"]) + float(edge["bottom"])) * 0.5)
		_plate.mark_down(middle,
			maxf(8.0, (float(edge["bottom"]) - float(edge["top"])) * 0.16))
	else:
		_plate.clear_down_mark()
