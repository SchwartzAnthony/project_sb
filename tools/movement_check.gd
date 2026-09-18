extends SceneTree

# =============================================================
#  ARE THEY SHAKING, AND ARE THEY STANDING ON EACH OTHER?
#
#  Two complaints that a screenshot cannot answer and a parse check cannot
#  see, so they get a number each:
#
#    SHAKE     how often a player REVERSES DIRECTION — a turn of more than
#              120 degrees from one tenth of a second to the next. A player
#              walking somewhere scores nearly none. A player wandering round
#              their patch turns smoothly and scores a few. A player
#              vibrating on the spot reverses every single frame.
#
#              It is counted this way on purpose: "distance travelled over
#              distance gained" calls a wanderer a shaker, and wandering is
#              wanted.
#
#    TOUCHING  how many pairs of players are closer together than a player
#              is wide. Two is a tackle. Eight is a scrum.
#
#  It plays a real match with AUTO on and reports the worst second.
#
#      godot --headless --script res://tools/movement_check.gd
#
#  A tool, not part of the game. Nothing loads it.
# =============================================================

const SECONDS := 90
const STEP := 0.1
## Closer than this and two players are drawn on top of each other.
const TOO_CLOSE := 34.0


func _initialize() -> void:
	await process_frame
	_pick_a_team()
	MatchMode.choose(self, "friendly")
	change_scene_to_file("res://src/formations/main_scene.tscn")
	for i in 6:
		await process_frame

	var scene := current_scene
	if scene == null:
		print("[move] the match did not open")
		quit(1)
		return

	var state = scene.get("state")
	MatchHUD.set_auto_pick(state, true)
	if scene.has_method("_on_auto_pick_changed"):
		scene.call("_on_auto_pick_changed", true)
	# Past the team sheet: this is about the match, not the gate.
	for i in 40:
		var sheet = scene.get("_sheet")
		if sheet == null or not is_instance_valid(sheet):
			break
		if bool(sheet.get("_opened")):
			sheet.call("_go")
			break
		await create_timer(0.2, true, false, true).timeout

	var last: Dictionary = {}
	var heading: Dictionary = {}
	var flips: Dictionary = {}
	var worst_shake := 0.0
	var worst_touch := 0
	var touch_total := 0.0
	var still_seconds := 0.0
	var clock := 0.0
	var samples := 0

	for tick in int(float(SECONDS) / STEP):
		await create_timer(STEP, true, false, true).timeout
		if not is_instance_valid(scene):
			break
		var units: Array = scene.call("_all_units")
		if units.is_empty():
			continue

		# ---- how often each one turns round ----
		var moved_any := false
		for unit in units:
			var id: int = unit.get_instance_id()
			var here: Vector2 = unit.global_position
			if last.has(id):
				var step: Vector2 = here - Vector2(last[id])
				if step.length() > 0.4:
					moved_any = true
					if heading.has(id):
						var was: Vector2 = Vector2(heading[id])
						if was.length() > 0.001 \
								and was.normalized().dot(step.normalized()) < -0.5:
							flips[id] = int(flips.get(id, 0)) + 1
					heading[id] = step
			last[id] = here

		samples += 1
		clock += STEP
		if clock >= 1.0:
			for unit in units:
				var id2: int = unit.get_instance_id()
				worst_shake = maxf(worst_shake, float(flips.get(id2, 0)))
				flips[id2] = 0
			clock = 0.0

		# ---- how many pairs are on top of each other ----
		var touching := 0
		for i in units.size():
			for j in range(i + 1, units.size()):
				if units[i].global_position.distance_to(units[j].global_position) < TOO_CLOSE:
					touching += 1
		worst_touch = maxi(worst_touch, touching)
		touch_total += float(touching)

		# ---- is the pitch alive? ----
		var playing := int(scene.get("current_state")) == 1
		if playing and not moved_any:
			still_seconds += STEP

	print("")
	print("[move] worst shake  %.0f reversals in a second   (0-2 is walking or wandering. 6+ is vibrating)" % worst_shake)
	# THE AVERAGE IS THE HONEST ONE. The worst is a single tenth of a second
	# somewhere in ninety, and every scramble for a loose ball puts two players
	# inside a player's width for a moment — that is a tackle, not a fault. The
	# average says whether the pitch is LIVING like that.
	print("[move] pile-up: %d pairs at the worst moment, %.1f pairs on average, closer than %d pixels"
		% [worst_touch, touch_total / maxf(float(samples), 1.0), int(TOO_CLOSE)])
	print("[move] seconds of live play with nobody moving: %.1f" % still_seconds)
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
