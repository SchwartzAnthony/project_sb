extends SceneTree

# =============================================================
#  A PICTURE OF THE CLUB HOUSE AND ITS RECRUITMENT BOARD  (round AH)
#
#      xvfb-run godot --rendering-driver opengl3 --resolution 1920x1080 \
#          --script res://tools/recruit_shot.gd
#
#  Runs inside the TEST ENVIRONMENT, so your real save is never touched.
#  Writes recruit_board.png into the user:// folder.
# =============================================================


func _initialize() -> void:
	await process_frame
	TestEnvironment.enter(self)
	var db := CardDatabase.get_db()
	var state := GameState.fetch(self)
	state.set_count("coins", 120)
	state.set_count("matches_played", 4)
	RecruitBoard.sign(0, state, db)
	var room: Control = load("res://src/ui/rooms/clubhouse.tscn").instantiate()
	root.add_child(room)
	for i in 6:
		await process_frame
	await create_timer(0.4, true, false, true).timeout
	var picture := root.get_viewport().get_texture().get_image()
	picture.save_png("user://recruit_board.png")
	print("[shot] user://recruit_board.png")
	TestEnvironment.leave(self)
	quit(0)
