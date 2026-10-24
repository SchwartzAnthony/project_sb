extends "res://tools/match_shot.gd"

# =============================================================
#  THE PATCH BALL ROLLING IN A REAL MATCH
#
#  Opens a match the way match_shot.gd does, presses START, and once play is
#  running saves a frame every 1/15 s with the ball's spot on screen in the
#  name, so a GIF can be cut round the ball (tools/make_film_gif.py or ffmpeg).
#
#      xvfb-run godot --rendering-driver opengl3 --resolution 1920x1080 \
#          --script res://tools/ball_match_gif.gd
#
#  Frames land in user://ball_match/. A tool, not part of the game.
# =============================================================

const FRAMES_DIR := "user://ball_match"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(FRAMES_DIR)
	await process_frame
	_pick_a_team()
	MatchMode.choose(self, "friendly")
	change_scene_to_file("res://src/formations/main_scene.tscn")
	for i in 4:
		await process_frame
	_scene = current_scene
	if _scene == null:
		print("[ball_match] the match did not open")
		quit(1)
		return
	for i in 30:
		var sheet = _scene.get("_sheet")
		if sheet == null or not is_instance_valid(sheet):
			break
		if bool(sheet.get("_opened")):
			sheet.call("_go")
			break
		await _wait(0.3)
	# The kick-off countdown, then a little open play.
	await _wait(5.0)
	for i in 120:
		await _wait(1.0 / 15.0)
		await RenderingServer.frame_post_draw
		var spot := Vector2.ZERO
		var b = _scene.get("ball")
		if b != null and is_instance_valid(b):
			spot = (b as Node2D).get_global_transform_with_canvas().origin
		root.get_texture().get_image().save_png("%s/f%03d_%d_%d.png" % [
			FRAMES_DIR, i, int(spot.x), int(spot.y)])
	print("[ball_match] done in %s" % ProjectSettings.globalize_path(FRAMES_DIR))
	quit(0)
