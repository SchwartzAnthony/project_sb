extends SceneTree

# =============================================================
#  HOW MANY GOALS IS A MATCH? — the dial, read out loud
#
#  ============ WHY THIS EXISTS ============
#
#  I tuned `ShotOdds.csv` against a shot power of 0 to 8 and then measured
#  the game: SHOT POWERS ARE 10 TO 22. Every number in the `Per Power` column
#  was doing ten times the work I thought it was, and matches came out 3-3
#  and 0-4 instead of the 1-3 a side a football match should be.
#
#  That was a guess where a measurement belonged. This is the measurement.
#
#  ============ WHAT IT DOES ============
#
#  It does NOT play matches — a match takes two and a half minutes and you
#  would need thirty of them. It plays the SHOTS: it takes the real shot
#  powers a match produces, the real keeper stamina, the real number of
#  rounds, and rolls the real curve.
#
#      godot --headless --script res://tools/scoring_balance.gd
#
#  Out of it come the three numbers that decide whether the football is any
#  good:
#
#      goals per side per match, on average
#      how often a match ends 0-0, and how often somebody gets six
#      what fraction of shots go in
#
#  ============ THE SHOT POWERS ARE MEASURED, NOT INVENTED ============
#
#  `SHOT_POWERS` below came out of `tools/match_soak.gd` logs. If you change
#  the tier ladder, combos or brews, re-read a soak log and put the new
#  numbers in — and the honest way to do that is at the bottom of this file,
#  which prints the line to paste.
# =============================================================

## Shot powers seen in real matches, from match_soak.gd. See the note above.
const SHOT_POWERS: Array[int] = [10, 12, 14, 15, 15, 16, 16, 17, 17, 20, 22]

## Nine rounds a match — three cycles of three. Both sides shoot in a round
## only in the sense that ONE of them does; the loser of the clash defends.
const ROUNDS := 9
const MATCHES := 2000

## What we are aiming at, and the reason the round exists.
const WANT_LOW := 1.0
const WANT_HIGH := 3.0

## The crazy one-sided game: the better side wins this share of the clashes
## and its shots are worth this much more.
const ONE_SIDED_SHARE := 0.75
const ONE_SIDED_BONUS := 5
## Mirrors `shot_stamina_bite` in Tuning.csv. Read below, not hard-coded.
var BITE := 0.45


func _initialize() -> void:
	seed(20260924)
	var db := CardDatabase.get_db()
	var keeper_max := _typical_keeper(db)
	BITE = db.tune_float("shot_stamina_bite", 0.45)

	print("")
	print("=== SCORING BALANCE ===")
	print("  %d matches, %d rounds each, a keeper with %d stamina."
		% [MATCHES, ROUNDS, keeper_max])
	print("  shot powers: %s" % str(SHOT_POWERS))
	print("")

	var goals_for: Array[int] = []
	var total_shots := 0
	var total_goals := 0
	var nil_nil := 0
	var six_plus := 0
	var biggest := 0

	for m in MATCHES:
		# Two keepers, each with their own wall. A round is one shot at one
		# of them — whoever won the clash attacks.
		var stamina := {false: keeper_max, true: keeper_max}
		var scored := {false: 0, true: 0}

		for r in ROUNDS:
			var shooter_is_player := randf() < 0.5
			var target: bool = not shooter_is_player      # the OTHER keeper
			var power: int = SHOT_POWERS[randi() % SHOT_POWERS.size()]

			total_shots += 1
			var went_in := randf() < ShotOdds.odds(stamina[target], keeper_max, power)
			# The same order as the real thing: roll against what was shown,
			# THEN take the stamina off. See take_shot() in goalie_unit.gd.
			stamina[target] = maxi(0, int(stamina[target]) - int(round(float(power) * BITE)))
			if went_in:
				scored[shooter_is_player] = int(scored[shooter_is_player]) + 1
				total_goals += 1
				stamina[target] = keeper_max      # a conceded goal refills him

		var mine := int(scored[true])
		var theirs := int(scored[false])
		goals_for.append(mine)
		goals_for.append(theirs)
		if mine + theirs == 0:
			nil_nil += 1
		if maxi(mine, theirs) >= 6:
			six_plus += 1
		biggest = maxi(biggest, maxi(mine, theirs))

	var per_side := 0.0
	for g in goals_for:
		per_side += float(g)
	per_side /= float(goals_for.size())

	# ---- how often each score happens ----
	var spread: Dictionary = {}
	for g in goals_for:
		spread[g] = int(spread.get(g, 0)) + 1

	print("  GOALS FOR ONE SIDE, per match:  %.2f on average" % per_side)
	print("")
	print("  %-8s %8s %s" % ["goals", "of sides", ""])
	for g in range(0, maxi(7, biggest + 1)):
		var many := int(spread.get(g, 0))
		var share := 100.0 * float(many) / float(goals_for.size())
		print("  %-8d %7.1f%% %s" % [g, share, "#".repeat(int(round(share * 0.5)))])

	print("")
	print("  shots that went in:     %.0f%% (%d of %d)"
		% [100.0 * float(total_goals) / maxf(1.0, float(total_shots)), total_goals, total_shots])
	print("  matches that ended 0-0: %.1f%%" % [100.0 * float(nil_nil) / float(MATCHES)])
	print("  a side reaching six:    %.1f%%   (the crazy one-sided game)"
		% [100.0 * float(six_plus) / float(MATCHES)])
	print("  the most anybody scored: %d" % biggest)

	# ---- the verdict ----
	print("")
	if per_side < WANT_LOW:
		print("  ! TOO FEW. Aiming for %.0f to %.0f a side; this is %.2f."
			% [WANT_LOW, WANT_HIGH, per_side])
		print("  ! Raise the Chance column of ShotOdds.csv, or Per Power.")
	elif per_side > WANT_HIGH:
		print("  ! TOO MANY. Aiming for %.0f to %.0f a side; this is %.2f."
			% [WANT_LOW, WANT_HIGH, per_side])
		print("  ! Lower the Chance column of ShotOdds.csv, starting with the")
		print("  ! 25%% and 50%% rows — that is where most shots are taken.")
	else:
		print("  %.2f goals a side. That is inside the %.0f to %.0f you asked for."
			% [per_side, WANT_LOW, WANT_HIGH])

	# ============ AND THE CRAZY ONE-SIDED GAME ============
	#
	# The run above is two equal sides, which is the average case and not the
	# interesting one. "Six in a one-sided game" is a question about the TAIL,
	# and the tail is fattest when one side is simply better — bigger shots,
	# more of the clashes. This runs that.
	print("")
	print("  --- a one-sided game: the stronger side shoots %d%% of the rounds, %+d power ---"
		% [int(ONE_SIDED_SHARE * 100.0), ONE_SIDED_BONUS])
	var lopsided: Array[int] = []
	var got_six := 0
	for m in MATCHES:
		var stamina := keeper_max
		var scored := 0
		for r in ROUNDS:
			if randf() >= ONE_SIDED_SHARE:
				continue          # the weaker side had this round; ignore it
			var power: int = SHOT_POWERS[randi() % SHOT_POWERS.size()] + ONE_SIDED_BONUS
			if randf() < ShotOdds.odds(stamina, keeper_max, power):
				scored += 1
				stamina = keeper_max
			else:
				stamina = maxi(0, stamina - int(round(float(power) * BITE)))
		lopsided.append(scored)
		if scored >= 6:
			got_six += 1
	var strong := 0.0
	for g in lopsided:
		strong += float(g)
	strong /= float(lopsided.size())
	print("  the stronger side scores %.2f on average, and reaches six %.1f%% of the time."
		% [strong, 100.0 * float(got_six) / float(lopsided.size())])

	print("")
	print("  --- what one shot is worth, at the powers this game produces ---")
	print("  %-12s %7s %7s %7s %7s" % ["stamina", "P10", "P14", "P18", "P22"])
	for left in [100, 75, 50, 25, 10, 0]:
		var stamina := int(round(float(keeper_max) * float(left) / 100.0))
		print("  %3d%% (%2d)    %6d%% %6d%% %6d%% %6d%%" % [left, stamina,
			int(round(ShotOdds.chance(stamina, keeper_max, 10))),
			int(round(ShotOdds.chance(stamina, keeper_max, 14))),
			int(round(ShotOdds.chance(stamina, keeper_max, 18))),
			int(round(ShotOdds.chance(stamina, keeper_max, 22)))])

	print("")
	quit(0)


## The stamina of a typical keeper out of YOUR Goalies.csv, so the numbers
## above are about your game rather than about a number I made up.
func _typical_keeper(db: CardDatabase) -> int:
	var total := 0
	var many := 0
	for keeper in db.goalie_data:
		if keeper != null and keeper.max_stamina > 0:
			total += keeper.max_stamina
			many += 1
	return int(round(float(total) / float(many))) if many > 0 else 25
