class_name Juice
extends RefCounted

# =============================================================
#  PLAYING THE JUICE
#
#  One line at the moment something happens:
#
#      Juice.fire(self, "enemy_hit", {"node": foe, "amount": dealt,
#                                     "average": 6.0})
#
#  and every row of Juice.csv with `When = enemy_hit` goes off — the shake,
#  the flash, the pop, the slow-motion and the sound, on whatever the row's
#  `Who` column names.
#
#  ============ WHAT YOU PASS IT ============
#
#      node      the thing to shake, for a row whose Who is player/enemy/ball
#      amount    how big this one was. Optional
#      average   what an ordinary one is, so `amount` means something
#
#  Leave `amount` out and every hit shakes the same, which is exactly what
#  Shake Scale 0 does anyway.
#
#  ============ WHY IT IS ALL IN ONE PLACE ============
#
#  Because feel is the thing you will fiddle with a hundred times, and a
#  hundred fiddles across twelve scripts is how a codebase stops being
#  editable. Here it is one spreadsheet and one file, and the twelve scripts
#  only ever say WHAT HAPPENED.
#
#  ============ TURNING IT DOWN ============
#
#      juice_scale      in Tuning.csv. 0 kills every effect, 0.5 halves them,
#                       2 doubles them. For people who dislike screen shake,
#                       and for you while you are debugging
#      juice_slowmo     false stops the slow-motion dips only
# =============================================================


## Fire every effect registered for a moment.
##
## `on` is any Node in the tree — it is used to find the scene and to hang
## the tweens on. Nothing here ever fails loudly: a missing node, a missing
## row or a missing sound all just mean less happens.
static func fire(on: Node, moment: String, facts: Dictionary = {}) -> void:
	if on == null or not is_instance_valid(on):
		return
	var rows := JuiceDB.rows_for(moment)
	if rows.is_empty():
		return

	var db := CardDatabase.get_db()
	var overall := db.tune_float("juice_scale", 1.0)
	if overall <= 0.0:
		return

	var amount := float(facts.get("amount", 0.0))
	var average := float(facts.get("average", 0.0))
	var node := facts.get("node", null) as Node

	for entry in rows:
		var row: Dictionary = entry
		var strength := JuiceDB.strength_of(amount, average,
			float(row["shake_scale"])) * overall

		match String(row["who"]):
			"screen":
				_shake_screen(on, float(row["shake"]) * strength,
					float(row["flash"]), row["flash_colour"])
			_:
				_shake_node(node, float(row["shake"]) * strength,
					float(row["flash"]), row["flash_colour"],
					float(row["pop"]), float(row["squash"]))

		if float(row["slowmo"]) > 0.0 and db.tune_bool("juice_slowmo", true):
			_slow_down(on, float(row["slowmo"]))

		var sound := String(row["sound"]).strip_edges()
		if sound != "":
			_play(on, sound, facts)


# =============================================================
#  SHAKING ONE THING
# =============================================================

## A short, decaying wobble around wherever the node already is, plus an
## optional flash and an optional pop.
##
## IT REMEMBERS WHERE THE NODE WAS. Two hits landing on the same enemy in
## quick succession would otherwise each save the shaken position as "home"
## and the enemy would walk off across the pitch. The mark on the node is
## what stops that.
static func _shake_node(node: Node, pixels: float, flash: float,
		tint: Color, pop: float, squash: float) -> void:
	if node == null or not is_instance_valid(node):
		return
	var item := node as CanvasItem
	if item == null:
		return

	if pixels > 0.5 and (node is Node2D or node is Control):
		var home: Vector2 = node.get_meta("juice_home", node.get("position"))
		node.set_meta("juice_home", home)

		var shake := item.create_tween()
		var steps := 5
		for i in steps:
			var fade := 1.0 - float(i) / float(steps)
			var to: Vector2 = home + Vector2(
				randf_range(-pixels, pixels), randf_range(-pixels, pixels)) * fade
			shake.tween_property(node, "position", to, 0.035)
		shake.tween_property(node, "position", home, 0.05)
		shake.finished.connect(func() -> void:
			if is_instance_valid(node):
				node.remove_meta("juice_home"))

	if flash > 0.0:
		var was: Color = item.get_meta("juice_tint", item.modulate)
		item.set_meta("juice_tint", was)
		item.modulate = tint
		var back := item.create_tween()
		back.tween_property(item, "modulate", was, flash)
		back.finished.connect(func() -> void:
			if is_instance_valid(item):
				item.remove_meta("juice_tint"))

	if pop > 0.0 or squash > 0.0:
		var scaled := node as Node2D
		var control := node as Control
		if scaled == null and control == null:
			return
		var base: Vector2 = node.get_meta("juice_scale", node.get("scale"))
		node.set_meta("juice_scale", base)
		# POP AND SQUASH TOGETHER read as weight: it gets wider as it gets
		# shorter, the way a struck thing does.
		var big := Vector2(
			base.x * maxf(pop, 1.0) * (1.0 + squash),
			base.y * maxf(pop, 1.0) * (1.0 - squash))
		var bounce := item.create_tween()
		bounce.tween_property(node, "scale", big, 0.07) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		bounce.tween_property(node, "scale", base, 0.13) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		bounce.finished.connect(func() -> void:
			if is_instance_valid(node):
				node.remove_meta("juice_scale"))


# =============================================================
#  SHAKING THE WHOLE SCREEN
# =============================================================

## The match has a real Camera2D and shakes that. Every other screen has no
## camera at all, so the SCENE ROOT is nudged instead — which looks the same
## and costs nothing. One function, both cases.
static func _shake_screen(on: Node, pixels: float, flash: float,
		tint: Color) -> void:
	if pixels <= 0.5 and flash <= 0.0:
		return
	var tree := on.get_tree()
	if tree == null:
		return

	if pixels > 0.5:
		var camera := on.get_viewport().get_camera_2d()
		if camera != null and camera.has_method("shake"):
			# match_camera.gd knows how to shake properly, with its own decay.
			camera.call("shake", pixels)
		else:
			_shake_node(tree.current_scene, pixels, 0.0, Color.WHITE, 0.0, 0.0)

	if flash > 0.0:
		_flash_screen(on, flash, tint)


## A full-screen wash of colour that fades out. Drawn on its own layer above
## everything, ignoring the mouse, and gone when it is finished.
static func _flash_screen(on: Node, seconds: float, tint: Color) -> void:
	var tree := on.get_tree()
	if tree == null or tree.current_scene == null:
		return

	var layer := CanvasLayer.new()
	layer.layer = 250
	tree.current_scene.add_child(layer)

	var wash := ColorRect.new()
	wash.color = Color(tint.r, tint.g, tint.b, 0.55)
	wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(wash)

	var fade := wash.create_tween()
	fade.tween_property(wash, "color:a", 0.0, seconds)
	fade.finished.connect(func() -> void:
		if is_instance_valid(layer):
			layer.queue_free())


# =============================================================
#  SLOW MOTION
# =============================================================

## A brief dip in the speed of the whole game, then back. This is the single
## cheapest way to make a hit feel like it connected.
##
## It multiplies whatever speed you are already on rather than setting one,
## so a dip at 8x speed is still a dip and does not yank you back to 1x.
static func _slow_down(on: Node, seconds: float) -> void:
	var tree := on.get_tree()
	if tree == null:
		return
	var was := Engine.time_scale
	Engine.time_scale = was * 0.35
	# `true` for process_always: the timer has to keep running while the
	# game is slowed, or it would take three times as long to finish.
	await tree.create_timer(seconds, true, false, true).timeout
	Engine.time_scale = was


# =============================================================
#  SOUND
# =============================================================

## The Sound column is a row of Audio.csv first, and a file in
## assets/audio/ second — so a WAV you have just dropped in makes a noise
## before you have written a row for it.
static func _play(on: Node, sound: String, facts: Dictionary) -> void:
	var tree := on.get_tree()
	if tree == null:
		return
	AudioDirector.play_cue(tree, sound, facts)
