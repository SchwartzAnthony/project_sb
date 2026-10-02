extends SceneTree

# =============================================================
#  DOES EVERY WIRED ABILITY GO OFF WHEN IT SHOULD?  (round Y)
#
#      godot --headless --script res://tools/ability_check.gd
#
#  The coverage meter says a card is WIRED. This says it WORKS: for every
#  card whose Attack / Defend cell names abilities, it stages that card's
#  exact moment on a fresh engine and checks the effect landed where the
#  sentence says it should:
#
#      on_attack / on_defend    the card attacks / defends a dummy opponent
#      on_win_duel              ...and wins
#      reveal                   it is shown in the draft
#      goalie_save              it sits in the exhaust zone and its keeper saves
#      on_duel_start            it duels
#
#  and then, for an effect that WAITS ("the next fire ally"), a second card
#  of the right kind duels and the tool checks it is the one that got it.
#
#  It also checks the moment it should NOT go off: an Attack ability must
#  stay silent when the card defends (ruling F1).
#
#  Every line it prints is one card side, in words. Ends ALL GOOD or with
#  the list of what did not happen.
# =============================================================

var trouble: Array[String] = []
var checked := 0


func _initialize() -> void:
	var db := CardDatabase.get_db()
	print("")
	print("=== ABILITY CHECK ===")
	for card in db.players:
		if card.is_star() and card.attack_ability_id.strip_edges() == "":
			continue
		for slot in ["attack", "defend"]:
			var cell := card.attack_ability_id if slot == "attack" else card.defend_ability_id
			if cell.strip_edges() == "" or (card.is_star() and slot == "defend"):
				continue
			for piece in cell.split(";"):
				var ability := db.get_ability(String(piece).strip_edges())
				if ability == null or not AbilityData.trigger_is_live(ability.trigger) \
						or not AbilityData.EFFECTS.has(ability.effect):
					continue
				_check(card, slot, ability, db)
	print("")
	print("  %d ability(ies) staged." % checked)
	if trouble.is_empty():
		print("=== ALL GOOD ===")
	else:
		print("=== %d PROBLEM(S) ===" % trouble.size())
		for line in trouble:
			print("  . " + line)
	quit()


## A plain card to stand opposite, or to be "the next one".
func _dummy(name_text: String, tier: String, power: int, element: String, unit_type: String) -> PlayerData:
	var d := PlayerData.new()
	d.player_name = name_text
	d.tier = tier
	d.base_power_left = power
	d.base_power_right = power
	d.element = element
	d.unit_type = unit_type
	d.player_type = "Normal"
	return d


func _check(card: PlayerData, slot: String, ability: AbilityData, db: CardDatabase) -> void:
	checked += 1
	var engine := AbilityEngine.new(db)
	engine.begin_match()
	var me := false
	var opp := _dummy("Opponent", card.get_tier_clean(), 2, "Earth", "Normal")
	# The "next" card of the right kind, on whichever side the target names.
	var next := AbilityData.parse_next(ability.target)
	var filter := String(next.get("filter", ""))
	var mate := _dummy("NextMate", "IV", 2, "", card.unit_type)
	for piece in filter.split("+"):
		var p := String(piece).strip_edges().to_lower()
		if p in ["i", "ii", "iii", "iv"]:
			mate.tier = p.to_upper()
		elif p in ["water", "fire", "earth", "air"]:
			mate.element = p.capitalize()
		elif p != "":
			mate.unit_type = p.capitalize() if p != "unkengeister" else "Unkengeister"
	var tier_iv := _dummy("TierFour", "IV", 3, card.element, card.unit_type)
	engine.sync_field([card, mate, tier_iv], [opp])
	engine.keeper_stamina = {false: 20, true: 20}

	var role := slot
	var label := "%s %s (%s, %s)" % [card.player_name, slot.capitalize(), ability.trigger, ability.effect]
	var trig := ability.trigger
	var before_atk := 0
	var before_def := 0
	var landed := false
	var why := ""

	# ---- stage the moment ----
	match trig:
		"onattack", "ondefend", "onduelstart", "onwinduel", "onloseduel", "afterduel":
			if trig == "onattack":
				role = "attack"
			elif trig == "ondefend":
				role = "defend"
			engine.round_lineups([card, tier_iv], [opp])
			engine.begin_round()
			engine.begin_duel(card, opp)
			before_atk = engine.attack_power(card, me)
			before_def = engine.defense_power(card, me)
			if role == "attack":
				engine.resolve_duel_abilities(card, me, opp)
			else:
				engine.resolve_duel_abilities(opp, true, card)
			if trig in ["onwinduel", "afterduel"]:
				engine.resolve_duel_outcome(card, me, opp, true)
			elif trig == "onloseduel":
				engine.resolve_duel_outcome(opp, true, card, me)
		"reveal":
			engine.fire_reveal(card, me)
		"goaliesave":
			# It played a round first, in the role this side belongs to - an
			# exhausted card always has. THEN it is in the exhaust and its
			# keeper saves.
			engine.round_lineups([card], [opp])
			engine.begin_duel(card, opp)
			if slot == "attack":
				engine.resolve_duel_abilities(card, me, opp)
			else:
				engine.resolve_duel_abilities(opp, true, card)
			engine.take_pending_stamina()
			engine.round_finished()                 # card -> exhaust
			engine.after_shot(true, false)          # they shot, our keeper saved
		_:
			print("  ?  %s - no stage written for this moment yet" % label)
			return

	# ---- did it land? ----
	var stamina := engine.take_pending_stamina()
	var shot := engine.shot_bonus(me)
	match ability.effect:
		"drainstamina", "restorestamina":
			var keeper_side := ability.target.to_lower() != "own_goalie"
			if ability.effect == "restorestamina":
				keeper_side = ability.target.to_lower() != "own_goalie"
			if not next.is_empty():
				# It waits: a matching card has to duel first.
				engine.begin_duel(mate, opp)
				stamina = engine.take_pending_stamina()
			for change in stamina:
				var want_delta := -ability.value if ability.effect == "drainstamina" else ability.value
				if int(change["delta"]) == want_delta:
					landed = true
			why = "no keeper change of %d" % ability.value
		"addshotpower":
			landed = shot >= ability.value
			why = "shot bonus is %d" % shot
		"addpower", "addattack", "adddefense":
			if next.is_empty() and ability.target.to_lower() in ["self", ""]:
				var gain := engine.attack_power(card, me) - before_atk if role == "attack" \
					else engine.defense_power(card, me) - before_def
				# A card already at the ceiling (5) cannot go higher - that is
				# the rule working, not the ability failing.
				var at_cap := (before_atk if role == "attack" else before_def) >= engine.max_power
				landed = gain != 0 or (at_cap and ability.value > 0)
				why = "its own power did not move"
			elif ability.target.to_lower().begins_with("tier:"):
				landed = engine.attack_power(tier_iv, me) != tier_iv.base_power_left
				why = "the Tier IV card's attack did not move"
			elif ability.target.to_lower().begins_with("tag:") or ability.target.to_lower() in ["all_allies", "allallies"]:
				var moved := engine.attack_power(card, me) != card.base_power_left \
					or engine.defense_power(card, me) != card.base_power_right
				landed = moved or card.base_power_left >= engine.max_power
				why = "nobody it names changed"
			elif not next.is_empty():
				var target_card := card if String(next["kind"]) == "next_self" else mate
				var target_side := me
				var facing := opp
				if String(next["kind"]) == "next_enemy":
					target_card = _dummy("NextEnemy", "II", 2, "Water", "Normal")
					target_side = true
					facing = mate
				var waiting := engine.pending_count(target_side) > 0
				if target_side:
					engine.begin_duel(facing, target_card)
				else:
					engine.begin_duel(target_card, opp)
				var now := engine.attack_power(target_card, target_side)
				landed = waiting and now != target_card.base_power_left
				why = ("nothing was waiting for the next card" if not waiting
					else "%s did not change when it duelled" % target_card.player_name)
		"addcardchance_unused":
			pass
		"addcardchance":
			landed = float(engine.card_chance[true]) > 0.0
			why = "no card chance on the enemy"
		_:
			print("  ?  %s - effect not checked here" % label)
			return

	if landed:
		print("  ok %s" % label)
	else:
		trouble.append("%s: %s" % [label, why])
		print("  !! %s - %s" % [label, why])

	# ---- and the moment it must NOT go off (ruling F1) ----
	if trig == "onattack" or (trig == "onwinduel" and slot == "attack" and ability.effect == "addshotpower"):
		var quiet := AbilityEngine.new(db)
		quiet.begin_match()
		quiet.sync_field([card], [opp])
		quiet.round_lineups([card], [opp])
		quiet.begin_round()
		quiet.begin_duel(card, opp)
		quiet.resolve_duel_abilities(opp, true, card)       # card DEFENDS
		quiet.resolve_duel_outcome(card, me, opp, true)
		# BY ID: its Defend ability is SUPPOSED to go off here, so only this
		# ability waiting, or a shot bonus when its Defend side gives none,
		# counts as the Attack side going off.
		var fired := quiet.pending_ids().has(ability.id)
		if ability.effect == "addshotpower" and not _defend_gives_shot(card, db):
			fired = fired or quiet.shot_bonus(me) > 0
		if fired:
			trouble.append("%s: its ATTACK ability went off while it was DEFENDING" % label)
			print("  !! %s - went off while defending (ruling F1)" % label)


func _defend_gives_shot(card: PlayerData, db: CardDatabase) -> bool:
	for piece in card.defend_ability_id.split(";"):
		var other := db.get_ability(String(piece).strip_edges())
		if other != null and other.effect == "addshotpower":
			return true
	return false
