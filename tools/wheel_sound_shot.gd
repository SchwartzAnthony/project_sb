extends SceneTree

# =============================================================
#  THE FREE KICK WHEEL WITH ITS SOUNDS, FILMED (24 Oct 2026)
#
#  Like clash_wheel_shot.gd, but plays it twice - once you win the call
#  (confetti, then you press ATTACK), once they win - and writes when each
#  sound fired (wheel_sound_times.txt beside the pictures in
#  user://wheel_sound/) so a film with the sound can be put together.
#
#      xvfb-run godot --rendering-driver opengl3 --resolution 1920x1080 \
#          --script res://tools/wheel_sound_shot.gd
#
#  A tool, not part of the game. Nothing loads it.
# =============================================================

func _initialize() -> void:
	seed(20260923)
	await process_frame
	_pick_a_team()
	MatchMode.choose(self, "friendly")
	change_scene_to_file("res://src/formations/main_scene.tscn")
	for i in 10:
		await process_frame

	# ---- past the sheet, the line-ups and the kick-off ----
	var pressed := false
	for i in 300:
		await create_timer(0.2, true, false, true).timeout
		if current_scene == null:
			continue
		var sheet = current_scene.get("_sheet")
		if sheet != null and is_instance_valid(sheet):
			# ONCE. Pressing START on every poll is what turned up the
			# double-kick-off bug — see _on_kick_off_wanted() in main_scene.
			if bool(sheet.get("_opened")) and not pressed:
				pressed = true
				sheet.call("_go")
			continue
		# SKIP, AND THEN KEEP CHECKING. The parade puts your side up, then
		# theirs, and `skip` on the first one does not stop the second from
		# being built — which is how the first run of this tool photographed
		# the cut-away through a team sheet.
		var parade = _find(current_scene, "LineUpParade")
		if parade != null:
			parade.call("skip")
			continue
		break
	for i in 100:
		await create_timer(0.1, true, false, true).timeout
		var still = _find(current_scene, "LineUpParade")
		if still == null:
			break
		still.call("skip")
	for i in 300:
		await create_timer(0.1, true, false, true).timeout
		if current_scene != null and int(current_scene.get("current_state")) == 1:
			break
	await create_timer(0.8, true, false, true).timeout

	var scene := current_scene
	if scene == null:
		quit(1)
		return
	scene.call("freeze_play", true)
	var rps = scene.get("rps")
	DirAccess.make_dir_recursive_absolute("user://wheel_sound")
	var started := Time.get_ticks_msec()
	var log := FileAccess.open("user://wheel_sound/wheel_sound_times.txt", FileAccess.WRITE)
	var frame := 0
	for round_win in [true, false]:
		rps.call("start")
		rps.call("set_locked", false)
		for i in 6:
			await create_timer(0.1, true, false, true).timeout
			_shoot(frame, started, log); frame += 1
		# Settle where it stops first, then call ON it (a win) or far from it.
		seed(4242 if round_win else 777)
		randi()
		var stop := 1 + randi() % 10
		seed(4242 if round_win else 777)
		var call := stop if round_win else ((stop + 4) % 10) + 1
		log.store_line("%d sound wheel_pick" % (Time.get_ticks_msec() - started))
		log.store_line("%d sound wheel_spin" % (Time.get_ticks_msec() - started))
		rps.call("_pick", call)
		var title := ""
		var chose := false
		for i in 70:
			await create_timer(0.1, true, false, true).timeout
			_shoot(frame, started, log); frame += 1
			var now: String = rps.get("_title").text
			if now != title:
				if title == "THE WHEEL":
					log.store_line("%d sound %s" % [Time.get_ticks_msec() - started,
						"wheel_win" if int(rps.get("_picked")) == int(rps.get("_landed")) or round_win else "wheel_lose"])
				title = now
			if not bool(rps.call("is_running")):
				break
			if round_win and not chose and bool(rps.call("awaiting_choice")):
				for k in 14:
					await create_timer(0.1, true, false, true).timeout
					_shoot(frame, started, log); frame += 1
				chose = true
				log.store_line("%d sound side_chosen" % (Time.get_ticks_msec() - started))
				rps.call("_choose", true)
		for i in 8:
			await create_timer(0.1, true, false, true).timeout
			_shoot(frame, started, log); frame += 1
	log.close()
	quit(0)


func _shoot(frame: int, started: int, log: FileAccess) -> void:
	if DisplayServer.get_name() == "headless":
		return
	root.get_texture().get_image().save_png("user://wheel_sound/ws_%03d.png" % frame)
	log.store_line("%d frame %03d" % [Time.get_ticks_msec() - started, frame])


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
