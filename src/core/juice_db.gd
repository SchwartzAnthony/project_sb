class_name JuiceDB
extends RefCounted

# =============================================================
#  JUICE — the shakes, flashes, pops and sounds, in a spreadsheet
#
#  Everything that makes the game FEEL like something is happening lives in
#  res://data/Juice.csv. No feel is typed into a script any more: the code
#  says "this moment happened", and the spreadsheet decides what that looks
#  and sounds like.
#
#  ============ THE COLUMNS ============
#
#      ID           yours. Two rows may share a `When` — both fire
#      When         the moment. The list is below
#      Who          player / enemy / screen / ball. WHAT gets shaken
#      Shake        how far it jumps, in pixels
#      Shake Scale  how much BIGGER a big hit shakes. See below
#      Flash        seconds of a colour wash. 0 = none
#      Flash Colour #rrggbb
#      Pop          scale it snaps to and back from. 1.10 = 10% bigger
#      Squash       how much it squashes while it pops. 0.14 reads as weight
#      Sound        a row of Audio.csv, or a file name in assets/audio/
#      Slowmo       seconds the whole game runs slow. Use sparingly
#      Notes        yours
#
#  ============ THE MOMENTS ============
#
#      ball_received     a player takes the ball
#      ball_kicked       a player strikes it
#      enemy_hit         your shot lands on an enemy
#      enemy_died        an enemy goes down
#      player_hurt       one of yours takes a hit
#      player_exhausted  one of yours runs out of stamina
#      player_healed     an item mends somebody
#      combo_fired       a combo completes in the build-up
#      shot_struck       the final shot of an Adventure move
#      enemy_windup      an enemy gains its buff
#      goal_scored       a goal in a league match
#      play_maker        PLAY MAKER fires
#      star_switch       STAR PLAYER SWITCH
#
#  A moment nobody wrote a row for simply does nothing. Delete every row and
#  the game plays identically, just flat.
#
#  ============ SHAKE SCALE, WHICH IS THE INTERESTING ONE ============
#
#  You asked for a hit to shake harder when it hurts more. `Shake` is the
#  shake for an AVERAGE hit; `Shake Scale` is how much the size of the hit
#  moves that number:
#
#      Shake Scale 0     every hit shakes the same. Flat, predictable
#      Shake Scale 1.0   a double-strength hit shakes twice as hard
#      Shake Scale 1.5   exaggerated. Small hits barely register, big ones
#                        are an event
#
#  The maths is in strength_of() below and it is deliberately gentle — it is
#  a square root, so a hit ten times as big shakes about three times as hard
#  rather than ten. Ten times would be unwatchable.
#
#  ============ SOUND ============
#
#  The Sound column names a row of Audio.csv, which is where volume, bus and
#  fade already live — so a juice sound is an ordinary game sound and obeys
#  the Sound tab of Settings like everything else. A name Audio.csv has never
#  heard of is looked for as a file in assets/audio/ instead, so you can drop
#  a WAV in and hear it without writing a row first.
# =============================================================

const PATH := "res://data/Juice.csv"

static var _instance: JuiceDB

## When -> Array of rows that fire at that moment.
var moments: Dictionary = {}
var problems: Array[String] = []

const MOMENTS: Array[String] = [
	"ball_received", "ball_kicked", "enemy_hit", "enemy_died", "player_hurt",
	"player_exhausted", "player_healed", "combo_fired", "shot_struck",
	"enemy_windup", "goal_scored", "play_maker", "star_switch",
]
const WHO: Array[String] = ["player", "enemy", "screen", "ball"]


static func get_db() -> JuiceDB:
	if _instance == null:
		_instance = JuiceDB.new()
		_instance.load_all()
	return _instance


## Not reload() — see any other loader for why that name is taken.
static func reload_files() -> void:
	_instance = null
	get_db()


func load_all() -> void:
	moments.clear()
	problems.clear()

	for row in MenuSupport.read_csv(PATH):
		var id_text := MenuSupport.field(row, "ID")
		if id_text == "":
			continue
		var when_text := MenuSupport.field(row, "When").strip_edges().to_lower()
		if not MOMENTS.has(when_text):
			problems.append("Juice.csv row '%s' says When = '%s', which is not a moment. The list is: %s"
				% [id_text, when_text, ", ".join(MOMENTS)])
			continue

		var who := MenuSupport.field(row, "Who", "screen").strip_edges().to_lower()
		if not WHO.has(who):
			problems.append("Juice.csv row '%s' says Who = '%s'. It must be one of: %s"
				% [id_text, who, ", ".join(WHO)])
			who = "screen"

		var entry := {
			"id": id_text,
			"who": who,
			"shake": MenuSupport.field_float(row, "Shake", 0.0),
			"shake_scale": MenuSupport.field_float(row, "Shake Scale", 0.0),
			"flash": MenuSupport.field_float(row, "Flash", 0.0),
			"flash_colour": _colour(MenuSupport.field(row, "Flash Colour"),
				Color(1, 1, 1)),
			"pop": MenuSupport.field_float(row, "Pop", 0.0),
			"squash": MenuSupport.field_float(row, "Squash", 0.0),
			"sound": MenuSupport.field(row, "Sound"),
			"slowmo": MenuSupport.field_float(row, "Slowmo", 0.0),
		}
		if not moments.has(when_text):
			moments[when_text] = [] as Array[Dictionary]
		(moments[when_text] as Array).append(entry)

	for note in problems:
		push_warning("[juice] " + note)
	var total := 0
	for key in moments.keys():
		total += (moments[key] as Array).size()
	print("[juice] %d effect(s) across %d moment(s)." % [total, moments.size()])


## Every row that fires at a moment. Empty is normal and means "do nothing".
static func rows_for(when_text: String) -> Array:
	return get_db().moments.get(when_text.to_lower(), [])


# =============================================================
#  HOW HARD DID THAT HIT?
# =============================================================

## Turn "this hit for 14, an average hit is 6" into a multiplier for Shake.
##
## A SQUARE ROOT ON PURPOSE. Damage in this game can vary by ten times
## between a poke and a four-tier move with combos on it, and multiplying the
## shake by ten would throw the camera off the screen. A square root keeps a
## big hit feeling big while staying watchable: ten times the damage is about
## three times the shake.
static func strength_of(amount: float, average: float, scale: float) -> float:
	if scale <= 0.0 or average <= 0.0:
		return 1.0
	var ratio := maxf(0.05, amount / average)
	return 1.0 + (sqrt(ratio) - 1.0) * scale


static func _colour(text: String, fallback: Color) -> Color:
	var clean := text.strip_edges()
	if clean == "":
		return fallback
	if not clean.begins_with("#"):
		clean = "#" + clean
	if not Color.html_is_valid(clean):
		push_warning("[juice] '%s' is not a colour. Write it as #rrggbb." % text)
		return fallback
	return Color.html(clean)
