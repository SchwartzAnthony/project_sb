extends SceneTree

# =============================================================
#  A WHOLE LEAGUE MATCH, PLAYED THROUGH, WITH NOBODY WATCHING
#
#  ============ WHY THIS EXISTS ============
#
#  Every other tool looks at ONE moment: the shape of the pitch, the restart,
#  a screenshot of the draft. None of them answers the question that actually
#  matters after a change to the match —
#
#      does a match still get from kick-off to full time?
#
#  Adventure has had `adventure_soak.gd` since round H and it has caught real
#  crashes. The league match had nothing, which is how a celebration that
#  never returned, or a hold that never lifted, could have shipped: both
#  would look like the game having frozen, and a frozen game prints nothing.
#
#  ============ WHAT IT DOES ============
#
#  AUTO on, speed up, and let it play. Every few seconds it reports where the
#  match is; if that report stops changing it says so and gives up rather
#  than hanging for ever, because A TOOL THAT HANGS IS A TOOL NOBODY RUNS.
#
#  At the end: the score, the goals, how long it took, and whether the match
#  actually finished.
#
#      godot --headless --script res://tools/match_soak.gd
#
#  A tool, not part of the game. Nothing loads it.
# =============================================================

## Give up if nothing at all has changed for this long. Generous, because a
## celebration and a restart together are ten seconds of nothing happening.
const STUCK_SECONDS := 45.0
const GIVE_UP_SECONDS := 900.0
var _last_minute := 0.0

var _last_change := 0.0
var _last_state := ""


func _initialize() -> void:
	# Round AB: SOAK_SEED changes the match (tools/balance_report.py plays many).
	var seed_text := OS.get_environment("SOAK_SEED")
	seed(int(seed_text) if seed_text.is_valid_int() else 20260922)
	await process_frame
	# Round AC: SOAK_TEST_ENV=1 plays inside the TEST COMPLETE ENVIRONMENT
	# (its own save, everything unlocked) instead of the plain save.
	# Round AD: any window that opens answers itself, so a save that says
	# "ask me" can never hang a soak.
	CardDatabase.get_db().tuning[CardDatabase._normalise("choice_window_seconds")] = "1"
	# SOAK_START=keeper_claim forces every PLAY MAKER start (PlayMakerStarts.csv).
	PlayMakerStarts.force_start = OS.get_environment("SOAK_START")
	if OS.get_environment("SOAK_TEST_ENV") == "1":
		TestEnvironment.enter(self)
		print("[soak] inside the TEST ENVIRONMENT")
	_pick_a_team()
	MatchMode.choose(self, "friendly")
	change_scene_to_file("res://src/formations/main_scene.tscn")
	for i in 10:
		await process_frame

	var scene := current_scene
	if scene == null:
		print("[soak] the match did not open")
		quit(1)
		return

	# ---- past the team sheet and the line-ups ----
	for i in 300:
		await create_timer(0.2, true, false, true).timeout
		scene = current_scene
		if scene == null:
			continue
		var sheet = scene.get("_sheet")
		if sheet != null and is_instance_valid(sheet):
			if bool(sheet.get("_opened")):
				sheet.call("_go")
			continue
		var parade = _find(scene, "LineUpParade")
		if parade != null:
			parade.call("skip")
			continue
		break

	scene = current_scene
	if scene == null:
		print("[soak] the match went away before it started")
		quit(1)
		return

	# ---- AUTO on, and fast ----
	#
	# AUTO answers the clash and the draft. Without it the tool sits on the
	# first PLAY MAKER for ever, which is the whole reason every other tool
	# in here turns it on as well.
	var state = scene.get("state")
	MatchHUD.set_auto_pick(state, true)
	if scene.has_method("_on_auto_pick_changed"):
		scene.call("_on_auto_pick_changed", true)
	var speed_text := OS.get_environment("SOAK_SPEED")
	GameSpeed.set_speed(float(speed_text) if speed_text.is_valid_float() else 4.0)

	var started := Time.get_ticks_msec()
	var goals := 0
	var finished := false
	_last_change = 0.0

	while true:
		await create_timer(0.5, true, false, true).timeout
		var ran := float(Time.get_ticks_msec() - started) / 1000.0

		if not is_instance_valid(scene):
			print("[soak] the match scene disappeared after %.0fs — that is the end of it." % ran)
			# ============ A FALSE ALARM THIS USED TO RAISE (round X) ============
			# The game can reach full time AND leave for the next screen
			# between two of these half-second looks, so the soak never saw
			# state 4 and called a finished match a failure. If the clock was
			# within one round of the end when it was last seen, the match
			# finished - the Output panel above says FULL TIME either way.
			var length := float(CardDatabase.get_db().tune_int("match_length_minutes", 90))
			if _last_minute >= length - 12.0:
				print("[soak] it was at minute %.0f of %.0f - it finished and moved on before the soak looked." % [_last_minute, length])
				finished = true
			break
		_last_minute = float(scene.get("match_time_minutes"))

		var score := "%d-%d" % [int(scene.get("player_score")), int(scene.get("enemy_score"))]
		var here := "%s %d %.1f" % [score, int(scene.get("current_state")),
			float(scene.get("match_time_minutes"))]

		var total := int(scene.get("player_score")) + int(scene.get("enemy_score"))
		if total > goals:
			goals = total
			print("[soak] %5.0fs  GOAL — %s   (minute %.0f)"
				% [ran, score, float(scene.get("match_time_minutes"))])

		# ============ IS IT STILL MOVING? ============
		#
		# The state, the clock and the score together. A celebration holds the
		# clock, and a draft holds it too, but the STATE changes when either
		# begins and ends — so all three being identical for forty-five
		# seconds means something has stopped.
		if here != _last_state:
			_last_state = here
			_last_change = ran
		elif ran - _last_change > STUCK_SECONDS:
			print("[soak] STUCK. Nothing has changed for %.0fs at %s." % [STUCK_SECONDS, here])
			print("[soak] state 0=pre 1=playing 2=drafting 3=autobattle 4=full time")
			print("[soak] FAILED after %.0fs." % ran)
			quit(1)
			return

		if int(scene.get("current_state")) == 4:   # MatchState.FULL_TIME
			finished = true
			print("[soak] %5.0fs  FULL TIME — %s" % [ran, score])
			break

		if ran > GIVE_UP_SECONDS:
			print("[soak] gave up after %.0fs without reaching full time." % ran)
			break

	print("")
	if finished:
		print("[soak] the match finished. %d goal(s), %.0f seconds of real time."
			% [goals, float(Time.get_ticks_msec() - started) / 1000.0])
		print("[soak] NO TROUBLE.")
		quit(0)
	else:
		print("[soak] the match did NOT reach full time.")
		quit(1)


func _find(node: Node, wanted: String):
	if node == null:
		return null
	if node.name == wanted:
		return node
	for child in node.get_children():
		var hit = _find(child, wanted)
		if hit != null:
			return hit
	return null


func _pick_a_team() -> void:
	var db := CardDatabase.get_db()
	# ROUND Z: SOAK_CLASS=Lorelei (an environment variable) plays that class,
	# so each class's engine - tokens, swans, burn, Ore - gets a full match.
	var wanted := OS.get_environment("SOAK_CLASS")
	for card in db.players:
		if wanted != "":
			break
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
