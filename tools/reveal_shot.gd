extends SceneTree

# =============================================================
#  A REVEAL, PHOTOGRAPHED — the strip above the card row
#
#  A card played face up goes ON THE TABLE: a strip above the row you are
#  choosing from, holding theirs on the left and yours on the right, each
#  with its power and what its ability does. It only exists while something
#  has been shown, so this is the only way to look at it without playing a
#  match and hoping the right card turns up in the right tier.
#
#  THIS IS A LAYOUT CHECK. It calls the same _put_on_the_table() the match
#  calls, with real cards out of your own spreadsheets. The other two
#  questions have tools of their own:
#
#      does the button appear on the right cards, does the ability fire
#          tools/reveal_check.gd
#      do the opposition's rules ever decide to show one
#          tools/enemy_play_check.gd
#
#      xvfb-run godot --rendering-driver opengl3 --resolution 1920x1080 \
#          --script res://tools/reveal_shot.gd
#
#  A tool, not part of the game. Nothing loads it.
# =============================================================

func _initialize() -> void:
	seed(20260921)
	await process_frame
	MatchMode.choose(self, "friendly")
	change_scene_to_file("res://src/formations/main_scene.tscn")
	for i in 8:
		await process_frame
	var scene := current_scene
	if scene == null:
		print("[shown] the match did not open")
		quit(1)
		return

	# ---- PAST THE TEAM SHEET ----
	#
	# It holds for START now (`team_sheet_hold`), so this waits for the bar
	# to fill and then presses it. Polled rather than timed, because the
	# sheet's own timing comes out of Tuning.csv and can be set to anything.
	for i in 200:
		var sheet = scene.get("_sheet")
		if sheet == null or not is_instance_valid(sheet):
			break
		if bool(sheet.get("_opened")):
			sheet.call("_go")
			break
		await create_timer(0.2, true, false, true).timeout
	await create_timer(1.5, true, false, true).timeout

	# ---- AUTO ON ----
	#
	# The PLAY MAKER opens with the coin clash, and the clash waits for a
	# human to call a number. Without this the tool sits on that screen until
	# it is killed, which cost me three runs.
	var state = scene.get("state")
	MatchHUD.set_auto_pick(state, true)
	if scene.has_method("_on_auto_pick_changed"):
		scene.call("_on_auto_pick_changed", true)

	# ---- MAKE A DRAFT HAPPEN ----
	#
	# The row of cards is what this is a picture of, and waiting five in-game
	# minutes for one is the difference between a two-second test and a
	# two-minute one.
	if is_instance_valid(scene):
		scene.call("trigger_playmaker_event")
	for i in 120:
		await create_timer(0.1, true, false, true).timeout
		if not is_instance_valid(scene):
			break
		var row = scene.get("card_container")
		if row != null and row.get_child_count() > 0:
			break

	var db := CardDatabase.get_db()
	var mine = _with_reveal(db)
	var theirs = _any_other(db, mine)
	if mine == null:
		print("[shown] Nothing in your CSVs has a `reveal` ability, so there is")
		print("[shown] nothing to put on the table. Put LORE_OPEN_HAND or")
		print("[shown] BRAND_CALLED_SHOT in a card's Attack Ability column.")
		quit(1)
		return

	scene.call("_put_on_the_table", mine, false)
	for j in 8:
		await process_frame
	_shoot("v_00_yours")

	if theirs != null:
		scene.call("_put_on_the_table", theirs, true)
		for j in 8:
			await process_frame
		_shoot("v_01_both")

	print("[shown] pictures in %s" % ProjectSettings.globalize_path("user://"))
	quit(0)


## A card that actually has something written against the `reveal` trigger.
func _with_reveal(db: CardDatabase):
	for card in db.players:
		for ability_id in [card.active_attack_ability(), card.active_defend_ability()]:
			var ability: AbilityData = db.get_ability(String(ability_id))
			if ability != null and ability.trigger == "reveal":
				return card
	return null


## Anybody else, to stand in for the other side's card.
func _any_other(db: CardDatabase, not_this):
	for card in db.players:
		if card != not_this and card.get_attack_power() > 0:
			return card
	return null


func _shoot(shot_name: String) -> void:
	root.get_texture().get_image().save_png("user://%s.png" % shot_name)
	print("[shown] %s.png" % shot_name)
