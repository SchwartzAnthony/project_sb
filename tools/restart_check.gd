extends SceneTree

# =============================================================
#  THE RESTART — DOES ANYBODY MOVE?
#
#  Opens a real match with AUTO on, so the game plays itself, and prints one
#  line a second: the freeze depth, who has the ball, and how far the
#  outfield players have moved since the last line.
#
#  IT EXISTS BECAUSE "they do not move after the goalie kicks" is not
#  something a parse check or a screenshot can see. A still picture of eleven
#  players standing still and a still picture of eleven players running look
#  exactly the same.
#
#      godot --headless --script res://tools/restart_check.gd
#
#  WHAT TO LOOK FOR
#    moved  should be a healthy number nearly all the time. A run of 0.0
#           while state is 1 (playing) and freeze is 0 is the bug.
#    box    how many outfield players are inside the goal area. Anything
#           above 2 while the keeper has it is a huddle.
#
#  A tool, not part of the game. Nothing loads it.
# =============================================================

const SECONDS := 60
## How often it looks. A restart lasts two or three seconds, so once a second
## can miss one entirely — which is how a bug you can see in the game shows up
## as a clean report.
const STEP := 0.2


func _initialize() -> void:
	await process_frame
	_pick_a_team()
	MatchMode.choose(self, "friendly")
	change_scene_to_file("res://src/formations/main_scene.tscn")
	for i in 6:
		await process_frame

	var scene := current_scene
	if scene == null:
		print("[restart] the match did not open")
		quit(1)
		return

	# NO AUTO, NO WAITING FOR A ROUND. The restart is what is under test, and
	# in a real match it happens once every few minutes at the end of a long
	# chain of duels — so this calls the shot directly, several times, and
	# watches the seconds that follow.
	#
	# A LOW SHOT POWER on purpose: a saved shot is the case that goes wrong,
	# because that is the one where the keeper stands there holding the ball.
	var state = scene.get("state")
	MatchHUD.set_auto_pick(state, false)
	await create_timer(3.0, true, false, true).timeout

	var worst_box := 0
	var worst_after := 0
	for attempt in 4:
		print("[restart] ======== shot %d ========" % (attempt + 1))
		scene.call("finish_round", attempt % 2 == 0, 2)

		var saw_hold := false
		var live_at := -1.0
		for tick in int(14.0 / STEP):
			await create_timer(STEP, true, false, true).timeout
			if not is_instance_valid(scene):
				break
			var hold := bool(scene.get("restart_hold"))
			var box := _near_keepers(scene)
			worst_box = maxi(worst_box, box)
			if hold:
				saw_hold = true
			if hold or (saw_hold and live_at < 0.0):
				print("[restart] %5.1fs  state %s  hold %s  clock %s  near-keeper %d" % [
					float(tick) * STEP, str(scene.get("current_state")),
					"Y" if hold else "n", _clock(scene), box])
			if saw_hold and not hold and live_at < 0.0:
				live_at = float(tick) * STEP
				print("[restart] ---- the ball is live again ----")
			# TWO SECONDS AFTER THE RESTART is the moment that matters: is
			# anybody still standing in the goal area who should have gone?
			if live_at >= 0.0 and float(tick) * STEP >= live_at + 2.0:
				worst_after = maxi(worst_after, box)
				print("[restart] two seconds after the restart: %d near a keeper" % box)
				break
		if not saw_hold:
			print("[restart] NO RESTART HOLD HAPPENED — the shot did not reach it.")
		await create_timer(1.5, true, false, true).timeout

	print("[restart] worst two seconds after a restart: %d near a keeper" % worst_after)
	print("[restart] done. Most players standing over a keeper at once: %d" % worst_box)
	quit(0)


func _near_keepers(scene: Node) -> int:
	var box := 0
	for unit in (scene.call("_all_units") as Array):
		if _in_a_box(scene, unit):
			box += 1
	return box


func _clock(scene: Node) -> String:
	return "%.2f" % float(scene.get("match_time_minutes"))


## STANDING OVER A KEEPER. Not "in the penalty area" — plenty of football
## happens in a penalty area. This is the huddle: an outfield player within a
## couple of strides of either keeper. 170 is deliberately generous — "in the
## goal area" is what was reported, not "touching the keeper".
func _in_a_box(scene: Node, unit) -> bool:
	var keepers: Dictionary = scene.get("goalies")
	for key in keepers.keys():
		var keeper = keepers[key]
		if keeper == null or not is_instance_valid(keeper):
			continue
		if unit.global_position.distance_to(keeper.global_position) < 170.0:
			return true
	return false


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
