extends SceneTree

# =============================================================
#  THE BASE, AND EVERY WINDOW THAT OPENS OVER IT
#
#  Nine buildings, five of them opening screens that used to be whole scenes.
#  The thing worth photographing is that the base is STILL THERE behind each
#  one — dimmed, with the building you clicked still under your cursor.
#
#      xvfb-run godot --rendering-driver opengl3 --resolution 1920x1080 \
#          --script res://tools/base_shot.gd
#
#      bs_00_base.png      the nine doors, some locked
#      bs_01_open.png      everything unlocked, and the visitors placed
#      bs_02..bs_10        one shot per window
#
#  It works on the save IN MEMORY only — nothing is written to disk.
#
#  A tool, not part of the game. Nothing loads it.
# =============================================================

## Which window to photograph, and what the base calls it.
const WINDOWS: Array = [
	["achievements", "Achievements"],
	["talents", "Talent Tree"],
	["clubhouse", "Club House"],
	["dorms", "Dorms"],
	["trophies", "Trophy Room"],
	["training", "Training Ground"],
	["pub", "Pub"],
	["brewery", "Brewery"],
	["brewer", "The Traveling Brewer"],
]


func _initialize() -> void:
	await process_frame
	change_scene_to_file("res://src/ui/base_screen.tscn")
	for i in 40:
		await process_frame
	await create_timer(0.8, true, false, true).timeout

	var base := current_scene
	if base == null:
		print("[base] the base did not open.")
		quit(1)
		return

	# THE "NEW AT THE BASE" PANEL comes up over a fresh save and dims
	# everything behind it. Dismiss it, or every picture is of that panel.
	_dismiss_panels(base)
	await create_timer(0.4, true, false, true).timeout

	print("[base] %d building(s) on the map." % BaseDB.get_db().buildings_for(base.state).size())
	_shoot("bs_00_base")

	# ---- open every door, and give the purse something in it ----
	for entry in BaseDB.get_db().buildings.duplicate():
		for term in String(entry["requires"]).split(";", false):
			var clean := String(term).strip_edges()
			if clean.to_lower().begins_with("unlocked:"):
				base.state.unlock(clean.substr(clean.find(":") + 1).strip_edges())
	for money in ShopBook.currencies():
		base.state.set_count(String(money["counter"]), 600)
	base.state.set_count(ClassTree.POINTS, 20)
	base._rebuild()
	_dismiss_panels(base)
	await create_timer(0.6, true, false, true).timeout
	_shoot("bs_01_open")

	var at := 2
	for pair in WINDOWS:
		var word := String(pair[0])
		var title := String(pair[1])
		var window := BaseWindow.open(base, title, ScenePaths.for_name(word))
		if window == null:
			print("[base] %s did not open." % word)
			continue
		for i in 12:
			await process_frame
		await create_timer(0.7, true, false, true).timeout
		_shoot("bs_%02d_%s" % [at, word])
		window.close()
		await create_timer(0.2, true, false, true).timeout
		at += 1

	print("[base] pictures in %s" % ProjectSettings.globalize_path("user://"))
	quit(0)


func _shoot(shot_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("[base] headless — no picture taken. Run it under xvfb-run.")
		return
	root.get_texture().get_image().save_png("user://%s.png" % shot_name)
	print("[base] %s.png" % shot_name)


func _dismiss_panels(base: Node) -> void:
	for child in base.get_children():
		if child is NewUnlocksPanel:
			child.queue_free()
