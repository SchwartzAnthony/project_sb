extends SceneTree

# =============================================================
#  THE ADVENTURE LOOK CHECK  (adventure-look, 10 Oct 2026)
#
#  Opens the soccer & training board, unrolls the first scroll, rolls it up
#  again, then opens the run itself for a few seconds so the isometric
#  players run, stand and fight. Any error Godot prints is a real one.
#
#      godot --headless --path . --script res://tools/adventure_look_check.gd
#
#  With a window (no --headless) it also saves five pictures to
#  art_source/drafts/adventure_look/screens/.
#
#  It is a tool, not part of the game. Nothing loads it.
# =============================================================

const OUT := "res://art_source/drafts/adventure_look/screens/"


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _shot(file_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var image := root.get_texture().get_image()
	if image != null:
		image.save_png(ProjectSettings.globalize_path(OUT + file_name))
		print("[look] saved ", OUT + file_name)


func _run() -> void:
	# -- --biome=<id> : just the run in that biome, and one picture of it.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--biome="):
			await _one_biome(arg.substr(8))
			return
	change_scene_to_file(ScenePaths.BOUNTY_BOARD)
	await _frames(30)
	var board := current_scene as BountyBoard
	if board == null:
		push_error("[look] the board did not open")
		quit(1)
		return
	await _shot("board.png")

	var jobs := board.adventure.bounties_in(String(board._chosen_biome.get("id", "")), board.state)
	print("[look] %d scrolls on the board" % jobs.size())
	if not jobs.is_empty():
		board._open_scroll(jobs[0])
		await _frames(60)
		await _shot("scroll.png")
		var scroll := board._scroll
		if scroll == null:
			push_error("[look] the scroll did not open")
		else:
			scroll.close()
			await _frames(60)
			print("[look] scroll closed: ", board._scroll == null)

	change_scene_to_file(ScenePaths.ADVENTURE)
	await _frames(240)
	var scene := current_scene as AdventureScene
	if scene != null:
		var iso := 0
		for walker in scene._walkers:
			if walker._iso:
				iso += 1
		print("[look] %d of %d players are isometric" % [iso, scene._walkers.size()])
	await _shot("run.png")
	if scene != null:
		# A drop and a wave on the field, so their isometric pictures show.
		scene._drop_a_pickup()
		scene._drop_a_pickup()
		await _frames(120)
		print("[look] %d drops on the field" % scene._pickups.size())
		await _shot("run_wave.png")
		# Let the run go on, fast, until the first wave is met and the fight
		# opens, then look at the fight on the field.
		Engine.time_scale = 4.0
		var waited := 0
		while scene.current_state != AdventureScene.RunState.ENCOUNTER and waited < 3000:
			await process_frame
			waited += 1
		Engine.time_scale = 1.0
		await _frames(90)
		print("[look] fight open: %s, %d enemies" % [
			scene.current_state == AdventureScene.RunState.ENCOUNTER, scene._foes.size()])
		await _shot("fight.png")
	quit(0)


func _one_biome(biome_id: String) -> void:
	var adventure := AdventureDB.get_db()
	var biome := {}
	for entry in adventure.all_biomes():
		if String(entry.get("id", "")) == biome_id:
			biome = entry
	if biome.is_empty():
		push_error("[look] no biome " + biome_id)
		quit(1)
		return
	var jobs := adventure.bounties_in(biome_id, null)
	AdventureRun.begin(self, jobs[0] if not jobs.is_empty() else {}, biome)
	change_scene_to_file(ScenePaths.ADVENTURE)
	await _frames(300)
	print("[look] %s field open" % biome_id)
	await _shot("field_%s.png" % biome_id)
	quit(0)
