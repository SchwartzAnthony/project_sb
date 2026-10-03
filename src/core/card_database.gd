class_name CardDatabase
extends RefCounted

# =============================================================
#  CARD DATABASE — the CSVs ARE the game data
#
#  Everything is read straight out of res://data/*.csv when the match
#  starts. There is no import step and no .tres files to keep in sync.
#  Drop a CSV in, press play, it is in the game.
#
#  HOW FILES ARE RECOGNISED
#  File NAMES do not matter. Each CSV is classified by its header row:
#
#    contains "Unit Type"  + "Base Power Left"  -> unit cards
#    contains "Max Stamina"                     -> goalies
#    contains "Ability ID"                      -> abilities
#    contains "Key" + "Value"                   -> tuning
#
#  COLUMN ORDER DOES NOT MATTER EITHER. Columns are matched by header
#  name (case, spaces and underscores are ignored), so you can reorder
#  them, add your own, or leave optional ones out entirely. Unknown
#  columns are ignored rather than breaking the import.
#
#  ADDING A NEW CLASS / RACE — no code, no editor script:
#    1. Export a CSV with the same headers into res://data/
#    2. Put the artwork PNGs in res://assets/players/
#    3. Optionally add a row to Goalies.csv for its keeper
#    4. Optionally add res://src/formations/<class>_formation.tscn;
#       without one, a formation is generated from the pitch.
# =============================================================

const DATA_DIR := "res://data/"
const PLAYER_ART_DIRS: Array[String] = ["res://assets/players/", "res://assets/"]
const GOALIE_ART_DIRS: Array[String] = ["res://assets/goalies/", "res://assets/players/", "res://assets/"]
const FORMATION_DIR := "res://src/formations/"

static var _instance: CardDatabase

var players: Array[PlayerData] = []
var goalie_data: Array[GoalieData] = []
var abilities: Dictionary = {}      # ability_id (lower) -> AbilityData
var anims: Dictionary = {}          # "name|unittype" (lower) -> AnimSpec
var tuning: Dictionary = {}         # key (lower) -> String
var problems: Array[String] = []    # everything that looked wrong, for one tidy report

## Numbers ADDED on top of Tuning.csv, earned from talents and unlocks.
##
## Any counter in your save named  tune_<something>  lands here and is added
## to the Tuning.csv row of that name. A talent whose Effects say
##     count:tune_press_speed+12
## makes press_speed 12 higher for that save, for good, with no code.
##
## Filled by apply_bonuses_from(). Empty until something calls it.
var bonuses: Dictionary = {}


# =============================================================
#  SINGLETON  (a static var, so there is no autoload to register)
# =============================================================

static func get_db() -> CardDatabase:
	if _instance == null:
		_instance = CardDatabase.new()
		_instance.load_all()
	return _instance


## Re-read every CSV from disk. Handy while tuning.
## RE-READ THE SPREADSHEETS FROM DISK.
##
## NOT CALLED `reload()`. Every class_name in Godot is also a Script object,
## and Script already has a built-in reload() — so `BaseDB.reload()` resolved
## to THAT and printed
##
##     Cannot reload script while instances exist.
##
## while quietly never calling this at all. Naming it reload_files() is the
## whole fix. If you add a loader of your own, avoid reload(), free(),
## duplicate() and get_name() for the same reason.
static func reload_files() -> void:
	_instance = null
	get_db()


# =============================================================
#  LOADING
# =============================================================

func load_all() -> void:
	players.clear()
	goalie_data.clear()
	abilities.clear()
	anims.clear()
	tuning.clear()
	tier_bands.clear()
	problems.clear()

	var dir := DirAccess.open(DATA_DIR)
	if dir == null:
		problems.append("Could not open %s" % DATA_DIR)
		return

	var names := dir.get_files()
	names.sort()

	# PASS ONE: the tier bands, and nothing else. Files are read
	# alphabetically, so TierPowers.csv would otherwise arrive long after the
	# unit CSVs — and a band that is not loaded yet cannot check anything.
	for file_name in names:
		if file_name.to_lower().ends_with(".csv"):
			_load_csv(DATA_DIR + file_name, true)

	# PASS TWO: everything else, now that a card can be checked as it is read.
	for file_name in names:
		if file_name.to_lower().ends_with(".csv"):
			_load_csv(DATA_DIR + file_name, false)

	_report()


func _load_csv(path: String, bands_only: bool = false) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		problems.append("Could not read %s" % path)
		return
	var rows := parse_csv(file.get_as_text())
	file.close()

	if rows.size() < 2:
		return

	# Map normalised header name -> column index.
	var columns: Dictionary = {}
	var header: PackedStringArray = rows[0]
	for i in header.size():
		var key := _normalise(header[i])
		if key != "":
			columns[key] = i

	var short_name := path.get_file()

	if columns.has("tier") and columns.has("minattack"):
		if bands_only:
			_read_tier_bands(rows, columns, short_name)
		return
	if bands_only:
		return

	# ============ ONE "Base Power" COLUMN IS ENOUGH ============
	#
	# A card carries a left number and a right number because a card has two
	# faces. Most sheets do not care: you write one number and mean both. So a
	# file with a single `Base Power` column is a unit file too, and
	# _read_units() reads that one number into both.
	#
	# This is not a convenience, it is a bug fix. The rule used to be "a unit
	# file has Unit Type AND Base Power Left", and a file that failed it fell
	# through to the bottom of this chain and was SILENTLY SKIPPED — so
	# simplifying a spreadsheet down to one power column made a whole team
	# quietly vanish from the game with nothing printed anywhere.
	if columns.has("unittype") \
			and (columns.has("basepowerleft") or columns.has("basepower")):
		_read_units(rows, columns, short_name)
	elif columns.has("maxstamina"):
		_read_goalies(rows, columns, short_name)
	elif columns.has("abilityid"):
		_read_abilities(rows, columns, short_name)
	elif columns.has("animation") and columns.has("row"):
		_read_anims(rows, columns, short_name)
	elif columns.has("key") and columns.has("value"):
		_read_tuning(rows, columns)
	elif columns.has("basicside") and columns.has("name"):
		# ============ AN EMBLEMS FILE IS NOT A TEAM ============
		#
		# "<Class> Emblems.csv" has a Unit Type column and a Name column, so
		# it walked straight into the complaint below and was announced as a
		# broken team on every single startup — twice, once per class.
		#
		# It is not broken and it is not a team: class_book.gd reads it, and
		# `Basic Side` is the column only an Emblems file has. Recognised and
		# passed over in silence, which is what a file that belongs to
		# somebody else deserves.
		pass
	elif columns.has("unittype") or columns.has("playertype"):
		# ============ AND IT SAYS SO WHEN IT CANNOT READ ONE ============
		#
		# A file that looks like a team but cannot be read is the most
		# expensive kind of mistake a CSV-driven game has: nothing crashes,
		# nothing is printed, the players are simply not there, and there is
		# nowhere to go and look. If it has a Unit Type column it was meant to
		# be a team, so it is named out loud instead of being skipped.
		push_warning("[CardDB] %s looks like a team but has no power column. Add 'Base Power'. NONE of its cards are in the game." % short_name)
		print("[CardDB] %s was SKIPPED — it has a Unit Type column but no 'Base Power' column, so none of its cards loaded." % short_name)
	# Anything else is simply not ours — silently skipped.


# --- Units ---------------------------------------------------

# =============================================================
#  TIER POWER BANDS  —  data/TierPowers.csv
#
#  A card's Tier says where it stands on the pitch; its power says how good
#  it is. Those two are supposed to agree:
#
#      Tier I    0, 1 or 2
#      Tier II   1, 2 or 3
#      Tier III  2, 3 or 4
#      Tier IV   3, 4 or 5
#
#  Nothing enforced that, so one mistyped number in a unit CSV put a
#  5-power card in Tier I and the whole match read as broken without any
#  error appearing anywhere.
#
#  Now every card is checked at load. Anything outside its band is named in
#  the startup report AND pulled back into range, so a typo costs you a line
#  in the Output panel rather than an evening.
#
#  THE BANDS ARE A SPREADSHEET. Change them in data/TierPowers.csv and the
#  game agrees with you next time you press F5. Delete the file and no
#  checking happens at all.
# =============================================================

## tier key -> {"minatk", "maxatk", "mindef", "maxdef"}
var tier_bands: Dictionary = {}


func _read_tier_bands(rows: Array, columns: Dictionary, source: String) -> void:
	for i in range(1, rows.size()):
		var row: PackedStringArray = rows[i]
		var tier_text := _cell(row, columns, "tier")
		if tier_text == "":
			continue
		tier_bands[_normalise(tier_text)] = {
			"tier": tier_text,
			"minatk": _cell_int(row, columns, "minattack"),
			"maxatk": _cell_int(row, columns, "maxattack"),
			"mindef": _cell_int(row, columns, "mindefense"),
			"maxdef": _cell_int(row, columns, "maxdefense"),
			"where": "%s row %d" % [source, i + 1],
		}


## Pull one card into its tier's band, and say so if it had to.
## Returns true if the card was changed.
func _apply_tier_band(card: PlayerData, source: String) -> bool:
	var key := _normalise(card.get_tier_clean())
	if not tier_bands.has(key):
		return false

	var band: Dictionary = tier_bands[key]
	var low_atk := int(band["minatk"])
	var high_atk := int(band["maxatk"])
	var low_def := int(band["mindef"])
	var high_def := int(band["maxdef"])

	var was_atk := card.base_power_left
	var was_def := card.base_power_right
	var fixed := false

	if was_atk < low_atk or was_atk > high_atk:
		card.base_power_left = clampi(was_atk, low_atk, high_atk)
		problems.append("%s: '%s' is Tier %s with %d attack, but Tier %s is %d to %d. Using %d — fix the Base Power Left column."
			% [source, card.player_name, card.get_tier_clean(), was_atk,
				band["tier"], low_atk, high_atk, card.base_power_left])
		fixed = true

	if was_def < low_def or was_def > high_def:
		card.base_power_right = clampi(was_def, low_def, high_def)
		problems.append("%s: '%s' is Tier %s with %d defence, but Tier %s is %d to %d. Using %d — fix the Base Power Right column."
			% [source, card.player_name, card.get_tier_clean(), was_def,
				band["tier"], low_def, high_def, card.base_power_right])
		fixed = true

	return fixed


## What a tier is allowed to be, as words. Used by the hover panel.
func tier_band_text(tier_key: String) -> String:
	var key := _normalise(tier_key)
	if not tier_bands.has(key):
		return ""
	var band: Dictionary = tier_bands[key]
	return "Tier %s is %d to %d" % [band["tier"], int(band["minatk"]), int(band["maxatk"])]


func _read_units(rows: Array, columns: Dictionary, source: String) -> void:
	for i in range(1, rows.size()):
		var row: PackedStringArray = rows[i]
		var name_text := _cell(row, columns, "name")
		if name_text == "":
			continue

		var card := PlayerData.new()
		card.unit_type = _cell(row, columns, "unittype")
		card.player_name = name_text
		card.attack_text = _cell(row, columns, "attack")
		card.defend_text = _cell(row, columns, "defend")

		# ============ A STAR HAS ONE ABILITY, NOT TWO ============
		#
		# data/Star Players.csv writes `Front Side` where a unit file writes
		# `Attack` and `Defend`, and that is the design rather than an
		# accident: a Star has ONE ability and an Ultimate; a normal unit has
		# two abilities and no Ultimate. So Front Side fills both faces.
		#
		# It is read as a FALLBACK and not as a replacement, so a sheet that
		# writes Attack and Defend keeps working exactly as it did, and a
		# sheet that writes all three is not quietly overwritten by the
		# shorter column.
		var front := _cell(row, columns, "frontside")
		if front != "":
			if card.attack_text == "":
				card.attack_text = front
			if card.defend_text == "":
				card.defend_text = front

		card.ultimate_text = _cell(row, columns, "ultimateside")
		card.emblem_name = _cell(row, columns, "emblem")
		card.star_set = _cell(row, columns, "set")
		card.element = _cell(row, columns, "element")
		# A single `Base Power` column stands for both faces. A sheet that
		# writes both is still read as both, so nothing that already worked
		# changes — see the note at the top of _read_one().
		var one_power := _cell(row, columns, "basepower")
		if one_power.strip_edges() != "" and not columns.has("basepowerleft"):
			card.base_power_left = int(one_power)
			card.base_power_right = int(one_power)
		else:
			card.base_power_left = _cell_int(row, columns, "basepowerleft")
			card.base_power_right = _cell_int(row, columns, "basepowerright")
		card.tier = _cell(row, columns, "tier")
		card.stufe = _cell(row, columns, "stufe")
		card.tool = _cell(row, columns, "tool")
		card.card_number = _cell_int(row, columns, "cardnumber")
		card.card_date = _cell_int(row, columns, "carddate")
		card.card_set = _cell(row, columns, "setname")
		card.created_by = _cell(row, columns, "createdby")

		var type_text := _cell(row, columns, "playertype")
		card.player_type = type_text if type_text != "" else "Normal"

		# Optional ability hooks — blank means "no ability", which is fine.
		card.attack_ability_id = _cell(row, columns, "attackability")
		card.defend_ability_id = _cell(row, columns, "defendability")

		# Optional "Stamina" column, used ONLY in Adventure mode. Blank means
		# "work it out from my power", which is what you want for almost every
		# card — see AdventureRun.stamina_for().
		card.adventure_stamina = _cell_int(row, columns, "stamina")

		# Optional "Level" column. It decides who a FRIENDLY puts you up
		# against and nothing else — see team_level.gd. Blank (0) means
		# "work it out from my tier and power", so the column is entirely
		# optional. Note this is NOT the "Stufe" column, which is card text.
		card.level = _cell_int(row, columns, "level")

		var art_name := _cell(row, columns, "artwork")
		if art_name != "":
			card.artwork = _find_texture(art_name, PLAYER_ART_DIRS)
			if card.artwork == null:
				problems.append("%s: artwork '%s' not found for %s" % [source, art_name, name_text])

		# THE OTHER FACE. Missing is not a problem worth reporting: a Star
		# with one drawing works, it simply does not change when it turns
		# over — and every Star is in that state until the art is made.
		var ult_art := _cell(row, columns, "ultimateartwork")
		if ult_art != "":
			card.ultimate_artwork = _find_texture(ult_art, PLAYER_ART_DIRS)

		if card.is_star():
			var formation_name := _cell(row, columns, "formation")
			if formation_name == "":
				formation_name = card.unit_type.to_lower().replace(" ", "_") + "_formation.tscn"
			var formation_path := FORMATION_DIR + formation_name
			if ResourceLoader.exists(formation_path):
				card.formation_scene = load(formation_path)

		if card.get_tier_index() < 0:
			problems.append("%s: '%s' has tier '%s' — expected I, II, III or IV"
				% [source, name_text, card.tier])

		_apply_tier_band(card, source)
		players.append(card)


# --- Goalies -------------------------------------------------

func _read_goalies(rows: Array, columns: Dictionary, source: String) -> void:
	for i in range(1, rows.size()):
		var row: PackedStringArray = rows[i]
		var name_text := _cell(row, columns, "name")
		if name_text == "":
			continue

		var keeper := GoalieData.new()
		keeper.team = _cell(row, columns, "team")
		keeper.goalie_name = name_text
		keeper.max_stamina = _cell_int(row, columns, "maxstamina")
		# "Passive / Ability" normalises to "passiveability".
		keeper.ability_text = _first_cell(row, columns, ["passiveability", "abilitytext", "ability"])
		keeper.ability_id = _cell(row, columns, "abilityid")

		if keeper.max_stamina <= 0:
			problems.append("%s: goalie '%s' has Max Stamina %d — using 25"
				% [source, name_text, keeper.max_stamina])
			keeper.max_stamina = 25

		var art_name := _cell(row, columns, "artwork")
		if art_name != "":
			keeper.artwork = _find_texture(art_name, GOALIE_ART_DIRS)

		var front_name := _first_cell(row, columns, ["shootoutartwork", "frontartwork"])
		if front_name != "":
			keeper.shootout_artwork = _find_texture(front_name, GOALIE_ART_DIRS)

		goalie_data.append(keeper)


# --- Abilities -----------------------------------------------

func _read_abilities(rows: Array, columns: Dictionary, source: String) -> void:
	for i in range(1, rows.size()):
		var row: PackedStringArray = rows[i]
		var id_text := _cell(row, columns, "abilityid")
		if id_text == "":
			continue

		var ability := AbilityData.new()
		ability.id = id_text
		ability.display_name = _cell(row, columns, "name")
		ability.trigger = _normalise(_cell(row, columns, "trigger"))
		ability.target = _cell(row, columns, "target").strip_edges().to_lower()
		# ROUND Z: `add_counter:burn` - the word, then what it is about.
		var effect_text := _cell(row, columns, "effect").strip_edges()
		ability.effect = _normalise(effect_text.split(":")[0])
		if effect_text.contains(":"):
			ability.effect_arg = effect_text.split(":", true, 1)[1].strip_edges().to_lower()
		# ROUND Z: the Cost column - `ore:3`.
		var cost_text := _cell(row, columns, "cost").strip_edges().to_lower()
		if cost_text != "":
			var cost_bits := cost_text.split(":")
			ability.cost_kind = _normalise(String(cost_bits[0]))
			ability.cost_amount = maxi(1, int(String(cost_bits[1]))) if cost_bits.size() > 1 and String(cost_bits[1]).is_valid_int() else 1
		ability.value = _cell_int(row, columns, "value")
		ability.scope = _normalise(_cell(row, columns, "scope"))
		ability.notes = _cell(row, columns, "notes")
		# MAX: "5" = five a match, "1/cycle" = once a cycle, "1/game" = once a
		# match. Round Y added the per-cycle form for "(once per cycle)".
		var max_text := _cell(row, columns, "max").strip_edges().to_lower()
		if max_text.contains("/"):
			var max_bits := max_text.split("/")
			ability.max_uses = maxi(0, int(String(max_bits[0]))) if String(max_bits[0]).is_valid_int() else 0
			var per := String(max_bits[1]).strip_edges()
			ability.max_per = "cycle" if per.begins_with("cycle") else ("round" if per.begins_with("round") else "match")
			# `2/cycle/side`: the whole side shares the count (round Z).
			ability.max_shared = max_text.ends_with("/side")
		else:
			ability.max_uses = maxi(0, int(max_text)) if max_text.is_valid_int() else 0
		ability.condition = _cell(row, columns, "if")
		# ROUND AA: the Ask column - `yes` asks the player first.
		ability.ask = _cell(row, columns, "ask").strip_edges().to_lower() in ["yes", "true", "1", "ask"]

		var complaint := ability.validate()
		if complaint != "":
			problems.append("%s: ability '%s' — %s" % [source, id_text, complaint])
			continue

		abilities[id_text.to_lower()] = ability


# --- Animations ----------------------------------------------

func _read_anims(rows: Array, columns: Dictionary, source: String) -> void:
	for i in range(1, rows.size()):
		var row: PackedStringArray = rows[i]
		var anim_name := _cell(row, columns, "animation")
		if anim_name == "":
			continue

		var spec := AnimSpec.new()
		spec.name = anim_name.strip_edges().to_lower()
		spec.unit_type = _cell(row, columns, "unittype")
		spec.sheet_columns = _cell_int_or(row, columns, "sheetcolumns", AnimSpec.DEFAULT_COLUMNS)
		spec.sheet_rows = _cell_int_or(row, columns, "sheetrows", AnimSpec.DEFAULT_ROWS)
		spec.row = _cell_int(row, columns, "row")
		spec.first_frame = _cell_int(row, columns, "firstframe")
		spec.frames = _cell_int_or(row, columns, "frames", 1)
		spec.fps = _cell_float_or(row, columns, "fps", 10.0)
		spec.loop = _cell_bool(row, columns, "loop")
		spec.notes = _cell(row, columns, "notes")

		var complaint := spec.validate()
		if complaint != "":
			problems.append("%s: animation '%s' — %s" % [source, anim_name, complaint])
			continue

		anims[_anim_key(spec.name, spec.unit_type)] = spec


static func _anim_key(anim_name: String, unit_type: String) -> String:
	return "%s|%s" % [anim_name.strip_edges().to_lower(), _normalise(unit_type)]


## Look up an animation: a class-specific row wins, otherwise the generic one.
## Returns null if neither exists — callers fall back to a still frame.
func get_anim(anim_name: String, unit_type: String = "") -> AnimSpec:
	var specific: Variant = anims.get(_anim_key(anim_name, unit_type))
	if specific != null:
		return specific
	return anims.get(_anim_key(anim_name, ""))


# --- Tuning --------------------------------------------------

func _read_tuning(rows: Array, columns: Dictionary) -> void:
	for i in range(1, rows.size()):
		var row: PackedStringArray = rows[i]
		var key := _normalise(_cell(row, columns, "key"))
		if key == "":
			continue
		tuning[key] = _cell(row, columns, "value")


# =============================================================
#  QUERIES
# =============================================================

func get_ability(id_text: String) -> AbilityData:
	if id_text.strip_edges() == "":
		return null
	return abilities.get(id_text.strip_edges().to_lower())


func roster_for_class(unit_type: String) -> Array[PlayerData]:
	var out: Array[PlayerData] = []
	var wanted := unit_type.strip_edges().to_lower()
	for card in players:
		if card.is_star():
			continue
		if card.unit_type.strip_edges().to_lower() == wanted:
			out.append(card)
	return out


func stars_for_class(unit_type: String) -> Array[PlayerData]:
	var out: Array[PlayerData] = []
	var wanted := unit_type.strip_edges().to_lower()
	for card in players:
		if card.is_star() and card.unit_type.strip_edges().to_lower() == wanted:
			out.append(card)
	return out


## ============ WHICH TIER DOES THIS CLASS'S STARS HOLD? ============
##
## A class's Star Players hold ONE tier between them — Lorelei's three are
## Tier IV, Brandteufel's are Tier III. That tier is locked in the team
## builder and the Stars rotate through it at HOLD UP.
##
## It used to be read as "whatever tier the FIRST Star row happens to be",
## which is fine until a class has Stars in two tiers. Then the star tier
## was decided by row order, HOLD UP offered every Star regardless of tier,
## and picking one dropped it into the slot the old Star was standing in —
## a Tier IV Star in the Tier I position, with the bookkeeping quietly
## following along.
##
## Now it is the tier that holds the MOST of the class's Stars, and any
## Star outside it is named in the startup report instead of being fielded.
func star_tier_for_class(unit_type: String) -> String:
	var counts: Dictionary = {}
	for card in stars_for_class(unit_type):
		var tier := card.get_tier_clean()
		if tier != "":
			counts[tier] = int(counts.get(tier, 0)) + 1

	var best := ""
	var best_count := 0
	# PlayerData.TIER_ORDER, so a tie is broken by the lower tier every time
	# rather than by whichever key the dictionary hands back first.
	for tier in PlayerData.TIER_ORDER:
		var n := int(counts.get(tier, 0))
		if n > best_count:
			best_count = n
			best = tier
	return best


## The class's Stars as a LADDER: one on each rung of their tier, weakest
## first. Any Star in the wrong tier, or sharing a rung with another Star,
## is left out — content_report names it so you can fix the CSV.
func star_ladder_for_class(unit_type: String) -> Array[PlayerData]:
	var tier := star_tier_for_class(unit_type)
	if tier == "":
		return [] as Array[PlayerData]

	# vary = false: your Stars must be the same three every time you pick
	# this class, unlike an enemy squad which is drawn fresh each match.
	var made := TierLadder.build(stars_for_class(unit_type), tier, self, false)
	var out: Array[PlayerData] = []
	out.assign(made["cards"])
	return out


## class name -> Array[PlayerData] of that class's Star Players.
func stars_by_class() -> Dictionary:
	var grouped: Dictionary = {}
	for card in players:
		if not card.is_star():
			continue
		var key := card.unit_type.strip_edges()
		if key == "":
			continue
		if not grouped.has(key):
			grouped[key] = [] as Array[PlayerData]
		(grouped[key] as Array[PlayerData]).append(card)
	return grouped


func goalie_for_team(team: String) -> GoalieData:
	var wanted := team.strip_edges().to_lower()
	for keeper in goalie_data:
		if keeper.team.strip_edges().to_lower() == wanted:
			return keeper
	return null


# --- Tuning accessors ----------------------------------------
# Every one falls back to the value passed in, so a missing or misspelled
# row in Tuning.csv degrades to the built-in default instead of crashing.

func tune_float(key: String, fallback: float) -> float:
	var name_key := _normalise(key)
	var raw := String(tuning.get(name_key, ""))
	var value := float(raw) if raw.is_valid_float() else fallback
	return value + float(bonuses.get(name_key, 0.0))


func tune_int(key: String, fallback: int) -> int:
	var name_key := _normalise(key)
	var raw := String(tuning.get(name_key, ""))
	var value := int(raw) if raw.is_valid_int() else fallback
	return value + int(bonuses.get(name_key, 0))


## Read every  tune_<something>  counter out of the save and stack them on
## top of Tuning.csv. Call this once before a match, after the save is loaded.
##
## Names line up because both sides are stripped down to letters and digits:
## the counter `tune_press_speed` becomes `tunepressspeed`, drop the leading
## `tune` and you have `pressspeed`, which is exactly what `press_speed`
## normalises to.
func apply_bonuses_from(state: GameState) -> void:
	bonuses.clear()
	if state == null:
		return

	for key in state.counters.keys():
		var name_key := String(key)
		if not name_key.begins_with("tune") or name_key.length() <= 4:
			continue
		var target := name_key.substr(4)
		bonuses[target] = float(state.counters[key])

	if not bonuses.is_empty():
		print("[tuning] %d value(s) raised by talents: %s" % [bonuses.size(), bonuses])


## A text value, e.g. a path to a PNG. Blank rows fall back like the rest.
func tune_text(key: String, fallback: String = "") -> String:
	var raw := String(tuning.get(_normalise(key), "")).strip_edges()
	return raw if raw != "" else fallback


func tune_bool(key: String, fallback: bool) -> bool:
	var raw := String(tuning.get(_normalise(key), "")).strip_edges().to_lower()
	if raw in ["true", "yes", "1", "on"]:
		return true
	if raw in ["false", "no", "0", "off"]:
		return false
	return fallback


# =============================================================
#  HELPERS
# =============================================================

## "Base Power Left" / "base_power_left" / "BASEPOWERLEFT" all match.
static func _normalise(text: String) -> String:
	var out := ""
	for c in text.strip_edges().to_lower():
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			out += c
	return out


func _cell(row: PackedStringArray, columns: Dictionary, key: String) -> String:
	if not columns.has(key):
		return ""
	var index: int = columns[key]
	if index >= row.size():
		return ""
	return row[index].strip_edges()


func _first_cell(row: PackedStringArray, columns: Dictionary, keys: Array) -> String:
	for key in keys:
		var value := _cell(row, columns, String(key))
		if value != "":
			return value
	return ""


func _cell_int(row: PackedStringArray, columns: Dictionary, key: String) -> int:
	var raw := _cell(row, columns, key)
	return int(raw) if raw.is_valid_int() else 0


func _cell_int_or(row: PackedStringArray, columns: Dictionary, key: String, fallback: int) -> int:
	var raw := _cell(row, columns, key)
	return int(raw) if raw.is_valid_int() else fallback


func _cell_float_or(row: PackedStringArray, columns: Dictionary, key: String, fallback: float) -> float:
	var raw := _cell(row, columns, key)
	return float(raw) if raw.is_valid_float() else fallback


func _cell_bool(row: PackedStringArray, columns: Dictionary, key: String) -> bool:
	return _cell(row, columns, key).strip_edges().to_lower() in ["true", "yes", "1", "on", "loop"]


func _find_texture(file_name: String, dirs: Array[String]) -> Texture2D:
	for folder in dirs:
		var path: String = folder + file_name
		if ResourceLoader.exists(path):
			return load(path) as Texture2D
	return null


func _report() -> void:
	print("[CardDB] %d cards, %d goalies, %d abilities, %d animations, %d tuning values."
		% [players.size(), goalie_data.size(), abilities.size(), anims.size(), tuning.size()])
	if problems.is_empty():
		return
	print("[CardDB] %d thing(s) need attention in your CSVs:" % problems.size())
	for line in problems:
		print("         - ", line)


# =============================================================
#  CSV PARSER
#  Handles quoted fields and doubled quotes, which matters because your
#  ability text contains commas.
# =============================================================

static func parse_csv(content: String) -> Array:
	var rows: Array = []
	var current_row := PackedStringArray()
	var field := ""
	var in_quotes := false
	var i := 0

	while i < content.length():
		var c := content[i]
		if in_quotes:
			if c == '"':
				if i + 1 < content.length() and content[i + 1] == '"':
					field += '"'
					i += 1
				else:
					in_quotes = false
			else:
				field += c
		else:
			if c == '"':
				in_quotes = true
			elif c == ",":
				current_row.append(field)
				field = ""
			elif c == "\r":
				pass
			elif c == "\n":
				current_row.append(field)
				field = ""
				rows.append(current_row)
				current_row = PackedStringArray()
			else:
				field += c
		i += 1

	if not field.is_empty() or not current_row.is_empty():
		current_row.append(field)
		rows.append(current_row)

	return rows
