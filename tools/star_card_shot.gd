extends SceneTree

# =============================================================
#  THE STAR PLAYER'S CARD, PHOTOGRAPHED  (24 Oct 2026)
#
#  Lays a few beer mat cards side by side, Star players first, so the gold
#  star where the bottle cap was (CardFace.csv star_frame) can be checked
#  next to a normal card.
#
#      xvfb-run godot --rendering-driver opengl3 --resolution 1920x1080 \
#          --script res://tools/star_card_shot.gd
#
#  Picture: user://star_cards.png. A tool, not part of the game.
# =============================================================

func _initialize() -> void:
	await process_frame
	var db := CardDatabase.get_db()
	var shown: Array[PlayerData] = []
	for card in db.players:
		if card.is_star() and card.player_name.contains("Koch"):
			shown.append(card)
			break
	for card in db.players:
		if card.is_star() and not shown.has(card) and shown.size() < 2:
			shown.append(card)
	for card in db.players:
		if not card.is_star():
			shown.append(card)
			break
	var row := HBoxContainer.new()
	row.position = Vector2(60, 60)
	row.add_theme_constant_override("separation", 40)
	root.add_child(row)
	for card in shown:
		row.add_child(MenuSupport.card_face(card, db, Vector2(440, 580)))
		print("[star card] %s  star=%s  power=%d" % [card.player_name, card.is_star(), card.get_attack_power()])
	for i in 30:
		await process_frame
	root.get_texture().get_image().save_png("user://star_cards.png")
	print("[star card] saved user://star_cards.png")
	quit(0)
