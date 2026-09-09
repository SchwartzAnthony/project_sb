class_name AdventureScene
extends Node2D

# =============================================================
#  THE RUN — Phase 2: the scroll, the pickups, and meeting a wave
#
#  Your party runs right. The field slides left. Things on the ground come
#  past and the nearest players peel off to grab them. When a wave arrives
#  the party stops and forms up on the left, and the encounter begins.
#
#  ============ WHAT IS BUILT, AND WHAT IS NOT ============
#
#  BUILT NOW      the scroll, the party, the ball being knocked about, the
#                 ground pickups, waves arriving, the enemies walking on,
#                 the loot roll, and Continue Forward / Return to Base.
#
#  NOT YET        the encounter itself. Reaching a wave currently plays it
#                 out automatically and you win. THE DRAFT, THE FOCUS
#                 TARGET, STAMINA AND FLEEING ARE PHASE 3 AND 4.
#
#  That is deliberate. This phase exists so you can look at the speed, the
#  spacing and the feel and tell me what is wrong with them, which is not a
#  thing either of us can judge from a spreadsheet. Everything the encounter
#  will need — the run, the haul, the stamina rules — is already in
#  adventure_run.gd waiting for it.
#
#  ============ NOTHING HERE NAMES CONTENT ============
#
#  The biome, its waves, which enemies turn up and what they drop all come
#  from Biomes.csv, AdventureEnemies.csv and Drops.csv through AdventureDB.
#  The speeds and spacings are Tuning.csv. This file is only the motion.
# =============================================================

enum RunState { RUNNING, MEETING, ENCOUNTER, LOOT, FINISHED }

const GROUND_Y := 420.0
const PARTY_X := 260.0          # where the party runs, in screen space
const SPAWN_X := 1500.0         # off the right edge, where things come from
const FORM_X := 200.0           # where the party forms up to fight

var db: CardDatabase
var adventure: AdventureDB
var state: GameState
var run: AdventureRun

var current_state: RunState = RunState.RUNNING

var _scroll_speed := 120.0
var _travelled := 0.0
var _next_pickup_at := 0.0
var _next_wave_at := 0.0

var _walkers: Array[AdventureWalker] = []
var _pickups: Array[Node2D] = []
var _foes: Array[Node2D] = []

var _world: Node2D
var _ball: Node2D
var _ball_holder: int = 0
var _pass_clock := 0.0

var _banner: Label
var _headline: Label
var _haul_label: Label
var _wave_label: Label
var _popup: CanvasLayer


# =============================================================
#  SETTING OFF
# =============================================================

func _ready() -> void:
	GameSpeed.reset()
	db = CardDatabase.get_db()
	adventure = AdventureDB.get_db()
	state = GameState.fetch(get_tree())
	run = AdventureRun.current(get_tree())

	if run == null:
		# Someone pressed play on this scene directly. Rather than crash,
		# take the first bounty there is so the scene can still be looked at.
		run = _stand_in_run()

	_scroll_speed = db.tune_float("adventure_scroll_speed", 120.0)

	_build_world()
	_build_hud()
	_spawn_party()
	_plan_ahead()

	AudioDirector.fire(get_tree(), "match_started",
		{"biome": run.biome_name()}, state)
	_say("%s — %s" % [run.biome_name(), run.bounty_name()])
	print("[adventure] Setting off into %s. %d wave(s) to the boss."
		% [run.biome_name(), run.waves()])


## Only used when the scene is run on its own from the editor.
func _stand_in_run() -> AdventureRun:
	var biomes := adventure.all_biomes()
	if biomes.is_empty():
		push_warning("[adventure] No biomes in Biomes.csv — there is nothing to run through.")
		return AdventureRun.begin(get_tree(), {}, {"name": "Nowhere", "waves": 1})

	var first_biome: Dictionary = biomes[0]
	var jobs := adventure.bounties_in(String(first_biome["id"]), state)
	var job: Dictionary = jobs[0] if not jobs.is_empty() else {}
	print("[adventure] No run was started — using '%s' so this scene can be looked at on its own."
		% first_biome["name"])
	return AdventureRun.begin(get_tree(), job, first_biome)


# =============================================================
#  THE WORLD
# =============================================================

func _build_world() -> void:
	var sky := ColorRect.new()
	sky.color = MenuSupport.COLOUR_BACKGROUND
	sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var layer := CanvasLayer.new()
	layer.layer = -10
	layer.add_child(sky)
	add_child(layer)

	_world = Node2D.new()
	_world.name = "World"
	add_child(_world)

	# The ground is drawn rather than a texture, so the scene works before
	# any biome art exists. Drop a Scroll Art / Ground image into your assets
	# and this is where it would be swapped in.
	var ground := Node2D.new()
	ground.name = "Ground"
	ground.draw.connect(_draw_ground.bind(ground))
	_world.add_child(ground)

	_ball = Node2D.new()
	_ball.name = "Ball"
	_ball.draw.connect(_draw_ball.bind(_ball))
	_world.add_child(_ball)


func _draw_ground(on: Node2D) -> void:
	# A band of grass, and stripes that slide with the run so the motion is
	# readable even with no artwork at all.
	on.draw_rect(Rect2(Vector2(-200.0, GROUND_Y), Vector2(2400.0, 400.0)),
		Color(0.13, 0.20, 0.15), true)
	on.draw_line(Vector2(-200.0, GROUND_Y), Vector2(2200.0, GROUND_Y),
		Color(0.22, 0.34, 0.24), 3.0)

	var stripe := Color(0.16, 0.24, 0.18)
	var gap := 120.0
	var offset := fposmod(-_travelled, gap)
	var x := -200.0 + offset
	while x < 2200.0:
		on.draw_rect(Rect2(Vector2(x, GROUND_Y + 8.0), Vector2(gap * 0.5, 380.0)),
			stripe, true)
		x += gap


func _draw_ball(on: Node2D) -> void:
	on.draw_circle(Vector2.ZERO, 7.0, Color(0.93, 0.93, 0.90))
	on.draw_arc(Vector2.ZERO, 7.0, 0.0, TAU, 16, Color(0.25, 0.25, 0.25), 1.5, true)


# =============================================================
#  THE PARTY
# =============================================================

func _spawn_party() -> void:
	var picked := TeamSelection.fetch(get_tree())
	var squad: Dictionary = {}

	if picked != null:
		# The team builder settled this: the Star tier is held by the Stars,
		# every other tier by the three you chose.
		for tier in TierLadder.TIERS:
			if tier == picked.star_tier:
				var stars: Array[PlayerData] = []
				if picked.active_star != null:
					stars.append(picked.active_star)      # ONE Star in Adventure
				squad[tier] = stars
			else:
				var regulars: Array[PlayerData] = []
				regulars.assign(picked.regulars.get(tier, []))
				squad[tier] = regulars
	else:
		squad = _stand_in_squad()

	run.squad = squad

	var index := 0
	for tier in TierLadder.TIERS:
		for entry in (squad.get(tier, []) as Array):
			var card := entry as PlayerData
			if card == null:
				continue
			var walker := AdventureWalker.new()
			_world.add_child(walker)
			walker.setup(card, _scroll_speed * 2.2)
			walker.position = _slot_for(index)
			walker.target = walker.position
			walker.stamina_fraction = 1.0
			_walkers.append(walker)
			index += 1

	if _walkers.is_empty():
		push_warning("[adventure] Nobody set off — no team was chosen. Go through the team builder first.")
	else:
		_ball.position = _walkers[0].position + Vector2(0.0, -6.0)


## A rough running formation: a couple of rows behind the leader.
func _slot_for(index: int) -> Vector2:
	var column := index / 3
	var seat := index % 3
	return Vector2(PARTY_X - column * 78.0,
		GROUND_Y - 40.0 + (seat - 1) * 62.0)


## Only for running this scene on its own — the first legal squad it can build.
func _stand_in_squad() -> Dictionary:
	var squad: Dictionary = {}
	var classes: Array[String] = []
	for card in db.players:
		var key := card.unit_type.strip_edges()
		if key != "" and not classes.has(key):
			classes.append(key)
	if classes.is_empty():
		return squad

	var roster := db.roster_for_class(classes[0])
	for tier in TierLadder.TIERS:
		var made := TierLadder.build(roster, tier, db, false)
		squad[tier] = made["cards"]
	return squad


# =============================================================
#  WHAT IS COMING UP
# =============================================================

func _plan_ahead() -> void:
	_next_pickup_at = _travelled + _pickup_gap()
	_next_wave_at = _travelled + _wave_gap()


func _pickup_gap() -> float:
	var seconds := db.tune_float("adventure_pickup_gap", 3.0)
	return maxf(60.0, seconds * _scroll_speed) * randf_range(0.7, 1.3)


func _wave_gap() -> float:
	var seconds := db.tune_float("adventure_wave_gap", 12.0)
	return maxf(200.0, seconds * _scroll_speed)


# =============================================================
#  THE LOOP
# =============================================================

func _process(delta: float) -> void:
	if current_state == RunState.RUNNING:
		_scroll(delta)
		_pass_the_ball(delta)
	elif current_state == RunState.MEETING:
		_close_in()

	if current_state == RunState.RUNNING:
		_carry_pickups(delta)
	_settle_walkers()

	if _world != null:
		var ground := _world.get_node_or_null("Ground")
		if ground != null:
			ground.queue_redraw()


func _scroll(delta: float) -> void:
	var step := _scroll_speed * delta
	_travelled += step

	# EVERYTHING SLIDES LEFT. The party is what the camera is on, so it
	# stays put on screen and the world moves past it — which is why this is
	# an "endless" scroll rather than a very long level.
	for pickup in _pickups:
		pickup.position.x -= step
	for foe in _foes:
		foe.position.x -= step

	if _travelled >= _next_pickup_at:
		_next_pickup_at = _travelled + _pickup_gap()
		_drop_a_pickup()

	if _travelled >= _next_wave_at:
		_begin_meeting()


## Knock the ball between the party as they run, so it reads as football
## rather than a queue of people jogging.
func _pass_the_ball(delta: float) -> void:
	if _walkers.size() < 2 or _ball == null:
		return
	_pass_clock -= delta
	if _pass_clock <= 0.0:
		_pass_clock = db.tune_float("adventure_pass_seconds", 1.4) * randf_range(0.7, 1.3)
		_ball_holder = randi() % _walkers.size()

	var holder := _walkers[_ball_holder]
	if holder != null and is_instance_valid(holder):
		_ball.position = _ball.position.lerp(
			holder.position + Vector2(16.0, -4.0), delta * 6.0)
		_ball.queue_redraw()


# =============================================================
#  PICKUPS
#
#  Up to `adventure_pickup_carriers` of the nearest players peel off to
#  collect one. They break formation, touch it, and fall back in.
# =============================================================

func _drop_a_pickup() -> void:
	var table := String(run.biome.get("drops", ""))
	if table.strip_edges() == "":
		return
	var rolled := adventure.roll(table, state)
	if rolled.is_empty():
		return

	var item_id := String(rolled.keys()[0])
	var amount := int(rolled[item_id])
	var known := adventure.item(item_id)

	var pickup := Node2D.new()
	pickup.position = Vector2(SPAWN_X, GROUND_Y + randf_range(10.0, 90.0))
	pickup.set_meta("item", item_id)
	pickup.set_meta("amount", amount)
	pickup.set_meta("name", String(known["name"]) if not known.is_empty() else item_id)
	pickup.set_meta("claimed", false)
	pickup.set_meta("carriers", [] as Array)
	pickup.draw.connect(_draw_pickup.bind(pickup))
	_world.add_child(pickup)
	_pickups.append(pickup)


func _draw_pickup(on: Node2D) -> void:
	var lit := not bool(on.get_meta("claimed", false))
	var tint := MenuSupport.COLOUR_ACCENT if lit else MenuSupport.COLOUR_TEXT_DIM
	on.draw_rect(Rect2(Vector2(-9, -9), Vector2(18, 18)), tint.darkened(0.4), true)
	on.draw_rect(Rect2(Vector2(-9, -9), Vector2(18, 18)), tint, false, 2.0)


func _carry_pickups(delta: float) -> void:
	var carriers_allowed := db.tune_int("adventure_pickup_carriers", 3)
	var still: Array[Node2D] = []

	for pickup in _pickups:
		if not is_instance_valid(pickup):
			continue

		# Off the left edge and never reached — it is gone.
		if pickup.position.x < -120.0:
			pickup.queue_free()
			continue

		var carriers: Array = pickup.get_meta("carriers", [])
		if carriers.is_empty() and pickup.position.x < 900.0:
			carriers = _nearest_free_walkers(pickup.position, carriers_allowed)
			pickup.set_meta("carriers", carriers)
			for walker in carriers:
				(walker as AdventureWalker).fetching = true

		var got := false
		for entry in carriers:
			var walker := entry as AdventureWalker
			if walker == null or not is_instance_valid(walker) or walker.knocked_out:
				continue
			walker.target = pickup.position + Vector2(0.0, -20.0)
			if walker.position.distance_to(pickup.position) < 34.0:
				got = true

		if got:
			run.collect(String(pickup.get_meta("item")),
				int(pickup.get_meta("amount")))
			_say("Picked up %d %s" % [int(pickup.get_meta("amount")),
				pickup.get_meta("name")])
			_refresh_haul()
			for entry2 in carriers:
				var walker2 := entry2 as AdventureWalker
				if walker2 != null and is_instance_valid(walker2):
					walker2.fetching = false
			pickup.queue_free()
			continue

		still.append(pickup)

	_pickups = still


## The closest players who are not already fetching something.
func _nearest_free_walkers(where: Vector2, how_many: int) -> Array:
	var free: Array = []
	for walker in _walkers:
		if walker != null and is_instance_valid(walker) \
				and not walker.fetching and not walker.knocked_out:
			free.append(walker)

	# Insertion sort by distance — the list is ten long at most.
	var sorted: Array = []
	for entry in free:
		var at := sorted.size()
		for i in sorted.size():
			if (sorted[i] as Node2D).position.distance_to(where) \
					> (entry as Node2D).position.distance_to(where):
				at = i
				break
		sorted.insert(at, entry)

	var taken: Array = []
	for i in mini(maxi(1, how_many), sorted.size()):
		taken.append(sorted[i])
	return taken


## Anyone not fetching drifts back to their slot in the formation.
func _settle_walkers() -> void:
	for i in _walkers.size():
		var walker := _walkers[i]
		if walker == null or not is_instance_valid(walker) or walker.fetching:
			continue
		if current_state == RunState.RUNNING:
			walker.target = _slot_for(i)
		else:
			walker.target = _formation_slot(i)


## Where the party stands to fight: a tighter block, further left.
func _formation_slot(index: int) -> Vector2:
	var column := index / 4
	var seat := index % 4
	return Vector2(FORM_X - column * 66.0, GROUND_Y - 80.0 + seat * 56.0)


# =============================================================
#  MEETING A WAVE
# =============================================================

func _begin_meeting() -> void:
	current_state = RunState.MEETING
	_spawn_wave()
	_say("COMBAT")
	AudioDirector.fire(get_tree(), "hold_up", {"biome": run.biome_name()}, state)


func _spawn_wave() -> void:
	var pool := String(run.biome.get("pool", ""))
	var boss_wave := run.is_boss_wave()

	var line_up: Array[Dictionary] = []
	if boss_wave:
		var boss := adventure.enemy(String(run.bounty.get("boss", "")))
		if not boss.is_empty():
			line_up.append(boss)

	# One ordinary enemy per tier, so every tier of the draft has somebody
	# to face. A tier with nobody is a walkover, which is a rule rather than
	# an accident — see PHASE1_BOUNTY_BOARD.md.
	if not boss_wave:
		var wanted := db.tune_int("adventure_enemies_per_wave", 3)
		for tier in TierLadder.TIERS:
			if line_up.size() >= wanted:
				break
			var choices := adventure.pool_enemies(pool, tier)
			if choices.is_empty():
				continue
			line_up.append(choices[randi() % choices.size()])

	for i in line_up.size():
		var foe := Node2D.new()
		foe.position = Vector2(SPAWN_X + i * 90.0,
			GROUND_Y - 60.0 + (i % 3) * 62.0)
		foe.set_meta("enemy", line_up[i])
		foe.set_meta("home", Vector2(920.0 + (i / 3) * 96.0,
			GROUND_Y - 60.0 + (i % 3) * 62.0))
		foe.draw.connect(_draw_foe.bind(foe))
		_world.add_child(foe)
		_foes.append(foe)

	print("[adventure] Wave %d of %d — %d enemy(s)%s." % [
		run.wave, run.waves(), line_up.size(),
		"  (THE BOSS)" if boss_wave else ""])


func _draw_foe(on: Node2D) -> void:
	var entry: Dictionary = on.get_meta("enemy", {})
	if entry.is_empty():
		return

	var boss := bool(entry.get("boss", false))
	var size := 26.0 if boss else 19.0
	var tint := Color(0.62, 0.28, 0.30) if boss else Color(0.45, 0.30, 0.36)

	on.draw_circle(Vector2.ZERO, size, tint)
	on.draw_arc(Vector2.ZERO, size, 0.0, TAU, 24, tint.lightened(0.35), 2.0, true)

	var font := ThemeDB.fallback_font
	var label := str(int(entry.get("power", 0)))
	var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16).x
	on.draw_string(font, Vector2(-width * 0.5, 6.0), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, MenuSupport.COLOUR_TEXT)

	# ONE BAR PER LAYER, outermost on top. This is the shape of the fight in
	# Phase 3 and 4: chew through the top bar before the next one is exposed.
	var layers: Array = entry.get("layers", [])
	var y := size + 6.0
	for layer in layers:
		var amount := int((layer as Dictionary)["amount"])
		var soak := int((layer as Dictionary)["soak"])
		var width_px := clampf(float(amount) * 2.4, 16.0, 74.0)
		var bar := Rect2(Vector2(-width_px * 0.5, y), Vector2(width_px, 5.0))
		on.draw_rect(bar, Color(0.10, 0.11, 0.14), true)
		# Darker means it soaks more — a wall you have to grind rather than
		# a bar you sweep through.
		on.draw_rect(bar, Color(0.72, 0.42, 0.38).darkened(float(soak) * 0.14), true)
		y += 7.0


## The two sides walk towards each other, then the encounter starts.
func _close_in() -> void:
	var ready_to_go := true
	for foe in _foes:
		if not is_instance_valid(foe):
			continue
		var home: Vector2 = foe.get_meta("home")
		foe.position = foe.position.move_toward(home, _scroll_speed * 2.4 * get_process_delta_time())
		if foe.position.distance_to(home) > 4.0:
			ready_to_go = false
		foe.queue_redraw()

	for walker in _walkers:
		if walker != null and is_instance_valid(walker) and not walker.is_settled():
			ready_to_go = false

	if ready_to_go:
		_run_encounter()


# =============================================================
#  THE ENCOUNTER  —  PHASE 3 REPLACES THIS WHOLE SECTION
#
#  Today it waits a beat and you win. What goes here next is:
#    * pick which enemy to focus  (a click, with its stats on hover)
#    * draft Tier I..IV, the enemy revealing each as you commit
#    * Flee, until the fourth tier is committed
#    * compare totals, deal damage into layers, take damage yourself
# =============================================================

func _run_encounter() -> void:
	if current_state == RunState.ENCOUNTER:
		return
	current_state = RunState.ENCOUNTER
	_say("The way is blocked — %d in the way" % _foes.size())
	await get_tree().create_timer(1.1).timeout
	if current_state != RunState.ENCOUNTER:
		return
	_win_encounter()


func _win_encounter() -> void:
	var loot: Dictionary = {}
	for foe in _foes:
		if not is_instance_valid(foe):
			continue
		var entry: Dictionary = foe.get_meta("enemy", {})
		var rolled := adventure.roll(String(entry.get("drops", "")), state)
		for key in rolled.keys():
			loot[key] = int(loot.get(key, 0)) + int(rolled[key])
		foe.queue_free()
	_foes.clear()

	run.collect_all(loot)
	_refresh_haul()

	var was_boss := run.is_boss_wave()
	current_state = RunState.LOOT
	_show_loot(loot, was_boss)


# =============================================================
#  THE LOOT POPUP, AND THE CHOICE
# =============================================================

func _show_loot(loot: Dictionary, was_boss: bool) -> void:
	_popup = _make_popup()

	var box := _popup.get_node("Holder/Panel/Margin/Column") as VBoxContainer
	box.add_child(MenuSupport.heading(
		"THE BOSS IS DOWN" if was_boss else "WAVE %d CLEARED" % run.wave,
		28, MenuSupport.COLOUR_ACCENT))

	if loot.is_empty():
		box.add_child(_quiet("They were carrying nothing."))
	else:
		box.add_child(MenuSupport.heading("PICKED UP", 15, MenuSupport.COLOUR_TEXT_DIM))
		for key in loot.keys():
			var known := adventure.item(String(key))
			var label := Label.new()
			label.text = "+%d   %s" % [int(loot[key]),
				String(known["name"]) if not known.is_empty() else String(key)]
			label.add_theme_font_size_override("font_size", 16)
			box.add_child(label)

	box.add_child(_quiet(
		"Carrying %d thing%s. None of it is yours until you get home."
		% [run.haul_size(), "" if run.haul_size() == 1 else "s"]))

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)

	if was_boss:
		# The bounty is done. There is nothing further in, so the only way is
		# home — and the reward is paid when the haul is banked.
		var claim := _make_button("CLAIM THE BOUNTY  ▶", Vector2(260, 52))
		claim.pressed.connect(_go_home.bind(true))
		buttons.add_child(claim)
	else:
		var onward := _make_button("Continue forward", Vector2(220, 52))
		onward.tooltip_text = "Further in. More to pick up, and more that can go wrong."
		onward.pressed.connect(_continue_forward)
		buttons.add_child(onward)

		var home := _make_button("Return to base", Vector2(200, 52))
		home.tooltip_text = "Walk away with everything you are carrying."
		home.pressed.connect(_go_home.bind(false))
		buttons.add_child(home)


func _continue_forward() -> void:
	if _popup != null:
		_popup.queue_free()
		_popup = null
	run.wave += 1
	current_state = RunState.RUNNING
	_next_wave_at = _travelled + _wave_gap()
	_next_pickup_at = _travelled + _pickup_gap()
	_refresh_wave()
	_say("Onward — wave %d" % run.wave)


## HOME WITH THE HAUL. This is the only place a run's pickings become real:
## bank() turns them into counters in your save, which is what makes them
## work with buildings, talents and conditions with no new code.
func _go_home(claimed_bounty: bool) -> void:
	if current_state == RunState.FINISHED:
		return
	current_state = RunState.FINISHED

	var taken := run.bank(state, 1.0)
	var words: Array[String] = []
	for key in taken.keys():
		var known := adventure.item(String(key))
		words.append("%d %s" % [int(taken[key]),
			String(known["name"]) if not known.is_empty() else String(key)])

	if claimed_bounty:
		var reward := String(run.bounty.get("reward", ""))
		if reward.strip_edges() != "":
			DialogueGrammar.apply(reward, state)
			print("[adventure] Bounty claimed: %s" % reward)

	state.save_to_disk()
	AdventureRun.clear(get_tree())
	print("[adventure] Home with: %s" % (", ".join(words) if not words.is_empty() else "nothing"))

	ScenePaths.go_to(get_tree(), ScenePaths.BASE, false)


# =============================================================
#  THE HUD
# =============================================================

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	add_child(layer)

	_headline = Label.new()
	_headline.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_headline.offset_left = 24.0
	_headline.offset_top = 18.0
	_headline.offset_bottom = 48.0
	_headline.add_theme_font_size_override("font_size", 20)
	_headline.add_theme_color_override("font_color", MenuSupport.COLOUR_ACCENT)
	_headline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_headline)

	_wave_label = Label.new()
	_wave_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_wave_label.offset_left = 24.0
	_wave_label.offset_top = 46.0
	_wave_label.offset_bottom = 70.0
	_wave_label.add_theme_font_size_override("font_size", 14)
	_wave_label.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	_wave_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_wave_label)

	_haul_label = Label.new()
	_haul_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_haul_label.offset_left = -420.0
	_haul_label.offset_top = 18.0
	_haul_label.offset_right = -24.0
	_haul_label.offset_bottom = 48.0
	_haul_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_haul_label.add_theme_font_size_override("font_size", 15)
	_haul_label.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT)
	_haul_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_haul_label)

	_banner = Label.new()
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.offset_left = -400.0
	_banner.offset_right = 400.0
	_banner.offset_top = 96.0
	_banner.offset_bottom = 140.0
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 26)
	_banner.add_theme_color_override("font_color", MenuSupport.COLOUR_ACCENT)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.hide()
	layer.add_child(_banner)

	_refresh_wave()
	_refresh_haul()


func _refresh_wave() -> void:
	if _wave_label == null:
		return
	var total := run.waves()
	_wave_label.text = "%s   ·   wave %d of %d%s" % [run.bounty_name(),
		run.wave, total, "   ·   THE BOSS" if run.is_boss_wave() else ""]


func _refresh_haul() -> void:
	if _haul_label == null:
		return
	if run.haul.is_empty():
		_haul_label.text = "carrying nothing"
		return
	var words: Array[String] = []
	for key in run.haul.keys():
		var known := adventure.item(String(key))
		words.append("%d %s" % [int(run.haul[key]),
			String(known["name"]) if not known.is_empty() else String(key)])
	_haul_label.text = "carrying:  " + "   ".join(words)


func _say(text: String) -> void:
	if _headline != null:
		_headline.text = run.biome_name()
	if _banner == null:
		return
	_banner.text = text
	_banner.show()
	_banner.modulate.a = 1.0
	var fade := create_tween()
	fade.tween_interval(1.4)
	fade.tween_property(_banner, "modulate:a", 0.0, 0.6)


# =============================================================
#  SMALL THINGS
# =============================================================

func _make_popup() -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.name = "Popup"
	layer.layer = 20
	add_child(layer)

	var holder := Control.new()
	holder.name = "Holder"
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(holder)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(dim)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(520, 0)
	panel.offset_left = -260.0
	panel.offset_right = 260.0
	panel.offset_top = -200.0
	panel.offset_bottom = 200.0
	panel.add_theme_stylebox_override("panel", MenuSupport.panel_style(
		MenuSupport.COLOUR_PANEL, MenuSupport.COLOUR_ACCENT))
	holder.add_child(panel)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	# THE LAYER is returned, not the holder: freeing the holder would leave
	# an empty CanvasLayer behind and the next popup would stack on top of it.
	return layer


func _make_button(label: String, size: Vector2) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = size
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 15)
	return button


func _quiet(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	return label
