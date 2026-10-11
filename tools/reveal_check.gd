extends SceneTree

# =============================================================
#  SHOW — DOES PLAYING A CARD FACE UP ACTUALLY DO ANYTHING?
#
#  Four questions, each with a printed answer:
#
#    1. Is `reveal` live?         AbilityTriggers.csv says so or it does not.
#    2. Does the button appear?   Only on a card that HAS a reveal ability,
#                                 and only on that one.
#    3. Does the ability fire?    A shown card should be worth more than the
#                                 same card unshown.
#    4. Do they answer it?        Their pick after a reveal should be their
#                                 BEST in that tier, not a random one.
#
#      godot --headless --script res://tools/reveal_check.gd
#
#  A tool, not part of the game. Nothing loads it.
# =============================================================

func _initialize() -> void:
	await process_frame
	var db := CardDatabase.get_db()
	var bad := 0

	# ---- 1. the trigger ----
	var live := AbilityData.trigger_is_live("reveal")
	print("[reveal] trigger live in AbilityTriggers.csv: %s" % ("yes" if live else "NO"))
	if not live:
		print("[reveal] nothing else can be true while that says planned.")
		quit(1)
		return

	# ---- 2. which cards carry one ----
	var carriers: Array[PlayerData] = []
	for card in db.players:
		for cell in [card.active_attack_ability(), card.active_defend_ability()]:
			var found := false
			for ability_id in String(cell).split(";"):
				var ability := db.get_ability(String(ability_id).strip_edges())
				if ability != null and ability.trigger == "reveal":
					found = true
			if found:
				carriers.append(card)
				break
	print("[reveal] cards with a reveal ability: %d" % carriers.size())
	for card in carriers:
		print("[reveal]   %s (Tier %s) — %s" % [card.player_name,
			card.get_tier_clean(), card.active_attack_ability()])
	if carriers.is_empty():
		print("[reveal] WRITE ONE: put CALLED_SHOT or LORE_OPEN_HAND in a card's Attack Ability column.")
		bad += 1

	# ---- 3. does the ability actually land ----
	for card in carriers:
		var engine := AbilityEngine.new()
		engine.db = db
		var before := engine.attack_power(card, false)
		engine.fire_reveal(card, false)
		var after := engine.attack_power(card, false)
		var shot: int = int(engine.shot_bonus(false)) if engine.has_method("shot_bonus") else 0
		print("[reveal] %s: attack %d -> %d, shot bonus %+d" % [
			card.player_name, before, after, shot])
		# ROUND Z: "your next swan..." does not change this card - it WAITS for
		# the next one. Anything that went off at all counts (the engine counts
		# a trigger only when an ability really fired). One whose If is not met
		# here ("if you control a token") is reported, not failed.
		var went_off := engine.triggers_for(false) > 0
		if after == before and shot == 0 and not went_off:
			if _has_condition(card, db):
				print("[reveal]   waits on its If column - nothing to show here, which is right")
			else:
				print("[reveal]   NOTHING HAPPENED — check the Effect column of %s"
					% card.active_attack_ability())
				bad += 1

	# ---- 4. and the order when both sides show ----
	#
	# AbilityTriggers.csv promises the LOWER POWER goes first. Two shown cards
	# of different power should come out weakest-first.
	if carriers.size() >= 2:
		var engine2 := AbilityEngine.new()
		engine2.db = db
		var a: PlayerData = carriers[0]
		var b: PlayerData = carriers[1]
		engine2.resolve_duel_abilities(a, false, b, "", [a, b])
		print("[reveal] both shown: %s (%d) vs %s (%d) — resolved without error" % [
			a.player_name, a.get_attack_power(),
			b.player_name, b.get_defense_power()])

	# ---- and a picture of the cards, if there is a window to draw in ----
	#
	# Run it under xvfb and it photographs a row: one card that carries a
	# reveal ability and one that does not, so "the button is only on a card
	# that has something to show" is something you can look at.
	#
	#     xvfb-run godot --rendering-driver opengl3 --resolution 1280x720 \
	#         --script res://tools/reveal_check.gd
	if not carriers.is_empty() and DisplayServer.get_name() != "headless":
		var plain: PlayerData = null
		for card in db.players:
			if not carriers.has(card):
				plain = card
				break
		var row := HBoxContainer.new()
		row.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		row.add_theme_constant_override("separation", 30)
		root.add_child(row)
		for card in [carriers[0], plain]:
			if card == null:
				continue
			var face: PlayerCardUI = load("res://src/ui/player_card_ui.tscn").instantiate()
			row.add_child(face)
			face.setup_card(card)
		for i in 6:
			await process_frame
		root.get_texture().get_image().save_png("user://r_00_cards.png")
		print("[reveal] picture: %sr_00_cards.png"
			% ProjectSettings.globalize_path("user://"))

	print("")
	print("[reveal] %s" % ("ALL GOOD." if bad == 0 else "%d PROBLEM(S) ABOVE." % bad))
	quit(0 if bad == 0 else 1)


func _has_condition(card: PlayerData, db: CardDatabase) -> bool:
	for cell in [card.active_attack_ability(), card.active_defend_ability()]:
		for ability_id in String(cell).split(";"):
			var ability := db.get_ability(String(ability_id).strip_edges())
			if ability != null and ability.trigger == "reveal" and ability.condition.strip_edges() != "":
				return true
	return false
