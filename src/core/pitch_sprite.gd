class_name PitchSprite
extends RefCounted

# =============================================================
#  THE ISOMETRIC PLAYERS ON THE PITCH  (round AN)
#
#  Anthony: the players on the tilted pitch are drawn in the isometric view,
#  in 8 directions, with their own run, kick, idle, tackle, fall and cheer.
#
#  These sheets are for the PITCH only. Cards, duels, portraits and the story
#  still use the old 12 x 39 sheet in the card's Artwork column, so nothing
#  else changes.
#
#  TWO FILES
#
#    data/PitchSprites.csv   who wears which pitch sheet.
#        Wears        the file name of the card's own sheet
#                     (class_Normal_female_blonde.png) OR a class name
#                     (Normal). The file name is tried first, then the class.
#        Pitch Sheet  a sheet in assets/players/pitch/ (built by
#                     tools/make_pitch_sheet.py). Several separated by | =
#                     one picked per player, the same one every match.
#    data/PitchAnims.csv     where each animation is on a pitch sheet.
#        Animation    idle, run, kick, tackle, fall, cheer
#        First Row    its first row. The 8 directions follow, one row each,
#                     in this order: east, south-east, south, south-west,
#                     west, north-west, north, north-east.
#        Frames, FPS, Loop
#        Stand-in     (optional) what to play instead while a sheet has no
#                     rows for this animation yet, e.g. drink -> cheer.
#
#  A card with no row in PitchSprites.csv plays on the old sheet, as before.
#
#  Tuning.csv: pitch_sheet_cell (the square frame size), pitch_sprite_scale,
#  pitch_sprite_lift (moves the picture up so the feet sit on the spot),
#  pitch_ground_squash (how flat the ground looks on screen; it turns a
#  screen direction back into a ground direction before picking one of 8).
# =============================================================

const SPRITES_PATH := "res://data/PitchSprites.csv"
const ANIMS_PATH := "res://data/PitchAnims.csv"
const SHEET_DIR := "res://assets/players/pitch/"
## Drawn players (18 Oct 2026): per-sheet frame size, lift, size and smooth
## scaling. A sheet with no row here is a pixel sheet and uses Tuning.csv.
const SHEETS_PATH := "res://data/PitchSheets.csv"

## The order of the 8 direction rows under each animation's First Row.
const DIRECTIONS: Array[String] = ["east", "south-east", "south", "south-west",
	"west", "north-west", "north", "north-east"]

## Set on a card by MatchCoach.change_class: his own name row stops counting.
const CHANGED_CLASS := "changed_class"

static var _wears: Dictionary = {}
static var _anims: Dictionary = {}
static var _sheets: Array[Dictionary] = []
static var _loaded := false


static func reload() -> void:
	_loaded = false
	_load()


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_wears = {}
	_anims = {}
	_sheets = []
	for row in MenuSupport.read_csv(SHEETS_PATH):
		var pattern := MenuSupport.field(row, "Sheet").strip_edges().to_lower()
		if pattern == "":
			continue
		_sheets.append({
			"pattern": pattern,
			"cell": MenuSupport.field_float(row, "Cell", 0.0),
			"lift": MenuSupport.field_float(row, "Lift", -1.0),
			"size": MenuSupport.field_float(row, "Size", 1.0),
			"smooth": MenuSupport.field(row, "Smooth", "false").strip_edges().to_lower() == "true",
		})
	for row in MenuSupport.read_csv(SPRITES_PATH):
		var who := MenuSupport.field(row, "Wears").strip_edges()
		var sheets := MenuSupport.field(row, "Pitch Sheet").strip_edges()
		if who != "" and sheets != "":
			_wears[who.to_lower()] = sheets
	for row in MenuSupport.read_csv(ANIMS_PATH):
		var anim_name := MenuSupport.field(row, "Animation").strip_edges().to_lower()
		if anim_name == "":
			continue
		_anims[anim_name] = {
			"row": MenuSupport.field_int(row, "First Row", 0),
			"frames": maxi(1, MenuSupport.field_int(row, "Frames", 1)),
			"fps": maxf(0.1, MenuSupport.field_float(row, "FPS", 10.0)),
			"loop": MenuSupport.field(row, "Loop", "true").strip_edges().to_lower() == "true",
			"stand_in": MenuSupport.field(row, "Stand-in").strip_edges().to_lower(),
		}


## The pitch sheet this card plays in, or null for the old sheet.
## `pick` chooses between several looks; pass something fixed per player.
static func sheet_for(card: PlayerData, pick: int = 0) -> Texture2D:
	_load()
	if card == null:
		return null
	# His own name first (24 Oct 2026, the tutorial Koch): a row for one
	# player wins over the picture he shares with everyone else. Once a
	# match changes his class (MatchTalk class:, Koch turning into a
	# Bergmännlein) he wears his new class's row instead, on the pitch and
	# on his card (Anthony, 24 Oct).
	var keys: Array[String] = []
	if not card.has_meta(CHANGED_CLASS):
		keys.append(card.player_name.to_lower())
	var own := card.active_artwork()
	if own != null and own.resource_path != "":
		keys.append(own.resource_path.get_file().to_lower())
	keys.append(card.unit_type.to_lower())
	for key in keys:
		if not _wears.has(key):
			continue
		# Only the looks whose sheet actually exists, so a look that has not
		# been drawn yet is skipped rather than sending the player back to
		# the old sheet.
		var paths: Array[String] = []
		for look in String(_wears[key]).split("|", false):
			var file_name := String(look).strip_edges()
			var path := file_name if file_name.begins_with("res://") else SHEET_DIR + file_name
			if file_name != "" and ResourceLoader.exists(path):
				paths.append(path)
		if paths.is_empty():
			continue
		return load(paths[absi(pick) % paths.size()]) as Texture2D
	return null


## How a pitch sheet is cut and drawn: {cell, lift, size, smooth}.
## cell = frame size in the sheet, lift = its pixels the figure is lifted,
## size = extra scale next to a pixel player, smooth = drawn art (no hard
## pixels). From data/PitchSheets.csv, else Tuning.csv like a pixel sheet.
static func look_of(sheet: Texture2D) -> Dictionary:
	_load()
	var db := CardDatabase.get_db()
	var out := {
		"cell": maxf(1.0, db.tune_float("pitch_sheet_cell", 72.0)) if db != null else 72.0,
		"lift": db.tune_float("pitch_sprite_lift", 0.0) if db != null else 0.0,
		"size": 1.0,
		"smooth": false,
	}
	if sheet == null:
		return out
	var file_name := sheet.resource_path.get_file().to_lower()
	for row in _sheets:
		if file_name.match(String(row["pattern"])) or file_name.get_basename().match(String(row["pattern"])):
			if float(row["cell"]) > 0.0:
				out["cell"] = float(row["cell"])
			if float(row["lift"]) >= 0.0:
				out["lift"] = float(row["lift"])
			out["size"] = maxf(0.05, float(row["size"]))
			out["smooth"] = bool(row["smooth"])
			break
	return out


## True for a drawn (not pixel) sheet: scale it smoothly.
static func is_smooth(sheet: Texture2D) -> bool:
	return sheet != null and bool(look_of(sheet)["smooth"])


## {row, frames, fps, loop} for an animation, or {} if PitchAnims.csv has none.
static func anim(anim_name: String) -> Dictionary:
	_load()
	return _anims.get(anim_name.to_lower(), {})


static func has_anim(anim_name: String) -> bool:
	return not anim(anim_name).is_empty()


## Which of the 8 directions a SCREEN direction is (y down), 0 = east.
## `squash` undoes the flattened ground first, so a run straight up the
## tilted pitch reads as north-east and not as east.
static func direction_of(screen: Vector2, squash: float = 1.0) -> int:
	if screen.length_squared() < 0.0001:
		return -1
	var ground := Vector2(screen.x, screen.y * maxf(0.1, squash))
	var step := int(roundf(ground.angle() / (PI / 4.0)))
	return posmod(step, 8)


# =============================================================
#  THE SAME FIGURE IN THE WINDOWS  (round AN)
#
#  Anthony: when a player shoots or kicks, the window must show the sprite
#  that player has on the pitch. The duel, the shootout and every caption
#  window (fouls, free kicks, goals, the ball going out) ask here first, and
#  only use the card's old sheet when the card has no pitch sheet.
#
#  Those windows name their animations the old way; this is what each one
#  becomes on a pitch sheet. Anything not listed plays idle.
# =============================================================

const WINDOW_ANIMS := {
	"kick": "kick", "kick_back": "kick", "ability": "kick", "shot": "kick",
	"win": "cheer", "celebrate": "cheer", "cheer": "cheer",
	"lose": "fall", "death": "fall", "fall": "fall",
	"run": "run", "idle": "idle", "tackle": "tackle",
}


## The pitch sheet for `card`, or null. The same look the card wears on the
## pitch (PlayerUnit picks it by the same name).
static func window_sheet(card: PlayerData) -> Texture2D:
	if card == null:
		return null
	return sheet_for(card, hash(card.player_name))


## The duel sheets (tools/make_drawn_duel_sheet.py): one per pitch sheet,
## same file name, in Tuning.csv duel_sheets, frames duel_cell big, all
## facing right. Which row each move is on and how many frames it has;
## the speed and looping come from PitchAnims.csv, as on the pitch.
const DUEL_ROWS := {"idle": [0, 4], "run": [1, 8], "kick": [2, 9], "cheer": [3, 9], "fall": [4, 7]}


## {sheet, spec} for `anim_name` from the duel sheet of `pitch`, or {}. The duel
## window and the shot window (24 Oct: "the player kicking the ball at the
## goalie is blurry") both draw these.
static func duel_spec(pitch: Texture2D, anim_name: String, db: CardDatabase) -> Dictionary:
	if pitch == null or db == null:
		return {}
	var folder := db.tune_text("duel_sheets", "res://assets/players/duel/").strip_edges()
	if folder == "":
		return {}
	var path := folder.path_join(pitch.resource_path.get_file())
	if not ResourceLoader.exists(path):
		return {}
	var sheet := load(path) as Texture2D
	var cell := db.tune_text("duel_cell", "400,540").split(",")
	if sheet == null or cell.size() != 2:
		return {}
	var wanted := String(WINDOW_ANIMS.get(anim_name.to_lower(), "idle"))
	if not DUEL_ROWS.has(wanted):
		wanted = "idle"
	var row: Array = DUEL_ROWS[wanted]
	var timing := anim(wanted)
	var spec := AnimSpec.new()
	spec.name = wanted
	spec.sheet_columns = maxi(1, int(sheet.get_width() / float(cell[0])))
	spec.sheet_rows = maxi(1, int(sheet.get_height() / float(cell[1])))
	spec.row = int(row[0])
	spec.first_frame = 0
	spec.frames = int(row[1])
	spec.fps = float(timing.get("fps", 10.0))
	spec.loop = bool(timing.get("loop", wanted != "kick" and wanted != "fall"))
	return {"sheet": sheet, "spec": spec}


## An AnimSpec that plays `anim_name` from a pitch sheet, facing `direction`
## (an index into DIRECTIONS: 0 east, 1 south-east, 2 south ... 7 north-east).
static func window_spec(sheet: Texture2D, anim_name: String, direction: int = 1) -> AnimSpec:
	if sheet == null:
		return null
	var wanted := String(WINDOW_ANIMS.get(anim_name.to_lower(), "idle"))
	var row := anim(wanted)
	if row.is_empty():
		row = anim("idle")
		if row.is_empty():
			return null
	var cell := float(look_of(sheet)["cell"])
	var spec := AnimSpec.new()
	spec.name = wanted
	spec.sheet_columns = maxi(1, int(sheet.get_width() / cell))
	spec.sheet_rows = maxi(1, int(sheet.get_height() / cell))
	spec.row = int(row["row"]) + posmod(direction, 8)
	spec.first_frame = 0
	spec.frames = int(row["frames"])
	spec.fps = float(row["fps"])
	spec.loop = bool(row["loop"])
	return spec
