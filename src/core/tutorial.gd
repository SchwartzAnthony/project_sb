class_name Tutorial
extends RefCounted

# =============================================================
#  THE TUTORIAL  (round AN - Anthony, 7 Oct)
#
#  "Remove the Introduction and add it to the Tutorial on the main menu.
#   When a player starts a brand new game, ask them: would you like to do
#   the Tutorial? If not, you can find it later on the main menu."
#
#  ============ THE TWO WAYS IN ============
#
#    A NEW SAVE      the base asks the question (Language.csv tutorial_offer_*).
#                    YES plays the tutorial in that save. NO gives the base its
#                    starting team (below) and nothing else.
#    THE MAIN MENU   the Tutorial button plays it in a save of its own
#                    (user://tutorial_story.json, wiped every time), so your
#                    real game is never touched, and comes back to the menu.
#
#  ============ WHAT IT IS ============
#
#    1. Pub Dialogue 1 - the Dialogue.csv scene in Tuning.csv tutorial_first_scene
#    2. the tutorial match - MatchModes.csv row tutorial_match_mode, with the
#       Head Coach's stops in MatchTalk.csv (Mode = tutorial)
#    3. full time - the base, locked, with the starting team
#
#  ============ THE STARTING TEAM ============
#
#  Tuning.csv starting_team names a squad CSV (data/StartingTeam.csv): twelve
#  plain players, three per Tier. Each ID is made ONCE per save and kept, so
#  a player who already played the tutorial match under the same ID (the
#  IDs match data/IntroSquad.csv) is the same person at the base. Whether
#  you said yes or no, the base ends up the same: the full team, everything
#  else locked.
# =============================================================

const META := "cw_tutorial"
const SEALED_SAVE := "user://tutorial_story.json"
const SEALED_TEAMS := "user://tutorial_story_teams.json"
const DONE_FLAG := "starting_team_given"


## Is the tutorial running right now?
static func active(tree: SceneTree) -> bool:
	return tree != null and tree.has_meta(META)


## Should a brand-new save ask? (Tuning.csv tutorial_offer, true.)
static func offer_on_new_game() -> bool:
	return CardDatabase.get_db().tune_bool("tutorial_offer", true)


## The question over the base. True = yes, do the tutorial.
static func ask(host: Node) -> bool:
	var options: Array[String] = [
		Loc.text("tutorial_offer_yes", "Yes, show me"),
		Loc.text("tutorial_offer_no", "No, straight to the base"),
	]
	var picked: int = await ChoiceWindow.ask(host,
		Loc.text("tutorial_offer_title", "THE TUTORIAL"),
		Loc.text("tutorial_offer_text", "Would you like to do the Tutorial? If not, you can find it later on the main menu."),
		options)
	return picked == 0


## Start it. `sealed` = in a save of its own (from the main menu).
static func start(tree: SceneTree, sealed: bool) -> void:
	if tree == null:
		return
	var db := CardDatabase.get_db()
	var info := {"sealed": sealed}
	if sealed:
		info["save"] = GameState.SAVE_PATH
		info["teams"] = TeamRoster.SAVE_PATH
		for path in [SEALED_SAVE, SEALED_TEAMS]:
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		GameState.SAVE_PATH = SEALED_SAVE
		TeamRoster.SAVE_PATH = SEALED_TEAMS
		GameState.forget(tree)
		TeamSelection.clear(tree)
	tree.set_meta(META, info)

	var state := GameState.fetch(tree)
	if state != null:
		# A tutorial save never asks the question itself.
		state.set_flag("game_begun")
		state.set_flag("in_tutorial")
		state.save_to_disk()

	ScenePaths.clear_trail(tree)
	MatchMode.choose(tree, db.tune_text("tutorial_match_mode", "tutorial"))
	var first := db.tune_text("tutorial_first_scene", "prologue")
	print("[tutorial] Starting the tutorial (%s): '%s', then the %s match." % [
		"its own save" if sealed else "this save", first,
		db.tune_text("tutorial_match_mode", "tutorial")])
	# A squad match walks straight through Team Select, so the screen goes
	# black from the end of the story, not after it.
	DialogueView.play(tree, first, ScenePaths.TEAM_SELECT)


## The tutorial match is over.
static func finish(tree: SceneTree) -> void:
	if tree == null or not tree.has_meta(META):
		return
	var info: Dictionary = tree.get_meta(META)
	tree.remove_meta(META)
	var state := GameState.fetch(tree)
	if state != null:
		state.set_flag("in_tutorial", false)
		state.set_flag("tutorial_done")
	MatchMode.clear(tree)
	TeamSelection.clear(tree)
	ScenePaths.clear_trail(tree)

	if bool(info.get("sealed", false)):
		if state != null:
			state.save_to_disk()
		GameState.SAVE_PATH = String(info.get("save", SaveSlots.REAL_STATE))
		TeamRoster.SAVE_PATH = String(info.get("teams", SaveSlots.REAL_TEAMS))
		GameState.forget(tree)
		print("[tutorial] Finished. Your own save is back - to the title screen.")
		ScenePaths.go_to(tree, ScenePaths.MAIN_MENU, false)
		return

	give_starting_team(state)
	print("[tutorial] Finished. To the base: the full team, everything else locked.")
	ScenePaths.go_to(tree, ScenePaths.BASE, false)


## Leave it half way (the pause menu's Quit in the tutorial match).
static func abandon(tree: SceneTree) -> void:
	if active(tree):
		finish(tree)


## The base after the tutorial, or after NO: a full team of plain players
## with random names (Tuning.csv starting_team), and nothing unlocked. Once
## per save.
static func give_starting_team(state: GameState) -> void:
	if state == null or state.has_flag(DONE_FLAG):
		return
	var db := CardDatabase.get_db()
	var file := db.tune_text("starting_team", "StartingTeam.csv")
	var picked := SquadSheet.selection_from(file, db, state, true)
	state.set_flag(DONE_FLAG)
	state.save_to_disk()
	print("[tutorial] Starting team from %s: %d named players at the base." % [
		file, RecruitBook.names(state).size()])
	if picked == null:
		push_warning("[tutorial] %s could not make a team." % file)
