extends SceneTree

# =============================================================
#  THE ENEMY TEAM DATA WINDOW, ON ITS OWN, PHOTOGRAPHED
#
#  The window you get from ENEMY TEAM DATA on the team shelf and from TEAM on
#  the match HUD. It is a long list that grows with every card and every
#  ability you write, so the thing worth checking is whether it still fits:
#  a twelve-card squad with two abilities each is a lot of writing in one box.
#
#      xvfb-run godot --rendering-driver opengl3 --resolution 1920x1080 \
#          --script res://tools/scout_shot.gd
#
#  Two pictures land in user://: the window as it opens, and the window
#  after it has been scrolled to the bottom.
#
#  A tool, not part of the game. Nothing loads it.
# =============================================================

func _initialize() -> void:
	await process_frame
	var db := CardDatabase.get_db()

	# The fullest squad in the project, because the worst case is the one
	# worth photographing.
	var best := ""
	var most := 0
	for card in db.players:
		var many := db.roster_for_class(card.unit_type).size()
		if many > most:
			most = many
			best = card.unit_type
	if best == "":
		print("[scout] no cards found")
		quit(1)
		return

	var squad: Array[PlayerData] = []
	for card in db.roster_for_class(best):
		squad.append(card)
	var stars := db.stars_for_class(best)

	print("[scout] %s — %d cards, %d of them Stars" % [best, squad.size(), stars.size()])

	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(holder)

	var window := EnemyTeamWindow.open(holder, db, best, squad, stars,
		"Everything they can put on the pitch. Escape closes this.")
	for i in 8:
		await process_frame
	_shoot("s_00_open")

	# ---- and the bottom of the list ----
	var scroller := _find_scroller(window)
	if scroller != null:
		scroller.scroll_vertical = 100000
		for i in 4:
			await process_frame
		_shoot("s_01_bottom")
	else:
		print("[scout] no scroll box found — the list may not be scrollable")

	print("[scout] pictures in %s" % ProjectSettings.globalize_path("user://"))
	quit(0)


func _find_scroller(from: Node) -> ScrollContainer:
	if from is ScrollContainer:
		return from
	for child in from.get_children():
		var found := _find_scroller(child)
		if found != null:
			return found
	return null


func _shoot(name: String) -> void:
	var image := root.get_texture().get_image()
	image.save_png("user://%s.png" % name)
	print("[scout] %s.png" % name)
