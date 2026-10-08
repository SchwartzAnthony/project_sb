class_name TutorialJumps
extends RefCounted

# =============================================================
#  TUTORIAL JUMPS - a developer tool  (round AN, Anthony 8 Oct)
#
#  "Can you create a dev menu for me to jump between the different
#   important aspects of the tutorial?"
#
#  The Dev screen (the Dev button on the base) has a TUTORIAL JUMPS row: one
#  button per row of data/TutorialJumps.csv.
#
#    ID       a name for the row
#    Label    the words on the button
#    Kind     brewery    the tutorial Brewery TIME OUT on its own, Hanna and
#                        all. Value = the flag the Guide.csv rows wait on
#                        (tut_brewery)
#             minigame   one machine's brewing mini-game. Value = the
#                        BrewerySections.csv ID. Played as a brewer of
#                        Tuning.csv brewery_tour_chance %, and it CAN be lost,
#                        so you see both endings
#    Value    see Kind
#
#  A jump never touches your real save. The Brewery jump plays in a save of
#  its own (user://tutorial_jump.json, wiped before and after) with
#  flag:in_tutorial set, exactly as the tutorial does; when Hanna is done
#  you are back on the Dev screen with your own save.
#  A Kind this file does not know is greyed out and says so.
# =============================================================

const FILE := "res://data/TutorialJumps.csv"
const JUMP_SAVE := "user://tutorial_jump.json"
const KINDS: Array[String] = ["brewery", "minigame"]


static func rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row in MenuSupport.read_csv(FILE):
		var id_text := MenuSupport.field(row, "ID").strip_edges()
		if id_text == "":
			continue
		out.append({
			"id": id_text,
			"label": MenuSupport.field(row, "Label", id_text).strip_edges(),
			"kind": MenuSupport.field(row, "Kind").strip_edges().to_lower(),
			"value": MenuSupport.field(row, "Value").strip_edges(),
		})
	return out


static func known(row: Dictionary) -> bool:
	return KINDS.has(String(row.get("kind", "")))


## Do the jump over `host` (the Dev screen). `done` is called with a line to
## show when it is over.
static func jump(host: Control, row: Dictionary, done: Callable) -> void:
	match String(row.get("kind", "")):
		"brewery":
			await _brewery(host, String(row["value"]))
			done.call("Back from the tutorial Brewery. Your own save is untouched.")
		"minigame":
			var won := await _minigame(host, String(row["value"]))
			done.call("%s: %s." % [row["label"], "WON - the batch is made" if won else "LOST - the batch is spoiled"])
		_:
			done.call("'%s' is not a kind of jump this game knows yet." % row.get("kind", ""))


static func _minigame(host: Control, section_id: String) -> bool:
	var game := BreweryMinigame.game_for(section_id)
	if game.is_empty():
		return false
	var section := BreweryBook.section(section_id)
	var view := BreweryMinigame.open(host, game,
		int(CardDatabase.get_db().tune_float("brewery_tour_chance", 85.0)),
		String(section.get("name", section_id)), false)
	return await view.finished


## The tutorial Brewery on its own, in a throwaway save.
static func _brewery(host: Control, flag: String) -> void:
	var tree := host.get_tree()
	var real_path := GameState.SAVE_PATH
	host.get_viewport().gui_release_focus()
	GameState.fetch(tree).save_to_disk()
	_wipe()
	GameState.SAVE_PATH = JUMP_SAVE
	GameState.forget(tree)
	var state := GameState.fetch(tree)
	state.set_flag("in_tutorial", true)
	state.set_flag(flag.replace("-", "_"), true)

	var layer := CanvasLayer.new()
	layer.layer = 140
	host.add_child(layer)
	var screen := (load(MatchCoach.BREWERY_SCENE) as PackedScene).instantiate() as BreweryScreen
	# No Back to the base: Hanna ends it, as in the match.
	screen.in_match = true
	layer.add_child(screen)
	await screen.left
	layer.queue_free()

	GameState.SAVE_PATH = real_path
	GameState.forget(tree)
	_wipe()
	print("[tutorial jumps] Brewery done - back in %s." % real_path)


static func _wipe() -> void:
	if FileAccess.file_exists(JUMP_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(JUMP_SAVE))
