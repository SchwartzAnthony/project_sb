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
#    "STAR PLAYER SWITCH"     : end of cycle. Active Star goes inactive, you pick
#                     from the remaining Stars, all 9 regulars reset.
#    Total          : 3 cycles = 9 PLAY MAKERs + 2 STAR PLAYER SWITCHes = 11 pauses.
# =============================================================

signal round_ready_for_combat(player_lineup: Array, enemy_lineup: Array)
signal round_resolved(player_score: int, enemy_score: int)
signal match_ended(player_score: int, enemy_score: int)
## One STAR PLAYER SWITCH Star substitution has finished jogging on.
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
## ============ ROCK, PAPER, SCISSORS IS GONE ============
##
## It is a number guess now — both sides call one to ten, a coin lands on
## one, and whoever called closer chooses attack or defend. See
## coin_clash.gd, which answers to exactly the same five things the old
## screen did, so nothing else in this file had to change.
##
## The old rps_clash.gd and rps_clash.tscn are still in the project and still
## work. Put `use_coin_clash` to false in Tuning.csv to go back to them.
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

## The row from MatchModes.csv this match is running as. Never empty —
## MatchMode.current() falls back to the season match.
var match_mode: Dictionary = {}

## True in a mode whose Timer is 0. There is no final whistle on the clock;
## the match ends when the last round has been played.
var no_clock: bool = false

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
var rps: Node = null
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

## The Teams.csv row the opposition is fielding, or {} for "any cards of the
## class". This is what makes a fixture a fixture rather than a lucky dip.
var enemy_team: Dictionary = {}

## A SIDE MADE UP ON THE SPOT, for a friendly. Null for a season fixture.
##
## "Play a match" from the base is not a league game: it is a match against a
## team assembled out of the whole collection at roughly YOUR level. The
## level is worked out by team_level.gd and the side is built by
## scratch_team.gd; this is where the result is parked so that
## _choose_enemy_team() and load_roster_by_type() can both see it.
var scratch_opponent: ScratchTeam = null

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

## Escape. Speed, AUTO, and a way out that costs you the match.
var pause_menu: PauseMenu = null

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
## never freezes, and an unmatched thaw there would leave the next STAR PLAYER SWITCH
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
## And how far off his shoulder, so a marker is never level with his man.
var mark_shoulder: float = 74.0
## How far toward his man a defender actually commits. 1 = man-marking and
## glued pairs; 0.5 = zonal, the man is a lean on top of his own position.
var mark_commitment: float = 0.5
## How far past his man the ball must travel before a marker changes shoulder.
## Small numbers flip the marker back and forth and read as a shake.
var mark_swap_gap: float = 90.0
## How far a marker keeps shifting about on top of that. Never parked.
var mark_drift: float = 26.0
## How far an attacker breaks off its marker to show for the ball.
var open_spread: float = 230.0
## How far forward a player breaks when showing for the pass.
var open_break: float = 120.0
## And how far toward its own touchline. Using the width of the pitch.
var open_width: float = 150.0

# --- Moving about with nothing to do ---
## How far a waiting player wanders from its slot, in pixels.
var drift_reach: float = 110.0
## How quickly. Small is slow — this is a walk, not a shuffle.
var drift_pace: float = 0.17
## How far a waiting side leans toward the ball's end of the pitch, 0..1.
var drift_ball_lean: float = 0.16
## How much of the way toward the ball the WHOLE SHAPE slides. The reason a
## player off the ball is moving at all.
var block_follow: float = 0.34
## How much of that shift is forward and back rather than across. A line
## shifts sideways far more readily than it changes its depth.
var block_depth_share: float = 0.45
## How much of the personal sway is up and down rather than across. Small:
## the up-and-down was the part that read as bobbing.
var drift_updown: float = 0.22
## How long everybody converges on the man a goal kick is aimed at.
var goal_kick_converge_seconds: float = 2.6
## How wide a surging side fans out instead of piling onto the goal mouth.
var surge_spread: float = 210.0
## How many of a breaking side actually run into the box. The rest push up
## and hold the shape.
var surge_runners: int = 3
## How much of the runners' advance the players holding the shape make.
var surge_rest_share: float = 0.30
## How many defenders close the ball down while the other side breaks. The
## rest drop off and keep their spacing.
var recover_closers: int = 2
## The smallest gap a marker may end up at from his man's exact height, as a
## share of `mark_shoulder`. The last word against a pair standing level.
var mark_level_floor: float = 0.55
## How far a player may wander from their slot, as a fraction of their roam
## band. The leash used to be a flat pixel count that was smaller than a
## quarter, which caged everybody underneath the zones.
var leash_band_fraction: float = 0.45
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

## ============ THE BALL IS DEAD: EVERYBODY HOME ============
##
## True from the whistle that follows a shot until play actually restarts —
## the keeper's kick, or the kick-off after a goal.
##
## WHY IT HAD TO BE ITS OWN STATE. Once the keeper has the ball, the ordinary
## rules say "the ball is in my quarter and the other side has it, go and win
## it" — so the far side's Tier I and Tier IV both set off for the keeper and
## stood over him. That is not a thing that happens in football, and it looked
## exactly as odd as it sounds.
##
## While this is true nothing chases, nothing presses and nothing marks: every
## outfield player walks back to their own starting position and waits there,
## and the keeper is left alone with the ball. The moment it is kicked this
## goes back to false and the ordinary rules take over mid-stride.
var restart_hold: bool = false

## The one player allowed to move during a restart hold: whoever the keeper is
## kicking to. Without this exception the hold would have to be lifted before
## the kick, and lifting it before the kick is what put two players back on
## top of the keeper.
var restart_receiver: PlayerUnit = null
## ============ EVERYBODY GOES WITH THE KICK ============
## The man a goal kick is aimed at, and the moment the whole pitch stops
## converging on him. Both sides break toward him — his own to support, the
## other to intercept — for `goal_kick_converge_seconds`, then the ordinary
## rules take over again. A window rather than a state, so nothing has to
## remember to switch it off.
var converge_on: PlayerUnit = null
var converge_until: float = -1.0

## The team sheet and START gate in front of the kick-off. Freed once START
## is pressed; null for the rest of the match.
var _sheet: TeamSheet = null

## How briskly they walk home at a restart, as a multiple of walk_speed. You
## asked for no sprinting; 1.6 is a purposeful walk rather than a jog.
## `restart_walk_boost` in Tuning.csv.
var restart_walk_boost: float = 1.6

## How much of the remaining distance to goal a surging unit closes.
## 0 = nobody moves, 1 = everyone piles onto the goal line.
var surge_advance: float = 0.45
## How much a surging unit converges on the goal mouth. 1 = everyone funnels
## into the middle, 0 = they keep their lane and just run forward.
var surge_centring: float = 0.35
## Free-running seconds, used only for idle drift. Unlike the match clock this
## keeps ticking while play is stopped.
var _anim_clock: float = 0.0
## The ball's x, eased. What a waiting line leans on, so a relay hop moves the
## shape smoothly instead of jolting it. INF until the first frame with a ball.
var _ball_lean_x: float = INF

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

# =============================================================
#  DISCIPLINE — the match's half of the foul system
#
#  The rules live in src/core/foul_book.gd and the numbers in data/Fouls.csv.
#  These three are the only things the match itself has to remember.
# =============================================================

## THE HOLES IN THE LADDER. "enemy|III" -> [3] means the away side's Tier III
## has lost its 3-power man to a red card and needs a stand-in.
var _ladder_holes: Dictionary = {}

## A stand-in card -> THE UNIT THAT PLAYS HIM.
##
## A stand-in has no body of its own: he is a survivor of the same tier
## playing out of position, so the card in the draft row and the man who runs
## about the pitch are two different objects. Everything else in this file
## finds a unit from a card through unit_for_card(), which asks here.
var _stand_in_bodies: Dictionary = {}

## Bookings and sendings-off this match, for the full-time line.
var _cards_shown: Array[Dictionary] = []
## True only between "PLAY MAKER!" and its combat. Kickoff and STAR PLAYER SWITCH drafts
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

	# THE SKIN. Every menu screen gets this from MenuEscape.install(); the
	# match has its own pause menu and never calls it, which is exactly the
	# kind of gap that left the pitch looking like a different game from the
	# menus in front of it. One line.
	ThemeBook.dress(get_tree())

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
	# The mode comes AFTER tuning, so a Quick Match overrides the defaults
	# rather than being overwritten by them, and BEFORE the fixture, so a
	# mode that does not record the season never looks one up.
	_apply_match_mode()
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
	spawn_pause_menu()
	_place_card_row()

	# A match is not somewhere Back should ever return you to, so the trail
	# of screens is wiped at kick-off. Without this, Back on the season table
	# would walk you into the game you have just finished.
	ScenePaths.clear_trail(get_tree())

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


## ============ WHERE THE CARDS SIT ============
##
## The row of cards you choose from used to be wherever the CardContainer
## node happened to be anchored in main_scene.tscn, which was along the
## bottom edge — so on a tall window the cards were half off the screen and
## nowhere near the thing they were about.
##
## It is placed from here now, from two rows of Tuning.csv:
##
##     card_row_x   0 = hard left, 0.5 = middle, 1 = hard right
##     card_row_y   0 = the top,   0.5 = middle, 1 = the bottom
##
## Both are fractions of the window, so it lands in the same place whatever
## the resolution, and the row is CENTRED on that point rather than starting
## at it. There is nothing to drag in the editor any more — change the
## numbers, press F5.
func _place_card_row() -> void:
	if card_container == null:
		return

	var where := Vector2(
		db.tune_float("card_row_x", 0.5),
		db.tune_float("card_row_y", 0.5))

	card_container.add_theme_constant_override("separation",
		db.tune_int("card_row_gap", 18))
	card_container.alignment = BoxContainer.ALIGNMENT_CENTER

	# ANCHORED, NOT POSITIONED. A fixed position would be wrong the moment
	# the window is resized; anchors move with it. The box is given the full
	# width so the row can centre itself inside it.
	card_container.set_anchors_preset(Control.PRESET_TOP_WIDE, true)
	card_container.anchor_top = where.y
	card_container.anchor_bottom = where.y
	card_container.anchor_left = 0.0
	card_container.anchor_right = 1.0

	var card_box := PlayerCardUI.card_size()
	card_container.offset_left = 0.0
	card_container.offset_right = 0.0
	# Centred ON the line rather than hanging off it.
	card_container.offset_top = -card_box.y * 0.5
	card_container.offset_bottom = card_box.y * 0.5

	# card_row_x nudges the whole row sideways from the middle.
	var slide := (where.x - 0.5) * 2.0
	card_container.offset_left += slide * 200.0
	card_container.offset_right += slide * 200.0

	print("[cards] Card row centred at %.2f, %.2f of the window (card_row_x / card_row_y in Tuning.csv)."
		% [where.x, where.y])


func _process(delta: float) -> void:
	# Before the early return: the camera has to keep easing back out to the
	# wide view during the draft and at full time, which are exactly the
	# moments this function used to stop doing anything.
	_drive_camera()

	if current_state != MatchState.PLAYING:
		return

	# THE CLOCK STOPS FOR A DEAD BALL. It is already stopped for the shot and
	# the draft, because those are not the PLAYING state; this covers the
	# restart, which is. The clock starts again the moment the keeper kicks.
	if restart_hold:
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
		# STAR PLAYER SWITCH only in a mode that rotates your Stars. A Quick Match gives
		# you one Star for the whole run, so there is nobody to bring on.
		var rotates := bool(match_mode.get("rotation", true))
		if rotates and rounds_this_cycle >= ROUNDS_PER_CYCLE and current_cycle < TOTAL_CYCLES:
			trigger_hold_up_event()
		elif rounds_this_cycle < ROUNDS_PER_CYCLE:
			trigger_playmaker_event()
		return

	# --- The final whistle in a no-clock mode ---
	#
	# There is no 90th minute to reach, so the match ends when the last round
	# has been played and the pitch has gone quiet again. Checked here rather
	# than in _on_draft_complete() so the ball still has its moment: the round
	# plays out, and full time comes at the next idle frame.
	if no_clock and next_event_index >= event_schedule.size():
		_full_time()


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

	# THE SAME EVENT FEEDS THE SOUND. Everything the match reports — a goal,
	# a save, a duel, a brew — already comes through here with its facts, so
	# one line gives Audio.csv every match moment at once, including any you
	# add later.
	AudioDirector.fire(get_tree(), event, facts, state)


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

	# ============ A SMOOTHED BALL POSITION FOR THE LINE TO LEAN ON ============
	#
	# The waiting side leans toward the ball's end of the pitch — see
	# _drift_point(). It cannot lean on the ball's REAL position, because
	# during a relay the ball is handed from player to player and jumps
	# hundreds of pixels between one frame and the next. Every waiting player
	# would about-turn at every hop, which is the whole side twitching, and it
	# is exactly the sort of shake this round is supposed to be removing.
	#
	# So it eases toward the ball instead: the line drifts up and back the way
	# a real one does, and a hop in the ball is a lean rather than a jolt.
	if ball != null and is_instance_valid(ball):
		if is_inf(_ball_lean_x):
			_ball_lean_x = ball.global_position.x
		else:
			_ball_lean_x = lerpf(_ball_lean_x, ball.global_position.x,
				clampf(delta * 1.2, 0.0, 1.0))

	# The quarters brighten while you are choosing and fade back once play
	# restarts — loud exactly when they are useful.
	if zone_overlay != null:
		zone_overlay.set_focused(current_state == MatchState.DRAFTING)

	# The ball is fenced into midfield for all of the waiting play and freed
	# the moment a PLAY MAKER starts resolving. See _ball_corridor().
	if ball != null:
		ball.set_corridor(_ball_corridor(), current_state == MatchState.PLAYING)

	_move_the_scenery()
	_assign_roles()


func _assign_roles() -> void:
	if ball == null or zones == null:
		return
	var units := _all_units()
	if units.is_empty():
		return

	# THE BALL IS DEAD — see restart_hold. Everybody walks home and nobody
	# goes near the keeper. This is checked before anything else because it
	# outranks every other rule, including the break.
	if restart_hold:
		var slack := maxf(10.0, db.tune_float("restart_home_slack", 70.0))
		for unit in units:
			if unit == restart_receiver and ball != null:
				# The man the goal kick is aimed at. He may come to meet it.
				unit.set_role(PlayerUnit.Role.RECEIVE, ball.global_position,
					unit.chase_speed)
				continue
			# ============ HOME, THEN WANDER — ONCE ============
			#
			# Walking to a fixed point and then standing on it for two seconds
			# is eleven statues waiting for a whistle. Once a player is back in
			# their own area they are given the ordinary wandering point
			# instead, so the pitch is alive while the keeper has the ball —
			# they are just not allowed to come and take it off him.
			#
			# THE `settled` FLAG IS THE IMPORTANT PART, and leaving it out cost
			# me an afternoon. Asking "am I within `slack` of home" every frame
			# is a switch that flips both ways: a player arrives, is handed a
			# wandering point three hundred pixels away, walks toward it, leaves
			# the slack circle, is sent home again, arrives, is handed another
			# wandering point... and so on, sixty times a second, for the whole
			# restart. That is not a wander, it is a player vibrating on the
			# edge of a circle.
			#
			# Once home, they STAY in wandering mode until the next restart.
			if not unit.restart_settled \
					and unit.global_position.distance_to(unit.home_position) <= slack:
				unit.restart_settled = true
			if unit.restart_settled:
				unit.set_role(PlayerUnit.Role.HOLD, _drift_point(unit), unit.walk_speed)
			else:
				unit.set_role(PlayerUnit.Role.HOLD, unit.home_position,
					unit.walk_speed * restart_walk_boost)
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

		# ============ THE GOAL KICK GOES UP AND EVERYBODY GOES WITH IT ============
		#
		# For a couple of seconds after the keeper launches one, the whole
		# pitch breaks toward the man it is aimed at — his side to support
		# him, theirs to get there first — instead of standing and watching
		# the ball travel. See _goal_kick().
		var converge := _converge_target(unit)
		if converge != Vector2.INF:
			unit.set_role(PlayerUnit.Role.BALL, converge, unit.chase_speed)
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
		# `claims_x`, not `contains_x`. The roam band is 60% of the pitch, so
		# asking it "is this ball in my territory" meant a ball in the centre
		# circle belonged to four Tiers at once and six players set off for it.
		# The claim band is a third of the pitch and it is a different question
		# — see pitch_zones.gd.
		var mine_to_win := side != unit_side and unit.steal_cooldown <= 0.0 \
			and zones.claims_x(tier, unit.is_enemy, ball.global_position) \
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


## ============ WHERE ONE PLAYER RUNS DURING A GOAL KICK ============
##
## Vector2.INF means "the window is shut, carry on as normal" — a sentinel
## rather than a second flag to keep in step.
##
## They do not all run at the same square metre, which would be the clumping
## problem again in a new hat. The man it is aimed at is the CENTRE and
## everyone takes a place around him: his own side spread out behind and
## beside him to receive a knock-down, the other side in front of him between
## the ball and their goal.
func _converge_target(unit: PlayerUnit) -> Vector2:
	if converge_on == null or not is_instance_valid(converge_on):
		return Vector2.INF
	if _anim_clock > converge_until:
		converge_on = null
		return Vector2.INF
	if unit == converge_on:
		return Vector2.INF

	var at := converge_on.global_position
	var mine := unit.is_enemy == converge_on.is_enemy
	# Their side gets between him and the goal he is running at; his side
	# comes to support from behind and beside.
	var forward := 1.0 if not converge_on.is_enemy else -1.0
	var along := (26.0 if mine else 74.0) * (-forward if mine else forward)

	# A fan, so ten people arriving do not arrive on one spot. Each player
	# keeps their own slice of the circle for the whole window.
	var slice := float(int(unit.get_instance_id()) % 7) / 7.0 * TAU
	var ring := 86.0 + float(int(unit.get_instance_id()) % 3) * 44.0
	var spot := at + Vector2(along, 0.0) + Vector2(cos(slice), sin(slice)) * ring
	return unit.leash_point(spot)


## ============ MARKING SOMEBODY WITHOUT STANDING ON THEM ============
##
## This is what made the two sides look glued together, and it was one line:
## the marker stood `mark_distance` toward its own goal from its man, measured
## along a vector from the man to a point AT THE MAN'S OWN HEIGHT. That vector
## is perfectly horizontal, so the marker parked itself at exactly the man's
## eye level, every frame, for the whole match. Twenty-two players in eleven
## perfect horizontal pairs.
##
## A real defender stands GOAL-SIDE and OFF ONE SHOULDER, and never stops
## adjusting. So now:
##
##   * goal-side by `mark_distance` as before,
##   * plus a sideways offset of its own, so the pair is never level,
##   * plus a slow personal drift, so nobody is ever parked,
##   * and the shoulder they stand off is decided by where the BALL is, which
##     means the marker shifts as play moves — the thing that reads as
##     defending rather than as standing.
func _mark_point(unit: PlayerUnit) -> Vector2:
	var man := unit.mark_target
	if man == null or not is_instance_valid(man):
		return _drift_point(unit)

	var rect := get_play_rect()
	var own_goal_x: float = rect.position.x if not unit.is_enemy else rect.end.x
	var goal_side := signf(own_goal_x - man.global_position.x)

	# ---- which shoulder ----
	#
	# The one the ball is on, so the defender stands between his man and the
	# play. It is REMEMBERED on the unit and only changed once the ball is
	# clearly on the other side (`mark_swap_gap`). Worked out fresh every
	# frame, a ball drifting across the marked man's exact height flips the
	# side sixty times a second and throws the marker back and forth — a shake
	# of my own making.
	if is_zero_approx(unit.mark_side):
		unit.mark_side = 1.0 if (int(unit.get_instance_id()) % 2 == 0) else -1.0
	if ball != null and is_instance_valid(ball):
		var above := ball.global_position.y - man.global_position.y
		if absf(above) > mark_swap_gap and not is_equal_approx(signf(above), unit.mark_side):
			unit.mark_side = signf(above)
	var shoulder := unit.mark_side

	var phase := float(unit.get_instance_id() % 100) * 0.37
	var spot := man.global_position
	spot.x += goal_side * mark_distance
	spot.y += shoulder * mark_shoulder

	# ============ MARKING A ZONE, NOT A MAN ============
	#
	# `mark_commitment` is how far from their own position toward their man a
	# defender actually goes. At 1.0 they follow him everywhere, which is
	# where the glued pairs came from: two players locked together wandering
	# the pitch as one object. At 0.5 the defender's OWN slot is still the
	# bigger half of the decision and the man is a lean — which is zonal
	# marking, and what an autobattler at this zoom should be showing.
	spot = unit.home_position.lerp(spot, clampf(mark_commitment, 0.0, 1.0))

	# Never parked: a slow wander on top of the marking spot, wider across
	# than up and down so it does not fight the shoulder offset.
	spot += Vector2(
		sin(_anim_clock * 0.31 + phase) * mark_drift,
		cos(_anim_clock * 0.23 + phase) * mark_drift * 0.45)
	return unit.leash_point(_never_level(spot, man.global_position, unit.mark_side))


## ============ AND NEVER, EVER DEAD LEVEL ============
##
## "Don't have them be this parallel to each other."
##
## Every rule above pushes a marker off his man's shoulder, and every one of
## them is a lerp or a sum, so every one of them can land back on nought.
## Commit half way toward a man who is a shoulder's width above you and you
## are half a shoulder above him; average that with a drift that happens to be
## pointing down and you are level with him again. Not often — but on a pitch
## of twenty-two, often enough that there is always a pair of them somewhere,
## and a pair standing dead level is the thing that reads as glued.
##
## So the last word belongs to a floor: if a marker has ended up within
## `least` pixels of his man's exact height, he is moved out to `least` on the
## shoulder he had already chosen. It costs nothing when the offsets did their
## job, which is nearly always.
func _never_level(spot: Vector2, man: Vector2, side: float) -> Vector2:
	var least := mark_shoulder * mark_level_floor
	if least <= 0.0:
		return spot
	var gap := spot.y - man.y
	if absf(gap) >= least:
		return spot
	var push := signf(gap) if not is_zero_approx(gap) else signf(side)
	if is_zero_approx(push):
		push = 1.0
	return Vector2(spot.x, man.y + push * least)


## ============ SHOWING FOR THE PASS ============
##
## Get off whoever is nearest, break the way your side is attacking, and — the
## part that was missing — GO WIDE. Nobody ever went near a touchline because
## every target was clamped into a narrow band and the only offset here was 45
## pixels forward. A side that never uses the width of the pitch plays every
## move through the middle, which is exactly what it looked like.
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

	# Forward, the way this side attacks.
	spot.x += (1.0 if not unit.is_enemy else -1.0) * open_break

	# AND WIDE. Whichever touchline this player is already nearer, pushed
	# toward it — so a move has somebody on the wing to find.
	var play := get_play_rect()
	var middle := play.position.y + play.size.y * 0.5
	var out := signf(unit.home_position.y - middle)
	if is_zero_approx(out):
		out = 1.0 if int(unit.get_instance_id()) % 2 == 0 else -1.0
	spot.y += out * open_width

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

	# ============ NOT EVERYBODY RUNS INTO THE BOX ============
	#
	# "Don't clump everyone together when the Tier IV is about to shoot, that
	# is super unnatural."
	#
	# It was, and the reason was that the break had one rule for all ten: every
	# player on the scoring side closed the same fraction of the distance to
	# the same goal mouth. Ten people converging on one point is a heap however
	# much you fan it out afterwards.
	#
	# A real side breaking has two jobs going at once:
	#
	#   THE RUNNERS   the few nearest players attack the box, and they attack
	#                 DIFFERENT PARTS of it — near post, far post, the spot,
	#                 the edge for the cut-back. Each one has a station of its
	#                 own and no two share one.
	#   THE REST      push up to support and hold their shape. They do not
	#                 follow the ball into the area; they are the reason there
	#                 is somebody to pass back to.
	#
	# `surge_runners` is how many go. Three is a striker and two arriving.
	var station := _surge_station(unit)
	var middle := rect.position.y + rect.size.y * 0.5
	var spot := Vector2.ZERO

	if station >= 0:
		# ---- A RUNNER. Its own station around the box, nobody else's. ----
		#
		# Measured off the goal mouth: across the face of the goal by
		# `surge_spread` and back off it by a share of the same, so the four
		# stations make an arc rather than a line.
		var arc: Array[Vector2] = [
			Vector2(0.06, -0.62),   # near post
			Vector2(0.02, 0.64),    # far post
			Vector2(0.16, 0.00),    # the penalty spot
			Vector2(0.30, -0.30),   # the edge, for the cut-back
			Vector2(0.30, 0.34),    # and the other side of it
		]
		var pick: Vector2 = arc[station % arc.size()]
		var forward := -1.0 if not unit.is_enemy else 1.0
		spot = Vector2(
			mouth.x + forward * (edge * 0.4 + rect.size.x * pick.x),
			mouth.y + pick.y * surge_spread * 1.35)
	else:
		# ---- THE REST. Push the line up; keep the lane you are in. ----
		#
		# A quarter of the advance the runners make and NO centring at all, so
		# the shape behind the ball stays a shape.
		spot = Vector2(
			lerpf(unit.home_position.x, line_x, surge_advance * surge_rest_share),
			unit.home_position.y)
		# The line squeezes toward the middle a little, the way a side does
		# when it commits — but only a little, and out of its own lane.
		spot.y = lerpf(spot.y, middle, surge_centring * 0.35)

	# A slow shuffle on top, so a waiting forward is not a statue in the box.
	var phase := float(unit.get_instance_id() % 100) * 0.37
	spot += Vector2(
		sin(_anim_clock * 0.5 + phase) * 28.0,
		cos(_anim_clock * 0.41 + phase) * 22.0)

	return Vector2(
		clampf(spot.x, rect.position.x + 20.0, rect.end.x - 20.0),
		clampf(spot.y, rect.position.y + 24.0, rect.end.y - 24.0))


## Which station around the box this player is running to, or -1 for "you are
## not one of the runners, hold the shape".
##
## Worked out by ORDER OF NEARNESS TO THE GOAL, and worked out fresh, so the
## players who were already furthest forward are the ones who go — which is
## what makes the front players the ones in the box and the back players the
## ones holding. It is stable while the break lasts because their positions
## barely change relative to each other over two seconds.
func _surge_station(unit: PlayerUnit) -> int:
	var forward := 1.0 if not unit.is_enemy else -1.0
	var ahead: Array[PlayerUnit] = []
	for other in _all_units():
		if other.is_enemy != unit.is_enemy:
			continue
		ahead.append(other)
	ahead.sort_custom(func(a: PlayerUnit, b: PlayerUnit) -> bool:
		return a.global_position.x * forward > b.global_position.x * forward)
	var place := ahead.find(unit)
	if place < 0 or place >= maxi(0, surge_runners):
		return -1
	return place


## Where a defender drops back to while the other side breaks: goal-side of
## his man, and deliberately NOT leashed to his quarter, so he can retreat the
## length of the pitch with the attack instead of being pinned to his post.
func _recover_point(unit: PlayerUnit) -> Vector2:
	var rect := get_play_rect()
	var own_goal_x: float = rect.position.x if not unit.is_enemy else rect.end.x

	# ============ TWO OF THEM GO, THE REST DROP OFF ============
	#
	# Every defender used to be sent to a point `mark_distance` goal-side of
	# his man, dead level with him and with no give in it at all — so the
	# instant a break started, the whole defence snapped into pairs with the
	# whole attack. It was the glued look at its very worst, at the one moment
	# you are certain to be watching.
	#
	# A defence under a break does what a defence does: the nearest one or two
	# go and close the ball down, everybody else drops off, stays goal-side,
	# and holds the distance between them.
	if _is_closest_to_ball(unit, recover_closers):
		return ball.arrival_point() if ball != null and is_instance_valid(ball) \
			else unit.home_position

	var man := unit.mark_target
	if man == null or not is_instance_valid(man):
		# Nobody to track — fall back toward your own goal and hold the line.
		return Vector2(
			lerpf(unit.home_position.x, own_goal_x, surge_advance * 0.6),
			unit.home_position.y)

	# Goal-side of the man AND off one shoulder, and only `mark_commitment` of
	# the way there from where this defender already belongs — the same zonal
	# rule the ordinary marking uses, rather than a second, stricter one that
	# only comes out when it shows most.
	var goal_side := signf(own_goal_x - man.global_position.x)
	if is_zero_approx(unit.mark_side):
		unit.mark_side = 1.0 if (int(unit.get_instance_id()) % 2 == 0) else -1.0
	var spot := man.global_position
	spot.x += goal_side * mark_distance
	spot.y += unit.mark_side * mark_shoulder
	# Drop TOWARD THE OWN GOAL, not toward the slot: a defence under pressure
	# retreats, it does not hold its kick-off line.
	var dropped := Vector2(
		lerpf(unit.home_position.x, own_goal_x, surge_advance * 0.5),
		unit.home_position.y)
	spot = dropped.lerp(spot, clampf(mark_commitment, 0.0, 1.0))
	spot = _never_level(spot, man.global_position, unit.mark_side)
	return Vector2(
		clampf(spot.x, rect.position.x + 20.0, rect.end.x - 20.0),
		clampf(spot.y, rect.position.y + 24.0, rect.end.y - 24.0))


## Is this unit one of the `how_many` on its side nearest the ball? Used to
## decide who goes and who holds, in the two places where "everybody goes"
## turned into a heap.
func _is_closest_to_ball(unit: PlayerUnit, how_many: int) -> bool:
	if how_many <= 0 or ball == null or not is_instance_valid(ball):
		return false
	var at := ball.arrival_point()
	var mine: Array[PlayerUnit] = []
	for other in _all_units():
		if other.is_enemy == unit.is_enemy:
			mine.append(other)
	mine.sort_custom(func(a: PlayerUnit, b: PlayerUnit) -> bool:
		return a.global_position.distance_to(at) < b.global_position.distance_to(at))
	var place := mine.find(unit)
	return place >= 0 and place < how_many


## Called when the last duel is settled. `side_is_enemy` is whoever won it and
## is about to shoot.
func _begin_surge(side_is_enemy: bool) -> void:
	attack_surge_side = 1 if side_is_enemy else 0
	print("  The break is on — %s push up." % ("they" if side_is_enemy else "you"))


func _end_surge() -> void:
	attack_surge_side = -1


## ============ WHAT A PLAYER DOES WHEN NOTHING IS HAPPENING ============
##
## This was a small circle: 34 pixels across and 46 up and down, at a fixed
## rate, centred on the player's slot. Twenty-two people bobbing up and down
## on the spot — which is exactly what it looked like, and the up-and-down was
## the bigger of the two numbers, which is why the bobbing was vertical.
##
## A player with nothing to do in a real match DOES NOT vibrate on a spot.
## They walk about: a few strides one way, a look around, a few strides back,
## mostly sideways to sideways rather than up and down, over a patch far
## bigger than their own bootprint.
##
## So the drift is now:
##
##   * WIDE — `drift_reach` across, and wider still across the pitch than up
##     and down it, because a footballer shuffles across their line;
##   * SLOW — `drift_pace` is about a third of the old rate, so a stride takes
##     a couple of seconds instead of a couple of frames;
##   * IRREGULAR — three waves at unrelated rates rather than one circle, so
##     no two players ever trace the same shape and nobody loops;
##   * and pulled gently toward the ball's end of the pitch, so a whole side
##     shifts up and back with the play the way a real line does.
func _drift_point(unit: PlayerUnit) -> Vector2:
	var phase := float(unit.get_instance_id() % 100) * 0.37
	var pace := drift_pace

	# ============ THE BLOCK MOVES, THE PLAYER BARELY DOES ============
	#
	# "Why are they moving up and down when they don't have the ball?"
	#
	# Because the only thing moving them WAS a sine wave. A player with no job
	# walked a slow circle round their slot, and twenty-two slow circles is a
	# pitch of people fidgeting — motion with no reason behind it, which is
	# exactly what it looks like from above.
	#
	# A real side off the ball is not still and is not fidgeting either. It
	# moves as ONE SHAPE, and it moves because the ball moved: the whole block
	# slides across when the ball goes wide and steps up when it goes forward.
	# Every player is walking somewhere for a reason, and the reason is the
	# same reason for all ten of them.
	#
	# So the drift is now mostly `block_follow_*` — the shape sliding after the
	# ball — with a small personal sway on top for life. The sway is a third of
	# what it was and the VERTICAL sway is smaller again, because the up-and-
	# down was the part that read as bobbing.
	var spot := unit.home_position
	if ball != null and is_instance_valid(ball) and block_follow > 0.0:
		var at := ball.global_position
		# Sideways with the ball, and forward/back with it. A defensive line
		# shifts across the pitch far more readily than it changes its depth,
		# which is why the two have separate rows.
		spot.y += (at.y - unit.home_position.y) * block_follow
		spot.x += (at.x - unit.home_position.x) * block_follow * block_depth_share

	# The old lean is still here and still does its job: it is the part of the
	# shift that survives while the ball is dead, when there is nothing to
	# follow. The block above takes over the moment there is.
	if not is_inf(_ball_lean_x) and drift_ball_lean > 0.0:
		spot.x += (_ball_lean_x - unit.home_position.x) * drift_ball_lean

	# A stride, not a circle: two unrelated rates across and a much smaller one
	# up and down, so nobody loops and nobody bobs.
	spot += Vector2(
		sin(_anim_clock * pace + phase) * drift_reach
			+ sin(_anim_clock * pace * 0.31 + phase * 1.7) * drift_reach * 0.55,
		cos(_anim_clock * pace * 0.73 + phase) * drift_reach * drift_updown)

	return unit.leash_point(spot)


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
	enemy_team = {}

	# The ceiling applies to every match, friendly or not, so it is set
	# before any early return below.
	if abilities != null:
		abilities.max_power = db.tune_int("max_card_power", 5)

	if season == null or state == null:
		return

	# AN OPPONENT MADE UP ON THE SPOT. The mode's Opponent column decides:
	#   team      a club, from the season table or Teams.csv  (the old way)
	#   scratch   a side assembled at your level               (a friendly)
	# See scratch_team.gd. This happens before the fixture lookup because a
	# scratch side replaces the fixture rather than filling one in.
	if String(match_mode.get("opponent", "team")).to_lower() == "scratch":
		_build_scratch_opponent()
		return

	# A mode that does not record the season has no fixture at all. It is a
	# friendly by definition, so there is nothing to look up, no Difficulty
	# to apply, and no opponent named by the table.
	if not bool(match_mode.get("records", true)):
		current_fixture = {}
		print("[mode] %s — no fixture. Nothing here is written to the season table."
			% match_mode.get("name", "Quick Match"))
		return

	# "Play it again" from the stats screen. The fixture is already recorded,
	# so this run is a friendly: same opposition, nothing written down.
	if state.has_flag(MatchStatsScreen.REPLAY_FLAG):
		state.set_flag(MatchStatsScreen.REPLAY_FLAG, false)
		replaying = true
		current_fixture = season.previous(state)
		if not current_fixture.is_empty():
			# THE TEAM COLUMN WINS. A fixture that names a team gets that team's
			# class and that team's cards; one that does not falls back to Class,
			# which is what every fixture did before Teams.csv existed.
			enemy_team = {}
			var team_id := String(current_fixture.get("team", "")).strip_edges()
			if team_id != "":
				enemy_team = TeamDB.get_db().find(team_id)
				if enemy_team.is_empty():
					push_warning("[teams] Season.csv fixture '%s' names team '%s', which is not in Teams.csv. Falling back to the Class column."
						% [current_fixture["id"], team_id])

			forced_enemy_class = String(current_fixture["class"]).strip_edges()
			if not enemy_team.is_empty():
				var team_class := String(enemy_team["class"]).strip_edges()
				if team_class != "":
					forced_enemy_class = team_class
				print("[teams] Facing %s — power %d, %d named card(s)." % [
					enemy_team["name"], TeamDB.get_db().rated_power(enemy_team),
					(enemy_team["cards"] as Array).size()])

			print("[season] Rerunning %s as a friendly. Nothing will be recorded."
				% current_fixture["opponent"])
			return
		print("[season] Nothing to rerun — playing the next fixture instead.")

	current_fixture = season.current(state)
	if current_fixture.is_empty():
		print("[season] No fixture on — this is a friendly. The result will not be recorded.")
		return

	forced_enemy_class = String(current_fixture["class"]).strip_edges()

	# The ceiling, before anything is added on. This is what stops an ability
	# turning a 5-power Tier IV into a 6.
	if abilities != null:
		abilities.max_power = db.tune_int("max_card_power", 5)

	# DIFFICULTY MAKES THEM FINISH BETTER — it does not make their cards
	# bigger. A harder fixture adds to the opposition's SHOT, so their Tier I
	# is still a 0, a 1 and a 2 exactly like yours. See the long note in
	# ability_engine.gd, and TIER_LADDER_AND_AUTO.md.
	var scale := db.tune_float("season_difficulty_scale", 1.0)
	var bonus := int(round(float(int(current_fixture["difficulty"])) * scale))
	if abilities != null and bonus != 0:
		if db.tune_bool("difficulty_as_power", false):
			abilities.side_bonus[true] = bonus
			print("[season] difficulty_as_power is ON — the enemy's cards are +%d, which breaks the tier ladder. Turn it off in Tuning.csv." % bonus)
		else:
			abilities.side_shot_bonus[true] = bonus

	print("[season] Matchday %d of %d — %s%s%s" % [
		int(current_fixture["number"]), season.last_number(),
		current_fixture["opponent"],
		"  (THE FINAL)" if bool(current_fixture["final"]) else "",
		"  difficulty +%d to their shot" % bonus if bonus != 0 else ""])


## THE MODE SHAPES THE MATCH. Tuning.csv sets the defaults; the chosen mode
## from MatchModes.csv overrides them for this match only. See match_mode.gd.
func _apply_match_mode() -> void:
	match_mode = MatchMode.current(get_tree())

	TOTAL_CYCLES = maxi(1, int(match_mode["cycles"]))
	ROUNDS_PER_CYCLE = maxi(1, int(match_mode["rounds"]))

	var minutes := float(match_mode["timer"])
	no_clock = minutes <= 0.0
	if no_clock:
		# A no-clock match still needs the minute hand to drive the event
		# schedule, so it is given far more time than it can use and ends
		# when the rounds run out instead. See _process().
		MATCH_LENGTH_MINUTES = 10000.0
		LAST_EVENT_MINUTE = FIRST_EVENT_MINUTE \
			+ db.tune_float("no_clock_event_spacing", 6.0) \
			* float(TOTAL_CYCLES * ROUNDS_PER_CYCLE)
	else:
		MATCH_LENGTH_MINUTES = minutes

	print("[mode] %s — %d cycle(s) of %d, %s, %s." % [
		match_mode["name"], TOTAL_CYCLES, ROUNDS_PER_CYCLE,
		"no clock" if no_clock else "%d minutes" % int(minutes),
		"goes in the table" if bool(match_mode["records"]) else "not recorded"])


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
	mark_shoulder = db.tune_float("mark_shoulder", mark_shoulder)
	mark_commitment = db.tune_float("mark_commitment", mark_commitment)
	mark_swap_gap = db.tune_float("mark_swap_gap", mark_swap_gap)
	mark_drift = db.tune_float("mark_drift", mark_drift)
	open_spread = db.tune_float("open_spread", open_spread)
	open_break = db.tune_float("open_break", open_break)
	open_width = db.tune_float("open_width", open_width)
	drift_reach = db.tune_float("drift_reach", drift_reach)
	drift_pace = db.tune_float("drift_pace", drift_pace)
	drift_updown = db.tune_float("drift_updown", drift_updown)
	block_follow = db.tune_float("block_follow", block_follow)
	block_depth_share = db.tune_float("block_depth_share", block_depth_share)
	drift_ball_lean = db.tune_float("drift_ball_lean", drift_ball_lean)
	goal_kick_converge_seconds = db.tune_float(
		"goal_kick_converge_seconds", goal_kick_converge_seconds)
	surge_spread = db.tune_float("surge_spread", surge_spread)
	surge_runners = db.tune_int("surge_runners", surge_runners)
	surge_rest_share = db.tune_float("surge_rest_share", surge_rest_share)
	recover_closers = db.tune_int("recover_closers", recover_closers)
	mark_level_floor = db.tune_float("mark_level_floor", mark_level_floor)
	leash_band_fraction = db.tune_float("leash_band_fraction", leash_band_fraction)


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
	# Both clash screens take the same three numbers, so this works for
	# either of them. set() rather than a dotted name because `rps` is
	# whichever of the two was built — see spawn_rps().
	rps.set("enemy_attack_chance",
		db.tune_float("enemy_attack_chance", rps.get("enemy_attack_chance")))
	rps.set("reveal_seconds",
		db.tune_float("rps_reveal_seconds", rps.get("reveal_seconds")))
	rps.set("result_seconds",
		db.tune_float("rps_result_seconds", rps.get("result_seconds")))


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
	# ---- the five that decide whether the pitch looks alive or twitchy ----
	unit.personal_space = db.tune_float("unit_personal_space", unit.personal_space)
	unit.contest_crowding = db.tune_float("unit_contest_crowding", unit.contest_crowding)
	unit.arrive_radius = db.tune_float("unit_arrive_radius", unit.arrive_radius)
	unit.still_threshold = db.tune_float("unit_still_threshold", unit.still_threshold)
	unit.face_deadzone = db.tune_float("unit_face_deadzone", unit.face_deadzone)


func _tune_goalie(keeper: GoalieUnit) -> void:
	# THE CURVE IS THE DEFAULT. The two flat numbers below it are what the
	# keeper used before ShotOdds.csv existed, and `shot_odds` false is how
	# you go back to them — see goalie_unit.gd.
	keeper.use_shot_odds = db.tune_bool("shot_odds", true)
	keeper.stamina_bite = db.tune_float("shot_stamina_bite", 0.45)
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
	# NO CLOCK, NO CLOCK FACE. A Quick Match counts rounds instead of minutes,
	# because a running "0412:37" would be nonsense and a blank corner would
	# look broken.
	if no_clock:
		timer_label.text = "ROUND %d / %d" % [
			mini(next_event_index + 1, TOTAL_CYCLES * ROUNDS_PER_CYCLE),
			TOTAL_CYCLES * ROUNDS_PER_CYCLE]
		return
	var mins := int(match_time_minutes)
	var secs := int((match_time_minutes - mins) * 60.0)
	timer_label.text = "%02d:%02d" % [mins, secs]


## ============ WHAT A FRIENDLY PAYS ============
##
## The Rewards and Rewards On Win columns of MatchModes.csv, written in the
## same language as a dialogue Effects column:
##
##     count:scrap+3          three scrap, win or lose
##     count:friendly_wins+1  only in the On Win column
##     unlock:The Cup         hand out an unlock
##
## So "what a friendly is worth" is a spreadsheet edit and nothing here
## needs to know what scrap is. An unlock earned this way lands on the same
## "what you gained" panel as any other, because the panel works by
## comparing two photographs of your save — see match_report.gd.
func _pay_out_the_mode(outcome: String) -> void:
	if state == null:
		return

	var paid: Array[String] = []
	var always := String(match_mode.get("rewards", "")).strip_edges()
	if always != "":
		DialogueGrammar.apply(always, state)
		paid.append(always)

	if outcome == "win":
		var on_win := String(match_mode.get("rewards_win", "")).strip_edges()
		if on_win != "":
			DialogueGrammar.apply(on_win, state)
			paid.append(on_win)

	if paid.is_empty():
		print("[mode] %s pays nothing — fill in its Rewards column in MatchModes.csv."
			% match_mode.get("name", "this mode"))
		return
	print("[mode] %s paid out: %s" % [match_mode.get("name", "this mode"),
		"  ·  ".join(paid)])


## EVERY CARD OF YOURS THAT WAS ON THE PITCH, Stars included. Read off the
## units rather than off the draft, because a player who was named and never
## picked still played the match — they stood in the rain for ninety minutes
## like everybody else.
func _squad_that_played() -> Array:
	var out: Array = []
	for unit in _all_units():
		if unit.is_enemy or unit.data == null:
			continue
		if not out.has(unit.data):
			out.append(unit.data)
	return out


func _full_time() -> void:
	match_time_minutes = MATCH_LENGTH_MINUTES
	current_state = MatchState.FULL_TIME
	timer_label.text = "FULL TIME" if no_clock \
		else "%02d:00" % int(MATCH_LENGTH_MINUTES)
	event_announcement.text = "FULL TIME  %d - %d" % [player_score, enemy_score]
	event_announcement.show()
	print("FULL TIME — %d : %d" % [player_score, enemy_score])
	match_ended.emit(player_score, enemy_score)

	var outcome := "draw"
	if player_score > enemy_score:
		outcome = "win"
	elif player_score < enemy_score:
		outcome = "loss"

	# ============ "DID I WIN THE LAST ONE?" AS A FLAG ============
	#
	# Counters can say how many you have won; nothing could say whether the
	# match that just finished was one. A Progression row that pays a bonus
	# for winning needs exactly that, so it is written here, set on a win and
	# CLEARED on anything else — a flag that is only ever set is a flag that
	# is true forever.
	if state != null:
		state.set_flag("won_last_match", outcome == "win")

	var facts := _facts_for(null)
	facts["result"] = outcome
	facts["scored"] = str(player_score)
	facts["conceded"] = str(enemy_score)
	facts["margin"] = str(player_score - enemy_score)
	_report("match_ended", facts)

	# ============ THE REFEREE'S NOTEBOOK ============
	#
	# Printed even when it is empty, because "no cards" is a result too and a
	# line that only sometimes appears is a line you stop looking for.
	if _cards_shown.is_empty():
		print("  Discipline: no cards.")
	else:
		for shown in _cards_shown:
			print("  %s card: %s (%s)" % [String(shown["colour"]).capitalize(),
				shown["name"], "them" if bool(shown["side"]) else "you"])

	# ============ WHO PLAYED, AND WHO IS OUT NEXT WEEK ============
	#
	# A fixture has been played, so everybody's rest comes down by one — and
	# THEN the players who were actually named go out for theirs. That order
	# matters: the other way round, a player would be let off a fixture of
	# their own rest by the very match they were playing in.
	#
	# `recovery` in Tuning.csv turns the whole thing off and the squad is
	# available every week, as it was.
	if state != null and db.tune_bool("recovery", false):
		RecoveryBook.advance_turn(state, db)
		RecoveryBook.played(_squad_that_played(), state, db)

	# ============ AND THE MATCH PAYS ============
	#
	# Which purse, and how much, is data/Currencies.csv — and WHICH MODE pays
	# it is a column of that file, so a Quick Match never pays league coins
	# and a season match never pays marks. That is the whole of "separate
	# currencies per mode", and the match only has to say which mode it was.
	if state != null:
		var mode_id := String(match_mode.get("id", MatchMode.DEFAULT_ID))
		for coin in ShopBook.pay_out(mode_id, outcome, state):
			print("  [purse] %+d %s." % [int(coin["amount"]), coin["name"]])
			if gains != null:
				gains.note(String(coin["name"]), "%+d" % int(coin["amount"]))

	# ============ AND A TURN PASSES IN THE CELLAR ============
	#
	# A fixture is the game's unit of time, so it has to be ONE unit: the
	# Brewery's lagering is advanced from the same line the squad's rest is,
	# and there is exactly one answer to "what is a turn". Whatever comes out
	# of the cellar is listed on the what-you-gained panel, because a barrel
	# that appeared while you were playing is a thing you want told about.
	if state != null:
		for came_out in BreweryBook.advance_turn(state):
			var words := "%d %s out of the cellar" % [
				int(came_out["many"]), came_out["made"]]
			print("  [brewery] %s (%s)." % [words, came_out["section"]])
			if gains != null:
				gains.note(String(came_out["section"]), words)

	# ============ AND THE ACHIEVEMENTS ARE REVIEWED ============
	#
	# Here rather than only when a screen opens, because a match can end and
	# be read without changing screen — and "you have just unlocked the
	# Brewery" belongs to the whistle, not to the next menu.
	#
	# It runs AFTER _report("match_ended"), so every counter this match filled
	# has already been written and an achievement asking for it sees today's
	# number rather than yesterday's.
	var earned_now := AchievementBook.review(state)
	if gains != null:
		for row in earned_now:
			gains.note(String(row["name"]), String(row["description"]))

	# One-match brews wear off at the whistle. Permanent ones stay on.
	var brews_off := BrewDB.clear_temporary(state)
	if brews_off > 0 and gains != null:
		gains.note("%d one-match brew%s wore off" % [
			brews_off, "" if brews_off == 1 else "s"], "pour another at the Pub")

	# The fixture is recorded BEFORE the Progression rows run, so that a row
	# saying  Requires: flag:season_over  or  count:season_wins>=3  is testing
	# today's result rather than yesterday's.
	var summary: Dictionary = {}
	if not bool(match_mode.get("records", true)):
		# A Quick Match. The table is not touched, but every Stats.csv counter
		# still ran, so the resources, unlocks and achievement progress you
		# earned are all there — that is the whole point of playing one.
		summary = {
			"fixture": {}, "scored": player_score, "conceded": enemy_score,
			"actions": [] as Array[Dictionary],
		}
		print("[mode] %s finished %d-%d. Nothing written to the table; what you collected is yours."
			% [match_mode.get("name", "Quick Match"), player_score, enemy_score])
		_pay_out_the_mode(outcome)
	elif season != null and not replaying:
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

	# The tier comes from the CLASS, not from the card you happened to click.
	# Those are the same thing on good data; on a class whose Stars straddle
	# two tiers they are not, and the class's own answer is the right one.
	player_star_tier = db.star_tier_for_class(chosen.unit_type)
	if player_star_tier == "":
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

	# Kick-off: the team sheet, then the countdown, then both sides go for a
	# loose ball. See _open_the_team_sheet() and _kickoff_sequence().
	_open_the_team_sheet()

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

	# THE MATCH IS NOT LIVE YET. _kickoff_sequence() marks it playing when the
	# countdown reaches START, and the team sheet in front of it holds
	# everything until you have seen who you are playing and pressed START.
	_open_the_team_sheet()

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
	# ============ THE PITCH IS A SCREEN TOO ============
	#
	# Every menu announces itself through MenuEscape.install(); the match has
	# its own pause menu and never called it, so `screen=match` rows in
	# Audio.csv could never match and the crowd loop never started. This sits
	# here because it is the one line BOTH ways into a match pass through —
	# the drafted kick-off and the one that takes the team straight out of
	# the builder.
	AudioDirector.fire(get_tree(), "screen_opened", {"screen": "match"}, state)

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


## ============ THE FRIENDLY OPPONENT ============
##
## Work out what YOUR side is worth, then have scratch_team.gd assemble one
## about that good out of every card in the game. The whole calculation is
## Tuning.csv rows and the Level column of your unit CSVs — see
## team_level.gd — so what counts as "about that good" is yours to set.
func _build_scratch_opponent() -> void:
	current_fixture = {}
	enemy_team = {}
	forced_enemy_class = ""

	var selection := TeamSelection.fetch(get_tree())

	# TWO DIFFERENT NUMBERS, and they are not interchangeable — see the note
	# in team_level.gd. The headline is what your side is WORTH; the card
	# level is what it goes SHOPPING with.
	var your_level := TeamLevel.of_selection(selection, db)
	var shopping_at := TeamLevel.card_level_of_selection(selection)
	if shopping_at <= 0.0:
		shopping_at = db.tune_float("friendly_default_level", 6.0)

	scratch_opponent = ScratchTeam.build(shopping_at, db, state,
		selection.unit_type if selection != null else "")
	forced_enemy_class = scratch_opponent.star_class

	print("[friendly] Your side is level %d (cards average %.1f)."
		% [your_level, shopping_at])
	print("[friendly] Facing %s" % scratch_opponent.describe())

	# A ONE-TIME NUDGE, not a warning. With the Level column blank every legal
	# team guesses out at the same level, because the tier ladder guarantees
	# the same powers — so every friendly is the same difficulty until you
	# fill it in. Worth saying once rather than leaving you to wonder.
	if TeamLevel.levels_are_unset(db):
		print("[friendly] No card anywhere has a Level yet, so every side matches every other.")
		print("           Fill the Level column in your unit CSVs and friendlies start scaling.")


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
	var roster := load_roster_by_type(star_player.unit_type, is_enemy)
	var tiers: Dictionary = layout["tiers"]

	for tier_key in ALL_TIERS:
		if tier_key == this_star_tier:
			continue                      # the Star already fills this tier
		if not tiers.has(tier_key):
			continue

		var positions: Array = tiers[tier_key]
		var available := filter_units_by_tier(roster, tier_key)

		# ============ THE LADDER, FOR BOTH SIDES ============
		#
		# A tier is one card of each power — Tier I is a 0, a 1 and a 2 — so
		# the line-up is BUILT rung by rung rather than shuffled and sliced.
		# The old code took three cards at random, which is how the enemy
		# ended up fielding three 2s while you fielded a 0, a 1 and a 2.
		#
		# Your side starts from what you chose in the team builder and only
		# has gaps filled; the enemy is drawn fresh each match, so it is a
		# different legal three every time. See tier_ladder.gd.
		var pool: Array[PlayerData] = []
		var short_of: Array[int] = []

		if not is_enemy and chosen_regulars.has(tier_key):
			var built: Array[PlayerData] = []
			built.assign(chosen_regulars[tier_key])
			var mended := TierLadder.repair(built, available, tier_key, db)
			pool.assign(mended["cards"])
			short_of.assign(mended["missing"])
			for dropped: PlayerData in (mended["dropped"] as Array):
				print("[ladder] %s cannot stand in Tier %s — %s. Left out."
					% [dropped.player_name, tier_key, TierLadder.describe(tier_key, db)])
		else:
			# The opposition prefers the cards its Teams.csv row names, and
			# falls back to the rest of its class for any rung the row left
			# empty — so a row naming two cards still fields a legal three.
			var made := TierLadder.build(available, tier_key, db, true,
				filter_units_by_tier(db.roster_for_class(star_player.unit_type), tier_key))
			pool.assign(made["cards"])
			short_of.assign(made["missing"])

		for power in short_of:
			# A data problem, not a code fault — say which card is missing so
			# it can be added to a CSV, rather than just "not enough cards".
			print("[ladder] '%s' has no %d-power Tier %s card to field%s."
				% [star_player.unit_type, power, tier_key,
					" for the opposition" if is_enemy else ""])

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

	# ============ THE LEASH FOLLOWS THE BAND ============
	#
	# The leash used to be a flat 210 pixels whatever size the pitch was, and
	# on a normal pitch that is less than half a quarter — so a player could
	# not reach the edge of their OWN zone, never mind anyone else's. It was
	# the real cage, quietly, underneath the zone that everyone was blaming.
	#
	# It is now a fraction of the roam band, so it scales with the pitch and
	# with zone_roam: at the default a player may wander most of their band
	# before anything reminds them where they live.
	var band := unit.tier_soft_zone.size.x
	if band > 1.0:
		unit.leash = maxf(160.0, band * leash_band_fraction)


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
	# BREAKING A KEEPER IS AN EVENT WORTH COUNTING. The moment their bar
	# reaches zero is the moment the next shot becomes a certainty, so it is
	# a real milestone rather than a number going down — and Stats.csv and
	# Achievements.csv can both hang off it. Only THEIR keeper: everything
	# the game unlocks is about what you did.
	enemy_goalie.stamina_depleted.connect(_on_keeper_emptied)
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


## Their keeper has nothing left. Reported once per emptying — the goalie
## refills on conceding, so this fires again the next time you break him.
func _on_keeper_emptied() -> void:
	var facts: Dictionary = {}
	if active_player_star != null:
		facts["class"] = active_player_star.unit_type
	_report("keeper_emptied", facts)


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
	# A locked speed says so on the big announcement, not in the corner.
	hud.speed_locked.connect(func(words: String) -> void: announce(words, 1.6))
	hud.scout_wanted.connect(show_enemy_team)


## The hover window. It lives on the SelectionUI layer with the cards, so it
## sits over them and the camera never moves it.
func spawn_card_stats() -> void:
	if not db.tune_bool("card_hover_stats", true):
		return
	card_stats = CardStatsPanel.make(db)
	selection_ui.add_child(card_stats)


## The pause overlay. It is added last so it sits above the HUD, and it
## keeps running while everything else is stopped.
func spawn_pause_menu() -> void:
	pause_menu = PauseMenu.make(db, state)
	add_child(pause_menu)
	pause_menu.quit_requested.connect(_on_quit_match)
	pause_menu.auto_pick_changed.connect(_on_pause_menu_auto_changed)


## They pressed quit, twice, having been told what it costs.
func _on_quit_match() -> void:
	GameSpeed.reset()

	# Put the save back to the kick-off photograph. Nothing this match gave
	# them survives — which is exactly what the warning said would happen.
	if gains != null:
		gains.restore(state)

	# And no post-match screens: there is no result to show.
	MatchReport.take(get_tree())
	ScenePaths.go_to(get_tree(), ScenePaths.BASE, false)


## AUTO was switched on or off mid-match. Two things follow from that, and
## both have to happen the instant the button is pressed rather than at the
## next event: the game takes over (or hands back), and your clicks lock
## (or unlock). Doing only the first is what let you and the computer both
## choose in the same round.
func _on_auto_pick_changed(is_on: bool) -> void:
	_apply_auto_lock(is_on)
	if is_on and current_state == MatchState.DRAFTING:
		_offer_auto_pick()


## The same thing, toggled from the pause menu instead of the HUD. The HUD's
## button is repainted so the two never disagree.
func _on_pause_menu_auto_changed(is_on: bool) -> void:
	if hud != null:
		hud.refresh_auto_button()
	_on_auto_pick_changed(is_on)


## Dim and disable everything the player would otherwise click while AUTO
## is playing: the offered cards, and the clash buttons.
func _apply_auto_lock(is_on: bool) -> void:
	if card_container != null:
		for child in card_container.get_children():
			var card := child as PlayerCardUI
			if card != null:
				card.set_locked(is_on)
	if rps != null:
		rps.set_locked(is_on)
	# A locked card cannot be hovered, so a stats panel left open by the card
	# under the cursor would sit there for the rest of the match.
	if is_on and card_stats != null:
		card_stats.hide()


## Is AUTO playing for us right now? One question, asked in several places.
func _auto_is_on() -> bool:
	return state != null and MatchHUD.auto_pick_on(state)


func spawn_rps() -> void:
	if db != null and db.tune_bool("use_coin_clash", true):
		rps = CoinClash.make(db)
		add_child(rps)
		_tune_rps()
		return

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
	rps.set_locked(_auto_is_on())

	# AUTO plays the clash too — the throw AND the attack/defend choice — so
	# "sit back and watch" really means the whole match, not "the whole match
	# except the two buttons in the middle of it".
	if _auto_is_on():
		rps.auto_play(db.tune_float("auto_pick_seconds", 0.9),
			db.tune_float("auto_attack_chance", 0.5))

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
	# A STAND-IN. He is a copy of a survivor made to fill a hole a red card
	# left in the ladder, so the body that plays him is the man he was copied
	# from — see _stand_ins_for() and foul_book.gd.
	var body: PlayerUnit = _stand_in_bodies.get(card, null)
	if body != null and is_instance_valid(body) and body.is_enemy == side_is_enemy:
		return body
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
	# ============ THE MARGIN BETWEEN THE IMAGE AND THE LINES ============
	#
	# The pitch IMAGE is 16:9 so the wide shot can show all of it with no
	# black edges. The white LINES inside it are a real pitch shape, which is
	# not 16:9 — so there is grass, a running track, whatever you draw, round
	# the outside. These two numbers say how much, and they are what makes
	# the game's play area line up with your drawing.
	#
	# They are rows because they belong to the picture: draw the lines closer
	# to the edge and you lower them, draw a big surround and you raise them.
	var side := db.tune_float("pitch_inset_x", 0.06) if db != null else 0.06
	var ends := db.tune_float("pitch_inset_y", 0.10) if db != null else 0.10
	return area.grow_individual(
		-area.size.x * side, -area.size.y * ends,
		-area.size.x * side, -area.size.y * ends)


func get_pitch_rect() -> Rect2:
	if field_sprite != null and field_sprite.texture != null:
		var size := field_sprite.texture.get_size() * field_sprite.global_scale
		var origin := field_sprite.global_position
		if field_sprite.centered:
			origin -= size / 2.0
		return Rect2(origin, size)
	return get_viewport_rect()


# =============================================================
#  THE SCENERY — data/Stadium.csv
#
#  The pitch used to be a sprite placed by hand in the .tscn: a 1000 x 667
#  photograph, scaled 2.216 across and 2.114 down. Two different scale
#  factors, so the picture was very slightly squashed, and no answer at all
#  to "what size should I draw one".
#
#  It is a spreadsheet now. The pitch is stretched to exactly the Width and
#  Height of its row whatever size the file is drawn at, and the background
#  layers are built here from the same file. See stadium_book.gd.
# =============================================================

## Every layer except the pitch, so they can be moved with the camera.
var _scenery: Array[Dictionary] = []


func _build_the_stadium() -> void:
	if field_sprite == null:
		return

	# ---- THE PITCH, at exactly the size the spreadsheet asks for ----
	var wanted := StadiumBook.pitch_size()
	var pitch_row := StadiumBook.row_for("pitch")
	var art := String(pitch_row.get("image", ""))
	if art != "":
		var swapped := _field_texture(art)
		if swapped != null:
			field_sprite.texture = swapped
	if field_sprite.texture != null:
		var raw := field_sprite.texture.get_size()
		if raw.x > 1.0 and raw.y > 1.0:
			# ONE SCALE PER AXIS, worked out from the drawing rather than
			# typed in — so a file drawn at any size lands on the same
			# rectangle and nothing is squashed by accident.
			field_sprite.scale = Vector2(wanted.x / raw.x, wanted.y / raw.y)
	field_sprite.centered = true
	# ============ WHERE THE PITCH SITS, AND WHY NOT AT THE ORIGIN ============
	#
	# The obvious thing is to centre it on (0, 0). Doing that cost me a run.
	#
	# The play rectangle is the CAMERA'S VIEW intersected with the pitch, and
	# the camera does not exist yet when the geometry is locked — so the view
	# at that moment is the raw viewport, which starts at (0, 0) and runs
	# down and right. A pitch centred on the origin has three quarters of
	# itself in negative space, the intersection is a quarter of the grass,
	# and twenty-two players get laid out in it. The measured symptom was the
	# average gap between players falling from 155 pixels to 102.
	#
	# So it is centred on the middle of that first view, which is where the
	# hand-placed sprite effectively was. The Offset X / Offset Y columns
	# still move it from there.
	var first_view := get_viewport_rect()
	field_sprite.position = first_view.get_center() \
		+ Vector2(pitch_row.get("offset", Vector2.ZERO))
	field_sprite.z_index = -10

	# ---- AND WHAT IS BEHIND AND OVER IT ----
	_scenery.clear()
	var order := {"background": -40, "crowd": -30, "lights": 60}
	for row in StadiumBook.layers():
		var layer_name := String(row["layer"])
		if layer_name == "pitch" or not order.has(layer_name):
			continue
		if String(row.get("image", "")) == "":
			continue
		if not StadiumBook.allowed(row, state):
			print("[stadium] '%s' is not drawn — its Requires does not pass." % layer_name)
			continue
		var texture := _field_texture(String(row["image"]))
		if texture == null:
			print("[stadium] '%s' names %s, which is not in assets/field/ yet."
				% [layer_name, row["image"]])
			continue
		var sprite := Sprite2D.new()
		sprite.name = "Stadium_%s" % layer_name
		# Same centre as the pitch, so a background lines up with the grass.
		sprite.texture = texture
		sprite.centered = true
		sprite.z_index = int(order[layer_name])
		sprite.modulate = StadiumBook.tint_of(row)
		var box: Vector2 = row.get("size", Vector2.ZERO)
		var raw2 := texture.get_size()
		if box.x > 1.0 and box.y > 1.0 and raw2.x > 1.0 and raw2.y > 1.0:
			sprite.scale = Vector2(box.x / raw2.x, box.y / raw2.y)
		add_child(sprite)
		sprite.position = field_sprite.position \
			+ Vector2(row.get("offset", Vector2.ZERO))
		_scenery.append({
			"node": sprite,
			"home": sprite.position,
			"parallax": float(row.get("parallax", 0.0)),
		})
	if not _scenery.is_empty():
		print("[stadium] %d scenery layer(s) built." % _scenery.size())


## Drift the background against the camera, so it reads as distance rather
## than as a sticker on the grass. Called from _process().
func _move_the_scenery() -> void:
	if _scenery.is_empty() or camera == null:
		return
	var eye := camera.global_position
	for entry in _scenery:
		var sprite := entry["node"] as Sprite2D
		if sprite == null or not is_instance_valid(sprite):
			continue
		sprite.global_position = Vector2(entry["home"]) + eye * float(entry["parallax"])


## A picture out of assets/field/, by name, with or without an extension.
func _field_texture(art: String) -> Texture2D:
	var clean := art.strip_edges()
	if clean == "":
		return null
	if clean.begins_with("res://"):
		return load(clean) as Texture2D if ResourceLoader.exists(clean) else null
	for tail in [".png", ".jpg", ".jpeg", ".webp", ""]:
		var path := "res://assets/field/%s%s" % [clean, tail]
		if ResourceLoader.exists(path):
			return load(path) as Texture2D
	return null


## Pin the play area for the duration of a spawn, so both teams are built
## against identical geometry. Always paired with _unlock_geometry().
func _lock_geometry() -> void:
	if _geometry_locked:
		return

	# THE SCENERY FIRST. The play rectangle is measured off the pitch sprite,
	# so the sprite has to be the size Stadium.csv asks for BEFORE anything
	# reads it — otherwise the formation is laid out against the old
	# hand-placed rectangle and the grass moves underneath it.
	_build_the_stadium()
	# The camera is built here, before the play rect is pinned, so that the
	# rectangle it is handed is the un-zoomed one. After this the two agree
	# forever, because get_visible_world_rect() hands back the camera's own
	# framing.
	_spawn_camera(get_visible_world_rect())

	_locked_play_rect = get_play_rect()
	_geometry_locked = true

	zones = PitchZones.new(_locked_play_rect,
		db.tune_float("zone_share", 0.25),
		# zone_roam REPLACES zone_stretch, and the old row is deliberately not
		# consulted: a band a third of the pitch wide was the cage, so falling
		# back to it would quietly put the cage back. See pitch_zones.gd.
		db.tune_float("zone_roam", 0.60),
		db.tune_float("zone_side_inset", 0.34),
		db.tune_float("zone_lane_stagger", 0.5),
		db.tune_float("zone_lane_depth", 0.22),
		db.tune_float("zone_claim", 0.34))

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

## The cards a side may field.
##
## For YOUR side this is simply everyone of your class. For the opposition it
## is narrowed to the cards named in their Teams.csv row, which is how
## "Reedbank Wanderers field these four" is expressed without any code
## knowing who Reedbank are.
##
## A team that names no cards, or whose named cards have all been used, falls
## back to the whole class — so a half-filled row still gives you a match.
func load_roster_by_type(unit_type: String, for_enemy: bool = false) -> Array[PlayerData]:
	var whole_class := db.roster_for_class(unit_type)

	# A SCRATCH SIDE IS NOT A CLASS. It is a pick-up team drawn from the
	# whole collection, so its regulars are handed over as they are rather
	# than filtered down to one class. They are already ladder-legal — see
	# scratch_team.gd — and spawn_team() only ever asks "who is Tier II",
	# which is why a mixed side drops straight in here.
	if for_enemy and scratch_opponent != null:
		if not scratch_opponent.cards.is_empty():
			return scratch_opponent.cards
		print("[friendly] The scratch side came out empty — fielding the whole class instead.")
		return whole_class

	if not for_enemy or enemy_team.is_empty():
		return whole_class

	var wanted := TeamDB.get_db().resolve_cards(enemy_team)
	if wanted.is_empty():
		return whole_class

	# Only the named cards, and only ones of the class actually on the pitch.
	var out: Array[PlayerData] = []
	for card in whole_class:
		for named in wanted:
			if named == card:
				out.append(card)
				break

	if out.is_empty():
		print("[teams] '%s' names no cards of class %s — using the whole class."
			% [enemy_team.get("name", "?"), unit_type])
		return whole_class
	return out


func _stars_grouped_by_class() -> Dictionary:
	return db.stars_by_class()


## The three Stars this class fields — one on each rung of its star tier,
## weakest first. Not simply "every Star row of this class", which is how a
## class with Stars in two tiers used to hand out an illegal bundle.
func get_star_bundle_by_type(unit_type: String) -> Array[PlayerData]:
	return db.star_ladder_for_class(unit_type)


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


## EVERYONE STILL ON THE PITCH.
##
## A sent-off man is not. This one line is what "the team only has 9 players
## left" actually means: every draft list, every marking assignment, every
## pass target and every search for a team-mate in this file already asks
## here, so none of them had to be taught what a red card is.
func _all_units() -> Array[PlayerUnit]:
	var out: Array[PlayerUnit] = []
	for child in units_container.get_children():
		var unit := child as PlayerUnit
		if unit != null and not unit.is_sent_off:
			out.append(unit)
	return out


## Including the ones sent off. Only the discipline code wants this — to
## count how many of a side are already gone, and for the full-time report.
func _everyone_ever() -> Array[PlayerUnit]:
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
	# A card shown last round is not shown this one.
	revealed_by_tier.clear()
	enemy_revealed_by_tier.clear()
	_clear_the_table()
	round_in_progress = true

	for unit in _all_units():
		unit.clear_round_flags()

	# The pitch holds still from the whistle until the last card is locked in.
	freeze_play(true)

	# ============ THE BALL GOES OUT FIRST ============
	#
	# A round used to open by asking you to call a number between one and
	# ten. It opens with football now: somebody gives the ball away, it goes
	# over the touchline, and the other side walks over to throw it back in.
	# See `data/OutOfBounds.csv` — every beat of it is a row.
	#
	# It runs BEFORE the PLAY MAKER call on purpose. The whistle is for the
	# restart, and the restart is the throw-in.
	await _put_it_out_of_play()

	print("PLAY MAKER!  Cycle %d, Round %d" % [current_cycle, rounds_this_cycle])
	AudioDirector.fire(get_tree(), "play_maker",
		{"cycle": str(current_cycle), "round": str(rounds_this_cycle)}, state)
	Juice.fire(self, "play_maker", {})
	await announce("PLAY MAKER!")

	# WHOEVER TAKES THE THROW CHOOSES. That is the whole of what the coin
	# used to do, moved onto a thing that happens in a football match.
	player_attacks_this_round = await _ask_the_thrower()
	print("  Throw-in: %s." % ("you attack" if player_attacks_this_round else "they attack"))
	await _say_which_way_round()

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
	revealed_by_tier.clear()
	enemy_revealed_by_tier.clear()
	_clear_the_table()

	# THE WHISTLE. This has to be the very first thing that happens — before
	# the enemy's substitution and before the "STAR PLAYER SWITCH" banner, both of which
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

	# ============ IT IS CALLED A STAR PLAYER SWITCH ============
	#
	# The words on screen were "STAR PLAYER SWITCH", which said what the game was doing
	# to the clock rather than what was happening to your team. It is the same
	# event; only the writing changed.
	#
	# THE AUDIO EVENT IS STILL `hold_up`, deliberately: that is the key your
	# Audio.csv row is written against, and renaming it would silence your
	# whistle. The name in a spreadsheet is a label, not a sentence.
	print("STAR PLAYER SWITCH.  Starting cycle %d" % current_cycle)
	AudioDirector.fire(get_tree(), "hold_up", {"cycle": str(current_cycle)}, state)
	Juice.fire(self, "star_switch", {})
	await announce("STAR PLAYER SWITCH")

	draft_phases.assign(["StarChoice"])
	current_phase_index = 0
	start_next_draft_phase()


# =============================================================
#  THE KICK-OFF
#
#  ============ WHAT IT LOOKS LIKE ============
#
#  The camera comes in on two players facing each other over the ball in the
#  centre circle. THREE. TWO. ONE. START — and both of them go for it. Whoever
#  gets there first has it, passes it, and the ball is live exactly as it was
#  before: knocked about between players until the first PLAY MAKER.
#
#  ============ WHY IT IS A LOOSE BALL ============
#
#  A match used to open with your Star simply holding the ball, which is a
#  strange thing for a football match to do and told you nothing. Putting the
#  ball down in the middle and letting both sides run at it uses the chase
#  behaviour that is already there, so the first thing you see is the game
#  playing itself — and it is genuinely uncertain who comes away with it.
#
#      kickoff_countdown         false and your Star starts on the ball, as before
#      kickoff_count_seconds     how long each of 3, 2, 1 is held
#      kickoff_go_seconds        how long START is held
# =============================================================

# =============================================================
#  THE TEAM SHEET, AND THE START BUTTON
#
#  A match used to begin the instant the screen changed. Now there is a beat:
#  both crests, both names and three Stars a side on a sheet with a bar
#  filling along the bottom, then the sheet lifts to show the two teams
#  standing on the grass with a START button between the crests.
#
#  NOTHING RUNS UNTIL START IS PRESSED. The pitch is frozen, the clock is at
#  00:00 and the countdown has not begun.
#
#  `team_sheet` in Tuning.csv turns the whole thing off and a match opens
#  straight into the 3 - 2 - 1, exactly as it did before.
# =============================================================

func _open_the_team_sheet() -> void:
	if db == null or not db.tune_bool("team_sheet", true):
		_kickoff_sequence()
		return

	# ============ IN POSITION BEFORE ANYBODY LOOKS ============
	#
	# Every unit is put ON its own slot before the sheet goes up. Spawning
	# leaves them near their slots rather than on them, and the freeze holds
	# them wherever they happened to be — so the pitch you looked at behind
	# the START button was not the pitch you got, and the instant START was
	# pressed the whole formation shuffled into place. That shuffle is what
	# looked like the players swapping.
	for unit in _all_units():
		unit.global_position = unit.home_position

	# The duel window's card back wears the two crests, and this is the first
	# moment both of them are known.
	_tell_the_arena_who_is_playing()

	# EVERYTHING STOPS. The teams are on the grass and in position, the ball
	# is nowhere yet, and none of it moves until the sheet is done with.
	freeze_play(true)
	if camera != null and camera.has_method("lock_view"):
		camera.call("lock_view", true)

	_sheet = TeamSheet.make(db)
	selection_ui.add_child(_sheet)
	_sheet.kick_off_wanted.connect(_on_kick_off_wanted)
	_sheet.show_for(_team_facts(false), _team_facts(true))


## THE CREST ON THE BACK OF THE DUEL CARD. The arena is built before either
## team is chosen, so it is told afterwards rather than working it out — and
## it is told here, where both sides are finally known.
func _tell_the_arena_who_is_playing() -> void:
	if duel_arena == null or not is_instance_valid(duel_arena):
		return
	var mine := _team_facts(false)
	var theirs := _team_facts(true)
	# LEFT IS ALWAYS YOU in the duel window, whichever side is attacking, so
	# the crests are handed over the same way round every time.
	duel_arena.left_crest = String(mine.get("crest", ""))
	duel_arena.left_team = String(mine.get("name", ""))
	duel_arena.right_crest = String(theirs.get("crest", ""))
	duel_arena.right_team = String(theirs.get("name", ""))


## THE OPPOSITION'S WHOLE SQUAD, any time during a match. The same window the
## team shelf opens before you have even chosen a side.
func show_enemy_team() -> void:
	var facts := _team_facts(true)
	var klass := active_enemy_star.unit_type if active_enemy_star != null else ""
	var squad: Array[PlayerData] = []
	if klass != "":
		squad = db.roster_for_class(klass)
	for star in enemy_star_bundle:
		if star != null and not squad.has(star):
			squad.append(star)
	EnemyTeamWindow.open(self, db, String(facts.get("name", "")), squad,
		enemy_star_bundle,
		"Their three Stars are ringed. One is on the pitch; the other two come on at the STAR PLAYER SWITCH.")


## Set the first time START is pressed. See below.
var _kick_off_started := false


func _on_kick_off_wanted() -> void:
	# ============ ONCE, HOWEVER MANY TIMES START IS PRESSED ============
	#
	# A double press used to run this twice: TWO line-up parades stacked on
	# top of each other, two countdowns, two kick-offs. I found it because a
	# tool held the button down, but a fast double-click on the real button,
	# or space and the mouse together, would do exactly the same thing — and
	# what the player would see is the team sheet appearing to come back.
	#
	# One flag, and the second press does nothing.
	if _kick_off_started:
		return
	_kick_off_started = true

	# ============ THE TEAMS WALK OUT ============
	#
	# Between the sheet and the countdown: your side one player at a time,
	# then theirs. The team sheet shows two crests and six Stars; this is the
	# twenty other people who are about to play, and every one of them is a
	# card you will be choosing between for the next ninety minutes.
	#
	# The pitch stays frozen behind it — the parade is over the top, and
	# unfreezing before it is done would start the match behind the curtain.
	await _walk_them_out()

	freeze_play(false)
	if camera != null and camera.has_method("lock_view"):
		camera.call("lock_view", false)
	_kickoff_sequence()


## Both line-ups, in order, skippable. Returns when it is done or skipped.
func _walk_them_out() -> void:
	if db == null or not db.tune_bool("line_up_parade", true):
		return
	var yours: Array = []
	var others: Array = []
	for unit in _all_units():
		if unit.data == null:
			continue
		var into: Array = others if unit.is_enemy else yours
		if not into.has(unit.data):
			into.append(unit.data)
	if yours.is_empty() and others.is_empty():
		return

	var mine_facts := _team_facts(false)
	var their_facts := _team_facts(true)
	var parade := LineUpParade.open(self, db, yours, others,
		String(mine_facts.get("name", "YOUR SIDE")).to_upper(),
		String(their_facts.get("name", "THEM")).to_upper())
	await parade.finished


## WHO IS PLAYING, for the sheet. A name, a crest and the Stars.
##
## The crest comes from the `Banner Art` column of ClassInfo.csv, which is
## where a class's picture already lives — so a new class gets a crest on this
## screen the moment it gets one anywhere else, with nothing to wire up. A
## class with no banner yet falls back to `banner_<class>` and then to
## `banner_normal_team`, and a side with no art at all draws a lettered disc.
func _team_facts(theirs: bool) -> Dictionary:
	var klass := ""
	var stars: Array[PlayerData] = []
	if theirs:
		klass = active_enemy_star.unit_type if active_enemy_star != null else ""
		stars = enemy_star_bundle.duplicate()
	else:
		klass = active_player_star.unit_type if active_player_star != null else ""
		stars = player_star_bundle.duplicate()

	# THE ONE WHO IS ACTUALLY PLAYING GOES FIRST. The other two are the bench
	# for the Star switches, and reading them left to right should say so.
	var playing := active_enemy_star if theirs else active_player_star
	if playing != null and stars.has(playing):
		stars.erase(playing)
		stars.insert(0, playing)

	var info := _class_info(klass)
	var shown := MenuSupport.field(info, "Display Name").strip_edges()
	if shown == "":
		shown = klass if klass != "" else ("The Opposition" if theirs else "Your Club")

	var crest := MenuSupport.field(info, "Banner Art").strip_edges()
	if crest == "" or MenuSupport.icon_texture(crest) == null:
		crest = "banner_%s" % CardDatabase._normalise(klass)
	if MenuSupport.icon_texture(crest) == null:
		crest = db.tune_text("team_crest_fallback", "banner_normal_team")

	return {"name": shown, "crest": crest, "stars": stars}


## One row of ClassInfo.csv, or {} if that class has none. Read through the
## same forgiving reader every menu uses, so a missing file or a renamed
## column is not an error here either.
func _class_info(klass: String) -> Dictionary:
	if klass == "":
		return {}
	var wanted := CardDatabase._normalise(klass)
	for row in MenuSupport.read_csv("res://data/ClassInfo.csv"):
		if CardDatabase._normalise(MenuSupport.field(row, "Class")) == wanted:
			return row
	return {}


func _kickoff_sequence() -> void:
	if db == null or not db.tune_bool("kickoff_countdown", true):
		give_ball_to(false)
		current_state = MatchState.PLAYING
		return

	freeze_play(true)
	var spot := get_play_rect().get_center()
	if ball != null:
		ball.global_position = spot
		if ball.has_method("drop_loose"):
			ball.call("drop_loose")

	# TWO PLAYERS OVER THE BALL, one from each side — whoever was nearest the
	# middle already, so nobody teleports across the pitch to get there.
	var facing: Array[PlayerUnit] = []
	for side: bool in [false, true]:
		var nearest: PlayerUnit = null
		for unit in _all_units():
			if unit.is_enemy != side:
				continue
			if nearest == null or unit.global_position.distance_to(spot) \
					< nearest.global_position.distance_to(spot):
				nearest = unit
		if nearest != null:
			facing.append(nearest)
			var step := Vector2(-46.0 if not side else 46.0, 0.0)
			var walk := nearest.create_tween()
			walk.tween_property(nearest, "global_position", spot + step, 0.45) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	if camera != null and camera.has_method("look_close"):
		camera.call("look_close", spot)
		# AND HOLD IT. The match asks the camera to follow the play every
		# frame; for these few seconds it is told not to listen.
		if camera.has_method("lock_view"):
			camera.call("lock_view", true)
	await get_tree().create_timer(0.5).timeout

	# ITS OWN TIMERS, not announce()'s. announce() waits on an ordinary tree
	# timer, and the pitch is frozen while this runs — a countdown that takes
	# its cue from anything the freeze touches drifts, and a "3 - 2 - 1" that
	# drifts is worse than no countdown at all. `true` for process_always
	# means these tick regardless.
	var beat := db.tune_float("kickoff_count_seconds", 0.7)
	for word in ["3", "2", "1"]:
		_say_now(word)
		await get_tree().create_timer(beat, true, false, true).timeout
	_say_now("START")
	await get_tree().create_timer(
		db.tune_float("kickoff_go_seconds", 0.55), true, false, true).timeout
	_say_now("")

	if camera != null:
		if camera.has_method("lock_view"):
			camera.call("lock_view", false)
		if camera.has_method("look_wide"):
			camera.call("look_wide")
	# AND THEY GO. The ball is loose in the middle and the chase behaviour
	# that runs for the rest of the match takes it from here.
	freeze_play(false)
	# THE MATCH IS LIVE ONLY NOW. It used to be marked playing the instant
	# the teams were on the pitch, which meant the clock ran through the
	# countdown — two minutes gone before anybody had touched the ball.
	current_state = MatchState.PLAYING

	# ============ AND THE WHISTLE GOES HERE ============
	#
	# It used to hang on `match_started`, which fires while the scene is
	# still assembling itself — so the referee blew up over the loading
	# screen, several seconds before anybody could kick anything. `kick_off`
	# is its own moment: after the countdown, as play begins.
	_report("kick_off", _facts_for(null))


## ============ A LONG ANNOUNCEMENT RAN OFF THE SCREEN ============
##
## The label was placed by hand in the .tscn — a fixed box from x=660 to
## x=1276 at 72 point, with no wrapping — which is fine for "PLAY MAKER!" and
## is not fine for "They pour Fire Brew on Sapphire Current", which ran off
## the right-hand edge mid-word. A line the player cannot finish reading is
## worse than no line.
##
## So it is the full width of the window now, it wraps, and it shrinks to fit
## rather than overflowing. Done here rather than in the scene file because
## the window can be any size.
func _fit_the_announcement() -> void:
	if event_announcement == null:
		return
	event_announcement.set_anchors_preset(Control.PRESET_TOP_WIDE, true)
	event_announcement.anchor_left = 0.0
	event_announcement.anchor_right = 1.0
	event_announcement.anchor_top = 0.32
	event_announcement.anchor_bottom = 0.32
	var inset := db.tune_float("announce_inset", 120.0) if db != null else 120.0
	event_announcement.offset_left = inset
	event_announcement.offset_right = -inset
	event_announcement.offset_top = 0.0
	event_announcement.offset_bottom = db.tune_float("announce_height", 240.0) \
		if db != null else 240.0
	event_announcement.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# SHRINK RATHER THAN SPILL. Godot will drop the point size as far as this
	# to make the words fit the box, and only then start clipping.
	event_announcement.add_theme_font_size_override("font_size",
		int(db.tune_float("announce_font_size", 72.0)) if db != null else 72)
	event_announcement.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	event_announcement.clip_text = false
	event_announcement.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	event_announcement.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


## ============ THE CALL, LOUD, THE MOMENT IT IS DECIDED ============
##
## The clash closes and you are immediately choosing cards. Without this
## there was nothing between the two: the result flashed on a screen that was
## already going away.
func _say_which_way_round() -> void:
	if db != null and not db.tune_bool("side_call", true):
		return
	var seconds := db.tune_float("side_call_seconds", 1.3) if db != null else 1.3
	if seconds <= 0.0:
		return
	var word := Loc.text("you_are_attacking", "YOU ARE ATTACKING") \
		if player_attacks_this_round else Loc.text("you_are_defending", "YOU ARE DEFENDING")
	# The same two colours the banner uses, so the word and the strip that
	# follows it read as one thing.
	var tint := SideBanner.attack_colour() if player_attacks_this_round \
		else SideBanner.defend_colour()
	if event_announcement != null:
		event_announcement.add_theme_color_override("font_color", tint)
	await announce(word, seconds)
	if event_announcement != null:
		event_announcement.remove_theme_color_override("font_color")


## Put a word on the screen right now and leave it there. The caller decides
## how long for — see the kick-off, which is doing its own timing.
func _say_now(text: String) -> void:
	if event_announcement == null:
		return
	_fit_the_announcement()
	event_announcement.text = text
	event_announcement.visible = text != ""


func announce(text: String, seconds: float = 2.0) -> void:
	_fit_the_announcement()
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

	# ============ AND IT STAYS ON SCREEN ============
	#
	# Which way round the round is played decides WHICH OF THE TWO NUMBERS on
	# a card is the one that counts, so it is the single most important fact
	# in the draft — and it used to be said once, in small text, on a screen
	# that closed a second later. The banner sits above the cards for the
	# whole draft and says the tier as well.
	#
	# The two Star phases are a different kind of choice — you are swapping
	# who is on the pitch, not answering anybody — so it is hidden for those.
	var banner := SideBanner.make(self)
	if phase == "Star" or phase == "StarChoice":
		banner.hide_it()
	else:
		banner.set_side(player_attacks_this_round)
		banner.set_tier(phase)
		banner.show_it()

	if phase == "Star":
		for star_data in _weakest_first(get_star_player_choices()):
			create_card_for_unit(star_data)
		_offer_auto_pick()
		return

	if phase == "StarChoice":
		# ONLY STARS OF YOUR STAR TIER. The incoming Star takes the outgoing
		# one's place on the pitch, so offering a Star from another tier is
		# offering a swap that cannot legally happen.
		var swappable: Array[PlayerData] = []
		for star_data in available_player_stars:
			if player_star_tier == "" or star_data.get_tier_clean() == player_star_tier:
				swappable.append(star_data)

		if swappable.is_empty():
			# No stars left (this shouldn't fire — cycle 3 has no STAR PLAYER SWITCH).
			current_phase_index += 1
			start_next_draft_phase()
			return
		for star_data in _weakest_first(swappable):
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

	var tier_bodies: Array[PlayerUnit] = []
	for unit in _all_units():
		if unit.is_enemy or unit.is_exhausted:
			continue
		if star_holds and unit.is_star_player:
			continue
		if unit.data != null and unit.data.get_tier_clean() == phase:
			tier_bodies.append(unit)

	var tier_choices: Array[PlayerData] = []
	for unit in tier_bodies:
		tier_choices.append(unit.data)
	# ANYONE THE REFEREE TOOK OUT OF THIS TIER IS REPLACED BY A SURVIVOR
	# PLAYING OUT OF POSITION. Nothing happens here in a match with no red
	# cards in it, which is most of them.
	tier_choices.append_array(_stand_ins_for(phase, false, tier_bodies))

	var choices_found := 0
	for card in _weakest_first(tier_choices):
		create_card_for_unit(card)
		choices_found += 1

	if choices_found == 0:
		print("[draft] No available Tier %s cards — skipping this phase." % phase)
		_enemy_pick_for_tier(phase)
		current_phase_index += 1
		start_next_draft_phase()
		return

	_offer_auto_pick()


## WEAKEST ON THE LEFT, STRONGEST ON THE RIGHT — always.
##
## The cards used to appear in whatever order the units happened to sit in
## the scene, which changed from round to round. Now the row always reads the
## same way, so after two matches you stop reading the numbers at all and
## just know that the card on the right is the strong one.
##
## An explicit insertion sort: the list is four or five cards long, and this
## keeps two cards of equal power in the order they were found rather than
## shuffling them about between rounds.
func _weakest_first(cards: Array) -> Array[PlayerData]:
	var sorted: Array[PlayerData] = []
	for entry in cards:
		var card := entry as PlayerData
		if card == null:
			continue
		var at := sorted.size()
		for i in sorted.size():
			if _card_order(sorted[i]) > _card_order(card):
				at = i
				break
		sorted.insert(at, card)
	return sorted


## What "stronger" means for the purpose of laying the row out. Attack while
## you are attacking this round, defence while you are defending — so the
## right-hand card is always the best one FOR THIS ROUND, not in the abstract.
func _card_order(card: PlayerData) -> int:
	if card == null:
		return -1
	return card.get_attack_power() if player_attacks_this_round \
		else card.get_defense_power()


func create_card_for_unit(data: PlayerData) -> void:
	var card := PLAYER_CARD_SCENE.instantiate() as PlayerCardUI
	card_container.add_child(card)
	card.setup_card(data)
	card.card_hovered.connect(_on_card_hovered)
	card.card_unhovered.connect(_on_card_unhovered)
	card.card_selected.connect(_on_card_selected)
	card.brew_wanted.connect(_on_brew_wanted)
	card.reveal_wanted.connect(_on_reveal_wanted)
	# Born locked if AUTO is already running, so there is never a frame in
	# which a fresh card is clickable during an automatic pick.
	card.set_locked(_auto_is_on())
	if data != null:
		offered_cards.append(data)

	# NO SECOND STAR BADGE. The shared card face draws the Star marker
	# itself now (see MenuSupport.card_face), so flagging it here as well
	# put two badges in the same corner. _flag_card_as_star() below is kept
	# in case you want a bigger marker on the pitch than on the shelf.


# =============================================================
#  POURING A BREW ON A CARD, MID-DRAFT
#
#  The Pub is where you plan; this is where you react. You are looking at
#  four cards and about to choose one, and THAT is the moment you know which
#  of them wants to be something else — so the flask is on the card rather
#  than three screens away.
#
#  NOTHING NEW IS STORED. It is the same pour the Pub does: it costs the same
#  materials out of Brews.csv, it needs the same unlock, it lays the same
#  overlay on the card, and the same line at the final whistle takes it off
#  again — see BrewDB.clear_temporary(), which the whistle already calls.
#  A brew poured here is a ONE-MATCH brew and is never made permanent, because
#  making a permanent decision in the middle of a match is not a thing anybody
#  meant to do.
# =============================================================

func _on_brew_wanted(card: PlayerData) -> void:
	if card == null or state == null:
		return
	if _auto_is_on():
		return

	var bag := InventoryScreen.open(self, state, InventoryScreen.Use.ON_CARD,
		"Using something on %s. It wears off at the final whistle." % card.player_name)
	bag.used.connect(func(entry: Dictionary) -> void:
		_use_on_card(card, entry)
		if is_instance_valid(bag):
			bag.close())


## ============ USING A CARRIED ITEM ON A CARD ============
##
## The item is SPENT — one comes off the counter — and whatever its `Use`
## column says happens to this player. Today that is `brew:<id>`, which lays
## the named row of Brews.csv over the card: a new class, new art and new
## abilities until the final whistle.
##
## NOTHING IS MADE HERE. A brew is bottled at the Brewery, which is a building
## with a recipe in its Action column; the bag holds the bottle. That is the
## difference between an inventory and a workshop, and it is why this spends
## the ITEM rather than the reed it was made from.
func _use_on_card(card: PlayerData, entry: Dictionary) -> void:
	var item_id := String(entry.get("id", ""))
	if item_id == "" or state.count(item_id) <= 0:
		return

	var brew_id := AdventureDB.brew_in_use(entry)
	if brew_id == "":
		announce("%s cannot be used on a player." % entry.get("name", "That"), 1.5)
		return

	var brew := BrewDB.get_db().find(brew_id)
	if brew.is_empty():
		push_warning("[brew] %s has Use brew:%s but Brews.csv has no such row."
			% [item_id, brew_id])
		return

	# THE CLASS RULE STILL APPLIES. A Fire Brew is written For Class Lorelei,
	# and a Brandteufel drinking it would be nonsense — so it is refused here,
	# out loud, and the bottle is NOT spent.
	if not BrewDB.suits(brew, card):
		announce("%s cannot drink that." % NamePlate.short_name(card), 1.5)
		print("[brew] %s is not %s — refused, nothing spent." % [
			card.player_name, brew.get("for_class", "?")])
		return

	state.add_count(item_id, -1)
	# THE BOTTLE IS THE COST. pour() would also charge the brew's material
	# Cost, which is what the Brewery already took to make it — so the overlay
	# is laid on directly rather than going through the Pub's till.
	state.set_text(BrewDB.TEMP_PREFIX + BrewDB.card_key(card), brew_id)
	BrewDB.get_db().apply_all(db, state)
	state.save_to_disk()

	_redraw_offered_cards()
	announce("%s drinks %s." % [NamePlate.short_name(card),
		brew.get("name", "it")], 1.6)
	print("[brew] %s used on %s mid-draft. %d left." % [
		entry.get("name", item_id), card.player_name, state.count(item_id)])


## Rebuild the faces in the card row without changing which cards are on
## offer. A brewed card wears different art, a different class and different
## abilities, and all three are drawn on the face.
func _redraw_offered_cards() -> void:
	if card_container == null:
		return
	for child in card_container.get_children():
		var card := child as PlayerCardUI
		if card != null and card.current_data != null:
			card.setup_card(card.current_data)
			card.set_locked(_auto_is_on())


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

	AudioDirector.fire(get_tree(), "card_hovered", _facts_for_card(data), state)


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


## The facts a card carries, for Audio.csv and anything else that wants to
## tell one card apart from another.
func _facts_for_card(card: PlayerData) -> Dictionary:
	if card == null:
		return {}
	return {
		"card": card.player_name,
		"class": card.active_unit_type(),
		"tier": card.get_tier_clean(),
		"star": "yes" if card.is_star() else "no",
		"brew": card.brew_id,
	}


# =============================================================
#  SHOW — PLAYING A CARD FACE UP  (the `reveal` trigger)
#
#  ============ THE TRADE ============
#
#  Every pick until now has been simultaneous and hidden: you choose, they
#  choose, the cards meet. SHOW breaks that on purpose, in one direction only.
#
#      you press SHOW      the card is chosen AND named out loud
#      they answer it      knowing exactly what they are answering
#      the card fires      whatever it has written against `reveal`
#
#  So the ability is not free. It costs the one thing a hidden draft gives
#  you, which is that they have to guess — and a card worth showing has to be
#  worth more than the guess.
#
#  ============ WHY THE ENEMY ANSWERS PROPERLY ============
#
#  They pick at random when your card is hidden, because there is nothing to
#  pick against. Once you have shown one, they take the best answer they have
#  in that tier: the strongest defence if you are attacking this round, the
#  strongest attack if you are not. If the sides ever swap mid-round, the same
#  line follows the swap, because it asks the round rather than remembering.
#
#  ============ IF BOTH SIDES SHOW ============
#
#  AbilityTriggers.csv says the LOWER POWER goes first, which is the ordinary
#  ability-priority rule the duel already runs on — lower priority resolves
#  first, attacker breaks a tie. A shown card is given a priority of its own
#  power, so two shown cards resolve weakest-first with nothing special added
#  to the duel code.
# =============================================================

## Which of your cards has been shown, by tier. Cleared each round.
var revealed_by_tier: Dictionary = {}
## And which of THEIRS. Their rules in EnemyPlay.csv decide whether they show
## one; see _enemy_reveals().
var enemy_revealed_by_tier: Dictionary = {}
## The strip above the card row that holds whatever is face up.
var _table: RevealStrip = null


func _on_reveal_wanted(selected_data: PlayerData) -> void:
	if selected_data == null or _auto_is_on():
		return
	if current_phase_index >= draft_phases.size():
		return
	var phase := draft_phases[current_phase_index]
	# The Star phases are a different choice — you are swapping who is on the
	# pitch, not answering anybody, so there is nothing to show them.
	if phase == "Star" or phase == "StarChoice":
		_on_card_selected(selected_data)
		return

	revealed_by_tier[phase] = selected_data
	if abilities != null:
		abilities.fire_reveal(selected_data, false)
	# ON THE TABLE, not just in the log. A reveal you cannot see is a rule,
	# not a moment — the card goes face up above the row you are choosing
	# from, where both sides can read it while the tier is still open.
	_put_on_the_table(selected_data, false)
	announce("%s is played face up." % NamePlate.short_name(selected_data), 1.6)
	print("[reveal] you show %s in Tier %s. They answer it knowing."
		% [selected_data.player_name, phase])
	_on_card_selected(selected_data)


## ============ THE OTHER SIDE SHOWS ONE ============
##
## Called from _enemy_pick_for_tier() the moment their rules say to play a
## card face up, which is while the tier is still open — the whole value of
## knowing is that there is still a choice left to make with it.
func _enemy_reveals(tier_key: String, card: PlayerData) -> void:
	enemy_revealed_by_tier[tier_key] = card
	if abilities != null:
		abilities.fire_reveal(card, true)
	_put_on_the_table(card, true)
	announce("They play %s face up." % NamePlate.short_name(card), 1.8)
	print("[reveal] they show %s in Tier %s." % [card.player_name, tier_key])


## The strip above the card row. Made the first time anything is shown and
## kept afterwards, because a tier that reveals nothing should not have an
## empty box sitting over it.
func _put_on_the_table(card: PlayerData, is_enemy: bool) -> void:
	if not db.tune_bool("reveal_strip", true):
		return
	if _table == null or not is_instance_valid(_table):
		_table = RevealStrip.make(db)
		var holder := get_node_or_null("SelectionUI")
		if holder == null:
			return
		holder.add_child(_table)
		_place_the_table()
	_table.show_card(card, is_enemy)


## Above the row of cards, the full width of the window, so it reads as a
## table the cards are being played onto rather than as another window.
func _place_the_table() -> void:
	if _table == null or card_container == null:
		return
	var high := db.tune_float("reveal_strip_height", 120.0)
	_table.set_anchors_preset(Control.PRESET_TOP_WIDE, true)
	_table.anchor_top = card_container.anchor_top
	_table.anchor_bottom = card_container.anchor_top
	_table.anchor_left = 0.0
	_table.anchor_right = 1.0
	var inset := db.tune_float("reveal_strip_inset", 220.0)
	_table.offset_left = inset
	_table.offset_right = -inset
	# Hung ABOVE the row: the cards' own box starts half a card above the
	# anchor, so the strip ends where that begins.
	var card_box := PlayerCardUI.card_size()
	_table.offset_bottom = -card_box.y * 0.5 - 12.0
	_table.offset_top = _table.offset_bottom - high


## Take both cards off the table — the tier is settled.
func _clear_the_table() -> void:
	if _table != null and is_instance_valid(_table):
		_table.clear()


func _on_card_selected(selected_data: PlayerData) -> void:
	AudioDirector.fire(get_tree(), "card_picked", _facts_for_card(selected_data), state)
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


## STAR PLAYER SWITCH: one of your other Stars comes on for the one that is playing.
##
## THE STAR TIER DOES NOT MOVE. The incoming Star steps into the outgoing
## Star's slot on the pitch, so it must belong to the same tier — otherwise
## a Tier IV Star ends up standing in the Tier I position, and the tier
## bookkeeping used to follow it there rather than stopping it.
##
## Your own Stars are a ladder in one tier (see star_ladder_for_class), so
## this can only fire on a hand-edited CSV. It refuses rather than fields it.
func _resolve_star_rotation(chosen: PlayerData) -> void:
	var chosen_tier := chosen.get_tier_clean()
	if player_star_tier != "" and chosen_tier != player_star_tier:
		print("[stars] %s is Tier %s and your Star slot is Tier %s — not swapping. Give the class's Stars one tier between them in the unit CSV."
			% [chosen.player_name, chosen_tier, player_star_tier])
		available_player_stars.erase(chosen)
		return

	_swap_star_on_pitch(chosen, false)
	active_player_star = chosen
	available_player_stars.erase(chosen)
	print("New active Star: %s (Tier %s)" % [chosen.player_name, player_star_tier])


## STAR PLAYER SWITCH substitution. Play stops, the outgoing Star jogs off the nearest
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
	#
	# THROUGH unit_for_card(), not by comparing data, because a stand-in is a
	# card with somebody else's body: the man who gets tired is the survivor
	# who agreed to play out of position, not the card that was drawn for him.
	var picked := unit_for_card(selected_data, false)
	for unit in _all_units():
		if unit.is_enemy or unit.is_star_player:
			continue
		if unit == picked:
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

	# ============ THEY READ THEIR RULES AND PICK ============
	#
	# Not an AI — a list of rules in EnemyPlay.csv, read top to bottom, first
	# match wins. See enemy_play.gd for what a row may say. The old behaviour,
	# "take one at random", is the last row of that file, so deleting the rest
	# puts the game back exactly as it was.
	var cards: Array = []
	for unit in choices:
		if unit.data != null:
			cards.append(unit.data)
	# THEY GET STAND-INS TOO. A red card costs them the same thing it costs
	# you, and an enemy tier that quietly kept fielding three men while yours
	# was down to two would be the worst kind of unfairness: invisible.
	cards.append_array(_stand_ins_for(tier_key, true, choices))

	var verdict: Dictionary = EnemyPlay.decide({
		"tier": tier_key,
		"style": _their_play_style(),
		"you_revealed": revealed_by_tier.get(tier_key, null),
		"attacking": not player_attacks_this_round,
		"their_goals": enemy_score,
		"your_goals": player_score,
		"round": rounds_this_cycle,
		"choices": cards,
		"state": state,
	})

	# WHAT THEY PICKED IS A CARD; WHO PLAYS IT IS LOOKED UP. Those are the
	# same thing for everybody except a stand-in, and keeping them apart here
	# is what lets a stand-in be an ordinary choice rather than a special case.
	var chosen_card: PlayerData = cards.pick_random() as PlayerData
	var wanted = verdict.get("card", null)
	if wanted != null and cards.has(wanted):
		chosen_card = wanted as PlayerData
	var chosen := unit_for_card(chosen_card, true)
	if chosen_card == null or chosen == null:
		return
	if String(verdict.get("rule", "")) != "":
		print("[enemy] Tier %s: %s by rule '%s'%s" % [tier_key,
			chosen_card.player_name, verdict["rule"],
			" — face up" if bool(verdict.get("face_up", false)) else ""])

	# ---- AND IF THEY ARE SHOWING IT, THEY SHOW IT NOW ----
	#
	# "The enemy player has to reveal their card right away if they are going
	# to use it." So the reveal happens HERE, as they pick, while the tier is
	# still open — not when the duel starts, by which time knowing is no use
	# to anybody.
	if bool(verdict.get("face_up", false)):
		_enemy_reveals(tier_key, chosen_card)

	# ---- AND WHATEVER ELSE THE RULE SAYS TO DO ----
	#
	# The `Do` column, in the same words every other spreadsheet uses. It is
	# what lets the opening match be scripted — `brew:fire` pours one on the
	# card they have just taken, which is the moment in the story where you
	# find out brews exist at all.
	var do_text := String(verdict.get("do", "")).strip_edges()
	if do_text != "":
		_enemy_does(do_text, chosen_card)

	for unit in choices:
		if unit == chosen:
			unit.is_exhausted = true
			unit.is_playmaker = true
			unit.set_highlight(true)
		else:
			unit.set_highlight(false)
	round_enemy_picks.append(chosen_card)


## ============ A SCRIPTED THING THE OTHER SIDE DOES ============
##
## `brew:<id>` pours a brew on the card they have just taken, exactly the way
## the Pub and the flask do — same row of Brews.csv, same overlay, same wear
## off at the final whistle. Anything else is handed to the ordinary effects
## language, so `announce:`, `flag:` and `count:` all work here too.
func _enemy_does(term: String, card: PlayerData) -> void:
	var colon := term.find(":")
	var kind := term.substr(0, colon).strip_edges().to_lower() if colon > 0 else ""
	var rest := term.substr(colon + 1).strip_edges() if colon > 0 else ""

	if kind == "brew":
		var brew := BrewDB.get_db().find(rest)
		if brew.is_empty():
			push_warning("[enemy] Do said brew:%s but Brews.csv has no such row." % rest)
			return
		if not BrewDB.suits(brew, card):
			print("[enemy] %s cannot drink %s — the For Class column refused it."
				% [card.player_name, rest])
			return
		state.set_text(BrewDB.TEMP_PREFIX + BrewDB.card_key(card), rest)
		BrewDB.get_db().apply_all(db, state)
		_redraw_offered_cards()
		announce("They pour %s on %s." % [brew.get("name", rest),
			NamePlate.short_name(card)], 1.8)
		print("[enemy] %s drinks %s." % [card.player_name, rest])
		return

	if kind == "announce":
		announce(rest, db.tune_float("progression_announce_seconds", 1.6))
		return

	DialogueGrammar.apply(term, state)


## WHICH SET OF RULES THIS OPPONENT PLAYS BY. The `Play Style` column of
## Teams.csv, which is blank out of the box — a blank style uses the rows of
## EnemyPlay.csv that have a blank Style, which is all of them.
func _their_play_style() -> String:
	return String(enemy_team.get("play_style", "")).strip_edges()


## What the ENEMY is judged on when they are answering a card they can see.
## Their defence when you are attacking this round, their attack when you are
## not — asked of the round rather than remembered, so a side swap mid-round
## is followed rather than ignored.
func _answering_power(card: PlayerData) -> int:
	if card == null:
		return -1
	return card.get_defense_power() if player_attacks_this_round \
		else card.get_attack_power()


func _on_draft_complete() -> void:
	# The draft is over; the banner belongs to the draft.
	var banner := SideBanner.find_on(self)
	if banner != null:
		banner.hide_it()

	# Kickoff / STAR PLAYER SWITCH drafts have no combat — just restart the clock.
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

	# ============ THE THROW GOES TO A TEAM-MATE ============
	#
	# "The throw goes to a team-mate, and that player starts the relay to the
	#  Tier I attacker."
	#
	# So the ball does not simply appear at the feet of whoever is duelling
	# first. It is thrown to somebody standing on the pitch, and the relay
	# starts FROM HIM — which is what makes the throw-in a real restart
	# rather than a menu that hands the ball over.
	await _take_the_throw()

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
		# WHOSE BALL IT WAS GOING IN. Kept because `player_has_ball` is
		# flipped by a turnover further down, and the duel has to be reported
		# against the side that was attacking — see the note there.
		var was_mine := player_has_ball
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
		# A card played face up in the draft resolves on its POWER rather than
		# on its Ability Priority — see _on_reveal_wanted(). An empty list is
		# passed when nothing was shown, which is the ordinary round.
		# BOTH SIDES' face-up cards. AbilityTriggers.csv promises that if both
		# show, the lower power resolves first, and that can only be kept if
		# the list knows about theirs as well as yours.
		var face_up: Array = revealed_by_tier.values()
		face_up.append_array(enemy_revealed_by_tier.values())
		abilities.resolve_duel_abilities(atk, attacker_is_enemy, def, "", face_up)

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

		# ============ THE WIN SOUND ON A LOSS ============
		#
		# "The win/lose sounds don't fit — it plays the win sound when I lose
		# and the reverse sometimes too."
		#
		# It was reading `player_has_ball`, which the turnover above had
		# ALREADY FLIPPED. Work the four cases through:
		#
		#     you attack and hold    wins=true,  ball still yours   -> won   ok
		#     you attack and lose    wins=false, ball now theirs    -> WON   wrong
		#     you defend and hold    wins=false, ball now yours     -> LOST  wrong
		#     you defend and lose    wins=true,  ball still theirs  -> lost  ok
		#
		# Exactly half of them inverted, which is precisely "sometimes". It
		# asks `was_mine` now — whose ball it was going INTO the duel — so
		# the answer no longer depends on what the duel did to possession.
		var my_unit := unit_for_card(mine, false)
		var i_won := attacker_wins == was_mine
		if i_won:
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

	# ============ AND THEN THE REFEREE ============
	#
	# After the combat, before the shot. See the FOULS section below.
	var fouls: Dictionary = await _settle_fouls(player_lineup, enemy_lineup)
	player_bank += int(fouls["player_bonus"])
	enemy_bank += int(fouls["enemy_bonus"])
	if int(fouls["possession_to"]) >= 0:
		player_has_ball = int(fouls["possession_to"]) == 0
		# The set piece is taken by whoever was last up that side, so the man
		# who shoots is a man who was in the round rather than whoever the
		# fallback happens to find nearest the goal.
		var set_piece: Array = player_lineup if player_has_ball else enemy_lineup
		for i in range(set_piece.size() - 1, -1, -1):
			if set_piece[i] != null:
				round_shooter_card = set_piece[i]
				break

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


# =============================================================
#  FOULS, CARDS AND THE HOLE A RED CARD LEAVES
#
#  The rules and the reasoning are in src/core/foul_book.gd; the numbers are
#  in data/Fouls.csv. This section is only the part that needs a pitch.
#
#  ============ WHEN IT HAPPENS ============
#
#  AFTER the four duels and BEFORE the shot, which is the order you asked
#  for: "after the combat their % of creating a foul is established". It also
#  happens to be the only place it can go and still matter — a free kick
#  awarded after the shot is a free kick awarded to nobody.
#
#  ============ WHAT A FOUL IS WORTH ============
#
#      any foul      `foul_free_kick_power` on the fouled side's shot
#      a card        and the fouled side takes the ball
#
#  A card stops the game; that is what makes it the moment a side gets the
#  set piece. `foul_card_gives_possession` turns that half off if you would
#  rather a booking were only a booking.
# =============================================================

## Roll both sides, show what happened, hand out the cards.
##
## Returns what the shot should know about it:
##     player_bonus / enemy_bonus   extra shot power
##     possession_to                -1 nobody, 0 you, 1 them
func _settle_fouls(player_lineup: Array, enemy_lineup: Array) -> Dictionary:
	var out: Dictionary = {"player_bonus": 0, "enemy_bonus": 0, "possession_to": -1}
	if db == null or not db.tune_bool("fouls", true) or abilities == null:
		return out
	if FoulBook.rows().is_empty():
		return out

	var free_kick := db.tune_int("foul_free_kick_power", 3)
	var card_gives_ball := db.tune_bool("foul_card_gives_possession", true)

	# PRINTED EVERY ROUND, foul or no foul. The foul chance is a function of
	# this number and nothing else, so when the cards feel too frequent or too
	# rare this line in the Output panel is where the answer is — before
	# touching a single row of Fouls.csv.
	print("  Triggers this round: you %d, them %d." % [
		abilities.triggers_for(false), abilities.triggers_for(true)])

	# BOTH SIDES ARE ROLLED, yours first — only so that the match log reads
	# the same way round every time.
	for offender_is_enemy in [false, true]:
		var many := abilities.triggers_for(offender_is_enemy)
		var verdict := FoulBook.roll(many)
		if verdict == "":
			continue

		var lineup: Array = enemy_lineup if offender_is_enemy else player_lineup
		var culprit := _who_fouled(lineup, offender_is_enemy)
		var odds := FoulBook.odds_at(many)
		print("  FOUL: %s side, %d trigger(s) -> %.0f%% -> %s%s" % [
			"away" if offender_is_enemy else "home", many,
			float(odds["chance"]), verdict,
			"" if culprit == null or culprit.data == null
			else " (" + culprit.data.player_name + ")"])

		if verdict == "yellow":
			await _book_him(culprit, offender_is_enemy)
		elif verdict == "red":
			await _send_off(culprit, offender_is_enemy, "RED CARD")
		else:
			await _show_the_foul("FREE KICK", culprit, offender_is_enemy)

		# YOUR fouls are counted; theirs are not. Every counter in Stats.csv
		# is a counter about you, and a row called "fouls given away" that
		# quietly included the opposition's would be a lie on the end-of-match
		# screen. The sound fires for both — see _show_the_foul().
		if not offender_is_enemy:
			_report("foul_given", _facts_for(culprit))

		# The other side gets the kick.
		if offender_is_enemy:
			out["player_bonus"] = int(out["player_bonus"]) + free_kick
		else:
			out["enemy_bonus"] = int(out["enemy_bonus"]) + free_kick
		if card_gives_ball and verdict != "free kick":
			out["possession_to"] = 0 if offender_is_enemy else 1

	return out


## WHO GAVE IT AWAY. One of the four who played this round, at random,
## because the foul is the side's and the man is the story.
##
## Only somebody still on the pitch: a stand-in's body can be booked (he is a
## real man out there), and anyone already sent off obviously cannot.
func _who_fouled(lineup: Array, side_is_enemy: bool) -> PlayerUnit:
	var pool: Array[PlayerUnit] = []
	for card in lineup:
		var unit := unit_for_card(card as PlayerData, side_is_enemy)
		if unit != null and not unit.is_sent_off and not pool.has(unit):
			pool.append(unit)
	if pool.is_empty():
		# Nobody from the round is available — anyone on that side will do
		# rather than dropping the foul on the floor.
		for unit in _all_units():
			if unit.is_enemy == side_is_enemy:
				pool.append(unit)
	if pool.is_empty():
		return null
	return pool.pick_random()


## A booking. And the second one is a red — the ordinary rule of football,
## which is why it is a line in Tuning.csv and not a line in this file.
func _book_him(unit: PlayerUnit, side_is_enemy: bool) -> void:
	if unit == null:
		await _show_the_foul("YELLOW CARD", null, side_is_enemy)
		return
	unit.yellow_cards += 1
	_cards_shown.append({"side": side_is_enemy, "colour": "yellow",
		"name": unit.data.player_name if unit.data != null else "?"})
	if not side_is_enemy:
		_report("card_yellow", _facts_for(unit))

	if unit.yellow_cards >= 2 and db.tune_bool("foul_two_yellows_is_red", true):
		await _send_off(unit, side_is_enemy, "SECOND YELLOW")
		return
	await _show_the_foul("YELLOW CARD", unit, side_is_enemy)


## Off. And the ladder now has a hole in it — see _stand_ins_for().
func _send_off(unit: PlayerUnit, side_is_enemy: bool, why: String) -> void:
	if unit == null:
		await _show_the_foul(why, null, side_is_enemy)
		return

	_cards_shown.append({"side": side_is_enemy, "colour": "red",
		"name": unit.data.player_name if unit.data != null else "?"})
	if not side_is_enemy:
		_report("card_red", _facts_for(unit))

	# ============ REMEMBER THE HOLE BEFORE HE IS GONE ============
	#
	# His tier and his power, because in a moment unit_for_card() will not be
	# able to find him at all and the draft still has to know what is missing.
	if unit.data != null:
		var tier := unit.data.get_tier_clean()
		var power := unit.data.base_power_left
		var key := _hole_key(side_is_enemy, tier)
		var holes: Array = _ladder_holes.get(key, [])
		if not holes.has(power):
			holes.append(power)
		_ladder_holes[key] = holes
		var whose := "Away" if side_is_enemy else "Home"
		print("  SENT OFF: %s (%s, Tier %s P:%d). %s side down to %d." % [
			unit.data.player_name, why, tier, power, whose,
			_still_standing(side_is_enemy)])

	await _show_the_foul(why, unit, side_is_enemy)

	# AFTER the window, so you see the man it is about before he leaves.
	if ball != null and ball.is_carried_by(unit):
		ball.drop()
	unit.send_off()


## The window and the big word. The same window the goal celebration and the
## throw-in use — see anim_window.gd for why there is only one.
func _show_the_foul(headline: String, unit: PlayerUnit, side_is_enemy: bool) -> void:
	var seconds := db.tune_float("foul_window_seconds", 1.6)
	var who := "Them" if side_is_enemy else "You"
	var name_text := unit.data.player_name if unit != null and unit.data != null else who
	AudioDirector.fire(get_tree(), "foul_shown", {"card": headline.to_lower()}, state)
	if seconds <= 0.0:
		return

	var window := AnimWindow.open(self, db, 150)
	if is_instance_valid(window):
		window.show_panel("%s — %s" % [headline, name_text], "", "lose",
			unit.data if unit != null else null, ["lose", "idle"])
	await get_tree().create_timer(seconds, true, false, true).timeout
	if is_instance_valid(window):
		window.close()


func _hole_key(side_is_enemy: bool, tier_key: String) -> String:
	return "%s|%s" % ["enemy" if side_is_enemy else "you", tier_key.to_upper()]


func _still_standing(side_is_enemy: bool) -> int:
	var many := 0
	for unit in _all_units():
		if unit.is_enemy == side_is_enemy:
			many += 1
	return many


# =============================================================
#  THE STAND-IN
#
#  "Tier III P:3 has gotten a red card. So now there are Tier III P:2 and P:4
#   left. Either P:2 or P:4 at random will be chosen a replacement, keeping
#   their Tier III and P:x name but getting the P:3 and having all abilities
#   removed."
#
#  A red card breaks THE ONE RULE — a tier holds one card of each power — so
#  the tier borrows a body to stand on the empty rung. He keeps his name, he
#  takes the missing power, and he loses everything that made him good at
#  anything, which is what playing out of position feels like.
#
#  A NEW COPY IS MADE EVERY DRAFT PHASE, on purpose: the donor is drawn at
#  random each time, so who covers the gap changes from round to round the
#  way it would in a real match.
# =============================================================

## The extra cards this tier should be offered because of red cards.
## Empty — and free — in a match with no sendings-off, which is most of them.
func _stand_ins_for(tier_key: String, side_is_enemy: bool,
		survivors: Array) -> Array[PlayerData]:
	var out: Array[PlayerData] = []
	if db == null or not db.tune_bool("foul_stand_ins", true):
		return out
	var holes: Array = _ladder_holes.get(_hole_key(side_is_enemy, tier_key), [])
	if holes.is_empty() or survivors.is_empty():
		return out

	for power in holes:
		# Somebody fit is already covering that rung — no stand-in needed.
		var covered := false
		for unit in survivors:
			var body := unit as PlayerUnit
			if body != null and body.data != null and body.data.base_power_left == int(power):
				covered = true
				break
		if covered:
			continue

		var donor := (survivors.pick_random()) as PlayerUnit
		if donor == null or donor.data == null:
			continue
		var card := FoulBook.stand_in_for(donor.data, int(power))
		if card == null:
			continue
		_stand_in_bodies[card] = donor
		out.append(card)
		print("[fouls] %s Tier %s has no P:%d — %s covers it (no abilities)." % [
			"Their" if side_is_enemy else "Your", tier_key.to_upper(),
			int(power), donor.data.player_name])
	return out


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
		restart_hold = false
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
		if scored:
			Juice.fire(self, "goal_scored", {})
			# THE CELEBRATION. What happens, in what order and for how long is
			# every one of it a row of Celebration.csv — including the word
			# GOAL itself, which is why there is no announce() on this branch
			# any more. An empty spreadsheet puts it back exactly as it was.
			await _celebrate_goal(shooter, shooter_is_player)
		else:
			await announce("MISS", db.tune_float("verdict_seconds", 1.4))

		if scored:
			# Restart from the centre. The side that CONCEDED kicks off, and
			# target_key is exactly that side (it owns the beaten keeper).
			await _let_them_shape_up(db.tune_float("goal_pause_seconds", 2.0))
			ball.global_position = get_play_rect().get_center()
			# AND THEY GO. Ordinary rules again from the touch of the ball.
			restart_hold = false
			give_ball_to(target_key)
		else:
			# --- 4. Saved: the keeper hoofs it upfield to their own side ---
			#
			# The order matters. Everybody walks home FIRST, with the keeper
			# left alone on the ball, and only then is it kicked — so the ball
			# arrives into a pitch that has a shape, rather than into the
			# scrum that had gathered around the keeper.
			await _let_them_shape_up(db.tune_float("save_pause_seconds", 2.0))
			# THE HOLD STAYS ON THROUGH THE KICK. It used to be lifted a line
			# earlier, which handed the pitch back to the ordinary rules while
			# the keeper still had the ball — and the ordinary rules say "the
			# other side has it in my quarter, go and win it". So the two who
			# had just walked home turned round and walked back onto the
			# keeper, which is exactly what you were seeing.
			#
			# The man the kick is aimed at is allowed to move; see
			# restart_receiver.
			await _goal_kick(target_key)
			restart_hold = false

	# The break is over, the ball comes off its rails, and everyone drifts back
	# to their own quarter under the usual zone pull. The players never stopped.
	_end_surge()
	# BELT AND BRACES. restart_hold stops the whole pitch, so a path that
	# leaves it set — a shot that ends early, a keeper that is missing, an
	# await that throws — would look exactly like the game having frozen.
	# It is cleared here as well, on every way out of a round.
	restart_hold = false
	restart_receiver = null
	if ball != null:
		ball.scripted_possession = false
	round_resolved.emit(player_score, enemy_score)
	current_state = MatchState.PLAYING


# =============================================================
#  THE GOAL CELEBRATION
#
#  "Have the player who shot the goal slide on the ground and their teammates
#  surround them. Then show a window open for an animation... confetti and
#  cheering... ALLOW ME TO DICTATE WHAT IS IN THE ANIMATION AND FOR HOW LONG,
#  then it goes back to being with the goalie as before."
#
#  So: nothing in here decides what a celebration IS. It knows how to make
#  seven things happen and `data/Celebration.csv` says which of them happen,
#  in what order, and for how long. Read celebration_book.gd for the columns.
#
#  Three things it is careful about, all of them the same worry — a flourish
#  must never be the thing that breaks a match:
#
#    * an empty or missing spreadsheet is the OLD BEHAVIOUR, to the frame:
#      the word GOAL for `verdict_seconds` and then the restart;
#    * it can always be cut short, and cutting it short still puts everybody
#      back on their feet and hands the ball to the keeper;
#    * every unit it touches is checked for still existing first, because a
#      celebration runs for several seconds and a match can end during one.
# =============================================================

func _celebrate_goal(scorer: PlayerUnit, scored_by_player: bool) -> void:
	var beats := CelebrationBook.steps_for(scored_by_player)
	if db == null or not db.tune_bool("goal_celebration", true) or beats.is_empty():
		await announce("GOAL!", db.tune_float("verdict_seconds", 1.4) if db != null else 1.4)
		return

	var facts := _celebration_facts(scorer, scored_by_player)
	var show := GoalCelebration.open(self, db, _celebration_colours())

	# THE BALL IS DEAD and nobody is steering. `restart_hold` stops the clock
	# — a celebration must not eat the match — and the freeze stops the
	# ordinary rules from dragging people back toward the ball while they are
	# being walked into a huddle by hand.
	restart_hold = true
	restart_receiver = null
	freeze_play(true)

	# THE NAME TAGS COME OFF, except the scorer's. Nine plates inside a
	# hundred-pixel huddle is a black smear with letters in it; one name in
	# the middle of a ring of bodies is a photograph. `celebration_hide_names`
	# puts them all back.
	var name_the_scorer := db.tune_bool("celebration_hide_names", true)
	if name_the_scorer:
		for unit in _all_units():
			unit.plate_hidden = unit != scorer

	for i in beats.size():
		if not is_instance_valid(show) or show.was_cut():
			break
		var beat: Dictionary = beats[i]
		var kind := String(beat["do"])
		var seconds := float(beat["seconds"])

		match kind:
			"slide":
				_slide_the_scorer(scorer, seconds)
			"swarm":
				_swarm_the_scorer(scorer, seconds)
			"confetti":
				show.confetti()
			"sound":
				AudioDirector.play_cue(get_tree(), String(beat["sound"]))
			"say":
				_say_now(CelebrationBook.fill(String(beat["text"]), facts))
			"window":
				show.show_panel(CelebrationBook.fill(String(beat["text"]), facts),
					String(beat["art"]), String(beat["animation"]),
					scorer.data if scorer != null and is_instance_valid(scorer) else null)
			_:
				pass   # "wait" — the row is the number

		await _celebration_beat(seconds, show)

		# ============ A BEAT TIDIES UP AFTER ITSELF ============
		#
		# Both of the beats that put something on the screen take it away
		# again when their Seconds are up, UNLESS the next row is the same
		# kind — which is what makes two window rows a slideshow inside one
		# panel rather than a panel opening and shutting twice, and what
		# stops GOAL! sitting across the middle of the huddle that follows
		# it. (It did, and it looked like a bug.)
		if not _next_beat_is(beats, i, kind):
			if kind == "window" and is_instance_valid(show):
				show.hide_panel()
			elif kind == "say":
				_say_now("")

	# ============ AND EVERYTHING GOES BACK ============
	# Every one of these runs however the celebration ended — finished,
	# skipped, or cut off by the match ending mid-huddle.
	_say_now("")
	if is_instance_valid(show):
		show.close()
	for unit in _all_units():
		unit.stand_up()
		unit.plate_hidden = false
	freeze_play(false)


## Wait, but give up the moment somebody clicks. Sliced rather than one timer
## because a single four-second timer cannot be cancelled, and a celebration
## you asked to skip that then carries on for three more seconds is worse
## than one you could not skip at all.
func _celebration_beat(seconds: float, show: GoalCelebration) -> void:
	if seconds <= 0.0:
		await get_tree().process_frame
		return

	# ============ AN ABSOLUTE DEADLINE, NOT A COUNTDOWN ============
	#
	# The first version subtracted each slice from a running total, which
	# drifts: a timer asked for 0.08 seconds fires on the first frame AFTER
	# 0.08 seconds, so every slice overshoots by up to a frame and thirteen
	# of them per second added up to the huddle forming half a second after
	# the picture of the huddle was taken. Measured, not guessed.
	#
	# A deadline in real milliseconds is self-correcting: a slice that ran
	# long simply makes the next one shorter, and the beat ends when your
	# Seconds say it ends.
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while true:
		if not is_instance_valid(show) or show.was_cut():
			return
		var left := float(deadline - Time.get_ticks_msec()) / 1000.0
		if left <= 0.0:
			return
		# IGNORING TIME SCALE ON PURPOSE. goal_scored asks Juice for a
		# slow-motion dip, and seconds in your spreadsheet should mean
		# seconds rather than "seconds unless something slowed the game down".
		await get_tree().create_timer(minf(left, 0.08), true, false, true).timeout


## Is the row after this one the same kind of row? Two windows in a row are
## one window showing two things; two `say` rows are one line replacing
## another without a blank frame between them.
func _next_beat_is(beats: Array[Dictionary], index: int, kind: String) -> bool:
	return index + 1 < beats.size() and String(beats[index + 1]["do"]) == kind


## The words Celebration.csv may put in a caption. A placeholder nobody has a
## value for is left as written — see CelebrationBook.fill().
func _celebration_facts(scorer: PlayerUnit, scored_by_player: bool) -> Dictionary:
	var facts: Dictionary = {
		"score": "%d - %d" % [player_score, enemy_score],
		"scorer": "Somebody",
		"team": String(_team_facts(not scored_by_player).get("name", "")),
		"class": "",
		"tier": "",
	}
	if scorer != null and is_instance_valid(scorer) and scorer.data != null:
		facts["scorer"] = scorer.data.player_name
		facts["class"] = scorer.data.unit_type
		facts["tier"] = scorer.data.get_tier_clean()
	return facts


## The confetti palette, as a row of Tuning.csv: hex colours separated by
## spaces. A blank row or a bad colour falls back to the five the window
## ships with, so a typo is dull rather than invisible.
func _celebration_colours() -> Array[Color]:
	var out: Array[Color] = []
	var written := db.tune_text("celebration_confetti_colours", "") if db != null else ""
	for word in written.split(" ", false):
		var text := String(word).strip_edges()
		if text == "":
			continue
		if not text.begins_with("#"):
			text = "#" + text
		if Color.html_is_valid(text):
			out.append(Color.html(text))
	return out


## ============ THE SCORER GOES DOWN ============
##
## Away from the goal he has just scored in and out toward the nearer
## touchline, which is where a real one ends up — the corner flag is where
## the crowd is. Clamped to the grass, because a slide that carries a player
## off the pitch is a player the restart then has to walk all the way back.
func _slide_the_scorer(scorer: PlayerUnit, seconds: float) -> void:
	if scorer == null or not is_instance_valid(scorer) or seconds <= 0.0:
		return
	var rect := get_play_rect()
	var far := db.tune_float("celebration_slide_distance", 180.0)
	var sideways := signf(scorer.global_position.y - rect.get_center().y)
	if is_zero_approx(sideways):
		sideways = 1.0
	var target := scorer.global_position + Vector2(
		-scorer.attack_dir * far, sideways * far * 0.35)
	target.x = clampf(target.x, rect.position.x + 40.0, rect.end.x - 40.0)
	target.y = clampf(target.y, rect.position.y + 40.0, rect.end.y - 40.0)
	scorer.slide_to(target, seconds)


## ============ AND THE REST OF THEM ARRIVE ============
##
## A ring around him, and — this is the part worth the extra fifteen lines —
## each player is given THE SLOT NEAREST TO WHERE HE ALREADY IS. Handing out
## the slots in squad order instead makes half the team run past each other
## on the way to the huddle, which reads as a bug even though every one of
## them ends up in the right place.
func _swarm_the_scorer(scorer: PlayerUnit, seconds: float) -> void:
	if scorer == null or not is_instance_valid(scorer) or seconds <= 0.0:
		return
	var mates: Array[PlayerUnit] = []
	for unit in _all_units():
		if unit != scorer and unit.is_enemy == scorer.is_enemy:
			mates.append(unit)
	if mates.is_empty():
		return

	var rect := get_play_rect()
	var radius := maxf(30.0, db.tune_float("celebration_swarm_radius", 110.0))
	var middle := scorer.global_position

	var slots: Array[float] = []
	for i in mates.size():
		slots.append(TAU * float(i) / float(mates.size()))

	# NEAREST MAN CHOOSES FIRST. He is the one who will be seen to arrive, and
	# the ones further out have further to come and more room to bend on the
	# way, so any slot still going suits them.
	mates.sort_custom(func(a: PlayerUnit, b: PlayerUnit) -> bool:
		return a.global_position.distance_squared_to(middle) \
			< b.global_position.distance_squared_to(middle))

	for mate in mates:
		var bearing := (mate.global_position - middle).angle()
		var best := 0
		var best_gap := INF
		for s in slots.size():
			var gap: float = absf(angle_difference(bearing, slots[s]))
			if gap < best_gap:
				best_gap = gap
				best = s
		var angle: float = slots[best]
		slots.remove_at(best)
		var spot := middle + Vector2(cos(angle), sin(angle)) * radius
		spot.x = clampf(spot.x, rect.position.x + 20.0, rect.end.x - 20.0)
		spot.y = clampf(spot.y, rect.position.y + 20.0, rect.end.y - 20.0)
		mate.run_to(spot, maxf(0.2, seconds))


# =============================================================
#  OUT OF BOUNDS — how a round begins
#
#  "Remove the 1-10 system and use an out of bounds system: a hidden roll
#   decides who gives the ball away, that player kicks it out with an
#   animation window, the closest player from the other side walks to where
#   it went out and stands outside the line, THEN the PLAY MAKER starts."
#
#  Every beat of it is a row of `data/OutOfBounds.csv`, the same shape as
#  Celebration.csv — one row is one beat, `Seconds` is how long before the
#  NEXT row starts, and an empty file opens the round instantly, which is
#  what it did before any of this existed.
#
#  Three things it holds on to, because the rows refer to them:
#
#      _gave_it_away   the player the hidden roll blamed
#      _throw_spot     where on the touchline the ball left
#      _thrower        the opponent who walked over to take it
# =============================================================

var _gave_it_away: PlayerUnit = null
var _throw_spot: Vector2 = Vector2.ZERO
var _thrower: PlayerUnit = null
## true when the ball went out over the TOP touchline rather than the bottom.
var _went_out_high := false


func _put_it_out_of_play() -> void:
	_gave_it_away = null
	_thrower = null
	if db == null or not db.tune_bool("out_of_bounds", true):
		return
	var beats := OutOfBoundsBook.steps()
	if beats.is_empty():
		return

	# The pitch is already frozen by trigger_playmaker_event(); the ball and
	# the two players involved are moved by hand from here.
	var window := AnimWindow.open(self, db, 150)

	for i in beats.size():
		var beat: Dictionary = beats[i]
		var kind := String(beat["do"])
		var seconds := float(beat["seconds"])

		match kind:
			"roll":
				_blame_somebody()
			"kick_out":
				_kick_it_out(seconds)
			"walk_up":
				_walk_up_to_it(seconds)
			"sound":
				AudioDirector.play_cue(get_tree(), String(beat["sound"]))
			"say":
				_say_now(OutOfBoundsBook.fill(String(beat["text"]), _throw_facts()))
			"window":
				# WHOEVER THE BEAT IS ABOUT. A `window` row after the roll is
				# about the man who put it out; after the walk it is about the
				# man taking the throw. Working it out from what has happened
				# rather than from a column keeps the spreadsheet short.
				var who := _thrower if _thrower != null else _gave_it_away
				if is_instance_valid(window):
					window.show_panel(
						OutOfBoundsBook.fill(String(beat["text"]), _throw_facts()),
						String(beat["art"]), String(beat["animation"]),
						who.data if who != null and is_instance_valid(who) else null,
						["lose", "idle"])
			_:
				pass   # "wait" — the row is the number

		await _beat(seconds)

		# A window closes when the next row is not another window; a `say`
		# clears itself the same way. The same rule as the celebration, so
		# the two files behave identically.
		if not _next_is(beats, i, kind):
			if kind == "window" and is_instance_valid(window):
				window.hide_panel()
			elif kind == "say":
				_say_now("")

	_say_now("")
	if is_instance_valid(window):
		window.close()


## Sliced against an absolute deadline rather than counted down, for the same
## reason the celebration is: a timer fires on the first frame AFTER its time,
## so thirteen slices a second each overshoot and the beats drift apart.
func _beat(seconds: float) -> void:
	if seconds <= 0.0:
		await get_tree().process_frame
		return
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while true:
		var left := float(deadline - Time.get_ticks_msec()) / 1000.0
		if left <= 0.0:
			return
		await get_tree().create_timer(minf(left, 0.08), true, false, true).timeout


func _next_is(beats: Array[Dictionary], index: int, kind: String) -> bool:
	return index + 1 < beats.size() and String(beats[index + 1]["do"]) == kind


## ============ THE HIDDEN ROLL ============
##
## Somebody has to have given it away. It is decided out of sight, so the
## moment reads as football rather than as a dice throw — and it is weighted
## by a Tuning row rather than being a straight coin, because "the side that
## is behind gets the ball back a little more often" is a design lever you
## may want and cannot have if this is hard-coded at a half.
func _blame_somebody() -> void:
	var player_loses := randf() < db.tune_float("out_of_bounds_player_chance", 0.5)
	var pool: Array[PlayerUnit] = []
	for unit in _all_units():
		if unit.is_enemy != player_loses and unit.data != null:
			pool.append(unit)
	if pool.is_empty():
		return
	# THE ONE NEAREST THE BALL. Whoever was closest to it is the one who
	# would have had it, and blaming a defender standing forty yards away
	# for a ball he never touched is the kind of thing a player notices.
	var here := ball.global_position if ball != null else get_play_rect().get_center()
	pool.sort_custom(func(a: PlayerUnit, b: PlayerUnit) -> bool:
		return a.global_position.distance_squared_to(here) \
			< b.global_position.distance_squared_to(here))
	_gave_it_away = pool[0]
	print("  Out of bounds: %s put it out." % _who(_gave_it_away))


## ============ HE PUTS IT OUT ============
##
## Straight over the NEARER touchline, from where he is standing. The spot is
## kept inside the pitch's length so a throw is never taken from behind the
## goal line, which is a corner and a different thing entirely.
func _kick_it_out(seconds: float) -> void:
	var rect := get_play_rect()
	var from := _gave_it_away.global_position if _gave_it_away != null \
		and is_instance_valid(_gave_it_away) else rect.get_center()

	_went_out_high = from.y < rect.get_center().y
	var edge := rect.position.y if _went_out_high else rect.end.y
	var inset := db.tune_float("throw_in_inset", 26.0)

	_throw_spot = Vector2(
		clampf(from.x + randf_range(-90.0, 90.0),
			rect.position.x + rect.size.x * 0.12,
			rect.end.x - rect.size.x * 0.12),
		edge)

	if ball != null:
		ball.scripted_possession = false
		ball.shoot(_throw_spot + Vector2(0.0, -inset if _went_out_high else inset))
	if _gave_it_away != null and is_instance_valid(_gave_it_away):
		Juice.fire(self, "ball_kicked", {"node": _gave_it_away})
	if seconds <= 0.0:
		return


## ============ AND THE OTHER SIDE WALKS OVER ============
##
## The nearest player of the OTHER side, and he stands OUTSIDE the line —
## which is where a throw-in is taken from, and is the detail that makes the
## whole sequence read as football rather than as a menu.
func _walk_up_to_it(seconds: float) -> void:
	if _gave_it_away == null or not is_instance_valid(_gave_it_away):
		return
	var theirs := not _gave_it_away.is_enemy
	var pool: Array[PlayerUnit] = []
	for unit in _all_units():
		if unit.is_enemy == theirs and unit.data != null:
			pool.append(unit)
	if pool.is_empty():
		return
	pool.sort_custom(func(a: PlayerUnit, b: PlayerUnit) -> bool:
		return a.global_position.distance_squared_to(_throw_spot) \
			< b.global_position.distance_squared_to(_throw_spot))
	_thrower = pool[0]

	var stand := _standing_spot()
	_thrower.run_to(stand, maxf(0.2, seconds))
	print("  %s walks over to take the throw." % _who(_thrower))


## ============ THE THROWER CHOOSES ============
##
## What the coin used to decide. Returns true when YOUR side attacks.
func _ask_the_thrower() -> bool:
	if db == null or not db.tune_bool("out_of_bounds", true):
		return await run_rps_clash()      # the old coin, still there
	# No thrower — nobody was on the pitch to take it. Fall back rather than
	# stopping the match over a flourish.
	if _thrower == null or not is_instance_valid(_thrower):
		return randi() % 2 == 0

	var yours := not _thrower.is_enemy
	var view := ThrowInView.open(self, db, yours, _throw_words())
	if _auto_is_on():
		view.auto_play(db.tune_float("auto_pick_seconds", 0.9),
			db.tune_float("auto_attack_chance", 0.5))
	var result: Variant = await view.chosen
	return bool(result)


## ============ OUTSIDE THE LINE, BUT STILL ON THE SCREEN ============
##
## A throw-in is taken from off the pitch, and standing him there is the
## detail that makes the whole sequence read as football. It is also the
## detail that made him INVISIBLE the first time I looked at a screenshot:
## the camera's wide shot is never allowed to show anything past the grass,
## and the white lines run very close to the edge of the grass, so 26 pixels
## outside the line was 18 pixels off the top of the screen.
##
## So the spot is pushed out by `throw_in_inset` and then clamped back into
## the picture. If there is no room to stand outside, he stands ON the line
## — visible and slightly wrong beats correct and invisible.
func _standing_spot() -> Vector2:
	var inset := db.tune_float("throw_in_inset", 26.0)
	var stand := _throw_spot + Vector2(0.0, -inset if _went_out_high else inset)

	var seen := get_visible_world_rect()
	var grass := get_pitch_rect()
	if grass.size.y > 1.0:
		var both := seen.intersection(grass)
		if both.size.y > 1.0:
			seen = both
	var edge := db.tune_float("throw_in_screen_margin", 18.0)
	if seen.size.y > edge * 3.0:
		stand.y = clampf(stand.y, seen.position.y + edge, seen.end.y - edge)
	return stand


## "Bauer throws in from the left touchline, twenty yards out."
func _throw_words() -> String:
	var rect := get_play_rect()
	var side := Loc.text("touchline_top", "the top touchline") if _went_out_high \
		else Loc.text("touchline_bottom", "the bottom touchline")
	var across := 0.5
	if rect.size.x > 1.0:
		across = clampf((_throw_spot.x - rect.position.x) / rect.size.x, 0.0, 1.0)
	var third := Loc.text("third_middle", "the middle third")
	if across < 0.34:
		third = Loc.text("third_left", "the left third")
	elif across > 0.66:
		third = Loc.text("third_right", "the right third")
	return "%s takes it from %s, in %s." % [_who(_thrower), side, third]


func _throw_facts() -> Dictionary:
	return {
		"loser": _who(_gave_it_away),
		"thrower": _who(_thrower),
		"side": "you" if (_thrower != null and is_instance_valid(_thrower)
			and not _thrower.is_enemy) else "them",
		"tier": _thrower.data.get_tier_clean() if _thrower != null
			and is_instance_valid(_thrower) and _thrower.data != null else "",
	}


func _who(unit: PlayerUnit) -> String:
	if unit == null or not is_instance_valid(unit) or unit.data == null:
		return Loc.text("somebody", "Somebody")
	return unit.data.player_name


## ============ THE THROW ITSELF ============
##
## The thrower is standing outside the line. He throws to the NEAREST
## team-mate who is actually on the pitch, and the ordinary relay picks it up
## from there and carries it to the Tier I attacker.
##
## He stays outside the line while he throws, which is correct, and walks
## back on his own the moment the pitch is unfrozen.
func _take_the_throw() -> void:
	if db == null or not db.tune_bool("out_of_bounds", true):
		return
	if _thrower == null or not is_instance_valid(_thrower) or ball == null:
		return

	var mates: Array[PlayerUnit] = []
	for unit in _all_units():
		if unit != _thrower and unit.is_enemy == _thrower.is_enemy and unit.data != null:
			mates.append(unit)
	if mates.is_empty():
		return

	# NEAREST, because a throw-in is a short ball. A thrower picking out
	# somebody forty yards away is a highlight, not a restart.
	mates.sort_custom(func(a: PlayerUnit, b: PlayerUnit) -> bool:
		return a.global_position.distance_squared_to(_thrower.global_position) \
			< b.global_position.distance_squared_to(_thrower.global_position))
	var receiver := mates[0]

	ball.global_position = _thrower.global_position
	ball.scripted_possession = true
	Juice.fire(self, "ball_kicked", {"node": _thrower})
	ball.deliver_to(receiver)
	await ball.delivery_arrived
	print("  Throw-in: %s to %s." % [_who(_thrower), _who(receiver)])

	var beat := db.tune_float("throw_in_settle_seconds", 0.35)
	if beat > 0.0:
		await get_tree().create_timer(beat).timeout


## ============ THE PAUSE BEFORE A RESTART ============
##
## The break is over the moment the ball is dead, not when play restarts. It
## used to be ended afterwards, so the two teams were still in their attacking
## shape when the keeper kicked — the whole front line up one end, nobody in
## the middle, and a restart into a pitch that made no sense.
##
## Ending the surge here and then holding for a couple of seconds gives
## everybody time to walk back to their own quarter first. Nobody sprints;
## they simply set off earlier and the restart waits for them.
##
##     goal_pause_seconds    the hold after a goal
##     save_pause_seconds    the hold before the keeper kicks
##     restart_walk_boost    how briskly they walk home
##
## THE CALLER CLEARS `restart_hold`, not this function — it has to stay true
## until the ball is actually kicked, which is a line or two later.
func _let_them_shape_up(seconds: float) -> void:
	_end_surge()
	restart_hold = true
	restart_receiver = null
	restart_walk_boost = maxf(0.2, db.tune_float("restart_walk_boost", 1.6))

	# ============ THEY ARE WALKED HOME, NOT ASKED TO STEER HOME ============
	#
	# The first version of this set everyone's ROLE to "go home" and waited.
	# That reads well and does not work, for two reasons that both bite at
	# exactly the wrong moment:
	#
	#   * steering is leashed to a player's own quarter and can be stopped
	#     dead by a freeze (a duel cut-away holds the whole pitch still), so
	#     a player standing in the six-yard box after a shot could simply
	#     stay there;
	#   * and waiting for "is everybody home yet" then never came true, so
	#     the hold ran on and FROZE them there — which is why two of them
	#     ended up stood on the keeper instead of walking away from him.
	#
	# run_to() is the call the substitution and the shot run-up already use.
	# It tweens the player to a point and is not leashed, not steered and not
	# frozen. So the restart is now deterministic: they set off together, and
	# when the walk is over every one of them IS home. Nobody sprints — the
	# time is worked out from the distance, and it is a walk.
	var slack := maxf(10.0, db.tune_float("restart_home_slack", 70.0))
	var walk_speed := maxf(40.0, db.tune_float("restart_walk_speed", 420.0))
	var longest := 0.0

	for unit in _all_units():
		var gap := unit.global_position.distance_to(unit.home_position)
		if gap <= slack:
			continue
		# NOT ONE DURATION FOR EVERYBODY. A player four yards out of position
		# and one at the other end of the pitch both arriving at the same
		# moment is the thing that looks like a video game.
		var takes := clampf(gap / walk_speed, 0.25,
			maxf(0.3, db.tune_float("restart_walk_max_seconds", 2.6)))
		longest = maxf(longest, takes)
		unit.run_to(unit.home_position, takes)

	# The hold is at least as long as the pause you asked for, and at least
	# as long as the longest walk — so the ball is never put back into play
	# with somebody still on their way.
	var wait := maxf(maxf(0.0, seconds), longest)
	if wait <= 0.0:
		return
	await get_tree().create_timer(wait).timeout


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
	restart_receiver = best
	# ============ EVERYBODY GOES WITH THE KICK ============
	#
	# The whole pitch breaks toward the man it is aimed at: his own side to
	# support him, the other side to get there first. That is what happens
	# when a keeper launches one, and the restart used to end with twenty-two
	# people standing still watching the ball travel.
	#
	# It is a WINDOW, not a state — see _converge_target(). It runs down on
	# its own, so nothing has to remember to turn it off.
	converge_on = best
	converge_until = _anim_clock + goal_kick_converge_seconds
	ball.deliver_to(best)
	await ball.delivery_arrived
	restart_receiver = null


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

	# EVERYTHING ON THE PITCH STOPS while the cut-away is up.
	#
	# It did not before, so behind the duel window the other eighteen players
	# carried on running and the ball carried on being kicked about. You were
	# watching two cards fight over a game that had moved on without them.
	freeze_play(true)

	duel_arena.play_duel({
		"tier": tier,
		"left": defender_side if attacker_is_enemy else attacker_side,
		"right": attacker_side if attacker_is_enemy else defender_side,
	})
	await duel_arena.duel_finished

	freeze_play(false)


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
