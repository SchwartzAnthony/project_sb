extends SceneTree

# =============================================================
#  THE CONQUESTS BANNER, PRESSED  (Conquests placeholder)
#
#      xvfb-run godot --rendering-driver opengl3 --resolution 1920x1080 \
#          --script res://tools/conquests_shot.gd
#
#      cq_00_base.png    the top row with the torn Conquests banner on it
#      cq_01_soon.png    the coming-soon note it opens
#
#  Presses the real banner, then checks a note actually came up. Works on
#  the save in memory only. A tool, not part of the game.
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
	await create_timer(2.5, true, false, true).timeout
	_shoot("cq_00_base")

	var banner: Button = null
	for node in _every(base):
		if node is Label and (node as Label).text == Loc.text("conquests_button", "Conquests"):
			banner = node.get_parent() as Button
	if banner == null:
		print("[conquests] ! no Conquests banner on the top row.")
		quit(1)
		return
	banner.emit_signal("pressed")
	for i in 12:
		await process_frame
	await create_timer(0.5, true, false, true).timeout
	if base.get_node_or_null("Dialog") == null:
		print("[conquests] ! the banner opened nothing.")
		quit(1)
		return
	_shoot("cq_01_soon")
	print("[conquests] THE BANNER OPENS ITS COMING-SOON NOTE.")
	quit(0)


func _shoot(shot_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("[conquests] headless - no picture taken. Run it under xvfb-run.")
		return
	root.get_texture().get_image().save_png("user://%s.png" % shot_name)
	print("[conquests] %s.png" % shot_name)


func _every(from: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child in from.get_children():
		out.append(child)
		out.append_array(_every(child))
	return out
