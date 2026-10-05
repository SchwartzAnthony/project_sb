extends SceneTree

# =============================================================
#  THE SIMULATION RUNNER  (round AI - "Tester Claude")
#
#      godot --headless --path . --script res://tests/sim_runner.gd
#
#  Plays MANY matches in a few minutes, with no pitch and no pictures, and
#  writes what happened to res://data/combat_telemetry.json.
#
#  ============ WHAT IT IS, AND WHAT IT IS NOT ============
#
#  It is the REAL combat: the same AbilityEngine the match uses, the same
#  cards, abilities, counters, tokens, Ore, Emblem Basic sides, the same duel
#  rule (attack against defence, the winner keeps or takes the ball), the same
#  bank, the same shot against the same keeper with the same ShotOdds.csv.
#
#  It leaves out what only exists on the grass: who touched the ball, mines
#  being worked, gravestones knocked over, fouls and free kicks, and the
#  Emblem RACE (so no Ultimates). Every question a card would ask is
#  answered with its default. For the whole game with all of that, use
#  tools/balance_report.py - it plays the real match, slowly.
#
#  ============ WHAT IT PLAYS: data/SimMatchups.csv ============
#
#    Matchup   a name for the row
#    Home      a class (Lorelei, Unkengeister ...), Normal for the Basic
#              Team, or random
#    Away      the same
#    Home Picks / Away Picks   how a side chooses its card in each tier,
#              each round:  strongest  random  weakest
#    Share     how much of the run this row gets (a weight). 0 = off.
#
#  ============ SETTINGS (environment variables) ============
#
#    SIM_MATCHES   how many matches in all (default 1000)
#    SIM_SEED      the random seed (default 20261005) - same seed, same run
#    SIM_OUT       where to write (default res://data/combat_telemetry.json)
#
#  ============ WHAT "DPS" AND "DAMAGE" MEAN HERE ============
#
#  Sturmball has no hit points. A duel is one number against another. So:
#
#    power_dealt     the power a card fought with, summed over its duels
#                    (its "damage per duel" is power_dealt / duels)
#    power_faced     the power it fought against ("damage taken")
#    keeper_damage   stamina a side's shots took off the other keeper
#    match ticks     duels played (4 a round)
# =============================================================

const TIERS: Array[String] = ["I", "II", "III", "IV"]
const MATCHUPS := "res://data/SimMatchups.csv"

var db: CardDatabase
var rng := RandomNumberGenerator.new()
var classes: Array[String] = []

var by_class: Dictionary = {}       # class -> {played, won, drawn, lost, gf, ga, keeper_damage, duels{tier:[won,total]}}
var by_card: Dictionary = {}        # "Class|Name" -> {...}
var by_ability: Dictionary = {}     # ability id -> times fired
var by_matchup: Dictionary = {}
var by_matchup_class: Dictionary = {}
var ticks: Array[int] = []
var goals_per_match: Array[int] = []
var problems: Array[String] = []


func _initialize() -> void:
	db = CardDatabase.get_db()
	var total := int(OS.get_environment("SIM_MATCHES")) if OS.get_environment("SIM_MATCHES") != "" else 1000
	var seed_value := int(OS.get_environment("SIM_SEED")) if OS.get_environment("SIM_SEED") != "" else 20261005
	var out_path := OS.get_environment("SIM_OUT") if OS.get_environment("SIM_OUT") != "" else "res://data/combat_telemetry.json"
	rng.seed = seed_value
	seed(seed_value)

	# The classes "random" draws from: `sim_classes` in Tuning.csv.
	for piece in db.tune_text("sim_classes", "Lorelei,Rauhnacht-Feuergeister,Bergmännlein,Unkengeister").split(",", false):
		var klass := String(piece).strip_edges()
		if db.stars_by_class().has(klass):
			classes.append(klass)
		else:
			problems.append("sim_classes names '%s', which has no Stars - left out" % klass)
	if classes.is_empty():
		for key in db.stars_by_class().keys():
			classes.append(String(key))

	var rows := _matchups()
	var weight := 0.0
	for r in rows:
		weight += float(r["share"])
	print("[sim] %d matches, seed %d, %d matchup row(s), classes: %s" % [total, seed_value, rows.size(), ", ".join(classes)])

	var started := Time.get_ticks_msec()
	var played := 0
	for r in rows:
		var n := int(round(float(total) * float(r["share"]) / maxf(weight, 0.0001)))
		for i in n:
			if played >= total:
				break
			_play_match(r)
			played += 1
			if played % 100 == 0:
				print("[sim] %d / %d" % [played, total])
	while played < total and not rows.is_empty():
		_play_match(rows[0])
		played += 1

	var report := _report(played, seed_value, Time.get_ticks_msec() - started)
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	if file == null:
		print("[sim] could not write %s" % out_path)
	else:
		file.store_string(JSON.stringify(report, "  "))
		file.close()
		print("[sim] wrote %s (%d matches in %.1f s)" % [out_path, played, (Time.get_ticks_msec() - started) / 1000.0])
	for p in problems.slice(0, 10):
		print("[sim] note: %s" % p)
	quit(0)


func _matchups() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row in MenuSupport.read_csv(MATCHUPS):
		var share := MenuSupport.field_float(row, "Share", 1.0)
		if share <= 0.0:
			continue
		out.append({
			"name": MenuSupport.field(row, "Matchup", "?"),
			"home": MenuSupport.field(row, "Home", "random").strip_edges(),
			"away": MenuSupport.field(row, "Away", "random").strip_edges(),
			"home_picks": MenuSupport.field(row, "Home Picks", "random").strip_edges().to_lower(),
			"away_picks": MenuSupport.field(row, "Away Picks", "random").strip_edges().to_lower(),
			"share": share,
		})
	if out.is_empty():
		out.append({"name": "random vs random", "home": "random", "away": "random",
			"home_picks": "random", "away_picks": "random", "share": 1.0})
	return out


# =============================================================
#  A TEAM
# =============================================================

func _team(klass: String) -> Dictionary:
	var stars: Array[PlayerData] = []
	for s in db.stars_by_class().get(klass, []):
		stars.append(s as PlayerData)
	var star_tier := db.star_tier_for_class(klass) if not stars.is_empty() else ""
	var pool := db.roster_for_class(klass)
	var tiers := {}
	for t in TIERS:
		var cards: Array[PlayerData] = []
		if t != star_tier:
			for c in TierLadder.build(pool, t, db, true)["cards"]:
				cards.append(c as PlayerData)
		tiers[t] = cards
	return {"class": klass, "stars": stars, "star_tier": star_tier, "tiers": tiers,
		"keeper": db.goalie_for_team(klass)}


func _pick(team: Dictionary, tier: String, how: String, star: PlayerData) -> PlayerData:
	if tier == String(team["star_tier"]) and star != null:
		return star
	var cards: Array[PlayerData] = team["tiers"][tier]
	if cards.is_empty():
		return null
	match how:
		"strongest":
			var best := cards[0]
			for c in cards:
				if c.get_attack_power() > best.get_attack_power():
					best = c
			return best
		"weakest":
			var low := cards[0]
			for c in cards:
				if c.get_attack_power() < low.get_attack_power():
					low = c
			return low
	return cards[rng.randi_range(0, cards.size() - 1)]


func _all_cards(team: Dictionary) -> Array:
	var out: Array = []
	for t in TIERS:
		out.append_array(team["tiers"][t])
	out.append_array(team["stars"])
	return out


# =============================================================
#  A MATCH
# =============================================================

func _resolve_class(word: String) -> String:
	if word.to_lower() == "random" or word == "":
		return classes[rng.randi_range(0, classes.size() - 1)]
	return word


func _play_match(r: Dictionary) -> void:
	var home_class := _resolve_class(String(r["home"]))
	var away_class := _resolve_class(String(r["away"]))
	var teams := {false: _team(home_class), true: _team(away_class)}
	var picks := {false: String(r["home_picks"]), true: String(r["away_picks"])}

	var e := AbilityEngine.new(db)
	e.interactive = {false: false, true: false}
	e.begin_match()
	e.sync_field(_all_cards(teams[false]), _all_cards(teams[true]))

	var stamina := {}
	var max_st := {}
	var shield := {false: 0, true: 0}
	for side in [false, true]:
		var k: GoalieData = teams[side]["keeper"]
		max_st[side] = k.max_stamina if k != null else 25
		stamina[side] = max_st[side]
	var bite := db.tune_float("shot_stamina_bite", 0.55)
	var cycles := db.tune_int("sim_cycles", 3)
	var per_cycle := db.tune_int("rounds_per_cycle", 3)
	var score := {false: 0, true: 0}
	var keeper_damage := {false: 0, true: 0}
	var match_ticks := 0
	var home_attacks := rng.randf() < 0.5

	for cycle in cycles:
		e.begin_cycle()
		var star_now := {}
		for side in [false, true]:
			var stars: Array[PlayerData] = teams[side]["stars"]
			star_now[side] = stars[cycle % stars.size()] if not stars.is_empty() else null
			var badges: Array = []
			if star_now[side] != null:
				badges.append_array(EmblemBook.on_the_field([star_now[side]]))
			e.set_emblems(side, badges)
		for round_i in per_cycle:
			var lineup := {false: [], true: []}
			for side in [false, true]:
				for t in TIERS:
					lineup[side].append(_pick(teams[side], t, String(picks[side]), star_now[side]))
			e.begin_round()
			e.round_lineups(lineup[false], lineup[true])
			e.apply_passives(lineup[false], lineup[true])
			var bank := {false: 0, true: 0}
			var has_ball := not home_attacks if round_i % 2 == 1 else home_attacks
			for i in TIERS.size():
				var mine: PlayerData = lineup[false][i]
				var theirs: PlayerData = lineup[true][i]
				if mine == null or theirs == null:
					continue
				e.begin_duel(mine, theirs)
				var atk_side := not has_ball
				var atk: PlayerData = mine if has_ball else theirs
				var def: PlayerData = theirs if has_ball else mine
				e.resolve_duel_abilities(atk, atk_side, def, "", [])
				for ask in e.take_asks():
					e.answer_default(ask)
				var mid := e.take_mid_swap()
				if not mid.is_empty():
					if atk == mid["out"]:
						atk = mid["in"]
					elif def == mid["out"]:
						def = mid["in"]
				var flip := e.take_switch()
				if not flip.is_empty():
					var was := atk
					atk = def
					def = was
					atk_side = not atk_side
					has_ball = not has_ball
				var ap := e.attack_power(atk, atk_side)
				var dp := e.defense_power(def, not atk_side)
				# SIM_TRACE=Kurt prints every duel that card plays, with the
				# engine's own log - to see WHY a card wins.
				var trace := OS.get_environment("SIM_TRACE")
				if trace != "" and (atk.player_name == trace or def.player_name == trace):
					print("  [trace] %s %s (%d) attacks %s %s (%d)%s" % [teams[atk_side]["class"], atk.player_name, ap,
						teams[not atk_side]["class"], def.player_name, dp, "  - after a SWITCH" if not flip.is_empty() else ""])
					for line in e.log_lines:
						print("  [trace]   " + String(line).strip_edges())
				var tie_to_attacker := db.tune_bool("ties_go_to_attacker", false)
				if not flip.is_empty() and db.tune_bool("switch_loses_ties", true):
					tie_to_attacker = true
				var atk_wins := ap > dp or (ap == dp and tie_to_attacker)
				_note_duel(atk, atk_side, ap, dp, atk_wins, teams, TIERS[i], e)
				_note_duel(def, not atk_side, dp, ap, not atk_wins, teams, TIERS[i], e)
				if atk_wins:
					e.resolve_duel_outcome(atk, atk_side, def, not atk_side)
					bank[atk_side] += ap + dp
				else:
					e.resolve_duel_outcome(def, not atk_side, atk, atk_side)
					bank[not atk_side] += ap + dp
					has_ball = not has_ball
				match_ticks += 1
				_drain(e)
			# THE SHOT - whoever has the ball after Tier IV.
			var shooter_side: bool = not has_ball
			var shooter: PlayerData = lineup[shooter_side][TIERS.size() - 1]
			var power: int = int(bank[shooter_side]) + e.shot_bonus(shooter_side)
			if shooter != null:
				power += e.fire_on_shot(shooter, shooter_side)
			_keeper_changes(e, stamina, max_st, shield)
			var keeper_side: bool = not shooter_side
			var scored := false
			if power > 0:
				var chance := clampf(ShotOdds.chance(int(stamina[keeper_side]), int(max_st[keeper_side]), power)
					+ e.keeper_shift(keeper_side), 0.0, 100.0)
				scored = rng.randf() * 100.0 < chance
				var loss := maxi(1, int(round(float(power) * bite)))
				var soaked := mini(int(shield[keeper_side]), loss)
				shield[keeper_side] = int(shield[keeper_side]) - soaked
				loss -= soaked
				var before := int(stamina[keeper_side])
				stamina[keeper_side] = maxi(0, before - loss)
				keeper_damage[shooter_side] = int(keeper_damage[shooter_side]) + (before - int(stamina[keeper_side]))
				if scored:
					score[shooter_side] = int(score[shooter_side]) + 1
					stamina[keeper_side] = max_st[keeper_side]
					if shooter != null:
						var key := _card_key(teams[shooter_side]["class"], shooter)
						by_card[key]["goals"] = int(by_card[key]["goals"]) + 1
				e.after_shot(shooter_side, scored)
			e.round_finished()
			_keeper_changes(e, stamina, max_st, shield)
			_drain(e)
			home_attacks = not home_attacks
		e.close_cycle()
	e.finish_match()
	_drain(e)

	ticks.append(match_ticks)
	goals_per_match.append(int(score[false]) + int(score[true]))
	for side in [false, true]:
		var klass := String(teams[side]["class"])
		var row: Dictionary = _class_row(klass)
		row["played"] = int(row["played"]) + 1
		var us := int(score[side])
		var them := int(score[not side])
		var verdict := "won" if us > them else ("lost" if us < them else "drawn")
		row[verdict] = int(row[verdict]) + 1
		row["goals_for"] = int(row["goals_for"]) + us
		row["goals_against"] = int(row["goals_against"]) + them
		row["keeper_damage_dealt"] = int(row["keeper_damage_dealt"]) + int(keeper_damage[side])
	var mk := String(r["name"])
	# The class table again, split by matchup row - a class that only looks
	# strong because one row made it play "strongest" shows up here.
	for side in [false, true]:
		var klass := String(teams[side]["class"])
		if not by_matchup_class.has(mk):
			by_matchup_class[mk] = {}
		var t: Dictionary = by_matchup_class[mk]
		if not t.has(klass):
			t[klass] = {"played": 0, "won": 0, "drawn": 0, "lost": 0}
		var us := int(score[side])
		var them := int(score[not side])
		t[klass]["played"] = int(t[klass]["played"]) + 1
		var verdict := "won" if us > them else ("lost" if us < them else "drawn")
		t[klass][verdict] = int(t[klass][verdict]) + 1
	if not by_matchup.has(mk):
		by_matchup[mk] = {"played": 0, "home_won": 0, "away_won": 0, "drawn": 0, "home": r["home"], "away": r["away"],
			"home_picks": r["home_picks"], "away_picks": r["away_picks"]}
	var m: Dictionary = by_matchup[mk]
	m["played"] = int(m["played"]) + 1
	if int(score[false]) > int(score[true]):
		m["home_won"] = int(m["home_won"]) + 1
	elif int(score[false]) < int(score[true]):
		m["away_won"] = int(m["away_won"]) + 1
	else:
		m["drawn"] = int(m["drawn"]) + 1


func _keeper_changes(e: AbilityEngine, stamina: Dictionary, max_st: Dictionary, shield: Dictionary) -> void:
	for ch in e.take_pending_stamina():
		var side := bool(ch.get("enemy_side", false))
		var delta := int(ch.get("delta", 0))
		# A shield stops SHOTS only, as in the match (`shield_blocks_drains`).
		if delta < 0 and db.tune_bool("shield_blocks_drains", false):
			var soaked := mini(int(shield[side]), -delta)
			shield[side] = int(shield[side]) - soaked
			delta += soaked
		stamina[side] = clampi(int(stamina[side]) + delta, 0, int(max_st[side]))
		shield[side] = int(shield[side]) + int(ch.get("shield", 0))


func _drain(e: AbilityEngine) -> void:
	e.take_events()
	e.take_swaps()
	e.take_zone_moves()
	e.take_cold_touch()
	e.take_gravestones()
	e.take_emblem_resets()
	e.take_mid_swap()
	e.take_switch()
	for ask in e.take_asks():
		e.answer_default(ask)
	e.log_lines.clear()


# =============================================================
#  COUNTING
# =============================================================

func _class_row(klass: String) -> Dictionary:
	if not by_class.has(klass):
		by_class[klass] = {"played": 0, "won": 0, "drawn": 0, "lost": 0, "goals_for": 0, "goals_against": 0,
			"keeper_damage_dealt": 0, "triggers": 0, "duels": {}}
	return by_class[klass]


func _card_key(klass: String, card: PlayerData) -> String:
	var key := "%s|%s" % [klass, card.player_name]
	if not by_card.has(key):
		by_card[key] = {"class": klass, "name": card.player_name, "tier": card.get_tier_clean(),
			"printed_power": card.get_attack_power(), "star": card.is_star(), "duels": 0, "duels_won": 0,
			"power_dealt": 0, "power_faced": 0, "abilities_fired": 0, "goals": 0}
	return key


func _note_duel(card: PlayerData, side: bool, mine: int, theirs: int, won: bool, teams: Dictionary, tier: String, e: AbilityEngine) -> void:
	var klass := String(teams[side]["class"])
	# A token or a card swapped in from outside the team still counts for the class.
	var key := _card_key(klass, card)
	var c: Dictionary = by_card[key]
	c["duels"] = int(c["duels"]) + 1
	c["duels_won"] = int(c["duels_won"]) + (1 if won else 0)
	c["power_dealt"] = int(c["power_dealt"]) + mine
	c["power_faced"] = int(c["power_faced"]) + theirs
	var fired := e.fired_in_duel(card, side)
	c["abilities_fired"] = int(c["abilities_fired"]) + fired.size()
	for id in fired:
		by_ability[String(id)] = int(by_ability.get(String(id), 0)) + 1
	var row := _class_row(klass)
	row["triggers"] = int(row["triggers"]) + fired.size()
	var d: Dictionary = row["duels"]
	if not d.has(tier):
		d[tier] = {"won": 0, "total": 0}
	d[tier]["total"] = int(d[tier]["total"]) + 1
	d[tier]["won"] = int(d[tier]["won"]) + (1 if won else 0)


func _report(played: int, seed_value: int, ms: int) -> Dictionary:
	var classes_out := {}
	for klass in by_class:
		var r: Dictionary = by_class[klass]
		var p := maxi(1, int(r["played"]))
		var tiers := {}
		for t in r["duels"]:
			var d: Dictionary = r["duels"][t]
			tiers[t] = {"won": d["won"], "total": d["total"], "win_rate": snappedf(float(d["won"]) / maxf(1.0, float(d["total"])), 0.001)}
		classes_out[klass] = {
			"played": r["played"], "won": r["won"], "drawn": r["drawn"], "lost": r["lost"],
			"win_rate": snappedf(float(r["won"]) / p, 0.001),
			"win_rate_draws_half": snappedf((float(r["won"]) + 0.5 * float(r["drawn"])) / p, 0.001),
			"goals_for_per_match": snappedf(float(r["goals_for"]) / p, 0.01),
			"goals_against_per_match": snappedf(float(r["goals_against"]) / p, 0.01),
			"keeper_damage_per_match": snappedf(float(r["keeper_damage_dealt"]) / p, 0.01),
			"ability_triggers_per_match": snappedf(float(r["triggers"]) / p, 0.01),
			"duels_by_tier": tiers,
		}
	var cards_out: Array = []
	for key in by_card:
		var c: Dictionary = by_card[key]
		var n := maxi(1, int(c["duels"]))
		var row := c.duplicate()
		row["duel_win_rate"] = snappedf(float(c["duels_won"]) / n, 0.001)
		row["power_per_duel"] = snappedf(float(c["power_dealt"]) / n, 0.01)
		row["power_faced_per_duel"] = snappedf(float(c["power_faced"]) / n, 0.01)
		row["abilities_per_duel"] = snappedf(float(c["abilities_fired"]) / n, 0.01)
		cards_out.append(row)
	cards_out.sort_custom(func(a, b): return float(a["duel_win_rate"]) > float(b["duel_win_rate"]))
	var abil: Array = []
	for id in by_ability:
		abil.append({"ability": id, "fired": by_ability[id], "per_match": snappedf(float(by_ability[id]) / maxf(1.0, played), 0.001)})
	abil.sort_custom(func(a, b): return int(a["fired"]) > int(b["fired"]))
	var t_sum := 0
	for t in ticks:
		t_sum += t
	var g_sum := 0
	for g in goals_per_match:
		g_sum += g
	return {
		"about": "Sturmball headless combat simulation (tests/sim_runner.gd). Engine-level: no pitch, no fouls, no Emblem race/Ultimates; questions answered with defaults. Power stands in for damage: there are no hit points.",
		"made": Time.get_datetime_string_from_system(),
		"matches": played,
		"seed": seed_value,
		"seconds": snappedf(ms / 1000.0, 0.1),
		"match": {"ticks_per_match": snappedf(float(t_sum) / maxf(1, ticks.size()), 0.01),
			"goals_per_match": snappedf(float(g_sum) / maxf(1, goals_per_match.size()), 0.01)},
		"matchups": by_matchup,
		"classes_by_matchup": by_matchup_class,
		"classes": classes_out,
		"cards": cards_out,
		"abilities": abil,
	}
