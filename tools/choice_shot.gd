extends SceneTree

# =============================================================
#  THE QUESTION WINDOW, PHOTOGRAPHED  (round AA)
#
#      xvfb-run -a godot --rendering-driver opengl3 --resolution 1920x1080 \
#          --script res://tools/choice_shot.gd
#
#  Opens the window the game uses to ask you something - here, which unit
#  Gremory's Rose token replaces - and saves choice_01_rose.png in user://.
#  A tool; nothing loads it.
# =============================================================

func _initialize() -> void:
	await process_frame
	var back := ColorRect.new()
	back.color = Color(0.12, 0.35, 0.16)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(back)
	var options: Array[String] = [
		"Matthias   (Tier I, power 0, field)",
		"Magdalena   (Tier I, power 1, field)",
		"Leonhard   (Tier I, power 2, exhaust)"]
	var notes: Array[String] = [
		"While in exhaust: Give a Tier I water unit +1 power during combat (once per cycle)",
		"While in exhaust: Deal 1 damage to the enemy goalie at the end of a cycle (once per cycle)",
		"While in exhaust: Give a Tier II water unit ability priority during combat (once per cycle)"]
	ChoiceWindow.ask(root, "ROSE UNIT TOKEN",
		"A Rose Unit token takes the place of one of your units. Which one?\nThe unit you pick waits in the exhaust, where its \"While in exhaust\" side works.",
		options, notes)
	for i in 12:
		await process_frame
	root.get_texture().get_image().save_png("user://choice_01_rose.png")
	print("[choice] choice_01_rose.png in %s" % ProjectSettings.globalize_path("user://"))
	quit(0)
