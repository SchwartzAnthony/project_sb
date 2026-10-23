extends SceneTree

# =============================================================
#  THE STORY SCREEN, PHOTOGRAPHED  (round AN)
#
#      godot --path . --resolution 1920x1080 --script res://tools/story_shot.gd
#
#  Opens the conversation screen and photographs a few lines of the intro,
#  with the faces and the bar from data/StoryArt.csv. Saves story_<n>.png in
#  user://. Nothing is saved to your game. A tool; nothing loads it.
# =============================================================

const SHOTS := [
	["tut-base-welcome", "welcome"],
	["prologue", "open"],
	["prologue", "servus"],
	["prologue", "still_cold"],
	["prologue", "koch_changed"],
	["prologue", "auf"],
	["after_first_match", "base"],
]

## The Head Coach's eight faces, on made-up lines: [mood, view, side].
const COACH := [
	["happy", "front", "left"], ["sad", "front", "left"],
	["drunk", "front", "left"], ["mad", "front", "left"],
	["happy", "side", "left"], ["sad", "side", "right"],
	["drunk", "side", "left"], ["mad", "side", "right"],
]

## Koch's faces the story uses, the same way.
const KOCH := [
	["", "front", "right"], ["happy", "side", "right"], ["sad", "side", "right"],
	["drunk", "side", "right"], ["mad", "side", "right"],
]


func _initialize() -> void:
	await process_frame
	ThemeBook.dress(self)
	var view: DialogueView = load(ScenePaths.STORY).instantiate()
	view.type_speed = 0.0
	view.transition_time = 0.0
	view.return_to_menu = false
	view.scene_name = "prologue"
	root.add_child(view)
	for i in 6:
		await process_frame
	for n in SHOTS.size():
		var shot: Array = SHOTS[n]
		var line := view.story.line_for(shot[0], shot[1], view.state)
		if line == null:
			print("[story_shot] no line %s/%s" % shot)
			continue
		# A line with no Background keeps the room already up, as in the game.
		view._show(line)
		for i in 8:
			await process_frame
		var file := "user://story_%d_%s.png" % [n + 1, shot[1]]
		root.get_texture().get_image().save_png(file)
		print("[story_shot] ", ProjectSettings.globalize_path(file))
	for face in COACH:
		await _face(view, "coach", "The Head Coach", "", face)
	var clear := DialogueLine.new()
	clear.leaves = "all"
	clear.text = "..."
	view._show(clear)
	for i in 8:
		await process_frame
	for face in KOCH:
		await _face(view, "koch", "Koch", "koch", face)
	quit(0)


func _face(view: DialogueView, who: String, speaker: String, portrait: String, face: Array) -> void:
	var line := DialogueLine.new()
	line.scene = "story_shot"
	line.id = "%s_%s_%s" % [who, face[0], face[1]]
	line.speaker = speaker
	line.portrait = portrait
	line.mood = face[0]
	line.view = face[1]
	line.side = face[2]
	line.text = "(%s, %s) Welcome to the club, Trainer. Sit down, have a beer." % [face[0], face[1]]
	view._show(line)
	for i in 8:
		await process_frame
	var file := "user://story_%s_%s_%s.png" % [who, face[0], face[1]]
	root.get_texture().get_image().save_png(file)
	print("[story_shot] ", ProjectSettings.globalize_path(file))
