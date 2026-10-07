extends SceneTree

# =============================================================
#  PHOTOGRAPH THE MATCH MAKER, THE BAG, TEAM BUILD AND THE SONG BIRD
#  (round AN)
#
#      godot --path . --resolution 1920x1080 --script res://tools/match_maker_shot.gd
#
#  Presses the base's real Play a match flag and saves the Match Maker,
#  then the bag (no Keys tab) and Team Build (no Talents tab). Then it opens
#  the title screen and writes down, for two loops of the menu song, the
#  song second at which the bird lands - the two numbers should be the same.
#  Pictures go to user://match_maker/. Runs in the TEST ENVIRONMENT - your
#  save is safe.
# =============================================================

const OUT := "user://match_maker/"


func _initialize() -> void:
	await process_frame
	TestEnvironment.enter(self)
	var state := GameState.fetch(self)
	state.set_flag("game_begun")
	state.set_flag("tutorial_match", false)
	state.set_flag("tutorial_match_2", false)
	# No prologue over the base: an ordinary save that has seen it.
	state.set_flag("prologue_done")
	state.set_flag("brewery_tour", false)
	state.set_flag("intro_adventure", false)
	for row_id in ["welcome_at_base", "kick_off_first_match", "kick_off_second_match",
			"open_the_brewery", "meet_the_merchant"]:
		state.set_flag(Progression.DONE_PREFIX + row_id)
	DirAccess.make_dir_recursive_absolute(OUT)

	# ---- the base, and its Play a match flag ----
	change_scene_to_file("res://src/ui/base_screen.tscn")
	for i in 40:
		await process_frame
	await create_timer(0.8, true, false, true).timeout
	var base := current_scene
	for child in base.get_children():
		if child is NewUnlocksPanel:
			child.queue_free()
	var flag := _button_saying(base, "Play a match", "A friendly against")
	if flag == null:
		print("[maker] ! no Play a match button on the base.")
	else:
		flag.emit_signal("pressed")
		await create_timer(0.6, true, false, true).timeout
		var maker := base.get_node_or_null("MatchMaker")
		print("[maker] the Match Maker %s." % ("opened" if maker != null else "DID NOT OPEN"))
		_shoot("01_match_maker")
		if maker != null:
			maker.queue_free()
	await create_timer(0.3, true, false, true).timeout

	# ---- the bag ----
	var bag := InventoryScreen.open(base, state, InventoryScreen.Use.NOTHING)
	await create_timer(0.5, true, false, true).timeout
	_shoot("02_inventory")
	bag.close()
	await create_timer(0.2, true, false, true).timeout

	# ---- Team Build ----
	var window := BaseWindow.open(base, "Team Build", ScenePaths.TEAM_BUILD)
	await create_timer(0.8, true, false, true).timeout
	_shoot("03_team_build")
	if window != null:
		window.close()

	# ---- the bird and the song ----
	ScenePaths.go_to(self, "res://src/ui/main_menu.tscn")
	await create_timer(1.0, true, false, true).timeout
	var bird: TextureRect = null
	for node in _every(current_scene):
		if node is MenuMotion and (node as MenuMotion).kind == "bird":
			bird = (node as MenuMotion).art as TextureRect
	if bird == null:
		print("[maker] ! no bird on the title screen.")
	else:
		var landed_before := false
		var landings := 0
		var frame := 0
		var waited := 0.0
		var loops := 0 if OS.get_cmdline_user_args().has("no-bird") else 2
		while landings < loops and waited < 70.0:
			await create_timer(0.1, true, false, true).timeout
			waited += 0.1
			var song := AudioDirector.song_time(self)
			var landed := bird.visible and bird.position.is_equal_approx(
				(bird.get_child(0) as MenuMotion).home)
			if landed and not landed_before:
				landings += 1
				print("[maker] the bird landed at %.2f s into the song (loop %d)." % [song.x, landings])
				_shoot("04_bird_landed_loop%d" % landings)
			landed_before = landed
			# A strip of frames round each landing, for a GIF.
			if song.y > 0.0 and song.x > 2.5 and song.x < 12.5:
				root.get_texture().get_image().save_png(OUT + "bird_%03d.png" % frame)
				frame += 1
		print("[maker] %d bird frame(s) saved." % frame)

	print("[maker] pictures in %s" % ProjectSettings.globalize_path(OUT))
	TestEnvironment.leave(self)
	quit(0)


func _shoot(shot_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	root.get_texture().get_image().save_png(OUT + shot_name + ".png")
	print("[maker] %s.png" % shot_name)


## A button by its words, or (a banner, whose words are on the cloth) by
## the start of its hover text.
func _button_saying(from: Node, words: String, hover: String = "") -> Button:
	for node in _every(from):
		var button := node as Button
		if button == null:
			continue
		if hover != "" and button.tooltip_text.begins_with(hover):
			return button
		for label in _every(button):
			if label is Label and (label as Label).text.strip_edges() == words:
				return button
	return null


func _every(from: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child in from.get_children():
		out.append(child)
		out.append_array(_every(child))
	return out
