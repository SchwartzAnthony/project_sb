extends SceneTree

# =============================================================
#  THE MENUS AROUND THE GAME, PHOTOGRAPHED
#
#  The screens you pass through before a match ever starts: the save shelf,
#  a slot's settings window, the Are You Sure, and the Escape panel. None of
#  them is reachable from a tool without clicking, so this opens each one by
#  hand and photographs it.
#
#      xvfb-run godot --rendering-driver opengl3 --resolution 1920x1080 \
#          --script res://tools/menu_shot.gd
#
#  A tool, not part of the game. Nothing loads it.
# =============================================================

func _initialize() -> void:
	await process_frame

	# ROUND AN: in the TEST ENVIRONMENT. This used to add 14 matches to your
	# real slot 1 every time it ran.
	TestEnvironment.enter(self)

	change_scene_to_file("res://src/ui/slot_screen.tscn")
	for i in 30:
		await process_frame
	var screen := current_scene
	if screen == null:
		print("[menu] the slot screen did not open")
		quit(1)
		return
	await create_timer(0.6, true, false, true).timeout
	_shoot("n_00_slots")

	# ---- the cog ----
	if screen.has_method("_open_slot_settings"):
		screen.call("_open_slot_settings", 1, {"line": "14 matches, 1 unlock"})
		for i in 8:
			await process_frame
		_shoot("n_01_slot_settings")

		# ---- and the Are You Sure behind it ----
		var window: Node = null
		for child in screen.get_children():
			if child is CanvasLayer and child.name == "Dialog":
				window = child
		if window != null and screen.has_method("_confirm_delete"):
			screen.call("_confirm_delete", 1, window)
			for i in 8:
				await process_frame
			_shoot("n_02_are_you_sure")

	# ---- the Escape panel, on the base ----
	change_scene_to_file("res://src/ui/base_screen.tscn")
	for i in 40:
		await process_frame
	await create_timer(0.8, true, false, true).timeout
	var base := current_scene
	if base != null:
		# MenuEscape installs itself as a child of the screen, but a screen
		# that builds its chrome into a sub-node can put it deeper — so look
		# through the whole branch rather than one level.
		var escape: MenuEscape = _find_escape(base)
		if escape != null:
			escape.set("_armed", true)
			var panel = escape.get("_panel")
			if panel != null:
				panel.show()
			for i in 8:
				await process_frame
			_shoot("n_03_escape")
		else:
			print("[menu] no MenuEscape on the base screen")

	print("[menu] pictures in %s" % ProjectSettings.globalize_path("user://"))
	TestEnvironment.leave(self)
	quit(0)


func _find_escape(node: Node) -> MenuEscape:
	if node is MenuEscape:
		return node as MenuEscape
	for child in node.get_children():
		var hit := _find_escape(child)
		if hit != null:
			return hit
	return null


func _shoot(shot_name: String) -> void:
	root.get_texture().get_image().save_png("user://%s.png" % shot_name)
	print("[menu] %s.png" % shot_name)
