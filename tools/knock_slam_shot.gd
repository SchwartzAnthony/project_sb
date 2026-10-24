extends SceneTree

# =============================================================
#  THE THREE KNOCK-AWAY SLAMS, PHOTOGRAPHED (Anthony, 24 Oct 2026)
#
#  Three made-up duels won by 1, 3 and 5: a SMALL, a LARGE and a MEGA slam
#  (duel_knock_large_from / duel_knock_mega_from in Tuning.csv). The duel
#  itself is fast-forwarded; only the knock-away is photographed, every
#  1/20 s, over the drawn village pitch so the MEGA screen shake shows.
#
#      xvfb-run godot --rendering-driver opengl3 --resolution 1920x1080 \
#          --script res://tools/knock_slam_shot.gd
#
#  Pictures land in user://knock/ as <size>_NNNNN.png (frame number). For
#  smooth timing add --fixed-fps 20 --write-movie /tmp/knock.png -- film
#  and cut the frames the [knock] lines print.
#  A tool, not part of the game. Nothing loads it.
# =============================================================



func _initialize() -> void:
	await process_frame
	var db := CardDatabase.get_db()
	# `-- film` with --write-movie: the movie is the record, no pictures.
	var film := OS.get_cmdline_user_args().has("film")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://knock"))

	# The pitch behind, on the world canvas, as in a match.
	var ground := Sprite2D.new()
	ground.centered = false
	var path := db.tune_text("pitch_background_shot", "res://assets/field/match_ground_village.png")
	if ResourceLoader.exists(path):
		ground.texture = load(path)
		var size := ground.texture.get_size()
		ground.scale = Vector2.ONE * maxf(1920.0 / size.x, 1080.0 / size.y)
	root.add_child(ground)

	var cards: Array = []
	for card in db.players:
		if card.get_tier_clean() == "III" and cards.size() < 2:
			cards.append(card)
	var arena = load("res://src/ui/duel_arena.tscn").instantiate()
	root.add_child(arena)
	arena.db = db
	arena.apply_tuning(db)
	await process_frame

	for margin in [1, 3, 5]:
		var slam: String = arena.knock_size(margin)
		var left := {"card": cards[0], "is_attacker": true, "priority": 0,
			"power_before": 4, "power_after": 4 + margin, "printed": 4,
			"ability": null, "fired": false, "wins": true}
		var right := {"card": cards[1], "is_attacker": false, "priority": 9,
			"power_before": 4, "power_after": 4, "printed": 4,
			"ability": null, "fired": false, "wins": false}
		arena.speed = 12.0
		arena.play_duel({"tier": "III", "left": left, "right": right})
		var start := -1
		while arena.is_running():
			await process_frame
			var winner: Control = arena._side_panel("left")
			if start < 0 and winner != null and winner.z_index == 1:
				arena.speed = 1.0
				start = Engine.get_frames_drawn()
			if not film and start >= 0:
				root.get_texture().get_image().save_png("user://knock/%s_%05d.png" % [slam, Engine.get_frames_drawn() - start])
		var n := Engine.get_frames_drawn() - start
		print("[knock] frames %d %d %s" % [start, start + n, slam])
		print("[knock] won by %d = %s, %d pictures" % [margin, slam, n])
		await create_timer(0.3, true, false, true).timeout
	print("[knock] in %s" % ProjectSettings.globalize_path("user://knock"))
	quit(0)
