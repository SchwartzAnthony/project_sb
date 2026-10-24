extends SceneTree

# =============================================================
#  THE MATCH BALL, BIG, ROLLING
#
#  Puts one Ball on a green square, drawn large, and rolls it right, up,
#  left, down and round in a circle, saving a frame each step. Used to check
#  the patch ball (src/units/ball_face.gdshader) spins the way it travels.
#
#      xvfb-run godot --rendering-driver opengl3 --resolution 1920x1080 \
#          --script res://tools/ball_roll_shot.gd
#
#  Frames land in user://ball_roll/. A tool, not part of the game.
# =============================================================

const OUT := "user://ball_roll"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var grass := ColorRect.new()
	grass.color = Color(0.36, 0.55, 0.25)
	grass.size = Vector2(1920, 1080)
	root.add_child(grass)
	var ball := Ball.new()
	ball.radius = 120.0
	ball.trail_seconds = 0.0
	ball.ring_radius = 0.0
	root.add_child(ball)
	var spot := Vector2(960, 540)
	ball.global_position = spot
	await process_frame
	var frame := 0
	var legs := [Vector2(1, 0), Vector2(0, -1), Vector2(-1, 0), Vector2(0, 1)]
	for leg in legs:
		for i in 24:
			spot += leg * 15.0
			ball.global_position = spot
			await process_frame
			frame = await _snap(frame)
	for i in 72:
		var a := TAU * float(i) / 72.0
		ball.global_position = Vector2(960, 540) + Vector2(cos(a), sin(a)) * 330.0
		await process_frame
		frame = await _snap(frame)
	print("[ball_roll] %d frames in %s" % [frame, ProjectSettings.globalize_path(OUT)])
	quit()


func _snap(frame: int) -> int:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/f%03d.png" % [OUT, frame])
	return frame + 1
