extends SceneTree

# =============================================================
#  THE BREWER'S CART AND THE PUB'S TEN SEATS, PHOTOGRAPHED
#
#      xvfb-run godot --rendering-driver opengl3 --resolution 1920x1080 \
#          --script res://tools/shop_shot.gd
#
#      sh_00_broke.png    the cart with an empty purse: everything greyed,
#                         and every price still readable. This is the shot
#                         that matters, because it is what a new save sees
#      sh_01_flush.png    the same cart after a season's takings
#      sh_02_pub.png      the Pub with `pub_ten` forced on and four seats
#                         taken, so the dimming can be looked at
#
#  It works on the save IN MEMORY only — nothing is written to disk.
#
#  A tool, not part of the game. Nothing loads it.
# =============================================================


func _initialize() -> void:
	await process_frame
	var db := CardDatabase.get_db()

	change_scene_to_file("res://src/ui/shop_screen.tscn")
	for i in 40:
		await process_frame
	await create_timer(0.8, true, false, true).timeout

	var shop := current_scene as ShopScreen
	if shop == null:
		print("[shop] the cart did not open.")
		quit(1)
		return

	for entry in ShopBook.shelf():
		for term in String(entry["requires"]).split(";", false):
			var clean := String(term).strip_edges()
			if clean.to_lower().begins_with("unlocked:"):
				shop.state.unlock(clean.substr(clean.find(":") + 1).strip_edges())
	shop._rebuild()
	await create_timer(0.5, true, false, true).timeout
	print("[shop] purse empty.")
	_shoot("sh_00_broke")

	for money in ShopBook.currencies():
		shop.state.set_count(String(money["counter"]), 225)
	shop._rebuild()
	await create_timer(0.5, true, false, true).timeout
	print("[shop] purse at a season's takings.")
	_shoot("sh_01_flush")

	# ---- and the Pub, with the ten-seat room forced on ----
	db.tuning[CardDatabase._normalise("pub_ten")] = "true"
	change_scene_to_file("res://src/ui/pub_screen.tscn")
	for i in 40:
		await process_frame
	await create_timer(0.8, true, false, true).timeout

	var pub := current_scene as PubScreen
	if pub == null:
		print("[shop] the Pub did not open.")
		quit(1)
		return
	var seated := 0
	for card in CardDatabase.get_db().players:
		if card.is_star() or seated >= 4:
			continue
		PubBook.toggle(card, pub.state, db)
		seated += 1
	pub._refresh_seats()
	pub._rebuild_cards()
	await create_timer(0.6, true, false, true).timeout
	print("[shop] the Pub: %s" % PubBook.words(pub.state, db))
	_shoot("sh_02_pub")

	print("[shop] pictures in %s" % ProjectSettings.globalize_path("user://"))
	quit(0)


func _shoot(shot_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("[shop] headless — no picture taken. Run it under xvfb-run.")
		return
	root.get_texture().get_image().save_png("user://%s.png" % shot_name)
	print("[shop] %s.png" % shot_name)
