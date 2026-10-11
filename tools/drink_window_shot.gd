extends SceneTree

# =============================================================
#  THE DRINKING WINDOW ON ITS OWN  (round AN, 11 Oct)
#
#  Opens DrinkWindow (src/ui/drink_window.gd) for a Club player over a
#  blank screen and saves it every tenth of a second, so you can see the
#  PixelLab stein drink and the burp without playing the tutorial.
#
#      godot --path . --resolution 1920x1080 --script res://tools/drink_window_shot.gd
#
#  Frames land in user://drink_window_shot/. DRINK_WINDOW_WHO picks a card
#  by name (default: the first Club card), DRINK_WINDOW_KIND barrel or
#  bottle. A tool, not part of the game.
# =============================================================

var _shot := 0


func _initialize() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://drink_window_shot"))
	var db := CardDatabase.get_db()
	var roster := db.roster_for_class("Normal")
	var who: PlayerData = null
	var wanted := OS.get_environment("DRINK_WINDOW_WHO")
	for card in roster:
		if wanted == "" or card.player_name == wanted:
			who = card
			break
	if who == null:
		print("[drink_window_shot] no card")
		quit(1)
		return
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(host)
	var back := ColorRect.new()
	back.color = Color(0.25, 0.45, 0.25)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.add_child(back)
	var kind := OS.get_environment("DRINK_WINDOW_KIND")
	var window = DrinkWindow.play(host, who, kind if kind != "" else "barrel")
	print("[drink_window_shot] %s, pitch drink: %s" % [who.player_name, window.get("_pitch") != null])
	var done := [false]
	window.finished.connect(func() -> void: done[0] = true)
	for i in 80:
		await create_timer(0.1, true, false, true).timeout
		await process_frame
		root.get_viewport().get_texture().get_image().save_png(
			"user://drink_window_shot/f_%03d.png" % _shot)
		_shot += 1
		if done[0]:
			break
	print("[drink_window_shot] done, %d frames, finished=%s" % [_shot, done[0]])
	quit(0)
