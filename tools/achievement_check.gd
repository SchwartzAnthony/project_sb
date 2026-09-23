extends SceneTree

# =============================================================
#  ACHIEVEMENTS, READ BACK TO YOU
#
#  You said it plainly: "everything needs to be unlocked here first." That
#  makes `data/Achievements.csv` the root of the game, and it makes one
#  question worth asking every time you add content:
#
#      IS THIS THING REACHABLE AT ALL, or have I written a room that no
#      achievement ever opens?
#
#  That is the question a spreadsheet cannot answer for you and this tool
#  can. It also checks the other direction — an achievement that waits on a
#  counter nothing ever counts is an achievement nobody will ever earn.
#
#      godot --headless --script res://tools/achievement_check.gd
#
#  A tool, not part of the game. Nothing loads it.
# =============================================================

func _initialize() -> void:
	var problems := 0
	var db := CardDatabase.get_db()

	print("")
	print("=== Achievements.csv ===")
	for problem in AchievementBook.problems():
		print("  ! %s" % problem)
		problems += 1

	var rows := AchievementBook.rows()
	if rows.is_empty():
		print("  No achievements. Nothing in the game is gated behind one.")
		quit(0)
		return

	print("")
	print("  %-18s %-26s %s" % ["id", "needs", "hands over"])
	for row in rows:
		print("  %-18s %-26s %s%s" % [row["id"], row["needs"],
			", ".join(row["unlocks"]) if not row["unlocks"].is_empty() else "-",
			"   (hidden)" if bool(row["hidden"]) else ""])

	# ---- does anything count what they are waiting for? ----
	print("")
	print("  --- the counters they wait on ---")
	var counters := _counter_names()
	var missing := 0
	for row in rows:
		for wanted in _counters_in(String(row["needs"])):
			if counters.has(wanted):
				continue
			# A {placeholder} counter is made one-per-value at runtime, so
			# `goals_with_brew_fire` comes from the row `goals_with_brew_{brew}`.
			if _covered_by_a_pattern(wanted, counters):
				continue
			print("  ! '%s' waits on count:%s, and no row of Stats.csv makes that counter."
				% [row["id"], wanted])
			missing += 1
			problems += 1
	if missing == 0:
		print("  every counter they wait on is made by a row of Stats.csv.")

	# ---- is everything they hand over actually used? ----
	print("")
	print("  --- what they hand over ---")
	var granted := AchievementBook.everything_unlockable()
	var tested := _everything_tested()
	var idle := 0
	var tested_keys: Array[String] = []
	for thing in tested:
		tested_keys.append(_squash(thing))
	for thing in granted:
		if not tested_keys.has(_squash(thing)):
			print("  . '%s' is unlocked but nothing in any spreadsheet tests unlocked:%s yet."
				% [thing, thing])
			print("    (Not a mistake while you are building it — it is the room waiting for its door.)")
			idle += 1
	print("  %d unlocked, %d of them not tested by anything yet." % [granted.size(), idle])

	# ---- and the other direction, which is the dangerous one ----
	print("")
	print("  --- things that are tested but NOBODY grants ---")
	var orphan := 0
	var granted_keys: Array[String] = []
	for thing in granted:
		granted_keys.append(_squash(thing))
	for thing in tested:
		if granted_keys.has(_squash(thing)) or _granted_elsewhere(thing):
			continue
		print("  ! unlocked:%s is tested somewhere, but no achievement and no" % thing)
		print("    Progression row ever grants it. That content can never appear.")
		orphan += 1
		problems += 1
	if orphan == 0:
		print("  everything that is tested is granted by something.")

	print("")
	print("=== %s ===" % ("ALL GOOD" if problems == 0 else "%d thing(s) to look at" % problems))
	print("")
	quit(0)


## Every counter name Stats.csv makes.
func _counter_names() -> Array[String]:
	var out: Array[String] = []
	for row in MenuSupport.read_csv("res://data/Stats.csv"):
		var name_text := MenuSupport.field(row, "Counter").strip_edges()
		if name_text != "":
			out.append(name_text)
	return out


## A counter made one-per-value, like `goals_with_brew_{brew}`, covers
## `goals_with_brew_fire`.
func _covered_by_a_pattern(wanted: String, counters: Array[String]) -> bool:
	for pattern in counters:
		if not pattern.contains("{"):
			continue
		var head := pattern.substr(0, pattern.find("{"))
		if head != "" and wanted.begins_with(head):
			return true
	return false


## The `count:name>=n` terms inside a condition.
func _counters_in(condition: String) -> Array[String]:
	var out: Array[String] = []
	for piece in condition.split(";", false):
		var term := String(piece).strip_edges()
		if not term.to_lower().begins_with("count:"):
			continue
		var rest := term.substr(6)
		for sign_text in [">=", "<=", ">", "<", "=="]:
			var at := rest.find(sign_text)
			if at > 0:
				rest = rest.substr(0, at)
				break
		var clean := rest.strip_edges()
		if clean != "" and not out.has(clean):
			out.append(clean)
	return out


## Every `unlocked:X` written in a CONDITION COLUMN of any spreadsheet.
##
## THE COLUMNS, NOT THE WHOLE FILE. The first version scanned the raw text
## and picked up half a dozen sentences out of Notes columns — including one
## that read "unlocked:fast forward here and hand that unlock out with a
## talent". A checker that reports prose as a finding is a checker you learn
## to ignore.
const CONDITION_COLUMNS: Array[String] = [
	"Requires", "Needs", "When", "Condition", "Unlocked By", "Do", "Reward",
]

func _everything_tested() -> Array[String]:
	var out: Array[String] = []
	var folder := DirAccess.open("res://data")
	if folder == null:
		return out
	folder.list_dir_begin()
	var file_name := folder.get_next()
	while file_name != "":
		if file_name.to_lower().ends_with(".csv"):
			for row in MenuSupport.read_csv("res://data/" + file_name):
				for column in CONDITION_COLUMNS:
					for thing in _unlocks_in(MenuSupport.field(row, column)):
						if not out.has(thing):
							out.append(thing)
		file_name = folder.get_next()
	folder.list_dir_end()
	return out


## The `unlocked:Name` terms inside one condition.
func _unlocks_in(condition: String) -> Array[String]:
	var out: Array[String] = []
	for piece in condition.split(";", false):
		var term := String(piece).strip_edges()
		var low := term.to_lower()
		if low.begins_with("!unlocked:"):
			term = term.substr(10)
		elif low.begins_with("unlocked:"):
			term = term.substr(9)
		else:
			continue
		var clean := term.strip_edges().to_lower()
		if clean != "" and not out.has(clean):
			out.append(clean)
	return out


## ============ THE GAME'S OWN RULE FOR MATCHING A NAME ============
##
## I nearly shipped a check that reported `Master Brewer` and `master_brewer`
## as two different unlocks that would never both be granted. Then I read
## GameState._key(): it lowercases and throws away everything that is not a
## letter or a digit. **They are the same unlock.** Spelling, spacing,
## capitals and punctuation do not matter anywhere in the unlock vocabulary.
##
## So this is a copy of that rule, and it is used on BOTH sides of every
## comparison below — which is what stopped this tool reporting sixteen
## problems that did not exist.
func _squash(text: String) -> String:
	var out := ""
	for i in text.length():
		var c := text[i]
		if c.to_lower() != c.to_upper() or c.is_valid_int():
			out += c.to_lower()
	return out


## Progression.csv and the base can grant unlocks too — an achievement is not
## the only door, it is only meant to be the first one.
func _granted_elsewhere(thing: String) -> bool:
	for path in ["res://data/Progression.csv", "res://data/Buildings.csv",
			"res://data/Season.csv", "res://data/Bounties.csv", "res://data/Talents.csv"]:
		if not FileAccess.file_exists(path):
			continue
		var handle := FileAccess.open(path, FileAccess.READ)
		if handle == null:
			continue
		handle.close()
		# The same loose matching the game uses, so `unlock:Master Brewer`
		# here answers a `unlocked:master_brewer` there.
		for row in MenuSupport.read_csv(path):
			for column in ["Do", "Reward", "Action", "Effect", "Grants"]:
				for piece in MenuSupport.field(row, column).split(";", false):
					var term := String(piece).strip_edges()
					if term.to_lower().begins_with("unlock:") \
							and _squash(term.substr(7)) == _squash(thing):
						return true
	return false
