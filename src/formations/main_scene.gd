extends Node2D

# =============================================================
#  MAIN SCENE — match clock, drafting, spawning, round resolution
#
#  MATCH SHAPE
#    Kickoff        : pick 1 of 3 Star Players (this picks your class)
#    Round          : "PLAY MAKER!" -> pick through Tier I, II, III, IV.
#                     The tier your active Star sits in is skipped (the
#                     Star already occupies that slot), so it is 3 picks.
#    Cycle          : 3 rounds — 3-of-3, then 2-of-2, then 1-of-1.
#    "HOLD UP!"     : end of cycle. Active Star goes inactive, you pick
#                     from the remaining Stars, all 9 regulars reset.
#    Total          : 3 cycles = 9 PLAY MAKERs + 2 HOLD UPs = 11 pauses.
# =============================================================

signal round_ready_for_combat(player_lineup: Array, enemy_lineup: Array)
signal round_resolved(player_score: int, enemy_score: int)
signal match_ended(player_score: int, enemy_score: int)

# --- Scene wiring -------------------------------------------
@onready var selection_ui: CanvasLayer = $SelectionUI
@onready var card_container: HBoxContainer = $SelectionUI/CardContainer
@onready var start_draft_button: Button = $SelectionUI/StartDraftButton
@onready var timer_label: Label = $SelectionUI/TimerLabel
@onready var event_announcement: Label = $SelectionUI/EventAnnouncement

@export var field_sprite: Sprite2D

const PLAYER_CARD_SCENE: PackedScene = preload("res://src/ui/player_card_ui.tscn")
const PLAYER_UNIT_SCENE: PackedScene = preload("res://src/units/player_unit.tscn")
const GOALIE_SCENE: PackedScene = preload("res://src/units/goalie_unit.tscn")
const RPS_SCENE: PackedScene = preload("res://src/ui/rps_clash.tscn")

# --- Match settings -----------------------------------------
# These are VARIABLES, not constants, because Tuning.csv overwrites them in
# _ready(). The values here are only the fallback when a row is missing.
const ALL_TIERS: Array[String] = ["I", "II", "III", "IV"]
var ROUNDS_PER_CYCLE := 3
var TOTAL_CYCLES := 3
var MATCH_LENGTH_MINUTES := 90.0
var FIRST_EVENT_MINUTE := 5.0
var LAST_EVENT_MINUTE := 82.0

## 90 in-game minutes elapse over (90 / time_scale) real seconds.
@export var time_scale: float = 1.0
## On an exact power tie in a duel: false = defender holds, true = attacker breaks through.
@export var ties_go_to_attacker: bool = false
## Resolve rounds instantly in code. Turn OFF once combat_arena.tscn exists.
@export var headless_combat: bool = true
## Show the rock/paper/scissors screen. Off = silent coin flip.
@export var use_rps_minigame: bool = true

enum MatchState { PRE_MATCH, PLAYING, DRAFTING, AUTOBATTLE, FULL_TIME }

# --- Runtime state ------------------------------------------
var current_state: MatchState = MatchState.PRE_MATCH
var match_time_minutes: float = 0.0

var current_cycle: int = 1
var rounds_this_cycle: int = 0
var event_schedule: Array[float] = []
var next_event_index: int = 0

var units_container: Node2D
var goalies: Dictionary = {}   # false -> player goalie, true -> enemy goalie
var ball: Ball = null
var rps: RpsClash = null
## Everything the game knows, read from res://data/*.csv at startup.
var db: CardDatabase
var abilities: AbilityEngine
## Who won the rock/paper/scissors clash and chose to attack this round.
var player_attacks_this_round: bool = true
## The card holding the ball when the duel chain ended — it takes the shot.
var round_shooter_card: PlayerData = null
## Substitutions can nest (enemy rotates its Star at the same moment you do),
## so freezing is reference-counted rather than a plain bool.
var _freeze_depth: int = 0

# Team state
var player_star_bundle: Array[PlayerData] = []
var enemy_star_bundle: Array[PlayerData] = []
var available_player_stars: Array[PlayerData] = []
var available_enemy_stars: Array[PlayerData] = []
var active_player_star: PlayerData = null
var active_enemy_star: PlayerData = null
var player_star_tier: String = ""
var enemy_star_tier: String = ""

# Draft state
var draft_phases: Array[String] = []
var current_phase_index: int = 0
var round_player_picks: Array[PlayerData] = []
var round_enemy_picks: Array[PlayerData] = []
## True only between "PLAY MAKER!" and its combat. Kickoff and HOLD UP! drafts
## must NOT resolve combat — without this they replay the previous round's
## picks and fire a phantom shot (11 shots per match instead of 9).
var round_in_progress: bool = false

var player_score: int = 0
var enemy_score: int = 0


# =============================================================
#  LIFECYCLE
# =============================================================

func _ready() -> void:
	randomize()

	db = CardDatabase.get_db()
	abilities = AbilityEngine.new(db)
	_apply_match_tuning()

	units_container = Node2D.new()
	units_container.name = "UnitsContainer"
	add_child(units_container)

	spawn_goalies()
	spawn_ball()
	spawn_rps()
	build_event_schedule()

	event_announcement.hide()
	timer_label.text = "00:00"
	start_draft_button.show()
	start_draft_button.pressed.connect(_on_start_draft_pressed)


func _process(delta: float) -> void:
	if current_state != MatchState.PLAYING:
		return

	match_time_minutes += delta * time_scale

	# --- Final whistle ---
	if match_time_minutes >= MATCH_LENGTH_MINUTES:
		_full_time()
		return

	_update_clock_label()

	# --- Scheduled events ---
	if next_event_index < event_schedule.size() \
			and match_time_minutes >= event_schedule[next_event_index]:
		next_event_index += 1
		if rounds_this_cycle >= ROUNDS_PER_CYCLE and current_cycle < TOTAL_CYCLES:
			trigger_hold_up_event()
		elif rounds_this_cycle < ROUNDS_PER_CYCLE:
			trigger_playmaker_event()


# =============================================================
#  TUNING — every number below comes from Tuning.csv when a row exists,
#  otherwise the value already in code stands. Nothing here can crash on a
#  missing or misspelled row.
# =============================================================

func _apply_match_tuning() -> void:
	MATCH_LENGTH_MINUTES = db.tune_float("match_length_minutes", MATCH_LENGTH_MINUTES)
	FIRST_EVENT_MINUTE = db.tune_float("first_event_minute", FIRST_EVENT_MINUTE)
	LAST_EVENT_MINUTE = db.tune_float("last_event_minute", LAST_EVENT_MINUTE)
	ROUNDS_PER_CYCLE = db.tune_int("rounds_per_cycle", ROUNDS_PER_CYCLE)
	TOTAL_CYCLES = db.tune_int("total_cycles", TOTAL_CYCLES)
	ties_go_to_attacker = db.tune_bool("ties_go_to_attacker", ties_go_to_attacker)
	use_rps_minigame = db.tune_bool("use_rps_minigame", use_rps_minigame)


func _tune_ball() -> void:
	if ball == null:
		return
	ball.pass_speed = db.tune_float("ball_pass_speed", ball.pass_speed)
	ball.shot_speed = db.tune_float("ball_shot_speed", ball.shot_speed)
	ball.carry_seconds = Vector2(
		db.tune_float("ball_carry_min_seconds", ball.carry_seconds.x),
		db.tune_float("ball_carry_max_seconds", ball.carry_seconds.y))
	ball.forward_pass_chance = db.tune_float("ball_forward_pass_chance", ball.forward_pass_chance)
	ball.intercept_radius = db.tune_float("ball_intercept_radius", ball.intercept_radius)
	ball.tackle_radius = db.tune_float("ball_tackle_radius", ball.tackle_radius)
	ball.possession_grace = db.tune_float("ball_possession_grace", ball.possession_grace)
	ball.tackle_recovery = db.tune_float("ball_tackle_recovery", ball.tackle_recovery)


func _tune_rps() -> void:
	if rps == null:
		return
	rps.enemy_attack_chance = db.tune_float("enemy_attack_chance", rps.enemy_attack_chance)
	rps.reveal_seconds = db.tune_float("rps_reveal_seconds", rps.reveal_seconds)
	rps.result_seconds = db.tune_float("rps_result_seconds", rps.result_seconds)


func _tune_unit(unit: PlayerUnit) -> void:
	unit.walk_speed = db.tune_float("unit_walk_speed", unit.walk_speed)
	unit.chase_speed = db.tune_float("unit_chase_speed", unit.chase_speed)
	unit.dribble_speed = db.tune_float("unit_dribble_speed", unit.dribble_speed)
	unit.interest_radius = db.tune_float("unit_interest_radius", unit.interest_radius)
	unit.roam_radius = db.tune_float("unit_roam_radius", unit.roam_radius)


func _tune_goalie(keeper: GoalieUnit) -> void:
	keeper.break_through_chance = db.tune_float("goalie_break_through_chance", keeper.break_through_chance)
	keeper.open_goal_chance = db.tune_float("goalie_open_goal_chance", keeper.open_goal_chance)


func _update_clock_label() -> void:
	var mins := int(match_time_minutes)
	var secs := int((match_time_minutes - mins) * 60.0)
	timer_label.text = "%02d:%02d" % [mins, secs]


func _full_time() -> void:
	match_time_minutes = MATCH_LENGTH_MINUTES
	current_state = MatchState.FULL_TIME
	timer_label.text = "90:00"
	event_announcement.text = "FULL TIME  %d - %d" % [player_score, enemy_score]
	event_announcement.show()
	print("FULL TIME — %d : %d" % [player_score, enemy_score])
	match_ended.emit(player_score, enemy_score)


# =============================================================
#  EVENT SCHEDULE
#  11 pauses spread evenly across the 90 minutes, with jitter.
# =============================================================

func build_event_schedule() -> void:
	event_schedule.clear()
	var total_events := TOTAL_CYCLES * ROUNDS_PER_CYCLE + (TOTAL_CYCLES - 1)  # 11
	var gap := (LAST_EVENT_MINUTE - FIRST_EVENT_MINUTE) / float(total_events - 1)
	for i in total_events:
		event_schedule.append(FIRST_EVENT_MINUTE + gap * i + randf_range(-1.2, 1.2))
	event_schedule.sort()


# =============================================================
#  KICKOFF
# =============================================================

func _on_start_draft_pressed() -> void:
	start_draft_button.hide()
	current_state = MatchState.DRAFTING
	draft_phases.assign(["Star"])
	current_phase_index = 0
	print("Kickoff — choose your Star Player.")
	start_next_draft_phase()


func _resolve_kickoff_star(chosen: PlayerData) -> void:
	active_player_star = chosen
	player_star_tier = chosen.get_tier_clean()

	player_star_bundle = get_star_bundle_by_type(chosen.unit_type)
	available_player_stars = player_star_bundle.duplicate()
	available_player_stars.erase(chosen)

	spawn_team(chosen, false)

	# Enemy picks a different class so you never mirror-match.
	_choose_enemy_team(chosen.unit_type)

	_assign_goalie_data()

	for unit in _all_units():
		unit.clear_round_flags()
		if unit.data == chosen and not unit.is_enemy:
			unit.is_playmaker = true
			unit.set_highlight(true)

	# Kick-off: your Star starts on the ball.
	give_ball_to(false)

	print("Player class: %s  |  Star: %s (Tier %s)" % [
		chosen.unit_type, chosen.player_name, player_star_tier])


func _choose_enemy_team(player_type_to_avoid: String) -> void:
	var by_class := _stars_grouped_by_class()
	var candidates: Array[String] = []
	for class_name_key in by_class.keys():
		if String(class_name_key).to_lower() != player_type_to_avoid.to_lower():
			candidates.append(String(class_name_key))

	if candidates.is_empty():
		push_warning("Only one class of Star Players found — enemy will mirror your class.")
		candidates.append(player_type_to_avoid)

	candidates.shuffle()
	var enemy_class: String = candidates[0]

	enemy_star_bundle = get_star_bundle_by_type(enemy_class)
	enemy_star_bundle.shuffle()
	if enemy_star_bundle.is_empty():
		push_error("No Star Players found for enemy class '%s'." % enemy_class)
		return

	active_enemy_star = enemy_star_bundle[0]
	enemy_star_tier = active_enemy_star.get_tier_clean()
	available_enemy_stars = enemy_star_bundle.duplicate()
	available_enemy_stars.erase(active_enemy_star)

	spawn_team(active_enemy_star, true)

	for unit in _all_units():
		if unit.is_enemy:
			unit.set_highlight(false)

	print("Enemy class: %s  |  Star: %s (Tier %s)" % [
		enemy_class, active_enemy_star.player_name, enemy_star_tier])


# =============================================================
#  SPAWNING
# =============================================================

func spawn_team(star_player: PlayerData, is_enemy: bool) -> void:
	if star_player == null:
		push_error("spawn_team called with no Star Player.")
		return
	var pitch_center_x := get_pitch_center_x()
	var this_star_tier := star_player.get_tier_clean()

	# A formation scene is now OPTIONAL. Whatever it does not supply is filled
	# in from a generated layout, so a team always reaches the pitch.
	var layout := build_layout(star_player, this_star_tier)

	# --- 1. The Star ---
	var star_pos: Vector2 = mirror_if_enemy(layout["star"], pitch_center_x, is_enemy)
	var star_unit := create_unit_instance(star_player, star_pos, is_enemy)
	if star_unit:
		star_unit.is_star_player = true

	# --- 2. The 9 regulars ---
	var roster := load_roster_by_type(star_player.unit_type)
	var tiers: Dictionary = layout["tiers"]

	for tier_key in ALL_TIERS:
		if tier_key == this_star_tier:
			continue                      # the Star already fills this tier
		if not tiers.has(tier_key):
			continue

		var positions: Array = tiers[tier_key]
		var pool := filter_units_by_tier(roster, tier_key)
		pool.shuffle()

		if pool.size() < positions.size():
			# A data problem, not a code fault — CardDB has already named the
			# offending row, so print rather than push_warning (no backtrace).
			print("[roster] '%s' has only %d Tier %s cards for %d slots."
				% [star_player.unit_type, pool.size(), tier_key, positions.size()])

		for i in mini(positions.size(), pool.size()):
			var pos: Vector2 = mirror_if_enemy(positions[i], pitch_center_x, is_enemy)
			create_unit_instance(pool[i], pos, is_enemy)


# Reads whatever the formation scene offers, then patches the gaps and
# normalises the result so it always lands inside your own half of the screen.
func build_layout(star_player: PlayerData, star_tier: String) -> Dictionary:
	var star_pos := Vector2.ZERO
	var have_star := false
	var tiers: Dictionary = {}

	if star_player.formation_scene != null:
		var formation := star_player.formation_scene.instantiate()
		formation.visible = false      # it carries its own pitch sprites
		add_child(formation)

		# The markers are NOT direct children: the real layout is
		# StarSlot/TierIII/Star_TierIII, so search the whole subtree.
		var star_slot := formation.get_node_or_null("StarSlot")
		if star_slot != null:
			var m := _first_marker_in(star_slot)
			if m != null:
				star_pos = m.global_position
				have_star = true

		var regular_slots := formation.get_node_or_null("RegularSlots")
		if regular_slots != null:
			for tier_node in regular_slots.get_children():
				var key := String(tier_node.name).replace("Tier", "").strip_edges().to_upper()
				var arr: Array[Vector2] = []
				for m2 in _all_markers_in(tier_node):
					arr.append(m2.global_position)
				if not arr.is_empty():
					tiers[key] = arr

		remove_child(formation)
		formation.free()

	# --- Fill in anything the scene did not provide ---
	var fallback := default_layout(star_tier)
	var fallback_tiers: Dictionary = fallback["tiers"]

	if not have_star:
		star_pos = fallback["star"]
		if star_player.formation_scene != null:
			print("[formation] '%s' has no Marker2D under StarSlot — generated the Star position."
				% star_player.player_name)

	for key in fallback_tiers.keys():
		if not tiers.has(key) or (tiers[key] as Array).size() < 3:
			tiers[key] = fallback_tiers[key]

	if have_star:
		star_pos = _fit_layout_to_home_half(star_pos, tiers)

	return {"star": star_pos, "tiers": tiers}


func _first_marker_in(node: Node) -> Marker2D:
	for child in node.get_children():
		var m := child as Marker2D
		if m != null:
			return m
		var deeper := _first_marker_in(child)
		if deeper != null:
			return deeper
	return null


func _all_markers_in(node: Node) -> Array[Marker2D]:
	var out: Array[Marker2D] = []
	for child in node.get_children():
		var m := child as Marker2D
		if m != null:
			out.append(m)
		else:
			out.append_array(_all_markers_in(child))
	return out


## The authored formations spread their markers across the WHOLE pitch, so once
## the enemy side was mirrored the two teams overlapped and half the units sat
## off screen. This keeps the shape you drew but squeezes it into your own half
## of whatever is actually visible.
func _fit_layout_to_home_half(star_pos: Vector2, tiers: Dictionary) -> Vector2:
	var points: Array[Vector2] = [star_pos]
	for key in tiers.keys():
		for p in (tiers[key] as Array):
			points.append(p)
	if points.size() < 2:
		return star_pos

	var src := Rect2(points[0], Vector2.ZERO)
	for p in points:
		src = src.expand(p)
	if src.size.x < 1.0 or src.size.y < 1.0:
		return star_pos

	var play := get_play_rect()
	var dst := Rect2(play.position, Vector2(play.size.x * 0.46, play.size.y))

	for key in tiers.keys():
		var moved: Array[Vector2] = []
		for p in (tiers[key] as Array):
			moved.append(_remap_point(p, src, dst))
		tiers[key] = moved

	return _remap_point(star_pos, src, dst)


func _remap_point(p: Vector2, src: Rect2, dst: Rect2) -> Vector2:
	return Vector2(
		dst.position.x + ((p.x - src.position.x) / src.size.x) * dst.size.x,
		dst.position.y + ((p.y - src.position.y) / src.size.y) * dst.size.y)


# A 3-3-3 grid derived from the pitch, authored for the HOME (left) side.
func default_layout(star_tier: String) -> Dictionary:
	var rect := get_play_rect()

	# Columns march from your own goal out toward the halfway line.
	# Fractions are of the VISIBLE play area, so the shape holds at any
	# window size or camera zoom.
	var col_x: Dictionary = {
		"I":   rect.position.x + rect.size.x * 0.08,
		"II":  rect.position.x + rect.size.x * 0.21,
		"III": rect.position.x + rect.size.x * 0.33,
		"IV":  rect.position.x + rect.size.x * 0.44,
	}
	var rows: Array[float] = [
		rect.position.y + rect.size.y * 0.18,
		rect.position.y + rect.size.y * 0.50,
		rect.position.y + rect.size.y * 0.82,
	]

	var tiers: Dictionary = {}
	for key in ALL_TIERS:
		if key == star_tier:
			continue
		var x: float = col_x[key]
		var arr: Array[Vector2] = []
		for y in rows:
			arr.append(Vector2(x, y))
		tiers[key] = arr

	var star_x: float = col_x.get(star_tier, rect.position.x + rect.size.x * 0.33)
	return {
		"star": Vector2(star_x, rect.position.y + rect.size.y * 0.50),
		"tiers": tiers,
	}


func create_unit_instance(data: PlayerData, pos: Vector2, is_enemy: bool) -> PlayerUnit:
	var unit := PLAYER_UNIT_SCENE.instantiate() as PlayerUnit
	if unit == null:
		push_error("player_unit.tscn did not instantiate as a PlayerUnit.")
		return null
	unit.is_enemy = is_enemy
	unit.data = data
	unit.ball = ball
	unit.play_bounds = get_play_rect()
	unit.attack_dir = -1.0 if is_enemy else 1.0   # home defends the left goal
	_tune_unit(unit)
	units_container.add_child(unit)   # add first so @onready refs exist
	unit.set_home(pos)                # then place and start roaming
	return unit


func spawn_goalies() -> void:
	var home_marker := find_child("HomeGoaliePos", true, false) as Marker2D
	var away_marker := find_child("AwayGoaliePos", true, false) as Marker2D

	var home_pos: Vector2
	var away_pos: Vector2
	if home_marker != null and away_marker != null:
		home_pos = home_marker.global_position
		away_pos = away_marker.global_position
	else:
		# Optional markers. Add Marker2Ds named HomeGoaliePos / AwayGoaliePos
		# to main_scene.tscn to place the keepers by hand.
		print("[goalies] No HomeGoaliePos / AwayGoaliePos markers — using pitch bounds.")
		var rect := get_play_rect()
		home_pos = Vector2(rect.position.x, rect.get_center().y)
		away_pos = Vector2(rect.end.x, rect.get_center().y)

	var player_goalie := GOALIE_SCENE.instantiate() as GoalieUnit
	player_goalie.is_enemy = false
	units_container.add_child(player_goalie)
	player_goalie.global_position = home_pos
	player_goalie.goal_conceded.connect(_on_goal_conceded.bind(false))
	goalies[false] = player_goalie

	var enemy_goalie := GOALIE_SCENE.instantiate() as GoalieUnit
	enemy_goalie.is_enemy = true
	units_container.add_child(enemy_goalie)
	enemy_goalie.global_position = away_pos
	var enemy_art := enemy_goalie.get_node_or_null("Artwork") as Sprite2D
	if enemy_art:
		enemy_art.flip_h = true
	enemy_goalie.goal_conceded.connect(_on_goal_conceded.bind(true))
	goalies[true] = enemy_goalie

	_tune_goalie(player_goalie)
	_tune_goalie(enemy_goalie)


func _assign_goalie_data() -> void:
	if active_player_star:
		var d := _load_goalie_for_team(active_player_star.unit_type)
		if d and goalies.has(false):
			goalies[false].setup(d)
	if active_enemy_star:
		var d2 := _load_goalie_for_team(active_enemy_star.unit_type)
		if d2 and goalies.has(true):
			goalies[true].setup(d2)


func _load_goalie_for_team(team: String) -> GoalieData:
	var keeper := db.goalie_for_team(team)
	if keeper == null:
		print("[goalies] No row for '%s' in Goalies.csv — using default stamina." % team)
	return keeper


func _on_goal_conceded(conceded_by_enemy: bool) -> void:
	# No print here — finish_round() announces the goal AFTER the shot line,
	# otherwise the log reads "GOAL!" before the shot that caused it.
	if conceded_by_enemy:
		player_score += 1
	else:
		enemy_score += 1


# =============================================================
#  PITCH GEOMETRY
# =============================================================

func spawn_ball() -> void:
	ball = Ball.new()
	ball.name = "Ball"
	ball.units_provider = Callable(self, "_all_units")
	units_container.add_child(ball)
	ball.global_position = get_play_rect().get_center()
	_tune_ball()


func spawn_rps() -> void:
	rps = RPS_SCENE.instantiate() as RpsClash
	if rps == null:
		push_error("rps_clash.tscn did not instantiate as an RpsClash — check the scene's root node type.")
		return
	rps.name = "RpsClash"
	add_child(rps)
	_tune_rps()


## Run the clash and return true if YOUR side attacks in the Tier I duel.
func run_rps_clash() -> bool:
	if rps == null or not use_rps_minigame:
		return randi() % 2 == 0
	rps.start()
	var result: Variant = await rps.clash_finished
	return bool(result)


## Everyone stops running and passing — used while a substitution plays out,
## and for the whole of a PLAY MAKER so the pitch holds still during picks.
func freeze_play(value: bool) -> void:
	_freeze_depth = maxi(0, _freeze_depth + (1 if value else -1))
	var frozen := _freeze_depth > 0
	if ball != null:
		ball.set_frozen(frozen)
	for unit in _all_units():
		unit.movement_frozen = frozen


## Hand the ball to the side that won rock/paper/scissors.
## rps_clash.tscn will call this; the headless path below calls it too.
func give_ball_to(side_is_enemy: bool) -> void:
	if ball == null:
		return

	var picked: Array[PlayerUnit] = []
	var any: Array[PlayerUnit] = []
	for unit in _all_units():
		if unit.is_enemy != side_is_enemy:
			continue
		any.append(unit)
		if unit.is_playmaker:
			picked.append(unit)

	var pool := picked if not picked.is_empty() else any
	if pool.is_empty():
		return
	ball.give_to(pool.pick_random())


## Give the ball to one side's unit in a specific tier — used after the clash so
## the ATTACKER's Tier I pick (the first card locked in) starts on the ball.
func give_ball_to_tier(side_is_enemy: bool, tier_key: String) -> void:
	if ball == null:
		return
	for unit in _all_units():
		if unit.is_enemy != side_is_enemy or unit.data == null:
			continue
		if unit.data.get_tier_clean() != tier_key:
			continue
		if unit.is_playmaker or unit.is_star_player:
			ball.give_to(unit)
			return
	give_ball_to(side_is_enemy)   # fall back to anyone on that side


## Mirror the enemy about the centre of the VISIBLE play area, not the centre of
## the field texture — those differ whenever the sprite overhangs the window,
## and the mismatch pushed the enemy team off-centre.
func get_pitch_center_x() -> float:
	return get_play_rect().get_center().x


## What the camera can actually see, in world coordinates.
func get_visible_world_rect() -> Rect2:
	var vp := get_viewport()
	if vp == null:
		return get_viewport_rect()
	var ct := vp.get_canvas_transform()
	var zoom := ct.get_scale()
	if is_zero_approx(zoom.x) or is_zero_approx(zoom.y):
		return get_viewport_rect()
	return Rect2(-ct.origin / zoom, vp.get_visible_rect().size / zoom)


## Where units are allowed to be: the visible screen, clipped to the pitch when
## the pitch is the smaller of the two, then inset so nobody hugs a touchline.
## Formations were overflowing because they used the raw texture rect, which is
## far larger than the window when the field sprite is not scaled to fit.
func get_play_rect() -> Rect2:
	var area := get_visible_world_rect()
	var pitch := get_pitch_rect()
	if pitch.size.x > 1.0 and pitch.size.y > 1.0:
		var clipped := area.intersection(pitch)
		if clipped.size.x > 1.0 and clipped.size.y > 1.0:
			area = clipped
	return area.grow_individual(
		-area.size.x * 0.06, -area.size.y * 0.10,
		-area.size.x * 0.06, -area.size.y * 0.10)


func get_pitch_rect() -> Rect2:
	if field_sprite != null and field_sprite.texture != null:
		var size := field_sprite.texture.get_size() * field_sprite.global_scale
		var origin := field_sprite.global_position
		if field_sprite.centered:
			origin -= size / 2.0
		return Rect2(origin, size)
	return get_viewport_rect()


func mirror_if_enemy(original_pos: Vector2, center_x: float, is_enemy: bool) -> Vector2:
	if not is_enemy:
		return original_pos
	return Vector2((2.0 * center_x) - original_pos.x, original_pos.y)


# =============================================================
#  DATA LOADING
# =============================================================

# Everything comes from the CSVs via CardDatabase. There are no .tres card
# files to keep in sync any more — data/players/ and data/goalies/ can be
# deleted. Drop a CSV in res://data/ and it is in the next match.

func load_roster_by_type(unit_type: String) -> Array[PlayerData]:
	return db.roster_for_class(unit_type)


func _stars_grouped_by_class() -> Dictionary:
	return db.stars_by_class()


func get_star_bundle_by_type(unit_type: String) -> Array[PlayerData]:
	return db.stars_for_class(unit_type)


## Kickoff choices: one Star from each of three DIFFERENT classes, so the
## pick genuinely chooses your team. (The old version shuffled the whole
## star pool and could hand you three cards from the same class.)
func get_star_player_choices() -> Array[PlayerData]:
	var by_class := _stars_grouped_by_class()
	var class_names: Array = by_class.keys()
	class_names.shuffle()

	# One Star per class first, so once you have 3+ classes the kickoff offers
	# three DIFFERENT classes. Everything else goes in the reserve pile.
	var choices: Array[PlayerData] = []
	var reserve: Array[PlayerData] = []
	for key in class_names:
		var bundle: Array[PlayerData] = by_class[key]
		if bundle.is_empty():
			continue
		bundle.shuffle()
		choices.append(bundle[0])
		for i in range(1, bundle.size()):
			reserve.append(bundle[i])

	if choices.is_empty():
		push_error("No Star Players found. Check that a CSV in res://data/ has rows with Player Type = Star.")
		return choices

	# With fewer than 3 classes imported, top the kickoff up from the reserve
	# so you always get three cards. Picking any of them still fixes your
	# class, your Star's Tier and therefore your formation.
	reserve.shuffle()
	while choices.size() < 3 and not reserve.is_empty():
		choices.append(reserve.pop_back())

	choices.shuffle()
	while choices.size() > 3:
		choices.pop_back()
	return choices


func filter_units_by_tier(roster: Array[PlayerData], tier_key: String) -> Array[PlayerData]:
	var matching: Array[PlayerData] = []
	for p in roster:
		if p.get_tier_clean() == tier_key.to_upper():
			matching.append(p)
	return matching


func _all_units() -> Array[PlayerUnit]:
	var out: Array[PlayerUnit] = []
	for child in units_container.get_children():
		if child is PlayerUnit:
			out.append(child)
	return out


# =============================================================
#  EVENT TRIGGERS
# =============================================================

func trigger_playmaker_event() -> void:
	current_state = MatchState.DRAFTING
	rounds_this_cycle += 1
	round_player_picks.clear()
	round_enemy_picks.clear()
	round_in_progress = true

	for unit in _all_units():
		unit.clear_round_flags()

	# The pitch holds still from the whistle until the last card is locked in.
	freeze_play(true)

	print("PLAY MAKER!  Cycle %d, Round %d" % [current_cycle, rounds_this_cycle])
	await announce("PLAY MAKER!")

	# Rock/paper/scissors decides who attacks in Tier I, BEFORE the draft.
	player_attacks_this_round = await run_rps_clash()
	print("  Clash: %s attacks." % ("You" if player_attacks_this_round else "Enemy"))

	draft_phases.assign(ALL_TIERS)
	current_phase_index = 0
	start_next_draft_phase()


func trigger_hold_up_event() -> void:
	current_state = MatchState.DRAFTING
	current_cycle += 1
	rounds_this_cycle = 0
	round_in_progress = false
	round_player_picks.clear()
	round_enemy_picks.clear()

	abilities.begin_cycle()
	for unit in _all_units():
		unit.reset_for_new_cycle()

	# Enemy rotates its own Star at the same time.
	if not available_enemy_stars.is_empty():
		var new_enemy_star: PlayerData = available_enemy_stars.pick_random()
		available_enemy_stars.erase(new_enemy_star)
		_swap_star_on_pitch(new_enemy_star, true)
		active_enemy_star = new_enemy_star
		enemy_star_tier = new_enemy_star.get_tier_clean()

	print("HOLD UP!  Starting cycle %d" % current_cycle)
	await announce("HOLD UP!")

	draft_phases.assign(["StarChoice"])
	current_phase_index = 0
	start_next_draft_phase()


func announce(text: String, seconds: float = 2.0) -> void:
	event_announcement.text = text
	event_announcement.show()
	await get_tree().create_timer(seconds).timeout
	event_announcement.hide()


# =============================================================
#  DRAFTING
# =============================================================

func start_next_draft_phase() -> void:
	for child in card_container.get_children():
		child.queue_free()

	if current_phase_index >= draft_phases.size():
		_on_draft_complete()
		return

	var phase := draft_phases[current_phase_index]

	if phase == "Star":
		for star_data in get_star_player_choices():
			create_card_for_unit(star_data)
		return

	if phase == "StarChoice":
		if available_player_stars.is_empty():
			# No stars left (this shouldn't fire — cycle 3 has no HOLD UP).
			current_phase_index += 1
			start_next_draft_phase()
			return
		for star_data in available_player_stars:
			create_card_for_unit(star_data)
		return

	# --- Regular tier phase ---
	# Your Star already fills its own tier, so there is nothing to pick there.
	if phase == player_star_tier:
		_enemy_pick_for_tier(phase)
		current_phase_index += 1
		start_next_draft_phase()
		return

	var choices_found := 0
	for unit in _all_units():
		if unit.is_enemy or unit.is_star_player or unit.is_exhausted:
			continue
		if unit.data != null and unit.data.get_tier_clean() == phase:
			create_card_for_unit(unit.data)
			choices_found += 1

	if choices_found == 0:
		print("[draft] No available Tier %s cards — skipping this phase." % phase)
		_enemy_pick_for_tier(phase)
		current_phase_index += 1
		start_next_draft_phase()


func create_card_for_unit(data: PlayerData) -> void:
	var card := PLAYER_CARD_SCENE.instantiate() as PlayerCardUI
	card_container.add_child(card)
	card.setup_card(data)
	card.card_hovered.connect(_on_card_hovered)
	card.card_unhovered.connect(_on_card_unhovered)
	card.card_selected.connect(_on_card_selected)


func _on_card_hovered(data: PlayerData) -> void:
	for unit in _all_units():
		if not unit.is_enemy and unit.data == data:
			unit.set_highlight(true)


func _on_card_unhovered(data: PlayerData) -> void:
	for unit in _all_units():
		if not unit.is_enemy and unit.data == data:
			unit.set_highlight(false)   # stays bright if is_playmaker


func _on_card_selected(selected_data: PlayerData) -> void:
	var phase := draft_phases[current_phase_index]
	print("Locked in: %s (%s)" % [selected_data.player_name, phase])

	match phase:
		"Star":
			_resolve_kickoff_star(selected_data)
		"StarChoice":
			_resolve_star_rotation(selected_data)
		_:
			_resolve_tier_pick(phase, selected_data)

	current_phase_index += 1
	start_next_draft_phase()


func _resolve_star_rotation(chosen: PlayerData) -> void:
	_swap_star_on_pitch(chosen, false)
	active_player_star = chosen
	player_star_tier = chosen.get_tier_clean()
	available_player_stars.erase(chosen)
	print("New active Star: %s (Tier %s)" % [chosen.player_name, player_star_tier])


## HOLD UP! substitution. Play stops, the outgoing Star jogs off the nearest
## touchline, the incoming Star jogs on into the same slot, then play resumes.
func _swap_star_on_pitch(new_star: PlayerData, is_enemy: bool) -> void:
	var star_unit: PlayerUnit = null
	for unit in _all_units():
		if unit.is_enemy == is_enemy and unit.is_star_player:
			star_unit = unit
			break

	if star_unit == null:
		push_warning("Could not find a star unit on the pitch to swap (is_enemy=%s)." % is_enemy)
		return

	var slot := star_unit.home_position
	var rect := get_play_rect()

	# Leave by whichever touchline is closer.
	var exit_y: float = rect.position.y - 90.0
	if star_unit.global_position.y > rect.get_center().y:
		exit_y = rect.end.y + 90.0
	var wing := Vector2(slot.x, exit_y)

	freeze_play(true)

	# If the outgoing Star was on the ball, drop it before they leave.
	if ball != null and ball.is_carried_by(star_unit):
		ball.carrier = null

	await star_unit.run_to(wing, 0.65)

	# Same pitch object, new card — swap it while it is off screen.
	star_unit.update_unit_data(new_star)
	star_unit.global_position = wing
	star_unit.is_playmaker = true
	star_unit.set_highlight(true)

	await star_unit.run_to(slot, 0.65)
	star_unit.set_home(slot)

	freeze_play(false)


func _resolve_tier_pick(tier_key: String, selected_data: PlayerData) -> void:
	# --- Your pick ---
	for unit in _all_units():
		if unit.is_enemy or unit.is_star_player:
			continue
		if unit.data == selected_data:
			unit.is_exhausted = true
			unit.is_playmaker = true
			unit.set_highlight(true)
		elif unit.data != null and unit.data.get_tier_clean() == tier_key:
			unit.set_highlight(false)
	round_player_picks.append(selected_data)

	# --- Enemy pick (ONCE — the old code ran this block twice) ---
	_enemy_pick_for_tier(tier_key)


func _enemy_pick_for_tier(tier_key: String) -> void:
	# The enemy's Star fills its own tier, so no draft there.
	if tier_key == enemy_star_tier:
		return

	var choices: Array[PlayerUnit] = []
	for unit in _all_units():
		if not unit.is_enemy or unit.is_star_player or unit.is_exhausted:
			continue
		if unit.data != null and unit.data.get_tier_clean() == tier_key:
			choices.append(unit)

	if choices.is_empty():
		return

	var chosen: PlayerUnit = choices.pick_random()
	for unit in choices:
		if unit == chosen:
			unit.is_exhausted = true
			unit.is_playmaker = true
			unit.set_highlight(true)
		else:
			unit.set_highlight(false)
	round_enemy_picks.append(chosen.data)


func _on_draft_complete() -> void:
	# Kickoff / HOLD UP! drafts have no combat — just restart the clock.
	if not round_in_progress:
		current_state = MatchState.PLAYING
		print("Draft complete — clock running.")
		return

	round_in_progress = false
	resolve_round()


# =============================================================
#  ROUND RESOLUTION
#
#  Combat order is Tier I -> II -> III -> IV. Your Star fights in its own
#  tier's slot. Rock/paper/scissors decides who attacks in Tier I; after
#  that the winner of each duel attacks in the next one.
#
#  For each duel you WIN you bank (your power + the beaten enemy's power).
#  Whoever holds the ball after Tier IV shoots at the opposing goalie.
#
#  While `headless_combat` is true this runs instantly in code.
#  Once combat_arena.tscn exists, flip it off and drive it from the signal.
# =============================================================

func build_lineup(picks: Array[PlayerData], star: PlayerData, star_tier: String) -> Array[PlayerData]:
	var lineup: Array[PlayerData] = []
	for t in ALL_TIERS:
		if t == star_tier and star != null:
			lineup.append(star)
			continue
		var found: PlayerData = null
		for p in picks:
			if p.get_tier_clean() == t:
				found = p
				break
		lineup.append(found)
	return lineup


func resolve_round() -> void:
	current_state = MatchState.AUTOBATTLE

	# Picks are in — the attacker's Tier I card collects the ball and play resumes.
	var player_has_ball := player_attacks_this_round
	give_ball_to_tier(not player_has_ball, "I")
	freeze_play(false)

	var player_lineup := build_lineup(round_player_picks, active_player_star, player_star_tier)
	var enemy_lineup := build_lineup(round_enemy_picks, active_enemy_star, enemy_star_tier)

	round_ready_for_combat.emit(player_lineup, enemy_lineup)

	if not headless_combat:
		return   # combat_arena.tscn takes over and calls finish_round() when done

	print("  %s attacks first." % ("You" if player_has_ball else "Enemy"))

	abilities.begin_round()
	abilities.apply_passives(player_lineup, enemy_lineup)

	var player_bank := 0
	var enemy_bank := 0

	for i in ALL_TIERS.size():
		var mine: PlayerData = player_lineup[i]
		var theirs: PlayerData = enemy_lineup[i]
		if mine == null or theirs == null:
			print("  Tier %s: no contest (missing card)." % ALL_TIERS[i])
			continue

		abilities.begin_duel()

		var attacker_is_enemy := not player_has_ball
		var atk: PlayerData = mine if player_has_ball else theirs
		var def: PlayerData = theirs if player_has_ball else mine

		# Abilities go on the stack first: lowest priority resolves first,
		# attacker breaks a tie. Only then are the numbers compared.
		abilities.resolve_duel_abilities(atk, attacker_is_enemy, def)

		var atk_power := abilities.attack_power(atk, attacker_is_enemy)
		var def_power := abilities.defense_power(def, not attacker_is_enemy)

		var attacker_wins := atk_power > def_power
		if atk_power == def_power:
			attacker_wins = ties_go_to_attacker

		if attacker_wins:
			abilities.resolve_duel_outcome(atk, attacker_is_enemy, def, not attacker_is_enemy)
		else:
			abilities.resolve_duel_outcome(def, not attacker_is_enemy, atk, attacker_is_enemy)

		var banked := atk_power + def_power
		if attacker_wins:
			if player_has_ball:
				player_bank += banked
			else:
				enemy_bank += banked
		else:
			if player_has_ball:
				enemy_bank += banked
			else:
				player_bank += banked
			player_has_ball = not player_has_ball   # possession flips

		print("  Tier %s: %s (%d atk) vs %s (%d def) -> %s" % [
			ALL_TIERS[i], atk.player_name, atk_power,
			def.player_name, def_power,
			"attacker holds" if attacker_wins else "TURNOVER"])

		for line in abilities.log_lines:
			print(line)
		abilities.log_lines.clear()

		# Whoever holds the ball after this tier is the current shooter.
		round_shooter_card = mine if player_has_ball else theirs

	# Goalie stamina changes queued by abilities land before the shot.
	for change in abilities.take_pending_stamina():
		var keeper: GoalieUnit = goalies.get(bool(change["enemy_side"]))
		if keeper != null:
			keeper.adjust_stamina(int(change["delta"]))

	var bank := player_bank if player_has_ball else enemy_bank
	bank += abilities.shot_bonus(not player_has_ball)

	await finish_round(player_has_ball, bank)


## Called by combat_arena.tscn (or by the headless path above).
##
## The shot is played out ON THE PITCH: the unit that won the last duel is
## given the ball, steps toward goal, and strikes it. The keeper's roll is
## made BEFORE the ball is animated, so the ball visibly stops at a save and
## visibly crosses the line for a goal — the picture never lies about the result.
func finish_round(shooter_is_player: bool, shot_power: int) -> void:
	var target_key := true if shooter_is_player else false   # the OTHER goalie
	var keeper: GoalieUnit = goalies.get(target_key)

	if keeper == null or shot_power <= 0:
		print("  No shot taken this round.")
		round_resolved.emit(player_score, enemy_score)
		current_state = MatchState.PLAYING
		return

	var shooter := _find_shooter(shooter_is_player)

	# --- 1. The ball reaches the shooter ---
	if shooter != null and ball != null:
		ball.give_to(shooter)
		var toward_goal := shooter.global_position.lerp(keeper.global_position, 0.25)
		await shooter.run_to(toward_goal, db.tune_float("shot_run_up_seconds", 0.45))

	# --- 2. Decide the outcome, then show it ---
	var scored := keeper.take_shot(shot_power)

	print("  SHOT: %s (%s) fires %d power -> %s (keeper stamina now %d)" % [
		"You" if shooter_is_player else "Enemy",
		shooter.data.player_name if shooter != null and shooter.data != null else "unknown",
		shot_power, "GOAL" if scored else "saved", keeper.current_stamina])
	if scored:
		print("  GOAL!  %d - %d" % [player_score, enemy_score])

	# --- 3. Strike it ---
	if ball != null:
		var goal_line := _goal_mouth(target_key)
		ball.shoot(keeper.global_position if not scored else goal_line)
		await ball.shot_arrived

		if scored:
			# Restart from the centre. The side that CONCEDED kicks off, and
			# target_key is exactly that side (it owns the beaten keeper).
			await get_tree().create_timer(0.6).timeout
			ball.global_position = get_play_rect().get_center()
			give_ball_to(target_key)
		else:
			# The keeper gathers it and plays it out to their own side.
			give_ball_to(target_key)

	round_resolved.emit(player_score, enemy_score)
	current_state = MatchState.PLAYING


## The on-pitch unit holding the ball at the end of the duel chain.
func _find_shooter(shooter_is_player: bool) -> PlayerUnit:
	var side_is_enemy := not shooter_is_player

	if round_shooter_card != null:
		for unit in _all_units():
			if unit.is_enemy == side_is_enemy and unit.data == round_shooter_card:
				return unit

	# Fall back to whoever on that side is nearest the goal they attack.
	var best: PlayerUnit = null
	var best_x := -INF
	for unit in _all_units():
		if unit.is_enemy != side_is_enemy:
			continue
		var reach := unit.global_position.x * (-1.0 if side_is_enemy else 1.0)
		if reach > best_x:
			best_x = reach
			best = unit
	return best


## A point just past the keeper, on the goal line.
func _goal_mouth(keeper_is_enemy: bool) -> Vector2:
	var rect := get_play_rect()
	var keeper: GoalieUnit = goalies.get(keeper_is_enemy)
	var y := keeper.global_position.y if keeper != null else rect.get_center().y
	var x := rect.end.x + 40.0 if keeper_is_enemy else rect.position.x - 40.0
	return Vector2(x, y)
