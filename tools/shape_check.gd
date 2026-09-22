extends SceneTree

# =============================================================
#  ARE THEY STANDING IN PAIRS, AND IS ANYBODY USING THE PITCH?
#
#  The complaint this was written for: "Tier I and Tier IV are STILL next to
#  each other, it is as if they are coded to be stuck to each other."
#
#  A screenshot shows that and a parse check cannot, so it gets numbers:
#
#    GLUED PAIRS   two players from OPPOSITE sides within `PAIR_NEAR` pixels
#                  of each other AND within `PAIR_LEVEL` pixels of the same
#                  height. That is the shape in the screenshot: not merely
#                  close, but LEVEL — shoulder to shoulder, all match.
#
#    WIDTH USED    how much of the pitch's height the players cover AT ANY
#                  ONE MOMENT, averaged. Not the most anybody ever reached
#                  over the whole match, which is near 100% either way and
#                  tells you nothing — this is how spread the shape is while
#                  you are looking at it.
#
#    LENGTH USED   the same across the pitch.
#
#    SPREAD        the average distance from a player to the nearest other
#                  player. Small means a heap.
#
#    OWN-HALF CROSSINGS  how often a player is somewhere their Tier's home
#                  quarter is not. Zero means the zones are cages.
#
#      godot --headless --script res://tools/shape_check.gd
#
#  A tool, not part of the game. Nothing loads it.
# =============================================================

const SECONDS := 80
const STEP := 0.1
## Close enough to read as "next to each other".
const PAIR_NEAR := 120.0
## And level enough to read as "parallel".
const PAIR_LEVEL := 26.0


func _initialize() -> void:
	# THE SAME CARDS AND THE SAME COIN EVERY TIME. It does NOT make the run
	# identical - a real match is running at a real frame rate underneath
	# this, so the numbers still move a little between runs - but it takes
	# the draft and the clash out of the swing. Run it twice before you
	# believe a small change either way.
	seed(20260921)
	await process_frame
	_pick_a_team()
	MatchMode.choose(self, "friendly")
	change_scene_to_file("res://src/formations/main_scene.tscn")
	for i in 6:
		await process_frame

	var scene := current_scene
	if scene == null:
		print("[shape] the match did not open")
		quit(1)
		return

	var state = scene.get("state")
	MatchHUD.set_auto_pick(state, true)
	if scene.has_method("_on_auto_pick_changed"):
		scene.call("_on_auto_pick_changed", true)
	for i in 40:
		var sheet = scene.get("_sheet")
		if sheet == null or not is_instance_valid(sheet):
			break
		if bool(sheet.get("_opened")):
			sheet.call("_go")
			break
		await create_timer(0.2, true, false, true).timeout

	var worst_pairs := 0
	var pair_total := 0.0
	var tall_total := 0.0
	var wide_total := 0.0
	var spread_total := 0.0
	var samples := 0
	var out_of_zone := 0
	var placed := 0
	# ---- and the same numbers, split by WHAT IS HAPPENING ----
	#
	# One average over a whole match hides the two moments that were actually
	# complained about: the break at the shot, and the restart after a goal.
	# Both are short, so they barely move a match-long mean.
	var phase_pairs := {"open": 0.0, "break": 0.0, "restart": 0.0}
	var phase_gap := {"open": 0.0, "break": 0.0, "restart": 0.0}
	var phase_n := {"open": 0.0, "break": 0.0, "restart": 0.0}
	# ---- and DOES ANYBODY EVER GO ANYWHERE ----
	#
	# "Players never get even close to the edge of the field or get close to
	# the goal." A coarse grid of the pitch, ticked off as somebody stands in
	# each square, plus how near anyone came to each edge.
	var visited := {}
	var nearest_edge := {"top": INF, "bottom": INF, "own goal": INF, "their goal": INF}

	var play: Rect2 = scene.call("get_play_rect")

	for tick in int(float(SECONDS) / STEP):
		await create_timer(STEP, true, false, true).timeout
		if not is_instance_valid(scene):
			break
		var units: Array = scene.call("_all_units")
		if units.size() < 4:
			continue

		# ---- pairs standing level with an opponent ----
		var pairs := 0
		for i in units.size():
			for j in range(i + 1, units.size()):
				if units[i].is_enemy == units[j].is_enemy:
					continue
				var a: Vector2 = units[i].global_position
				var b: Vector2 = units[j].global_position
				if a.distance_to(b) < PAIR_NEAR and absf(a.y - b.y) < PAIR_LEVEL:
					pairs += 1
		worst_pairs = maxi(worst_pairs, pairs)
		pair_total += float(pairs)

		# ---- how spread the shape is RIGHT NOW ----
		var near_total := 0.0
		var top := INF
		var bottom := -INF
		var left := INF
		var right := -INF
		for unit in units:
			var here: Vector2 = unit.global_position
			top = minf(top, here.y)
			bottom = maxf(bottom, here.y)
			left = minf(left, here.x)
			right = maxf(right, here.x)

			var nearest := INF
			for other in units:
				if other == unit:
					continue
				nearest = minf(nearest, here.distance_to(other.global_position))
			near_total += nearest

			# ---- and whether anybody ever leaves their own quarter ----
			placed += 1
			visited[Vector2i(int((here.x - play.position.x) / play.size.x * 12.0),
				int((here.y - play.position.y) / play.size.y * 8.0))] = true
			nearest_edge["top"] = minf(float(nearest_edge["top"]), here.y - play.position.y)
			nearest_edge["bottom"] = minf(float(nearest_edge["bottom"]), play.end.y - here.y)
			nearest_edge["own goal"] = minf(float(nearest_edge["own goal"]), here.x - play.position.x)
			nearest_edge["their goal"] = minf(float(nearest_edge["their goal"]), play.end.x - here.x)
			var zone: Rect2 = unit.tier_zone
			if zone.size.x > 1.0 and (here.x < zone.position.x or here.x > zone.end.x):
				out_of_zone += 1

		var gap_now := near_total / float(units.size())
		var moment := "open"
		if bool(scene.get("restart_hold")):
			moment = "restart"
		elif int(scene.get("attack_surge_side")) >= 0:
			moment = "break"
		phase_pairs[moment] = float(phase_pairs[moment]) + float(pairs)
		phase_gap[moment] = float(phase_gap[moment]) + gap_now
		phase_n[moment] = float(phase_n[moment]) + 1.0

		spread_total += gap_now
		tall_total += bottom - top
		wide_total += right - left
		samples += 1

	var height := maxf(play.size.y, 1.0)
	var length := maxf(play.size.x, 1.0)
	print("")
	print("[shape] glued pairs: %d at the worst moment, %.1f on average" % [
		worst_pairs, pair_total / maxf(float(samples), 1.0)])
	print("[shape]   (opposite sides, within %d px AND level within %d px)"
		% [int(PAIR_NEAR), int(PAIR_LEVEL)])
	var shots := maxf(float(samples), 1.0)
	print("[shape] width of the pitch covered at any one moment:  %.0f%%" % (
		tall_total / shots / height * 100.0))
	print("[shape] length of the pitch covered at any one moment: %.0f%%" % (
		wide_total / shots / length * 100.0))
	print("[shape] average gap to the nearest other player: %.0f px" % (
		spread_total / maxf(float(samples), 1.0)))
	print("[shape] time spent outside their own quarter: %.0f%%   (0%% means the zones are cages)"
		% (float(out_of_zone) / maxf(float(placed), 1.0) * 100.0))
	print("")
	print("[shape] and the same, split by what was happening:")
	for moment in ["open", "break", "restart"]:
		var n: float = maxf(float(phase_n[moment]), 1.0)
		print("[shape]   %-8s %5.1f%% of the match   %.1f glued pairs   %.0f px to the nearest player"
			% [moment, float(phase_n[moment]) / maxf(float(samples), 1.0) * 100.0,
			   float(phase_pairs[moment]) / n, float(phase_gap[moment]) / n])
	print("")
	print("[shape] squares of the pitch anybody stood in: %d of 96" % visited.size())
	print("[shape] closest anybody came to   a touchline: %.0f px top, %.0f px bottom"
		% [float(nearest_edge["top"]), float(nearest_edge["bottom"])])
	print("[shape] closest anybody came to        a goal: %.0f px yours, %.0f px theirs"
		% [float(nearest_edge["own goal"]), float(nearest_edge["their goal"])])
	print("")
	print("[shape]   open = ordinary play, break = somebody is about to shoot, restart = after a goal")
	quit(0)


func _pick_a_team() -> void:
	var db := CardDatabase.get_db()
	var wanted := ""
	for card in db.players:
		if card.is_star():
			wanted = card.unit_type
			break
	if wanted == "":
		return
	var roster := db.roster_for_class(wanted)
	var picked := TeamSelection.new()
	picked.unit_type = wanted
	picked.star_tier = db.star_tier_for_class(wanted)
	var stars := db.stars_for_class(wanted)
	picked.star_bundle = stars
	picked.active_star = stars[0] if not stars.is_empty() else null
	for tier in TierLadder.TIERS:
		if tier == picked.star_tier:
			continue
		picked.regulars[tier] = TierLadder.build(roster, tier, db, false)["cards"]
	TeamSelection.store(self, picked)
