extends SceneTree

# =============================================================
#  THE STAR HALL, PHOTOGRAPHED — EMPTY, THEN FILLED
#
#  The class tree is three screens in one: nothing placed, some placed, and
#  the emblem choice that only appears when all three nodes are full. Getting
#  to the third one in a real game is eight matches away, which is a long
#  walk to find out that a column is running off the bottom.
#
#      xvfb-run godot --rendering-driver opengl3 --resolution 1920x1080 \
#          --script res://tools/class_tree_shot.gd
#
#      ct_00_empty.png    a new save: three empty plinths per class
#      ct_01_picking.png  the Star picker open inside a node
#      ct_02_filled.png   every node full, the emblems offered, the spirit
#                         ready to forge
#
#  It writes to the SAVE IN MEMORY only — nothing is written to disk, so
#  running it does not spend your real talent points.
#
#  A tool, not part of the game. Nothing loads it.
# =============================================================


func _initialize() -> void:
	await process_frame
	change_scene_to_file("res://src/ui/class_tree_screen.tscn")
	for i in 40:
		await process_frame
	await create_timer(0.8, true, false, true).timeout

	var screen := current_scene as ClassTreeScreen
	if screen == null:
		print("[class tree] the screen did not open.")
		quit(1)
		return

	# ---- a clean board, and enough points to spend ----
	screen.state.set_count(ClassTree.POINTS, 40)
	screen._rebuild()
	await create_timer(0.5, true, false, true).timeout
	_shoot("ct_00_empty")

	# ---- the picker, open inside the first node of the first class ----
	var who := _first_class()
	if who != "":
		var nodes := ClassTree.nodes_for(who, screen.state)
		if not nodes.is_empty():
			screen._open_picker(who, String(nodes[0]["set_id"]))
			await create_timer(0.5, true, false, true).timeout
			_shoot("ct_01_picking")

	# ---- fill everything, choose an emblem, forge the spirit ----
	var db := CardDatabase.get_db()
	for key in ClassBook.classes():
		var entry: ClassBook.ClassEntry = ClassBook.classes()[key]
		if entry.stars.is_empty() or entry.sets.is_empty():
			continue
		for node in ClassTree.nodes_for(entry.unit_type, screen.state):
			var taken := ClassTree.stars_placed(entry.unit_type, screen.state)
			for star in ClassTree.stars_you_own(entry.unit_type, screen.state, db):
				if taken.has(ClassTree.star_key(star)):
					continue
				ClassTree.place_star(entry.unit_type, String(node["set_id"]),
					star, screen.state, db)
				break
	screen._rebuild()
	await create_timer(0.6, true, false, true).timeout
	_shoot("ct_02_filled")

	print("[class tree] pictures in %s" % ProjectSettings.globalize_path("user://"))
	quit(0)


func _first_class() -> String:
	for key in ClassBook.classes():
		var entry: ClassBook.ClassEntry = ClassBook.classes()[key]
		if not entry.stars.is_empty() and not entry.sets.is_empty():
			return entry.unit_type
	return ""


func _shoot(shot_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("[class tree] headless — no picture taken. Run it under xvfb-run.")
		return
	root.get_texture().get_image().save_png("user://%s.png" % shot_name)
	print("[class tree] %s.png" % shot_name)
