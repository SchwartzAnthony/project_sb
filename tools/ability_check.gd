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


func _check(card: PlayerData, slot: String, ability: AbilityData, db: CardDatabase) -> void:
	checked += 1
	var engine := AbilityEngine.new(db)
	engine.begin_match()
	var me := false
	var opp := _dummy("Opponent", card.get_tier_clean(), 2, "Earth", "Normal")
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
				if target_side:
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
		_say(now == before + 1 and again == before,
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
