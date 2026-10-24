extends SceneTree

# =============================================================
#  SCREENSHOT: THE INVENTORY INFO BOX SCROLLS
#
#  Opens the bag as a match opens it, points at the Kleiner Faß (the longest
#  description), photographs the top of the words, scrolls down and
#  photographs again.
#
#      xvfb-run godot --rendering-driver opengl3 --resolution 1920x1080 \
#          --script res://tools/info_scroll_shot.gd
#
#  A tool, not part of the game. Nothing loads it.
# =============================================================


func _initialize() -> void:
	await process_frame
	CardDatabase.get_db()
	AdventureDB.get_db()
	var state := GameState.new()
	for pair in [["keg", 1], ["small_bottle", 3], ["water_element", 1]]:
		state.add_count(String(pair[0]), int(pair[1]))
	var holder := Node.new()
	root.add_child(holder)
	var bag := InventoryScreen.open(holder, state, InventoryScreen.Use.ON_CARD,
		"Using something on Koch. It wears off at the final whistle.")
	await _settle()
	var tile := bag.tile_for("keg")
	if tile != null:
		tile.mouse_entered.emit()
	await _settle()
	_snap("info_top")
	var bar := bag._words_scroll.get_v_scroll_bar()
	print("[info] words %d px tall, box %d px, can scroll %s" % [
		bag._words.size.y, bag._words_scroll.size.y, bar.max_value > bar.page])
	bag._words_scroll.scroll_vertical = int(bar.max_value)
	await _settle()
	_snap("info_bottom")
	quit()


func _settle() -> void:
	for i in 4:
		await process_frame
	await create_timer(0.25, true, false, true).timeout


func _snap(label: String) -> void:
	var picture := root.get_viewport().get_texture().get_image()
	var path := "user://%s.png" % label
	picture.save_png(path)
	print("[info] %s" % ProjectSettings.globalize_path(path))
