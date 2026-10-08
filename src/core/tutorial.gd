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
#                    YES plays the tutorial, then back to that save's base
#                    with the starting team. NO gives the base its starting
#                    team (below) and nothing else.
#    THE MAIN MENU   the Tutorial button plays it and comes back to the menu.
#
#  EITHER WAY it plays in a save of its own (user://tutorial_story.json,
#  wiped at the start and the end), so it opens and ends with nothing
#  affecting your real game (Anthony, 8 Oct).
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
#  plain players, three per Tier, with random names, made once per save.
#  Whether you said yes or no, the base ends up the same: the full team,
#  everything else locked.
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


## Start it. ALWAYS in a save of its own (user://tutorial_story.json, wiped
## every time), so nothing the tutorial does - its players, its flags, its
## match - ever reaches your real game (Anthony, 8 Oct: "the tutorial should
## open and end with nothing affecting the base game").
## `from_menu` true = back to the title screen at the end; false (a new
## save said Yes) = back to that save, at its base with the starting team.
static func start(tree: SceneTree, from_menu: bool) -> void:
	if tree == null:
		return
	var db := CardDatabase.get_db()
	var info := {
		"from_menu": from_menu,
		"save": GameState.SAVE_PATH,
		"teams": TeamRoster.SAVE_PATH,
	}
	_wipe_sealed()
	GameState.SAVE_PATH = SEALED_SAVE
	TeamRoster.SAVE_PATH = SEALED_TEAMS
	GameState.forget(tree)
	TeamSelection.clear(tree)
	tree.set_meta(META, info)

	var state := GameState.fetch(tree)
	if state != null:
		# The tutorial's own save never asks the question itself.
		state.set_flag("game_begun")
		state.set_flag("in_tutorial")
		state.save_to_disk()

	ScenePaths.clear_trail(tree)
	MatchMode.choose(tree, db.tune_text("tutorial_match_mode", "tutorial"))
	var first := db.tune_text("tutorial_first_scene", "prologue")
	print("[tutorial] Starting the tutorial in its own save: '%s', then the %s match." % [
		first, db.tune_text("tutorial_match_mode", "tutorial")])
	# A squad match walks straight through Team Select, so the screen goes
	# black from the end of the story, not after it.
	DialogueView.play(tree, first, ScenePaths.TEAM_SELECT)


## The tutorial is over (full time, or Quit in the match). Its save is thrown
## away and yours comes back exactly as it was.
static func finish(tree: SceneTree) -> void:
	if tree == null or not tree.has_meta(META):
		return
	var info: Dictionary = tree.get_meta(META)
	tree.remove_meta(META)
	MatchMode.clear(tree)
	TeamSelection.clear(tree)
	ScenePaths.clear_trail(tree)

	GameState.SAVE_PATH = String(info.get("save", SaveSlots.REAL_STATE))
	TeamRoster.SAVE_PATH = String(info.get("teams", SaveSlots.REAL_TEAMS))
	GameState.forget(tree)
	_wipe_sealed()

	if bool(info.get("from_menu", true)):
		print("[tutorial] Finished. Nothing kept - to the title screen.")
		ScenePaths.go_to(tree, ScenePaths.MAIN_MENU, false)
		return

	# A new save said Yes: it gets exactly what No would have given it.
	give_starting_team(GameState.fetch(tree))
	print("[tutorial] Finished. Nothing kept - to the base: the starting team, everything else locked.")
	ScenePaths.go_to(tree, ScenePaths.BASE, false)


static func _wipe_sealed() -> void:
	for path in [SEALED_SAVE, SEALED_TEAMS]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


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
