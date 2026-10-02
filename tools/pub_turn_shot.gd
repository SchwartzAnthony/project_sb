extends SceneTree

# =============================================================
#  THREE BEERS, PRESSED FOR REAL (round X)
#
#  Opens the Pub, presses the Rhine Water Lager, presses Müller three times,
#  photographs the "who does he become?" question, presses the first set,
#  and photographs the result. Every press is the real button, so a broken
#  button is a failed run - the lesson of round U.
#
#      xvfb-run -a godot --rendering-driver opengl3 --resolution 1920x1080 \
#          --script res://tools/pub_turn_shot.gd
#
#  Uses a scratch save that is thrown away: nothing is written to disk.
#  Pictures: pt_01_choice.png, pt_02_turned.png in the user:// folder.
# =============================================================

const PLAYER := "Müller"
const BREW := "Rhine Water Lager"


func _initialize() -> void:
	await process_frame
	var state := GameState.fetch(self)
	state.reset()
	state.set_count("reed", 9)
	# The tool's save must never reach the disk.
	GameState.SAVE_PATH = "user://pub_turn_shot_throwaway.json"

	change_scene_to_file("res://src/ui/pub_screen.tscn")
	for i in 30:
		await process_frame
	var pub := current_scene
	if pub == null:
		print("[pub] the Pub did not open.")
		quit(1)
		return

	var trouble := 0
	var brew := _button_with(pub, BREW)
	if brew == null:
		print("[pub] ! no brew button called '%s'." % BREW)
		quit(1)
		return
	brew.emit_signal("pressed")
	await process_frame
	await process_frame

	for i in 3:
		var card := _button_with(pub, PLAYER)
		if card == null:
			print("[pub] ! no card button for %s." % PLAYER)
			quit(1)
			return
		card.emit_signal("pressed")
		for f in 4:
			await process_frame
		print("[pub] pour %d: %s" % [i + 1, (pub as PubScreen)._detail.text])

	await create_timer(0.4, true, false, true).timeout
	var chooser := pub.find_child("WhoDoesHeBecome", true, false)
	if chooser == null:
		print("[pub] ! three pours did not ask who he becomes.")
		trouble += 1
	else:
		_shoot("pt_01_choice")
		var first := _button_with(chooser, " set")
		if first == null:
			print("[pub] ! the question has no set buttons.")
			trouble += 1
		else:
			first.emit_signal("pressed")
			for f in 6:
				await process_frame
			await create_timer(0.4, true, false, true).timeout
			print("[pub] %s" % (pub as PubScreen)._detail.text)
			_shoot("pt_02_turned")

	var who := TransformBook.became(_card_named(PLAYER), state)
	if who == "":
		print("[pub] ! %s did not turn." % PLAYER)
		trouble += 1
	else:
		print("[pub] %s became the card '%s'." % [PLAYER, who])
	print("")
	print("[pub] %s" % ("THREE BEERS WORK WHEN PRESSED." if trouble == 0 else "%d PROBLEM(S) - see above." % trouble))
	TransformBook.restore_all()
	quit(0 if trouble == 0 else 1)


func _card_named(who: String) -> PlayerData:
	for card in CardDatabase.get_db().players:
		if card.player_name == who:
			return card
	return null


## The first Button whose own text, or any Label inside it, contains `words`.
func _button_with(from: Node, words: String) -> Button:
	for node in from.find_children("*", "Button", true, false):
		var button := node as Button
		if button.text.contains(words):
			return button
		for label in button.find_children("*", "Label", true, false):
			if (label as Label).text == words or (label as Label).text.contains(words) and words.length() > 4:
				return button
	return null


func _shoot(shot_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("[pub] headless - no picture taken. Run it under xvfb-run.")
		return
	root.get_texture().get_image().save_png("user://%s.png" % shot_name)
	print("[pub] %s.png" % shot_name)
