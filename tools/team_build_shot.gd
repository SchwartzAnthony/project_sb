extends SceneTree

# =============================================================
#  TEAM BUILD, PRESSED FOR REAL (round Y)
#
#  On a THROWAWAY save and a throwaway team file (nothing of yours is read or
#  written), it:
#
#      1. opens the base on a brand-new game
#      2. presses the PUB plaque          -> must open TEAM BUILD, not the Pub
#      3. presses PLAY A MATCH            -> must open TEAM BUILD, not a match
#      4. places three Stars for nothing (team_build_free_stars) and saves a
#         full team of twelve
#      5. presses the PUB plaque again    -> must open the Pub
#
#  and photographs each window. Ends with TEAM BUILD WORKS WHEN PRESSED, or
#  the list of what did not.
#
#      xvfb-run -a godot --rendering-driver opengl3 --resolution 1920x1080 \
#          --script res://tools/team_build_shot.gd
# =============================================================

const CLASS := "Lorelei"

var trouble: Array[String] = []


func _initialize() -> void:
	await process_frame
	GameState.SAVE_PATH = "user://team_build_shot_throwaway.json"
	TeamRoster.SAVE_PATH = "user://team_build_shot_teams.json"
	var empty := TeamRoster.new()
	empty.save()
	var state := GameState.fetch(self)
	state.reset()
	state.unlock("Pub")
	# The opening scenes are not what is being tested: mark them as seen so
	# the base opens on the base and not on the prologue.
	for once in ["welcome_at_base", "sign_your_first_three"]:
		state.set_flag(Progression.DONE_PREFIX + once, true)

	change_scene_to_file("res://src/ui/base_screen.tscn")
	for i in 40:
		await process_frame
	await create_timer(0.6, true, false, true).timeout
	var base := current_scene
	_dismiss(base)

	# ---- 2 + 3: turned away ----
	for door in ["Pub", "Play a match"]:
		var button := _named(base, door)
		if button == null:
			trouble.append("No '%s' button on the base." % door)
			continue
		button.emit_signal("pressed")
		for f in 10:
			await process_frame
		await create_timer(0.5, true, false, true).timeout
		var window := _window(base)
		var hub := window != null and window.content is TeamBuildScreen
		print("[team build] new game, pressed %s -> %s" % [door, "TEAM BUILD" if hub else "something else"])
		if not hub:
			trouble.append("On a new game, %s did not send you to Team Build." % door)
		else:
			_shoot("tb_%s" % door.to_lower().replace(" ", "_"))
			window.close()
			await create_timer(0.2, true, false, true).timeout
	if current_scene != base:
		trouble.append("Play a match left the base on a game with no team.")

	# The Star Hall tab, on the new game, before anything is placed
	var first := BaseWindow.open(base, "Team Build", ScenePaths.TEAM_BUILD)
	for f in 10:
		await process_frame
	await create_timer(0.5, true, false, true).timeout
	_shoot("tb_star_hall_new_game")
	if first != null and first.content is TeamBuildScreen and (first.content as TeamBuildScreen)._tab != "Star Hall":
		trouble.append("A new game should land on the Star Hall tab - the Stars come first.")
	first.close()
	await create_timer(0.2, true, false, true).timeout

	# ---- 4: three Stars and a team of twelve ----
	var db := CardDatabase.get_db()
	var nodes := ClassTree.nodes_for(CLASS, state)
	var stars := ClassTree.stars_you_own(CLASS, state, db)
	for i in nodes.size():
		var fitting: PlayerData = stars[i]
		for star in stars:
			if ClassTree.fits(star, String(nodes[i]["set_id"]), db):
				fitting = star
		var result := ClassTree.place_star(CLASS, String(nodes[i]["set_id"]), fitting, state, db)
		print("[team build] %s" % result["why"])
		if not bool(result["ok"]):
			trouble.append("Placing a free Star failed: %s" % result["why"])
	var entry := TeamRoster.blank(CLASS, db.star_tier_for_class(CLASS))
	var chosen: Dictionary = {}
	for tier in TierLadder.TIERS:
		if tier == String(entry["star_tier"]):
			continue
		var row: Array[PlayerData] = []
		var have: Array[int] = []
		for card in ClassTree.gate_cards(db.roster_for_class(CLASS), state, db):
			if card.is_star() or card.get_tier_clean() != tier or have.has(card.base_power_left):
				continue
			row.append(card)
			have.append(card.base_power_left)
		chosen[tier] = row
	TeamRoster.set_cards(entry, chosen)
	var book := TeamRoster.load_all()
	book.put(entry)
	book.save()
	var now := TeamBuild.status(state, db)
	print("[team build] after: %s players, %s of %s Stars, ready = %s %s" % [
		now["players"], now["stars"], now["of"], now["ok"], now["why"]])
	if not bool(now["ok"]):
		trouble.append("Three Stars and a full team still are not ready: %s" % now["why"])

	# The hub, with everything ticked
	var hub_window := BaseWindow.open(base, "Team Build", ScenePaths.TEAM_BUILD)
	for f in 10:
		await process_frame
	await create_timer(0.5, true, false, true).timeout
	_shoot("tb_ready_hub")
	hub_window.close()
	await create_timer(0.2, true, false, true).timeout

	# ---- 5: the Pub opens ----
	if base.has_method("_rebuild"):
		base._rebuild()
	await create_timer(0.3, true, false, true).timeout
	var pub := _named(base, "Pub")
	if pub != null:
		pub.emit_signal("pressed")
		for f in 10:
			await process_frame
		await create_timer(0.5, true, false, true).timeout
		var window := _window(base)
		var is_pub := window != null and window.content is PubScreen
		print("[team build] ready, pressed Pub -> %s" % ("THE PUB" if is_pub else "something else"))
		if not is_pub:
			trouble.append("With a ready team, the Pub still did not open.")
		else:
			_shoot("tb_pub_open")

	print("")
	if trouble.is_empty():
		print("[team build] TEAM BUILD WORKS WHEN PRESSED.")
	else:
		for line in trouble:
			print("[team build] ! " + line)
	quit(0 if trouble.is_empty() else 1)


func _dismiss(base: Node) -> void:
	for child in base.get_children():
		if child is NewUnlocksPanel:
			child.queue_free()


func _named(from: Node, who: String) -> Button:
	for node in _every(from):
		var button := node as Button
		if button == null:
			continue
		for label in _every(button):
			var text := label as Label
			if text != null and text.text.strip_edges().begins_with(who):
				return button
	return null


func _window(base: Node) -> BaseWindow:
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


func _shoot(shot_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	root.get_texture().get_image().save_png("user://%s.png" % shot_name)
	print("[team build] %s.png" % shot_name)
