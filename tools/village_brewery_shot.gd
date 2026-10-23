extends SceneTree

# =============================================================
#  THE VILLAGE BASE: THE CHURCH IS THE BREWERY (20 Oct 2026)
#
#  Opens the base, unlocks the Brewery, and checks the church:
#  only its own pixels take the click (not the sky or a bush), the mouse
#  over it shows it lit up, and pressing it opens the Brewery window.
#
#      xvfb-run godot --resolution 1920x1080 --script res://tools/village_brewery_shot.gd
#
#      vb_00_rest.png    the base, church at rest
#      vb_01_hover.png   the mouse on the church
#      vb_02_open.png    after pressing it
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
	for child in base.get_children():
		if child is NewUnlocksPanel:
			child.queue_free()
	base.state.unlock("Brewery")
	base.state.set_count("brewery_key", 1)
	base._rebuild()
	await create_timer(0.6, true, false, true).timeout

	var church: MapBuilding = null
	for node in _every(base):
		if node is MapBuilding and (node as MapBuilding).covered:
			church = node
	if church == null:
		print("[village] ! no village building on the base.")
		quit(1)
		return
	var bad := 0
	var used: Rect2 = church.get_meta("taken")
	var middle := used.get_center()
	var checks := {
		"the church's middle": [middle, true],
		"the sky above it": [Vector2(middle.x, used.position.y - 40.0), false],
		"the bush in front": [Vector2(used.position.x + used.size.x * 0.62, used.end.y - 10.0), false],
	}
	for what in checks:
		var at: Vector2 = checks[what][0]
		var hit := church._has_point(at)
		print("[village] %s %s takes the click: %s" % ["" if hit == checks[what][1] else "!", what, hit])
		if hit != checks[what][1]:
			bad += 1
	_shoot("vb_00_rest")
	church.emit_signal("mouse_entered")
	await create_timer(0.3, true, false, true).timeout
	_shoot("vb_01_hover")
	church.emit_signal("mouse_exited")
	church.emit_signal("pressed")
	for i in 12:
		await process_frame
	await create_timer(0.8, true, false, true).timeout
	var window: BaseWindow = null
	for child in base.get_children():
		if child is BaseWindow:
			window = child
	if window == null:
		print("[village] ! pressing the church opened NO WINDOW.")
		bad += 1
	else:
		print("[village] pressing the church opened: %s" % window.name)
		_shoot("vb_02_open")
	print("[village] %s" % ("ALL GOOD." if bad == 0 else "%d PROBLEM(S)." % bad))
	quit(0 if bad == 0 else 1)


func _shoot(shot_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	root.get_texture().get_image().save_png("user://%s.png" % shot_name)
	print("[village] %s.png" % shot_name)


func _every(from: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child in from.get_children():
		out.append(child)
		out.append_array(_every(child))
	return out
