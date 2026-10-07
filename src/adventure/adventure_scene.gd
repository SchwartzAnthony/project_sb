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

## ============ THE LANE, AND HOW BIG EVERYTHING IS ============
##
## The grass band, and the only place a player may stand. Everything that
## moves a walker ends by clamping into it — see adventure_walker.gd — which
## is the fix for the party running along the black above the pitch.
##
## FOUR ROWS OF TUNING.CSV DECIDE THE SCALE, and the numbers below are only
## what is used when those rows are missing:
##
##     adventure_lane_top        where the grass starts down the screen
##     adventure_lane_height     how deep the grass band is
##     adventure_player_size     how big a player is drawn, as a radius
##     adventure_ball_size       how big the ball is drawn, as a radius
##
## The defaults were chosen to MATCH THE ORDINARY PITCH: a deeper lane, a
## player who reads the same size in both places, and a ball small enough to
## be a ball rather than a melon. Lane and player belong together — make the
## band deeper and make the players bigger with it.
static var LANE_TOP := 250.0
static var LANE_HEIGHT := 540.0
static var LANE_BOTTOM := 790.0


const PARTY_X := 300.0          # where the party runs, in screen space
const SPAWN_X := 1500.0         # off the right edge, where things come from
const FORM_X := 220.0           # where the party forms up to fight

var db: CardDatabase
var adventure: AdventureDB
var state: GameState
var run: AdventureRun

var current_state: RunState = RunState.RUNNING

var _scroll_speed := 120.0
## The speed the run settles at. _scroll_speed eases towards a multiple of
## this: a little faster while fetching, slower on the approach to a fight.
var _base_scroll_speed := 120.0
var _travelled := 0.0
var _next_pickup_at := 0.0
## How many pickups are still owed on this stretch, and how far apart they
## are. Both come from Pickups.csv — see _plan_ahead().
var _pickups_left := 0
var _pickup_step := 0.0
var _next_wave_at := 0.0
## How long the two sides have been walking towards each other.
var _meeting_clock := 0.0

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
	# ROUND AN: the game's font, the smallest text size and the see-through
	# plate behind words, even when this scene is opened on its own.
	ThemeBook.dress(get_tree())
	db = CardDatabase.get_db()
	adventure = AdventureDB.get_db()
	state = GameState.fetch(get_tree())
	run = AdventureRun.current(get_tree())

	if run == null:
		# Someone pressed play on this scene directly. Rather than crash,
		# take the first bounty there is so the scene can still be looked at.
		run = _stand_in_run()

	_scroll_speed = db.tune_float("adventure_scroll_speed", 120.0)
	_base_scroll_speed = _scroll_speed

	# WHICH EIGHT ICONS ARE IN PLAY. Worked out once, here, as the run opens
	# — so the bar, the pile and every card agree about what counts. See the
	# EIGHT SLOTS note at the top of trait_db.gd.
	TraitDB.refresh_loadout(state, db)

	_read_scale()
	_read_biome_look()
	_build_world()
	_build_hud()
	_spawn_party()
	_plan_ahead()

	AudioDirector.fire(get_tree(), "match_started",
		{"biome": run.biome_name()}, state)
	_say("%s — %s" % [run.biome_name(), run.bounty_name()])
	print("[adventure] Setting off into %s. %d wave(s) to the boss."
		% [run.biome_name(), run.waves()])


## Read the four scale rows and hand two of them to the walker and the ball,
## which draw themselves. Called before anything is built, so the very first
## frame is already the right size.
func _read_scale() -> void:
	LANE_TOP = db.tune_float("adventure_lane_top", 250.0)
	LANE_HEIGHT = db.tune_float("adventure_lane_height", 540.0)
	LANE_BOTTOM = LANE_TOP + LANE_HEIGHT
	AdventureWalker.RADIUS = db.tune_float("adventure_player_size", 26.0)
	AdventureStrike.BALL_RADIUS = db.tune_float("adventure_ball_size", 7.0)
	print("[adventure] Lane %.0f to %.0f, player radius %.0f, ball radius %.0f."
		% [LANE_TOP, LANE_BOTTOM, AdventureWalker.RADIUS, AdventureStrike.BALL_RADIUS])


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

## ============ THE LOOK OF A BIOME IS FOUR COLOURS AND A PICTURE ============
##
## Biomes.csv now carries them, so an ice biome is blues and a desert is
## yellows without a line of code:
##
##     Background   an image file name. Tiles and scrolls behind everything
##     Parallax     how fast it slides, 0 = still, 1 = same speed as the run
##     Sky          the colour behind it, and what shows if there is no image
##     Grass        the lane
##     Grass Stripe the mown stripes on it
##     Edge         the line along the top and bottom of the lane
##
## Colours are written the way a designer writes them — `#213a26`. Leave a
## column blank and it falls back to the marsh green, so a half-filled row
## still draws.
var _sky_colour := Color(0.09, 0.10, 0.13)
var _grass_colour := Color(0.13, 0.22, 0.15)
var _stripe_colour := Color(0.11, 0.18, 0.12)
var _edge_colour := Color(0.23, 0.36, 0.25)
var _parallax := 0.3
var _backdrop: TextureRect = null


func _read_biome_look() -> void:
	_sky_colour = _colour(String(run.biome.get("sky", "")), _sky_colour)
	_grass_colour = _colour(String(run.biome.get("grass", "")), _grass_colour)
	_stripe_colour = _colour(String(run.biome.get("stripe", "")), _stripe_colour)
	_edge_colour = _colour(String(run.biome.get("edge", "")), _edge_colour)
	_parallax = clampf(float(run.biome.get("parallax", 0.3)), 0.0, 1.0)


## "#213a26" -> a Color. Anything unreadable keeps the fallback rather than
## turning the screen black, and says so once in the Output panel.
static func _colour(text: String, fallback: Color) -> Color:
	var clean := text.strip_edges()
	if clean == "":
		return fallback
	if not clean.begins_with("#"):
		clean = "#" + clean
	if not Color.html_is_valid(clean.substr(1)):
		push_warning("[adventure] '%s' is not a colour. Write it like #213a26 in Biomes.csv." % text)
		return fallback
	return Color.html(clean.substr(1))


func _build_world() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Backdrop"
	layer.layer = -10
	add_child(layer)

	# THE SKY. Always painted, so there is never a black gap — and it is what
	# you see when a biome has no background image yet.
	var sky := ColorRect.new()
	sky.name = "Sky"
	sky.color = _sky_colour
	sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(sky)

	# THE BACKGROUND IMAGE, if the biome names one and the file exists. It is
	# tiled and slid left at the Parallax rate, so it moves slower than the
	# ground and the run reads as having depth.
	var art := MenuSupport.icon_texture(String(run.biome.get("art", "")))
	if art != null:
		_backdrop = TextureRect.new()
		_backdrop.name = "Background"
		_backdrop.texture = art
		_backdrop.stretch_mode = TextureRect.STRETCH_TILE
		_backdrop.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		_backdrop.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		# Wider than the window, so sliding it never shows an edge.
		_backdrop.offset_left = -art.get_width()
		_backdrop.offset_right = art.get_width()
		layer.add_child(_backdrop)
	elif String(run.biome.get("art", "")).strip_edges() != "":
		print("[adventure] Biomes.csv wants background '%s' — put that image in assets/backgrounds/ and it appears. Using the Sky colour until then."
			% run.biome.get("art", ""))

	_world = Node2D.new()
	_world.name = "World"
	add_child(_world)

	var ground := Node2D.new()
	ground.name = "Ground"
	ground.draw.connect(_draw_ground.bind(ground))
	_world.add_child(ground)

	_ball = Node2D.new()
	_ball.name = "Ball"
	_ball.draw.connect(_draw_ball.bind(_ball))
	_world.add_child(_ball)


func _draw_ground(on: Node2D) -> void:
	# THE LANE. Everything the party does happens between these two lines,
	# and the stripes slide with the run so the motion reads even with no art.
	var lane := Rect2(Vector2(-400.0, LANE_TOP), Vector2(2800.0, LANE_HEIGHT))
	on.draw_rect(lane, _grass_colour, true)

	var gap := 120.0
	var offset := fposmod(-_travelled, gap)
	var x := -400.0 + offset
	while x < 2400.0:
		on.draw_rect(Rect2(Vector2(x, LANE_TOP), Vector2(gap * 0.5, LANE_HEIGHT)),
			_stripe_colour, true)
		x += gap

	# The two edges, drawn last so the stripes cannot cover them.
	on.draw_line(Vector2(-400.0, LANE_TOP), Vector2(2400.0, LANE_TOP),
		_edge_colour, 3.0)
	on.draw_line(Vector2(-400.0, LANE_BOTTOM), Vector2(2400.0, LANE_BOTTOM),
		_edge_colour, 3.0)


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
			walker.setup(card, _scroll_speed * 2.2, db)
			# THE LANE IS HANDED TO THE WALKER, not assumed by it. Change
			# LANE_TOP / LANE_HEIGHT and every player obeys the new band.
			walker.lane_top = LANE_TOP
			walker.lane_bottom = LANE_BOTTOM
			walker.place_at(_slot_for(index))
			walker.stamina_fraction = 1.0
			_walkers.append(walker)
			index += 1

	if _walkers.is_empty():
		push_warning("[adventure] Nobody set off — no team was chosen. Go through the team builder first.")
	else:
		_ball.position = _walkers[0].position + Vector2(0.0, -6.0)


## A loose running shape rather than a grid. Slots are staggered on x as
## well as y, and each player drifts around its own slot (see the walker),
## so the party crosses over itself as it runs instead of marching in rows.
##
## ============ HOW MUCH ROOM A PARTY NEEDS ============
##
## Twelve players now carry a name over their head and a Tier/Power window at
## their feet, which is a great deal wider than the player is. Four rows
## across a 540-pixel band put those labels on top of each other.
##
## Both numbers are Tuning.csv rows so the shape can be opened out further
## once the black background becomes a forest or a river bank and the lane
## can afford to be deeper:
##
##     adventure_party_rows      how many across the band. 5 out of the box
##     adventure_party_spacing   pixels between columns, back down the lane
func _slot_for(index: int) -> Vector2:
	var lanes := maxi(1, db.tune_int("adventure_party_rows", 5))
	var spacing := db.tune_float("adventure_party_spacing", 108.0)
	var seat := index % lanes
	var column := index / lanes
	# Odd columns sit half a lane lower, which breaks up the rows.
	var stagger := 0.5 if column % 2 == 1 else 0.0
	var y := LANE_TOP + 52.0 + (float(seat) + stagger) * (LANE_HEIGHT - 104.0) / float(lanes)
	return Vector2(PARTY_X - column * spacing - (seat % 2) * 26.0, y)


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

## ============ THE STRETCH AHEAD, PLANNED RATHER THAN ROLLED ============
##
## "A fixed number of pickups before each wave and the boss, from a CSV."
##
## The wave is put at a fixed distance, and THEN the pickups are shared out
## evenly over that distance — so the count is the number in Pickups.csv
## whatever the run's speed happens to be. It used to be a timer with a
## random gap, which gave a run somewhere between one and six pickups and
## made a biome's haul impossible to balance against. See run_plan.gd.
func _plan_ahead() -> void:
	_next_wave_at = _travelled + _wave_gap()

	var biome_id := String(run.biome.get("id", "")) if run != null else ""
	var boss_next := run != null and run.wave + 1 >= run.waves()
	_pickups_left = RunPlan.how_many(biome_id, boss_next)
	_pickup_step = (_next_wave_at - _travelled) / float(_pickups_left + 1)
	_next_pickup_at = _travelled + _pickup_step
	print("[adventure] %d pickup(s) on this stretch%s."
		% [_pickups_left, " — the boss is next" if boss_next else ""])


func _wave_gap() -> float:
	var seconds := db.tune_float("adventure_wave_gap", 12.0)
	return maxf(200.0, seconds * _scroll_speed)


# =============================================================
#  THE LOOP
# =============================================================

func _process(delta: float) -> void:
	if current_state == RunState.RUNNING:
		_scroll(delta)
	elif current_state == RunState.MEETING:
		_close_in()

	# ============ THE BALL NEVER STOPS ============
	#
	# It used to be knocked about only while the party was RUNNING, so the
	# moment a fight began everybody froze holding it and the pitch went
	# dead while you decided who to go after. A team waiting for a throw-in
	# does not stand still with the ball under one boot.
	#
	# So it is passed in every state except the two where it is BUSY: the
	# encounter takes the ball over to kick it at an enemy, and a finished
	# run has nobody left to pass to.
	if current_state != RunState.ENCOUNTER and current_state != RunState.FINISHED:
		_pass_the_ball(delta)
	elif not _ball_is_busy():
		# In an encounter the ball is passed about too, but only in the gaps
		# — while you are choosing a target or drafting a tier, never while
		# a shot is in the air. _ball_is_busy() is what tells the difference.
		_pass_the_ball(delta)

	if current_state == RunState.RUNNING:
		_carry_pickups(delta)
	_settle_walkers()

	if _world != null:
		var ground := _world.get_node_or_null("Ground")
		if ground != null:
			ground.queue_redraw()


## HOW FAST THE RUN IS GOING RIGHT NOW.
##
## Not a constant: the party puts on a yard when somebody is chasing a
## pickup, and eases off on the approach to a fight so the confrontation
## has a beat of anticipation before it. Both are Tuning.csv rows.
func _wanted_speed() -> float:
	var chasing := false
	for pickup in _pickups:
		if is_instance_valid(pickup) and not (pickup.get_meta("carriers", []) as Array).is_empty():
			chasing = true
			break

	# The last stretch before a wave — slow to a walk.
	var to_wave := _next_wave_at - _travelled
	var slow_from := db.tune_float("adventure_slow_distance", 260.0)
	if to_wave <= slow_from:
		var how_far := clampf(to_wave / maxf(1.0, slow_from), 0.0, 1.0)
		return _base_scroll_speed * lerpf(
			db.tune_float("adventure_approach_pace", 0.55), 1.0, how_far)

	if chasing:
		return _base_scroll_speed * db.tune_float("adventure_fetch_pace", 1.18)
	return _base_scroll_speed


func _scroll(delta: float) -> void:
	# Ease rather than snap, so a change of pace is felt instead of noticed.
	_scroll_speed = move_toward(_scroll_speed, _wanted_speed(),
		_base_scroll_speed * 1.4 * delta)

	var step := _scroll_speed * delta
	_travelled += step

	# The background slides slower than the ground, which is what makes the
	# lane read as near and the picture behind it as far away.
	if _backdrop != null and _backdrop.texture != null:
		var span := float(_backdrop.texture.get_width())
		if span > 1.0:
			_backdrop.position.x = -fposmod(_travelled * _parallax, span)

	# EVERYTHING SLIDES LEFT. The party is what the camera is on, so it
	# stays put on screen and the world moves past it — which is why this is
	# an "endless" scroll rather than a very long level.
	for pickup in _pickups:
		pickup.position.x -= step
	for foe in _foes:
		foe.position.x -= step

	# COUNTED DOWN, NOT TIMED. When the stretch's pickups are used up no
	# more arrive, however long the walk turns out to be.
	if _pickups_left > 0 and _travelled >= _next_pickup_at:
		_pickups_left -= 1
		_next_pickup_at = _travelled + _pickup_step
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
		var was := _ball_holder
		# ============ NOBODY ON THE GROUND GETS THE BALL ============
		#
		# It used to pick any walker at all, so an exhausted player lying on
		# the grass would be passed to and the ball would hover over a body.
		# The pass only ever goes to somebody on their feet now; with nobody
		# on their feet at all it stays where it is.
		var can_take: Array[int] = []
		for i in _walkers.size():
			var who := _walkers[i]
			if who != null and is_instance_valid(who) and not who.lying \
					and not who.knocked_out:
				can_take.append(i)
		if can_take.is_empty():
			return
		_ball_holder = can_take[randi() % can_take.size()]

		# THE LITTLE KNOCK YOU ASKED FOR. The player letting go of the ball and
		# the player taking it both get whatever Juice.csv says — and it is
		# `ball_kicked` and `ball_received` there, so you can give the two of
		# them different weight without touching a line of this file.
		if was != _ball_holder:
			var leaving := _walkers[was] if was < _walkers.size() else null
			if leaving != null and is_instance_valid(leaving) and not leaving.lying:
				Juice.fire(self, "ball_kicked", {"node": leaving})
			var taking := _walkers[_ball_holder]
			if taking != null and is_instance_valid(taking) and not taking.lying:
				Juice.fire(self, "ball_received", {"node": taking})

	if _ball_holder >= _walkers.size():
		return
	var holder := _walkers[_ball_holder]
	if holder != null and is_instance_valid(holder) and not holder.lying:
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

	# HIGH OR LOW IN THE LANE, never always in front. That is what stops the
	# same two players collecting everything: an item near the top edge is
	# reached by whoever happens to be drifting up there.
	var pickup := Node2D.new()
	pickup.position = Vector2(SPAWN_X,
		randf_range(LANE_TOP + 34.0, LANE_BOTTOM - 34.0))
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
	return Vector2(FORM_X - column * 72.0,
		LANE_TOP + 56.0 + float(seat) * (LANE_HEIGHT - 112.0) / 3.0)


# =============================================================
#  MEETING A WAVE
# =============================================================

func _begin_meeting() -> void:
	current_state = RunState.MEETING
	_meeting_clock = 0.0

	# DROP WHATEVER YOU WERE CHASING. A player half way to a pickup when a
	# wave arrived used to keep walking towards it forever — the pickup was
	# no longer being scrolled, so it never arrived and neither did they.
	# That is the two players stuck out in the middle of your screenshot.
	for walker in _walkers:
		if walker != null and is_instance_valid(walker):
			walker.fetching = false
	for pickup in _pickups:
		if is_instance_valid(pickup):
			pickup.queue_free()
	_pickups.clear()

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

	# ENEMIES HAVE NO TIERS ANY MORE, so a wave is simply a number of them
	# drawn from the biome's pool by Weight. Change how many in Tuning.csv;
	# change which, and how often, in AdventureEnemies.csv.
	if not boss_wave:
		var wanted := maxi(1, db.tune_int("adventure_enemies_per_wave", 3))
		for i in wanted:
			var drawn := adventure.draw_from_pool(pool)
			if not drawn.is_empty():
				line_up.append(drawn)

	for i in line_up.size():
		var foe := Node2D.new()
		foe.position = Vector2(SPAWN_X + i * 90.0,
			LANE_TOP + LANE_HEIGHT * (0.16 + float(i % 3) * 0.30))
		foe.set_meta("enemy", line_up[i])
		foe.set_meta("home", Vector2(920.0 + (i / 3) * 96.0,
			LANE_TOP + LANE_HEIGHT * (0.16 + float(i % 3) * 0.30)))
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

	# YOU PICK BY CLICKING THE THING ITSELF, so it has to show that it can be
	# clicked and which one is chosen. A pale ring under the pointer, a solid
	# accent ring on the one you are going after.
	if bool(on.get_meta("focused", false)):
		on.draw_arc(Vector2.ZERO, size + 7.0, 0.0, TAU, 32,
			MenuSupport.COLOUR_ACCENT, 3.0, true)
	elif bool(on.get_meta("hovered", false)):
		on.draw_arc(Vector2.ZERO, size + 5.0, 0.0, TAU, 32,
			MenuSupport.COLOUR_TEXT, 2.0, true)

	var font := ThemeDB.fallback_font
	var label := str(int(entry.get("attack", 1)))
	var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16).x
	on.draw_string(font, Vector2(-width * 0.5, 6.0), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, MenuSupport.COLOUR_TEXT)

	# ONE BAR PER LAYER, outermost on top. This is the shape of the fight in
	# Phase 3 and 4: chew through the top bar before the next one is exposed.
	# ONE BAR PER LAYER, AND THEY EMPTY AS YOU HIT IT.
	#
	# These used to be drawn from the CSV row, which never changes — so the
	# bars sat full for the whole fight however hard you hit. The encounter
	# now writes what is LEFT onto this node after every hit (see
	# `set_meta("left", ...)`), and the filled part is drawn from that.
	var layers: Array = entry.get("layers", [])
	var left: Array = on.get_meta("left", [])
	var y := size + 6.0
	for i in layers.size():
		var layer: Dictionary = layers[i]
		var amount := maxi(1, int(layer["amount"]))
		var soak := int(layer["soak"])
		var still := amount if i >= left.size() else clampi(int(left[i]), 0, amount)

		var width_px := clampf(float(amount) * 2.4, 16.0, 74.0)
		var track := Rect2(Vector2(-width_px * 0.5, y), Vector2(width_px, 5.0))
		on.draw_rect(track, Color(0.10, 0.11, 0.14), true)

		if still > 0:
			var filled := track
			filled.size.x = width_px * (float(still) / float(amount))
			# Darker means it soaks more — a wall to grind rather than sweep.
			on.draw_rect(filled,
				Color(0.78, 0.44, 0.40).darkened(float(soak) * 0.14), true)
		y += 7.0


## The two sides walk towards each other, then the encounter starts.
## The two sides close, and then the fight opens.
##
## IT USED TO WAIT FOR THE PLAYERS TOO, and the players drift on purpose —
## so "everybody has settled" could be true late or never, and the combat
## panel took an age to appear. Only the ENEMIES walking into place is
## waited on now, and even that has a ceiling: after
## `adventure_meet_seconds` the fight starts regardless.
func _close_in() -> void:
	_meeting_clock += get_process_delta_time()

	var arrived := true
	for foe in _foes:
		if not is_instance_valid(foe):
			continue
		var home: Vector2 = foe.get_meta("home")
		foe.position = foe.position.move_toward(home,
			_scroll_speed * 3.2 * get_process_delta_time())
		if foe.position.distance_to(home) > 6.0:
			arrived = false
		foe.queue_redraw()

	if arrived or _meeting_clock > db.tune_float("adventure_meet_seconds", 1.6):
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
	_say("COMBAT")

	# Everything about the fight lives in adventure_encounter.gd. This scene
	# only hands it the wave and waits to hear how it went.
	# The fight is handed the enemies' rows AND their nodes, plus a way to
	# find the walker for a card. That is what lets it show the kick and the
	# hits rather than only writing them down. Nothing breaks if a node has
	# gone — adventure_strike.gd checks everything it is given.
	var wave: Array[Dictionary] = []
	var nodes: Array[Node2D] = []
	for foe in _foes:
		if is_instance_valid(foe):
			wave.append(foe.get_meta("enemy", {}) as Dictionary)
			nodes.append(foe)

	var fight := AdventureEncounter.open(self, db, state, run, wave,
		_world, nodes, Callable(self, "walker_for"), _ball)

	# THE BARS FOLLOW THE FIGHT. Without this the stamina under a player only
	# caught up when the whole encounter was over, so being hit showed you
	# nothing. The fight says "somebody changed" and this repaints them.
	fight.party_changed.connect(_refresh_walkers)

	var result: Array = await fight.finished
	fight.queue_free()

	# THE CLOCK GOES STRAIGHT WHEN THE FIGHT ENDS. A slow-motion dip that was
	# still running when the last enemy went down would otherwise keep the
	# whole scroll running slow. See juice.gd.
	Juice.release()
	# And the stand-ins go home. See _send_off_stand_ins().
	_send_off_stand_ins()

	var cleared := bool(result[0])
	var fled := bool(result[1])

	_refresh_walkers()

	if fled:
		_flee_home()
	elif cleared:
		await _win_encounter()
	else:
		_party_fell()


## IS THE BALL IN THE MIDDLE OF SOMETHING?
##
## adventure_strike.gd claims the ball while a kick is in the air by putting
## a `busy` mark on it, and drops the mark when the ball lands. Anything that
## would move the ball asks here first, so a pass can never yank a shot out
## of mid-flight.
func _ball_is_busy() -> bool:
	if _ball == null or not is_instance_valid(_ball):
		return true
	return bool(_ball.get_meta("busy", false))


## The walker standing in for a card, so the fight can kick a ball at the
## right player. Null when that card is not on the pitch.
func walker_for(card: PlayerData) -> Node2D:
	for walker in _walkers:
		if walker != null and is_instance_valid(walker) and walker.card == card:
			return walker
	return null


## KNOCKED OUT PLAYERS SHOW IT ON THE PITCH. The run holds the stamina; the
## walkers only draw it, so this is the one place the two are put in step.
## ============ SOMEBODY WHO WAS NOT THERE A MOMENT AGO ============
##
## A combo can bring a stand-in on mid-fight — a Treant walking out of the
## reeds to replace somebody who went down. It joins the squad in the run,
## and this is what gives it a body on the pitch: a walker like any other,
## so it takes the ball, gets passed to, takes hits and can be drafted.
##
## It comes on BESIDE the party rather than off the edge, because it did not
## travel here — it simply arrived.
func _walkers_for_new_arrivals() -> void:
	for tier in TierLadder.TIERS:
		for entry in (run.squad.get(tier, []) as Array):
			var card := entry as PlayerData
			if card == null or walker_for(card) != null:
				continue
			var walker := AdventureWalker.new()
			_world.add_child(walker)
			walker.setup(card, _scroll_speed * 2.2, db)
			walker.lane_top = LANE_TOP
			walker.lane_bottom = LANE_BOTTOM
			# Beside whoever is already standing, not on top of them.
			var beside := _formation_slot(_walkers.size())
			if not _walkers.is_empty():
				var first := _walkers[0]
				if is_instance_valid(first):
					beside = first.position + Vector2(randf_range(-70.0, 40.0),
						randf_range(-90.0, 90.0))
			# place_at(), not `position =`. A stand-in offered a slot beside
			# whoever is at the front can be handed a y above the top of the
			# band; place_at clamps it onto the grass. This is where the
			# Treant that lay on the black came from.
			walker.place_at(beside)
			walker.stamina_fraction = 1.0
			_walkers.append(walker)
			_say("%s joins you" % card.player_name)


## The stand-ins go home when the fight does. Their walkers are freed and
## the run forgets them, so the next wave is your team again.
func _send_off_stand_ins() -> void:
	for card in run.send_off_stand_ins():
		var walker := walker_for(card)
		if walker != null and is_instance_valid(walker):
			var fade := walker.create_tween()
			fade.tween_property(walker, "modulate:a", 0.0, 0.35)
			fade.finished.connect(func() -> void:
				if is_instance_valid(walker):
					walker.queue_free())
			_walkers.erase(walker)
	_settle_walkers()


func _refresh_walkers() -> void:
	# A stand-in brought on by a combo has no body yet. Give it one before
	# anything tries to draw it.
	_walkers_for_new_arrivals()
	for walker in _walkers:
		if walker == null or not is_instance_valid(walker) or walker.card == null:
			continue
		var full := AdventureRun.stamina_for(walker.card, db)
		walker.stamina_fraction = float(run.stamina_of(walker.card, db)) / maxf(1.0, float(full))
		walker.knocked_out = run.is_out(walker.card)
		# OUT OF STAMINA MEANS ON THE GROUND, not standing around greyed out.
		# The run holds the truth and the walker only shows it, so this is the
		# single place in the game where a player drops or gets back up. Both
		# calls do nothing if the player is already in that state.
		if walker.knocked_out:
			walker.lie_down()
		else:
			walker.get_up()


## FLED. You keep the share Tuning.csv says and walk out with it.
func _flee_home() -> void:
	current_state = RunState.FINISHED
	var keep := db.tune_float("adventure_flee_keep", 0.8)
	var taken := run.bank(state, keep)
	state.save_to_disk()
	AdventureRun.clear(get_tree())
	print("[adventure] Fled with %d%% of the haul: %s" % [int(keep * 100.0), taken])
	ScenePaths.go_to(get_tree(), ScenePaths.BASE, false)


## EVERYBODY DOWN. The haul is gone — that is what makes Return to Base a
## real decision rather than an obvious one.
func _party_fell() -> void:
	current_state = RunState.LOOT
	_popup = _make_popup()
	var box := _popup.get_node("Holder/Panel/Margin/Column") as VBoxContainer
	box.add_child(MenuSupport.heading("EVERYBODY IS DOWN", 28,
		Color(0.90, 0.42, 0.38)))
	box.add_child(_quiet(
		"You were carrying %d thing%s and none of it comes home. The party picks itself up outside the biome."
		% [run.haul_size(), "" if run.haul_size() == 1 else "s"]))

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)

	var home := _make_button("Back to the base", Vector2(240, 52))
	home.pressed.connect(func() -> void:
		current_state = RunState.FINISHED
		run.haul.clear()
		state.save_to_disk()
		AdventureRun.clear(get_tree())
		ScenePaths.go_to(get_tree(), ScenePaths.BASE, false))
	buttons.add_child(home)


# =============================================================
#  THE STRETCHER
#
#  ============ WHAT THIS IS ============
#
#  A player who runs out of stamina lies where they fell (see lie_down() in
#  adventure_walker.gd). When the last enemy is down, TWO PLAYERS WHO ARE NOT
#  ON YOUR TEAM jog in from behind the party, pick up everybody on the ground,
#  and carry them back off the way they came. Then the party moves on.
#
#  ============ WHO THE TWO ARE ============
#
#  Anybody in your unit CSV who is not in the party. They are ordinary cards,
#  drawn as ordinary walkers, so they get whatever artwork that card has and
#  they will change as you add units. They are never the same players as the
#  ones you are running with, which is the point — help arrives from outside.
#
#  If your CSV is so small that there is nobody spare, the stretcher is
#  skipped and the fallen simply stay down. Nothing breaks.
#
#  ============ TURNING IT OFF ============
#
#      adventure_stretcher        false and nobody is carried off
#      adventure_stretcher_seconds  how long the whole thing takes
# =============================================================

## Everybody on the ground is taken off before the party runs on.
##
## Awaited, so the loot popup does not land on top of it.
func _carry_off_the_fallen() -> void:
	if not db.tune_bool("adventure_stretcher", true):
		return

	var fallen: Array[AdventureWalker] = []
	for walker in _walkers:
		if walker == null or not is_instance_valid(walker) or walker.card == null:
			continue
		if run.is_out(walker.card):
			walker.lie_down()
			fallen.append(walker)
	if fallen.is_empty():
		return

	# TWO BEARERS PER FALLEN PLAYER, all going at once. One pair at a time
	# looked like a queue at a bus stop when three players were down.
	var spare := _players_not_on_the_team(fallen.size() * 2)
	if spare.is_empty():
		return

	_say("STRETCHER")
	var seconds := db.tune_float("adventure_stretcher_seconds", 2.4)
	var crews: Array = []
	for i in fallen.size():
		var left_card: PlayerData = spare[(i * 2) % spare.size()]
		var right_card: PlayerData = spare[(i * 2 + 1) % spare.size()]
		crews.append({
			"down": fallen[i],
			"crew": [_make_bearer(left_card, fallen[i], -1),
				_make_bearer(right_card, fallen[i], 1)],
		})

	await _walk_the_stretchers(crews, seconds)

	# The bearers are done with; the fallen player goes with them, so the
	# walker is freed too and its card simply is not on the pitch any more.
	for entry in crews:
		for bearer in (entry["crew"] as Array):
			if is_instance_valid(bearer):
				bearer.queue_free()
		var down: AdventureWalker = entry["down"]
		if is_instance_valid(down):
			_walkers.erase(down)
			down.queue_free()

	_settle_walkers()


## Cards that exist in your CSV but are not in the party. Shuffled, so the
## same two people are not on stretcher duty all game.
func _players_not_on_the_team(how_many: int) -> Array[PlayerData]:
	var on_the_team: Dictionary = {}
	for walker in _walkers:
		if walker != null and is_instance_valid(walker) and walker.card != null:
			on_the_team[walker.card.player_name] = true

	var pool: Array[PlayerData] = []
	for card in db.players:
		if card == null or on_the_team.has(card.player_name):
			continue
		pool.append(card)
	if pool.is_empty():
		return pool

	pool.shuffle()
	return pool.slice(0, mini(how_many, pool.size()))


## One bearer, stood off the left edge ready to come in. `side` is -1 for the
## one at the head and 1 for the one at the feet.
func _make_bearer(card: PlayerData, down: AdventureWalker, side: int) -> AdventureWalker:
	var bearer := AdventureWalker.new()
	_world.add_child(bearer)
	bearer.setup(card, _scroll_speed * 2.6, db)
	bearer.lane_top = LANE_TOP
	bearer.lane_bottom = LANE_BOTTOM
	# THEY COME FROM BEHIND. The party is running right, so help arrives from
	# the left — the way everybody came in.
	bearer.position = Vector2(-220.0 - randf() * 140.0,
		clampf(down.position.y + float(side) * 30.0,
			LANE_TOP + AdventureWalker.RADIUS, LANE_BOTTOM - AdventureWalker.RADIUS))
	bearer.target = bearer.position
	bearer.stamina_fraction = 1.0
	# THE TWEEN OWNS THEM. A bearer is walked by the three tweens below, so its
	# own steering and drift are switched off — otherwise the two would pull
	# the same walker in slightly different directions and it would judder.
	bearer.being_carried = true
	return bearer


## Run in, lift, carry out. Three plain tweens rather than any clever state,
## because it happens once and then everybody involved is freed.
func _walk_the_stretchers(crews: Array, seconds: float) -> void:
	var in_time := seconds * 0.4
	var lift_time := seconds * 0.15
	var out_time := seconds * 0.45

	# --- 1. IN. Each pair jogs to either side of its player. ---
	var arrive := create_tween()
	arrive.set_parallel(true)
	for entry in crews:
		var down: AdventureWalker = entry["down"]
		var side := -1
		for bearer in (entry["crew"] as Array):
			var beside := down.position + Vector2(float(side) * 46.0, float(side) * 8.0)
			arrive.tween_property(bearer, "position", beside, in_time) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			side = 1
	await arrive.finished

	# --- 2. LIFT. The player comes up off the grass a little. ---
	var lift := create_tween()
	lift.set_parallel(true)
	for entry in crews:
		var down: AdventureWalker = entry["down"]
		down.being_carried = true
		lift.tween_property(down, "position:y", down.position.y - 26.0, lift_time) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await lift.finished

	# --- 3. OUT. Everybody walks off the left edge together. ---
	var leave := create_tween()
	leave.set_parallel(true)
	for entry in crews:
		var down: AdventureWalker = entry["down"]
		var away := Vector2(-420.0, down.position.y)
		leave.tween_property(down, "position", away, out_time) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		var side := -1
		for bearer in (entry["crew"] as Array):
			var bearer_away := away + Vector2(float(side) * 46.0, float(side) * 8.0)
			leave.tween_property(bearer, "position", bearer_away, out_time) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
			side = 1
	await leave.finished


func _win_encounter() -> void:
	# THE FALLEN GO FIRST. The enemies are down, so before anything is counted
	# or claimed, anybody lying on the grass is carried off. Awaited, so the
	# loot popup never lands on top of the stretcher.
	await _carry_off_the_fallen()

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

	# ============ WHAT SHAPE THE PARTY IS IN ============
	#
	# Continue Forward should be an informed choice, and it was not: the
	# popup said what you had picked up but nothing about what it had cost
	# you. Stamina does NOT come back between waves, so this is the number
	# that decides whether to push on or walk home.
	box.add_child(MenuSupport.heading("THE PARTY", 15, MenuSupport.COLOUR_TEXT_DIM))
	for tier in TierLadder.TIERS:
		var standing := run.standing_in(tier, db)
		var full := 0
		var left := 0
		for entry in (run.squad.get(tier, []) as Array):
			var card := entry as PlayerData
			if card == null:
				continue
			full += AdventureRun.stamina_for(card, db)
			if not run.is_out(card):
				left += run.stamina_of(card, db)

		var row := Label.new()
		var share := 0 if full <= 0 else int(round(100.0 * float(left) / float(full)))
		row.text = "Tier %-4s %d of %d standing   ·   %d%% stamina" % [
			tier, standing.size(), (run.squad.get(tier, []) as Array).size(), share]
		row.add_theme_font_size_override("font_size", 14)
		row.add_theme_color_override("font_color",
			MenuSupport.COLOUR_TEXT if share > 34 else Color(0.90, 0.52, 0.45))
		box.add_child(row)

	if not run.knocked_out.is_empty():
		box.add_child(_quiet(
			"%d down. Smelling Salts bring one back — use them from ITEMS in the next fight."
			% run.knocked_out.size()))

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
	# ONE PLACE PLANS THE NEXT STRETCH, so the pickup count and the wave
	# distance can never be worked out two different ways.
	_plan_ahead()
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
		# THE BIOME IS MARKED AS CLEARED. Next time in, its enemies are
		# scaled up — see AdventureRun.difficulty().
		run.record_clear(state)
		var reward := String(run.bounty.get("reward", ""))
		if reward.strip_edges() != "":
			DialogueGrammar.apply(reward, state)
			print("[adventure] Bounty claimed: %s" % reward)

	# ROUND AN: a run carried home is counted - count:adventures_home is what
	# sends you to the Traveling Merchant after your first one (Progression.csv).
	DialogueGrammar.apply("count:adventures_home+1", state)
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
