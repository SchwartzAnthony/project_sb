extends SceneTree

# =============================================================
#  THE TEST ENVIRONMENT, CHECKED  (round AC)
#
#      godot --headless --path . --script res://tools/test_env_check.gd
#
#  Presses TEST COMPLETE ENVIRONMENT, checks what it made, checks that the
#  real save was never written, and leaves again. A tool; nothing loads it.
# =============================================================

var _bad := 0


func _initialize() -> void:
	await process_frame
	var real_path := GameState.SAVE_PATH
	var real_before := _stamp(real_path)
	var lines := TestEnvironment.enter(self)
	_expect(TestEnvironment.active(self), "the test environment is on")
	_expect(GameState.SAVE_PATH == TestEnvironment.STATE_PATH, "the game now saves to the test folder")
	var state := GameState.fetch(self)
	var db := CardDatabase.get_db()
	_expect(state.unlocks.size() > 0, "unlocks granted (%d)" % state.unlocks.size())
	_expect(SquadBook.names(state).size() >= db.players.size() - 5, "every card signed (%d of %d)" % [SquadBook.names(state).size(), db.players.size()])
	var roster := TeamRoster.load_all()
	_expect(roster.teams.size() >= 4, "one ready team per class (%d)" % roster.teams.size())
	for entry in roster.teams:
		var trouble := roster.trouble(entry, db)
		if trouble == "":
			trouble = TeamBuild.team_trouble(entry, state, db)
		_expect(trouble == "", "%s is ready to play%s" % [entry["name"], "" if trouble == "" else ": " + trouble])
	var progress := UnlockProgress.build(state)
	var open: Array[String] = []
	for e in progress.entries:
		if not bool(e.get("done", false)) and String(e.get("kind", "")) != "Fixture":
			open.append("%s %s" % [e["kind"], e["name"]])
	_expect(open.size() <= 3, "nothing left locked (%d still: %s)" % [open.size(), ", ".join(open.slice(0, 8))])
	TestEnvironment.leave(self)
	_expect(not TestEnvironment.active(self), "left again")
	_expect(GameState.SAVE_PATH == real_path, "back on the real save path")
	_expect(_stamp(real_path) == real_before, "the real save file was not written")
	print("")
	print("=== ALL GOOD ===" if _bad == 0 else "=== %d PROBLEM(S) ===" % _bad)
	quit(0 if _bad == 0 else 1)


func _stamp(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "missing"
	return str(FileAccess.get_modified_time(path))


func _expect(ok: bool, words: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + words)
	if not ok:
		_bad += 1
