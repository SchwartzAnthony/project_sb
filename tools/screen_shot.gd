extends SceneTree

# =============================================================
#  SCREENSHOTS OF THE NEW WINDOWS
#
#  The Inventory and the Edit Element Bonus picker are both popups that live
#  several clicks inside other screens, so this opens each one on its own,
#  puts something in it, and photographs it.
#
#      xvfb-run godot --rendering-driver opengl3 --resolution 1920x1080 \
#          --script res://tools/screen_shot.gd
#
#  A tool, not part of the game. Nothing loads it.
# =============================================================

var _shot := 0


func _initialize() -> void:
	await process_frame
	var db := CardDatabase.get_db()
	AdventureDB.get_db()
	TraitDB.get_db()

	# A SAVE WITH SOMETHING IN IT. An empty bag photographs as an empty box,
	# which tells you nothing about how a full one lays out.
	var state := GameState.new()
	for pair in [["reed", 34], ["bog_iron", 12], ["ash_glass", 7],
			["deep_salt", 3], ["coins", 250], ["smelling_salts", 2],
			["field_bandage", 4], ["team_orange", 1], ["throwing_stone", 6],
			["recipe_marsh_ale", 1], ["marsh_key", 1]]:
		state.add_count(String(pair[0]), int(pair[1]))
	state.unlock("Fire Brew")
	state.unlock("Water Brew")

	var holder := Node.new()
	root.add_child(holder)

	# ---- the bag, as the base opens it ----
	var bag := InventoryScreen.open(holder, state, InventoryScreen.Use.NOTHING)
	await _settle()
	_snap("bag-items")
	bag._show_tab("resources")
	await _settle()
	_snap("bag-resources")
	bag._show_tab("keys")
	await _settle()
	_snap("bag-keys")
	bag.close()
	await _settle()

	# ---- the bag, as the draft opens it: brews, clickable ----
	var pour := InventoryScreen.open(holder, state, InventoryScreen.Use.ON_CARD,
		"Pouring on Silver-Rhine Lorelei. It wears off at the final whistle.")
	await _settle()
	_snap("bag-on-card")
	pour.close()
	await _settle()

	# ---- which eight icons go into a run ----
	var picker := TraitLoadoutScreen.open(holder, state, db)
	await _settle()
	_snap("element-bonus")

	picker.queue_free()
	await _settle()

	# ---- a draft card, with the flask in its corner ----
	var sheet := Control.new()
	sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(sheet)
	var back := ColorRect.new()
	back.color = MenuSupport.COLOUR_BACKGROUND
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sheet.add_child(back)

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_CENTER)
	row.add_theme_constant_override("separation", 18)
	sheet.add_child(row)
	var shown := 0
	for card in db.players:
		if shown >= 4:
			break
		var face := preload("res://src/ui/player_card_ui.tscn").instantiate() as PlayerCardUI
		row.add_child(face)
		face.setup_card(card)
		shown += 1
	await _settle()
	_snap("draft-cards")

	print("[screens] done")
	quit(0)


func _settle() -> void:
	for i in 4:
		await process_frame
	await create_timer(0.25, true, false, true).timeout


func _snap(label: String) -> void:
	var view := root.get_viewport()
	if view == null:
		return
	var picture := view.get_texture().get_image()
	if picture == null:
		return
	var path := "user://s_%02d_%s.png" % [_shot, label]
	_shot += 1
	picture.save_png(path)
	print("[screens] %s" % path.get_file())
