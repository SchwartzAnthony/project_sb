extends SceneTree

# =============================================================
#  THE DRUNK METER, PRESSED FOR REAL (round AN)
#
#  Opens the Pub on a throwaway save, tries a Fire Brew on a sober player
#  (refused), pours plain beers until he is Tipsy and then Inspired (a Star),
#  and photographs every step. Every press is the real button.
#
#      godot --path . --resolution 1600x900 --script res://tools/drunk_shot.gd
#
#  Pictures: user://drunk/frame_NNN.png  (tools turn them into a GIF).
# =============================================================

var _frame := 0
var _pub: PubScreen


func _initialize() -> void:
	await process_frame
	GameState.SAVE_PATH = "user://drunk_shot_throwaway.json"
	var state := GameState.fetch(self)
	state.reset()
	state.set_count("reed", 30)
	state.set_count("ash_glass", 30)
	state.unlock("Keeper's Tonic")
	var db := CardDatabase.get_db()
	db.tuning["team_build_gate"] = "false"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://drunk"))

	change_scene_to_file("res://src/ui/pub_screen.tscn")
	for i in 30:
		await process_frame
	_pub = current_scene as PubScreen
	if _pub == null:
		print("[drunk] the Pub did not open.")
		quit(1)
		return

	# THE FIRST CARD ON THE GRID is the drinker; three others show the meter
	# at other levels so the picture reads at a glance.
	var grid_cards: Array[PlayerData] = []
	for card in db.players:
		if card != null and not card.is_star() and card.unit_type != "Rivals":
			grid_cards.append(card)
	var who: PlayerData = grid_cards[0]
	for pair in [[1, 15], [2, 45], [3, 85], [5, 30]]:
		if grid_cards.size() > int(pair[0]):
			DrunkBook.set_meter(grid_cards[int(pair[0])], int(pair[1]), state)
	_pub._rebuild_cards()
	await _hold(0.5, 4)

	# 1. A Keeper's Tonic on a sober man: refused.
	_press(_button_with(_pub._brew_list, "Keeper's Tonic"))
	await _hold(0.3, 3)
	_press(_card_button(who))
	await _hold(0.3, 8)
	print("[drunk] %s" % _pub._detail.text)

	# 2. Helles, Helles, Festbier, Festbier...
	var trouble := 0
	for brew_name in ["Helles", "Festbier", "Helles", "Festbier"]:
		_press(_button_with(_pub._brew_list, brew_name))
		await _hold(0.2, 2)
		_press(_card_button(who))
		await _hold(0.08, 14)
		print("[drunk] %s" % _pub._detail.text)
		await _hold(0.4, 4)

	if not DrunkBook.is_star(who, state):
		print("[drunk] ! %s is not a Star after the beers." % who.player_name)
		trouble += 1

	# 3. Now the Keeper's Tonic takes hold.
	_press(_button_with(_pub._brew_list, "Keeper's Tonic"))
	await _hold(0.2, 2)
	_press(_card_button(who))
	await _hold(0.3, 10)
	print("[drunk] %s" % _pub._detail.text)

	# 4. Kick-off: the star overlay goes on.
	BrewDB.get_db().apply_all(db, state)
	print("[drunk] at kick-off %s: star %s, attack %s, defend %s" % [who.player_name,
		who.drunk_star, who.active_attack_ability(), who.active_defend_ability()])
	# The match's hover panel on him, as a Star with Beer Courage.
	var panel := CardStatsPanel.make(db)
	_pub.add_child(panel)
	await process_frame
	panel.show_card(who, Vector2(560, 300))
	await _hold(0.3, 1)
	if DisplayServer.get_name() != "headless":
		root.get_texture().get_image().save_png("user://drunk/star_panel.png")
	BrewDB.restore_all()
	print("[drunk] %s" % ("THE DRUNK METER WORKS WHEN PRESSED." if trouble == 0 else "%d PROBLEM(S)." % trouble))
	quit(0 if trouble == 0 else 1)


func _press(button: Button) -> void:
	if button == null:
		print("[drunk] ! a button is missing.")
		return
	button.emit_signal("pressed")


func _card_button(card: PlayerData) -> Button:
	return _pub._card_buttons.get(card.player_name, null) as Button


func _button_with(from: Node, words: String) -> Button:
	for node in from.find_children("*", "Button", true, false):
		for label in (node as Button).find_children("*", "Label", true, false):
			if (label as Label).text == words:
				return node as Button
	return null


## Wait and photograph: `shots` frames, `gap` seconds apart.
func _hold(gap: float, shots: int) -> void:
	for i in shots:
		await create_timer(gap, true, false, true).timeout
		await process_frame
		if DisplayServer.get_name() != "headless":
			root.get_texture().get_image().save_png("user://drunk/frame_%03d.png" % _frame)
			_frame += 1
