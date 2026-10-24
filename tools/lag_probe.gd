extends "res://tools/tutorial_check.gd"

# =============================================================
#  WHERE DOES THE GAME STALL?  (round AN, 24 Oct: "the game seems to lag")
#
#      godot --headless --path . --script res://tools/lag_probe.gd
#      xvfb-run -a godot --rendering-driver opengl3 --script res://tools/lag_probe.gd
#
#  Plays the Tutorial exactly like tools/tutorial_check.gd, and prints every
#  frame that took longer than SLOW_MS, with the screen it was on and the
#  nodes that were made in it. A tool; nothing in the game loads it.
# =============================================================

const SLOW_MS := 40.0


class Spy extends Node:
	var last := 0
	var added := 0
	var added_kinds: Dictionary = {}
	var slow: Array[String] = []
	var frames := 0
	var total_ms := 0.0
	## scene name -> [frames, ms, frames over 1/30 s]
	var per_scene: Dictionary = {}

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		process_priority = -1000
		get_tree().node_added.connect(_on_added)
		last = Time.get_ticks_usec()

	func _on_added(node: Node) -> void:
		added += 1
		var kind := node.get_class()
		var script := node.get_script() as Script
		if script != null and script.resource_path != "":
			kind = script.resource_path.get_file()
		added_kinds[kind] = int(added_kinds.get(kind, 0)) + 1

	func _process(_delta: float) -> void:
		var now := Time.get_ticks_usec()
		var ms := (now - last) / 1000.0
		last = now
		frames += 1
		total_ms += ms
		var where := _where()
		var tally: Array = per_scene.get(where, [0, 0.0, 0])
		tally[0] += 1
		tally[1] += ms
		if ms > 34.0:
			tally[2] += 1
		per_scene[where] = tally
		if ms >= SLOW_MS:
			var scene := get_tree().current_scene
			var kinds := added_kinds.keys()
			kinds.sort_custom(func(a, b): return added_kinds[a] > added_kinds[b])
			var top: Array[String] = []
			for k in kinds.slice(0, 6):
				top.append("%s x%d" % [k, added_kinds[k]])
			var line := "[lag] %7.1f ms  t=%.1fs  scene=%s  added=%d %s" % [ms,
				Time.get_ticks_msec() / 1000.0, scene.name if scene != null else "-", added,
				str(top)]
			print(line)
			slow.append(line)
		added = 0
		added_kinds.clear()

	## The screen, plus what is open over it (a talk box, a duel, a story).
	func _where() -> String:
		var scene := get_tree().current_scene
		if scene == null:
			return "-"
		var name_text := String(scene.name)
		for extra in ["DialogueView", "DuelArena", "MatchTalkBox", "TimeOut"]:
			if scene.find_child(extra, true, false) != null:
				name_text += "+" + extra
		return name_text

	func _exit_tree() -> void:
		print("[lag] ===== frames per screen (average ms, frames slower than 30 fps) =====")
		for key in per_scene:
			var tally: Array = per_scene[key]
			print("[lag] %-40s %6d frames  avg %6.1f ms  slow %d" % [key, tally[0],
				tally[1] / maxf(1.0, tally[0]), tally[2]])


var _spy: Spy = null


func _initialize() -> void:
	_spy = Spy.new()
	root.add_child.call_deferred(_spy)
	super._initialize()


func _frame(_folder: String, _index: int) -> void:
	pass


func _shot_one(_shot_name: String) -> void:
	pass
