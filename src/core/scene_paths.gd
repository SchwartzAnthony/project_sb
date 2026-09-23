class_name ScenePaths
extends RefCounted

# =============================================================
#  SCENE PATHS — one place that knows where the screens live
#
#  Every menu screen asks this file "where is the match scene?" instead of
#  spelling out a folder. Two reasons that matters:
#
#    1. If you move a scene into a different folder, you fix ONE line here
#       instead of hunting through three scripts.
#    2. If a path here is wrong, the game does not just fail — it searches
#       res:// for a file of that name, uses what it finds, and prints the
#       correct path in the Output panel so you can paste it in below.
#
#  So a folder layout that does not match mine is a printed note, not a
#  broken button.
# =============================================================

const MAIN_MENU := "res://src/ui/main_menu.tscn"
const CLASS_SELECT := "res://src/ui/class_select.tscn"
const TEAM_BUILDER := "res://src/ui/team_builder.tscn"
const MATCH := "res://src/formations/main_scene.tscn"
const STORY := "res://src/ui/dialogue_view.tscn"
const BASE := "res://src/ui/base_screen.tscn"
const TALENTS := "res://src/ui/talent_screen.tscn"
const CLASS_TREE := "res://src/ui/class_tree_screen.tscn"
const BREWERY := "res://src/ui/brewery_screen.tscn"
const SHOP := "res://src/ui/shop_screen.tscn"
## THE FOUR ROOMS AND THE BOARD. One script, five scenes — see room_screen.gd.
const ACHIEVEMENTS := "res://src/ui/rooms/achievements.tscn"
const DORMS := "res://src/ui/rooms/dorms.tscn"
const CLUBHOUSE := "res://src/ui/rooms/clubhouse.tscn"
const TROPHIES := "res://src/ui/rooms/trophies.tscn"
const TRAINING := "res://src/ui/rooms/training.tscn"
const PUB := "res://src/ui/pub_screen.tscn"
const SEASON := "res://src/ui/season_screen.tscn"
const STATS := "res://src/ui/match_stats_screen.tscn"
const UNLOCKS := "res://src/ui/unlock_board.tscn"
const INSPECTOR := "res://src/ui/save_inspector.tscn"
const PAUSE := "res://src/ui/pause_menu.tscn"
const BOUNTY_BOARD := "res://src/ui/bounty_board.tscn"
const ADVENTURE := "res://src/adventure/adventure_scene.tscn"
const TEAM_SELECT := "res://src/ui/team_select.tscn"
const SETTINGS := "res://src/ui/settings_screen.tscn"
const SEASON_PICKER := "res://src/ui/season_picker.tscn"
const SLOTS := "res://src/ui/slot_screen.tscn"


## Turn a short word from a CSV into a screen path, so Progression.csv can
## say  goto:base  instead of a res:// path a non-coder should never have to
## type. An unknown word falls back to the main menu rather than nowhere.
static func for_name(screen: String) -> String:
	match screen.strip_edges().to_lower():
		"menu", "main_menu", "mainmenu":
			return MAIN_MENU
		"classes", "class_select", "classselect":
			return CLASS_SELECT
		"builder", "team_builder", "teambuilder":
			return TEAM_BUILDER
		"teams", "team", "team_select", "squads":
			return TEAM_SELECT
		"settings", "options", "config":
			return SETTINGS
		"match", "game", "pitch":
			return MATCH
		"story", "dialogue":
			return STORY
		"base", "hub", "home":
			return BASE
		"talents", "talent", "tree":
			return TALENTS
		"classtree", "class_tree", "classes_tree", "emblems", "stars":
			return CLASS_TREE
		"brewery", "brewhouse", "malthouse":
			return BREWERY
		"brewer", "shop", "cart", "traveling_brewer", "travelling_brewer":
			return SHOP
		"achievements", "achievement", "board_of_achievements":
			return ACHIEVEMENTS
		"dorms", "dorm", "beds":
			return DORMS
		"clubhouse", "club_house", "rest", "recovery":
			return CLUBHOUSE
		"trophies", "trophy", "trophy_room":
			return TROPHIES
		"training", "training_ground", "ausbildung":
			return TRAINING
		"pub", "tavern", "brews":
			return PUB
		"season", "table", "results", "fixtures":
			return SEASON
		"seasons", "competitions", "leagues", "season_picker":
			return SEASON_PICKER
		"slots", "saves", "slot", "load":
			return SLOTS
		"stats", "report", "fulltime", "full_time":
			return STATS
		"unlocks", "board", "locked", "progress":
			return UNLOCKS
		"inspector", "save", "dev", "debug":
			return INSPECTOR
		# "board" on its own already means the unlock board, above.
		"bounty", "bounties", "bounty_board", "explore":
			return BOUNTY_BOARD
		"adventure", "run", "scroll", "biome":
			return ADVENTURE
		_:
			push_warning("[scenes] Progression.csv asks to go to '%s', which is not a screen. Going to the main menu instead." % screen)
			return MAIN_MENU

## Folders never worth searching.
const SKIP_DIRS: Array[String] = [".godot", ".git", "addons", "sheet_previews"]

static var _resolved: Dictionary = {}


## Give it one of the constants above; get back a path that actually exists.
static func resolve(preferred: String) -> String:
	if ResourceLoader.exists(preferred):
		return preferred

	var wanted := preferred.get_file()
	if _resolved.has(wanted):
		return String(_resolved[wanted])

	var found := _search(wanted)
	if found == "":
		push_error("[scenes] Could not find '%s' anywhere in res://. The button that needed it will do nothing." % wanted)
		_resolved[wanted] = preferred
		return preferred

	print("[scenes] '%s' is not at %s — found it at %s instead." % [wanted, preferred, found])
	print("         Open src/core/scene_paths.gd and put that path in, and this search stops happening.")
	_resolved[wanted] = found
	return found


## Change to a scene by one of the constants above, searching if need be.
##
## The change is DEFERRED — it happens at the end of the current frame rather
## than this instant. That matters because a scene is very often changed from
## inside _ready(), and Godot will not let a node be removed while the tree is
## still busy adding it:
##
##   "Parent node is busy adding/removing children, remove_child() can't be
##    called at this time."
##
## Deferring here fixes it for every caller at once, so no screen has to
## remember to do it itself.
# =============================================================
#  WHERE YOU CAME FROM  —  the Back button
#
#  Every screen used to hard-code where its Back button went, so leaving the
#  season screen always landed you at the base even if you had arrived from
#  the main menu. That is the bug.
#
#  go_to() now remembers the screen you were on, and go_back() returns to it.
#  The trail lives on the SceneTree, the same place GameState and
#  TeamSelection ride, so it survives changing scene.
#
#  It is capped at TRAIL_MAX so that wandering around the base for an hour
#  does not build a list you then have to press Back fifty times to escape.
# =============================================================

const TRAIL_KEY := "cw_screen_trail"
const TRAIL_MAX := 12


static func _trail(tree: SceneTree) -> Array:
	if tree == null:
		return []
	if not tree.has_meta(TRAIL_KEY):
		tree.set_meta(TRAIL_KEY, [] as Array)
	return tree.get_meta(TRAIL_KEY) as Array


## Where you are standing right now, or "" if that cannot be told.
static func here(tree: SceneTree) -> String:
	if tree == null or tree.current_scene == null:
		return ""
	return tree.current_scene.scene_file_path


## Change to a screen, remembering the one you are leaving.
##
## `remember` is false for a screen you should never come BACK to — a match,
## for instance. Pressing Back on the season table should not restart the
## game you just played.
static func go_to(tree: SceneTree, preferred: String, remember: bool = true) -> void:
	if tree == null:
		return
	var path := resolve(preferred)
	if not ResourceLoader.exists(path):
		push_warning("[scenes] Nothing to load at '%s' — staying put." % path)
		return

	# THE CLOCK GOES STRAIGHT ON EVERY SCREEN CHANGE. A slow-motion dip that
	# was running when you left a fight would otherwise carry its slowed
	# clock into the next screen and never end. See juice.gd.
	Juice.release()

	if remember:
		var from := here(tree)
		# Not the screen you are already on: pressing a button that reloads
		# the same page should not fill the trail with copies of it.
		if from != "" and from != path:
			var trail := _trail(tree)
			trail.append(from)
			while trail.size() > TRAIL_MAX:
				trail.remove_at(0)

	# The music for the screen you are about to see. One hook here covers
	# every screen there is and every screen you ever add, which is why no
	# individual screen has a line of audio code in it.
	AudioDirector.fire(tree, "screen_opened",
		{"screen": screen_word(path)}, GameState.fetch(tree))

	tree.change_scene_to_file.call_deferred(path)


## `res://src/ui/season_screen.tscn` -> `season`. This is the word you put in
## Audio.csv's Match column, and the same word `goto:` already understands.
static func screen_word(path: String) -> String:
	var word := path.get_file().get_basename().to_lower()
	for tail in ["_screen", "_menu", "_view", "_board", "_inspector"]:
		if word.ends_with(tail):
			word = word.substr(0, word.length() - tail.length())
	return word


## Go back to wherever you came from. `fallback` is used when there is
## nowhere to go back to — the first screen of a session, usually.
static func go_back(tree: SceneTree, fallback: String = MAIN_MENU) -> void:
	if tree == null:
		return
	var trail := _trail(tree)
	while not trail.is_empty():
		var last := String(trail.pop_back())
		if last != "" and last != here(tree) and ResourceLoader.exists(last):
			print("[nav] Back: %s -> %s%s" % [screen_word(here(tree)),
				screen_word(last), _trail_text(trail)])
			tree.change_scene_to_file.call_deferred(last)
			return

	# NOTHING TO GO BACK TO. If you are seeing this when you expected Back to
	# work, the screen you came FROM was opened with go_to(..., false) or by
	# change_scene_to_file() directly — neither of which leaves a trail.
	print("[nav] Back from %s: nothing remembered, falling back to %s."
		% [screen_word(here(tree)), screen_word(resolve(fallback))])
	go_to(tree, fallback, false)


## The trail as words, for the [nav] lines. Newest last.
static func _trail_text(trail: Array) -> String:
	if trail.is_empty():
		return "   (nothing left behind it)"
	var words: Array[String] = []
	for path in trail:
		words.append(screen_word(String(path)))
	return "   (behind it: %s)" % " > ".join(words)


## Is there anywhere to go back to? Screens use this to decide whether their
## button should say "Back" or name the fallback outright.
static func can_go_back(tree: SceneTree) -> bool:
	return not _trail(tree).is_empty()


## Forget the trail. Called when a match starts, so that Back from the
## post-match screens never walks you into the match you just finished.
static func clear_trail(tree: SceneTree) -> void:
	if tree != null:
		tree.set_meta(TRAIL_KEY, [] as Array)


## Breadth-first walk of res:// looking for one file name.
static func _search(file_name: String) -> String:
	var queue: Array[String] = ["res://"]
	while not queue.is_empty():
		var dir_path: String = queue.pop_front()
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue

		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if entry.begins_with("."):
				entry = dir.get_next()
				continue

			var full := dir_path.path_join(entry)
			if dir.current_is_dir():
				if not SKIP_DIRS.has(entry):
					queue.append(full)
			elif entry == file_name:
				dir.list_dir_end()
				return full
			entry = dir.get_next()
		dir.list_dir_end()
	return ""
