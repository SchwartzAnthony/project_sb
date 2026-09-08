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
## One HOLD UP! Star substitution has finished jogging on.
signal substitution_finished

# --- Scene wiring -------------------------------------------
@onready var selection_ui: CanvasLayer = $SelectionUI
@onready var card_container: HBoxContainer = $SelectionUI/CardContainer
@onready var start_draft_button: Button = $SelectionUI/StartDraftButton
@onready var timer_label: Label = $SelectionUI/TimerLabel
@onready var event_announcement: Label = $SelectionUI/EventAnnouncement

## Built in code, so main_scene.tscn needs no editing.
var score_label: Label

@export var field_sprite: Sprite2D

const PLAYER_CARD_SCENE: PackedScene = preload("res://src/ui/player_card_ui.tscn")
const PLAYER_UNIT_SCENE: PackedScene = preload("res://src/units/player_unit.tscn")
const GOALIE_SCENE: PackedScene = preload("res://src/units/goalie_unit.tscn")
const RPS_SCENE: PackedScene = preload("res://src/ui/rps_clash.tscn")
const DUEL_ARENA_SCENE: PackedScene = preload("res://src/ui/duel_arena.tscn")
const SHOOTOUT_SCENE: PackedScene = preload("res://src/ui/shootout_view.tscn")

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
var duel_arena: DuelArena = null
var shootout: ShootoutView = null
## Everything the game knows, read from res://data/*.csv at startup.
var db: CardDatabase
var abilities: AbilityEngine
## What the story remembers: flags, counters, unlocks. Shared with the
## dialogue screen and the base, and saved between runs.
var state: GameState
## Stats.csv — turns match events into counters.
var stats: StatsRules
## Progression.csv — decides when things happen.
var steps: Progression

## The fixture list. Which team you are playing, and how hard they are.
var season: SeasonDB
## The row of Season.csv being played right now. Empty = a friendly, which is
## what you get once the season is over or if Season.csv is missing.
var current_fixture: Dictionary = {}
## Set from the fixture's Class column. Blank = pick an opponent at random,
## exactly as the game did before there was a season.
var forced_enemy_class: String = ""

## True when this is a rerun from the stats screen: same opposition, but the
## result is not written into the season table.
var replaying: bool = false

## The photograph of your progress taken at kick-off. Compared against the
## state at full time to work out what you gained, with no help from anything
## else. See match_report.gd.
var gains: MatchReport = null

## The view that follows the ball. Null when camera_enabled is false in
## Tuning.csv, and everything below copes with that.
var camera: MatchCamera = null

## The little strip of speed buttons and the AUTO toggle, top-left.
var hud: MatchHUD = null

## The stats window that appears while the mouse is over a card.
var card_stats: CardStatsPanel = null

## Every card currently on offer in the draft. Kept so that AUTO can pick one
## without having to reach inside the card widgets.
var offered_cards: Array[PlayerData] = []
## Who won the rock/paper/scissors clash and chose to attack this round.
var player_attacks_this_round: bool = true
## The card holding the ball when the duel chain ended — it takes the shot.
var round_shooter_card: PlayerData = null
## Substitutions can nest (enemy rotates its Star at the same moment you do),
## so freezing is reference-counted rather than a plain bool.
var _freeze_depth: int = 0
## True while a draft that stopped the pitch is still open, so the matching
## thaw fires exactly once. Counting alone was not enough: the kickoff draft
## never freezes, and an unmatched thaw there would leave the next HOLD UP!
## one short.
var _draft_froze_play: bool = false
## Star substitutions currently jogging on or off, both sides counted.
var _substitutions_running: int = 0
## Set while a team is being spawned, so both sides are laid out against one
## identical play area. See get_play_rect().
var _geometry_locked: bool = false
var _locked_play_rect: Rect2 = Rect2()

# --- Zones and off-ball movement (all overridable from Tuning.csv) ---
## The pitch cut into four quarters, one per Tier. Built when the teams spawn.
var zones: PitchZones = null
## false lays the teams out the old way — both squads inside their own half,
## no quarters, no marking. Handy for comparing the two.
var zones_enabled: bool = true
## Press radius as a fraction of pitch HEIGHT. A defender inside this of where
## the ball is going will charge it.
var press_radius_fraction: float = 0.55
## Extra defenders from OTHER quarters allowed to join the press.
var press_helpers: int = 2
var press_speed: float = 92.0
## How far goal-side of his man a marker stands.
var mark_distance: float = 54.0
## How far an attacker breaks off its marker to show for the ball.
var open_spread: float = 230.0
## The faint Tier colouring painted on the grass.
var zone_overlay: ZoneOverlay = null

# --- The corridor ---
## Which quarters the ball may roam during ordinary waiting play, counted 1-4
## from your goal. The default 2..3 fences it out of both Tier IV territories.
## Set to 1 and 4 to let it go anywhere, as it used to.
var ball_roam_quarter_first: int = 2
var ball_roam_quarter_last: int = 3

# --- The break ---
## Which side is currently surging at goal: -1 nobody, 0 you, 1 them. Set for
## the few seconds between the last duel and the shot.
var attack_surge_side: int = -1
## How much of the remaining distance to goal a surging unit closes.
## 0 = nobody moves, 1 = everyone piles onto the goal line.
var surge_advance: float = 0.45
## How much a surging unit converges on the goal mouth. 1 = everyone funnels
## into the middle, 0 = they keep their lane and just run forward.
var surge_centring: float = 0.35
## Free-running seconds, used only for idle drift. Unlike the match clock this
## keeps ticking while play is stopped.
var _anim_clock: float = 0.0

# Team state
## Tier -> the three regulars picked in the team builder. Empty means
## "nobody chose", and spawn_team falls back to a random roster.
var chosen_regulars: Dictionary = {}
## The classes offered at kickoff. The enemy avoids these, so a Star you were
## shown and turned down does not walk back on wearing the other shirt.
var _offered_star_classes: Array[String] = []

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
	state = GameState.fetch(get_tree())
	stats = StatsRules.get_rules()
	steps = Progression.get_rules()
	season = SeasonDB.get_db()

	# Taken FIRST, before a single thing has changed, so that everything the
	# match gives you — including anything a Progression row does at kick-off —
	# turns up on the "what you gained" panel afterwards.
	gains = MatchReport.snapshot(state)

	# Talents raise Tuning.csv numbers. This has to happen BEFORE the tuning
	# is read, or the match would use the un-boosted values.
	db.apply_bonuses_from(state)

	# Lay the brews on before anything reads a card. This clears the previous
	# match's overlays first, so a one-match brew really does last one match.
	BrewDB.get_db().apply_all(db, state)

	_apply_match_tuning()
	_apply_fixture()

	# Added BEFORE units_container on purpose. Everything here sits at z_index
	# 0, so it is tree order that puts the tint over the grass and under the
	# players.
	zone_overlay = ZoneOverlay.new()
	zone_overlay.name = "ZoneOverlay"
	add_child(zone_overlay)

	units_container = Node2D.new()
	units_container.name = "UnitsContainer"
	add_child(units_container)

	spawn_goalies()
	spawn_ball()
	spawn_rps()
	spawn_cutaways()
	spawn_scoreboard()
	build_event_schedule()

	spawn_hud()
	spawn_card_stats()

	event_announcement.hide()
	timer_label.text = "00:00"
	start_draft_button.show()
	start_draft_button.pressed.connect(_on_start_draft_pressed)

	# Came from the team builder? Then the Star is already chosen — blow the
	# whistle instead of asking again. One frame's wait lets the window finish
	# sizing, so the formation lands inside the visible pitch.
	if TeamSelection.fetch(get_tree()) != null:
		start_draft_button.hide()
		await get_tree().process_frame
		_on_start_draft_pressed()


func _process(delta: float) -> void:
	# Before the early return: the camera has to keep easing back out to the
	# wide view during the draft and at full time, which are exactly the
	# moments this function used to stop doing anything.
	_drive_camera()

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
#  REPORTING WHAT HAPPENED
#
#  The match does not know or care what is being counted. It just says
#  "a goal was scored, here are the facts about it" and Stats.csv decides
#  which counters that feeds. Add a row there, get a new tracked stat —
#  no change in here.
# =============================================================

## The facts that travel with a goal or a duel.
func _facts_for(unit: PlayerUnit) -> Dictionary:
	var facts: Dictionary = {}
	if active_player_star != null:
		facts["class"] = active_player_star.unit_type
	if unit == null:
		return facts

	if unit.data != null:
		facts["card"] = unit.data.player_name
		facts["tier"] = unit.data.get_tier_clean()
		if facts.get("class", "") == "":
			facts["class"] = unit.data.unit_type
	facts["star"] = "yes" if unit.is_star_player else "no"
	if unit.active_brew.strip_edges() != "":
		facts["brew"] = unit.active_brew
	return facts


func _report(event: String, facts: Dictionary) -> void:
	if stats != null and state != null:
		stats.record(event, facts, state)


## Run the Progression rows listening for this moment, then carry out
## anything they asked for that needs the scene tree.
## Returns true if a row took the screen over — played a story scene or sent
## you somewhere else — so the caller knows not to change scene as well.
## `return_to` is where a story scene comes back to when it finishes.
func _advance_progression(trigger: String, return_to: String = "") -> bool:
	if steps == null or state == null:
		return false
	var comes_back := return_to if return_to != "" else ScenePaths.MATCH
	for action in steps.fire(trigger, state):
		var kind := String(action["kind"])
		var value := String(action["value"])
		match kind:
			"announce":
				print("[progression] %s" % value)
				await announce(value, db.tune_float("progression_announce_seconds", 1.6))
			"story":
				state.save_to_disk()
				DialogueView.play(get_tree(), value, comes_back)
				return true
			"goto":
				state.save_to_disk()
				ScenePaths.go_to(get_tree(), ScenePaths.for_name(value))
				return true
	state.save_to_disk()
	return false


# =============================================================
#  OFF-BALL MOVEMENT
#
#  Every unit's ROLE is decided here, once per physics frame, and written
#  onto the unit. player_unit.gd then does nothing but drive toward it.
#
#  It has to be central. A single unit cannot see how many of its team-mates
#  have already broken toward the ball, so left to themselves either all ten
#  charge or none do. From up here "the three in that quarter press, two more
#  come across, everyone else stays with their man" is four lines of code.
# =============================================================

func _physics_process(delta: float) -> void:
	if current_state == MatchState.PRE_MATCH or current_state == MatchState.FULL_TIME:
		return
	# Its own clock, not the match clock: the match clock stops during a PLAY
	# MAKER and the idle drift would freeze with it, which is the exact thing
	# we are trying to get rid of.
	_anim_clock += delta

	# The quarters brighten while you are choosing and fade back once play
	# restarts — loud exactly when they are useful.
	if zone_overlay != null:
		zone_overlay.set_focused(current_state == MatchState.DRAFTING)

	# The ball is fenced into midfield for all of the waiting play and freed
	# the moment a PLAY MAKER starts resolving. See _ball_corridor().
	if ball != null:
		ball.set_corridor(_ball_corridor(), current_state == MatchState.PLAYING)

	_assign_roles()


func _assign_roles() -> void:
	if ball == null or zones == null:
		return
	var units := _all_units()
	if units.is_empty():
		return

	# -1 loose, 0 you, 1 them. Answered even mid-pass, so nobody stands about
	# doing nothing for the whole of every ball in the air.
	var side := ball.side_on_ball()
	var receiver := ball.intended_receiver()
	# Defenders converge on where the ball is GOING, not where it is, so they
	# arrive with it rather than trailing it.
	var focus := ball.arrival_point()
	var reach := zones.play.size.y * press_radius_fraction

	var pressing := _pick_pressers(units, side, focus, reach)

	for unit in units:
		var tier := "I"
		if unit.data != null:
			tier = unit.data.get_tier_clean()
		var unit_side := 1 if unit.is_enemy else 0

		if ball.is_carried_by(unit):
			# During a scripted relay the man on the ball is waiting to duel,
			# not attacking — if he set off for goal he would drag the whole
			# shape across the pitch between tiers.
			if ball.scripted_possession:
				unit.set_role(PlayerUnit.Role.HOLD, _drift_point(unit), unit.walk_speed)
			else:
				unit.set_role(PlayerUnit.Role.DRIBBLE, _dribble_point(unit), unit.dribble_speed)
			continue

		if receiver == unit:
			unit.set_role(PlayerUnit.Role.RECEIVE, ball.global_position, unit.chase_speed)
			continue

		# THE BREAK. Everyone on the scoring side abandons their quarter and
		# runs at the goal together, so the shot arrives at the end of a move
		# rather than out of nowhere.
		if attack_surge_side == unit_side:
			unit.set_role(PlayerUnit.Role.SURGE, _surge_point(unit), press_speed)
			continue

		# The other half of the break. Without this the defenders stayed
		# leashed to their posts and the attack simply ran straight through
		# them, which looked like ghosts passing each other.
		if attack_surge_side >= 0:
			unit.set_role(PlayerUnit.Role.RECOVER, _recover_point(unit), press_speed)
			continue

		# The ball is in MY quarter and it is not my team's — go and win it.
		var mine_to_win := side != unit_side and unit.steal_cooldown <= 0.0 \
			and zones.contains_x(tier, unit.is_enemy, ball.global_position) \
			and unit.global_position.distance_to(focus) < reach
		if mine_to_win:
			unit.set_role(PlayerUnit.Role.BALL, ball.global_position, unit.chase_speed)
			continue

		if side < 0:
			unit.set_role(PlayerUnit.Role.HOLD, _drift_point(unit), unit.walk_speed)
		elif side != unit_side:
			if pressing.has(unit):
				unit.set_role(PlayerUnit.Role.PRESS, focus, press_speed)
			else:
				unit.set_role(PlayerUnit.Role.MARK, _mark_point(unit), unit.walk_speed * 1.5)
		else:
			unit.set_role(PlayerUnit.Role.OPEN, _open_point(unit), unit.walk_speed * 1.6)


## Who charges the ball. Everyone defending whose own quarter the ball is in,
## plus the nearest `press_helpers` from neighbouring quarters. Everyone else
## stays with their man — which is what stops all ten chasing at once.
func _pick_pressers(units: Array[PlayerUnit], side: int, focus: Vector2,
		reach: float) -> Array[PlayerUnit]:
	var chosen: Array[PlayerUnit] = []
	if side < 0:
		return chosen

	var helpers: Array[PlayerUnit] = []
	for unit in units:
		var unit_side := 1 if unit.is_enemy else 0
		if unit_side == side or unit.steal_cooldown > 0.0:
			continue
		if unit.global_position.distance_to(focus) > reach:
			continue
		var tier := "I"
		if unit.data != null:
			tier = unit.data.get_tier_clean()
		if zones.contains_x(tier, unit.is_enemy, focus):
			chosen.append(unit)
		else:
			helpers.append(unit)

	# Take the N nearest without sorting. This runs every physics frame, and a
	# repeated scan of a handful of units beats allocating a sort each time.
	for _i in mini(press_helpers, helpers.size()):
		var best: PlayerUnit = null
		var best_d := INF
		for helper in helpers:
			if chosen.has(helper):
				continue
			var d := helper.global_position.distance_to(focus)
			if d < best_d:
				best_d = d
				best = helper
		if best == null:
			break
		chosen.append(best)

	return chosen


func _dribble_point(unit: PlayerUnit) -> Vector2:
	var rect := get_play_rect()
	var goal_x: float = rect.end.x if not unit.is_enemy else rect.position.x

	# In waiting play the ball may not enter the end quarters, so the carrier
	# aims at the edge of the corridor rather than at the goal. Without this he
	# would run into the fence and lean on it.
	if ball != null and ball.corridor_active and ball.corridor.size.x > 1.0:
		goal_x = clampf(goal_x, ball.corridor.position.x, ball.corridor.end.x)

	return Vector2(goal_x, unit.global_position.y)


## The strip of pitch the ball is allowed into during ordinary waiting play.
##
## By default quarters 2 and 3 — the middle half. Quarters 1 and 4 are the two
## Tier IV territories (yours at one end, theirs at the other), and keeping the
## ball out of them is what stops ambient passing ever threatening a goal. All
## scoring then has to come out of a PLAY MAKER, which is the point of it.
##
## Set ball_roam_quarter_first to 1 and _last to 4 in Tuning.csv to switch the
## whole rule off.
func _ball_corridor() -> Rect2:
	if zones == null or not zones_enabled:
		return Rect2()

	var first := clampi(ball_roam_quarter_first, 1, ALL_TIERS.size())
	var last := clampi(ball_roam_quarter_last, first, ALL_TIERS.size())

	var play := get_play_rect()
	var width := play.size.x * zones.share
	return Rect2(
		play.position.x + float(first - 1) * width, play.position.y,
		float(last - first + 1) * width, play.size.y)


## Stand between your man and the goal you are defending — but leashed, so
## marking cannot drag a whole tier out of position across the pitch.
func _mark_point(unit: PlayerUnit) -> Vector2:
	var man := unit.mark_target
	if man == null or not is_instance_valid(man):
		return _drift_point(unit)

	var rect := get_play_rect()
	var own_goal_x: float = rect.position.x if not unit.is_enemy else rect.end.x
	var toward_goal := (Vector2(own_goal_x, man.global_position.y) - man.global_position).normalized()
	return unit.leash_point(man.global_position + toward_goal * mark_distance)


## Show for the pass: get off whoever is nearest and drift a little the way
## your team is attacking, without abandoning your lane.
func _open_point(unit: PlayerUnit) -> Vector2:
	var nearest_foe: PlayerUnit = null
	var best := INF
	for other in _all_units():
		if other.is_enemy == unit.is_enemy:
			continue
		var d := other.global_position.distance_to(unit.global_position)
		if d < best:
			best = d
			nearest_foe = other

	var spot := unit.home_position
	if nearest_foe != null and best < open_spread * 1.6:
		spot += (unit.global_position - nearest_foe.global_position).normalized() * open_spread
	spot.x += (1.0 if not unit.is_enemy else -1.0) * 45.0
	return unit.leash_point(spot)


## Where a surging unit runs to: its own slot, thrown forward toward the goal
## it attacks and drawn a little toward the goal mouth. Deliberately NOT
## leashed to its quarter — the break is the one moment a unit is meant to
## leave its post for good.
func _surge_point(unit: PlayerUnit) -> Vector2:
	var rect := get_play_rect()
	var mouth := _goal_mouth(not unit.is_enemy)

	# Close a FRACTION OF THE REMAINING DISTANCE to goal rather than shifting
	# everyone forward by the same number of pixels. A fixed shift squashed the
	# back players into the touchline while the front ones ran out of pitch;
	# this moves the whole shape up while keeping its order and its spacing.
	var edge := rect.size.x * 0.10
	var line_x := mouth.x - edge
	if unit.is_enemy:
		line_x = mouth.x + edge

	var spot := Vector2(
		lerpf(unit.home_position.x, line_x, surge_advance),
		lerpf(unit.home_position.y, mouth.y, surge_centring))

	return Vector2(
		clampf(spot.x, rect.position.x + 20.0, rect.end.x - 20.0),
		clampf(spot.y, rect.position.y + 24.0, rect.end.y - 24.0))


## Where a defender drops back to while the other side breaks: goal-side of
## his man, and deliberately NOT leashed to his quarter, so he can retreat the
## length of the pitch with the attack instead of being pinned to his post.
func _recover_point(unit: PlayerUnit) -> Vector2:
	var rect := get_play_rect()
	var own_goal_x: float = rect.position.x if not unit.is_enemy else rect.end.x

	var man := unit.mark_target
	if man == null or not is_instance_valid(man):
		# Nobody to track — fall back toward your own goal and hold the line.
		return Vector2(
			lerpf(unit.home_position.x, own_goal_x, surge_advance * 0.6),
			unit.home_position.y)

	var toward_goal := (Vector2(own_goal_x, man.global_position.y) - man.global_position).normalized()
	var spot := man.global_position + toward_goal * mark_distance
	return Vector2(
		clampf(spot.x, rect.position.x + 20.0, rect.end.x - 20.0),
		clampf(spot.y, rect.position.y + 24.0, rect.end.y - 24.0))


## Called when the last duel is settled. `side_is_enemy` is whoever won it and
## is about to shoot.
func _begin_surge(side_is_enemy: bool) -> void:
	attack_surge_side = 1 if side_is_enemy else 0
	print("  The break is on — %s push up." % ("they" if side_is_enemy else "you"))


func _end_surge() -> void:
	attack_surge_side = -1


func _drift_point(unit: PlayerUnit) -> Vector2:
	var phase := float(unit.get_instance_id() % 100) * 0.06
	return unit.leash_point(unit.home_position + Vector2(
		sin(_anim_clock * 0.5 + phase) * 34.0,
		cos(_anim_clock * 0.37 + phase) * 46.0))


# =============================================================
#  TUNING — every number below comes from Tuning.csv when a row exists,
#  otherwise the value already in code stands. Nothing here can crash on a
#  missing or misspelled row.
# =============================================================

# =============================================================
#  THE SEASON
#
#  Season.csv says who you are playing and how hard they are. Everything
#  here degrades quietly: no Season.csv, or a season already finished, and
#  the match is a friendly that plays exactly as it always did.
# =============================================================

func _apply_fixture() -> void:
	current_fixture = {}
	forced_enemy_class = ""
	if season == null or state == null:
		return

	# "Play it again" from the stats screen. The fixture is already recorded,
	# so this run is a friendly: same opposition, nothing written down.
	if state.has_flag(MatchStatsScreen.REPLAY_FLAG):
		state.set_flag(MatchStatsScreen.REPLAY_FLAG, false)
		replaying = true
		current_fixture = season.previous(state)
		if not current_fixture.is_empty():
			forced_enemy_class = String(current_fixture["class"]).strip_edges()
			print("[season] Rerunning %s as a friendly. Nothing will be recorded."
				% current_fixture["opponent"])
			return
		print("[season] Nothing to rerun — playing the next fixture instead.")

	current_fixture = season.current(state)
	if current_fixture.is_empty():
		print("[season] No fixture on — this is a friendly. The result will not be recorded.")
		return

	forced_enemy_class = String(current_fixture["class"]).strip_edges()

	# Difficulty is a flat power bonus to every enemy card, for this fixture
	# only. It is deliberately blunt: one number in a spreadsheet, and you can
	# see straight away what a 2 does compared with a 0.
	var scale := db.tune_float("season_difficulty_scale", 1.0)
	var bonus := int(round(float(int(current_fixture["difficulty"])) * scale))
	if abilities != null and bonus != 0:
		abilities.side_bonus[true] = bonus

	print("[season] Matchday %d of %d — %s%s%s" % [
		int(current_fixture["number"]), season.last_number(),
		current_fixture["opponent"],
		"  (THE FINAL)" if bool(current_fixture["final"]) else "",
		"  difficulty +%d" % bonus if bonus != 0 else ""])


func _apply_match_tuning() -> void:
	MATCH_LENGTH_MINUTES = db.tune_float("match_length_minutes", MATCH_LENGTH_MINUTES)
	FIRST_EVENT_MINUTE = db.tune_float("first_event_minute", FIRST_EVENT_MINUTE)
	LAST_EVENT_MINUTE = db.tune_float("last_event_minute", LAST_EVENT_MINUTE)
	ROUNDS_PER_CYCLE = db.tune_int("rounds_per_cycle", ROUNDS_PER_CYCLE)
	TOTAL_CYCLES = db.tune_int("total_cycles", TOTAL_CYCLES)
	ties_go_to_attacker = db.tune_bool("ties_go_to_attacker", ties_go_to_attacker)
	use_rps_minigame = db.tune_bool("use_rps_minigame", use_rps_minigame)

	zones_enabled = db.tune_bool("zones_enabled", zones_enabled)
	press_radius_fraction = db.tune_float("press_radius_fraction", press_radius_fraction)
	ball_roam_quarter_first = db.tune_int("ball_roam_quarter_first", ball_roam_quarter_first)
	ball_roam_quarter_last = db.tune_int("ball_roam_quarter_last", ball_roam_quarter_last)
	surge_advance = db.tune_float("surge_advance", surge_advance)
	surge_centring = db.tune_float("surge_centring", surge_centring)
	press_helpers = db.tune_int("press_helpers", press_helpers)
	press_speed = db.tune_float("press_speed", press_speed)
	mark_distance = db.tune_float("mark_distance", mark_distance)
	open_spread = db.tune_float("open_spread", open_spread)


func _tune_ball() -> void:
	if ball == null:
		return
	ball.pass_speed = db.tune_float("ball_pass_speed", ball.pass_speed)
	ball.shot_speed = db.tune_float("ball_shot_speed", ball.shot_speed)
	ball.delivery_speed = db.tune_float("ball_delivery_speed", ball.delivery_speed)
	ball.carry_seconds = Vector2(
		db.tune_float("ball_carry_min_seconds", ball.carry_seconds.x),
		db.tune_float("ball_carry_max_seconds", ball.carry_seconds.y))
	ball.forward_pass_chance = db.tune_float("ball_forward_pass_chance", ball.forward_pass_chance)
	ball.intercept_radius = db.tune_float("ball_intercept_radius", ball.intercept_radius)
	ball.tackle_radius = db.tune_float("ball_tackle_radius", ball.tackle_radius)
	ball.possession_grace = db.tune_float("ball_possession_grace", ball.possession_grace)
	ball.tackle_recovery = db.tune_float("ball_tackle_recovery", ball.tackle_recovery)
	ball.pickup_radius = db.tune_float("ball_pickup_radius", ball.pickup_radius)
	ball.loose_settle_seconds = db.tune_float(
		"ball_loose_settle_seconds", ball.loose_settle_seconds)
	ball.loose_timeout_seconds = db.tune_float(
		"ball_loose_timeout_seconds", ball.loose_timeout_seconds)
	ball.pressure_radius = db.tune_float("ball_pressure_radius", ball.pressure_radius)
	ball.min_hold_seconds = db.tune_float("ball_min_hold_seconds", ball.min_hold_seconds)
	ball.intercept_grace = db.tune_float("ball_intercept_grace", ball.intercept_grace)
	ball.trail_seconds = db.tune_float("ball_trail_seconds", ball.trail_seconds)
	ball.ring_radius = db.tune_float("ball_ring_radius", ball.ring_radius)
	ball.corridor_return_speed = db.tune_float(
		"ball_corridor_return_speed", ball.corridor_return_speed)


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
	unit.zone_pull = db.tune_float("unit_zone_pull", unit.zone_pull)
	unit.leash = db.tune_float("unit_leash", unit.leash)
	unit.slot_pull = db.tune_float("unit_slot_pull", unit.slot_pull)
	unit.separation_radius = db.tune_float("unit_separation_radius", unit.separation_radius)
	unit.separation_strength = db.tune_float(
		"unit_separation_strength", unit.separation_strength)
	unit.contest_radius = db.tune_float("unit_contest_radius", unit.contest_radius)
	unit.swerve_strength = db.tune_float("unit_swerve_strength", unit.swerve_strength)


func _tune_goalie(keeper: GoalieUnit) -> void:
	keeper.break_through_chance = db.tune_float("goalie_break_through_chance", keeper.break_through_chance)
	keeper.open_goal_chance = db.tune_float("goalie_open_goal_chance", keeper.open_goal_chance)


# =============================================================
#  THE CAMERA
#
#  main_scene decides WHAT to look at; match_camera.gd decides how smoothly
#  to get there. Keeping those apart means the rule below is four lines you
#  can read, rather than easing sums mixed in with match logic.
# =============================================================

## Built the first time the pitch geometry is pinned, and given the pitch
## rectangle as it looked with NO camera in the scene. That framing is then
## what the whole match uses forever — see get_visible_world_rect().
func _spawn_camera(pitch: Rect2) -> void:
	if camera != null or not db.tune_bool("camera_enabled", true):
		return
	camera = MatchCamera.new()
	camera.name = "MatchCamera"
	add_child(camera)
	camera.setup(pitch, db)
	camera.make_current()
	print("[camera] Following the ball. Set camera_enabled to false in Tuning.csv to switch it off.")


func _drive_camera() -> void:
	if camera == null:
		return

	# Anything that is not live play gets the whole pitch: the draft, the
	# whistle, full time. You need to see both teams to choose a card.
	if current_state != MatchState.PLAYING or _freeze_depth > 0 or ball == null:
		camera.look_wide()
		return

	if ball.is_shooting():
		camera.look_close(ball.global_position)
		return

	# Mid-pass, look at where the ball is GOING. Following where it is drags
	# the view along behind every pass and the play always feels off-centre.
	var toward := ball.global_position
	if ball.is_in_flight():
		toward = ball.arrival_point()
	camera.look_at_play(ball.global_position, toward)


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

	var outcome := "draw"
	if player_score > enemy_score:
		outcome = "win"
	elif player_score < enemy_score:
		outcome = "loss"

	var facts := _facts_for(null)
	facts["result"] = outcome
	facts["scored"] = str(player_score)
	facts["conceded"] = str(enemy_score)
	facts["margin"] = str(player_score - enemy_score)
	_report("match_ended", facts)

	# One-match brews wear off at the whistle. Permanent ones stay on.
	var brews_off := BrewDB.clear_temporary(state)
	if brews_off > 0 and gains != null:
		gains.note("%d one-match brew%s wore off" % [
			brews_off, "" if brews_off == 1 else "s"], "pour another at the Pub")

	# The fixture is recorded BEFORE the Progression rows run, so that a row
	# saying  Requires: flag:season_over  or  count:season_wins>=3  is testing
	# today's result rather than yesterday's.
	var summary: Dictionary = {}
	if season != null and not replaying:
		summary = season.record(player_score, enemy_score, state)
	elif replaying:
		# A rerun still shows you a scoreline, it just does not go in the table.
		summary = {
			"fixture": current_fixture,
			"scored": player_score,
			"conceded": enemy_score,
			"actions": [] as Array[Dictionary],
		}
		print("[season] Rerun finished %d-%d. The table is untouched."
			% [player_score, enemy_score])

	var reward_actions: Array = summary.get("actions", [])
	for action in reward_actions:
		var reward_kind := String((action as Dictionary)["kind"])
		var reward_value := String((action as Dictionary)["value"])
		if reward_kind == "announce":
			print("[season] %s" % reward_value)
			await announce(reward_value, db.tune_float("progression_announce_seconds", 1.6))
		else:
			push_warning("[season] '%s:' does not work in a fixture's On Win / On Loss column. Put it in a Progression.csv row instead."
				% reward_kind)

	# A story or a goto in a Progression row takes the screen over. When it is
	# a story, it now comes back to the season screen rather than restarting
	# the match.
	var took_over := await _advance_progression("match_ended", ScenePaths.SEASON)

	# The second photograph, taken last, so unlocks handed out by the fixture
	# AND by the Progression rows both land on the panel.
	if gains != null:
		gains.summary = summary
		gains.finish(state)
		MatchReport.stash(get_tree(), gains)
	state.save_to_disk()

	if took_over:
		return

	# Time may be running at 8x; the full-time card should still be readable,
	# so it is timed in real seconds rather than game seconds.
	GameSpeed.reset()
	await get_tree().create_timer(db.tune_float("full_time_seconds", 2.6)).timeout

	# Never strand the player on the pitch with nothing to press. If the
	# season screen is missing for any reason, go to the base instead.
	# Full time goes to the stats screen, which then offers Continue through
	# to the season table. Each falls back to the next if a scene is missing,
	# so you can never be stranded on the pitch with nothing to press.
	var after := ScenePaths.STATS
	if not ResourceLoader.exists(ScenePaths.resolve(after)):
		after = ScenePaths.SEASON
	if not ResourceLoader.exists(ScenePaths.resolve(after)):
		push_warning("[match] Neither the stats screen nor the season screen was found, so full time goes to the base.")
		after = ScenePaths.BASE
	ScenePaths.go_to(get_tree(), after)


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

	# The team builder already settled the class, the Star and the 9 regulars.
	var picked := TeamSelection.fetch(get_tree())
	if picked != null and picked.active_star != null:
		_apply_team_selection(picked)
		return

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

	_lock_geometry()
	spawn_team(chosen, false)

	# Enemy picks a different class so you never mirror-match.
	_choose_enemy_team(chosen.unit_type)
	_unlock_geometry()

	_assign_marks()
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
	_print_line_ups()
	_report("match_started", _facts_for(null))
	_advance_progression("match_started")


## Kick off with the exact team chosen in the team builder. This is the same
## work _resolve_kickoff_star() does, minus the drafting: the Star, the Star
## bundle and the 9 regulars all arrive already decided.
func _apply_team_selection(picked: TeamSelection) -> void:
	chosen_regulars = picked.regulars
	active_player_star = picked.active_star
	player_star_tier = picked.star_tier
	player_star_bundle = picked.star_bundle.duplicate()
	available_player_stars = picked.star_bundle.duplicate()
	available_player_stars.erase(picked.active_star)

	# You never saw a kickoff card row, so nothing was "offered and refused" —
	# the enemy may draw from any class but yours.
	_offered_star_classes.clear()

	_lock_geometry()
	spawn_team(active_player_star, false)
	_choose_enemy_team(active_player_star.unit_type)
	_unlock_geometry()

	_assign_marks()
	_assign_goalie_data()

	for unit in _all_units():
		unit.clear_round_flags()
		if unit.data == active_player_star and not unit.is_enemy:
			unit.is_playmaker = true
			unit.set_highlight(true)

	give_ball_to(false)
	current_state = MatchState.PLAYING

	print("Your team — %s | Star: %s (Tier %s)" % [
		picked.unit_type, active_player_star.player_name, player_star_tier])
	_print_line_ups()
	_report("match_started", _facts_for(null))
	_advance_progression("match_started")


## Prints exactly who is on the pitch for each side. If a name here is not one
## you picked, that is a data problem worth reporting — and it also settles the
## commonest confusion: every Star wearing another class's colours belongs to
## the OPPOSITION, and now wears a badge on the pitch to prove it.
func _print_line_ups() -> void:
	for side: bool in [false, true]:
		var label := "Enemy" if side else "Your team"
		print("[team] %s:" % label)

		for tier in ALL_TIERS:
			var names := PackedStringArray()
			for unit in _all_units():
				if unit.is_enemy != side or unit.data == null:
					continue
				if unit.data.get_tier_clean() != tier:
					continue
				names.append(unit.data.player_name + (" ★" if unit.is_star_player else ""))
			if names.is_empty():
				continue
			print("         Tier %s: %s" % [tier, ", ".join(names)])


func _choose_enemy_team(player_type_to_avoid: String) -> void:
	var by_class := _stars_grouped_by_class()

	# THE SEASON GETS FIRST SAY. If today's fixture names a class, that is who
	# you play — the whole point of a fixture list is that you know who is
	# coming. A name that matches no card falls through to the old random
	# pick, with a line in the Output panel saying so.
	if forced_enemy_class != "":
		var named := ""
		for class_key in by_class.keys():
			if String(class_key).to_lower() == forced_enemy_class.to_lower():
				named = String(class_key)
				break
		if named != "":
			_field_enemy_class(named)
			return
		push_warning("[season] Season.csv asks for '%s', but no Star Player belongs to that class. Picking an opponent at random instead."
			% forced_enemy_class)

	# `preferred` also skips the classes you were offered at kickoff and turned
	# down. Without that the two Stars you just rejected could walk straight
	# back on for the opposition, which reads as "why is that card still here?".
	# `any_other` is the same list without that restriction, used when the
	# project has too few classes to be picky.
	var avoid_offered := db.tune_bool("enemy_avoids_offered_classes", true)
	var preferred: Array[String] = []
	var any_other: Array[String] = []

	for class_name_key in by_class.keys():
		var key := String(class_name_key)
		if key.to_lower() == player_type_to_avoid.to_lower():
			continue
		any_other.append(key)
		if avoid_offered and _offered_star_classes.has(key):
			continue
		preferred.append(key)

	var candidates := preferred
	if candidates.is_empty():
		candidates = any_other
	if candidates.is_empty():
		push_warning("Only one class of Star Players found — enemy will mirror your class.")
		candidates.append(player_type_to_avoid)

	candidates.shuffle()
	_field_enemy_class(candidates[0])


## Put an opposition of this exact class on the pitch.
func _field_enemy_class(enemy_class: String) -> void:
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
	# With zones on, a Tier's QUARTER decides x and the formation scene decides
	# y, so your authored shape still shows through in the dimension it still
	# has freedom in. With zones off this is the old mirrored layout exactly.
	var star_pos: Vector2 = mirror_if_enemy(layout["star"], pitch_center_x, is_enemy)
	if zones_enabled and zones != null:
		star_pos = Vector2(zones.slot_for(this_star_tier, is_enemy, 0, 1).x,
			layout["star"].y)
	var star_unit := create_unit_instance(star_player, star_pos, is_enemy)
	if star_unit:
		star_unit.is_star_player = true
		_place_in_zone(star_unit, this_star_tier)

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

		# Your side fields exactly the cards chosen in the team builder.
		# The enemy keeps drawing at random, so it stays a fresh opponent.
		if not is_enemy and chosen_regulars.has(tier_key):
			var built: Array[PlayerData] = []
			built.assign(chosen_regulars[tier_key])
			if not built.is_empty():
				pool = built

		if pool.size() < positions.size():
			# A data problem, not a code fault — CardDB has already named the
			# offending row, so print rather than push_warning (no backtrace).
			print("[roster] '%s' has only %d Tier %s cards for %d slots."
				% [star_player.unit_type, pool.size(), tier_key, positions.size()])

		var fielded := mini(positions.size(), pool.size())
		for i in fielded:
			var pos: Vector2 = mirror_if_enemy(positions[i], pitch_center_x, is_enemy)
			if zones_enabled and zones != null:
				pos = Vector2(zones.slot_for(tier_key, is_enemy, i, fielded).x,
					(positions[i] as Vector2).y)
			var made := create_unit_instance(pool[i], pos, is_enemy)
			if made != null:
				_place_in_zone(made, tier_key)


## Tell a unit which quarter it belongs to. Everything else about zoning —
## the pull back, the leash, the "ball is in my territory" test — reads these.
func _place_in_zone(unit: PlayerUnit, tier_key: String) -> void:
	if not zones_enabled or zones == null:
		return
	unit.tier_zone = zones.zone_for(tier_key, unit.is_enemy)
	unit.tier_soft_zone = zones.soft_zone_for(tier_key, unit.is_enemy)


## Top of the pitch first. A plain insertion sort — the lists are three long.
func _by_height(units: Array[PlayerUnit]) -> Array[PlayerUnit]:
	var out: Array[PlayerUnit] = []
	for unit in units:
		var at := out.size()
		for i in out.size():
			if unit.global_position.y < out[i].global_position.y:
				at = i
				break
		out.insert(at, unit)
	return out


## Pair every unit with the opponent standing in the same QUARTER as it.
##
## The two sides are mirrored, so a quarter holds your Tier N and their Tier
## (V - N): your defenders end up marking their attackers, which is the point
## of mirroring them. Pairs are matched by how far down the pitch they start,
## so the marking never crosses over itself.
func _assign_marks() -> void:
	if not zones_enabled or zones == null:
		return

	for quarter in ALL_TIERS.size():
		var mine: Array[PlayerUnit] = []
		var theirs: Array[PlayerUnit] = []
		for unit in _all_units():
			if unit.data == null:
				continue
			if zones.zone_index(unit.data.get_tier_clean(), unit.is_enemy) != quarter:
				continue
			if unit.is_enemy:
				theirs.append(unit)
			else:
				mine.append(unit)

		mine = _by_height(mine)
		theirs = _by_height(theirs)

		# A Star fills its quarter alone, so the three opposite all shadow the
		# one man. That is correct — he is the dangerous one.
		for i in mine.size():
			mine[i].mark_target = theirs[i % theirs.size()] if not theirs.is_empty() else null
		for i in theirs.size():
			theirs[i].mark_target = mine[i % mine.size()] if not mine.is_empty() else null


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
		if zones_enabled:
			star_pos = _fit_layout_to_pitch_height(star_pos, tiers)
		else:
			star_pos = _fit_layout_to_home_half(star_pos, tiers)

	return {"star": star_pos, "tiers": tiers}


## With quarters switched on, x comes from the Tier's zone, so all a formation
## scene still decides is the vertical shape. This stretches that shape over
## the full height of the pitch and leaves x alone for spawn_team to replace.
func _fit_layout_to_pitch_height(star_pos: Vector2, tiers: Dictionary) -> Vector2:
	var lowest := star_pos.y
	var highest := star_pos.y
	for key in tiers.keys():
		for p in (tiers[key] as Array):
			lowest = minf(lowest, (p as Vector2).y)
			highest = maxf(highest, (p as Vector2).y)
	var span := highest - lowest
	if span < 1.0:
		return star_pos

	var play := get_play_rect()
	var top := play.position.y + play.size.y * 0.14
	var height := play.size.y * 0.72

	for key in tiers.keys():
		var moved: Array[Vector2] = []
		for p in (tiers[key] as Array):
			var q := p as Vector2
			moved.append(Vector2(q.x, top + ((q.y - lowest) / span) * height))
		tiers[key] = moved

	return Vector2(star_pos.x, top + ((star_pos.y - lowest) / span) * height)


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
	# Your side only: the enemy never visits your Pub.
	if not is_enemy:
		unit.active_brew = BrewDB.brew_id_for(data, state)
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
	_update_score_label()

	# The scorer is whoever took the shot this round. Facts about them travel
	# with the event, and Stats.csv decides what that feeds.
	var scorer := _find_shooter(conceded_by_enemy)
	if conceded_by_enemy:
		_report("goal_scored", _facts_for(scorer))
	else:
		_report("goal_conceded", _facts_for(null))


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


## The two close-up views. Both are optional at runtime: turn them off with
## `duel_arena_enabled` / `shootout_enabled` in Tuning.csv and the match plays
## exactly as it did before, just without the cut-aways.
func spawn_cutaways() -> void:
	if db.tune_bool("duel_arena_enabled", true):
		duel_arena = DUEL_ARENA_SCENE.instantiate() as DuelArena
		if duel_arena != null:
			duel_arena.name = "DuelArena"
			add_child(duel_arena)
			duel_arena.apply_tuning(db)
		else:
			push_error("duel_arena.tscn did not instantiate as a DuelArena.")

	if db.tune_bool("shootout_enabled", true):
		shootout = SHOOTOUT_SCENE.instantiate() as ShootoutView
		if shootout != null:
			shootout.name = "ShootoutView"
			add_child(shootout)
			shootout.apply_tuning(db)
		else:
			push_error("shootout_view.tscn did not instantiate as a ShootoutView.")


## The scoreboard, centred at the top of the pitch. Created in code so you
## never have to touch main_scene.tscn; size and margin come from Tuning.csv.
func spawn_scoreboard() -> void:
	score_label = Label.new()
	score_label.name = "ScoreLabel"
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	score_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	score_label.grow_horizontal = Control.GROW_DIRECTION_BOTH

	var width := db.tune_float("scoreboard_width", 340.0)
	var height := db.tune_float("scoreboard_height", 96.0)
	var margin := db.tune_float("scoreboard_top_margin", 18.0)
	score_label.offset_left = -width / 2.0
	score_label.offset_right = width / 2.0
	score_label.offset_top = margin
	score_label.offset_bottom = margin + height

	score_label.add_theme_font_size_override("font_size",
		db.tune_int("scoreboard_font_size", 60))
	score_label.add_theme_color_override("font_color", Color(1, 1, 1))
	score_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	score_label.add_theme_constant_override("outline_size", 8)

	selection_ui.add_child(score_label)
	_update_score_label()


func _update_score_label() -> void:
	if score_label != null:
		score_label.text = "%d  –  %d" % [player_score, enemy_score]


## The speed buttons and the AUTO toggle. It lives on the SelectionUI layer,
## so the camera never moves it.
func spawn_hud() -> void:
	hud = MatchHUD.new()
	hud.name = "MatchHUD"
	hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hud.offset_left = db.tune_float("hud_left_margin", 16.0)
	hud.offset_top = db.tune_float("hud_top_margin", 14.0)
	selection_ui.add_child(hud)
	hud.setup(db, state)
	# Turning AUTO on mid-draft should pick straight away, not next round.
	hud.auto_pick_changed.connect(_on_auto_pick_changed)


## The hover window. It lives on the SelectionUI layer with the cards, so it
## sits over them and the camera never moves it.
func spawn_card_stats() -> void:
	if not db.tune_bool("card_hover_stats", true):
		return
	card_stats = CardStatsPanel.make(db)
	selection_ui.add_child(card_stats)


func _on_auto_pick_changed(is_on: bool) -> void:
	if is_on and current_state == MatchState.DRAFTING:
		_offer_auto_pick()


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


## Find the unit on the pitch that is showing a given card.
func unit_for_card(card: PlayerData, side_is_enemy: bool) -> PlayerUnit:
	if card == null:
		return null
	for unit in _all_units():
		if unit.is_enemy == side_is_enemy and unit.data == card:
			return unit
	return null


## One leg of the PLAY MAKER relay: work the ball up to whoever is holding it
## for this tier, then hold a beat so the viewer can see who has it.
##
## The ball is PASSED THROUGH the team-mates standing along the way rather than
## struck the full length of the pitch in one go. The man for this tier is
## still the end of the line — he just is not the only one who touches it.
func deliver_ball_to_card(card: PlayerData, side_is_enemy: bool) -> void:
	if ball == null:
		return
	var unit := unit_for_card(card, side_is_enemy)
	if unit == null or ball.is_carried_by(unit):
		return

	var hop_beat := db.tune_float("relay_hop_beat_seconds", 0.12)
	for stop in _relay_chain(unit, side_is_enemy):
		ball.deliver_to(stop)
		await ball.delivery_arrived
		if hop_beat > 0.0:
			await get_tree().create_timer(hop_beat).timeout

	# The chain never includes the destination, and an interception cannot
	# happen on a scripted relay, so this always lands.
	if not ball.is_carried_by(unit):
		ball.deliver_to(unit)
		await ball.delivery_arrived

	var beat := db.tune_float("relay_beat_seconds", 0.25)
	if beat > 0.0:
		await get_tree().create_timer(beat).timeout


## The team-mates the ball is played through on its way to `target`, in order.
## Does NOT include `target` itself.
##
## Greedy and deliberately simple: from where the ball is now, take the NEAREST
## team-mate that is meaningfully closer to the target than we already are, and
## repeat from there. Picking the nearest rather than the furthest is what makes
## it look like a passing move instead of a series of long balls.
func _relay_chain(target: PlayerUnit, side_is_enemy: bool) -> Array[PlayerUnit]:
	var chain: Array[PlayerUnit] = []
	if ball == null or target == null:
		return chain

	var max_hops := db.tune_int("relay_max_hops", 3)
	if max_hops <= 0:
		return chain
	var max_reach := db.tune_float("relay_hop_max_distance", 420.0)
	var min_progress := db.tune_float("relay_min_progress", 60.0)

	var here := ball.global_position
	var goal := target.global_position

	while chain.size() < max_hops:
		var best: PlayerUnit = null
		var best_hop := INF

		for unit in _all_units():
			if unit.is_enemy != side_is_enemy or unit == target or chain.has(unit):
				continue
			if ball.is_carried_by(unit):
				continue

			var hop := here.distance_to(unit.global_position)
			if hop > max_reach or hop >= best_hop:
				continue
			# Every hop has to actually advance the move, or the ball ends up
			# going sideways and backwards on its way up the pitch.
			if here.distance_to(goal) - unit.global_position.distance_to(goal) < min_progress:
				continue

			best_hop = hop
			best = unit

		if best == null:
			break
		chain.append(best)
		here = best.global_position

	return chain


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
	# ONCE THE CAMERA EXISTS, IGNORE IT. This function is asked "how big is
	# the pitch" by the formations, the quarters and the ball corridor, and
	# the honest answer is "the same as it was at kick-off". Reading the live
	# canvas transform instead would shrink the pitch every time the camera
	# zoomed in, squashing both formations in toward the ball.
	if camera != null and camera.home_rect.size.x > 1.0:
		return camera.home_rect

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
	# Both teams must be laid out against the SAME rectangle. get_play_rect()
	# reads the live camera, so if anything nudged the view between spawning
	# your side and spawning theirs, the two halves were mirrored about
	# different centre lines and the formations drifted into each other.
	# _lock_geometry() pins one rect for the whole of a spawn.
	if _geometry_locked:
		return _locked_play_rect

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


## Pin the play area for the duration of a spawn, so both teams are built
## against identical geometry. Always paired with _unlock_geometry().
func _lock_geometry() -> void:
	if _geometry_locked:
		return
	# The camera is built here, before the play rect is pinned, so that the
	# rectangle it is handed is the un-zoomed one. After this the two agree
	# forever, because get_visible_world_rect() hands back the camera's own
	# framing.
	_spawn_camera(get_visible_world_rect())

	_locked_play_rect = get_play_rect()
	_geometry_locked = true

	zones = PitchZones.new(_locked_play_rect,
		db.tune_float("zone_share", 0.25),
		db.tune_float("zone_stretch", 0.33),
		db.tune_float("zone_side_inset", 0.34))

	if zone_overlay != null:
		zone_overlay.visible = zones_enabled
		zone_overlay.setup(zones,
			db.tune_float("zone_tint_alpha", 0.07),
			db.tune_float("zone_tint_alpha_draft", 0.20))


func _unlock_geometry() -> void:
	_geometry_locked = false


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

	# Remember which classes were on the table, so _choose_enemy_team() can
	# steer the opposition away from the ones you looked at and passed on.
	_offered_star_classes.clear()
	for card in choices:
		var key := card.unit_type.strip_edges()
		if key != "" and not _offered_star_classes.has(key):
			_offered_star_classes.append(key)

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

	# THE WHISTLE. This has to be the very first thing that happens — before
	# the enemy's substitution and before the "HOLD UP!" banner, both of which
	# take seconds. Freezing later left the ball being passed around underneath
	# the announcement while you were trying to choose.
	#
	# It is undone in _on_draft_complete(), and not one moment sooner: that
	# waits for the incoming Star to finish jogging into their slot, so play
	# only restarts once the new Star is actually standing on the pitch.
	_draft_froze_play = true
	freeze_play(true)

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
	offered_cards.clear()

	if current_phase_index >= draft_phases.size():
		_on_draft_complete()
		return

	var phase := draft_phases[current_phase_index]

	if phase == "Star":
		for star_data in get_star_player_choices():
			create_card_for_unit(star_data)
		_offer_auto_pick()
		return

	if phase == "StarChoice":
		if available_player_stars.is_empty():
			# No stars left (this shouldn't fire — cycle 3 has no HOLD UP).
			current_phase_index += 1
			start_next_draft_phase()
			return
		for star_data in available_player_stars:
			create_card_for_unit(star_data)
		_offer_auto_pick()
		return

	# --- Regular tier phase ---
	#
	# THE STAR IS A CARD LIKE ANY OTHER NOW.
	#
	# It used to fill its own tier automatically, every round, for the whole
	# cycle. Three rounds per cycle meant the same Star played three times in
	# a row, and because the Lorelei Star is Tier IV with 5 power, the enemy
	# fielded a 5-power Tier IV three rounds running while your Tier IV
	# rotated through ordinary cards. That is the bug you saw, and it was
	# never a fair fight.
	#
	# Now the Star is simply OFFERED in its tier, alongside the regulars, and
	# is exhausted when used exactly like they are. Set `star_holds_its_tier`
	# to true in Tuning.csv to put the old behaviour back.
	var star_holds := db.tune_bool("star_holds_its_tier", false)
	if star_holds and phase == player_star_tier:
		_enemy_pick_for_tier(phase)
		current_phase_index += 1
		start_next_draft_phase()
		return

	var choices_found := 0
	for unit in _all_units():
		if unit.is_enemy or unit.is_exhausted:
			continue
		if star_holds and unit.is_star_player:
			continue
		if unit.data != null and unit.data.get_tier_clean() == phase:
			create_card_for_unit(unit.data)
			choices_found += 1

	if choices_found == 0:
		print("[draft] No available Tier %s cards — skipping this phase." % phase)
		_enemy_pick_for_tier(phase)
		current_phase_index += 1
		start_next_draft_phase()
		return

	_offer_auto_pick()


func create_card_for_unit(data: PlayerData) -> void:
	var card := PLAYER_CARD_SCENE.instantiate() as PlayerCardUI
	card_container.add_child(card)
	card.setup_card(data)
	card.card_hovered.connect(_on_card_hovered)
	card.card_unhovered.connect(_on_card_unhovered)
	card.card_selected.connect(_on_card_selected)
	if data != null:
		offered_cards.append(data)

	if data != null and data.is_star():
		_flag_card_as_star(card)


## The same badge the unit wears on the pitch, in the corner of its selection
## card — so "this one is a Star" reads identically in both places, and swapping
## star_badge.png changes both at once.
func _flag_card_as_star(card: Control) -> void:
	var holder := Control.new()
	holder.name = "StarFlag"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	holder.offset_left = -40.0
	holder.offset_top = 4.0
	holder.offset_right = -4.0
	holder.offset_bottom = 40.0
	card.add_child(holder)

	var mark := StarBadge.make_marker(false, 32.0)
	mark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(mark)


func _on_card_hovered(data: PlayerData) -> void:
	for unit in _all_units():
		if not unit.is_enemy and unit.data == data:
			unit.set_highlight(true)

	# The stats window, above the card row, so you can see what you are
	# choosing between before you commit to one.
	if card_stats != null:
		card_stats.show_card(data, _card_top_centre(data))


func _on_card_unhovered(data: PlayerData) -> void:
	for unit in _all_units():
		if not unit.is_enemy and unit.data == data:
			unit.set_highlight(false)   # stays bright if is_playmaker

	if card_stats != null:
		card_stats.hide()


## The middle of the top edge of the card showing this card, in screen
## coordinates, so the window can sit directly above the one you are pointing
## at. Falls back to the middle of the card row if the card cannot be found.
func _card_top_centre(data: PlayerData) -> Vector2:
	for child in card_container.get_children():
		var card := child as Control
		if card == null:
			continue
		var shown = card.get("data")
		if shown == data:
			return Vector2(card.global_position.x + card.size.x * 0.5,
				card.global_position.y)

	return Vector2(card_container.global_position.x + card_container.size.x * 0.5,
		card_container.global_position.y)


# =============================================================
#  AUTO-PICK — sit back and watch
#
#  When AUTO is on (the toggle in the top-left, or the A key, or
#  `auto_pick` in Tuning.csv), the game chooses your card at every PLAY
#  MAKER and every Star swap. It waits `auto_pick_seconds` first so you can
#  still see who was on offer, and so it does not feel like the screen
#  flickered.
#
#  It picks the strongest card for the job: attack power when your side is
#  attacking this round, defence power when you are defending. That is a
#  deliberately simple rule — it is meant to be a watchable demo, not a
#  clever opponent.
# =============================================================

func _offer_auto_pick() -> void:
	if state == null or not MatchHUD.auto_pick_on(state):
		return
	_auto_pick_soon()


func _auto_pick_soon() -> void:
	var wait := db.tune_float("auto_pick_seconds", 0.9)
	if wait > 0.0:
		await get_tree().create_timer(wait).timeout

	# Things move on while we wait — you may have picked yourself, or turned
	# AUTO back off, or the whistle may have gone.
	if current_state != MatchState.DRAFTING:
		return
	if not MatchHUD.auto_pick_on(state):
		return
	if offered_cards.is_empty():
		return

	var choice := _best_offered_card()
	if choice == null:
		return
	print("[auto] Picked %s for you." % choice.player_name)
	_on_card_selected(choice)


## The strongest card on offer. Attack power while you are attacking, defence
## power while you are defending; a Star breaks a tie.
func _best_offered_card() -> PlayerData:
	var best: PlayerData = null
	var best_score := -INF

	for card in offered_cards:
		if card == null:
			continue
		var score := float(card.get_attack_power() if player_attacks_this_round
			else card.get_defense_power())
		if card.is_star():
			score += 0.5
		if score > best_score:
			best_score = score
			best = card

	return best


func _on_card_selected(selected_data: PlayerData) -> void:
	if card_stats != null:
		card_stats.hide()
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

	# Both swaps run side by side and neither is awaited by its caller, so the
	# count is what _on_draft_complete() waits on before restarting the clock.
	_substitutions_running += 1

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
		ball.drop()

	await star_unit.run_to(wing, 0.65)

	# Same pitch object, new card — swap it while it is off screen.
	star_unit.update_unit_data(new_star)
	star_unit.global_position = wing
	star_unit.is_playmaker = true
	star_unit.set_highlight(true)

	await star_unit.run_to(slot, 0.65)
	star_unit.set_home(slot)

	freeze_play(false)

	_substitutions_running = maxi(0, _substitutions_running - 1)
	substitution_finished.emit()


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
	# The same rule as your side: the Star is one of the choices, not a
	# permanent fixture. See the long note in start_next_draft_phase().
	var star_holds := db.tune_bool("star_holds_its_tier", false)
	if star_holds and tier_key == enemy_star_tier:
		return

	var choices: Array[PlayerUnit] = []
	for unit in _all_units():
		if not unit.is_enemy or unit.is_exhausted:
			continue
		if star_holds and unit.is_star_player:
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
		# Both Stars are still jogging on at this point. Wait for them, or the
		# clock and the ball start again while the pitch is one player short.
		# Polled rather than awaiting substitution_finished, so a substitution
		# that somehow never reports back cannot wedge the match — after the
		# guard time play restarts regardless.
		var waited := 0.0
		while _substitutions_running > 0 and waited < 6.0:
			await get_tree().process_frame
			waited += get_process_delta_time()

		if _draft_froze_play:
			_draft_froze_play = false
			freeze_play(false)

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

## The four cards that will fight this round, one per tier.
##
## THE PICK ALWAYS WINS. This used to check the Star's tier FIRST and drop in
## the Star, throwing away the card you had just chosen for that tier — which
## is exactly "the cards I pick are not the stats used in combat". The Star is
## now only a fallback, for when nothing was picked for a tier at all.
func build_lineup(picks: Array[PlayerData], star: PlayerData, star_tier: String) -> Array[PlayerData]:
	var lineup: Array[PlayerData] = []
	for t in ALL_TIERS:
		var found: PlayerData = null
		for p in picks:
			if p != null and p.get_tier_clean() == t:
				found = p
				break

		# Nothing chosen for this tier. That happens when `star_holds_its_tier`
		# is on and the tier belongs to the Star, or when a tier had no
		# available cards left to offer.
		if found == null and t == star_tier and star != null:
			found = star

		lineup.append(found)
	return lineup


func resolve_round() -> void:
	current_state = MatchState.AUTOBATTLE

	# THE PITCH COMES BACK TO LIFE HERE.
	#
	# The whistle stopped everyone for the "PLAY MAKER!" call and for the
	# picking, which is right — you cannot read a row of cards while the game
	# runs underneath it. But it used to stay stopped through the whole relay
	# as well, so the ball was passed around a field of statues.
	#
	# Now the players move for all of that. Only the BALL stays on rails:
	# scripted_possession means it holds whoever the script gave it to and can
	# be neither tackled nor intercepted, so the relay still shows exactly the
	# man who is about to duel — while everyone else runs, marks and shows.
	freeze_play(false)
	if ball != null:
		ball.scripted_possession = true

	var player_has_ball := player_attacks_this_round

	var player_lineup := build_lineup(round_player_picks, active_player_star, player_star_tier)
	var enemy_lineup := build_lineup(round_enemy_picks, active_enemy_star, enemy_star_tier)

	# Printed every round, on purpose. When a number on screen looks wrong,
	# this line in the Output panel is the shortest way to see whether the
	# card that fought is the card you chose.
	for i in ALL_TIERS.size():
		var mine_card: PlayerData = player_lineup[i]
		var their_card: PlayerData = enemy_lineup[i]
		print("  Tier %-3s  YOU %-26s atk %d / def %d   THEM %-26s atk %d / def %d" % [
			ALL_TIERS[i],
			mine_card.player_name if mine_card != null else "(nobody)",
			mine_card.get_attack_power() if mine_card != null else 0,
			mine_card.get_defense_power() if mine_card != null else 0,
			their_card.player_name if their_card != null else "(nobody)",
			their_card.get_attack_power() if their_card != null else 0,
			their_card.get_defense_power() if their_card != null else 0])

	round_ready_for_combat.emit(player_lineup, enemy_lineup)

	if not headless_combat:
		if ball != null:
			ball.scripted_possession = false
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

		# --- The relay: the ball is played up to THIS tier's attacker ---
		await deliver_ball_to_card(atk, attacker_is_enemy)

		# Numbers BEFORE this duel's abilities, so the cut-away can show them
		# changing when a buff lands.
		var atk_before := abilities.attack_power(atk, attacker_is_enemy)
		var def_before := abilities.defense_power(def, not attacker_is_enemy)

		# Abilities go on the stack first: lowest priority resolves first,
		# attacker breaks a tie. Only then are the numbers compared.
		abilities.resolve_duel_abilities(atk, attacker_is_enemy, def)

		var atk_power := abilities.attack_power(atk, attacker_is_enemy)
		var def_power := abilities.defense_power(def, not attacker_is_enemy)

		var attacker_wins := atk_power > def_power
		if atk_power == def_power:
			attacker_wins = ties_go_to_attacker

		# --- The cut-away, before the outcome is applied ---
		await show_duel_arena(ALL_TIERS[i], atk, def, attacker_is_enemy,
			atk_before, atk_power, def_before, def_power, attacker_wins)

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

		# Report the duel before anything else reacts to it, so a counter is
		# never one behind what is on screen.
		var my_unit := unit_for_card(mine, false)
		if attacker_wins == player_has_ball:
			_report("duel_won", _facts_for(my_unit))
		else:
			_report("duel_lost", _facts_for(my_unit))

		# A turnover is SHOWN, not just recorded: the beaten attacker tries to
		# find a team-mate and the winner reads it and steps in.
		if not attacker_wins:
			await _play_interception(atk, attacker_is_enemy, def, not attacker_is_enemy)

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


## A turnover, played as an interception instead of a hand-over.
##
## The beaten attacker does not pass to the man who just beat him — nobody
## does that. He looks for his OWN team-mate closest to the danger, plays it
## there, and the winner reads the pass and cuts in front of the receiver.
## The ball ends up in the same hands either way; it just gets there for a
## reason you can see.
func _play_interception(loser_card: PlayerData, loser_is_enemy: bool,
		winner_card: PlayerData, winner_is_enemy: bool) -> void:
	if ball == null:
		return

	var winner := unit_for_card(winner_card, winner_is_enemy)
	if winner == null:
		return

	var passer := unit_for_card(loser_card, loser_is_enemy)
	var receiver := _team_mate_nearest_to(loser_is_enemy, winner, passer)

	# Nobody to aim at (a one-man side, or the passer is off the pitch) — fall
	# back to the plain hand-over rather than skipping the beat entirely.
	if receiver == null:
		ball.deliver_to(winner)
		await ball.delivery_arrived
		return

	ball.intercept_pass(receiver, winner,
		db.tune_float("intercept_at_fraction", 0.55))

	# The leap is not awaited: the winner is travelling while the ball is, so
	# the two of them meet. run_to() drops them out of normal steering for the
	# duration and hands them back to it afterwards.
	winner.run_to(ball.steal_point(), db.tune_float("intercept_leap_seconds", 0.45))

	await ball.delivery_arrived
	var aimed_at := receiver.data.player_name if receiver.data != null else "a team-mate"
	print("  %s reads it and cuts out the pass to %s." % [winner_card.player_name, aimed_at])

	var beat := db.tune_float("intercept_beat_seconds", 0.3)
	if beat > 0.0:
		await get_tree().create_timer(beat).timeout


## The unit on `side_is_enemy` standing closest to `toward`, ignoring `exclude`.
## Used to pick the man a beaten attacker aims at — the one under most
## pressure, which is exactly why the pass gets read.
func _team_mate_nearest_to(side_is_enemy: bool, toward: PlayerUnit,
		exclude: PlayerUnit) -> PlayerUnit:
	if toward == null:
		return null

	var best: PlayerUnit = null
	var best_d := INF
	for unit in _all_units():
		if unit.is_enemy != side_is_enemy or unit == exclude:
			continue
		var d := unit.global_position.distance_to(toward.global_position)
		if d < best_d:
			best_d = d
			best = unit
	return best


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
		_end_surge()
		if ball != null:
			ball.scripted_possession = false
		round_resolved.emit(player_score, enemy_score)
		current_state = MatchState.PLAYING
		return

	var shooter := _find_shooter(shooter_is_player)

	# --- 1. THE BREAK, then the last winner carries it into range ---
	if shooter != null and ball != null:
		# Whoever won the Tier IV duel is about to shoot. Before the ball moves
		# at all, the whole of that side pushes up at the goal — so the relay
		# happens through players who are RUNNING, and the shot is the end of a
		# move you watched rather than something that teleports into place.
		#
		# This runs whichever way the last duel went. It was asked for on the
		# turnover (attacker loses at Tier IV), but a shot with no build-up
		# looks just as abrupt when the attacker holds, so both get it.
		_begin_surge(shooter.is_enemy)
		var lead := db.tune_float("surge_lead_seconds", 0.7)
		if lead > 0.0:
			await get_tree().create_timer(lead).timeout

		await deliver_ball_to_card(shooter.data, shooter.is_enemy)

		# They used to step a flat 25% of the way to the keeper, which from the
		# far half still left them shooting from about the halfway line. Now
		# they run to a fixed distance OFF THE GOAL LINE, so wherever the move
		# started the shot is taken from somewhere believable.
		var spot := _shooting_position(shooter, target_key)
		var run := shooter.global_position.distance_to(spot) \
			/ maxf(db.tune_float("shot_run_up_speed", 520.0), 1.0)
		await shooter.run_to(spot, clampf(run,
			db.tune_float("shot_run_up_min_seconds", 0.35),
			db.tune_float("shot_run_up_max_seconds", 1.3)))

	# --- 2. The shootout cut-away, showing the numbers BEFORE the shot ---
	if shootout != null:
		shootout.play_shot({
			"shooter_card": shooter.data if shooter != null else null,
			"shooter_is_player": shooter_is_player,
			"shot_power": shot_power,
			"keeper_data": keeper.data,
			"keeper_stamina": keeper.current_stamina,
			"keeper_max": keeper.max_stamina,
		})
		await shootout.view_closed

	# --- 3. Decide the outcome, THEN show it ---
	var stamina_before := keeper.current_stamina
	var scored := keeper.take_shot(shot_power)
	var stamina_spent := maxi(0, stamina_before - keeper.current_stamina)

	# Report the shot and, if your keeper stopped it, the save. Both carry
	# their numbers, so Stats.csv can count saves, or stamina, or saves by
	# class, without a line of code in here changing.
	#
	# ONLY YOUR SIDE IS COUNTED. Everything the game unlocks is about what
	# YOU did, so an enemy shot must not land in `shots` and their keeper's
	# save must not land in `saves`.
	if shooter_is_player:
		var shot_facts := _facts_for(shooter)
		shot_facts["power"] = str(shot_power)
		shot_facts["stamina"] = str(stamina_spent)
		shot_facts["result"] = "goal" if scored else "saved"
		_report("shot_taken", shot_facts)
	elif not scored:
		# They shot, your keeper kept it out.
		var save_facts: Dictionary = {}
		if active_player_star != null:
			save_facts["class"] = active_player_star.unit_type
		if keeper.data != null:
			save_facts["card"] = keeper.data.goalie_name
		save_facts["power"] = str(shot_power)
		save_facts["stamina"] = str(stamina_spent)
		_report("save_made", save_facts)

	print("  SHOT: %s (%s) fires %d power -> %s (keeper stamina now %d)" % [
		"You" if shooter_is_player else "Enemy",
		shooter.data.player_name if shooter != null and shooter.data != null else "unknown",
		shot_power, "GOAL" if scored else "saved", keeper.current_stamina])
	if scored:
		print("  GOAL!  %d - %d" % [player_score, enemy_score])

	# --- 4. Strike it on the pitch, with the keeper diving for it either way ---
	if ball != null:
		var goal_line := _goal_mouth(target_key)
		var aim: Vector2 = goal_line if scored else keeper.global_position
		ball.shoot(aim)
		keeper.dive_at(ball.global_position)
		await ball.shot_arrived

		# --- 5. The verdict, once the ball has actually got there ---
		await announce("GOAL!" if scored else "MISS",
			db.tune_float("verdict_seconds", 1.4))

		if scored:
			# Restart from the centre. The side that CONCEDED kicks off, and
			# target_key is exactly that side (it owns the beaten keeper).
			await get_tree().create_timer(db.tune_float("goal_pause_seconds", 0.7)).timeout
			ball.global_position = get_play_rect().get_center()
			give_ball_to(target_key)
		else:
			# --- 4. Saved: the keeper hoofs it upfield to their own side ---
			await get_tree().create_timer(db.tune_float("save_pause_seconds", 0.4)).timeout
			await _goal_kick(target_key)

	# The break is over, the ball comes off its rails, and everyone drifts back
	# to their own quarter under the usual zone pull. The players never stopped.
	_end_surge()
	if ball != null:
		ball.scripted_possession = false
	round_resolved.emit(player_score, enemy_score)
	current_state = MatchState.PLAYING


## After a save: the keeper launches it to whichever team-mate is furthest
## upfield, which puts the ball back in open play on the far side of the pitch.
## THE GOAL KICK.
##
## It used to find whoever was furthest up the pitch, which is nearly always a
## Tier IV — the far end of the field. The ball flew the whole length and the
## restart felt like a punt into nothing.
##
## Now it aims at a chosen tier, `goal_kick_tier` in Tuning.csv (III by
## default), and only falls back to "whoever is furthest forward" if nobody of
## that tier is on the pitch. Set it to "II" for a shorter kick or "IV" to get
## the old behaviour back — no code.
func _goal_kick(keeper_is_enemy: bool) -> void:
	var wanted := db.tune_text("goal_kick_tier", "III").strip_edges()

	var best: PlayerUnit = null
	var best_reach := -INF
	var in_tier: Array[PlayerUnit] = []

	for unit in _all_units():
		if unit.is_enemy != keeper_is_enemy or unit.data == null:
			continue
		if wanted != "" and unit.data.get_tier_clean() == wanted:
			in_tier.append(unit)
		var reach: float = unit.global_position.x * (-1.0 if keeper_is_enemy else 1.0)
		if reach > best_reach:
			best_reach = reach
			best = unit

	# Of the right tier, take the one furthest forward — the natural outlet.
	if not in_tier.is_empty():
		var pick: PlayerUnit = in_tier[0]
		var pick_reach := -INF
		for unit in in_tier:
			var reach2: float = unit.global_position.x * (-1.0 if keeper_is_enemy else 1.0)
			if reach2 > pick_reach:
				pick_reach = reach2
				pick = unit
		best = pick
	elif wanted != "":
		print("  No Tier %s on the pitch — kicking to whoever is furthest forward." % wanted)

	if best == null or ball == null:
		return
	print("  Goal kick to %s (Tier %s)." % [
		best.data.player_name, best.data.get_tier_clean()])
	ball.deliver_to(best)
	await ball.delivery_arrived


## Open the duel cut-away for one tier and wait for it to finish.
## LEFT is always your side and RIGHT always the enemy, whichever attacks.
func show_duel_arena(tier: String, atk: PlayerData, def: PlayerData,
		attacker_is_enemy: bool, atk_before: int, atk_after: int,
		def_before: int, def_after: int, attacker_wins: bool) -> void:
	if duel_arena == null:
		return

	var attacker_side := {
		"card": atk,
		"is_attacker": true,
		"priority": atk.get_ability_priority(),
		"power_before": atk_before,
		"power_after": atk_after,
		"ability": db.get_ability(atk.active_attack_ability()),
		"wins": attacker_wins,
	}
	var defender_side := {
		"card": def,
		"is_attacker": false,
		"priority": def.get_ability_priority(),
		"power_before": def_before,
		"power_after": def_after,
		"ability": db.get_ability(def.active_defend_ability()),
		"wins": not attacker_wins,
	}

	duel_arena.play_duel({
		"tier": tier,
		"left": defender_side if attacker_is_enemy else attacker_side,
		"right": attacker_side if attacker_is_enemy else defender_side,
	})
	await duel_arena.duel_finished


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


## Where the shooter stands to strike it: a set distance out from the goal
## line, swung round toward the middle of the goal.
##
## The distance is a FRACTION of the pitch rather than a pixel count, so it
## reads the same whether your field art is 1280 wide or 4000.
func _shooting_position(shooter: PlayerUnit, keeper_is_enemy: bool) -> Vector2:
	var rect := get_play_rect()
	var mouth := _goal_mouth(keeper_is_enemy)

	var out := maxf(
		rect.size.x * db.tune_float("shot_distance_fraction", 0.20),
		db.tune_float("shot_distance_min_pixels", 120.0))

	# The enemy's goal is on the right, so their attacker stands to the LEFT
	# of it; the home goal is on the left, so its attacker stands to the right.
	var x: float = mouth.x - out if keeper_is_enemy else mouth.x + out

	# Swing toward the middle of the goal without going all the way, so shots
	# keep some of the angle the move arrived at.
	var y := lerpf(shooter.global_position.y, mouth.y,
		db.tune_float("shot_centring", 0.6))

	# Never send them off the pitch, and never send them BACKWARDS past where
	# they already are — a striker does not retreat to shoot.
	var spot := Vector2(
		clampf(x, rect.position.x, rect.end.x),
		clampf(y, rect.position.y, rect.end.y))

	var already_closer := false
	if keeper_is_enemy:
		already_closer = shooter.global_position.x > spot.x
	else:
		already_closer = shooter.global_position.x < spot.x

	if already_closer:
		spot.x = shooter.global_position.x

	return spot


## A point just past the keeper, on the goal line.
func _goal_mouth(keeper_is_enemy: bool) -> Vector2:
	var rect := get_play_rect()
	var keeper: GoalieUnit = goalies.get(keeper_is_enemy)
	var y := keeper.global_position.y if keeper != null else rect.get_center().y
	var x := rect.end.x + 40.0 if keeper_is_enemy else rect.position.x - 40.0
	return Vector2(x, y)
