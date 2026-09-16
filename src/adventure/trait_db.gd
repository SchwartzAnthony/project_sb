class_name TraitDB
extends RefCounted

# =============================================================
#  THE STACK — what Adventure combat runs on
#
#  ============ THE IDEA IN ONE PARAGRAPH ============
#
#  In a league match a player brings their ABILITIES. In Adventure they bring
#  their ICONS. Every player you send into the move drops their icons onto a
#  stack — Fire, Water, Brandteufel, Star — and the stack is what you are
#  really playing. Three Fire in the stack and every shot is worth four more.
#  Four Wand and a Treant walks on to replace somebody you lost.
#
#  THE STACK DOES NOT EMPTY EACH ROUND. It empties when the CYCLE comes round
#  — when every tier has fielded everybody it has — exactly the way your Stars
#  rotate in a league match. So a fight is not four separate rounds. It is one
#  long build, and the decision in front of you is which icon to add next.
#
#  ABILITIES DO NOTHING IN ADVENTURE. Not "are ignored" — they are not read.
#  The same eleven players are a different game here, which is the point.
#
#  ============ THE THREE SPREADSHEETS ============
#
#  res://data/AdventureTraits.csv     WHAT the icons are
#  res://data/AdventureCombos.csv     WHAT REACHING ONE DOES
#  res://data/AdventureSpawns.csv     the stand-ins a combo can bring on
#
#  ---- AdventureTraits.csv ----
#
#      ID       yours. AdventureCombos.csv points at it
#      Name     what is written under the icon
#      From     WHERE THE ICON COMES FROM. One of:
#                  element   the Element column of your unit CSV — and the
#                            Element column of Brews.csv if they drank
#                            something, so what they drink changes their icon
#                  class     the Unit Type column — and the BREWED class, so
#                            a Lorelei who drank a Fire Brew stacks as a
#                            Brandteufel
#                  star      Player Type = Star. The Value column is ignored
#                  tier      their Tier. Value is I / II / III / IV
#      Value    which value in that column counts. Blank for `star`
#      Icon     a file in assets/icons/. Missing = a coloured pip, which is
#               perfectly playable — draw them when you get to it
#      Colour   #rrggbb, used for the pip and the bar
#      Order    left to right along the top of the screen. Low numbers first
#      Max      how many the bar draws. Usually your biggest breakpoint
#
#  A PLAYER CAN CARRY SEVERAL ICONS. A Lorelei whose Element is Water stacks
#  Water AND Lorelei, from two different rows, and both bars move. That is
#  what makes a squad a decision rather than a sum.
#
#  ---- AdventureCombos.csv ----
#
#      Trait    which row of AdventureTraits.csv this belongs to
#      At       HOW MANY it takes. 2 means "two of this icon in the stack"
#      Name     what flashes up when it fires
#      Effect   attack / strike / heal / stamina / revive / spawn / shield
#      Value    the number. What it means is per effect — see below
#      Target   who or what. Per effect — see below
#      Lasts    held = it applies for as long as you hold that many
#               once = it fires the moment you reach it, and not again until
#                      the cycle comes round
#               blank = the sensible default for that effect, printed on load
#      Icon     THE ICON AT THIS BREAKPOINT, so the picture at the top of the
#               screen changes as you climb. Blank = keep the trait's own
#      Description   the line shown on the bar. Write it for a player
#
#  ONLY THE HIGHEST BREAKPOINT YOU HAVE REACHED IS ACTIVE, for `held`
#  effects. Three Fire gives you Blaze, not Kindling AND Blaze. `once`
#  effects all fire as you pass them, because they already happened.
#
#  ---- WHAT EACH EFFECT DOES ----
#
#      attack    Value is added to the SHOT. Never to a card — a card's power
#                is the tier ladder and nothing is allowed to move it
#      strike    Value damage straight into enemies. Target = all / focus
#      heal      Value stamina back. Target = lowest / all / last
#      stamina   the same as heal. Two names because one reads better in some
#                rows than the other
#      revive    Value knocked-out players get up. Target = how much stamina
#                each one gets, or blank for adventure_revive_stamina
#      shield    Value is taken off every hit against you while you hold it
#      spawn     Value stand-ins walk on. Target = a row of
#                AdventureSpawns.csv
#
#  An Effect this file has never heard of is reported by name on load, with
#  the list of the ones it knows, and that row is skipped. Nothing crashes.
# =============================================================

const TRAITS_PATH := "res://data/AdventureTraits.csv"
const COMBOS_PATH := "res://data/AdventureCombos.csv"
const SPAWNS_PATH := "res://data/AdventureSpawns.csv"

## Where an icon can come from. Adding one here means teaching _icons_of()
## about it as well — it is four lines, and the comment there says where.
const SOURCES: Array[String] = ["element", "class", "star", "tier"]

const EFFECTS: Array[String] = [
	"attack", "strike", "heal", "stamina", "revive", "shield", "spawn",
]

## Which effects go on applying while you hold them, and which happen once.
## Used only to fill in a blank `Lasts` column.
const HELD_BY_DEFAULT: Array[String] = ["attack", "shield"]

static var _instance: TraitDB

## In Order order, so the bar across the top draws itself by walking this.
var traits: Array[Dictionary] = []

## trait id -> Array of breakpoints, lowest At first.
var steps: Dictionary = {}

## spawn id -> its row.
var spawns: Dictionary = {}

var problems: Array[String] = []


static func get_db() -> TraitDB:
	if _instance == null:
		_instance = TraitDB.new()
		_instance.load_all()
	return _instance


## Not reload() — that name belongs to Godot's own Script.reload() and a
## static function called reload() is silently never the one that runs. Every
## loader in this project carries the same note for the same reason.
static func reload_files() -> void:
	_instance = null
	get_db()


# =============================================================
#  LOADING
# =============================================================

func load_all() -> void:
	traits.clear()
	steps.clear()
	spawns.clear()
	problems.clear()

	_read_traits()
	_read_combos()
	_read_spawns()

	for note in problems:
		push_warning("[traits] " + note)
	var step_count := 0
	for key in steps.keys():
		step_count += (steps[key] as Array).size()
	print("[traits] %d icon(s), %d breakpoint(s), %d stand-in(s)."
		% [traits.size(), step_count, spawns.size()])


func _read_traits() -> void:
	for row in MenuSupport.read_csv(TRAITS_PATH):
		var id_text := MenuSupport.field(row, "ID")
		if id_text == "":
			continue
		var from := MenuSupport.field(row, "From", "element").to_lower()
		if not SOURCES.has(from):
			problems.append("AdventureTraits.csv '%s' says From = '%s'. It must be one of: %s"
				% [id_text, from, ", ".join(SOURCES)])
			continue

		traits.append({
			"id": id_text,
			"name": MenuSupport.field(row, "Name", id_text),
			"from": from,
			"value": MenuSupport.field(row, "Value"),
			"icon": MenuSupport.field(row, "Icon"),
			"colour": _colour(MenuSupport.field(row, "Colour"), Color(0.6, 0.65, 0.7)),
			"order": int(MenuSupport.field_float(row, "Order", 100.0)),
			"max": maxi(1, int(MenuSupport.field_float(row, "Max", 4.0))),
			"notes": MenuSupport.field(row, "Notes"),
		})

	traits.sort_custom(func(a, b) -> bool:
		return int(a["order"]) < int(b["order"]))


func _read_combos() -> void:
	var known: Dictionary = {}
	for entry in traits:
		known[String(entry["id"]).to_lower()] = true

	for row in MenuSupport.read_csv(COMBOS_PATH):
		var id_text := MenuSupport.field(row, "ID")
		if id_text == "":
			continue

		var trait_id := MenuSupport.field(row, "Trait").to_lower()
		if not known.has(trait_id):
			problems.append("AdventureCombos.csv '%s' is for Trait '%s', which is not an ID in AdventureTraits.csv"
				% [id_text, trait_id])
			continue

		var effect := MenuSupport.field(row, "Effect", "attack").to_lower()
		if not EFFECTS.has(effect):
			problems.append("AdventureCombos.csv '%s' says Effect = '%s'. It must be one of: %s"
				% [id_text, effect, ", ".join(EFFECTS)])
			continue

		# A BLANK `Lasts` IS FILLED IN RATHER THAN REFUSED, because the right
		# answer is obvious from the effect: a bonus to the shot goes on
		# applying, a revive cannot happen twice.
		var lasts := MenuSupport.field(row, "Lasts").to_lower()
		if lasts != "held" and lasts != "once":
			lasts = "held" if HELD_BY_DEFAULT.has(effect) else "once"

		var at := maxi(1, int(MenuSupport.field_float(row, "At", 1.0)))
		var step := {
			"id": id_text,
			"trait": trait_id,
			"at": at,
			"name": MenuSupport.field(row, "Name", id_text),
			"effect": effect,
			"value": int(MenuSupport.field_float(row, "Value", 0.0)),
			"target": MenuSupport.field(row, "Target"),
			"lasts": lasts,
			"icon": MenuSupport.field(row, "Icon"),
			"description": MenuSupport.field(row, "Description"),
		}
		if not steps.has(trait_id):
			steps[trait_id] = [] as Array[Dictionary]
		(steps[trait_id] as Array).append(step)

	for key in steps.keys():
		(steps[key] as Array).sort_custom(func(a, b) -> bool:
			return int(a["at"]) < int(b["at"]))


func _read_spawns() -> void:
	for row in MenuSupport.read_csv(SPAWNS_PATH):
		var id_text := MenuSupport.field(row, "ID")
		if id_text == "":
			continue
		spawns[id_text.to_lower()] = {
			"id": id_text,
			"name": MenuSupport.field(row, "Name", id_text),
			"power": int(MenuSupport.field_float(row, "Power", 1.0)),
			"tier": MenuSupport.field(row, "Tier").strip_edges().to_upper(),
			"element": MenuSupport.field(row, "Element"),
			"class": MenuSupport.field(row, "Class", "Stand-in"),
			"stamina": maxi(1, int(MenuSupport.field_float(row, "Stamina", 3.0))),
			"art": MenuSupport.field(row, "Art"),
		}


# =============================================================
#  WHICH ICONS A PLAYER CARRIES
# =============================================================

## Every trait id this card puts on the stack. Usually two — one from its
## element and one from its class — and sometimes three with a Star.
##
## WHAT THEY DRANK COUNTS. Both the element and the class are read through
## the brew, so a Fire Brew genuinely changes what a player is worth in the
## stack rather than only changing their picture.
static func icons_of(card: PlayerData) -> Array[String]:
	var out: Array[String] = []
	if card == null:
		return out

	for entry in get_db().traits:
		var from := String(entry["from"])
		var wanted := String(entry["value"]).strip_edges().to_lower()
		var mine := ""
		match from:
			"element":
				mine = card.active_element().strip_edges().to_lower()
			"class":
				mine = card.active_unit_type().strip_edges().to_lower()
			"tier":
				mine = card.get_tier_clean().strip_edges().to_lower()
			"star":
				# THE VALUE COLUMN IS IGNORED for a star row, so that a
				# designer cannot get it subtly wrong by typing "yes".
				if card.is_star():
					out.append(String(entry["id"]))
				continue
			_:
				# A `From` this file does not know about. _read_traits() has
				# already refused it, so this is only here so that adding a
				# new source to SOURCES and forgetting this match is a quiet
				# nothing rather than a crash.
				continue
		if mine != "" and mine == wanted:
			out.append(String(entry["id"]))
	return out


## The same question about an ENEMY, which is a row of AdventureEnemies.csv
## rather than a card. Its Element and its Pool are what it carries.
##
## One table for both sides, deliberately: a combo you write is a rule about
## icons, not a rule about whose side somebody is on.
static func icons_of_enemy(row: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var element := String(row.get("element", "")).strip_edges().to_lower()
	var pool := String(row.get("pool", "")).strip_edges().to_lower()
	var boss := bool(row.get("boss", false))

	for entry in get_db().traits:
		var from := String(entry["from"])
		var wanted := String(entry["value"]).strip_edges().to_lower()
		if from == "star":
			if boss:
				out.append(String(entry["id"]))
		elif from == "element" and element != "" and element == wanted:
			out.append(String(entry["id"]))
		elif from == "class" and pool != "" and pool == wanted:
			out.append(String(entry["id"]))
	return out


# =============================================================
#  READING THE STACK
# =============================================================

## The breakpoints a count has reached, lowest first.
static func reached(trait_id: String, count: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for step in get_db().steps.get(trait_id.to_lower(), []):
		if int((step as Dictionary)["at"]) <= count:
			out.append(step)
	return out


## The HIGHEST breakpoint reached, or {} for none. This is the one that is
## active for a `held` effect, and the one whose Icon the bar shows.
static func best(trait_id: String, count: int) -> Dictionary:
	var hit := reached(trait_id, count)
	return hit[hit.size() - 1] if not hit.is_empty() else {}


## What it would take to reach the next one — the 4 in "3/4". Returns the
## trait's Max once every breakpoint has been reached, so the bar always has
## a number to show.
static func next_at(trait_id: String, count: int) -> int:
	for step in get_db().steps.get(trait_id.to_lower(), []):
		if int((step as Dictionary)["at"]) > count:
			return int((step as Dictionary)["at"])
	return maxi(count, _max_of(trait_id))


static func _max_of(trait_id: String) -> int:
	for entry in get_db().traits:
		if String(entry["id"]).to_lower() == trait_id.to_lower():
			return int(entry["max"])
	return 4


## A trait's row, or {} if the id is not in the spreadsheet.
static func trait_of(trait_id: String) -> Dictionary:
	for entry in get_db().traits:
		if String(entry["id"]).to_lower() == trait_id.to_lower():
			return entry
	return {}


static func _colour(text: String, fallback: Color) -> Color:
	var clean := text.strip_edges()
	if clean == "":
		return fallback
	if not clean.begins_with("#"):
		clean = "#" + clean
	if not Color.html_is_valid(clean):
		push_warning("[traits] '%s' is not a colour. Write it as #rrggbb." % text)
		return fallback
	return Color.html(clean)


# =============================================================
#  STAND-INS
# =============================================================

## Build a real party member out of a row of AdventureSpawns.csv.
##
## `tier` is where it is going — normally the tier of whoever it is
## replacing. A spawn whose own Tier column is filled in overrides that, so
## you can write a stand-in that always arrives in Tier I.
##
## ITS POWER IS CLAMPED INTO THAT TIER'S LEGAL RUNGS. The tier ladder is the
## one rule nothing in this game is allowed to break, and a spawn is not an
## exception — if you write a Treant with power 9 it arrives at the top rung
## of its tier and the log says so.
static func make_spawn(spawn_id: String, tier: String,
		db: CardDatabase = null) -> PlayerData:
	var row: Dictionary = get_db().spawns.get(spawn_id.strip_edges().to_lower(), {})
	if row.is_empty():
		push_warning("[traits] A combo wanted to bring on '%s', which is not an ID in AdventureSpawns.csv."
			% spawn_id)
		return null

	var database := db if db != null else CardDatabase.get_db()
	var landing := String(row["tier"]) if String(row["tier"]) != "" else tier
	if landing == "":
		landing = TierLadder.TIERS[0]

	var rungs := TierLadder.rungs(landing, database)
	var power := int(row["power"])
	if not rungs.is_empty():
		power = clampi(power, rungs[0], rungs[rungs.size() - 1])

	var made := PlayerData.new()
	made.player_name = String(row["name"])
	made.unit_type = String(row["class"])
	made.element = String(row["element"])
	made.player_type = "Normal"
	made.tier = landing
	made.base_power_left = power
	made.base_power_right = power
	made.adventure_stamina = int(row["stamina"])
	made.artwork = MenuSupport.icon_texture(String(row["art"]))
	made.set_meta("spawned", true)
	made.set_meta("spawn_power_wanted", int(row["power"]))
	return made
