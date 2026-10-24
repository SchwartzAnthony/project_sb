extends SceneTree

# =============================================================
#  HANNA IN THE BREWERY TALK, PHOTOGRAPHED  (23 Oct 2026)
#
#      godot --path . --resolution 1920x1080 --script res://tools/hanna_shot.gd
#
#  Opens the conversation screen on the brewery lines where Hanna and the
#  Head Coach stand side by side. Saves hanna_<n>.png in user://. Nothing is
#  saved to your game. A tool; nothing loads it.
# =============================================================

const SHOTS := [
	["brewery-intro", "servus"],
	["brewery-intro", "doing_well"],
	["tut-brewery-hanna", "train"],
	["tut-brewery-hanna", "steep"],
]


func _initialize() -> void:
	await process_frame
	ThemeBook.dress(self)
	var view: DialogueView = load(ScenePaths.STORY).instantiate()
	view.type_speed = 0.0
	view.transition_time = 0.0
	view.return_to_menu = false
	view.scene_name = "brewery-intro"
	root.add_child(view)
	for i in 6:
		await process_frame
	for n in SHOTS.size():
		var shot: Array = SHOTS[n]
		var line := view.story.line_for(shot[0], shot[1], view.state)
		if line == null:
			print("[hanna_shot] no line %s/%s" % shot)
			continue
		view._show(line)
		for i in 8:
			await process_frame
		var file := "user://hanna_%d_%s.png" % [n + 1, shot[1]]
		root.get_texture().get_image().save_png(file)
		print("[hanna_shot] ", ProjectSettings.globalize_path(file))
	quit(0)
