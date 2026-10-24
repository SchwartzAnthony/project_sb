extends SceneTree

# =============================================================
#  EVERY BUILDING WINDOW'S NAME SIGN (24 Oct 2026)
#
#  Opens the base and each building window in turn, and the Brewery on its
#  own (the Tutorial's way in), so their name signs can be compared.
#
#      xvfb-run godot --resolution 1920x1080 --script res://tools/building_signs_shot.gd
#
#      bs_<word>.png        each building's window over the base
#      bs_brewery_full.png  the Brewery as a whole screen
#
#  Works on the save in memory only. A tool, not part of the game.
# =============================================================

const WORDS := ["pub", "dorms", "brewery", "clubhouse", "training", "trophies"]


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
	for word in ["Brewery", "Pub", "Dorms", "Club House", "Training Ground", "Trophy Room"]:
		base.state.unlock(word)
	for key in ["brewery_key", "pub_key", "dorms_key", "club_house_key", "training_key", "trophy_room_key"]:
		base.state.set_count(key, 1)
	base._rebuild()
	await create_timer(0.8, true, false, true).timeout
	_shoot("bs_base")
	for word in WORDS:
		var path := ScenePaths.for_name(word)
		if path == "":
			continue
		var opened := BaseWindow.open(base, base._window_title(word), path)
		for i in 12:
			await process_frame
		await create_timer(0.8, true, false, true).timeout
		if opened != null:
			_shoot("bs_" + word)
			opened.close()
		await create_timer(0.4, true, false, true).timeout
	change_scene_to_file("res://src/ui/brewery_screen.tscn")
	for i in 40:
		await process_frame
	await create_timer(0.8, true, false, true).timeout
	_shoot("bs_brewery_full")
	quit(0)
func _shoot(shot_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	root.get_texture().get_image().save_png("user://%s.png" % shot_name)
	print("[signs] %s.png" % shot_name)


func _every(from: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child in from.get_children():
		out.append(child)
		out.append_array(_every(child))
	return out
