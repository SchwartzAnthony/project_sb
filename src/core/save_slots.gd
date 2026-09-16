class_name SaveSlots
extends RefCounted

# =============================================================
#  THREE SAVES INSTEAD OF ONE
#
#  Until now the game had exactly one save, at user://story_state.json. Now
#  it has as many as `slot_count` in Tuning.csv says — three out of the box —
#  and the title screen asks which one before it starts.
#
#  ============ WHAT A SLOT IS ============
#
#  A folder's worth of files with the slot's number on them:
#
#      user://slot2/story_state.json    your progress
#      user://slot2/teams.json          the teams you have built
#
#  Slot 1 keeps the OLD paths — user://story_state.json and user://teams.json
#  — so a save made before slots existed is slot 1 and is not lost. That is
#  the whole reason it is done this way round.
#
#  ============ HOW IT WORKS ============
#
#  GameState and TeamRoster both read a `static var` for their path. Choosing
#  a slot writes those two variables and forgets whatever was loaded, so the
#  next read comes off the new slot. The same trick the tutorial base uses,
#  and for the same reason: one value, changed in one place, and nothing
#  downstream had to learn about it.
#
#  Settings are NOT per slot. The language, the keys, the volume and the
#  palette are things about YOU, not about a playthrough, so they stay in
#  user://settings.json and are shared.
# =============================================================

const CHOSEN := "cw_save_slot"
const REAL_STATE := "user://story_state.json"
const REAL_TEAMS := "user://teams.json"


## How many slots the title screen offers.
static func count() -> int:
	return clampi(CardDatabase.get_db().tune_int("slot_count", 3), 1, 9)


## Which slot is being played. 1 until something says otherwise.
static func current(tree: SceneTree) -> int:
	if tree == null or not tree.has_meta(CHOSEN):
		return 1
	return int(tree.get_meta(CHOSEN))


# =============================================================
#  THE PATHS
# =============================================================

## SLOT 1 IS THE OLD PATHS. See the header — this is what stops an existing
## save disappearing the day slots are added.
static func state_path(slot: int) -> String:
	if slot <= 1:
		return REAL_STATE
	return "user://slot%d/story_state.json" % slot


static func teams_path(slot: int) -> String:
	if slot <= 1:
		return REAL_TEAMS
	return "user://slot%d/teams.json" % slot


# =============================================================
#  CHOOSING ONE
# =============================================================

## Play this slot from now on. Everything already in memory is dropped, so
## the next screen reads the new slot rather than the old one's leftovers.
static func choose(tree: SceneTree, slot: int) -> void:
	if tree == null:
		return
	slot = clampi(slot, 1, count())
	tree.set_meta(CHOSEN, slot)

	if slot > 1:
		DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path("user://slot%d" % slot))

	GameState.SAVE_PATH = state_path(slot)
	TeamRoster.SAVE_PATH = teams_path(slot)

	GameState.forget(tree)
	TeamSelection.clear(tree)
	ScenePaths.clear_trail(tree)

	print("[slots] Playing slot %d." % slot)
	print("        Progress: %s" % ProjectSettings.globalize_path(GameState.SAVE_PATH))


# =============================================================
#  WHAT IS IN A SLOT
# =============================================================

## A line for the title screen: "Slot 2 — 14 matches, 6 unlocks" or
## "Slot 3 — empty".
static func describe(slot: int) -> Dictionary:
	var path := state_path(slot)
	if not FileAccess.file_exists(path):
		return {"slot": slot, "used": false, "line": "Empty", "when": ""}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"slot": slot, "used": false, "line": "Empty", "when": ""}
	var raw := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		return {"slot": slot, "used": true, "line": "Unreadable", "when": ""}

	var data: Dictionary = parsed
	var counters: Dictionary = data.get("counters", {})
	var unlocks: Array = data.get("unlocks", [])
	var played := int(counters.get("matchesplayed",
		counters.get("matches_played", 0)))

	# WHEN IT WAS LAST TOUCHED, from the file itself rather than from
	# anything we have to remember to write.
	var when := ""
	var stamp := FileAccess.get_modified_time(path)
	if stamp > 0:
		var at := Time.get_datetime_dict_from_unix_time(stamp)
		when = "%04d-%02d-%02d  %02d:%02d" % [
			at["year"], at["month"], at["day"], at["hour"], at["minute"]]

	return {
		"slot": slot,
		"used": true,
		"line": "%d match%s   ·   %d unlock%s" % [
			played, "" if played == 1 else "es",
			unlocks.size(), "" if unlocks.size() == 1 else "s"],
		"when": when,
	}


## Wipe a slot. The player is asked twice by the screen before this is
## called — there is no undo.
static func erase(slot: int) -> void:
	for path in [state_path(slot), teams_path(slot)]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("[slots] Slot %d cleared." % slot)
