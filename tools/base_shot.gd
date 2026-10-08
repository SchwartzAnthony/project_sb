extends SceneTree

# =============================================================
#  THE BASE, AND EVERY WINDOW — OPENED BY PRESSING THE BUTTON
#
#  ============ WHY THIS TOOL WAS WRONG, AND IS NOW RIGHT ============
#
#  It used to call BaseWindow.open() itself. Every picture came out perfect
#  and the game was broken: a building's Action said `window:brewery`, that
#  term was quietly dropped on its way through the effects language, and
#  clicking a building showed its description and did nothing else.
#
#  A tool that reaches past the button cannot see a broken button. So this
#  one PRESSES THE REAL BUTTON — it finds the building's plaque on the base
#  by its name and emits `pressed`, exactly as a player's mouse would — and
#  then checks that a window actually appeared. If none did, it says which
#  building and carries on.
#
#      xvfb-run godot --rendering-driver opengl3 --resolution 1920x1080 \
#          --script res://tools/base_shot.gd
#
#      bs_00_base.png      the doors on the town map, some locked
#      bs_01_open.png      everything unlocked, and the visitors placed
#      bs_02..             one shot per window, each opened by its own button
#                          (the buildings, then the top-bar doors)
#
#  It works on the save IN MEMORY only — nothing is written to disk.
#
#  A tool, not part of the game. Nothing loads it.
# =============================================================

## Which window to photograph, and what the base calls it.
## The buildings to press, by the Name in Buildings.csv, plus the Stadium,
## which is a button on the top bar rather than a building.
const DOORS: Array[String] = [
	"Club House", "Dorms", "Trophy Room",
	"Training Ground", "Pub", "Brewery", "The Traveling Tavern",
]

## Doors on the top bar, by their words. `a|b` = either (the Achievements
## button says Erfolge in German). Round AN moved Achievements and Team Build
## off the town map and up here.
const BAR_DOORS: Array[String] = ["The stadium", "Your teams", "Erfolge|Achievements"]


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
	var broken := 0
	for who in DOORS:
		var button := _plaque_named(base, who)
		if button == null:
			print("[base] ! no plaque called '%s' on the base." % who)
			broken += 1
			continue

		# ============ PRESS IT, DO NOT REACH PAST IT ============
		button.emit_signal("pressed")
		for i in 12:
			await process_frame
		await create_timer(0.7, true, false, true).timeout

		var window := _open_window(base)
		if window == null:
			print("[base] ! pressing '%s' opened NO WINDOW. Check its Action column." % who)
			broken += 1
			continue
		_shoot("bs_%02d_%s" % [at, who.to_lower().replace(" ", "_")])
		window.close()
		await create_timer(0.2, true, false, true).timeout
		at += 1

	# ---- and the top-bar doors ----
	for words in BAR_DOORS:
		var door: Button = null
		for word in words.split("|"):
			door = _bar_button_named(base, word)
			if door != null:
				break
		if door == null:
			print("[base] ! no '%s' button on the top bar." % words)
			broken += 1
			continue
		door.emit_signal("pressed")
		for i in 12:
			await process_frame
		await create_timer(0.7, true, false, true).timeout
		var window := _open_window(base)
		if window == null:
			print("[base] ! the '%s' button opened NO WINDOW." % words)
			broken += 1
			continue
		_shoot("bs_%02d_%s" % [at, words.split("|")[0].to_lower().replace(" ", "_")])
		window.close()
		await create_timer(0.2, true, false, true).timeout
		at += 1

	print("")
	if broken == 0:
		print("[base] EVERY DOOR OPENED A WINDOW WHEN PRESSED.")
	else:
		print("[base] %d DOOR(S) DID NOT OPEN. See above." % broken)

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


## The building plaque whose label says this. Buildings are Buttons with a
## VBox of a picture and a Label inside them — so the search is for the
## label's text, which is what a player reads.
func _plaque_named(base: Node, who: String) -> Button:
	for node in _every(base):
		var button := node as Button
		if button == null:
			continue
		for label in _every(button):
			var text := label as Label
			if text != null and text.text.strip_edges().begins_with(who):
				return button
	return null


## A button on the top bar. Those are made by MenuSupport.icon_button(), so
## their words are in a Label too — but they are not plaques, so the search
## is the same and the caller says which it wanted.
func _bar_button_named(base: Node, who: String) -> Button:
	return _plaque_named(base, who)


## The window that is open over the base, or null.
func _open_window(base: Node) -> BaseWindow:
	for child in base.get_children():
		if child is BaseWindow:
			return child
	return null


func _every(from: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child in from.get_children():
		out.append(child)
		out.append_array(_every(child))
	return out
