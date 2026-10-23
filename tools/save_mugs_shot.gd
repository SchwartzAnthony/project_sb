extends SceneTree

# =============================================================
#  PHOTOGRAPH THE SAVE SCREEN'S BEER MUGS  (19 Oct 2026)
#
#      xvfb-run godot --path . --script res://tools/save_mugs_shot.gd
#
#  Opens Choose a Save, photographs it closed, then with slot 1's mug open
#  and with an empty slot's mug open: shot_mugs_closed.png,
#  shot_mugs_open.png, shot_mugs_empty_open.png in user://.
#  Runs in the TEST ENVIRONMENT, so your real save is never touched.
# =============================================================


func _initialize() -> void:
	await process_frame
	TestEnvironment.enter(self)
	ScenePaths.go_to(self, "res://src/ui/slot_screen.tscn")
	for i in 40:
		await process_frame
	await create_timer(1.0, true, false, true).timeout
	root.get_texture().get_image().save_png("user://shot_mugs_closed.png")
	var screen := current_scene
	var empty := 0
	for slot in range(1, SaveSlots.count() + 1):
		if not bool(SaveSlots.describe(slot)["used"]):
			empty = slot
	for pair in [[1, "open"], [empty, "empty_open"]]:
		if int(pair[0]) <= 0:
			continue
		screen.call("_toggle", int(pair[0]))
		for i in 20:
			await process_frame
		root.get_texture().get_image().save_png("user://shot_mugs_%s.png" % pair[1])
		screen.call("_toggle", int(pair[0]))
	TestEnvironment.leave(self)
	quit(0)
