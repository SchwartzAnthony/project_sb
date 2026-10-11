extends Node

# =============================================================
#  STURMBALL LAB - ADVENTURE
#
#  The real AdventureEncounter, opened with no pitch (exactly the way
#  tools/adventure_soak.gd opens it), driven from the lab page.
#
#  The fight is a state machine that resolves a round on the frame after the
#  last pick, so the page sends an action (focus an enemy, pick a card, play
#  on automatically) and then asks for the state until the fight is waiting
#  again.
#
#  The fight is tools/lab/lab_encounter.gd: AdventureEncounter with only its
#  drawing and its pauses taken out, so a round resolves in a frame.
#
#  What a run is here: the party you choose walks through a biome's waves.
#  Stamina, knock-outs and the tier rotation carry from wave to wave; the
#  icon pile starts empty each fight, as in the game. Stand-ins brought on
#  by a combo go home after each fight. Items and fleeing are left out.
#
#  MANY RUNS play side by side, twelve at a time.
# =============================================================

const TIERS: Array[String] = ["I", "II", "III", "IV"]
const PARALLEL := 12

class Ctx:
	var run: AdventureRun
	var state: GameState
	var fight: AdventureEncounter
	var holder: Node
	var notes: Array[String] = []
	var notes_sent := 0
	var result := ""             # "", "cleared", "lost"
	var waves_cleared := 0
	var rounds := 0
	var auto: Dictionary = {}    # {} = off; else {"focus": .., "pick": ..}
	var fixed_wave: Array = []
	var per_wave := 0            # 0 = adventure_enemies_per_wave
	var lost_at := 0             # the wave a lost run fell in
	var counted := false

var db: CardDatabase
var adventure: AdventureDB
var one: Ctx = null                    # the run played by hand
var sim: Dictionary = {}               # many runs
var sim_runs: Array = []               # Ctx


func _ready() -> void:
	db = CardDatabase.get_db()
	adventure = AdventureDB.get_db()
	TraitDB.get_db()


func handle(req: Dictionary) -> Dictionary:
	if db == null:
		_ready()
	match String(req.get("cmd", "")):
		"adv_meta":
			return _meta()
		"adv_new":
			return _new(req)
		"adv_state":
			return _state(one)
		"adv_focus":
			if one != null and _live(one) and one.fight.step == AdventureEncounter.Step.FOCUS:
				one.fight._choose_focus(int(req.get("i", 0)))
			return _state(one)
		"adv_pick":
			if one != null:
				_pick(one, String(req.get("card", "")))
			return _state(one)
		"adv_auto":
			if one != null:
				one.auto = req.get("auto", {}) if bool(req.get("on", true)) else {}
			return _state(one)
		"adv_sim":
			return _sim_start(req)
		"adv_sim_state":
			return _sim_state()
	return {"ok": false, "error": "unknown adventure cmd"}


func _live(c: Ctx) -> bool:
	return c != null and c.fight != null and is_instance_valid(c.fight)


# =============================================================
#  WHAT THERE IS
# =============================================================

func _enemy_json(row: Dictionary) -> Dictionary:
	var layers: Array = []
	for l in row.get("layers", []):
		layers.append({"name": l["name"], "amount": l["amount"], "soak": l["soak"]})
	return {"id": row.get("id", ""), "name": row.get("name", ""), "pool": row.get("pool", ""),
		"attack": row.get("attack", 1), "layers": layers, "targeting": row.get("targeting", "weakest"),
		"element": row.get("element", ""), "buff": row.get("buff", 0), "boss": row.get("boss", false),
		"weight": row.get("weight", 1), "icons": TraitDB.icons_of_enemy(row),
		"description": row.get("description", "")}


func _meta() -> Dictionary:
	var biomes: Array = []
	for b in adventure.all_biomes():
		var bounties: Array = []
		for k in adventure.bounties.keys():
			var bo: Dictionary = adventure.bounties[k]
			if CardDatabase._normalise(String(bo["biome"])) == CardDatabase._normalise(String(b["id"])):
				bounties.append({"id": bo["id"], "name": bo["name"], "boss": bo["boss"], "waves": bo["waves"]})
		biomes.append({"id": b["id"], "name": b["name"], "pool": b["pool"], "waves": b["waves"],
			"difficulty": b["difficulty"], "bounties": bounties})
	var enemies: Array = []
	for k in adventure.enemies.keys():
		enemies.append(_enemy_json(adventure.enemies[k]))
	var traits: Array = []
	for t in TraitDB.get_db().traits:
		var steps: Array = []
		for s in TraitDB.steps_of(String(t["id"])):
			steps.append({"at": s["at"], "name": s["name"], "effect": s["effect"], "value": s["value"],
				"target": s["target"], "lasts": s["lasts"], "description": s.get("description", "")})
		traits.append({"id": t["id"], "name": t["name"], "from": t["from"], "value": t["value"],
			"requires": t["requires"], "steps": steps})
	var players: Array = []
	var hidden: Array = load("res://tools/lab/lab.gd").HIDDEN_CLASSES
	for c in db.players:
		if hidden.has(c.unit_type):
			continue
		players.append({"name": c.player_name, "class": c.unit_type, "tier": c.get_tier_clean(),
			"atk": c.get_attack_power(), "star": c.is_star(), "element": c.active_element(),
			"icons": TraitDB.icons_of(c), "stamina": AdventureRun.stamina_for(c, db)})
	return {"ok": true, "biomes": biomes, "enemies": enemies, "traits": traits,
		"slots": TraitDB.slots(db), "players": players,
		"per_wave": db.tune_int("adventure_enemies_per_wave", 3)}


# =============================================================
#  A RUN
# =============================================================

func _card(name: String, tier: String) -> PlayerData:
	for c in db.players:
		if c.player_name == name and c.get_tier_clean() == tier:
			return c
	for c in db.players:
		if c.player_name == name:
			return c
	return null


## The live icons: the loadout the page chose, or the first `slots` of them.
## Set straight on TraitDB, so an icon a fresh save has not unlocked can
## still be tested.
func _set_loadout(ids: Array) -> void:
	var out: Array[Dictionary] = []
	for want in ids:
		for t in TraitDB.get_db().traits:
			if String(t["id"]).to_lower() == String(want).to_lower() and not out.has(t):
				out.append(t)
	if out.is_empty():
		for t in TraitDB.get_db().traits:
			if out.size() >= TraitDB.slots(db):
				break
			out.append(t)
	TraitDB._live = out


func _new_ctx(req: Dictionary) -> Ctx:
	var c := Ctx.new()
	c.state = GameState.new()
	c.run = AdventureRun.new()
	c.run.biome = adventure.biome(String(req.get("biome", "")))
	if c.run.biome.is_empty():
		var all := adventure.all_biomes()
		c.run.biome = all[0] if not all.is_empty() else {"name": "Nowhere", "waves": 1}
	var bounty_id := String(req.get("bounty", ""))
	c.run.bounty = adventure.bounty(bounty_id) if bounty_id != "" else {}
	# {"party": {"I": [names], ...}} - any card that fits the tier.
	var party: Dictionary = req.get("party", {})
	var squad := {}
	for t in TIERS:
		var line: Array[PlayerData] = []
		for n in (party.get(t, []) as Array):
			var card := _card(String(n), t)
			if card != null and not line.has(card):
				line.append(card)
		squad[t] = line
	c.run.squad = squad
	c.fixed_wave = req.get("wave", [])
	c.per_wave = int(req.get("per_wave", 0))
	# HOW LONG A RUN IS: the bounty's Waves, else the biome's. The page may
	# ask for another number; both copies are changed so either one counts.
	var waves := int(req.get("waves", 0))
	if waves > 0:
		c.run.biome = c.run.biome.duplicate()
		c.run.biome["waves"] = waves
		if not c.run.bounty.is_empty():
			c.run.bounty = c.run.bounty.duplicate()
			c.run.bounty["waves"] = waves
	# HOW OFTEN THIS BIOME WAS BEATEN BEFORE. The game's own ramp
	# (AdventureRun.difficulty: +adventure_repeat_step x biome Difficulty per
	# clear) makes every enemy tougher from it - this is how enemies grow.
	var clears := int(req.get("clears", 0))
	if clears > 0:
		c.state.add_count(c.run.clears_counter(), clears)
	return c


## The spreadsheets were edited: whatever was being played was built from
## the old numbers, so it stops, and the books are asked again.
func reset_after_edit() -> void:
	_stop_sim()
	sim = {}
	if one != null:
		_close(one)
		one = null
	db = CardDatabase.get_db()
	adventure = AdventureDB.get_db()
	TraitDB.get_db()


func _new(req: Dictionary) -> Dictionary:
	var seed_value := int(req.get("seed", 0))
	if seed_value == 0:
		seed_value = int(Time.get_unix_time_from_system()) % 1000000 + randi() % 1000
	seed(seed_value)
	_stop_sim()
	if one != null:
		_close(one)
	_set_loadout(req.get("loadout", []))
	one = _new_ctx(req)
	one.auto = req.get("auto", {})
	_open_wave(one)
	var out := _state(one)
	out["seed"] = seed_value
	return out


func _draw_wave(c: Ctx) -> Array[Dictionary]:
	var wave: Array[Dictionary] = []
	if not c.fixed_wave.is_empty():
		for id in c.fixed_wave:
			var row := adventure.enemy(String(id))
			if not row.is_empty():
				wave.append(row)
		return wave
	var pool := String(c.run.biome.get("pool", ""))
	if c.run.is_boss_wave() and not c.run.bounty.is_empty():
		var boss := adventure.enemy(String(c.run.bounty.get("boss", "")))
		if not boss.is_empty():
			wave.append(boss)
			return wave
	var wanted := c.per_wave if c.per_wave > 0 else maxi(1, db.tune_int("adventure_enemies_per_wave", 3))
	for i in wanted:
		var drawn := adventure.draw_from_pool(pool)
		if not drawn.is_empty():
			wave.append(drawn)
	return wave


func _open_wave(c: Ctx) -> void:
	var wave := _draw_wave(c)
	if wave.is_empty():
		c.result = "lost"
		c.notes.append("The biome produced no enemies - check its Enemy Pool.")
		return
	Engine.time_scale = 200.0
	c.holder = Node.new()
	add_child(c.holder)
	c.notes.append("=== Wave %d of %d%s: %s ===" % [c.run.wave, c.run.waves(),
		"  (THE BOSS)" if c.run.is_boss_wave() and not c.run.bounty.is_empty() else "",
		", ".join(wave.map(func(r): return String(r.get("name", "?"))))])
	var bare = load("res://tools/lab/lab_encounter.gd")
	c.fight = bare.open_bare(c.holder, db, c.state, c.run, wave)
	c.fight.noted.connect(_on_note.bind(c))
	c.fight.finished.connect(_on_finished.bind(c))
	if float(c.fight.get_meta("hard", 1.0)) > 1.01:
		c.notes.append("Difficulty x%.2f - enemies are scaled up." % float(c.fight.get_meta("hard", 1.0)))
	# The opening lines were said before anyone was listening.
	c.notes.append("Choose an enemy.")


func _on_note(text: String, c: Ctx) -> void:
	c.notes.append(text)
	if text.begins_with("Your line-up totals"):
		c.rounds += 1


func _on_finished(cleared: bool, _fled: bool, c: Ctx) -> void:
	if cleared:
		c.waves_cleared += 1
		c.run.send_off_stand_ins()
		if c.run.wave >= c.run.waves():
			c.result = "cleared"
		else:
			c.run.wave += 1
			_next_wave.call_deferred(c)
			return
	else:
		c.result = "lost"
		c.lost_at = c.run.wave
	_close.call_deferred(c)


func _next_wave(c: Ctx) -> void:
	_close(c)
	if c.result == "":
		_open_wave(c)


func _close(c: Ctx) -> void:
	if _live(c):
		c.fight.queue_free()
	if c.holder != null and is_instance_valid(c.holder):
		c.holder.queue_free()
	c.fight = null
	c.holder = null


func _pick(c: Ctx, which: String) -> void:
	if not _live(c) or c.fight.step != AdventureEncounter.Step.DRAFT:
		return
	var tier := c.fight._current_tier()
	var ready_now := c.run.available_in(tier, db)
	if ready_now.is_empty():
		return
	var chosen: PlayerData = null
	if which.begins_with("#") and which.substr(1).is_valid_int():
		var at := int(which.substr(1))
		if at >= 0 and at < ready_now.size():
			chosen = ready_now[at]
	if chosen == null:
		for card in ready_now:
			if card.player_name == which:
				chosen = card
	if chosen == null:
		chosen = _by_rule(c, ready_now, which)
	c.fight._pick_card(chosen)


func _by_rule(c: Ctx, cards: Array[PlayerData], how: String) -> PlayerData:
	match how:
		"strongest":
			var best := cards[0]
			for card in cards:
				if card.get_attack_power() > best.get_attack_power():
					best = card
			return best
		"weakest":
			return cards[0]
		"healthiest":
			var best := cards[0]
			for card in cards:
				if c.run.stamina_of(card, db) > c.run.stamina_of(best, db):
					best = card
			return best
	return cards[randi() % cards.size()]


func _left_total(c: Ctx, i: int) -> int:
	var n := 0
	for v in (c.fight.foes[i]["left"] as Array):
		n += int(v)
	return n


func _auto_focus(c: Ctx, how: String) -> int:
	var best := -1
	for i in c.fight.foes.size():
		if not c.fight._is_alive(i):
			continue
		if best < 0:
			best = i
			if how == "first":
				break
			continue
		match how:
			"weakest":
				if _left_total(c, i) < _left_total(c, best):
					best = i
			"strongest":
				if int(c.fight.foes[i]["row"].get("attack", 1)) > int(c.fight.foes[best]["row"].get("attack", 1)):
					best = i
	return best


func _drive(c: Ctx) -> void:
	if not _live(c) or c.auto.is_empty():
		return
	if c.fight.step == AdventureEncounter.Step.FOCUS:
		var target := _auto_focus(c, String(c.auto.get("focus", "first")))
		if target >= 0:
			c.fight._choose_focus(target)
	elif c.fight.step == AdventureEncounter.Step.DRAFT:
		var tier := c.fight._current_tier()
		if tier == "":
			return
		var ready_now := c.run.available_in(tier, db)
		if ready_now.is_empty():
			return
		c.fight._pick_card(_by_rule(c, ready_now, String(c.auto.get("pick", "random"))))


func _process(_delta: float) -> void:
	_drive(one)
	for c in sim_runs:
		_drive(c)
	_sim_tick()
	if (one == null or one.result != "" or not _live(one)) and sim_runs.is_empty():
		Engine.time_scale = 1.0


# =============================================================
#  WHAT THE PAGE SEES
# =============================================================

func _state(c: Ctx) -> Dictionary:
	if c == null:
		return {"ok": true, "none": true}
	var run := c.run
	var out := {"ok": true, "result": c.result, "wave": run.wave, "waves": run.waves(),
		"biome": run.biome.get("name", "?"), "waves_cleared": c.waves_cleared, "rounds": c.rounds,
		"auto": not c.auto.is_empty(), "hard": snappedf(run.difficulty(c.state, db), 0.01)}
	out["notes"] = c.notes.slice(c.notes_sent)
	c.notes_sent = c.notes.size()
	var party := {}
	for t in TIERS:
		var line: Array = []
		for entry in (run.squad.get(t, []) as Array):
			var card := entry as PlayerData
			if card == null:
				continue
			line.append({"name": card.player_name, "atk": card.get_attack_power(), "star": card.is_star(),
				"stamina": run.stamina_of(card, db), "max": AdventureRun.stamina_for(card, db),
				"out": run.is_out(card), "spent": run.is_spent(card), "icons": TraitDB.icons_of(card),
				"stand_in": run.stand_ins.has(card)})
		party[t] = line
	out["party"] = party
	if _live(c):
		var fight := c.fight
		var step_name := "focus"
		match fight.step:
			AdventureEncounter.Step.DRAFT:
				step_name = "draft"
			AdventureEncounter.Step.RESOLVING:
				step_name = "resolving"
			AdventureEncounter.Step.DONE:
				step_name = "done"
		out["step"] = step_name
		out["focus"] = fight._focus
		out["tier"] = fight._current_tier() if fight.step == AdventureEncounter.Step.DRAFT else ""
		var picked := {}
		for t in fight._picked.keys():
			var p = fight._picked[t]
			picked[t] = (p as PlayerData).player_name if p is PlayerData else null
		out["picked"] = picked
		var avail: Array = []
		if out["tier"] != "":
			for card in run.available_in(out["tier"], db):
				avail.append({"name": card.player_name, "atk": card.get_attack_power(),
					"stamina": run.stamina_of(card, db), "icons": TraitDB.icons_of(card)})
		out["available"] = avail
		var foes: Array = []
		for i in fight.foes.size():
			var f: Dictionary = fight.foes[i]
			var j := _enemy_json(f["row"])
			j["left"] = (f["left"] as Array).duplicate()
			j["alive"] = fight._is_alive(i)
			foes.append(j)
		out["foes"] = foes
		var counts := {}
		for k in fight.stack.counts.keys():
			counts[k] = fight.stack.counts[k]
		var active: Array = []
		for a in fight.stack.active():
			active.append({"name": a["name"], "effect": a["effect"], "value": a["value"]})
		out["stack"] = {"counts": counts, "active": active, "attack": fight.stack.attack_bonus(),
			"shield": fight.stack.shield()}
	else:
		out["step"] = "over" if c.result != "" else "between"
	var live: Array = []
	for t in TraitDB.live():
		live.append(t["id"])
	out["live_icons"] = live
	return out


# =============================================================
#  MANY RUNS
# =============================================================

func _stop_sim() -> void:
	for c in sim_runs:
		_close(c)
	sim_runs.clear()


func _sim_start(req: Dictionary) -> Dictionary:
	var seed_value := int(req.get("seed", 0))
	if seed_value == 0:
		seed_value = int(Time.get_unix_time_from_system()) % 1000000
	seed(seed_value)
	_stop_sim()
	if one != null:
		_close(one)
		one = null
	_set_loadout(req.get("loadout", []))
	sim = {"req": req, "n": clampi(int(req.get("n", 50)), 1, 2000), "started_runs": 0, "done": 0,
		"seed": seed_value, "cleared": 0, "waves": {}, "rounds": 0, "ko": {}, "fired": {},
		"started": Time.get_ticks_msec(), "waves_total": 0,
		"lost_at": {}, "kos": 0, "kos_runs": 0, "party": 0, "hard": 1.0}
	for i in mini(PARALLEL, int(sim["n"])):
		_sim_launch()
	return _sim_state()


func _sim_launch() -> void:
	var req: Dictionary = sim["req"]
	var c := _new_ctx(req)
	c.auto = {"focus": req.get("focus", "first"), "pick": req.get("pick", "random")}
	sim["started_runs"] = int(sim["started_runs"]) + 1
	sim["waves_total"] = c.run.waves()
	sim["hard"] = c.run.difficulty(c.state, db)
	sim_runs.append(c)
	_open_wave(c)


func _sim_tick() -> void:
	if sim.is_empty():
		return
	for c in sim_runs.duplicate():
		if c.result == "" or c.counted:
			continue
		c.counted = true
		sim["done"] = int(sim["done"]) + 1
		if c.result == "cleared":
			sim["cleared"] = int(sim["cleared"]) + 1
		var w := str(c.waves_cleared)
		sim["waves"][w] = int(sim["waves"].get(w, 0)) + 1
		if c.result == "lost":
			var la := str(c.lost_at)
			sim["lost_at"][la] = int(sim["lost_at"].get(la, 0)) + 1
		var kos := 0
		var size := 0
		sim["rounds"] = int(sim["rounds"]) + c.rounds
		for t in TIERS:
			for entry in (c.run.squad.get(t, []) as Array):
				var card := entry as PlayerData
				if card == null or c.run.stand_ins.has(card):
					continue
				size += 1
				if c.run.is_out(card):
					kos += 1
					sim["ko"][card.player_name] = int(sim["ko"].get(card.player_name, 0)) + 1
		sim["kos"] = int(sim["kos"]) + kos
		sim["kos_runs"] = int(sim["kos_runs"]) + (1 if kos > 0 else 0)
		sim["party"] = size
		for line in c.notes:
			var s := String(line)
			var at := s.find("!  ")
			if at > 0:
				var name := s.left(at)
				sim["fired"][name] = int(sim["fired"].get(name, 0)) + 1
		sim_runs.erase(c)
		if int(sim["started_runs"]) < int(sim["n"]):
			_sim_launch()


func _sim_state() -> Dictionary:
	if sim.is_empty():
		return {"ok": true, "none": true}
	var n := maxi(1, int(sim["done"]))
	return {"ok": true, "n": sim["n"], "done": sim["done"], "seed": sim["seed"],
		"cleared": sim["cleared"], "waves": sim["waves"], "rounds_per_run": snappedf(float(sim["rounds"]) / n, 0.01),
		"ko": sim["ko"], "fired": sim["fired"], "ms": Time.get_ticks_msec() - int(sim["started"]),
		"waves_total": sim["waves_total"], "lost_at": sim["lost_at"],
		"kos_per_run": snappedf(float(sim["kos"]) / n, 0.01), "runs_with_ko": sim["kos_runs"],
		"party": sim["party"], "hard": snappedf(float(sim["hard"]), 0.01)}
