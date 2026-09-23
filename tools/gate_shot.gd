extends SceneTree

# =============================================================
#  THE CLASS TREE'S GATE, ON AND OFF, SIDE BY SIDE
#
#  `class_tree_gates_units` in Tuning.csv is FALSE out of the box: an emblem
#  set's nine units are yours whether or not a Star stands in its node. The
#  day you turn it on is the day the team builder changes shape, and that is
#  a big enough change to want to see before a player does.
#
#      xvfb-run godot --rendering-driver opengl3 --resolution 1920x1080 \
#          --script res://tools/gate_shot.gd
#
#      tb_00_gate_off.png   the collection as it is today
#      tb_01_gate_on.png    the same screen with the gate forced on and no
#                           Star placed — which is what a new game looks like
#
#  It forces the switch IN MEMORY for the length of one screenshot. Nothing
#  is written to Tuning.csv and nothing is written to your save.
#
#  ============ WHAT IT ALREADY CAUGHT ============
#
#  Two things, both invisible while the gate was off. The gate silently did
#  nothing, because it handed a plain Array to a variable typed
#  Array[PlayerData] and Godot refuses that at runtime. And the "nothing in
#  the collection" note came out as a single column of one letter per line,
#  because a wrapping Label inside a GridContainer reports a minimum width of
#  one character. Neither is the kind of thing a parse check can see.
#
#  A tool, not part of the game. Nothing loads it.
# =============================================================

const CLASS_TO_SHOW := "Lorelei"


func _initialize() -> void:
	await process_frame
	var db := CardDatabase.get_db()

	var pick := TeamSelection.new()
	pick.unit_type = CLASS_TO_SHOW
	var entry := ClassBook.entry_for(CLASS_TO_SHOW)
	pick.star_tier = entry.star_tier if entry != null else "IV"
	TeamSelection.store(self, pick)

	change_scene_to_file("res://src/ui/team_builder.tscn")
	for i in 40:
		await process_frame
	await create_timer(0.8, true, false, true).timeout

	var screen := current_scene
	if screen == null:
		print("[gate] the team builder did not open.")
		quit(1)
		return

	print("[gate] OFF: %d card(s) in the collection." % screen._library.size())
	_shoot("tb_00_gate_off")

	# ---- forced on, in memory only ----
	db.tuning[CardDatabase._normalise("class_tree_gates_units")] = "true"
	screen._load_library()
	screen._chosen = {}
	screen._auto_fill()
	screen._refresh()
	await create_timer(0.6, true, false, true).timeout

	print("[gate] ON : %d card(s) in the collection." % screen._library.size())
	print("[gate] the screen says: %s" % screen._status.text)
	_shoot("tb_01_gate_on")

	print("[gate] pictures in %s" % ProjectSettings.globalize_path("user://"))
	quit(0)


func _shoot(shot_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("[gate] headless — no picture taken. Run it under xvfb-run.")
		return
	root.get_texture().get_image().save_png("user://%s.png" % shot_name)
	print("[gate] %s.png" % shot_name)
