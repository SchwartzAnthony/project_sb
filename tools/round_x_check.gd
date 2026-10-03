extends SceneTree

# =============================================================
#  ROUND X, MEASURED — names, recruits, three beers, the repeat offender
#  and the card that leans on the referee.
#
#      godot --headless --script res://tools/round_x_check.gd
#
#  It plays everything on a SCRATCH save that is never written to disk, so
#  running it cannot touch your game. It ends with ALL GOOD or with a list
#  of what is wrong, in sentences.
#
#  WHAT IT PROVES
#    1. NAMES       no two cards share a name; 300 recruits get 300 names;
#                   a released name is free again.
#    2. RECRUITS    recruit:I0 signs a named plain player; release: removes
#                   him and frees his name; nothing shows while
#                   named_recruits is off.
#    3. BEERS       water, water, fire = fire 1 of 3; three waters = the
#                   choice; he keeps his name, tier and power and takes the
#                   chosen card's class and abilities.
#    4. FOULS       a man's own fouls make him easier to see and likelier
#                   to be booked - printed as percentages.
#    5. THE ORE     Karl's add_card_chance stacks to its Max and no further,
#    CARD           and the talent door (count:tune_foul_card_bonus_enemy+n)
#                   moves the same number.
# =============================================================

const LINE := "  ────────────────────────────────────────────────────────────"

var trouble: Array[String] = []


func _initialize() -> void:
	print("")
	print("=== ROUND X ===")
	var db := CardDatabase.get_db()
	if db == null:
		print("  no card database.")
		quit()
		return
	_names(db)
	_recruits(db)
	_beers(db)
	_who_cannot_turn(db)
	_fouls(db)
	_ore_card(db)

	print("")
	if trouble.is_empty():
		print("  ALL GOOD.")
	else:
		print("  %d THING(S) TO LOOK AT:" % trouble.size())
		for line in trouble:
			print("   - " + line)
	print("")
	quit()


func _fresh() -> GameState:
	var state := GameState.new()
	state.reset()
	return state


# =============================================================
#  1. NAMES
# =============================================================

func _names(db: CardDatabase) -> void:
	print("")
	print("  === 1. NAMES ===")
	var seen: Dictionary = {}
	var clashes: Array[String] = []
	var placeholders := 0
	for card in db.players:
		var key := CardDatabase._normalise(card.player_name)
		if card.player_name.strip_edges().to_lower() == "unit name":
			placeholders += 1
		if seen.has(key):
			clashes.append(card.player_name)
		seen[key] = true
	print("  %d cards, %d first names and %d surnames in Names.csv."
		% [db.players.size(), NameBook.first_names().size(), NameBook.surnames().size()])
	if placeholders > 0:
		trouble.append("%d card(s) are still called 'Unit Name'." % placeholders)
	if not clashes.is_empty():
		trouble.append("These names are used by more than one card: %s" % ", ".join(clashes))
	else:
		print("  Every card has a name of its own.")

	var state := _fresh()
	var given: Dictionary = {}
	for i in 300:
		var one := NameBook.take(state, db)
		if given.has(one) or seen.has(CardDatabase._normalise(one)):
			trouble.append("NameBook gave out '%s' twice." % one)
			break
		given[one] = true
	print("  300 recruits in a row got 300 different names (%d first names left free before surnames were needed)."
		% maxi(0, NameBook.first_names().size() - db.players.size()))
	var sample: Array = given.keys().slice(0, 6)
	print("  e.g. %s" % ", ".join(PackedStringArray(sample)))

	var first: String = sample[0]
	NameBook.give_back(first, state)
	if not NameBook.is_free(first, state, db):
		trouble.append("A released name ('%s') was not free again." % first)
	else:
		print("  '%s' left the base and the name is free again." % first)


# =============================================================
#  2. RECRUITS
# =============================================================

func _recruits(db: CardDatabase) -> void:
	print("")
	print("  === 2. RECRUITS ===")
	var state := _fresh()
	DialogueGrammar.apply("recruit:I0;recruit:I0;recruit:I0=Johannes", state)
	var who := RecruitBook.names(state)
	print("  recruit:I0 three times (the last asking for Johannes): %s" % ", ".join(who))
	if who.size() != 3:
		trouble.append("Three recruit: actions signed %d players." % who.size())
	if not who.has("Johannes"):
		trouble.append("recruit:I0=Johannes did not use the name Johannes.")
	for name_text in who:
		if not SquadBook.names(state).has(name_text):
			trouble.append("%s was recruited but not signed into the squad." % name_text)

	var complaints := DialogueGrammar.complaints("recruit:V9", true)
	if complaints.is_empty():
		trouble.append("recruit:V9 should have been refused as a typo, and was not.")
	else:
		print("  A typo is refused out loud: %s" % complaints[0])

	var before := db.players.size()
	RecruitBook.apply_all(db, state)
	if RecruitBook.on(db):
		print("  named_recruits is ON: %d recruit card(s) joined the card list." % (db.players.size() - before))
	elif db.players.size() != before:
		trouble.append("named_recruits is off but recruits still appeared in the card list.")
	else:
		print("  named_recruits is OFF, so the card list did not change (as it should).")

	# Switch it on for a moment, as you will one day.
	db.tuning["namedrecruits"] = "true"
	RecruitBook.apply_all(db, state)
	var added := db.players.size() - before
	var johannes: PlayerData = null
	for card in db.players:
		if card.player_name == "Johannes":
			johannes = card
	print("  With it ON: %d recruit card(s) in the list. Johannes is %s." % [added,
		"Tier %s, Power %d, %s" % [johannes.get_tier_clean(), johannes.base_power_left, johannes.unit_type]
		if johannes != null else "MISSING"])
	if added != 3 or johannes == null:
		trouble.append("With named_recruits on, the three recruits did not all join the card list.")

	DialogueGrammar.apply("release:Johannes", state)
	RecruitBook.apply_all(db, state)
	if RecruitBook.is_recruit("Johannes", state) or not NameBook.is_free("Johannes", state, db):
		trouble.append("release:Johannes did not remove him and free the name.")
	else:
		print("  release:Johannes - gone from the base, and the name is free for the next man.")
	RecruitBook.remove_all(db)
	db.tuning["namedrecruits"] = "false"


# =============================================================
#  3. THREE BEERS
# =============================================================

func _beers(db: CardDatabase) -> void:
	print("")
	print("  === 3. THREE BEERS ===")
	var brews := BrewDB.get_db()
	var water := brews.find("turn_water")
	var fire := brews.find("turn_fire")
	if water.is_empty() or fire.is_empty():
		trouble.append("Brews.csv has no turn_water / turn_fire row, so there is nothing to test.")
		return
	var state := _fresh()
	state.add_count("reed", 20)
	state.add_count("ash_glass", 20)

	var plain: PlayerData = null
	for card in db.players:
		if card.unit_type == "Normal" and not card.is_star() and card.get_tier_clean() == "I" \
				and card.base_power_left == 0:
			plain = card
			break
	if plain == null:
		trouble.append("No plain (Normal) Tier I Power 0 card to pour for.")
		return
	var name_before := plain.player_name
	print("  %s is plain: Tier I, Power 0, %s." % [plain.player_name, plain.unit_type])

	TransformBook.pour(plain, water, state, db)
	TransformBook.pour(plain, water, state, db)
	var mid := TransformBook.progress(plain, state)
	print("  Two water: %s %d." % [mid["element"], mid["count"]])
	TransformBook.pour(plain, fire, state, db)
	var mixed := TransformBook.progress(plain, state)
	print("  ...then one fire: %s %d   (a new element starts again)" % [mixed["element"], mixed["count"]])
	if String(mixed["element"]) != "fire" or int(mixed["count"]) != 1:
		trouble.append("Water, water, fire should be fire 1 of 3; it was %s %d." % [mixed["element"], mixed["count"]])

	var last := {}
	for i in 3:
		last = TransformBook.pour(plain, water, state, db)
	print("  Three water: ready to choose = %s.  Reed left: %d of 20 (2 a beer)." % [last.get("ready", false),
		state.count("reed")])
	if not bool(last.get("ready", false)):
		trouble.append("Three water beers did not make him ready to turn.")
		return
	if state.count("reed") != 10:
		trouble.append("Five water pours at 2 reed should have cost 10 reed; %d were spent." % (20 - state.count("reed")))

	var options := TransformBook.choices(plain, water, db)
	var sets: Array[String] = []
	for role in options:
		sets.append("%s (%s)" % [role.card_set, role.player_name])
	print("  He may become: %s" % ", ".join(sets))
	if options.size() < 2:
		trouble.append("Only %d Lorelei card(s) at Tier I Power 0 to choose from." % options.size())
	if options.is_empty():
		return

	var role: PlayerData = options[0]
	TransformBook.complete(plain, role, state)
	TransformBook.apply_all(db, state)
	print("  Chose %s. He is now: %s, Tier %s, Power %d, %s, set %s." % [role.player_name,
		plain.player_name, plain.get_tier_clean(), plain.base_power_left, plain.unit_type, plain.card_set])
	print("     attack: %s" % plain.attack_text.strip_edges())
	if plain.player_name != name_before:
		trouble.append("He changed his name when he turned.")
	if plain.unit_type != "Lorelei" or plain.base_power_left != 0 or plain.get_tier_clean() != "I":
		trouble.append("After turning he should be a Tier I Power 0 Lorelei.")
	if plain.attack_text != role.attack_text:
		trouble.append("He did not take the chosen card's abilities.")
	if TransformBook.refusal(plain, water, state, db) == "":
		trouble.append("A player who has turned could drink a turning brew again.")

	var lorelei_brew := brews.find("fire")
	if not lorelei_brew.is_empty() and BrewDB.suits(lorelei_brew, plain):
		print("  And he may now drink the Fire Brew, which is For Class Lorelei.")
	TransformBook.restore_all()
	if plain.unit_type != "Normal":
		trouble.append("restore_all() did not give the card back its own class.")


## THE GAP NOBODY HAS ASKED ABOUT YET: in each class one tier belongs to the
## Stars alone, so a plain player of that tier has nothing to turn into.
func _who_cannot_turn(db: CardDatabase) -> void:
	print("")
	print("  === WHO CAN TURN INTO WHAT ===")
	var brews := BrewDB.get_db()
	var powers := {"I": [0, 1, 2], "II": [1, 2, 3], "III": [2, 3, 4], "IV": [3, 4, 5]}
	for entry in brews.brews:
		if not TransformBook.is_turning(entry):
			continue
		var missing: Array[String] = []
		for tier in ["I", "II", "III", "IV"]:
			for power in powers[tier]:
				var probe := PlayerData.new()
				probe.player_name = "probe"
				probe.tier = tier
				probe.base_power_left = int(power)
				probe.base_power_right = int(power)
				if TransformBook.choices(probe, entry, db).is_empty():
					missing.append("%s·%d" % [tier, power])
		if missing.is_empty():
			print("  %-26s every tier and power has something to become." % String(entry["becomes"]))
		else:
			print("  %-26s nothing to become at %s - those belong to its Stars."
				% [String(entry["becomes"]), " ".join(missing)])


# =============================================================
#  4. THE REPEAT OFFENDER
# =============================================================

func _fouls(db: CardDatabase) -> void:
	print("")
	print("  === 4. THE REPEAT OFFENDER ===")
	Referee.clear_heat()
	print("  With an EMPTY bar and no bookings, a foul by a man who has already")
	print("  committed this many is seen, and a seen one is a yellow, this often:")
	for ref in Referee.every():
		var row: Array[String] = []
		for own in 4:
			var seen := float(ref["per_own_foul"]) * float(own)
			var card := float(ref["card_per_own_foul"]) * float(own)
			row.append("%d: %2.0f%% / +%2.0f%%" % [own, seen, card])
		print("  %-20s %s" % [ref["name"], "   ".join(row)])

	var probe := RefCounted.new()
	Referee.record_foul(probe)
	Referee.record_foul(probe)
	if Referee.fouls_by(probe) != 2:
		trouble.append("Two fouls by one man were counted as %d." % Referee.fouls_by(probe))
	Referee.clear_heat()
	if Referee.fouls_by(probe) != 0:
		trouble.append("A man's fouls were not forgotten at kick-off.")
	if Referee.notice_chance(false, 0, db, 3) <= Referee.notice_chance(false, 0, db, 0) \
			and float(Referee.on_duty(db)["per_own_foul"]) > 0.0:
		trouble.append("A third foul is not easier to see than a first.")


# =============================================================
#  5. THE ORE CARD
# =============================================================

func _ore_card(db: CardDatabase) -> void:
	print("")
	print("  === 5. KARL'S ORE CARD, AND THE TALENT DOOR ===")
	var ability := db.get_ability("BERG_ORE_WHISPER")
	if ability == null:
		trouble.append("BERG_ORE_WHISPER is not in Abilities.csv (or was refused - see the Output panel).")
		return
	var karl: PlayerData = null
	for card in db.players:
		if card.active_attack_ability() == "BERG_ORE_WHISPER":
			karl = card
	print("  %s carries it: %s" % [karl.player_name if karl != null else "NOBODY",
		ability.describe()])
	if karl == null:
		trouble.append("No card has BERG_ORE_WHISPER in its Attack Ability column.")
		return

	var engine := AbilityEngine.new(db)
	engine.begin_match()
	# ROUND Z: "Consume 3 Ore:" is real now - he needs 3 Ore a go. Given
	# plenty, so this checks the Max, not the cost (ability_check does that).
	engine.add_to_pool(false, "ore", 99)
	var after: Array[String] = []
	for i in 7:
		engine.fire(karl, false, "on_attack")
		after.append("%.0f" % float(engine.card_chance[true]))
	print("  He attacks seven times. The enemy's extra booking chance: %s %%" % ", ".join(after))
	if float(engine.card_chance[true]) != float(ability.value * ability.max_uses):
		trouble.append("After seven attacks the bonus is %.0f%%, but Max %d x %d%% should stop it at %d%%."
			% [float(engine.card_chance[true]), ability.max_uses, ability.value,
				ability.value * ability.max_uses])
	if float(engine.card_chance[false]) != 0.0:
		trouble.append("Karl's card made HIS OWN side easier to book.")
	if engine.pool(false, "ore") != 99 - 3 * ability.max_uses:
		trouble.append("Karl should have spent %d Ore over his %d goes; the pool holds %d of 99."
			% [3 * ability.max_uses, ability.max_uses, engine.pool(false, "ore")])

	# --- what it does to a match, in cards ---
	var plain := _bookings(db, 0.0)
	var leaned := _bookings(db, float(engine.card_chance[true]))
	print("  Out of 1000 fouls the referee SEES by the enemy: %d yellows without it, %d with it on full."
		% [plain, leaned])

	# --- the talent door ---
	var state := _fresh()
	var before := Referee.card_bump(true, 0, db)
	DialogueGrammar.apply("count:tune_foul_card_bonus_enemy+3", state)
	db.apply_bonuses_from(state)
	var with_talent := Referee.card_bump(true, 0, db)
	print("  A talent with count:tune_foul_card_bonus_enemy+3: the enemy's bump goes %.0f%% -> %.0f%%."
		% [before, with_talent])
	if with_talent - before != 3.0:
		trouble.append("count:tune_foul_card_bonus_enemy+3 moved the bump by %.0f, not 3." % (with_talent - before))
	db.bonuses.clear()


## How many of 1000 seen enemy fouls end as a yellow, at a 0-trigger round,
## with this much extra from abilities.
func _bookings(db: CardDatabase, extra: float) -> int:
	var yellows := 0
	for i in 1000:
		var odds := FoulBook.odds_at(0)
		var verdict := "free kick"
		var roll := randf() * 100.0
		if roll < float(odds["red"]):
			verdict = "red"
		elif roll < float(odds["red"]) + float(odds["yellow"]):
			verdict = "yellow"
		if verdict == "free kick" and randf() * 100.0 < Referee.card_bump(true, 0, db, extra):
			verdict = "yellow"
		if verdict == "yellow":
			yellows += 1
	return yellows
