extends Node

# =============================================================
#  STURMBALL LAB - the rules, with no pitch, in a browser
#
#  A playtest bench for the combat. It runs the REAL rules code - the same
#  AbilityEngine, CardDatabase, TierLadder, EmblemBook and ShotOdds the game
#  runs, reading the same data/*.csv - and hands every number back as JSON,
#  so a plain web page can show what happened and why.
#
#  Build it with tools/lab/build.sh. It is exported to the web (Godot's
#  "Web" export, no threads) and driven from tools/lab/web/index.html:
#
#      window.sbLabCall(JSON.stringify({cmd: "meta"}))
#      JSON.parse(window.sbLabOut)
#
#  The same commands work on the command line, for checking it:
#
#      godot --headless --path . --script res://tools/lab/lab_cli.gd -- '{"cmd":"meta"}'
#
#  ============ THE MATCH IS THE SIMULATOR'S MATCH ============
#
#  One round is played exactly as tests/sim_runner.gd plays it (which is
#  main_scene.gd without the pitch): passives, four duels with abilities on
#  the stack, the bank, the shot against the keeper with ShotOdds.csv. What
#  only exists on the grass is left out: touches, mines being worked,
#  gravestones, fouls and free kicks, and the Emblem RACE (no Ultimates).
#  Questions a card would ask are answered with their default.
#
#  Nothing here is a copy of a rule. If a number is wrong in the lab it is
#  wrong in the game.
# =============================================================

const TIERS: Array[String] = ["I", "II", "III", "IV"]
const HOME := false   # the engine's "player" side
const AWAY := true    # the engine's "enemy" side

var db: CardDatabase
var rng := RandomNumberGenerator.new()
var _js_callback = null

## The match being played step by step (cmd "match_new" / "match_round").
var m: Dictionary = {}


var adv: Node = null


func _ready() -> void:
	db = CardDatabase.get_db()
	_adv()
	if OS.has_feature("web"):
		var win = JavaScriptBridge.get_interface("window")
		_js_callback = JavaScriptBridge.create_callback(_on_js)
		win.sbLabCall = _js_callback
		win.sbLabOut = JSON.stringify({"ok": true, "ready": true})


func _on_js(args: Array) -> void:
	var text := String(args[0]) if args.size() > 0 else "{}"
	var out := handle_text(text)
	JavaScriptBridge.get_interface("window").sbLabOut = out


func handle_text(text: String) -> String:
	var req = JSON.parse_string(text)
	if typeof(req) != TYPE_DICTIONARY:
		return JSON.stringify({"ok": false, "error": "not a JSON object: %s" % text.left(200)})
	var out: Dictionary = handle(req)
	return JSON.stringify(out)


func handle(req: Dictionary) -> Dictionary:
	if db == null:
		db = CardDatabase.get_db()
	var cmd := String(req.get("cmd", ""))
	if cmd.begins_with("adv_"):
		return _adv().handle(req)
	match cmd:
		"meta":
			return _meta()
		"match_new":
			return _match_new(req)
		"match_round":
			return _match_round(req)
		"sim":
			return _sim(req)
		"tune":
			return _tune(req)
		"files_list":
			return _files_list()
		"files_get":
			return _files_get(req)
		"files_set":
			return _files_set(req)
	return {"ok": false, "error": "unknown cmd '%s'" % cmd}


func _adv() -> Node:
	if adv == null:
		adv = load("res://tools/lab/lab_adventure.gd").new()
		adv.name = "Adventure"
		add_child(adv)
	return adv


# =============================================================
#  WHAT THERE IS - classes, cards, abilities, the numbers
# =============================================================

func _classes() -> Array[String]:
	var out: Array[String] = []
	for key in db.stars_by_class().keys():
		out.append(String(key))
	out.sort()
	# The Basic Team: plain cards, no Stars.
	if not out.has("Normal") and not db.roster_for_class("Normal").is_empty():
		out.append("Normal")
	return out


func _ability_json(id_text: String) -> Dictionary:
	var a := db.get_ability(id_text)
	if a == null:
		return {}
	return {"id": a.id, "name": a.display_name, "trigger": a.trigger, "target": a.target,
		"effect": a.effect, "value": a.value, "scope": a.scope, "condition": a.condition,
		"arg": a.effect_arg, "cost": ("%s %d" % [a.cost_kind, a.cost_amount]) if a.cost_kind != "" else "",
		"max": a.max_uses, "max_per": a.max_per, "ask": a.ask}


func _card_json(card: PlayerData) -> Dictionary:
	if card == null:
		return {}
	var out := {"name": card.player_name, "class": card.unit_type, "tier": card.get_tier_clean(),
		"atk": card.get_attack_power(), "def": card.get_defense_power(),
		"element": card.active_element(), "star": card.is_star(), "set": card.card_set,
		"attack_text": card.attack_text.strip_edges(), "defend_text": card.defend_text.strip_edges(),
		"attack_ability": _ability_json(card.active_attack_ability()),
		"defend_ability": _ability_json(card.active_defend_ability())}
	if card.is_star():
		out["ultimate_text"] = card.ultimate_text.strip_edges()
		var badge := EmblemBook.for_star(card)
		if badge != null:
			out["emblem"] = {"id": badge.id, "basic": badge.basic, "condition": badge.condition,
				"turns_on": badge.turns_on, "ultimate": badge.ultimate}
	return out


func _meta() -> Dictionary:
	var classes: Dictionary = {}
	for klass in _classes():
		var tiers: Dictionary = {}
		var star_tier := db.star_tier_for_class(klass)
		var pool := db.roster_for_class(klass)
		for t in TIERS:
			var cards: Array = []
			for c in pool:
				if c.get_tier_clean() == t:
					cards.append(_card_json(c))
			cards.sort_custom(func(a, b): return int(a["atk"]) < int(b["atk"]))
			tiers[t] = cards
		var stars: Array = []
		for s in db.star_ladder_for_class(klass):
			stars.append(_card_json(s))
		var keeper := db.goalie_for_team(klass)
		classes[klass] = {"star_tier": star_tier, "tiers": tiers, "stars": stars,
			"keeper": {"name": keeper.goalie_name, "stamina": keeper.max_stamina,
				"ability": keeper.ability_text.strip_edges()} if keeper != null else {"name": "(none)", "stamina": 25, "ability": ""}}
	var rungs := {}
	for t in TIERS:
		rungs[t] = TierLadder.rungs(t, db)
	var combos: Array = []
	for r in ComboDB.get_db().rules:
		combos.append(r)
	var odds: Array = ShotOdds.rows()
	var tune_keys := ["build_stamp", "ties_go_to_attacker", "switch_loses_ties", "shot_stamina_bite",
		"rounds_per_cycle", "sim_cycles", "max_card_power", "shield_blocks_drains", "emblems_on_field",
		"shot_odds"]
	var tuning := {}
	for k in tune_keys:
		tuning[k] = db.tune_text(k, "")
	var all_tuning := {}
	for k in db.tuning.keys():
		all_tuning[k] = db.tuning[k]
	return {"ok": true, "build": db.tune_text("build_stamp", "?"), "classes": classes, "rungs": rungs,
		"combos": combos, "shot_odds": odds, "tuning": tuning, "all_tuning": all_tuning,
		"problems": db.problems.slice(0, 40)}


## Change Tuning.csv values for this session only: {"cmd":"tune","set":{"key":"value"}}.
## {"cmd":"tune","reset":true} reads the spreadsheets again.
func _tune(req: Dictionary) -> Dictionary:
	if bool(req.get("reset", false)):
		CardDatabase.reload_files()
		db = CardDatabase.get_db()
		ShotOdds.forget()
	var sets: Dictionary = req.get("set", {})
	for k in sets.keys():
		db.tuning[String(k).to_lower()] = String(sets[k])
	ShotOdds.forget()
	return {"ok": true, "changed": sets.keys()}


# =============================================================
#  A TEAM
# =============================================================

func _find(cards: Array, name: String) -> PlayerData:
	for c in cards:
		if c != null and (c as PlayerData).player_name == name:
			return c
	return null


## `squad` (optional): {"I": ["name", ...], ...} - which card stands on each
## rung. Anything missing is filled by the tier ladder, as the game does.
func _team(klass: String, squad: Dictionary) -> Dictionary:
	var stars: Array[PlayerData] = []
	for s in db.star_ladder_for_class(klass):
		stars.append(s)
	if stars.is_empty():
		for s in db.stars_by_class().get(klass, []):
			stars.append(s as PlayerData)
	var star_tier := db.star_tier_for_class(klass) if not stars.is_empty() else ""
	var pool := db.roster_for_class(klass)
	var tiers := {}
	for t in TIERS:
		var cards: Array[PlayerData] = []
		if t != star_tier:
			var wanted: Array = []
			for n in (squad.get(t, []) as Array):
				var c := _find(pool, String(n))
				if c != null and c.get_tier_clean() == t:
					wanted.append(c)
			var built: Dictionary = TierLadder.build(wanted, t, db, false, pool)
			for c in built["cards"]:
				cards.append(c as PlayerData)
		tiers[t] = cards
	return {"class": klass, "stars": stars, "star_tier": star_tier, "tiers": tiers,
		"keeper": db.goalie_for_team(klass)}


func _all_cards(team: Dictionary) -> Array:
	var out: Array = []
	for t in TIERS:
		out.append_array(team["tiers"][t])
	out.append_array(team["stars"])
	return out


func _squad_json(team: Dictionary) -> Dictionary:
	var tiers := {}
	for t in TIERS:
		var names: Array = []
		for c in team["tiers"][t]:
			names.append((c as PlayerData).player_name)
		tiers[t] = names
	var stars: Array = []
	for s in team["stars"]:
		stars.append((s as PlayerData).player_name)
	var k: GoalieData = team["keeper"]
	return {"class": team["class"], "star_tier": team["star_tier"], "tiers": tiers, "stars": stars,
		"keeper": k.goalie_name if k != null else "(none)"}


## One card for a tier: a name, or "random" / "strongest" / "weakest".
func _pick(team: Dictionary, tier: String, how: String, star: PlayerData, ready_only: Array) -> PlayerData:
	if tier == String(team["star_tier"]) and star != null:
		return star
	var cards: Array = (team["tiers"][tier] as Array).duplicate()
	if cards.is_empty():
		return null
	if how.begins_with("#") and how.substr(1).is_valid_int():
		var at := int(how.substr(1))
		if at >= 0 and at < cards.size():
			return cards[at]
	var named := _find(cards, how)
	if named != null:
		return named
	# Prefer cards that are still on the field (not in the exhaust).
	if not ready_only.is_empty():
		var fresh: Array = []
		for c in cards:
			if ready_only.has(c):
				fresh.append(c)
		if not fresh.is_empty():
			cards = fresh
	match how:
		"strongest":
			var best: PlayerData = cards[0]
			for c in cards:
				if c.get_attack_power() > best.get_attack_power():
					best = c
			return best
		"weakest":
			var low: PlayerData = cards[0]
			for c in cards:
				if c.get_attack_power() < low.get_attack_power():
					low = c
			return low
	return cards[rng.randi_range(0, cards.size() - 1)]


# =============================================================
#  A MATCH, ROUND BY ROUND
# =============================================================

func _new_match(req: Dictionary) -> Dictionary:
	var home_class := String(req.get("home", "Lorelei"))
	var away_class := String(req.get("away", "Bergmännlein"))
	var squads: Dictionary = req.get("squads", {})
	var s := {}
	s["teams"] = {HOME: _team(home_class, squads.get("home", {})), AWAY: _team(away_class, squads.get("away", {}))}
	var e := AbilityEngine.new(db)
	e.interactive = {false: false, true: false}
	e.max_power = db.tune_int("max_card_power", 5)
	e.abilities_off = bool(req.get("no_abilities", false))
	e.begin_match()
	e.sync_field(_all_cards(s["teams"][HOME]), _all_cards(s["teams"][AWAY]))
	s["e"] = e
	s["stamina"] = {}
	s["max_st"] = {}
	s["shield"] = {HOME: 0, AWAY: 0}
	s["dmg"] = {HOME: 0, AWAY: 0}     # keeper stamina lost, all match
	for side in [HOME, AWAY]:
		var k: GoalieData = s["teams"][side]["keeper"]
		s["max_st"][side] = k.max_stamina if k != null else 25
		s["stamina"][side] = s["max_st"][side]
	s["score"] = {HOME: 0, AWAY: 0}
	s["cycle"] = 0
	s["round"] = 0          # round within the cycle
	s["cycles"] = int(req.get("cycles", db.tune_int("sim_cycles", 3)))
	s["per_cycle"] = db.tune_int("rounds_per_cycle", 3)
	var first := String(req.get("kickoff", "random"))
	s["home_attacks"] = rng.randf() < 0.5 if first == "random" else first == "home"
	s["star_now"] = {HOME: null, AWAY: null}
	s["combos_on"] = bool(req.get("combos", false))
	s["done"] = false
	s["stats"] = {"duels": 0}
	return s


func _match_new(req: Dictionary) -> Dictionary:
	var seed_value := int(req.get("seed", 0))
	if seed_value == 0:
		seed_value = int(Time.get_unix_time_from_system()) % 1000000 + randi() % 1000
	rng.seed = seed_value
	seed(seed_value)
	m = _new_match(req)
	return {"ok": true, "seed": seed_value, "state": _state_json(m),
		"home": _squad_json(m["teams"][HOME]), "away": _squad_json(m["teams"][AWAY])}


func _side_name(side: bool) -> String:
	return "away" if side else "home"


func _state_json(s: Dictionary) -> Dictionary:
	var e: AbilityEngine = s["e"]
	var zones := {}
	for side in [HOME, AWAY]:
		var team: Dictionary = s["teams"][side]
		var z := {"stars": []}
		for t in TIERS:
			z[t] = []
			for c in team["tiers"][t]:
				z[t].append(_zone_card(e, c, side))
		for c in team["stars"]:
			z["stars"].append(_zone_card(e, c, side))
		z["star_tier"] = team["star_tier"]
		z["star_now"] = (s["star_now"][side] as PlayerData).player_name if s["star_now"][side] != null else ""
		zones[_side_name(side)] = z
	return {"cycle": int(s["cycle"]) + 1, "round": int(s["round"]) + 1, "cycles": s["cycles"],
		"per_cycle": s["per_cycle"], "done": s["done"],
		"score": {"home": s["score"][HOME], "away": s["score"][AWAY]},
		"stamina": {"home": s["stamina"][HOME], "away": s["stamina"][AWAY]},
		"max_stamina": {"home": s["max_st"][HOME], "away": s["max_st"][AWAY]},
		"shield": {"home": s["shield"][HOME], "away": s["shield"][AWAY]},
		"keeper_damage": {"home": s["dmg"][HOME], "away": s["dmg"][AWAY]},
		"home_attacks_next": _next_has_ball(s) == HOME if not s["done"] else false,
		"ore": {"home": e.pool(HOME, "ore"), "away": e.pool(AWAY, "ore")},
		"squads": zones}


func _zone_card(e: AbilityEngine, c: PlayerData, side: bool) -> Dictionary:
	return {"name": c.player_name, "zone": e.zone_of(c, 1 if side else 0), "atk": c.get_attack_power(),
		"def": c.get_defense_power(), "token": c.is_token(), "element": c.active_element(),
		"text": c.attack_text.strip_edges() if c.is_token() else ""}


## Who has the ball at the start of the round about to be played: home
## attacks in the first round of a pair, the other side in the second.
func _next_has_ball(s: Dictionary) -> bool:
	var home_has := bool(s["home_attacks"])
	if int(s["round"]) % 2 == 1:
		home_has = not home_has
	return HOME if home_has else AWAY


func _take_lines(e: AbilityEngine) -> Array:
	var out: Array = []
	for l in e.log_lines:
		out.append(String(l).strip_edges())
	e.log_lines.clear()
	return out


func _events_text(e: AbilityEngine) -> Array:
	var out: Array = []
	for ev in e.take_events():
		var f: Dictionary = ev.get("facts", {})
		var what := String(ev.get("event", ""))
		if what == "card_played":
			continue
		out.append("%s: %s%s" % [_side_name(bool(ev.get("enemy", false))), what,
			(" (" + String(f.get("card", "")) + ")") if f.has("card") else ""])
	return out


func _drain(e: AbilityEngine, into: Array) -> void:
	into.append_array(_events_text(e))
	for sw in e.take_swaps():
		_apply_swap(sw)
		var o = sw.get("old")
		var n = sw.get("new")
		into.append("%s: %s becomes %s%s" % [_side_name(bool(sw.get("side", false))),
			(o as PlayerData).player_name if o is PlayerData else "?",
			(n as PlayerData).player_name if n is PlayerData else "?",
			(" (" + String(sw.get("kind", "")) + " token)") if String(sw.get("kind", "")) != "" else ""])
	e.take_zone_moves()
	e.take_cold_touch()
	e.take_gravestones()
	e.take_emblem_resets()
	e.take_mid_swap()
	e.take_switch()
	for ask in e.take_asks():
		into.append("question answered with its default: %s" % String(ask.get("text", ask.get("kind", "?"))))
		e.answer_default(ask)
	into.append_array(_take_lines(e))


## A token took a card's place (or gave it back). In the match the body on
## the pitch takes the new card, so the draft offers the token from then on;
## the lab swaps it in the squad list the same way.
var _s: Dictionary = {}

func _apply_swap(sw: Dictionary) -> void:
	if _s.is_empty():
		return
	var team: Dictionary = _s["teams"][bool(sw.get("side", false))]
	for t in TIERS:
		var cards: Array = team["tiers"][t]
		var at := cards.find(sw.get("old"))
		if at >= 0:
			cards[at] = sw.get("new")
	var stars: Array = team["stars"]
	var st := stars.find(sw.get("old"))
	if st >= 0:
		stars[st] = sw.get("new")


func _keeper_changes(s: Dictionary, into: Array) -> void:
	var e: AbilityEngine = s["e"]
	for ch in e.take_pending_stamina():
		var side := bool(ch.get("enemy_side", false))
		var delta := int(ch.get("delta", 0))
		if delta < 0 and db.tune_bool("shield_blocks_drains", false):
			var soaked := mini(int(s["shield"][side]), -delta)
			s["shield"][side] = int(s["shield"][side]) - soaked
			delta += soaked
		var before := int(s["stamina"][side])
		s["stamina"][side] = clampi(before + delta, 0, int(s["max_st"][side]))
		s["dmg"][side] = int(s["dmg"][side]) + maxi(0, before - int(s["stamina"][side]))
		s["shield"][side] = int(s["shield"][side]) + int(ch.get("shield", 0))
		if into != null:
			into.append("%s keeper: stamina %d -> %d%s" % [_side_name(side), before, int(s["stamina"][side]),
				(", shield +%d" % int(ch.get("shield", 0))) if int(ch.get("shield", 0)) != 0 else ""])


## THE ROUND. `plan` = {"home": [4 picks], "away": [4 picks], "stars": {"home": name, "away": name}}
## where a pick is a card name or random / strongest / weakest.
func _play_round(s: Dictionary, plan: Dictionary, logging: bool) -> Dictionary:
	var e: AbilityEngine = s["e"]
	_s = s
	var teams: Dictionary = s["teams"]
	var out := {"cycle": int(s["cycle"]) + 1, "round": int(s["round"]) + 1, "before": [], "duels": [], "after": []}

	# A NEW CYCLE: the Star Player switch, and the exhaust comes back.
	if int(s["round"]) == 0:
		if int(s["cycle"]) > 0:
			e.begin_cycle()
		var star_pick: Dictionary = plan.get("stars", {})
		for side in [HOME, AWAY]:
			var stars: Array[PlayerData] = teams[side]["stars"]
			var star: PlayerData = null
			if not stars.is_empty():
				star = _find(stars, String(star_pick.get(_side_name(side), "")))
				if star == null:
					star = stars[int(s["cycle"]) % stars.size()]
			s["star_now"][side] = star
			var badges: Array = []
			if star != null:
				badges.append_array(EmblemBook.on_the_field([star]))
			e.set_emblems(side, badges)
		out["stars"] = {"home": s["star_now"][HOME].player_name if s["star_now"][HOME] != null else "",
			"away": s["star_now"][AWAY].player_name if s["star_now"][AWAY] != null else ""}
		_drain(e, out["before"])

	var lineup := {HOME: [], AWAY: []}
	for side in [HOME, AWAY]:
		var picks: Array = plan.get(_side_name(side), [])
		var ready_cards: Array = e.cards_in(side, "field")
		for i in TIERS.size():
			var how := String(picks[i]) if i < picks.size() else String(plan.get(_side_name(side) + "_how", "random"))
			lineup[side].append(_pick(teams[side], TIERS[i], how, s["star_now"][side], ready_cards))
	for side in [HOME, AWAY]:
		e.keeper_stamina[side] = s["stamina"][side]
	e.begin_round()
	e.round_lineups(lineup[HOME], lineup[AWAY])
	e.apply_passives(lineup[HOME], lineup[AWAY])
	if logging:
		out["lineup"] = {"home": lineup[HOME].map(func(c): return _card_json(c)),
			"away": lineup[AWAY].map(func(c): return _card_json(c))}
		_drain(e, out["before"])
	else:
		_drain(e, [])

	var bank := {HOME: 0, AWAY: 0}
	var has_ball: bool = _next_has_ball(s)
	out["has_ball_first"] = _side_name(has_ball)
	for i in TIERS.size():
		var mine: PlayerData = lineup[HOME][i]
		var theirs: PlayerData = lineup[AWAY][i]
		if mine == null or theirs == null:
			if logging:
				out["duels"].append({"tier": TIERS[i], "skipped": true})
			continue
		e.begin_duel(mine, theirs)
		var pre: Array = []
		if logging:
			pre = _take_lines(e)
		var atk_side := has_ball
		var atk: PlayerData = mine if has_ball == HOME else theirs
		var def: PlayerData = theirs if has_ball == HOME else mine
		var atk_before := e.attack_power(atk, atk_side)
		var def_before := e.defense_power(def, not atk_side)
		# THE STACK ORDER: lower Ability Priority resolves first, the attacker
		# on a tie (AbilityEngine.resolve_duel_abilities).
		var prio := {"atk": atk.get_ability_priority() + e.priority_mod(atk, atk_side),
			"def": def.get_ability_priority() + e.priority_mod(def, not atk_side)}
		e.resolve_duel_abilities(atk, atk_side, def, "", [])
		var asks: Array = []
		for ask in e.take_asks():
			asks.append(String(ask.get("text", ask.get("kind", "?"))))
			e.answer_default(ask)
		var notes: Array = []
		var mid := e.take_mid_swap()
		if not mid.is_empty():
			notes.append("%s swaps out, %s comes in" % [(mid["out"] as PlayerData).player_name, (mid["in"] as PlayerData).player_name])
			if atk == mid["out"]:
				atk = mid["in"]
			elif def == mid["out"]:
				def = mid["in"]
		var flip := e.take_switch()
		if not flip.is_empty():
			notes.append("%s SWITCHES to defender - the duel turns round" % (flip["card"] as PlayerData).player_name)
			var was := atk
			atk = def
			def = was
			var wb := atk_before
			atk_before = def_before
			def_before = wb
			atk_side = not atk_side
			has_ball = not has_ball
		var ap := e.attack_power(atk, atk_side)
		var dp := e.defense_power(def, not atk_side)
		var tie_to_attacker := db.tune_bool("ties_go_to_attacker", false)
		var tie_rule := "ties go to the defender" if not tie_to_attacker else "ties go to the attacker"
		if not flip.is_empty() and db.tune_bool("switch_loses_ties", true):
			tie_to_attacker = true
			tie_rule = "a card that switched does not get the tie (switch_loses_ties)"
		var atk_wins := ap > dp or (ap == dp and tie_to_attacker)
		var fired_atk := e.fired_in_duel(atk, atk_side)
		var fired_def := e.fired_in_duel(def, not atk_side)
		if atk_wins:
			e.resolve_duel_outcome(atk, atk_side, def, not atk_side)
			bank[atk_side] += ap + dp
		else:
			e.resolve_duel_outcome(def, not atk_side, atk, atk_side)
			bank[not atk_side] += ap + dp
			has_ball = not has_ball
		s["stats"]["duels"] = int(s["stats"]["duels"]) + 1
		if logging:
			var lines: Array = []
			lines.append_array(pre)
			_drain(e, lines)
			out["duels"].append({"tier": TIERS[i],
				"atk": {"side": _side_name(atk_side), "name": atk.player_name, "printed": atk.get_attack_power(),
					"before": atk_before, "power": ap, "fired": fired_atk},
				"def": {"side": _side_name(not atk_side), "name": def.player_name, "printed": def.get_defense_power(),
					"before": def_before, "power": dp, "fired": fired_def},
				"prio": prio, "first": "atk" if int(prio["atk"]) <= int(prio["def"]) else "def",
				"notes": notes, "asks": asks, "lines": lines, "tie": ap == dp, "tie_rule": tie_rule if ap == dp else "",
				"winner": _side_name(atk_side if atk_wins else not atk_side), "turnover": not atk_wins,
				"banked": ap + dp, "bank": {"home": bank[HOME], "away": bank[AWAY]}})
		else:
			_drain(e, [])
		if s.has("tally"):
			_tally_duel(s, atk, atk_side, ap, dp, atk_wins, TIERS[i], fired_atk)
			_tally_duel(s, def, not atk_side, dp, ap, not atk_wins, TIERS[i], fired_def)

	# THE SHOT - whoever has the ball after Tier IV.
	var shooter_side: bool = has_ball
	var shooter: PlayerData = lineup[shooter_side][TIERS.size() - 1]
	var shot := {"side": _side_name(shooter_side), "shooter": shooter.player_name if shooter != null else "?",
		"bank": bank[shooter_side], "ability_bonus": e.shot_bonus(shooter_side)}
	var power: int = int(bank[shooter_side]) + e.shot_bonus(shooter_side)
	var on_shot := 0
	if shooter != null:
		on_shot = e.fire_on_shot(shooter, shooter_side)
	power += on_shot
	shot["on_shot"] = on_shot
	var combo_rows: Array = ComboDB.fired(lineup[shooter_side])
	var combo_bonus := 0
	for r in combo_rows:
		combo_bonus += int(r["bonus"])
	shot["combos"] = combo_rows.map(func(r): return {"name": r.get("name", r.get("id", "")), "bonus": r["bonus"]})
	shot["combos_applied"] = bool(s["combos_on"])
	if s["combos_on"]:
		power += combo_bonus
	var keeper_lines: Array = []
	_keeper_changes(s, keeper_lines)
	var keeper_side: bool = not shooter_side
	shot["power"] = power
	shot["stamina_before"] = s["stamina"][keeper_side]
	shot["max_stamina"] = s["max_st"][keeper_side]
	shot["shield_before"] = s["shield"][keeper_side]
	var scored := false
	if power > 0:
		var base_chance := ShotOdds.chance(int(s["stamina"][keeper_side]), int(s["max_st"][keeper_side]), power)
		var shift := e.keeper_shift(keeper_side)
		var chance := clampf(base_chance + shift, 0.0, 100.0)
		var roll := rng.randf() * 100.0
		scored = roll < chance
		var loss := maxi(1, int(round(float(power) * db.tune_float("shot_stamina_bite", 0.55))))
		var soaked := mini(int(s["shield"][keeper_side]), loss)
		s["shield"][keeper_side] = int(s["shield"][keeper_side]) - soaked
		loss -= soaked
		s["dmg"][keeper_side] = int(s["dmg"][keeper_side]) + mini(loss, int(s["stamina"][keeper_side]))
		s["stamina"][keeper_side] = maxi(0, int(s["stamina"][keeper_side]) - loss)
		shot["chance"] = snappedf(chance, 0.1)
		shot["base_chance"] = snappedf(base_chance, 0.1)
		shot["keeper_shift"] = shift
		shot["roll"] = snappedf(roll, 0.1)
		shot["bite"] = loss
		shot["soaked"] = soaked
		if scored:
			s["score"][shooter_side] = int(s["score"][shooter_side]) + 1
			s["stamina"][keeper_side] = s["max_st"][keeper_side]
			if s.has("tally") and shooter != null:
				var key := "%s|%s" % [teams[shooter_side]["class"], shooter.player_name]
				if s["tally"]["cards"].has(key):
					s["tally"]["cards"][key]["goals"] = int(s["tally"]["cards"][key]["goals"]) + 1
		e.after_shot(shooter_side, scored)
	else:
		shot["chance"] = 0.0
		shot["note"] = "no power - no shot"
	shot["scored"] = scored
	shot["stamina_after"] = s["stamina"][keeper_side]
	shot["keeper_lines"] = keeper_lines
	out["shot"] = shot
	e.round_finished()
	var after: Array = []
	_keeper_changes(s, after)
	_drain(e, after)
	out["after"] = after if logging else []

	s["round"] = int(s["round"]) + 1
	if int(s["round"]) >= int(s["per_cycle"]):
		s["round"] = 0
		s["cycle"] = int(s["cycle"]) + 1
		s["home_attacks"] = not bool(s["home_attacks"])
		if int(s["cycle"]) >= int(s["cycles"]):
			e.finish_match()
			_drain(e, out["after"] if logging else [])
			s["done"] = true
	else:
		if int(s["round"]) % 2 == 0:
			s["home_attacks"] = not bool(s["home_attacks"])
	out["score"] = {"home": s["score"][HOME], "away": s["score"][AWAY]}
	return out


func _match_round(req: Dictionary) -> Dictionary:
	if m.is_empty():
		return {"ok": false, "error": "no match - send match_new first"}
	if m["done"]:
		return {"ok": false, "error": "the match is over", "state": _state_json(m)}
	var r := _play_round(m, req, true)
	return {"ok": true, "round": r, "state": _state_json(m)}


# =============================================================
#  MANY MATCHES
# =============================================================

func _tally_duel(s: Dictionary, card: PlayerData, side: bool, mine: int, theirs: int, won: bool, tier: String, fired: Array) -> void:
	var t: Dictionary = s["tally"]
	var klass := String(s["teams"][side]["class"])
	var key := "%s|%s" % [klass, card.player_name]
	if not t["cards"].has(key):
		t["cards"][key] = {"side": _side_name(side), "class": klass, "name": card.player_name, "tier": tier,
			"printed": card.get_attack_power(), "star": card.is_star(), "duels": 0, "won": 0,
			"power": 0, "faced": 0, "fired": 0, "goals": 0}
	var c: Dictionary = t["cards"][key]
	c["duels"] = int(c["duels"]) + 1
	c["won"] = int(c["won"]) + (1 if won else 0)
	c["power"] = int(c["power"]) + mine
	c["faced"] = int(c["faced"]) + theirs
	c["fired"] = int(c["fired"]) + fired.size()
	for id in fired:
		var ak := "%s|%s" % [_side_name(side), String(id)]
		t["abilities"][ak] = int(t["abilities"].get(ak, 0)) + 1
	var dk := "%s|%s" % [_side_name(side), tier]
	if not t["tiers"].has(dk):
		t["tiers"][dk] = {"won": 0, "total": 0}
	t["tiers"][dk]["total"] = int(t["tiers"][dk]["total"]) + 1
	t["tiers"][dk]["won"] = int(t["tiers"][dk]["won"]) + (1 if won else 0)


func _sim(req: Dictionary) -> Dictionary:
	var n := clampi(int(req.get("n", 1000)), 1, 20000)
	var seed_value := int(req.get("seed", 0))
	if seed_value == 0:
		seed_value = int(Time.get_unix_time_from_system()) % 1000000
	rng.seed = seed_value
	seed(seed_value)
	var started := Time.get_ticks_msec()
	var tally := {"cards": {}, "abilities": {}, "tiers": {}}
	var res := {"home": 0, "away": 0, "draw": 0}
	var goals := {"home": 0, "away": 0}
	var hist := {}
	var shots := {"home": 0, "away": 0}
	var shot_goals := {"home": 0, "away": 0}
	var shot_power := {"home": 0, "away": 0}
	for i in n:
		var s := _new_match(req)
		s["tally"] = tally
		while not s["done"]:
			var plan := {"home_how": String(req.get("home_picks", "random")),
				"away_how": String(req.get("away_picks", "random"))}
			var star_order: Dictionary = req.get("stars", {})
			var cyc := int(s["cycle"])
			var st := {}
			for side_name in ["home", "away"]:
				var order: Array = star_order.get(side_name, [])
				if cyc < order.size():
					st[side_name] = order[cyc]
			plan["stars"] = st
			var r := _play_round(s, plan, false)
			var sh: Dictionary = r["shot"]
			shots[sh["side"]] = int(shots[sh["side"]]) + 1
			shot_power[sh["side"]] = int(shot_power[sh["side"]]) + int(sh["power"])
			if sh["scored"]:
				shot_goals[sh["side"]] = int(shot_goals[sh["side"]]) + 1
		var h := int(s["score"][HOME])
		var a := int(s["score"][AWAY])
		goals["home"] += h
		goals["away"] += a
		var hk := "%d-%d" % [h, a]
		hist[hk] = int(hist.get(hk, 0)) + 1
		if h > a:
			res["home"] += 1
		elif a > h:
			res["away"] += 1
		else:
			res["draw"] += 1
	var cards: Array = tally["cards"].values()
	cards.sort_custom(func(x, y): return String(x["side"]) + "%02d" % TIERS.find(String(x["tier"])) + String(x["name"]) < String(y["side"]) + "%02d" % TIERS.find(String(y["tier"])) + String(y["name"]))
	var abil: Array = []
	for k in tally["abilities"].keys():
		var parts := String(k).split("|")
		abil.append({"side": parts[0], "ability": parts[1], "fired": tally["abilities"][k],
			"per_match": snappedf(float(tally["abilities"][k]) / n, 0.01)})
	abil.sort_custom(func(x, y): return int(x["fired"]) > int(y["fired"]))
	var scores: Array = []
	for k in hist.keys():
		scores.append({"score": k, "n": hist[k]})
	scores.sort_custom(func(x, y): return int(x["n"]) > int(y["n"]))
	return {"ok": true, "n": n, "seed": seed_value, "ms": Time.get_ticks_msec() - started,
		"results": res, "goals": goals, "scores": scores.slice(0, 12), "shots": shots,
		"shot_goals": shot_goals, "shot_power": shot_power,
		"tiers": tally["tiers"], "cards": cards, "abilities": abil}


# =============================================================
#  EDITING THE SPREADSHEETS IN THE BROWSER
#
#  The page edits a CSV and sends the whole text back. The lab packs every
#  edited file into a small .pck of its own and lays it over res://data/
#  (ProjectSettings.load_resource_pack with replace_files), so EVERY reader
#  in the game - CardDatabase, TraitDB, ShotOdds, ClassBook ... - reads the
#  edited file exactly as it would read a changed CSV on the Deck. Then every
#  book is told to forget what it read, and reads again on next use.
#
#  Nothing is written back to the game from here. The page keeps the edits
#  and hands them to Claude, who puts them into data/ on the round branch.
# =============================================================

const DATA := "res://data/"
var _originals: Dictionary = {}    # file name -> the text the build shipped
var _packs := 0
var _edited: Dictionary = {}       # file name -> true while overridden


func _csv_names() -> Array:
	var out: Array = []
	var dir := DirAccess.open(DATA)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.to_lower().ends_with(".csv"):
			out.append(f)
	out.sort()
	return out


func _read_text(name: String) -> String:
	var f := FileAccess.open(DATA + name, FileAccess.READ)
	if f == null:
		return ""
	var t := f.get_as_text()
	f.close()
	return t


func _files_list() -> Dictionary:
	var out: Array = []
	for n in _csv_names():
		var t := _read_text(n)
		var nl := t.find("\n")
		out.append({"name": n, "bytes": t.length(), "header": t.left(nl if nl >= 0 else t.length()).strip_edges(),
			"edited": _edited.has(n)})
	return {"ok": true, "files": out}


## {"cmd":"files_get","names":[...], "original": false}
func _files_get(req: Dictionary) -> Dictionary:
	var out := {}
	for n in (req.get("names", []) as Array):
		var name := String(n)
		if bool(req.get("original", false)) and _originals.has(name):
			out[name] = _originals[name]
		else:
			out[name] = _read_text(name)
	return {"ok": true, "files": out}


## {"cmd":"files_set","files":{"Abilities.csv": "<whole text>"}, "reset":["Combos.csv"]}
## `reset` puts a file back to what the build shipped.
func _files_set(req: Dictionary) -> Dictionary:
	var files: Dictionary = req.get("files", {})
	var reset: Array = req.get("reset", [])
	var want := {}
	for k in files.keys():
		var name := String(k).get_file()
		if not FileAccess.file_exists(DATA + name):
			return {"ok": false, "error": "no file data/%s in this build" % name}
		want[name] = String(files[k])
	for k in reset:
		var name := String(k).get_file()
		if _originals.has(name):
			want[name] = _originals[name]
	if want.is_empty():
		return {"ok": true, "changed": []}
	for name in want.keys():
		if not _originals.has(name):
			_originals[name] = _read_text(name)
	_packs += 1
	DirAccess.make_dir_recursive_absolute("user://lab_edits")
	var pck_path := "user://lab_edits/edits_%d.pck" % _packs
	var packer := PCKPacker.new()
	var err := packer.pck_start(pck_path)
	if err != OK:
		return {"ok": false, "error": "could not start the edit pack (%d)" % err}
	var i := 0
	for name in want.keys():
		i += 1
		var tmp := "user://lab_edits/%d_%d.csv" % [_packs, i]
		var w := FileAccess.open(tmp, FileAccess.WRITE)
		w.store_string(want[name])
		w.close()
		packer.add_file(DATA + name, tmp)
	err = packer.flush()
	if err != OK:
		return {"ok": false, "error": "could not write the edit pack (%d)" % err}
	if not ProjectSettings.load_resource_pack(pck_path, true):
		return {"ok": false, "error": "the engine would not take the edit pack"}
	for name in want.keys():
		if reset.has(name) and not files.has(name):
			_edited.erase(name)
		else:
			_edited[name] = true
	_forget_everything()
	# The new numbers are read now, so anything wrong with them is reported now.
	db = CardDatabase.get_db()
	var problems: Array = []
	for p in db.problems:
		if not String(p).contains("artwork '"):     # the lab ships no pictures
			problems.append(p)
	problems.append_array(ShotOdds.problems())
	var adv_db := AdventureDB.get_db()
	if adv_db.get("problems") is Array:
		problems.append_array(adv_db.get("problems"))
	m = {}
	if adv != null:
		adv.call("reset_after_edit")
	return {"ok": true, "changed": want.keys(), "edited": _edited.keys(), "problems": problems.slice(0, 80)}


## Every book that read a CSV keeps what it read in a static. Drop them all,
## so the next question reads the (edited) file again.
func _forget_everything() -> void:
	for entry in ProjectSettings.get_global_class_list():
		var path := String(entry.get("path", ""))
		if not path.begins_with("res://src/"):
			continue
		var script = load(path)
		if script == null:
			continue
		for flag in ["_loaded", "_info_loaded", "_causes_loaded"]:
			if script.get(flag) is bool:
				script.set(flag, false)
		if script.get("_instance") != null:
			script.set("_instance", null)
	ShotOdds.forget()
	TraitDB._live = []
