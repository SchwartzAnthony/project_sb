class_name PitchZones
extends RefCounted

# =============================================================
#  PITCH ZONES — the field cut into four quarters, one per Tier
#
#  Each side's Tier I sits in its OWN defensive quarter and its Tier IV in
#  the attacking one, so the two teams are MIRRORED — like a real formation,
#  with defenders at the back and attackers up front.
#
#      |  quarter 1 |  quarter 2 |  quarter 3 |  quarter 4 |
#      |  H-I  A-IV |  H-II A-III|  H-III A-II|  H-IV  A-I |
#      |____________|____________|____________|____________|
#      ^ home goal                          away goal ^
#
#  So your Tier I defenders stand opposite their Tier IV attackers. Marking
#  is therefore by QUARTER, not by Tier: whoever you share a patch of grass
#  with is who you shadow.
#
#  Within a quarter the home side stands nearer its own goal (always the
#  left) and the away side nearer theirs, which puts the pairs side by side.
#
#  A unit is pulled back toward its own quarter, but the SOFT zone is wider
#  than the strict one (33% of the pitch against 25%), so chasing a ball just
#  over the line is allowed and going walkabout is not.
# =============================================================

const TIERS: Array[String] = ["I", "II", "III", "IV"]

## Fraction of the pitch each Tier owns outright.
var share: float = 0.25
## Fraction it may stray into while chasing.
var stretch: float = 0.33
## How far across its own quarter each side stands. 0.34 = home a third in.
var home_inset: float = 0.34

var play: Rect2 = Rect2()


func _init(play_rect: Rect2 = Rect2(), zone_share: float = 0.25,
		zone_stretch: float = 0.33, side_inset: float = 0.34) -> void:
	play = play_rect
	share = zone_share
	stretch = zone_stretch
	home_inset = side_inset


static func tier_index(tier: String) -> int:
	return TIERS.find(tier.strip_edges().to_upper())


## Which quarter, left to right, this Tier occupies for this side. The away
## side is mirrored, so their Tier I is at the far end from yours.
func zone_index(tier: String, is_enemy: bool) -> int:
	var index := tier_index(tier)
	if index < 0:
		return -1
	return (TIERS.size() - 1 - index) if is_enemy else index


## The quarter a Tier owns. An unknown Tier gets the whole pitch rather than
## an empty rect, so a typo in a CSV cannot pin a unit to a single pixel.
func zone_for(tier: String, is_enemy: bool = false) -> Rect2:
	var index := zone_index(tier, is_enemy)
	if index < 0:
		return play
	var width := play.size.x * share
	return Rect2(play.position.x + float(index) * width, play.position.y,
		width, play.size.y)


## The wider band a unit may chase into.
func soft_zone_for(tier: String, is_enemy: bool = false) -> Rect2:
	var strict := zone_for(tier, is_enemy)
	if zone_index(tier, is_enemy) < 0:
		return play
	var extra := play.size.x * (stretch - share) * 0.5
	var wide := Rect2(strict.position.x - extra, strict.position.y,
		strict.size.x + extra * 2.0, strict.size.y)
	# Never allow straying off the pitch itself.
	return wide.intersection(play)


## Where one unit stands when nothing is happening: its lane inside its
## quarter, on its own side of it.
##
## `lane` is 0..count-1 top to bottom; a lone unit (a Star filling its tier by
## itself) stands in the middle.
func slot_for(tier: String, is_enemy: bool, lane: int, count: int) -> Vector2:
	var zone := zone_for(tier, is_enemy)
	var across := home_inset if not is_enemy else (1.0 - home_inset)

	var down := 0.5
	if count > 1:
		# Spread across the middle 70% of the pitch height, so nobody is
		# permanently glued to a touchline.
		down = 0.15 + (float(lane) / float(count - 1)) * 0.70

	return Vector2(
		zone.position.x + zone.size.x * across,
		zone.position.y + zone.size.y * down)


## Is a point inside this Tier's soft band? Used for "the ball is in my
## territory, go and get it".
func contains_x(tier: String, is_enemy: bool, point: Vector2) -> bool:
	var wide := soft_zone_for(tier, is_enemy)
	return point.x >= wide.position.x and point.x <= wide.end.x


## A push back toward the strict quarter, zero while inside it and growing
## the further out a unit has drifted. Returned as a direction, not a force,
## so the caller decides how hard it bites.
func recentre(tier: String, is_enemy: bool, at: Vector2) -> Vector2:
	var zone := zone_for(tier, is_enemy)
	if at.x >= zone.position.x and at.x <= zone.end.x:
		return Vector2.ZERO
	var edge: float = zone.position.x if at.x < zone.position.x else zone.end.x
	var over: float = absf(at.x - edge) / maxf(zone.size.x, 1.0)
	return Vector2(signf(edge - at.x) * minf(over * 2.0, 1.0), 0.0)


## Clamp a point into a Tier's soft band and inside the pitch.
func pin(tier: String, is_enemy: bool, point: Vector2) -> Vector2:
	var wide := soft_zone_for(tier, is_enemy)
	return Vector2(
		clampf(point.x, wide.position.x, wide.end.x),
		clampf(point.y, play.position.y + 24.0, play.end.y - 24.0))
