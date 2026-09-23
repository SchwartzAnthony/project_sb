extends SceneTree

# =============================================================
#  THE BREWERY MAP, PHOTOGRAPHED — LOCKED, OPEN, AND WORKING
#
#  Getting to a Brewery with all six sections open is ten matches away in a
#  real game, which is a long walk to find out that the Bottling bench is off
#  the bottom of the yard.
#
#      xvfb-run godot --rendering-driver opengl3 --resolution 1920x1080 \
#          --script res://tools/brewery_shot.gd
#
#      bw_00_locked.png    a new save: the Malthouse open, five locked
#      bw_01_open.png      every section unlocked, the opening stock in
#      bw_02_worked.png    the chain run once, a barrel lagering in the cellar
#
#  It works on the save IN MEMORY only — nothing is written to disk, so
#  running it does not spend your real materials.
#
#  A tool, not part of the game. Nothing loads it.
# =============================================================


func _initialize() -> void:
	await process_frame
	change_scene_to_file("res://src/ui/brewery_screen.tscn")
	for i in 40:
		await process_frame
	await create_timer(0.8, true, false, true).timeout

	var screen := current_scene as BreweryScreen
	if screen == null:
		print("[brewery] the screen did not open.")
		quit(1)
		return

	# ---- a new save: only what an achievement has opened so far ----
	screen.state.unlock("Malthouse")
	screen._rebuild()
	await create_timer(0.5, true, false, true).timeout
	_shoot("bw_00_locked")

	# ---- every section open ----
	for section in BreweryBook.sections():
		for term in String(section["needs"]).split(";", false):
			var clean := String(term).strip_edges()
			if clean.to_lower().begins_with("unlocked:"):
				screen.state.unlock(clean.substr(clean.find(":") + 1).strip_edges())
	screen._rebuild()
	await create_timer(0.5, true, false, true).timeout
	_shoot("bw_01_open")

	# ---- run the chain once, so the cellar has something in it ----
	for section in BreweryBook.sections():
		var id_text := String(section["id"])
		if BreweryBook.can_work(id_text, screen.state):
			var result := BreweryBook.work(id_text, screen.state)
			print("[brewery] %-22s %s" % [section["name"],
				"lagering" if bool(result["waiting"]) else "done"])
	screen._rebuild()
	await create_timer(0.5, true, false, true).timeout
	_shoot("bw_02_worked")

	print("[brewery] pictures in %s" % ProjectSettings.globalize_path("user://"))
	quit(0)


func _shoot(shot_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("[brewery] headless — no picture taken. Run it under xvfb-run.")
		return
	root.get_texture().get_image().save_png("user://%s.png" % shot_name)
	print("[brewery] %s.png" % shot_name)
