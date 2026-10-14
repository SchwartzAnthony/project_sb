extends SceneTree

# =============================================================
#  IF THIS ELEMENT, THEN THIS BEER, PHOTOGRAPHED  (round AN, 12 Oct)
#
#      xvfb-run godot --rendering-driver opengl3 --resolution 1920x1080 \
#          --script res://tools/kettle_shot.gd
#
#      kettle_00_pick.png     the Brew Kettle asks which element goes in
#      kettle_01_bottled.png  the Water batch, bottled: six Water bottles
#
#  The save is IN MEMORY only. A tool, not part of the game.
# =============================================================


func _initialize() -> void:
	await process_frame
	change_scene_to_file("res://src/ui/brewery_screen.tscn")
	for i in 40:
		await process_frame
	await create_timer(0.8, true, false, true).timeout
	var screen := current_scene as BreweryScreen
	if screen == null:
		quit(1)
		return
	var state := screen.state
	for section in BreweryBook.sections():
		for term in String(section["needs"]).split(";", false):
			var clean := String(term).strip_edges()
			if clean.to_lower().begins_with("unlocked:"):
				state.unlock(clean.substr(clean.find(":") + 1).strip_edges())
		state.set_count(String(section["id"]) + "_key", 1)
	BreweryBook.add_stock("wort", 2, state)
	screen._rebuild()
	await create_timer(0.5, true, false, true).timeout

	screen._work("boiling")
	await create_timer(0.8, true, false, true).timeout
	_shoot("kettle_00_pick")
	var ask := _find(root, "ChoiceWindow")
	if ask != null:
		ask.queue_free()
	screen._playing = false

	# Brew it with Water, lager it, bottle it.
	BreweryBook.work("boiling", state, false, {}, "water_element")
	BreweryBook.work("cooling", state)
	for i in 4:
		BreweryBook.advance_turn(state)
	var bottled := BreweryBook.work("bottling", state, false, {"counter": "small_bottle", "many": 6})
	screen._rebuild()
	screen._say("Hanna: %d Small Bottle (%s). Each one only gives a %s beer, or one with no element."
		% [int(bottled["many"]), String(bottled["element"]).capitalize(),
		String(bottled["element"]).capitalize()], true)
	await create_timer(0.6, true, false, true).timeout
	_shoot("kettle_01_bottled")
	print("[kettle] next bottle: %s" % BreweryBook.bottle_element("small_bottle", state))
	quit(0)


func _find(node: Node, wanted: String) -> Node:
	if node.name == wanted:
		return node
	for child in node.get_children():
		var hit := _find(child, wanted)
		if hit != null:
			return hit
	return null


func _shoot(shot_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("[kettle] headless - no picture taken. Run it under xvfb-run.")
		return
	root.get_texture().get_image().save_png("user://%s.png" % shot_name)
	print("[kettle] %s.png" % shot_name)
