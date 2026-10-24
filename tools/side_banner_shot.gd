extends SceneTree

# =============================================================
#  THE ATTACKING / DEFENDING FLAG, PHOTOGRAPHED (24 Oct 2026)
#
#  The flag strip and the big call, both sides, on the drawn village, with
#  nothing else on screen.
#
#      xvfb-run godot --rendering-driver opengl3 --resolution 1920x1080 \
#          --script res://tools/side_banner_shot.gd
#
#  Pictures land in user:// as flag_attacking.png, flag_defending.png,
#  flag_call_attacking.png and flag_call_defending.png.
#  A tool, not part of the game. Nothing loads it.
# =============================================================

func _initialize() -> void:
	await process_frame
	ThemeBook.dress(self)
	var stage := Node2D.new()
	root.add_child(stage)
	var back := TextureRect.new()
	back.texture = load("res://assets/field/match_ground_village.png")
	back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	back.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	back.size = Vector2(1920, 1080)
	stage.add_child(back)
	for side in [true, false]:
		var banner := SideBanner.make(stage)
		banner.set_side(side)
		banner.set_tier("II")
		banner.show_it()
		for i in 6:
			await process_frame
		_shoot("flag_%s" % ("attacking" if side else "defending"))
		var word := "YOU ARE ATTACKING" if side else "YOU ARE DEFENDING"
		banner.hide_it()
		banner.call_out(side, word, 0.6)
		for i in 25:
			await process_frame
		_shoot("flag_call_%s" % ("attacking" if side else "defending"))
		await create_timer(0.7).timeout
	quit(0)


func _shoot(shot_name: String) -> void:
	root.get_texture().get_image().save_png("user://%s.png" % shot_name)
	print("[flag] %s.png" % shot_name)
