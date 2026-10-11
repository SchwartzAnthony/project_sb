extends SceneTree

# =============================================================
#  THE THREE CARDS, PHOTOGRAPHED
#
#  A foul happens somewhere in the middle of a match, after a draft and four
#  duels, and only some of the time. That is a long way to walk to find out
#  that the word RED CARD is running off the edge of a window — so the window
#  is opened here on its own, with the three captions it can ever show, and
#  each one is saved.
#
#      xvfb-run godot --rendering-driver opengl3 --resolution 1920x1080 \
#          --script res://tools/foul_shot.gd
#
#  It is the SAME window the goal celebration and the throw-in use — see
#  anim_window.gd — so what you see here is exactly what the match shows.
#
#  A tool, not part of the game. Nothing loads it.
# =============================================================

const SHOTS: Array = [
	["fl_00_free_kick", "FREE KICK — Müller"],
	["fl_01_yellow", "YELLOW CARD — Schwarzhammer"],
	["fl_02_red", "RED CARD — Bischoff"],
	["fl_03_second", "SECOND YELLOW — Schröder"],
]


func _initialize() -> void:
	await process_frame
	# An empty scene with the game's skin on it. The window draws its own
	# frame from the `window` row of Theme.csv, so there is nothing else the
	# picture needs.
	var stage := Control.new()
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var behind := ColorRect.new()
	behind.color = Color(0.10, 0.22, 0.10)     # grass, roughly
	behind.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(behind)
	root.add_child(stage)
	ThemeBook.dress(self)

	var db := CardDatabase.get_db()
	for i in 20:
		await process_frame

	for shot in SHOTS:
		var window := AnimWindow.open(stage, db, 150)
		for i in 3:
			await process_frame
		# ROUND AN: a real Club card, so the window shows its pitch figure.
		var who: PlayerData = null
		for card in db.players:
			if card.unit_type == "Normal":
				who = card
				break
		window.show_panel(String(shot[1]), "", "lose", who, ["lose", "idle"])
		await create_timer(0.6, true, false, true).timeout
		_shoot(String(shot[0]))
		window.close()
		await create_timer(0.2, true, false, true).timeout

	print("[fouls] pictures in %s" % ProjectSettings.globalize_path("user://"))
	quit(0)


func _shoot(shot_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("[fouls] headless — no picture taken. Run it under xvfb-run.")
		return
	root.get_texture().get_image().save_png("user://%s.png" % shot_name)
	print("[fouls] %s.png" % shot_name)
