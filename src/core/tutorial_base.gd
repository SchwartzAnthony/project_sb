class_name TutorialBase
extends RefCounted

# =============================================================
#  THE TUTORIAL BASE — the same game, in a sealed room
#
#  ============ WHAT IT IS ============
#
#  Pressing Tutorial on the title screen drops you into a base that looks and
#  works exactly like the real one, because it IS the real one — the same
#  screen, the same buttons, the same match. Two things are swapped out
#  underneath it:
#
#      THE SPREADSHEETS   res://data/tutorial/ instead of res://data/
#      THE SAVE           user://tutorial_save.json instead of your own
#
#  So the tutorial has its own buildings, its own visitors and its own
#  progress, and NOTHING you do in it can reach your real game. Leaving puts
#  both back and forgets the tutorial save is there.
#
#  ============ HOW YOU WRITE IT ============
#
#  Make the folder res://data/tutorial/ and put two files in it:
#
#      Buildings.csv    the handful of buildings the tutorial needs
#      Visitors.csv     whoever explains them
#
#  Same columns as the real ones. That is the entire job — there is no
#  tutorial script, no step list and no code. A tutorial is a small base
#  with a talkative visitor, and the conversation itself is Dialogue.csv
#  rows like every other conversation in the game.
#
#  If the folder is missing, pressing Tutorial says so on the title screen
#  rather than dropping you into an empty field.
#
#  ============ WHY NOT A SEPARATE SCENE? ============
#
#  Because a tutorial built out of its own screens teaches the tutorial, and
#  then stops working the day you change the real one. This way the tutorial
#  cannot drift: it is the game, with different furniture.
# =============================================================

const FOLDER := "res://data/tutorial/"
const SAVE_PATH := "user://tutorial_save.json"
const REAL_FOLDER := "res://data/"
const REAL_SAVE := "user://story_state.json"
const FLAG := "cw_in_tutorial"


## Is the tutorial running right now? The base screen asks, so it can show
## the banner and the way out.
static func active(tree: SceneTree) -> bool:
	return tree != null and tree.has_meta(FLAG)


## Is there a tutorial to enter? The title screen asks before it offers.
static func exists() -> bool:
	return DirAccess.dir_exists_absolute(FOLDER)


# =============================================================
#  IN
# =============================================================

## `which` lets one button word pick one of several tutorials later —
## `tutorial:advanced` would read res://data/tutorial_advanced/. Passing ""
## uses the ordinary one.
static func enter(tree: SceneTree, which: String = "") -> void:
	if tree == null:
		return

	var folder := FOLDER
	var save := SAVE_PATH
	if which.strip_edges() != "":
		var slug := which.strip_edges().to_lower().replace(" ", "_")
		folder = "res://data/tutorial_%s/" % slug
		save = "user://tutorial_%s.json" % slug

	if not DirAccess.dir_exists_absolute(folder):
		push_warning("[tutorial] There is no %s yet, so there is no tutorial to play. Make that folder and put a Buildings.csv and a Visitors.csv in it." % folder)
		print("[tutorial] Nothing at %s — staying on the menu." % folder)
		return

	tree.set_meta(FLAG, true)

	# The two swaps. Everything else in the game reads these two values
	# without knowing they can change, which is why nothing else needed
	# editing to make a tutorial exist.
	BaseDB.DATA_DIR = folder
	DialogueDB.DATA_DIR = folder
	GameState.SAVE_PATH = save

	BaseDB.reload()
	DialogueDB.reload()
	GameState.forget(tree)          # so the tutorial save is read, not yours
	ScenePaths.clear_trail(tree)

	print("[tutorial] Entering the tutorial base.")
	print("           Buildings and visitors: %s" % folder)
	print("           Progress: %s" % ProjectSettings.globalize_path(save))
	ScenePaths.go_to(tree, ScenePaths.BASE, false)


# =============================================================
#  OUT
# =============================================================

## Back to the real game. Both swaps are undone and the tutorial's progress
## is left on disk untouched, so coming back picks up where you stopped.
static func leave(tree: SceneTree) -> void:
	if tree == null:
		return

	var state := GameState.fetch(tree)
	if state != null:
		state.save_to_disk()        # into the TUTORIAL save, which is correct

	if tree.has_meta(FLAG):
		tree.remove_meta(FLAG)

	BaseDB.DATA_DIR = REAL_FOLDER
	DialogueDB.DATA_DIR = REAL_FOLDER
	GameState.SAVE_PATH = REAL_SAVE

	BaseDB.reload()
	DialogueDB.reload()
	GameState.forget(tree)          # your real save is read back in
	TeamSelection.clear(tree)
	ScenePaths.clear_trail(tree)

	print("[tutorial] Leaving the tutorial. Your own save is back.")
	ScenePaths.go_to(tree, ScenePaths.MAIN_MENU, false)


## Throw the tutorial's progress away, so it can be played from the top. The
## real save is never touched by this.
static func wipe() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
		print("[tutorial] Tutorial progress cleared.")
