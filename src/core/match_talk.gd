class_name MatchTalk
extends RefCounted

# =============================================================
#  MATCH TALK — the Head Coach stops the match to explain  (round AN)
#
#  data/MatchTalk.csv, one row per interruption:
#
#    ID        a name for the row, unique. Also how Once is remembered.
#    Mode      the MatchModes.csv row it belongs to (intro, intro2).
#              Blank = any match.
#    When      the match moment: kick_off, duel_won, duel_lost, shot_taken,
#              goal_scored, goal_conceded, save_made, keeper_emptied,
#              foul_given, card_yellow, card_red, free_kick_won,
#              star_switch, play_maker
#    Requires  the condition language (flag:x  count:goals>=1). Blank = always.
#    Scene     a scene in Dialogue.csv. Its lines play in a box over the
#              pitch (match_talk_box.gd) while the match waits.
#    Once      true = the first time ever, then never again.
#
#  The first row that fits a moment plays; one box at a time.
# =============================================================

const FILE := "res://data/MatchTalk.csv"
const DONE_PREFIX := "match_talk_done_"

static var _rows: Array[Dictionary] = []
static var _loaded := false


static func reload() -> void:
	_loaded = false
	_load()


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_rows = []
	var dialogue := DialogueDB.get_db()
	var names := dialogue.scene_names()
	for row in MenuSupport.read_csv(FILE):
		var id_text := MenuSupport.field(row, "ID").strip_edges()
		var scene := MenuSupport.field(row, "Scene").strip_edges()
		if id_text == "" or scene == "":
			continue
		if not names.has(scene):
			print("[match talk] %s: Dialogue.csv has no scene called '%s' yet, so this row is skipped." % [id_text, scene])
		_rows.append({
			"id": id_text,
			"mode": CardDatabase._normalise(MenuSupport.field(row, "Mode")),
			"when": MenuSupport.field(row, "When").strip_edges().to_lower(),
			"requires": MenuSupport.field(row, "Requires").strip_edges(),
			"scene": scene,
			"once": ["true", "yes", "1"].has(MenuSupport.field(row, "Once").strip_edges().to_lower()),
		})


## The scene to play at this moment of a match in this mode, or "".
## Marks a Once row as done.
static func scene_for(event: String, mode_id: String, state: GameState) -> String:
	_load()
	var mode_key := CardDatabase._normalise(mode_id)
	var names := DialogueDB.get_db().scene_names()
	for row in _rows:
		if String(row["when"]) != event:
			continue
		if String(row["mode"]) != "" and String(row["mode"]) != mode_key:
			continue
		if not names.has(String(row["scene"])):
			continue
		if state != null:
			if bool(row["once"]) and state.has_flag(DONE_PREFIX + String(row["id"])):
				continue
			if not DialogueGrammar.test(String(row["requires"]), state):
				continue
			if bool(row["once"]):
				state.set_flag(DONE_PREFIX + String(row["id"]), true)
		return String(row["scene"])
	return ""
