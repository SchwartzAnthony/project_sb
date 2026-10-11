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
#  ROUND AN - THE TUTORIAL (Anthony, 7 Oct) added four columns, all optional:
#
#    Round     only at this PLAY MAKER of the match (1 = the first). Blank = any.
#    Tier      only for this Tier (I, II, III, IV) - for the moments that have
#              one (cards_shown and the duel moments). Blank = any.
#    Highlight what the Head Coach points at while he talks: a gold box round
#              it (ring:word = a gold circle instead). Several with ;
#                card:first  card:last  card:<name>   a card being offered
#                cards                                every card offered
#                exhaust                              the EXHAUST ZONE button
#                keeper_chance  keeper_stamina  shot_power   (the shot window)
#    Do        what happens after his lines, with ; between:
#                pub:<scene>          TIME OUT - the match waits and the whole
#                                     screen becomes that Dialogue.csv scene
#                                     (the bar), then comes back exactly as it was
#                star:<name>          your player of that name becomes a Star
#                ability:<name>=<ID>  give him that Abilities.csv row, both sides
#                announce:<words>     the big words across the pitch
#
#  The tutorial's moments (When):
#    cards_shown          the cards of a Tier are on the table to choose from
#    duel_start           a duel window has turned over
#    duel_priority        "ABILITY PRIORITY" - the lower number ringed
#    duel_ability_1 / _2  the first / second ability box lights up
#    duel_power_check     "POWER CHECK" - both numbers ringed
#    duel_result          WIN / LOSE stamped
#    shot_odds            the shot window shows the % and the keeper's stamina
#    shot_done            the shot is over (goal or miss), before the restart
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
			"round": MenuSupport.field(row, "Round").strip_edges(),
			"tier": MenuSupport.field(row, "Tier").strip_edges().to_upper(),
			"highlight": MenuSupport.field(row, "Highlight").strip_edges(),
			"do": MenuSupport.field(row, "Do").strip_edges(),
		})


## ROUND AN: does any row for this mode and Play Maker teach a drink
## (Do drink_lesson)? The match greys every other bag button in it.
static func has_lesson(mode_id: String, play_maker: String) -> bool:
	_load()
	var mode_key := CardDatabase._normalise(mode_id)
	for row in _rows:
		if String(row["mode"]) != mode_key or String(row["round"]) != play_maker:
			continue
		if String(row["do"]).contains("drink_lesson:"):
			return true
	return false


## The scene to play at this moment of a match in this mode, or "".
## Marks a Once row as done.
static func scene_for(event: String, mode_id: String, state: GameState) -> String:
	return String(row_for(event, mode_id, state).get("scene", ""))


## ROUND AN: the whole row for this moment - scene, highlight, do - or {}.
## `facts` may carry "round" (the PLAY MAKER number) and "tier".
static func row_for(event: String, mode_id: String, state: GameState,
		facts: Dictionary = {}) -> Dictionary:
	_load()
	var mode_key := CardDatabase._normalise(mode_id)
	var names := DialogueDB.get_db().scene_names()
	for row in _rows:
		if String(row["when"]) != event:
			continue
		if String(row["mode"]) != "" and String(row["mode"]) != mode_key:
			continue
		if String(row["round"]) != "" and String(row["round"]) != str(facts.get("round", "")):
			continue
		if String(row["tier"]) != "" and String(row["tier"]) != String(facts.get("tier", "")).to_upper():
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
		return row
	return {}
