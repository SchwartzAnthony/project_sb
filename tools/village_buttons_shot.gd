extends SceneTree

# =============================================================
#  THE VILLAGE BASE BUTTONS (23 Oct 2026)
#
#  The drawn Pub, the Dorms and the pitch are buttons in the village picture, like the
#  brewery church. Checks: no Play a match flag on the top row, the Pub and
#  the pitch light up under the mouse, and pressing the pitch opens the
#  Match Maker.
#
#      xvfb-run godot --resolution 1920x1080 --script res://tools/village_buttons_shot.gd
#
#      vbb_00_rest.png    the base at rest
#      vbb_01_pub.png     the mouse on the Pub
#      vbb_02_field.png   the mouse on the pitch
#      vbb_04_dorms.png   the mouse on the Dorms
#      vbb_03_pressed.png after pressing the pitch
#
#  Works on the save in memory only. A tool, not part of the game.
# =============================================================


func _initialize() -> void:
	await process_frame
	change_scene_to_file("res://src/ui/base_screen.tscn")
	for i in 40:
		await process_frame
	await create_timer(0.8, true, false, true).timeout
	var base := current_scene
	for node in _every(root):
		if node is Label and String((node as Label).text).contains("Tutorial?"):
			var top: Node = node
			while top.get_parent() != base and top.get_parent() != root:
				top = top.get_parent()
			if top != base:
				top.queue_free()
	for child in base.get_children():
		if child is NewUnlocksPanel:
			child.queue_free()
	base.state.unlock("Pub")
	base.state.set_count("pub_key", 1)
	base.state.unlock("Dorms")
	base.state.set_count("dorms_key", 1)
	base._rebuild()
	await create_timer(0.6, true, false, true).timeout

	var bad := 0
	for node in _every(base):
		if node is Button and String((node as Button).text) == "Play a match":
			print("[buttons] ! the Play a match flag is still on the top row.")
			bad += 1
	var pub: MapBuilding = _village(base, "Pub")
	var field: MapBuilding = _village(base, "Play a match")
	var dorms: MapBuilding = _village(base, "Dorms")
	if pub == null or field == null or dorms == null:
		print("[buttons] ! missing: pub %s, field %s, dorms %s" % [pub != null, field != null, dorms != null])
		quit(1)
		return
	_shoot("vbb_00_rest")
	pub.emit_signal("mouse_entered")
	await create_timer(0.3, true, false, true).timeout
	_shoot("vbb_01_pub")
	pub.emit_signal("mouse_exited")
	field.emit_signal("mouse_entered")
	await create_timer(0.3, true, false, true).timeout
	_shoot("vbb_02_field")
	field.emit_signal("mouse_exited")
	dorms.emit_signal("mouse_entered")
	await create_timer(0.3, true, false, true).timeout
	_shoot("vbb_04_dorms")
	dorms.emit_signal("mouse_exited")
	await create_timer(0.2, true, false, true).timeout
	field.emit_signal("pressed")
	for i in 12:
		await process_frame
	await create_timer(0.8, true, false, true).timeout
	_shoot("vbb_03_pressed")
	var opened := false
	for node in _every(root):
		if node.name == "MatchMaker":
			opened = true
	print("[buttons] pressing the pitch opened the Match Maker: %s" % opened)
	if not opened and current_scene == base:
		bad += 1
	print("[buttons] %s" % ("ALL GOOD." if bad == 0 else "%d PROBLEM(S)." % bad))
	quit(0 if bad == 0 else 1)


func _village(base: Node, name_text: String) -> MapBuilding:
	for node in _every(base):
		if node is MapBuilding and (node as MapBuilding).covered:
			for child in node.get_children():
				if child is Label and String((child as Label).text).begins_with(name_text):
					return node
	return null


func _shoot(shot_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	root.get_texture().get_image().save_png("user://%s.png" % shot_name)
	print("[buttons] %s.png" % shot_name)


func _every(from: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child in from.get_children():
		out.append(child)
		out.append_array(_every(child))
	return out
