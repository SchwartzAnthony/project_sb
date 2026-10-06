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
#      volume_master    0.0 to 1.0. One per row of data/SoundBuses.csv
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

## ROUND AN: the sound channels (buses) and their sliders are rows in this
## file. See bus_rows().
const BUS_SHEET := "res://data/SoundBuses.csv"


## ============ THE SOUND CHANNELS ============
##
## THE BUG THIS FIXES: "the volume sliders do nothing."
##
## Two faults at once. The project only ever had ONE bus, Master, so every
## sound in Audio.csv that named Music, Effects or UI quietly played on
## Master instead, and the Music slider turned down a bus that did not exist.
## And the sliders were named SFX and Voice while Audio.csv says Effects and
## UI, so even a real bus would have missed.
##
## Now data/SoundBuses.csv is the one list: one row per bus, the slider that
## goes with it, and its default. The buses are made from it when the game
## starts (ensure_buses), the Sound tab draws one slider per row, and
## Audio.csv is checked against the same list.
static func bus_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for row in MenuSupport.read_csv(BUS_SHEET):
		var bus := MenuSupport.field(row, "Bus").strip_edges()
		var key := MenuSupport.field(row, "Setting").strip_edges()
		if bus == "" or key == "":
			continue
		rows.append({
			"bus": bus,
			"slider": MenuSupport.field(row, "Slider", bus),
			"setting": key,
			"default": clampf(MenuSupport.field_float(row, "Default", 0.8), 0.0, 1.0),
		})
	if rows.is_empty():
		# No spreadsheet: the buses this game shipped with.
		rows = [
			{"bus": "Master", "slider": "Everything", "setting": "volume_master", "default": 0.9},
			{"bus": "Music", "slider": "Music", "setting": "volume_music", "default": 0.7},
			{"bus": "Effects", "slider": "Effects", "setting": "volume_sfx", "default": 0.9},
			{"bus": "UI", "slider": "Menu clicks", "setting": "volume_ui", "default": 0.9},
		]
	return rows


## The bus names, for Audio.csv's check.
static func bus_names() -> Array[String]:
	var names: Array[String] = []
	for row in bus_rows():
		names.append(String(row["bus"]))
	if not names.has("Master"):
		names.push_front("Master")
	return names


## Make every bus in SoundBuses.csv that the project does not have yet. Each
## new one feeds Master, so the Everything slider still turns down the lot.
## Safe to call as often as you like.
static func ensure_buses() -> void:
	for row in bus_rows():
		var bus := String(row["bus"])
		if AudioServer.get_bus_index(bus) >= 0:
			continue
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, bus)
		AudioServer.set_bus_send(index, "Master")


static func defaults() -> Dictionary:
	var made := {
		"screen_mode": "windowed",
		"resolution": "1920x1080",
		"vsync": true,
		"max_fps": 0,
		"palette": "default",
		"text_scale": 1.0,
		"pad_enabled": true,
		"pad_deadzone": 0.2,
		"pad_vibration": true,
		"keys": {},
	}
	# One volume per row of SoundBuses.csv.
	for row in bus_rows():
		made[String(row["setting"])] = float(row["default"])
	return made


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


## Which settings need the WINDOW touched when they change. Everything else
## is applied without going near the window, which matters: re-applying the
## screen settings resizes and repositions the window, so changing a colour
## used to make the whole window jump. Now it does not.
const SCREEN_KEYS: Array[String] = [
	"screen_mode", "resolution", "vsync", "max_fps",
]


## Change one value, save it, and put it into effect straight away.
static func put(tree: SceneTree, key: String, value: Variant) -> Dictionary:
	var settings := load_all()
	settings[key] = value
	save_all(settings)
	preview(tree, settings, key)
	return settings


## ROUND AN: PUT ONE VALUE INTO EFFECT WITHOUT SAVING IT. The Settings screen
## calls this as you click and drag, so you hear and see the change at once;
## its Save button is what writes settings.json.
##
## ONLY THE PART THAT CHANGED IS RE-APPLIED. Changing a volume touches the
## audio buses and nothing else; changing a palette repaints and nothing
## else. That is the fix for the window resizing itself when you picked a
## colour.
static func preview(tree: SceneTree, settings: Dictionary, key: String) -> void:
	if SCREEN_KEYS.has(key):
		_apply_screen(settings)
	elif key.begins_with("volume_"):
		_apply_sound(settings)
	elif key == "palette":
		_apply_palette(String(settings.get(key, "default")))
	elif key.begins_with("pad_"):
		_apply_pad(settings)
	elif key == "text_scale":
		TextScale.apply(tree, float(settings.get(key, 1.0)))
	# Anything else is read where it is used and needs nothing doing here.


## ROUND AN: write only `keys` from `settings` into settings.json, on top of
## what is already there. The key bindings and the language save themselves
## the moment they change, so the Settings screen's Save must not write an
## older copy of them back over the file.
static func save_some(settings: Dictionary, keys: Array) -> Dictionary:
	var on_disk := load_all()
	for key in keys:
		on_disk[key] = settings.get(key)
	save_all(on_disk)
	return on_disk


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
	TextScale.apply(tree, float(settings.get("text_scale", 1.0)))


# =============================================================
#  THE THREE WINDOW MODES
#
#  ============ WHY IT DID NOT WORK ============
#
#  It used to set the MODE and the BORDERLESS FLAG in whatever order the
#  match arm happened to be written, straight from whichever mode the window
#  was already in. That is two problems at once:
#
#    * going to fullscreen and then clearing the borderless flag can knock
#      the window straight back out of fullscreen again — which is why
#      "Fullscreen" appeared to do nothing at all;
#    * and "Borderless" set the flag and only then asked for a size, on a
#      window that was still carrying the small size it had been given last
#      time it was windowed — which is why it looked like it shrank.
#
#  ============ WHAT IT DOES NOW ============
#
#  Always go back to a plain window first, clear every flag, and only then
#  apply the mode that was asked for. One known starting point, three short
#  arms, and no arm has to know what the last one left behind.
#
#      windowed    a normal window at the chosen resolution, centred
#      fullscreen  the whole screen, no window at all
#      borderless  a window with no frame, filling the screen it is on
#
#  `borderless` uses the size of THE SCREEN THE WINDOW IS ON, not screen 0,
#  so it fills the right monitor on a two-monitor desk.
# =============================================================

static func _apply_screen(settings: Dictionary) -> void:
	var wanted := String(settings.get("screen_mode", "windowed"))

	# ---- one known starting point ----
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)

	match wanted:
		"fullscreen":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		"borderless":
			var screen := DisplayServer.window_get_current_screen()
			var box := DisplayServer.screen_get_size(screen)
			var corner := DisplayServer.screen_get_position(screen)
			# THE FLAG FIRST, THEN THE SIZE. A frame that is removed after the
			# size is set takes its own thickness off the window, and the
			# result is a window a few pixels short of the screen on two edges.
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
			DisplayServer.window_set_size(box)
			DisplayServer.window_set_position(corner)
		_:
			var box2 := size_from_text(String(settings.get("resolution", "1920x1080")))
			if box2.x > 0 and box2.y > 0:
				DisplayServer.window_set_size(box2)
			# CENTRED. Coming back from fullscreen leaves the window wherever
			# the desktop feels like putting it, which is usually half off the
			# top-left corner.
			var screen2 := DisplayServer.window_get_current_screen()
			var room := DisplayServer.screen_get_size(screen2)
			var at := DisplayServer.screen_get_position(screen2)
			DisplayServer.window_set_position(
				at + (room - DisplayServer.window_get_size()) / 2)

	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if bool(settings.get("vsync", true))
		else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(settings.get("max_fps", 0))


static func _apply_sound(settings: Dictionary) -> void:
	ensure_buses()
	for row in bus_rows():
		_set_bus(String(row["bus"]),
			float(settings.get(String(row["setting"]), float(row["default"]))))


## A slider from 0 to 1 is not decibels. This is the conversion, and it also
## MUTES rather than turning a bus down to a whisper at zero.
static func _set_bus(bus_name: String, level: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
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
	#
	# THE SHIPPED PALETTE IS THE ONE IN Theme.csv when there is one. The
	# constants below are what the game looked like before that file existed
	# and are what it falls back to without it. An accessibility palette then
	# paints over BOTH, because red-green colour blindness is not a thing a
	# designer's palette gets to overrule.
	MenuSupport.COLOUR_BACKGROUND = Color(0.09, 0.10, 0.13)
	MenuSupport.COLOUR_PANEL = Color(0.14, 0.15, 0.19)
	MenuSupport.COLOUR_SLOT_EMPTY = Color(0.18, 0.19, 0.24)
	MenuSupport.COLOUR_LOCKED = Color(0.24, 0.20, 0.12)
	MenuSupport.COLOUR_ACCENT = Color(0.98, 0.76, 0.33)
	MenuSupport.COLOUR_TEXT = Color(0.92, 0.93, 0.96)
	MenuSupport.COLOUR_TEXT_DIM = Color(0.60, 0.63, 0.70)
	MenuSupport.COLOUR_ATTACK = Color(0.95, 0.62, 0.36)
	MenuSupport.COLOUR_DEFEND = Color(0.44, 0.73, 0.94)
	MenuSupport.TIER_COLOURS = [
		Color(0.30, 0.45, 0.62), Color(0.30, 0.56, 0.45),
		Color(0.62, 0.46, 0.26), Color(0.55, 0.32, 0.48),
	]
	ThemeBook.apply_palette()

	match name_text:
		"deuteranopia", "protanopia":
			# Blue / yellow / white / magenta: four that stay distinct when
			# red and green do not.
			MenuSupport.TIER_COLOURS = [
				Color(0.28, 0.48, 0.76), Color(0.85, 0.72, 0.24),
				Color(0.80, 0.80, 0.86), Color(0.68, 0.34, 0.66),
			]
			MenuSupport.COLOUR_ACCENT = Color(0.55, 0.78, 0.98)
			# Warm orange against cool blue survives red-green blindness
			# intact, so ATTACK and DEFEND keep the colours they have above.
		"tritanopia":
			# Blue and yellow merge instead, so this set leans on red/green.
			MenuSupport.TIER_COLOURS = [
				Color(0.78, 0.32, 0.30), Color(0.32, 0.62, 0.40),
				Color(0.84, 0.52, 0.66), Color(0.55, 0.55, 0.60),
			]
			MenuSupport.COLOUR_ACCENT = Color(0.92, 0.45, 0.45)
			# Blue and yellow merge under tritanopia, so the cool half of the
			# attack/defend pair moves to a green that stays distinct.
			MenuSupport.COLOUR_ATTACK = Color(0.90, 0.40, 0.38)
			MenuSupport.COLOUR_DEFEND = Color(0.36, 0.68, 0.46)
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
			MenuSupport.COLOUR_ATTACK = Color(1.0, 0.66, 0.30)
			MenuSupport.COLOUR_DEFEND = Color(0.45, 0.80, 1.0)


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
