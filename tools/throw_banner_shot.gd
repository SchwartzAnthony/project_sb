extends SceneTree

# =============================================================
#  THE THROW-IN WINDOW, BOTH SIDES, PHOTOGRAPHED
#
#  Opens the window over a real match twice: YOUR THROW (the two planks)
#  and THEIR THROW (the red panel). Pictures land in user://.
#
#      xvfb-run godot --rendering-driver opengl3 --resolution 1920x1080 \
#          --script res://tools/throw_banner_shot.gd
#
#  A tool, not part of the game. Nothing loads it.
# =============================================================

func _initialize() -> void:
	await process_frame
	MatchMode.choose(self, "friendly")
	change_scene_to_file("res://src/formations/main_scene.tscn")
	for i in 10:
		await process_frame
	# Press past the team sheet and the line-up, as tools/throw_in_shot.gd does.
	for i in 300:
		await create_timer(0.2, true, false, true).timeout
		var sheet = current_scene.get("_sheet") if current_scene != null else null
		if sheet != null and is_instance_valid(sheet):
			if bool(sheet.get("_opened")):
				sheet.call("_go")
			continue
		if current_scene != null:
			break
	for i in 120:
		await create_timer(0.1, true, false, true).timeout
		var parade = current_scene.find_child("LineUpParade", true, false)
		if parade == null:
			break
		parade.call("skip")
	await create_timer(1.5, true, false, true).timeout
	var db := CardDatabase.get_db()
	for side in [false, true]:
		var view := ThrowInView.open(current_scene, db, side, "Bauer throws in from the left touchline")
		ThemeBook.dress(self)
		for f in 12:
			await process_frame
		_shoot("throw_banner_%s" % ("yours" if side else "theirs"))
		view._finish(true)
		await process_frame
	quit(0)


func _shoot(shot_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	root.get_texture().get_image().save_png("user://%s.png" % shot_name)
	print("[throw] %s.png" % shot_name)
