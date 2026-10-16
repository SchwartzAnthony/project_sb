extends SceneTree

# =============================================================
#  THE PUB POURS YOUR BOTTLES  (Anthony, 15 Oct)
#
#      godot --script res://tools/pub_bottle_shot.gd -- OUT.png
#
#  A new game with 6 Fire small bottles, the Pub screen opened, the bottle
#  picked and poured on the first seated player; photographs the screen and
#  prints what he got. A tool, not part of the game.
# =============================================================


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := "user://pub_bottle.png"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	var screen: Node = load(ScenePaths.PUB).instantiate()
	root.add_child(screen)
	await process_frame
	var state: GameState = screen.get("state")
	var cards: CardDatabase = screen.get("cards")
	state.set_count("small_bottle", 6)
	state.set_text(BreweryBook.ELEMENTS_PREFIX + "small_bottle", "fire,fire,fire,fire,fire,fire")
	screen.call("_rebuild_brews")
	await process_frame
	var bottle: Dictionary = {}
	for one in screen.call("_bottles"):
		bottle = one
	print("bottles on tap: %s" % bottle.get("name", "none"))
	var who: PlayerData = null
	for card in cards.players:
		if card != null and not card.is_star() and PubBook.allowed(card, state, cards):
			who = card
			break
	if who == null or bottle.is_empty():
		print("nothing to pour")
		quit(1)
		return
	DrunkBook.set_meter(who, 60, state)
	screen.set("_selected", bottle)
	screen.call("_on_card", who)
	await process_frame
	await process_frame
	print("poured on %s: %s" % [who.player_name, BrewDB.brew_id_for(who, state)])
	print("detail: %s" % screen.get("_detail").text)
	print("bottles left: %d" % state.count("small_bottle"))
	var img := root.get_viewport().get_texture().get_image()
	if img != null:
		img.save_png(out)
	quit(0)
