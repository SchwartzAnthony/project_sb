extends SceneTree

# =============================================================
#  THE ADVENTURE SOAK TEST
#
#  Runs a whole Adventure fight with no window and no mouse: it builds a
#  legal squad, opens a real AdventureEncounter, and drafts a card for every
#  tier of every round until the wave is cleared or the party is down. Then
#  it does it again, several hundred times, with different squads.
#
#  WHAT IT IS FOR: a crash in the fight shows up here in thirty seconds
#  instead of showing up on your machine ten minutes into a run. Every error
#  Godot prints while it runs is a real error in the game.
#
#      godot --headless --script res://tools/adventure_soak.gd
#
#  It is a tool, not part of the game. Nothing loads it.
# =============================================================

const FIGHTS := 60

var db: CardDatabase
var adventure: AdventureDB
var state: GameState
var trouble: Array[String] = []

# GDSCRIPT LAMBDAS CAPTURE BY VALUE. A `var done := false` in the function
# below and `done = true` inside the signal handler are two different
# variables, and the loop spins for ever. Members are shared; locals are not.
var _done := false
var _cleared := false

## True for the second half of the run — see _a_wave().
var seed_hard := false


func _initialize() -> void:
	# THE FIGHT WAITS. _beat() and the build-up windows use real timers, and
	# two hundred fights of real waiting is an hour. Running the clock fast
	# makes the waits instant without changing a single rule.
	Engine.time_scale = 200.0
	db = CardDatabase.get_db()
	adventure = AdventureDB.get_db()
	TraitDB.get_db()

	print("")
	print("=== squads ===")
	_report_squad_shapes()

	print("")
	print("=== %d fights ===" % FIGHTS)
	var started := Time.get_ticks_msec()
	var cleared := 0
	var lost := 0
	for i in FIGHTS:
		seed_hard = i >= FIGHTS / 2
		var result := await _one_fight(i)
		if result:
			cleared += 1
		else:
			lost += 1
	print("")
	print("cleared %d, lost %d in %.1fs" % [cleared, lost,
		float(Time.get_ticks_msec() - started) / 1000.0])

	if trouble.is_empty():
		print("NO TROUBLE.")
	else:
		print("TROUBLE (%d):" % trouble.size())
		for note in trouble:
			print("   " + note)
	quit(0)


# =============================================================
#  ONE FIGHT
# =============================================================

func _one_fight(seed_value: int) -> bool:
	seed(seed_value)
	state = GameState.new()
	var run := AdventureRun.new()
	run.biome = _a_biome()
	run.bounty = {}
	run.squad = _a_squad()

	var wave := _a_wave(run)
	if wave.is_empty():
		trouble.append("fight %d: the biome produced no enemies" % seed_value)
		return false

	var holder := Node.new()
	root.add_child(holder)

	var fight := AdventureEncounter.open(holder, db, state, run, wave)
	# No stage, no nodes, no walkers: _can_show() is false and the fight runs
	# its rules without any of the animation. That is the point of the split.

	var guard := 0
	_done = false
	_cleared = false

	fight.finished.connect(func(was_cleared: bool, _fled: bool) -> void:
		_cleared = was_cleared
		_done = true)

	while not _done and guard < 3000:
		guard += 1
		await process_frame

		if fight.step == AdventureEncounter.Step.FOCUS:
			var target := -1
			for i in fight.foes.size():
				if fight._is_alive(i):
					target = i
					break
			if target < 0:
				break
			fight._choose_focus(target)

		elif fight.step == AdventureEncounter.Step.DRAFT:
			var tier := fight._current_tier()
			if tier == "":
				continue
			var ready_now := run.available_in(tier, db)
			if ready_now.is_empty():
				continue
			fight._pick_card(ready_now[randi() % ready_now.size()])

	if guard >= 3000:
		trouble.append("fight %d: ran out of frames — the fight never ended" % seed_value)

	# ---- the invariants ----
	_check_ladder(run, seed_value)

	if is_instance_valid(fight):
		fight.queue_free()
	holder.queue_free()
	return _cleared


## THE TIER LADDER IS THE ONE RULE. Check it AFTER the fight too, because a
## spawn brought on by a combo joins the squad and has to obey it as well.
func _check_ladder(run: AdventureRun, seed_value: int) -> void:
	for tier in TierLadder.TIERS:
		var rungs := TierLadder.rungs(tier, db)
		if rungs.is_empty():
			continue
		for entry in (run.squad.get(tier, []) as Array):
			var card := entry as PlayerData
			if card == null:
				continue
			var power := card.get_attack_power()
			if power < rungs[0] or power > rungs[rungs.size() - 1]:
				trouble.append("fight %d: %s is power %d in Tier %s, whose rungs are %s"
					% [seed_value, card.player_name, power, tier, str(rungs)])


# =============================================================
#  MAKING THINGS TO FIGHT WITH
# =============================================================

func _a_squad() -> Dictionary:
	var squad: Dictionary = {}
	for tier in TierLadder.TIERS:
		var pool: Array[PlayerData] = []
		for card in db.players:
			if TierLadder.fits(card, tier, db):
				pool.append(card)
		pool.shuffle()
		var line: Array[PlayerData] = []
		var used: Dictionary = {}
		for card in pool:
			var rung := card.get_attack_power()
			if used.has(rung):
				continue
			used[rung] = true
			line.append(card)
			if line.size() >= TierLadder.slot_count(tier, db):
				break
		squad[tier] = line
	return squad


func _a_biome() -> Dictionary:
	var all := adventure.all_biomes()
	return all[randi() % all.size()] if not all.is_empty() else {"name": "Nowhere", "waves": 1}


func _a_wave(run: AdventureRun) -> Array[Dictionary]:
	var wave: Array[Dictionary] = []
	var pool := String(run.biome.get("pool", run.biome.get("id", "")))
	var candidates := adventure.pool_enemies(pool)
	if candidates.is_empty():
		for key in adventure.enemies.keys():
			candidates.append(adventure.enemies[key])
	if candidates.is_empty():
		return wave
	# HALF THE FIGHTS ARE UNFAIR ON PURPOSE. A soak in which you always win
	# never runs the revive, the stand-in or the everybody-is-down paths, and
	# those are exactly the ones worth crashing.
	var how_many := 2 + randi() % 3
	if seed_hard:
		how_many = 8 + randi() % 8
	for i in how_many:
		wave.append(candidates[randi() % candidates.size()])
	return wave


# =============================================================
#  WHAT THE SQUADS LOOK LIKE
# =============================================================

func _report_squad_shapes() -> void:
	var icon_seen: Dictionary = {}
	var empty_rungs := 0
	for i in 400:
		seed(i)
		var squad := _a_squad()
		for tier in TierLadder.TIERS:
			var line: Array = squad.get(tier, [])
			if line.size() < TierLadder.slot_count(tier, db):
				empty_rungs += 1
			for entry in line:
				for icon in TraitDB.icons_of(entry as PlayerData):
					icon_seen[icon] = int(icon_seen.get(icon, 0)) + 1
	print("thin tiers across 400 squads: %d" % empty_rungs)
	for key in icon_seen.keys():
		print("   icon %-14s appears %d times in 400 squads (%.2f per squad)"
			% [key, int(icon_seen[key]), float(icon_seen[key]) / 400.0])
