extends SceneTree

# =============================================================
#  DOES EVERY WIRED ABILITY GO OFF WHEN IT SHOULD?  (round Y, round Z)
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
#      on_shot                  it shoots                          (round Z)
#
#  ROUND Z: BEFORE THE MOMENT, ITS If AND ITS Cost ARE MADE TRUE. A card that
#  says "Consume 3 Ore:" is given 3 Ore; "If you control a token" gets a Rose
#  token on the field; "If this has a burn counter" gets one. Then the check
#  is: did it go off, and did the Ore get spent?
#
#  Then for an effect that WAITS ("the next fire ally"), a second card of the
#  right kind duels and the tool checks it is the one that got it.
#
#  It also checks the moment it should NOT go off: an Attack ability must
#  stay silent when the card defends (ruling F1).
#
#  AND THE EMBLEMS (round Z). Five stories, one per Emblem whose Basic side
#  now plays: Zepar's swans, Sallos's songs, Belphegor's victory counters,
#  Buer's counter, Gremory's Rose tokens.
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
	print("--- the Emblems' Basic sides ---")
	_check_emblems(db)
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


## A dummy that matches a filter like "water+II", "swan", "token".
func _matching(name_text: String, filter: String, unit_type: String) -> PlayerData:
	var d := _dummy(name_text, "IV", 2, "", unit_type)
	for piece in filter.split("+"):
		var p := String(piece).strip_edges().to_lower()
		if p in ["i", "ii", "iii", "iv"]:
			d.tier = p.to_upper()
		elif p in ["water", "fire", "earth", "air"]:
			d.element = p.capitalize()
		elif p == "token":
			d.extra_tags = PackedStringArray(["rose", "token"])
		elif p == "swan":
			pass    # made a swan on the engine, below
		elif p != "":
			d.unit_type = p.capitalize() if p != "unkengeister" else "Unkengeister"
	return d


## MAKE ITS If AND ITS Cost TRUE before the moment (round Z).
func _prepare(engine: AbilityEngine, card: PlayerData, opp: PlayerData, ability: AbilityData) -> void:
	if ability.cost_kind == "ore":
		engine.add_to_pool(false, "ore", ability.cost_amount)
	for term in AbilityData.condition_terms(ability.condition):
		match String(term["word"]):
			"hastoken", "tokensatleast":
				var need := maxi(1, int(String(term["arg"]))) if String(term["arg"]) != "" else 1
				var tokens: Array = []
				for i in need:
					var t := _dummy("Rose %d" % i, "I", 1, "Water", "Lorelei")
					t.extra_tags = PackedStringArray(["rose", "token"])
					tokens.append(t)
				engine.sync_field(tokens, [])
			"isswan":
				engine.make_kind(card, false, "swan")
			"hascounter":
				engine.put_counter(card, false, String(term["arg"]) if String(term["arg"]) != "" else "burn")
			"enemyhascounter":
				engine.put_counter(opp, true, String(term["arg"]) if String(term["arg"]) != "" else "burn")
			"orethisround":
				engine.add_to_pool(false, "ore", 1)
			"touchedball", "touchedbeforeplaymaker":
				engine.set_touched(false, [card])
			"mining":
				engine.set_mining(false, [_dummy("Miner", "I", 1, "Earth", "Bergmännlein")], 4)
			"fused":
				engine._fused_with[engine._k(card, false)] = _dummy("Partner", card.get_tier_clean(), 1, "Fire", card.unit_type)
			"revealedwas":
				# C5 (Flauros): a card of that kind in the exhaust to reveal.
				var shown := _matching("InExhaust", String(term["arg"]), card.unit_type)
				engine.sync_field([shown], [])
				engine._move(shown, false, "exhaust")
	# C4: victory counters to count.
	if ability.effect == "powerfromcount" and ability.effect_arg == "victory":
		engine.add_to_pool(false, "victory", 2)


func _check(card: PlayerData, slot: String, ability: AbilityData, db: CardDatabase) -> void:
	checked += 1
	var engine := AbilityEngine.new(db)
	engine.begin_match()
	var me := false
	var opp := _dummy("Opponent", card.get_tier_clean(), 2, "Earth", "Normal")
	# A swap between two equal powers changes nothing to see (round AD).
	if ability.effect == "swappower" and card.get_attack_power() == 2:
		opp.base_power_left = 1
		opp.base_power_right = 1
	# The "next" card of the right kind, on whichever side the target names.
	var next := AbilityData.parse_next(ability.target)
	var filter := String(next.get("filter", ""))
	var mate := _matching("NextMate", filter, card.unit_type)
	if filter.contains("swan"):
		engine.make_kind(mate, false, "swan")
	var tier_iv := _dummy("TierFour", "IV", 3, card.element, card.unit_type)
	engine.sync_field([card, mate, tier_iv], [opp])
	engine.keeper_stamina = {false: 20, true: 20}
	var is_ally := String(next.get("kind", "")) == "ally"

	var role := slot
	var label := "%s %s (%s, %s)" % [card.player_name, slot.capitalize(), ability.trigger, ability.effect]
	var trig := ability.trigger
	var before_atk := 0
	var before_def := 0
	var opp_before := 0
	var landed := false
	var why := ""
	var ore_before := 0

	# ---- stage the moment ----
	match trig:
		"onattack", "ondefend", "onduelstart", "onwinduel", "onloseduel", "afterduel":
			if trig == "onattack":
				role = "attack"
			elif trig == "ondefend":
				role = "defend"
			var lineup: Array = [card, tier_iv]
			if is_ally:
				lineup.append(mate)
			engine.round_lineups(lineup, [opp])
			engine.begin_round()
			_prepare(engine, card, opp, ability)
			ore_before = engine.pool(me, "ore")
			engine.begin_duel(card, opp)
			# C4: an enemy buff for negate_buff to take away.
			if ability.effect == "negatebuff":
				engine._set_power(opp, true, opp.get_attack_power() + 1, null)
			before_atk = engine.attack_power(card, me)
			before_def = engine.defense_power(card, me)
			opp_before = engine.defense_power(opp, true) if role == "attack" else engine.attack_power(opp, true)
			if role == "attack":
				engine.resolve_duel_abilities(card, me, opp)
			else:
				engine.resolve_duel_abilities(opp, true, card)
			if trig in ["onwinduel", "afterduel"]:
				engine.resolve_duel_outcome(card, me, opp, true)
			elif trig == "onloseduel":
				engine.resolve_duel_outcome(opp, true, card, me)
		"reveal":
			engine.begin_round()
			_prepare(engine, card, opp, ability)
			ore_before = engine.pool(me, "ore")
			engine.fire_reveal(card, me)
		"contemplation":
			# It plays its round and goes to the exhaust - that is the moment.
			engine.round_lineups([card], [opp])
			engine.begin_round()
			_prepare(engine, card, opp, ability)
			ore_before = engine.pool(me, "ore")
			engine.begin_duel(card, opp)
			if slot == "attack":
				engine.resolve_duel_abilities(card, me, opp)
			else:
				engine.resolve_duel_abilities(opp, true, card)
			engine.take_pending_stamina()
			engine.round_finished()
		"whileinexhaust", "endofcycle", "aftercombat":
			# It plays a round first, in its own role, and goes to the exhaust.
			engine.round_lineups([card], [opp])
			engine.begin_round()
			engine.begin_duel(card, opp)
			if slot == "attack":
				engine.resolve_duel_abilities(card, me, opp)
			else:
				engine.resolve_duel_abilities(opp, true, card)
			engine.round_finished()
			engine.take_pending_stamina()
			# Then the moment, with it sitting in the exhaust.
			engine.begin_round()
			_prepare(engine, card, opp, ability)
			opp_before = opp.base_power_left
			match trig:
				"whileinexhaust":
					engine.round_lineups([mate], [opp])
					engine.begin_duel(mate, opp)
				"endofcycle":
					engine.begin_cycle()
				"aftercombat":
					engine.round_lineups([mate], [opp])
					engine.round_finished()
		"onshot":
			engine.begin_round()
			_prepare(engine, card, opp, ability)
			engine.fire_on_shot(card, me)
		"goaliesave":
			# It played a round first, in the role this side belongs to - an
			# exhausted card always has. THEN it is in the exhaust and its
			# keeper saves.
			engine.round_lineups([card], [opp])
			engine.begin_round()
			_prepare(engine, card, opp, ability)
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
	var target_flat := CardDatabase._normalise(ability.target)
	match ability.effect:
		"drainstamina", "restorestamina":
			if not next.is_empty() and not is_ally:
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
			if next.is_empty() and target_flat in ["self", ""]:
				var gain := engine.attack_power(card, me) - before_atk if role == "attack" \
					else engine.defense_power(card, me) - before_def
				# A card already at the ceiling (5) cannot go higher - that is
				# the rule working, not the ability failing.
				var at_cap := (before_atk if role == "attack" else before_def) >= engine.max_power
				landed = gain != 0 or (at_cap and ability.value > 0)
				why = "its own power did not move"
			elif next.is_empty() and (target_flat == "opponent" or ability.target.to_lower().begins_with("enemytier") \
					or ability.target.to_lower().begins_with("enemy_tier")):
				var opp_now := engine.defense_power(opp, true) if role == "attack" else engine.attack_power(opp, true)
				landed = opp_now != opp_before or (opp_before == 0 and ability.value < 0)
				why = "the enemy's power did not move (%d)" % opp_now
			elif ability.target.to_lower().begins_with("tier:"):
				landed = engine.attack_power(tier_iv, me) != tier_iv.base_power_left
				why = "the Tier IV card's attack did not move"
			elif ability.target.to_lower().begins_with("tag:") or target_flat == "allallies":
				var moved := engine.attack_power(card, me) != card.base_power_left \
					or engine.defense_power(card, me) != card.base_power_right
				landed = moved or card.base_power_left >= engine.max_power
				why = "nobody it names changed"
			elif is_ally:
				landed = engine.attack_power(mate, me) != mate.base_power_left
				why = "%s in this round's line-up did not change" % mate.player_name
			elif not next.is_empty():
				var target_card := card if String(next["kind"]) == "next_self" else mate
				var target_side := me
				var facing := opp
				if String(next["kind"]) == "next_enemy":
					target_card = _matching("NextEnemy", filter, "Normal")
					target_side = true
					facing = mate
				var waiting := engine.pending_count(target_side) > 0
				if trig == "whileinexhaust":
					# Round AB: from the exhaust it lands in the duel that just
					# began - on the matching card in it (mate, or opp).
					waiting = true
					if target_side:
						target_card = opp
				elif target_side:
					engine.begin_duel(facing, target_card)
				else:
					engine.begin_duel(target_card, opp)
				var now := engine.attack_power(target_card, target_side)
				landed = waiting and now != target_card.base_power_left
				why = ("nothing was waiting for the next card" if not waiting
					else "%s did not change when it duelled" % target_card.player_name)
		"addcardchance":
			landed = float(engine.card_chance[true]) > 0.0
			why = "no card chance on the enemy"
		"addcounter":
			var kind := ability.effect_arg
			if not next.is_empty():
				engine.begin_duel(mate, opp)
				landed = engine.counter(mate, me, kind) != 0
				why = "%s got no %s counter when it duelled" % [mate.player_name, kind]
			elif target_flat == "side":
				landed = engine.pool(me, kind) > 0
				why = "no %s on the side" % kind
			else:
				landed = engine.counter(card, me, kind) != 0
				why = "no %s counter on it" % kind
		"removecounter":
			landed = engine.counter(card, me, ability.effect_arg) == 0
			why = "the counter is still there"
		"gainore":
			landed = engine.pool(me, "ore") >= ability.value
			why = "the Ore pool holds %d" % engine.pool(me, "ore")
		# ---- round AA, C3: the keeper and the referee ----
		"goaliechance":
			var keeper_side := CardDatabase._normalise(ability.target) != "owngoalie"
			var shift := engine.keeper_shift(keeper_side)
			landed = is_equal_approx(shift, float(ability.value))
			why = "the %s keeper's shift is %+.0f%%, not %+d%%" % ["enemy" if keeper_side else "own", shift, ability.value]
		"goalieshield", "removeshields":
			var want := "shield" if ability.effect == "goalieshield" else "clear_shields"
			for change in stamina:
				if (change as Dictionary).has(want):
					landed = true
			why = "no %s change reached a keeper" % want
		"foulheat":
			var heat := engine.take_heat(true)
			landed = heat >= float(ability.value)
			why = "the referee's bar against them got %.1f" % heat
		"foulchance":
			landed = engine.foul_shift(true) >= float(ability.value)
			why = "their foul chance moved %+.0f%%" % engine.foul_shift(true)
		"foulcoinflip":
			landed = engine.coin_flips(me) == 1
			why = "no coin flip banked"
		# ---- round AB, C4: bending the duel ----
		"switchtodefender":
			var flip := engine.take_switch()
			landed = not flip.is_empty() and flip["card"] == card
			why = "no switch to defender happened"
		"alwaysdefending":
			landed = engine.is_always_defending(card, me)
			why = "it does not count as defending"
		"changepriority", "givepriority", "forceability", "negateability", "uncounterable", \
		"removecondition", "swappower", "setpowerfromtoken", "negatebuff", "powerfromcount", "useenemypower":
			var who: PlayerData = card
			var who_side := me
			var tflat := CardDatabase._normalise(ability.target)
			if tflat == "opponent" or ability.target.to_lower().begins_with("enemytier"):
				who = opp
				who_side = true
			if not next.is_empty() and not is_ally and trig == "whileinexhaust":
				who = opp if String(next["kind"]) == "next_enemy" else mate
				who_side = String(next["kind"]) == "next_enemy"
			elif not next.is_empty() and not is_ally:
				who = card if String(next["kind"]) == "next_self" else mate
				who_side = me
				if String(next["kind"]) == "next_enemy":
					who = _matching("NextEnemy", filter, "Normal")
					who_side = true
					engine.begin_duel(mate, who)
				else:
					engine.begin_duel(who, opp)
				# A duel buff from the landing is checked before it expires.
			elif is_ally:
				who = mate
			match ability.effect:
				"changepriority":
					landed = engine.priority_mod(who, who_side) == ability.value
				"givepriority":
					landed = engine.priority_mod(who, who_side) <= -100
				"forceability":
					landed = engine.forced_side(who, who_side) != ""
				"negateability":
					landed = engine.negated_side(who, who_side) != ""
				"uncounterable":
					landed = engine.is_uncounterable(who, who_side)
				"removecondition":
					landed = engine.ignores_if(who, who_side)
				"swappower", "setpowerfromtoken", "useenemypower", "powerfromcount":
					var now := engine.attack_power(who, who_side) if (who == card and role == "attack") or who_side \
						else engine.defense_power(who, who_side)
					landed = now != who.get_attack_power() or ability.effect == "useenemypower" \
						or (ability.effect == "powerfromcount" and now == _count_power(engine, db, ability, who, who_side))
				"negatebuff":
					landed = engine.attack_power(opp, true) == opp.get_attack_power() \
						and engine.defense_power(opp, true) == opp.get_defense_power()
			why = "%s did not happen to %s" % [ability.effect, who.player_name]
		"createtoken":
			engine.round_finished()
			var swaps := engine.take_swaps()
			landed = not swaps.is_empty() and (swaps[0]["new"] as PlayerData).is_token()
			why = "no token took its place"
			if landed and engine.zone_of(card, 0) != AbilityEngine.EXHAUST:
				landed = false
				why = "the card it replaced is not in the exhaust"
		_:
			print("  ?  %s - effect not checked here" % label)
			return

	# ---- and the Ore was spent ----
	if landed and ability.cost_kind == "ore" and ability.effect != "gainore":
		if engine.pool(me, "ore") != ore_before - ability.cost_amount and trig != "onshot":
			landed = false
			why = "it went off but %d Ore was not spent (pool %d, was %d)" % [
				ability.cost_amount, engine.pool(me, "ore"), ore_before]

	if landed:
		print("  ok %s" % label)
	else:
		trouble.append("%s: %s" % [label, why])
		print("  !! %s - %s" % [label, why])

	# ---- and with no Ore it must NOT go off (round Z) ----
	if ability.cost_kind == "ore" and trig in ["onattack", "ondefend", "onduelstart"]:
		var broke := AbilityEngine.new(db)
		broke.begin_match()
		broke.sync_field([card], [opp])
		broke.round_lineups([card], [opp])
		broke.begin_round()
		broke.begin_duel(card, opp)
		var trig_before := broke.triggers_for(me)
		if trig == "ondefend":
			broke.resolve_duel_abilities(opp, true, card)
		else:
			broke.resolve_duel_abilities(card, me, opp)
		var did := broke.triggers_for(me) - trig_before
		if did > 0 and broke.pool(me, "ore") == 0 and not broke.take_pending_stamina().is_empty():
			trouble.append("%s: went off with no Ore to pay for it" % label)
			print("  !! %s - went off with no Ore" % label)

	# ---- and the moment it must NOT go off (ruling F1) ----
	if trig == "onattack" or (trig == "onwinduel" and slot == "attack" and ability.effect == "addshotpower"):
		var quiet := AbilityEngine.new(db)
		quiet.begin_match()
		quiet.sync_field([card], [opp])
		quiet.round_lineups([card], [opp])
		quiet.begin_round()
		_prepare(quiet, card, opp, ability)
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


# =============================================================
#  THE EMBLEMS (round Z)
# =============================================================

func _badge(star: String) -> ClassBook.Emblem:
	for klass in ["Lorelei", "Rauhnacht-Feuergeister", "Bergmännlein", "Unkengeister"]:
		for badge in EmblemBook.for_class(klass):
			if CardDatabase._normalise(badge.star) == CardDatabase._normalise(star):
				return badge
	return null


func _say(ok: bool, label: String, why: String) -> void:
	checked += 1
	if ok:
		print("  ok %s" % label)
	else:
		trouble.append("%s: %s" % [label, why])
		print("  !! %s - %s" % [label, why])


func _events_named(engine: AbilityEngine, event: String) -> int:
	var n := 0
	for e in engine.take_events():
		if String(e["event"]) == event:
			n += 1
	return n


func _check_emblems(db: CardDatabase) -> void:
	var opp := _dummy("Opponent", "I", 1, "Earth", "Normal")
	_check_asks(db)
	_check_c4(db)
	_check_c5(db)
	_check_c6(db)
	_check_c7(db)
	_check_c8(db)
	_check_ag(db)

	# ---- ZEPAR: a water unit revealed becomes a Swan, and a Swan is +1 ----
	var zepar := _badge("Zepar")
	if zepar == null or zepar.basic_ability == "":
		_say(false, "Zepar's Emblem", "no Basic Ability in Lorelei Emblems.csv")
	else:
		var e := AbilityEngine.new(db)
		e.begin_match()
		var water := _dummy("Wave", "I", 1, "Water", "Lorelei")
		e.set_emblems(false, [zepar])
		e.sync_field([water], [opp])
		e.begin_round()
		var offered := e.emblem_reveal_for(water, false)
		e.fire_reveal(water, false)
		var swan := e.is_kind(water, false, "swan")
		e.round_lineups([water], [opp])
		e.begin_duel(water, opp)
		var before := e.attack_power(water, false)
		e.resolve_duel_abilities(water, false, opp)
		_say(offered and swan and e.attack_power(water, false) == before + 1
			and _events_named(e, "swan_made") == 1,
			"Zepar's Emblem: reveal makes a Swan (SHOW offered), a Swan is +1",
			"offered %s, swan %s, power %d -> %d" % [offered, swan, before, e.attack_power(water, false)])

	# ---- SALLOS: a water unit that defends and wins marks the enemy ----
	var sallos := _badge("Sallos")
	if sallos != null and sallos.basic_ability != "":
		var e := AbilityEngine.new(db)
		e.begin_match()
		var water := _dummy("Shore", "II", 3, "Water", "Lorelei")
		e.set_emblems(false, [sallos])
		e.sync_field([water], [opp])
		e.round_lineups([water], [opp])
		e.begin_round()
		e.begin_duel(water, opp)
		e.resolve_duel_abilities(opp, true, water)          # water DEFENDS
		e.resolve_duel_outcome(water, false, opp, true)      # and wins
		var songs := e.counter(opp, true, "song")
		var facts_ok := false
		for ev in e.take_events():
			if String(ev["event"]) == "counter_placed" and String(ev["facts"].get("class", "")) == "Lorelei":
				facts_ok = true
		_say(songs == 1 and facts_ok, "Sallos's Emblem: defend and win puts a Song on the enemy",
			"songs %d, event with class Lorelei %s" % [songs, facts_ok])

	# ---- BELPHEGOR: fire wins put victory counters on the side, two a cycle ----
	var belphegor := _badge("Belphegor")
	if belphegor != null and belphegor.basic_ability != "":
		var e := AbilityEngine.new(db)
		e.begin_match()
		var fire := _dummy("Ember", "III", 3, "Fire", "Rauhnacht-Feuergeister")
		e.set_emblems(false, [belphegor])
		e.sync_field([fire], [opp])
		for i in 3:
			e.begin_round()
			e.resolve_duel_outcome(fire, false, opp, true)
		var first_cycle := e.pool(false, "victory")
		e.begin_cycle()
		e.resolve_duel_outcome(fire, false, opp, true)
		_say(first_cycle == 2 and e.pool(false, "victory") == 3,
			"Belphegor's Emblem: a fire win is a victory counter, only two per cycle",
			"cycle one %d (want 2), after a new cycle %d (want 3)" % [first_cycle, e.pool(false, "victory")])

	# ---- BUER: a fire unit that receives a counter is +1 in that combat ----
	var buer := _badge("Buer")
	if buer != null and buer.basic_ability != "":
		var e := AbilityEngine.new(db)
		e.begin_match()
		var fire := _dummy("Cinder", "II", 2, "Fire", "Rauhnacht-Feuergeister")
		e.set_emblems(false, [buer])
		e.sync_field([fire], [opp])
		e.round_lineups([fire], [opp])
		e.begin_round()
		var before := e.attack_power(fire, false)
		e.put_counter(fire, false, "burn")
		e.begin_duel(fire, opp)                 # the +1 was waiting for its combat
		var now := e.attack_power(fire, false)
		e.put_counter(fire, false, "burn")      # a second counter, same cycle
		e.begin_duel(fire, opp)
		var again := e.attack_power(fire, false)
		# Round AG: a burn counter is also worth counter_power_burn by itself.
		var burn := int(round(db.tune_float("counter_power_burn", 0.0)))
		_say(now == before + 1 + burn and again == before + 2 * burn,
			"Buer's Emblem: a counter received is +1 in combat, once per cycle",
			"power %d -> %d, second time %d" % [before, now, again])

	# ---- GREMORY: two water units into the exhaust make a Rose Unit token ----
	var gremory := _badge("Gremory")
	if gremory != null and gremory.basic_ability != "":
		var e := AbilityEngine.new(db)
		e.begin_match()
		var a := _dummy("Brook", "I", 0, "Water", "Lorelei")
		var b := _dummy("Rill", "II", 2, "Water", "Lorelei")
		var tier_one := _dummy("Spring", "I", 1, "Water", "Lorelei")
		e.set_emblems(false, [gremory])
		e.sync_field([a, b, tier_one], [opp])
		e.begin_round()
		e.round_lineups([a, b], [opp])
		e.round_finished()                       # two water units to the exhaust
		var swaps := e.take_swaps()
		var made := swaps.size() == 1 and (swaps[0]["old"] as PlayerData) == tier_one \
			and (swaps[0]["new"] as PlayerData).is_token()
		var token: PlayerData = swaps[0]["new"] if swaps.size() == 1 else null
		var held := e.zone_of(tier_one, 0) == AbilityEngine.EXHAUST
		var traded := false
		for ev in e.take_events():
			if String(ev["event"]) == "token_made" and String(ev["facts"].get("tier", "")) == "I" \
					and String(ev["facts"].get("class", "")) == "Lorelei":
				traded = true
		e.begin_cycle()
		var still_held := e.zone_of(tier_one, 0) == AbilityEngine.EXHAUST
		var token_power := token.get_attack_power() if token != null else -1
		_say(made and held and still_held and traded and token_power == 1 and e.token_count(false) == 1,
			"Gremory's Emblem: a Rose Unit token takes a water Tier I's place; it stays in the exhaust",
			"made %s, held %s, still held after the cycle %s, event %s, power %d, tokens %d" % [
				made, held, still_held, traded, token_power, e.token_count(false)])
		# Once a round for the side: a second pair in the SAME round makes nothing.
		var c := _dummy("Tarn", "III", 2, "Water", "Lorelei")
		var d := _dummy("Mere", "IV", 3, "Water", "Lorelei")
		var tier_one_b := _dummy("Well", "I", 2, "Water", "Lorelei")
		e.sync_field([c, d, tier_one_b], [])
		e.round_lineups([c, d], [opp])
		e.round_finished()
		_say(e.take_swaps().is_empty(), "Gremory's Emblem: once a round", "a second token in one round")
		e.begin_round()
		e.round_lineups([c, d], [opp])
		e.round_finished()
		_say(e.take_swaps().size() == 1, "Gremory's Emblem: and again next round", "no token in the next round")


# =============================================================
#  ASKING YOU (round AA) - the answers change what happens
# =============================================================

func _check_asks(db: CardDatabase) -> void:
	var opp := _dummy("Opponent", "I", 1, "Earth", "Normal")
	# ---- Ore: asked before the duel; NO keeps the Ore ----
	var erich: PlayerData = null
	for card in db.players:
		if card.player_name == "Erich":
			erich = card
	if erich != null:
		for answer_yes in [true, false]:
			var e := AbilityEngine.new(db)
			e.begin_match()
			e.interactive = {false: true, true: false}
			e.sync_field([erich], [opp])
			e.round_lineups([erich], [opp])
			e.begin_round()
			e.add_to_pool(false, "ore", 5)
			e.begin_duel(erich, opp)
			var asked := e.duel_questions(erich, false, "defend", opp, true)
			for a in asked:
				e.consent(erich, false, a.id, answer_yes)
			e.resolve_duel_abilities(opp, true, erich)
			var spent := 5 - e.pool(false, "ore")
			_say(asked.size() == 1 and spent == (2 if answer_yes else 0),
				"Ore is asked before the duel, and %s" % ("YES spends it" if answer_yes else "NO keeps it"),
				"asked %d question(s), %d Ore spent" % [asked.size(), spent])
	# ---- Zepar: asked AFTER the reveal; no = no Swan ----
	var zepar := _badge("Zepar")
	if zepar != null:
		for answer_yes in [true, false]:
			var e := AbilityEngine.new(db)
			e.begin_match()
			e.interactive = {false: true, true: false}
			var water := _dummy("Wave", "I", 1, "Water", "Lorelei")
			e.set_emblems(false, [zepar])
			e.sync_field([water], [opp])
			e.fire_reveal(water, false)
			var before := e.is_kind(water, false, "swan")
			var asks := e.take_asks()
			for a in asks:
				e.answer(a, answer_yes)
			_say(not before and asks.size() == 1 and e.is_kind(water, false, "swan") == answer_yes,
				"Zepar asks before the Swan, and %s" % ("yes transforms" if answer_yes else "no does not"),
				"swan before the answer %s, %d ask(s), swan after %s" % [before, asks.size(), e.is_kind(water, false, "swan")])
	# ---- Gremory: YOU pick which unit becomes the Rose ----
	var gremory := _badge("Gremory")
	if gremory != null:
		var e := AbilityEngine.new(db)
		e.begin_match()
		e.interactive = {false: true, true: false}
		var a := _dummy("Brook", "I", 0, "Water", "Lorelei")
		var b := _dummy("Rill", "II", 2, "Water", "Lorelei")
		var weak := _dummy("Spring", "I", 0, "Water", "Lorelei")
		var strong := _dummy("Fountain", "I", 2, "Water", "Lorelei")
		e.set_emblems(false, [gremory])
		e.sync_field([a, b, weak, strong], [opp])
		e.begin_round()
		e.round_lineups([a, b], [opp])
		e.round_finished()
		var asks := e.take_asks()
		var picked_ok := false
		for ask in asks:
			if String(ask["kind"]) == "pick":
				picked_ok = (ask["options"] as Array).has(strong)
				e.answer(ask, strong)
		var swaps := e.take_swaps()
		_say(picked_ok and swaps.size() == 1 and swaps[0]["old"] == strong,
			"Gremory: you choose which unit the Rose replaces",
			"asks %d, swaps %d" % [asks.size(), swaps.size()])
		# ---- THEIR goal leaves it; YOUR goal sends it home (Q005) ----
		e.after_shot(true, true)
		var stays := e.take_swaps().is_empty() and e.token_count(false) == 1
		e.after_shot(false, true)
		var back := e.take_swaps()
		_say(stays and back.size() == 1 and back[0]["new"] == strong and e.token_count(false) == 0 \
				and e.zone_of(strong, 0) != "",
			"Your Rose goes home when YOU score (not when they do), and the unit walks back on",
			"stayed after their goal %s, %d swap(s) back, tokens left %d" % [stays, back.size(), e.token_count(false)])
	# ---- F2: the side that stays up in the exhaust ----
	var both: PlayerData = null
	for card in db.players:
		if both == null and _outside(card.active_attack_ability(), db) and _outside(card.active_defend_ability(), db):
			both = card
	if both != null:
		var e := AbilityEngine.new(db)
		e.begin_match()
		e.interactive = {false: true, true: false}
		e.sync_field([both], [opp])
		e.round_lineups([both], [opp])
		e.begin_round()
		e.begin_duel(both, opp)
		e.resolve_duel_abilities(both, false, opp)        # it attacked
		e.round_finished()
		var asks := e.take_asks()
		var side_ask: Dictionary = {}
		for ask in asks:
			if String(ask["kind"]) == "side":
				side_ask = ask
		if not side_ask.is_empty():
			e.answer(side_ask, "defend")
		_say(not side_ask.is_empty() and e.side_up(both, false) == "defend",
			"%s: you choose which side stays up in the exhaust (F2)" % both.player_name,
			"asked %s, side up now %s" % [not side_ask.is_empty(), e.side_up(both, false)])
		e.begin_cycle()
		_say(e.side_up(both, false) != "defend" or e.cycle_number == 1,
			"...and it is asked again next cycle", "the choice outlived its cycle")


func _outside(cell: String, db: CardDatabase) -> bool:
	for piece in cell.split(";"):
		var a := db.get_ability(String(piece).strip_edges())
		if a != null and AbilityEngine.OUTSIDE_DUEL.has(a.trigger):
			return true
	return false


# =============================================================
#  BENDING THE DUEL (round AB, C4) - whole duels, not one row
# =============================================================

func _find(db: CardDatabase, name_text: String) -> PlayerData:
	for card in db.players:
		if card.player_name == name_text:
			return card
	return null


## A row that, on that moment, gives ITSELF +power - for a test opponent.
func _self_buff_row(db: CardDatabase, trigger: String) -> String:
	for id_text in db.abilities.keys():
		var a: AbilityData = db.abilities[id_text]
		if a.trigger == trigger and a.effect == "addpower" and a.value > 0 \
				and CardDatabase._normalise(a.target) == "self" and a.condition == "" and a.cost_kind == "":
			return a.id
	return ""


func _check_c4(db: CardDatabase) -> void:
	print("--- bending the duel (C4) ---")
	# ---- Luis switches to being the defender ----
	var luis := _find(db, "Luis")
	if luis != null:
		var e := AbilityEngine.new(db)
		e.begin_match()
		var opp := _dummy("Opp", luis.get_tier_clean(), 2, "Earth", "Normal")
		e.sync_field([luis], [opp])
		e.round_lineups([luis], [opp])
		e.begin_round()
		e.begin_duel(luis, opp)
		e.resolve_duel_abilities(luis, false, opp)
		var flip := e.take_switch()
		_say(not flip.is_empty() and flip["card"] == luis and e.side_up(luis, false) == "defend",
			"Luis attacks, then switches to being the DEFENDER (Q047)",
			"switch %s, role now %s" % [not flip.is_empty(), e.side_up(luis, false)])
	# ---- René negates an ability that went BEFORE him: its buff is taken back ----
	var rene := _find(db, "René")
	var buff_row := _self_buff_row(db, "ondefend")
	if rene != null and buff_row != "":
		var e := AbilityEngine.new(db)
		e.begin_match()
		var opp := _dummy("Shield-bearer", rene.get_tier_clean(), 1, "Earth", "Normal")
		opp.defend_ability_id = buff_row
		e.sync_field([rene], [opp])
		e.round_lineups([rene], [opp])
		e.begin_round()
		e.put_counter(rene, false, "burn")
		e.begin_duel(rene, opp)
		e.resolve_duel_abilities(rene, false, opp)
		_say(e.defense_power(opp, true) == opp.get_defense_power() and e.negated_side(opp, true) == "defend",
			"René negates the enemy ability - the buff it gave itself is taken back",
			"enemy defends with %d (printed %d), negated %s" % [e.defense_power(opp, true), opp.get_defense_power(), e.negated_side(opp, true)])
	# ---- Dominik forces the defender to use its ATTACK side ----
	var dominik := _find(db, "Dominik")
	var atk_row := _self_buff_row(db, "onattack")
	if dominik != null and atk_row != "":
		var e := AbilityEngine.new(db)
		e.begin_match()
		var opp := _dummy("Forced", dominik.get_tier_clean(), 4, "Earth", "Normal")
		opp.base_power_left = 3
		opp.base_power_right = 3
		opp.attack_ability_id = atk_row
		e.sync_field([dominik], [opp])
		e.round_lineups([dominik], [opp])
		e.begin_round()
		e.add_to_pool(false, "ore", 2)
		e.begin_duel(dominik, opp)
		e.resolve_duel_abilities(dominik, false, opp)
		_say(e.forced_side(opp, true) == "attack" and e.defense_power(opp, true) > opp.get_defense_power(),
			"Dominik forces the defender to use its ATTACK side - and it does",
			"forced %s, enemy %d (printed %d)" % [e.forced_side(opp, true), e.defense_power(opp, true), opp.get_defense_power()])
	# ---- give priority from the exhaust re-orders the stack ----
	var leonhard := _find(db, "Leonhard")
	if leonhard != null:
		var e := AbilityEngine.new(db)
		e.begin_match()
		var water2 := _dummy("Brook", "II", 3, "Water", "Lorelei")
		var opp := _dummy("Opp", "II", 1, "Earth", "Normal")
		e.sync_field([leonhard, water2], [opp])
		e.round_lineups([leonhard], [opp])
		e.begin_round()
		e.begin_duel(leonhard, opp)
		e.resolve_duel_abilities(opp, true, leonhard)       # Leonhard defends -> plays his Defend side
		e.round_finished()                                    # -> exhaust
		e.begin_round()
		e.round_lineups([water2], [opp])
		e.begin_duel(water2, opp)                             # while in exhaust: next Tier II water first
		_say(e.priority_mod(water2, false) <= -100,
			"Leonhard in the exhaust: your Tier II water unit resolves FIRST",
			"priority change %d" % e.priority_mod(water2, false))


## ROUND AC (C5): the zones in action, each played as a little story.
func _check_c5(db: CardDatabase) -> void:
	print("--- the zones in action (C5) ---")
	# ---- Ralf swaps in from the exhaust (R17), +1, once per cycle ----
	var ralf := _find(db, "Ralf")
	if ralf != null:
		var e := AbilityEngine.new(db)
		e.begin_match()
		var mate := _dummy("Mate", "I", 1, "Air", "Unkengeister")
		var opp := _dummy("Opp", "I", 1, "Earth", "Normal")
		e.sync_field([ralf, mate], [opp])
		e.round_lineups([ralf], [opp])
		e.begin_round()
		e.begin_duel(ralf, opp)
		e.resolve_duel_abilities(ralf, false, opp)
		e.round_finished()                             # Ralf -> exhaust
		e.begin_round()
		e.round_lineups([mate], [opp])
		var options := e.exhaust_swap_options(false, mate)
		_say(options.has(ralf), "Ralf in the exhaust lights up before the Tier I duel", "options %d" % options.size())
		if options.has(ralf):
			e.do_exhaust_swap(ralf, mate, false)
			e.begin_duel(ralf, opp)
			_say(e.zone_of(mate, 0) == "exhaust" and e.zone_of(ralf, 0) == "combat"
				and e.attack_power(ralf, false) == mini(ralf.get_attack_power() + 1, 5),
				"Ralf swaps in: the Tier I he replaced goes to the exhaust, Ralf fights with +1",
				"mate %s, Ralf %s, power %d (printed %d)" % [e.zone_of(mate, 0), e.zone_of(ralf, 0),
					e.attack_power(ralf, false), ralf.get_attack_power()])
			e.round_finished()
			e.begin_round()
			var again := e.exhaust_swap_options(false, _dummy("Other", "I", 1, "Air", "Unkengeister"))
			_say(not again.has(ralf), "...and not again this cycle (once per cycle)", "options %d" % again.size())
	# ---- Ingrid: the next card picked is revealed too ----
	var ingrid := _find(db, "Ingrid")
	if ingrid != null:
		var e := AbilityEngine.new(db)
		e.begin_match()
		e.sync_field([ingrid], [])
		e.begin_round()
		e.set_role(ingrid, false, "defend")
		e.fire_reveal(ingrid, false)
		_say(e.take_reveal_next(false), "Ingrid's Reveal: your next pick is revealed too", "")
	# ---- Jan: to the exhaust -> another Tier IV goes instead, Jan comes back ----
	var jan := _find(db, "Jan")
	if jan != null:
		var e := AbilityEngine.new(db)
		e.begin_match()
		var other := _dummy("OtherFour", jan.get_tier_clean(), 2, "Air", "Unkengeister")
		var opp := _dummy("Opp", jan.get_tier_clean(), 1, "Earth", "Normal")
		e.sync_field([jan, other], [opp])
		e.round_lineups([jan], [opp])
		e.begin_round()
		e.begin_duel(jan, opp)
		e.resolve_duel_abilities(jan, false, opp)
		e.round_finished()
		_say(e.zone_of(jan, 0) == "field" and e.zone_of(other, 0) == "exhaust",
			"Jan goes to the exhaust - another Tier IV goes there instead and Jan comes back to be played",
			"Jan %s, other %s" % [e.zone_of(jan, 0), e.zone_of(other, 0)])
	# ---- Lothar: a token's next duel is doubled, then it swaps with the exhaust ----
	var lothar := _find(db, "Lothar")
	if lothar != null:
		var e := AbilityEngine.new(db)
		e.begin_match()
		var token := _dummy("Rose Unit", "I", 2, "Water", "Lorelei")
		token.extra_tags = PackedStringArray(["rose", "token"])
		var resting := _dummy("Resting", "I", 2, "Water", "Lorelei")
		var opp := _dummy("Opp", lothar.get_tier_clean(), 1, "Earth", "Normal")
		e.sync_field([lothar, token, resting], [opp])
		e._move(resting, false, "exhaust")
		e.round_lineups([lothar], [opp])
		e.begin_round()
		e.begin_duel(lothar, opp)
		e.resolve_duel_abilities(lothar, false, opp)
		e.round_finished()
		e.begin_round()
		var opp1 := _dummy("Opp1", "I", 1, "Earth", "Normal")
		e.round_lineups([token], [opp1])
		e.begin_duel(token, opp1)
		_say(e.attack_power(token, false) == 4, "Lothar: the token's next duel is fought with its printed power doubled (2 -> 4)",
			"token power %d" % e.attack_power(token, false))
		e.resolve_duel_abilities(token, false, opp1)
		e.resolve_duel_outcome(token, false, opp1, true)
		_say(e.zone_of(token, 0) == "exhaust" and e.zone_of(resting, 0) == "field",
			"...and after it, the token goes to the exhaust and a Tier I comes back from it",
			"token %s, resting %s" % [e.zone_of(token, 0), e.zone_of(resting, 0)])
	# ---- Jakob: revealed as a Swan -> a Swan token takes his place ----
	var jakob := _find(db, "Jakob")
	if jakob != null:
		var e := AbilityEngine.new(db)
		e.begin_match()
		e.sync_field([jakob], [])
		e.begin_round()
		e.set_role(jakob, false, "defend")
		e.make_kind(jakob, false, "swan")
		e.fire_reveal(jakob, false)
		var swaps := e.take_swaps()
		_say(not swaps.is_empty() and String(swaps[0].get("kind", "")) == "swan" and e.zone_of(jakob, 0) == "exhaust",
			"Jakob revealed as a Swan: he goes to the exhaust and a Swan Unit token takes his place",
			"swaps %d, Jakob %s" % [swaps.size(), e.zone_of(jakob, 0)])


## ROUND AD (C6): the class engines, each as a little story.
func _check_c6(db: CardDatabase) -> void:
	print("--- the class engines (C6) ---")
	# ---- Finn touched the ball: cold touch, enemy -2 ----
	var finn := _find(db, "Finn")
	if finn != null:
		var e := AbilityEngine.new(db)
		e.begin_match()
		var opp := _dummy("Opp", finn.get_tier_clean(), 3, "Earth", "Normal")
		e.sync_field([finn], [opp])
		e.round_lineups([finn], [opp])
		e.begin_round()
		e.set_touched(false, [finn])
		e.begin_duel(finn, opp)
		e.resolve_duel_abilities(finn, false, opp)
		_say(e.take_cold_touch() and int(e.cold_touches[false]) == 1 and e.defense_power(opp, true) == 1,
			"Finn touched the ball: a COLD TOUCH, and the enemy is -2", "enemy %d" % e.defense_power(opp, true))
		var e2 := AbilityEngine.new(db)
		e2.begin_match()
		e2.sync_field([finn], [opp])
		e2.round_lineups([finn], [opp])
		e2.begin_round()
		e2.begin_duel(finn, opp)
		e2.resolve_duel_abilities(finn, false, opp)
		_say(int(e2.cold_touches[false]) == 0, "...and nothing when he did NOT touch it", "")
	# ---- Ernst summons a gravestone ----
	var ernst := _find(db, "Ernst")
	if ernst != null:
		var e := AbilityEngine.new(db)
		e.begin_match()
		var opp := _dummy("Opp", ernst.get_tier_clean(), 1, "Earth", "Normal")
		e.sync_field([ernst], [opp])
		e.round_lineups([ernst], [opp])
		e.begin_round()
		e.put_counter(ernst, false, "burn")
		e.begin_duel(ernst, opp)
		e.resolve_duel_abilities(ernst, false, opp)
		_say((e.gravestones[false] as Array).size() == 1 and e.take_gravestones().size() == 1,
			"Ernst has a counter: a GRAVESTONE goes on the field", "")
	# ---- Marie swaps out for a card of her tier not played yet (the void) ----
	var marie := _find(db, "Marie")
	if marie != null:
		var e := AbilityEngine.new(db)
		e.begin_match()
		var other := _dummy("Waiting", marie.get_tier_clean(), 2, "Air", "Unkengeister")
		var opp := _dummy("Opp", marie.get_tier_clean(), 1, "Earth", "Normal")
		e.sync_field([marie, other], [opp])
		e.round_lineups([marie], [opp])
		e.begin_round()
		e.set_touched(false, [marie])
		e.begin_duel(marie, opp)
		e.resolve_duel_abilities(marie, false, opp)
		var mid := e.take_mid_swap()
		_say(not mid.is_empty() and mid["in"] == other and e.zone_of(marie, 0) == "field",
			"Marie swaps out of her duel for a Tier %s still to be played (the void, R07)" % marie.get_tier_clean(),
			"swap %s, Marie %s" % [not mid.is_empty(), e.zone_of(marie, 0)])
	# ---- Tobias: units mining each give +1 Ore ----
	var tobias := _find(db, "Tobias")
	if tobias != null:
		var e := AbilityEngine.new(db)
		e.begin_match()
		var opp := _dummy("Opp", tobias.get_tier_clean(), 1, "Air", "Normal")
		e.sync_field([tobias], [opp])
		e.round_lineups([tobias], [opp])
		e.begin_round()
		e.add_to_pool(false, "ore", 1)
		e.set_mining(false, [_dummy("M1", "I", 1, "Earth", "Bergmännlein"), _dummy("M2", "II", 1, "Earth", "Bergmännlein")], 4)
		e.begin_duel(tobias, opp)
		e.resolve_duel_abilities(tobias, false, opp)
		_say(e.pool(false, "ore") == 2, "Tobias: pay 1 Ore, two units mining give +1 each", "Ore %d" % e.pool(false, "ore"))
		e.mine_ore(false, 3, 3, tobias)
		_say(e.pool(false, "ore") == 5, "Mines worked since the last PLAY MAKER pay +1 Ore each (Q055)", "Ore %d" % e.pool(false, "ore"))
	# ---- Jonas fuses with a Tier III fire unit from the bench ----
	var jonas := _find(db, "Jonas")
	if jonas != null:
		var e := AbilityEngine.new(db)
		e.begin_match()
		var partner := _dummy("Bencher", "III", 4, "Fire", jonas.unit_type)
		var opp := _dummy("Opp", jonas.get_tier_clean(), 1, "Earth", "Normal")
		e.sync_field([jonas], [opp])
		e.set_bench(false, [partner])
		e.round_lineups([jonas], [opp])
		e.begin_round()
		e.begin_duel(jonas, opp)
		e.resolve_duel_abilities(jonas, false, opp)
		_say(e.fused_partner(jonas, false) == partner and e.attack_power(jonas, false) >= 4 and (e.bench[false] as Array).is_empty(),
			"Jonas FUSES with a Tier III fire unit from the bench: the higher power (Q056)",
			"partner %s, power %d" % [e.fused_partner(jonas, false) != null, e.attack_power(jonas, false)])


## ROUND AE (C7): the seven Emblem Basic sides built this round.
func _check_c7(db: CardDatabase) -> void:
	print("--- the Emblems' Basic sides (C7) ---")
	var opp := _dummy("Opp", "I", 2, "Earth", "Normal")
	# ---- Glasya-Labolas: an air unit that touched the ball is +1 ----
	var glasya := _badge("Glasya-Labolas")
	if glasya != null:
		var e := AbilityEngine.new(db)
		e.begin_match()
		var air := _dummy("Breeze", "I", 1, "Air", "Unkengeister")
		e.set_emblems(false, [glasya])
		e.sync_field([air], [opp])
		e.round_lineups([air], [opp])
		e.begin_round()
		e.set_touched(false, [air])
		e.begin_duel(air, opp)
		e.resolve_duel_abilities(air, false, opp)
		_say(e.attack_power(air, false) == 2, "Glasya-Labolas's Emblem: an air unit that touched the ball is +1", "power %d" % e.attack_power(air, false))
	# ---- Vassago: an air win makes the next air unit resolve earlier ----
	var vassago := _badge("Vassago")
	if vassago != null:
		var e := AbilityEngine.new(db)
		e.begin_match()
		var a1 := _dummy("Gust", "I", 3, "Air", "Unkengeister")
		var a2 := _dummy("Squall", "II", 1, "Air", "Unkengeister")
		var o2 := _dummy("Opp2", "II", 1, "Earth", "Normal")
		e.set_emblems(false, [vassago])
		e.sync_field([a1, a2], [opp, o2])
		e.round_lineups([a1, a2], [opp, o2])
		e.begin_round()
		e.begin_duel(a1, opp)
		e.resolve_duel_abilities(a1, false, opp)
		e.resolve_duel_outcome(a1, false, opp, true)
		e.begin_duel(a2, o2)
		_say(e.priority_mod(a2, false) == -1, "Vassago's Emblem: an air win gives the next air unit -1 priority", "mod %d" % e.priority_mod(a2, false))
	# ---- Caim: an air unit swaps with an air unit -> the enemy is -1 ----
	var caim := _badge("Caim")
	var ralf := _find(db, "Ralf")
	if caim != null and ralf != null:
		var e := AbilityEngine.new(db)
		e.begin_match()
		var mate := _dummy("Mate", "I", 1, "Air", "Unkengeister")
		var o := _dummy("OppI", "I", 3, "Earth", "Normal")
		e.set_emblems(false, [caim])
		e.sync_field([ralf, mate], [o])
		e.round_lineups([ralf], [o])
		e.begin_round()
		e.begin_duel(ralf, o)
		e.resolve_duel_abilities(ralf, false, o)
		e.round_finished()
		e.begin_round()
		e.round_lineups([mate], [o])
		e.do_exhaust_swap(ralf, mate, false)
		e.begin_duel(ralf, o)
		_say(e.defense_power(o, true) == 2, "Caim's Emblem: an air unit swaps in for an air unit - the enemy is -1", "enemy %d" % e.defense_power(o, true))
	# ---- Belial: earth cards not playing mine; +1 Ore per worked zone ----
	var belial := _badge("Belial")
	if belial != null:
		var e := AbilityEngine.new(db)
		e.begin_match()
		var digger := _dummy("Digger", "I", 1, "Earth", "Bergmännlein")
		var resting := _dummy("Resting", "II", 1, "Earth", "Bergmännlein")
		var player := _dummy("Player", "III", 2, "Earth", "Bergmännlein")
		e.set_emblems(false, [belial])
		e.sync_field([digger, resting, player], [opp])
		e._move(resting, false, "exhaust")
		e.begin_round()
		e.round_lineups([player], [opp])
		_say(e.pool(false, "ore") == 2 and e.mining_count(false) == 2,
			"Belial's Emblem: a mine in the field zone and the exhaust zone - both worked, +2 Ore, 2 mining",
			"Ore %d, mining %d" % [e.pool(false, "ore"), e.mining_count(false)])
	# ---- Haures: a save gives Ore to the Tier IV earth unit; the rock is harder to beat ----
	var haures := _badge("Haures")
	if haures != null:
		var e := AbilityEngine.new(db)
		e.begin_match()
		var four := _dummy("Boulder", "IV", 3, "Earth", "Bergmännlein")
		e.set_emblems(false, [haures])
		e.sync_field([four], [opp])
		e.begin_round()
		e.after_shot(true, false)
		# Round AG (Q116): haures_rock_shift is 0 now, so "harder to beat" is
		# whatever that row says.
		var rock := db.tune_float("haures_rock_shift", -5.0)
		_say(e.pool(false, "ore") == 2 and is_equal_approx(e.keeper_shift(false), rock),
			"Haures's Emblem: the rock keeper saves - the Tier IV earth unit collects 2 Ore; he is harder to beat",
			"Ore %d, shift %.0f (haures_rock_shift %.0f)" % [e.pool(false, "ore"), e.keeper_shift(false), rock])
	# ---- Flauros: a fire unit buffing another fire unit gives +1 more ----
	var flauros := _badge("Flauros")
	if flauros != null:
		var e := AbilityEngine.new(db)
		e.begin_match()
		var giver := _dummy("Giver", "I", 1, "Fire", "Rauhnacht-Feuergeister")
		var taker := _dummy("Taker", "I", 2, "Fire", "Rauhnacht-Feuergeister")
		var ab := AbilityData.new()
		ab.id = "TEST_BUFF"
		ab.effect = "addpower"
		ab.value = 1
		ab.scope = "duel"
		e.set_emblems(false, [flauros])
		e.sync_field([giver, taker], [opp])
		e.begin_round()
		e._land_buff(ab, taker, false, giver)
		_say(e.attack_power(taker, false) == 4, "Flauros's Emblem: a fire unit's +1 on another fire unit brings +1 more", "power %d" % e.attack_power(taker, false))
	# ---- Vassago's Condition: Unkengeister in the exhaust at once ----
	var e5 := AbilityEngine.new(db)
	e5.begin_match()
	var ups: Array = []
	for i in 3:
		ups.append(_dummy("U%d" % i, "I", 1, "Air", "Unkengeister"))
	e5.sync_field(ups, [opp])
	e5.round_lineups(ups, [opp])
	e5.begin_round()
	e5.round_finished()
	var peak := 0
	for ev in e5.take_events():
		if String(ev["event"]) == "exhaust_peak" and String((ev["facts"] as Dictionary).get("class", "")) == "Unkengeister":
			peak += int(String((ev["facts"] as Dictionary).get("amount", "0")))
	_say(peak == 3, "Vassago's Condition: three Unkengeister in the exhaust at once counts 3", "counted %d" % peak)


## ROUND AF (C8): the Stars' Ultimates, one story each.
## ROUND AG: your Q112 b (you pick Vassago's copy) and the Q118 dials.
## What a power_from_count card should fight at: the count, or (round AG,
## `count_power_floor` 1) never below its printed power.
func _count_power(engine: AbilityEngine, db: CardDatabase, ability: AbilityData, who: PlayerData, side: bool) -> int:
	var n := engine._count_for(ability.effect_arg, side, ability.value)
	if db.tune_bool("count_power_floor", false):
		n = maxi(n, who.get_attack_power())
	return n


func _check_ag(db: CardDatabase) -> void:
	print("--- round AG ---")
	var opp := _dummy("Opp", "II", 3, "Earth", "Normal")
	var e := AbilityEngine.new(db)
	e.begin_match()
	var row := _self_buff_row(db, "onattack")
	if row != "":
		var d1 := _dummy("DonorOne", "II", 1, "Earth", "Normal")
		var d2 := _dummy("DonorTwo", "II", 1, "Earth", "Normal")
		d1.attack_ability_id = row
		d2.attack_ability_id = row
		var thief := _dummy("Thief", "II", 1, "Air", "Unkengeister")
		e.sync_field([thief], [d1, d2, opp])
		e._move(d1, true, "exhaust")
		e._move(d2, true, "exhaust")
		e.set_ultimates(false, ["Vassago"])
		e.round_lineups([thief], [opp])
		e.begin_round()
		e.begin_duel(thief, opp)
		var options := e.vassago_options(thief, false)
		e.vassago_copy(thief, false, options[options.size() - 1])
		var copied: PlayerData = e._copied.get(e._k(thief, false), null)
		_say(options.size() == 2 and copied == d2 and e._pinned.has(e._k(d2, true)) and not e._pinned.has(e._k(d1, true)),
			"Vassago's Ultimate (Q112 b): two to copy - you pick the second, only it is held in the exhaust",
			"%d options, copied %s" % [options.size(), copied.player_name if copied != null else "nothing"])
	# Q118: a Star in Tier IV gets star_power_tier_IV in combat
	e = AbilityEngine.new(db)
	e.begin_match()
	var star := _dummy("StarFour", "IV", 3, "Fire", "Rauhnacht-Feuergeister")
	star.player_type = "Star"
	e.sync_field([star], [opp])
	var dial := int(round(db.tune_float("star_power_tier_IV", 0.0)))
	_say(not star.is_star() or e.attack_power(star, false) == 3 + dial,
		"Balance dial star_power_tier_IV (Q118): a Tier IV Star is +%d" % dial, "power %d" % e.attack_power(star, false))


func _check_c8(db: CardDatabase) -> void:
	print("--- the Ultimates (C8) ---")
	var opp := _dummy("Opp", "II", 3, "Earth", "Normal")
	# Zepar: a Swan attacks -> the enemy is a Swan too, and -2
	var e := AbilityEngine.new(db)
	e.begin_match()
	var swan := _dummy("Swanling", "II", 2, "Water", "Lorelei")
	e.sync_field([swan], [opp])
	e.make_kind(swan, false, "swan")
	e.set_ultimates(false, ["Zepar"])
	e.round_lineups([swan], [opp])
	e.begin_round()
	e.begin_duel(swan, opp)
	e.resolve_duel_abilities(swan, false, opp)
	_say(e.is_kind(opp, true, "swan") and e.defense_power(opp, true) == 1, "Zepar's Ultimate: a Swan attacks - the enemy becomes a Swan and is -2", "enemy %d" % e.defense_power(opp, true))
	# Sallos: two songs -1, three songs = 3 off its keeper
	e = AbilityEngine.new(db)
	e.begin_match()
	var a := _dummy("A", "II", 3, "Earth", "Normal")
	var b := _dummy("B", "III", 3, "Earth", "Normal")
	var me := _dummy("Me", "II", 1, "Water", "Lorelei")
	e.sync_field([me], [a, b])
	e.set_ultimates(false, ["Sallos"])
	e.put_counter(a, true, "song", 2)
	e.put_counter(b, true, "song", 3)
	e.begin_round()
	e.begin_duel(me, a)
	var two := e.attack_power(a, true)
	e.begin_duel(me, b)
	var drained := false
	for ch in e.take_pending_stamina():
		if bool(ch["enemy_side"]) and int(ch["delta"]) == -3:
			drained = true
	_say(two == 2 and drained and e.counter(b, true, "song") == 0, "Sallos's Ultimate: two songs -1; three songs = 3 off their keeper, songs gone", "two %d, drained %s" % [two, drained])
	# Belphegor: +1 per victory counter, and a goal resets it
	e = AbilityEngine.new(db)
	e.begin_match()
	var fire := _dummy("Ember", "II", 2, "Fire", "Rauhnacht-Feuergeister")
	e.sync_field([fire], [opp])
	e.set_ultimates(false, ["Belphegor"])
	e.add_to_pool(false, "victory", 2)
	var with_two := e.attack_power(fire, false)
	e.after_shot(false, true)
	_say(with_two == 4 and e.pool(false, "victory") == 0 and not e.take_emblem_resets().is_empty(),
		"Belphegor's Ultimate: +1 per victory counter; a goal clears them and flips the Emblem back", "power %d" % with_two)
	# Flauros: a weapon = the strongest fused unit, fusions broken up
	e = AbilityEngine.new(db)
	e.begin_match()
	var flauros := _find(db, "Flauros")
	var jonas := _find(db, "Jonas")
	if flauros != null and jonas != null:
		var partner := _dummy("Bencher", "III", 4, "Fire", "Rauhnacht-Feuergeister")
		e.sync_field([flauros, jonas], [opp])
		e.set_bench(false, [partner])
		e.round_lineups([jonas], [opp])
		e.begin_round()
		e.begin_duel(jonas, opp)
		e.resolve_duel_abilities(jonas, false, opp)
		e.on_ultimate(false, "Flauros")
		_say(e.attack_power(flauros, false) >= 4 and e.fused_partner(jonas, false) == null and e.zone_of(jonas, 0) == "exhaust",
			"Flauros's Ultimate: a weapon as strong as the strongest fused unit; the fusions break up into the exhaust",
			"Flauros %d, Jonas %s" % [e.attack_power(flauros, false), e.zone_of(jonas, 0)])
	# Buer: the Teufel Mask, +3 in combat, -1 counter per combat
	e = AbilityEngine.new(db)
	e.begin_match()
	var masked := _dummy("Masked", "II", 2, "Fire", "Rauhnacht-Feuergeister")
	e.sync_field([masked], [opp])
	e.on_ultimate(false, "Buer")
	e.round_lineups([masked], [opp])
	e.begin_round()
	e.begin_duel(masked, opp)
	var masked_power := e.attack_power(masked, false)
	e.resolve_duel_outcome(masked, false, opp, true)
	_say(masked_power == 5 and e.mask_on(masked, false) == 2, "Buer's Ultimate: the Teufel Mask is +3 in combat and loses one per combat", "power %d, mask %d" % [masked_power, e.mask_on(masked, false)])
	# Belial: the ore shop - buying is the ability
	e = AbilityEngine.new(db)
	e.begin_match()
	var digger := _dummy("Digger", "II", 1, "Earth", "Bergmännlein")
	e.sync_field([digger], [opp])
	e.set_ultimates(false, ["Belial"])
	e.add_to_pool(false, "ore", 4)
	e.round_lineups([digger], [opp])
	e.begin_round()
	e.begin_duel(digger, opp)
	var items := e.shop_items(digger, false)
	var gold: Dictionary = {}
	for it in items:
		if String(it["item"]) == "Gold Vein":
			gold = it
	if not gold.is_empty():
		e.shop_buy(digger, false, gold)
	_say(not gold.is_empty() and e.attack_power(digger, false) == 3 and e.pool(false, "ore") == 0,
		"Belial's Ultimate: the ore shop - Gold Vein, 4 Ore, +2 power", "power %d, Ore %d" % [e.attack_power(digger, false), e.pool(false, "ore")])
	# Haures: the keeper eats Ore for armour
	e = AbilityEngine.new(db)
	e.begin_match()
	e.set_ultimates(false, ["Haures"])
	e.add_to_pool(false, "ore", 2)
	e.begin_round()
	var shield := false
	for ch in e.take_pending_stamina():
		if int(ch.get("shield", 0)) == 1 and not bool(ch["enemy_side"]):
			shield = true
	_say(shield and e.pool(false, "ore") == 1 and e.keeper_shift(false) <= -5.0, "Haures's Ultimate: the keeper eats 1 Ore - a shield and 5% harder to beat", "Ore %d" % e.pool(false, "ore"))
	# Caim: ghosts on the ball for the next Unkengeister
	e = AbilityEngine.new(db)
	e.begin_match()
	var ghostly := _dummy("Wisp", "II", 1, "Air", "Unkengeister")
	e.sync_field([ghostly], [opp])
	e.ghosts[false] = 2
	e.round_lineups([ghostly], [opp])
	e.begin_round()
	e.begin_duel(ghostly, opp)
	var with_ghosts := e.attack_power(ghostly, false)
	e.resolve_duel_outcome(ghostly, false, opp, true)
	_say(with_ghosts == 3 and int(e.ghosts[false]) == 0, "Caim's Ultimate: two ghosts on the ball - the next Unkengeister +2, then they are gone", "power %d" % with_ghosts)
	# Gremory: every Rose in the exhaust adds to the shot
	e = AbilityEngine.new(db)
	e.begin_match()
	var rose := _dummy("Rose Unit", "I", 1, "Water", "Lorelei")
	rose.extra_tags = PackedStringArray(["rose", "token"])
	e.sync_field([rose], [opp])
	e._move(rose, false, "exhaust")
	e.set_ultimates(false, ["Gremory"])
	_say(e.shot_bonus(false) == 1, "Gremory's Ultimate: each Rose Unit in the exhaust adds 1 to the shot", "bonus %d" % e.shot_bonus(false))
	# Vassago: copy an enemy ability from their exhaust
	e = AbilityEngine.new(db)
	e.begin_match()
	var donor_row := _self_buff_row(db, "onattack")
	if donor_row != "":
		var donor := _dummy("Donor", "II", 1, "Earth", "Normal")
		donor.attack_ability_id = donor_row
		var thief := _dummy("Thief", "II", 1, "Air", "Unkengeister")
		e.sync_field([thief], [donor, opp])
		e._move(donor, true, "exhaust")
		e.set_ultimates(false, ["Vassago"])
		e.round_lineups([thief], [opp])
		e.begin_round()
		e.begin_duel(thief, opp)
		e.resolve_duel_abilities(thief, false, opp)
		_say(e.attack_power(thief, false) > 1, "Vassago's Ultimate: an Unkengeister copies an enemy ability from their exhaust", "power %d" % e.attack_power(thief, false))
	# Valefor: Bergmännlein in the exhaust mine; last round's miners +1
	e = AbilityEngine.new(db)
	e.begin_match()
	var rester := _dummy("Rester", "I", 1, "Earth", "Bergmännlein")
	var player := _dummy("Player", "II", 1, "Earth", "Bergmännlein")
	e.sync_field([rester, player], [opp])
	e._move(rester, false, "exhaust")
	e.set_ultimates(false, ["Valefor"])
	e.begin_round()
	e.round_lineups([player], [opp])
	var ore_after := e.pool(false, "ore")
	e.round_finished()
	e.begin_cycle()
	e.begin_round()
	e.round_lineups([rester], [opp])
	e.begin_duel(rester, opp)
	_say(ore_after == 1 and e.attack_power(rester, false) == 2, "Valefor's Ultimate: a Bergmännlein in the exhaust mines (+1 Ore) and is +1 in its next combat", "Ore %d, power %d" % [ore_after, e.attack_power(rester, false)])
