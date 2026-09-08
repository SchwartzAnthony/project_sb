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
const PUB := "res://src/ui/pub_screen.tscn"
const SEASON := "res://src/ui/season_screen.tscn"
const STATS := "res://src/ui/match_stats_screen.tscn"
const UNLOCKS := "res://src/ui/unlock_board.tscn"
const INSPECTOR := "res://src/ui/save_inspector.tscn"


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
		"match", "game", "pitch":
			return MATCH
		"story", "dialogue":
			return STORY
		"base", "hub", "home":
			return BASE
		"talents", "talent", "tree":
			return TALENTS
		"pub", "tavern", "brews":
			return PUB
		"season", "table", "results", "fixtures":
			return SEASON
		"stats", "report", "fulltime", "full_time":
			return STATS
		"unlocks", "board", "locked", "progress":
			return UNLOCKS
		"inspector", "save", "dev", "debug":
			return INSPECTOR
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
static func go_to(tree: SceneTree, preferred: String) -> void:
	if tree == null:
		return
	var path := resolve(preferred)
	if not ResourceLoader.exists(path):
		push_warning("[scenes] Nothing to load at '%s' — staying put." % path)
		return
	tree.change_scene_to_file.call_deferred(path)


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
