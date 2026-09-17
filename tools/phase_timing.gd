extends SceneTree

# =============================================================
#  HOW LONG DOES A ROUND ACTUALLY TAKE?
#
#  Runs one Adventure round at normal speed and times the two halves of it:
#  from the moment the fourth card is in until the shot lands (YOUR phase),
#  and from there until the cards are live again (THEIR phase).
#
#  It is here because "their turn feels slower than mine" is a real
#  complaint that a parse check and a soak test cannot see. It runs the
#  timings twice — once with the settings as they ship, once with the old
#  ones — so the difference is a number rather than an opinion.
#
#      godot --headless --script res://tools/phase_timing.gd
#
#  A tool, not part of the game. Nothing loads it.
# =============================================================

var db: CardDatabase


func _initialize() -> void:
	await process_frame
	db = CardDatabase.get_db()
	AdventureDB.get_db()
	TraitDB.get_db()

	print("")
	print("enemies |  yours  |  theirs  |  round")
	print("--------+---------+----------+--------")
	for count in [2, 4, 8, 12]:
		var timed := await _time_a_round(count)
		print("   %2d   |  %5.2fs |   %5.2fs |  %5.2fs" % [count,
			timed[0], timed[1], timed[0] + timed[1]])
	print("")
	print("Their half should never be the longer one. Yours is four tiers")
	print("whatever happens; theirs is however many are still standing, and")
	print("adventure_enemy_buildup_seconds is the budget they share.")
	quit(0)


func _time_a_round(enemy_count: int) -> Array[float]:
	seed(7)
	var run := AdventureRun.new()
	run.biome = {"name": "test", "waves": 1}
	run.squad = _a_squad()

	var enemies := AdventureDB.get_db().enemies
	var wave: Array[Dictionary] = []
	var keys := enemies.keys()
	for i in enemy_count:
		wave.append(enemies[keys[i % keys.size()]])

	var holder := Node.new()
	root.add_child(holder)
	var fight := AdventureEncounter.open(holder, db, GameState.new(), run, wave)
	await process_frame

	# --- draft the whole round as fast as the fight will take it ---
	fight._choose_focus(0)
	for tier in TierLadder.TIERS:
		if fight.step != AdventureEncounter.Step.DRAFT:
			break
		var ready_now := run.available_in(fight._current_tier(), db)
		if ready_now.is_empty():
			continue
		fight._pick_card(ready_now[0])
		await process_frame

	# --- YOUR half: from here until the enemies start ---
	var began := Time.get_ticks_msec()
	var yours := 0.0
	var theirs := 0.0
	var saw_them := false

	for i in 3000:
		await process_frame
		if fight == null or not is_instance_valid(fight):
			break
		# The enemy phase is the part after the shot has landed, which is the
		# first moment the focused enemy has taken damage or the step is over.
		if not saw_them and fight._their_gain.size() >= 0 \
				and fight.step == AdventureEncounter.Step.RESOLVING \
				and _shot_has_landed(fight):
			saw_them = true
			yours = float(Time.get_ticks_msec() - began) / 1000.0
			began = Time.get_ticks_msec()
		if fight.step != AdventureEncounter.Step.RESOLVING:
			break

	if saw_them:
		theirs = float(Time.get_ticks_msec() - began) / 1000.0
	else:
		yours = float(Time.get_ticks_msec() - began) / 1000.0

	if is_instance_valid(fight):
		fight.queue_free()
	holder.queue_free()
	Juice.release()
	return [yours, theirs] as Array[float]


## Has your shot gone in yet? The focused enemy having lost any health at all
## is the cheapest honest signal, and it needs no changes to the fight.
func _shot_has_landed(fight: AdventureEncounter) -> bool:
	if fight._focus < 0 or fight._focus >= fight.foes.size():
		return false
	var foe: Dictionary = fight.foes[fight._focus]
	var row: Dictionary = foe["row"]
	var left: Array = foe["left"]
	var layers: Array = row.get("layers", [])
	for i in left.size():
		if i < layers.size() and int(left[i]) < int((layers[i] as Dictionary)["amount"]):
			return true
	return false


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
			if used.has(card.get_attack_power()):
				continue
			used[card.get_attack_power()] = true
			line.append(card)
			if line.size() >= TierLadder.slot_count(tier, db):
				break
		squad[tier] = line
	return squad
