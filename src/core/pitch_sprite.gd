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

## The order of the 8 direction rows under each animation's First Row.
const DIRECTIONS: Array[String] = ["east", "south-east", "south", "south-west",
	"west", "north-west", "north", "north-east"]

static var _wears: Dictionary = {}
static var _anims: Dictionary = {}
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
		}


## The pitch sheet this card plays in, or null for the old sheet.
## `pick` chooses between several looks; pass something fixed per player.
static func sheet_for(card: PlayerData, pick: int = 0) -> Texture2D:
	_load()
	if card == null:
		return null
	var keys: Array[String] = []
	var own := card.active_artwork()
	if own != null and own.resource_path != "":
		keys.append(own.resource_path.get_file().to_lower())
	keys.append(card.player_name.to_lower())
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
