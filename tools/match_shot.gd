extends SceneTree

# =============================================================
#  SCREENSHOTS OF A REAL LEAGUE MATCH
#
#  Opens the match scene with a real team, watches the kick-off countdown and
#  the coin clash, and saves the screen at each step. It is how the two new
#  bits of the match get checked — a countdown that never appears and a coin
#  that never lands are not things a parse check can see.
#
#      xvfb-run godot --rendering-driver opengl3 --resolution 1920x1080 \
#          --script res://tools/match_shot.gd
#
#  A tool, not part of the game. Nothing loads it.
# =============================================================

var _shot := 0
var _scene: Node


func _initialize() -> void:
	await process_frame
	_pick_a_team()
	MatchMode.choose(self, "friendly")
	change_scene_to_file("res://src/formations/main_scene.tscn")
	for i in 4:
		await process_frame

	_scene = current_scene
	if _scene == null:
		print("[shot] the match did not open")
		quit(1)
		return

	# --- the team sheet, then the gate, then the kick-off ---
	for i in 6:
		await _wait(0.6)
		_snap("sheet-%d" % i)

	# Press START the way a player would — once the gate has actually opened,
	# which is the only moment a player could.
	var sheet = _scene.get("_sheet")
	for i in 20:
		sheet = _scene.get("_sheet")
		if sheet == null or not is_instance_valid(sheet):
			break
		if bool(sheet.get("_opened")):
			_snap("gate")
			sheet.call("_go")
			break
		await _wait(0.3)
	for i in 9:
		await _wait(0.45)
		_snap("kickoff-%d" % i)

	# --- hurry to the first PLAY MAKER and its clash ---
	if _scene.has_method("trigger_playmaker_event"):
		_scene.call("trigger_playmaker_event")
	for i in 14:
		await _wait(0.6)
		_snap("clash-%d" % i)
		var clash = _scene.get("rps")
		if clash != null and is_instance_valid(clash) and clash.has_method("awaiting_throw"):
			if clash.call("awaiting_throw"):
				clash.call("_pick", 4)
			elif clash.call("awaiting_choice"):
				clash.call("_choose", true)

	print("[shot] done")
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


func _wait(seconds: float) -> void:
	await create_timer(seconds, true, false, true).timeout


func _snap(label: String) -> void:
	var view := root.get_viewport()
	if view == null:
		return
	var picture := view.get_texture().get_image()
	if picture == null:
		return
	var path := "user://m_%02d_%s.png" % [_shot, label]
	_shot += 1
	picture.save_png(path)
	# WHAT EACH LINE SAYS, and why each one is worth printing:
	#   zoom   the camera actually moved. A kick-off that never pushes in
	#          looks identical to one that does in a still picture.
	#   ball   who is carrying. LOOSE means nobody — right for the countdown,
	#          wrong for a minute later, and that is the whole kick-off test.
	#   state  0 = pre-match, 1 = playing. The clock only runs on 1.
	var cam = _scene.get("camera") if _scene != null else null
	var z := 0.0
	if cam != null and is_instance_valid(cam):
		z = cam.zoom.x
	var b = _scene.get("ball") if _scene != null else null
	var who := "-"
	if b != null and is_instance_valid(b):
		var holder = b.get("carrier")
		who = str(holder.name) if holder != null and is_instance_valid(holder) else "LOOSE"
	print("[shot] %-26s zoom %.2f  ball %-14s  state %s" % [
		path.get_file(), z, who, str(_scene.get("current_state"))])
