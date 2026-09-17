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

const SECONDS := 150


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

	# AUTO plays it, so the whole round happens without a mouse.
	var state = scene.get("state")
	MatchHUD.set_auto_pick(state, true)
	if scene.has_method("_on_auto_pick_changed"):
		scene.call("_on_auto_pick_changed", true)

	var last: Dictionary = {}
	var still := 0
	var worst_box := 0
	for tick in SECONDS:
		await create_timer(1.0, true, false, true).timeout
		if not is_instance_valid(scene):
			break

		var moved := 0.0
		var box := 0
		var units: Array = scene.call("_all_units")
		for unit in units:
			var id: int = unit.get_instance_id()
			if last.has(id):
				moved += (unit.global_position - Vector2(last[id])).length()
			last[id] = unit.global_position
			if _in_a_box(scene, unit):
				box += 1
		worst_box = maxi(worst_box, box)

		var ball = scene.get("ball")
		var who := "-"
		if ball != null and is_instance_valid(ball):
			var holder = ball.get("carrier")
			who = str(holder.name) if holder != null and is_instance_valid(holder) else "loose"

		if moved < 1.0 and int(scene.get("current_state")) == 1:
			still += 1
		else:
			still = 0

		print("[restart] %3ds  state %s  freeze %s  ball %-12s  moved %7.1f  near-keeper %d%s" % [
			tick + 1, str(scene.get("current_state")), str(scene.get("_freeze_depth")),
			who, moved, box, "   <-- NOBODY MOVED" if still >= 2 else ""])

		if still >= 6:
			print("[restart] STUCK: six seconds of play with nobody moving.")
			quit(1)
			return

	print("[restart] done. Most players standing over a keeper at once: %d" % worst_box)
	quit(0)


## STANDING OVER A KEEPER. Not "in the penalty area" — plenty of football
## happens in a penalty area. This is the huddle: an outfield player within a
## couple of strides of either keeper.
func _in_a_box(scene: Node, unit) -> bool:
	var keepers: Dictionary = scene.get("goalies")
	for key in keepers.keys():
		var keeper = keepers[key]
		if keeper == null or not is_instance_valid(keeper):
			continue
		if unit.global_position.distance_to(keeper.global_position) < 110.0:
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
