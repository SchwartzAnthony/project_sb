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
#                    YES plays the tutorial; at the end that save gets its
#                    starting team and you are on the main menu (Tuning.csv
#                    tutorial_ends_on_menu, Anthony 24 Oct), so Play on its
#                    mug opens a fresh game. NO gives the base its starting
#                    team (below) and nothing else.
#    THE MAIN MENU   no Tutorial button since 24 Oct (Anthony); the
#                    tutorial_game action still works if MenuConfig.csv
#                    gets the row back.
#    TUTORIAL ONLY   Tuning.csv tutorial_only (false since 24 Oct). true =
#                    Play on any save plays the Tutorial and nothing else;
#                    at the end that save is deleted again and you are on
#                    the main menu. A save that was already being played is
#                    kept.
#
#  EITHER WAY it plays in a save of its own (user://tutorial_story.json,
#  wiped at the start and the end), so it opens and ends with nothing
#  affecting your real game (Anthony, 8 Oct).
#
#  ============ WHAT IT IS ============
#
#    1. the base (23 Oct) - the Dialogue.csv scene in Tuning.csv
#       tutorial_first_scene, then the base with only the Pub to press; the
#       Pub plays Pub Dialogue 1 (Tuning.csv tutorial_pub_scene). A blank
#       tutorial_pub_scene goes from the first scene straight to the match.
#    2. the tutorial match - MatchModes.csv row tutorial_match_mode, with the
#       Head Coach's stops in MatchTalk.csv (Mode = tutorial)
#    3. full time - "the morning after" (tutorial_morning.gd): the Dorms,
#       the Head Coach's goodbye and a first Adventure with Koch, still in
#       the tutorial's own save. Tuning.csv tutorial_morning_after false
#       skips it.
#    4. the end - the base, locked, with the starting team
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
## Set while the Tutorial waits for you to press the Pub on the base.
const PUB_FLAG := "tut_to_pub"


## Is the tutorial running right now?
static func active(tree: SceneTree) -> bool:
	return tree != null and tree.has_meta(META)


## Tuning.csv tutorial_only: Play on a save only ever plays the Tutorial,
## and the save is deleted again at the end (Anthony, 24 Oct).
static func only() -> bool:
	return CardDatabase.get_db().tune_bool("tutorial_only", false)


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
## save said Yes) = that save gets its starting team, then the title screen
## (or its base with Tuning.csv tutorial_ends_on_menu false).
## `erase_slot` above 0 (tutorial_only) = that save slot is deleted at the end.
static func start(tree: SceneTree, from_menu: bool, erase_slot: int = 0) -> void:
	if tree == null:
		return
	var db := CardDatabase.get_db()
	var info := {
		"from_menu": from_menu,
		"save": GameState.SAVE_PATH,
		"teams": TeamRoster.SAVE_PATH,
		"erase_slot": erase_slot,
	}
	_wipe_sealed()
	GameState.SAVE_PATH = SEALED_SAVE
	TeamRoster.SAVE_PATH = SEALED_TEAMS
	GameState.forget(tree)
	TeamSelection.clear(tree)
	tree.set_meta(META, info)

	var state := GameState.fetch(tree)
	# ROUND AN (Anthony, 23 Oct): the Tutorial opens on the base. With a
	# Tuning.csv tutorial_pub_scene, the first scene ends on the base, where
	# only the Pub can be pressed (Guide.csv tut_intro_pub), and the Pub plays
	# that scene and then the tutorial match.
	var pub_scene := db.tune_text("tutorial_pub_scene", "")
	if state != null:
		# The tutorial's own save never asks the question itself.
		state.set_flag("game_begun")
		state.set_flag("in_tutorial")
		if pub_scene != "":
			var effects := db.tune_text("tutorial_start_effects", "")
			if effects != "":
				DialogueGrammar.apply(effects, state)
			state.set_flag(PUB_FLAG)
			# The Head Coach shows them the Pub himself.
			NewUnlocksPanel.mark_all_seen(state)
		state.save_to_disk()

	ScenePaths.clear_trail(tree)
	MatchMode.choose(tree, db.tune_text("tutorial_match_mode", "tutorial"))
	var first := db.tune_text("tutorial_first_scene", "prologue")
	print("[tutorial] Starting the tutorial in its own save: '%s', then the %s match." % [
		first, db.tune_text("tutorial_match_mode", "tutorial")])
	if pub_scene != "":
		DialogueView.play(tree, first, ScenePaths.BASE)
		return
	# A squad match walks straight through Team Select, so the screen goes
	# black from the end of the story, not after it.
	DialogueView.play(tree, first, ScenePaths.TEAM_SELECT)


## True when a press of this Buildings.csv row is the Tutorial's walk into
## the Pub (Tuning.csv tutorial_pub_building): then the pub scene plays and
## the tutorial match follows. The base asks before it opens a building.
static func walk_into_pub(tree: SceneTree, state: GameState, building_id: String) -> bool:
	if not active(tree) or state == null or not state.has_flag(PUB_FLAG):
		return false
	var db := CardDatabase.get_db()
	if CardDatabase._normalise(building_id) != CardDatabase._normalise(db.tune_text("tutorial_pub_building", "pub")):
		return false
	state.set_flag(PUB_FLAG, false)
	state.save_to_disk()
	var scene := db.tune_text("tutorial_pub_scene", "prologue")
	print("[tutorial] Into the Pub: '%s', then the %s match." % [scene, db.tune_text("tutorial_match_mode", "tutorial")])
	DialogueView.play(tree, scene, ScenePaths.TEAM_SELECT)
	return true


## FULL TIME in the tutorial match. ROUND AN: "The morning after"
## (tutorial_morning.gd) carries the story on into the Dorms and a first
## Adventure when Tuning.csv tutorial_morning_after is true; otherwise the
## tutorial ends here. `played` = the side that was on the pitch.
static func full_time(tree: SceneTree, played: Array) -> void:
	if tree == null or not tree.has_meta(META):
		return
	if TutorialMorning.on():
		TutorialMorning.begin(tree, played)
		return
	finish(tree)


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

	# TUTORIAL ONLY (Tuning.csv tutorial_only): the save Play made is deleted
	# again. The menu then writes into the tutorial's throwaway file (wiped
	# at the next start), so the deleted save stays empty.
	var erase_slot := int(info.get("erase_slot", 0))
	if erase_slot > 0:
		SaveSlots.erase(erase_slot)
		GameState.SAVE_PATH = SEALED_SAVE
		TeamRoster.SAVE_PATH = SEALED_TEAMS
		GameState.forget(tree)
		print("[tutorial] Tutorial only: save %d deleted again." % erase_slot)

	if bool(info.get("from_menu", true)):
		print("[tutorial] Finished. Nothing kept - to the title screen.")
		ScenePaths.go_to(tree, ScenePaths.MAIN_MENU, false)
		return

	# A new save said Yes: it gets exactly what No would have given it.
	give_starting_team(GameState.fetch(tree))
	# Tuning.csv tutorial_ends_on_menu (Anthony, 24 Oct): the Tutorial is
	# self-contained and ends on the main menu; the save waits as a fresh
	# game for Play on its mug.
	if CardDatabase.get_db().tune_bool("tutorial_ends_on_menu", true):
		print("[tutorial] Finished. Nothing kept - the save waits as a fresh game; to the title screen.")
		ScenePaths.go_to(tree, ScenePaths.MAIN_MENU, false)
		return
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
