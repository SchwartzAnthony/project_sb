extends SceneTree

# =============================================================
#  THE SKIN, BEFORE AND AFTER
#
#  The hard part of Theme.csv is not writing it, it is believing it. A row
#  saying `panel_soft` either changes every box in the game or it changes
#  nothing, and a spreadsheet cannot show you which.
#
#  So this photographs the same screen twice:
#
#      th_00_flat.png     as Theme.csv is written right now
#      th_01_images.png   with assets/ui/panel_soft, window_frame and
#                         button_face forced into the Image columns
#
#  Look at the two side by side. If the second one is what you want, put
#  those three words into the three Image cells and it is yours.
#
#      xvfb-run godot --rendering-driver opengl3 --resolution 1920x1080 \
#          --script res://tools/theme_shot.gd
#
#  It changes nothing on disk. The swap is in memory, for the length of one
#  screenshot.
#
#  A tool, not part of the game. Nothing loads it.
# =============================================================

## element -> the image to force into it for the second picture.
const TRY: Dictionary = {
	"panel": "panel_soft",
	"window": "window_frame",
	"button": "button_face",
	"button_primary": "button_face",
	"slot": "panel_soft",
}


func _initialize() -> void:
	await process_frame
	change_scene_to_file("res://src/ui/slot_screen.tscn")
	for i in 30:
		await process_frame
	await create_timer(1.0, true, false, true).timeout

	_shoot("th_00_flat")
	_report("as written")

	# ============ REMEMBER EVERY BOX'S COLOUR FIRST ============
	#
	# The tint is the whole trick — an image is drawn MODULATED by the colour
	# the screen asked for. But a screen asks for that colour once, when it
	# builds its boxes, and by the time we swap the images in it has been
	# folded into a StyleBoxFlat and there is nothing left to read.
	#
	# So the colours are collected BEFORE the swap and handed back after it.
	# The first version of this tool skipped that step and photographed a
	# screen of white rectangles with white text on them.
	_remember(current_scene)

	# ---- force the images in and rebuild ----
	var swapped := 0
	var rows := ThemeBook.elements()
	for element in TRY:
		if not rows.has(element):
			continue
		if ThemeBook.image(String(TRY[element])) == null:
			print("[theme] assets/ui/%s is not there — skipping it." % TRY[element])
			continue
		for state in rows[element]:
			rows[element][state]["image"] = TRY[element]
			swapped += 1
	ThemeBook.restyle()
	ThemeBook.dress(self)
	_redress(current_scene)

	await create_timer(1.0, true, false, true).timeout
	_shoot("th_01_images")
	_report("with %d row(s) drawn from an image" % swapped)

	print("[theme] pictures in %s" % ProjectSettings.globalize_path("user://"))
	quit(0)


## A screen builds its boxes once, when it opens, so changing the rows
## afterwards does not reach the ones already drawn. Walking the tree and
## re-applying the `panel` style to every PanelContainer is enough to show
## what the file would do from a cold start.
func _remember(node: Node) -> void:
	if node == null:
		return
	var box := node as PanelContainer
	if box != null:
		var flat := box.get_theme_stylebox("panel") as StyleBoxFlat
		if flat != null:
			box.set_meta("theme_shot_tint", flat.bg_color)
	for child in node.get_children():
		_remember(child)


func _redress(node: Node) -> void:
	if node == null:
		return
	var box := node as PanelContainer
	if box != null:
		var tint: Color = box.get_meta("theme_shot_tint", Color(0, 0, 0, 0))
		box.add_theme_stylebox_override("panel", ThemeBook.style("panel", "", tint))
	var pressable := node as Button
	if pressable != null:
		for state in ["normal", "hover", "pressed", "disabled"]:
			var was := pressable.get_theme_stylebox(state) as StyleBoxFlat
			var tint := was.bg_color if was != null else Color(0, 0, 0, 0)
			pressable.add_theme_stylebox_override(state, ThemeBook.style(
				"button", "" if state == "normal" else state, tint))
	for child in node.get_children():
		_redress(child)


func _report(what: String) -> void:
	var images := 0
	var rows := ThemeBook.elements()
	for element in rows:
		for state in rows[element]:
			if String(rows[element][state]["image"]) != "":
				images += 1
	print("[theme] %s: %d row(s) with an image." % [what, images])


func _shoot(shot_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	root.get_texture().get_image().save_png("user://%s.png" % shot_name)
	print("[theme] %s.png" % shot_name)
