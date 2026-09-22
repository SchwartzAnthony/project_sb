class_name PitchZones
extends RefCounted

# =============================================================
#  PITCH ZONES — where a Tier LIVES, not where it is allowed to be
#
#  ============ READ THIS BEFORE CHANGING ANYTHING HERE ============
#
#  A zone is a CENTRE OF GRAVITY. It is not a fence, it is not a cage, and
#  nothing in the game is ever stopped at its edge.
#
#  The zones exist for exactly one reason: to stop all twenty-two players
#  hovering around the ball in one heap. That is the whole job. Everything
#  else — reaching a touchline, running into the box, chasing a ball three
#  quarters of the pitch away — is supposed to happen, and the strength of
#  the pull back is the only thing that decides how often.
#
#  It used to be a cage: every target a unit was given was CLAMPED into a
#  band a third of the pitch wide, so nobody ever reached a touchline, nobody
#  ever got near a goal, and a Tier I standing at the edge of its band simply
#  stopped there. That is not what the zones were for.
#
#      THREE BANDS, from the inside out
#
#      home      a quarter of the pitch. Where this Tier stands when there
#                is nothing to do, and the point it is drawn back toward.
#      roam      SIXTY per cent of the pitch. Where it moves about freely
#                with no pull at all. Bands overlap enormously on purpose —
#                a Tier II and a Tier III share most of their grass.
#      chasing   the whole pitch. A unit going for the ball is never pulled
#                back by anything, because a defender who lets a striker go
#                at the edge of a rectangle is not playing football.
#
#  ============ WHO STANDS WHERE ============
#
#      |  quarter 1 |  quarter 2 |  quarter 3 |  quarter 4 |
#      |  H-I  A-IV |  H-II A-III|  H-III A-II|  H-IV  A-I |
#      |____________|____________|____________|____________|
#      ^ home goal                          away goal ^
#
#  Your Tier I defenders stand opposite their Tier IV attackers, so marking
#  is by QUARTER rather than by Tier: whoever shares your patch of grass is
#  who you pick up.
#
#  ============ AND WHY THEY ARE NOT IN PAIRS ANY MORE ============
#
#  The two sides used to be laid out on the SAME lanes — home at 15%, 50% and
#  85% down the pitch, away at 15%, 50% and 85% — with one standing a third
#  of a quarter to the left of the other. Three horizontal pairs, every match,
#  before a ball was kicked, which is what made them look glued together.
#
#  The away side is now offset by HALF A LANE (`lane_stagger`) and each lane
#  sits at a slightly different depth (`lane_depth_wave`), so a back three
#  is a staggered line like a real one and nobody has an opponent parked on
#  their exact eye level.
# =============================================================

const TIERS: Array[String] = ["I", "II", "III", "IV"]

## Fraction of the pitch each Tier calls home. The gravity, not the wall.
var share: float = 0.25
## Fraction it moves about in with NO pull back at all. Wide on purpose.
var roam: float = 0.60
## Fraction of the pitch inside which a loose ball is THIS Tier's job. Much
## narrower than the roam band — see claims_x().
var claim: float = 0.34
## How far across its own quarter each side stands. 0.34 = home a third in.
var home_inset: float = 0.34
## How far the away side's lanes are shifted against the home side's, as a
## fraction of the gap between two lanes. 0.5 = exactly between them.
var lane_stagger: float = 0.5
## How much each lane is pushed forward and back from the others, as a
## fraction of the quarter's width. 0 lines them up in a column.
var lane_depth_wave: float = 0.22

var play: Rect2 = Rect2()


func _init(play_rect: Rect2 = Rect2(), zone_share: float = 0.25,
		zone_roam: float = 0.60, side_inset: float = 0.34,
		stagger: float = 0.5, depth_wave: float = 0.22,
		zone_claim: float = 0.34) -> void:
	play = play_rect
	share = zone_share
	roam = maxf(zone_roam, zone_share)
	home_inset = side_inset
	lane_stagger = stagger
	lane_depth_wave = depth_wave
	claim = clampf(zone_claim, zone_share, 1.0)


static func tier_index(tier: String) -> int:
	return TIERS.find(tier.strip_edges().to_upper())


## Which quarter, left to right, this Tier occupies for this side. The away
## side is mirrored, so their Tier I is at the far end from yours.
func zone_index(tier: String, is_enemy: bool) -> int:
	var index := tier_index(tier)
	if index < 0:
		return -1
	return (TIERS.size() - 1 - index) if is_enemy else index


## The quarter a Tier calls home. An unknown Tier gets the whole pitch rather
## than an empty rect, so a typo in a CSV cannot pin a unit to a single pixel.
func zone_for(tier: String, is_enemy: bool = false) -> Rect2:
	var index := zone_index(tier, is_enemy)
	if index < 0:
		return play
	var width := play.size.x * share
	return Rect2(play.position.x + float(index) * width, play.position.y,
		width, play.size.y)


## THE BAND A UNIT MOVES ABOUT IN FREELY. Much wider than its home quarter,
## centred on it, and clipped to the pitch. Nothing is clamped to this — it is
## where the pull back is zero.
func roam_zone_for(tier: String, is_enemy: bool = false) -> Rect2:
	var home := zone_for(tier, is_enemy)
	if zone_index(tier, is_enemy) < 0:
		return play
	var want := play.size.x * roam
	var extra := maxf(0.0, (want - home.size.x) * 0.5)
	var wide := Rect2(home.position.x - extra, play.position.y,
		home.size.x + extra * 2.0, play.size.y)
	return wide.intersection(play)


## Kept under its old name because other code still asks for it. It is the
## roam band now — there is no "soft fence" any more, only the band inside
## which nothing pulls you.
func soft_zone_for(tier: String, is_enemy: bool = false) -> Rect2:
	return roam_zone_for(tier, is_enemy)


## Where one unit stands when nothing is happening.
##
## `lane` is 0..count-1 top to bottom. A lone unit — a Star filling its tier by
## itself — stands in the middle of its lane spread rather than dead centre, so
## two lone Stars in facing quarters are still not on the same line.
func slot_for(tier: String, is_enemy: bool, lane: int, count: int) -> Vector2:
	var zone := zone_for(tier, is_enemy)
	var across := home_inset if not is_enemy else (1.0 - home_inset)

	# ---- down the pitch ----
	#
	# Spread across the middle 76% of the height, then shift the AWAY side by
	# half the gap between lanes. That half-lane is the whole difference
	# between a formation and three pairs of players standing on each other.
	var spread := 0.76
	var step := spread / float(maxi(count, 2) - 1)
	var down := 0.5
	if count > 1:
		down = (0.5 - spread * 0.5) + float(lane) * step
	if is_enemy:
		down += step * lane_stagger
		# A lone away unit has no lane to be offset from, so it is nudged by
		# a fixed amount instead of by nothing.
		if count <= 1:
			down += 0.12
	down = clampf(down, 0.10, 0.90)

	# ---- and across it ----
	#
	# ============ THE BUG THAT PUT THEM BACK IN PAIRS ============
	#
	# The wave used to alternate +/- by lane and then FLIP for the away side.
	# Work it through with a wave of 0.22 and a home inset of 0.34:
	#
	#     lane 0   home 0.34 + 0.22 = 0.56      away 0.66 - 0.22 = 0.44
	#     lane 1   home 0.34 - 0.22 = 0.12      away 0.66 + 0.22 = 0.88
	#     lane 2   home 0.34 + 0.22 = 0.56      away 0.66 - 0.22 = 0.44
	#
	# On every even lane the flip walks the two sides TOWARD each other until
	# they are an eighth of a quarter apart — about fifty pixels — while the
	# odd lanes fly apart. That is the screenshot: some pairs glued, the rest
	# nowhere near anybody. The sign flip was meant to stop the two shapes
	# mirroring and it did the opposite.
	#
	# ============ WHAT IT DOES INSTEAD ============
	#
	# Both sides read the same smooth wave, so the gap between them never
	# closes — and the away side reads it at a DIFFERENT PHASE, so the gap is
	# never the same twice either. No two lanes of the two shapes are the same
	# distance apart, which is what stops it looking like ruled lines.
	#
	# The step is deliberately not a neat fraction of TAU: a tidy step makes
	# the pattern repeat every few lanes, and a formation that repeats is a
	# formation you can see the grid in.
	var wave := 0.0
	if count > 1:
		var step_angle := 1.9
		var phase_shift := 2.1 if is_enemy else 0.0
		wave = sin(float(lane) * step_angle + phase_shift) * lane_depth_wave
	across = clampf(across + wave, 0.10, 0.90)

	return Vector2(
		zone.position.x + zone.size.x * across,
		zone.position.y + zone.size.y * down)


## ============ WHOSE BALL IS IT ============
##
## Two different questions were being answered by one band, and it made a
## midfield heap:
##
##   "may I be here?"          the ROAM band — 60% of the pitch, deliberately
##                             enormous, because nothing should pull a player
##                             back from most of the grass.
##   "is that ball MINE?"      a much narrower claim. If every Tier claims
##                             everything inside 60% of the pitch, then a ball
##                             in the centre circle belongs to Tier II and
##                             Tier III of BOTH sides at once — six players
##                             set off for it and arrive in one knot.
##
## So the claim is its own band and it is tight. Being allowed to run
## somewhere and thinking the ball there is your job are not the same thing,
## and conflating them is what put five players on one blade of grass.
func claims_x(tier: String, is_enemy: bool, point: Vector2) -> bool:
	var home := zone_for(tier, is_enemy)
	if zone_index(tier, is_enemy) < 0:
		return true
	var want := play.size.x * claim
	var extra := maxf(0.0, (want - home.size.x) * 0.5)
	return point.x >= home.position.x - extra and point.x <= home.end.x + extra


## Kept because older code asks for it. It is the ROAM question — "am I
## allowed to be here" — not the claim.
func contains_x(tier: String, is_enemy: bool, point: Vector2) -> bool:
	var wide := roam_zone_for(tier, is_enemy)
	return point.x >= wide.position.x and point.x <= wide.end.x


## A push back toward home, ZERO anywhere inside the roam band and growing
## gently outside it. Returned as a direction, not a force, so the caller
## decides how hard it bites.
func recentre(tier: String, is_enemy: bool, at: Vector2) -> Vector2:
	var wide := roam_zone_for(tier, is_enemy)
	if at.x >= wide.position.x and at.x <= wide.end.x:
		return Vector2.ZERO
	var edge: float = wide.position.x if at.x < wide.position.x else wide.end.x
	var over: float = absf(at.x - edge) / maxf(wide.size.x, 1.0)
	return Vector2(signf(edge - at.x) * minf(over * 2.0, 1.0), 0.0)


## Keep a point on the PITCH. It used to keep a point inside a Tier's band as
## well, which is what stopped anybody ever reaching a touchline or a goal.
func pin(_tier: String, _is_enemy: bool, point: Vector2) -> Vector2:
	return Vector2(
		clampf(point.x, play.position.x + 16.0, play.end.x - 16.0),
		clampf(point.y, play.position.y + 20.0, play.end.y - 20.0))
