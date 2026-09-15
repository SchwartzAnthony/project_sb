class_name GameSettings
extends RefCounted

# =============================================================
#  SETTINGS — the screen, the sound, the colours and the controller
#
#  ============ WHERE THEY LIVE ============
#
#  user://settings.json, beside your save and your teams. NOT in the project
#  folder — nothing here ever writes to res://. Delete that one file and
#  everything goes back to how it shipped.
#
#  ============ WHAT IS IN IT ============
#
#      screen_mode      "windowed", "fullscreen" or "borderless"
#      resolution       "1920x1080". Ignored in fullscreen
#      vsync            true / false
#      max_fps          0 means uncapped
#      volume_master    0.0 to 1.0. Same for music, sfx and voice
#      palette          "default", "deuteranopia", "protanopia",
#                       "tritanopia" or "high_contrast"
#      text_scale       1.0 is normal. 1.25 for bigger writing everywhere
#      pad_enabled      whether a controller is listened to at all
#      pad_deadzone     0.0 to 0.9. How far a stick must move to count
#      pad_vibration    true / false
#      keys             what the player has rebound. See game_keys.gd
#
#  A missing value is the default, so a settings file written by an older
#  build still loads and simply picks up whatever is new.
#
#  ============ HOW IT REACHES THE GAME ============
#
#  GameSettings.apply(tree) does the work: it sets the window, the audio
#  buses, the palette in MenuSupport, and the controller deadzones. Every
#  menu screen calls MenuEscape.install(self), and THAT calls this once per
#  run — so a screen never has to remember to apply the settings and a new
#  screen you add gets them for free.
# =============================================================

const SAVE_PATH := "user://settings.json"
const APPLIED_KEY := "cw_settings_applied"

const SCREEN_MODES: Array[String] = ["windowed", "fullscreen", "borderless"]
const RESOLUTIONS: Array[String] = [
	"1280x720", "1600x900", "1920x1080", "2560x1440", "3840x2160",
]
const PALETTES: Array[String] = [
	"default", "deuteranopia", "protanopia", "tritanopia", "high_contrast",
]
const BUSES: Array[String] = ["Master", "Music", "SFX", "Voice"]


static func defaults() -> Dictionary:
	return {
		"screen_mode": "windowed",
		"resolution": "1920x1080",
		"vsync": true,
		"max_fps": 0,
		"volume_master": 0.9,
		"volume_music": 0.7,
		"volume_sfx": 0.9,
		"volume_voice": 0.9,
		"palette": "default",
		"text_scale": 1.0,
		"pad_enabled": true,
		"pad_deadzone": 0.2,
		"pad_vibration": true,
		"keys": {},
	}


# =============================================================
#  READING AND WRITING
# =============================================================

static func load_all() -> Dictionary:
	var settings := defaults()
	if not FileAccess.file_exists(SAVE_PATH):
		return settings
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return settings
	var raw := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		push_warning("[settings] %s is not readable — using the defaults." % SAVE_PATH)
		return settings
	# Merge rather than replace, so a value the file has never heard of takes
	# its default instead of coming back as null.
	for key in (parsed as Dictionary).keys():
		settings[key] = (parsed as Dictionary)[key]
	return settings


static func save_all(settings: Dictionary) -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("[settings] Could not write %s — your settings will not be kept." % SAVE_PATH)
		return
	file.store_string(JSON.stringify(settings, "\t"))
	file.close()


## Change one value and put it into effect straight away.
static func put(tree: SceneTree, key: String, value: Variant) -> Dictionary:
	var settings := load_all()
	settings[key] = value
	save_all(settings)
	apply(tree, true)
	return settings


# =============================================================
#  PUTTING THEM INTO EFFECT
# =============================================================

## Called once per run by MenuEscape.install(), and again by the settings
## screen every time you change something.
static func apply(tree: SceneTree, force: bool = false) -> void:
	if tree != null and tree.has_meta(APPLIED_KEY) and not force:
		return
	if tree != null:
		tree.set_meta(APPLIED_KEY, true)

	var settings := load_all()
	_apply_screen(settings)
	_apply_sound(settings)
	_apply_palette(String(settings.get("palette", "default")))
	_apply_pad(settings)


static func _apply_screen(settings: Dictionary) -> void:
	match String(settings.get("screen_mode", "windowed")):
		"fullscreen":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
		"borderless":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
			DisplayServer.window_set_size(DisplayServer.screen_get_size())
			DisplayServer.window_set_position(Vector2i.ZERO)
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			var box := size_from_text(String(settings.get("resolution", "1920x1080")))
			if box.x > 0 and box.y > 0:
				DisplayServer.window_set_size(box)

	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if bool(settings.get("vsync", true))
		else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(settings.get("max_fps", 0))


static func _apply_sound(settings: Dictionary) -> void:
	_set_bus("Master", float(settings.get("volume_master", 0.9)))
	_set_bus("Music", float(settings.get("volume_music", 0.7)))
	_set_bus("SFX", float(settings.get("volume_sfx", 0.9)))
	_set_bus("Voice", float(settings.get("volume_voice", 0.9)))


## A slider from 0 to 1 is not decibels. This is the conversion, and it also
## MUTES rather than turning a bus down to a whisper at zero.
static func _set_bus(bus_name: String, level: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		# A project without a Music or Voice bus is fine; the row is skipped
		# and the Master bus still works.
		return
	var quiet := level <= 0.001
	AudioServer.set_bus_mute(index, quiet)
	if not quiet:
		AudioServer.set_bus_volume_db(index, linear_to_db(clampf(level, 0.0, 1.0)))


static func _apply_pad(settings: Dictionary) -> void:
	var dead := clampf(float(settings.get("pad_deadzone", 0.2)), 0.0, 0.9)
	for action in InputMap.get_actions():
		InputMap.action_set_deadzone(action, dead)


# =============================================================
#  THE COLOUR TAB
#
#  Every screen in the game reads its colours from MenuSupport, so swapping
#  the palette there changes ALL of them at once — no screen knows a palette
#  exists. The tier colours matter most: the default Tier II green and Tier
#  III amber are the classic pair that red-green colour blindness merges.
# =============================================================

static func _apply_palette(name_text: String) -> void:
	# Start from the shipped palette every time, so switching back and forth
	# does not leave a stale colour behind.
	MenuSupport.COLOUR_BACKGROUND = Color(0.09, 0.10, 0.13)
	MenuSupport.COLOUR_PANEL = Color(0.14, 0.15, 0.19)
	MenuSupport.COLOUR_SLOT_EMPTY = Color(0.18, 0.19, 0.24)
	MenuSupport.COLOUR_LOCKED = Color(0.24, 0.20, 0.12)
	MenuSupport.COLOUR_ACCENT = Color(0.98, 0.76, 0.33)
	MenuSupport.COLOUR_TEXT = Color(0.92, 0.93, 0.96)
	MenuSupport.COLOUR_TEXT_DIM = Color(0.60, 0.63, 0.70)
	MenuSupport.TIER_COLOURS = [
		Color(0.30, 0.45, 0.62), Color(0.30, 0.56, 0.45),
		Color(0.62, 0.46, 0.26), Color(0.55, 0.32, 0.48),
	]

	match name_text:
		"deuteranopia", "protanopia":
			# Blue / yellow / white / magenta: four that stay distinct when
			# red and green do not.
			MenuSupport.TIER_COLOURS = [
				Color(0.28, 0.48, 0.76), Color(0.85, 0.72, 0.24),
				Color(0.80, 0.80, 0.86), Color(0.68, 0.34, 0.66),
			]
			MenuSupport.COLOUR_ACCENT = Color(0.55, 0.78, 0.98)
		"tritanopia":
			# Blue and yellow merge instead, so this set leans on red/green.
			MenuSupport.TIER_COLOURS = [
				Color(0.78, 0.32, 0.30), Color(0.32, 0.62, 0.40),
				Color(0.84, 0.52, 0.66), Color(0.55, 0.55, 0.60),
			]
			MenuSupport.COLOUR_ACCENT = Color(0.92, 0.45, 0.45)
		"high_contrast":
			MenuSupport.COLOUR_BACKGROUND = Color(0.02, 0.02, 0.03)
			MenuSupport.COLOUR_PANEL = Color(0.08, 0.08, 0.10)
			MenuSupport.COLOUR_SLOT_EMPTY = Color(0.16, 0.16, 0.20)
			MenuSupport.COLOUR_TEXT = Color(1.0, 1.0, 1.0)
			MenuSupport.COLOUR_TEXT_DIM = Color(0.80, 0.82, 0.86)
			MenuSupport.COLOUR_ACCENT = Color(1.0, 0.90, 0.35)
			MenuSupport.TIER_COLOURS = [
				Color(0.36, 0.60, 0.90), Color(0.35, 0.80, 0.50),
				Color(0.95, 0.70, 0.30), Color(0.85, 0.45, 0.80),
			]


# =============================================================
#  SMALL THINGS
# =============================================================

## "1920x1080" -> Vector2i(1920, 1080). Anything unreadable comes back zero,
## and the caller leaves the window alone.
static func size_from_text(text: String) -> Vector2i:
	var parts := text.to_lower().split("x")
	if parts.size() != 2:
		return Vector2i.ZERO
	return Vector2i(int(parts[0].strip_edges()), int(parts[1].strip_edges()))


## The word a settings button shows: "Fullscreen", "High contrast".
static func pretty(text: String) -> String:
	return text.replace("_", " ").capitalize()
