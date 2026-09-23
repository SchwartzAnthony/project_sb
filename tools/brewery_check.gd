extends SceneTree

# =============================================================
#  THE BREWERY CHAIN, WALKED END TO END
#
#  A production chain is a thing you get wrong in the numbers. Every cell can
#  be spelled correctly and the map can still be impossible to start, or a
#  starting stock can be worth two bottles when you meant it to be worth
#  twenty. Neither of those is visible in a spreadsheet, and both of them are
#  visible here.
#
#      godot --headless --script res://tools/brewery_check.gd
#
#  WHAT IT DOES
#
#      1. every problem BreweryBook can see in the two spreadsheets
#      2. the six sections read back as a chain, in order
#      3. THE WALK — it starts a new game, opens every section, and works
#         them in order over and over until it runs out of something. Then it
#         tells you how many bottles that was, and WHAT RAN OUT FIRST, which
#         is the only number in this file worth tuning against
#      4. which achievement opens each section — because a section nothing
#         unlocks is a building you can never walk into
#
#  A tool, not part of the game. Nothing loads it.
# =============================================================

const TURNS := 60


func _initialize() -> void:
	var problems := 0

	print("")
	print("=== The Brewery ===")
	for problem in BreweryBook.problems():
		print("  ! %s" % problem)
		problems += 1

	var sections := BreweryBook.sections()
	if sections.is_empty():
		print("  No sections. The Brewery map has nothing on it.")
		quit(0)
		return

	# ============ 1. THE CHAIN, READ BACK ============
	print("")
	for one in sections:
		var takes: Array[String] = []
		for id_text in one["takes"]:
			var res := BreweryBook.resource(String(id_text))
			var name_text := String(res["name"]) if not res.is_empty() else String(id_text)
			var many := int(one["takes"][id_text])
			if not res.is_empty() and bool(res["kept"]):
				name_text += " (kept)"
			takes.append(name_text if many == 1 else "%d %s" % [many, name_text])
		var made := BreweryBook.resource(String(one["makes"]))
		var made_text := String(made["name"]) if not made.is_empty() else String(one["makes"])
		if int(one["how_many"]) > 1:
			made_text = "%d %s" % [int(one["how_many"]), made_text]
		var wait_text := ""
		if int(one["wait_max"]) > 0:
			wait_text = "   (lagers %d-%d turn(s))" % [int(one["wait_min"]), int(one["wait_max"])]
		print("  %d  %-22s %-12s %s  ->  %s%s" % [
			int(one["order"]), one["name"], one["worker"],
			", ".join(takes), made_text, wait_text])
		print("     opens on: %s" % one["needs"])

	# ============ 2. WHO OPENS IT ============
	#
	# The one question that cannot be answered from inside this file. Every
	# section is unlocked, and something has to do the unlocking — see
	# achievement_book.gd, and tools/achievement_check.gd for the other half.
	print("")
	print("  === WHO OPENS EACH SECTION ===")
	for one in sections:
		var needs := String(one["needs"])
		var wanted := _unlocks_named(needs)
		if wanted.is_empty():
			print("  %-22s needs '%s' — not an unlock, so nothing is checked here"
				% [one["name"], needs])
			continue
		for thing in wanted:
			var by := _who_grants(thing)
			if by == "":
				print("  %-22s ! NOTHING UNLOCKS '%s'. This section can never be opened."
					% [one["name"], thing])
				problems += 1
			else:
				print("  %-22s <- %s" % [one["name"], by])

	# ============ 3. THE WALK ============
	#
	# The number that matters. A fresh save, every section open, and the chain
	# worked in order until something runs dry.
	print("")
	print("  === THE WALK: a new game, every section open ===")
	var state := GameState.new()
	BreweryBook.stock_a_new_game(state)
	for one in sections:
		for thing in _unlocks_named(String(one["needs"])):
			state.unlock(thing)

	var start_line: Array[String] = []
	for res in BreweryBook.resources():
		if int(res["start"]) > 0:
			start_line.append("%s %d" % [res["name"], int(res["start"])])
	print("  Starting stock: %s" % ", ".join(start_line))
	print("")

	var made_count: Dictionary = {}
	var ran_dry := ""
	var turns_used := 0
	for turn in TURNS:
		turns_used = turn + 1
		var did_anything := false
		for one in sections:
			var id_text := String(one["id"])
			# Work it as many times as it can go this turn.
			for _again in 20:
				if not BreweryBook.can_work(id_text, state):
					break
				var result := BreweryBook.work(id_text, state)
				if not bool(result["ok"]):
					break
				did_anything = true
				var makes := String(result["made"])
				made_count[makes] = int(made_count.get(makes, 0)) + int(result["many"])
		# WHAT CAME OUT OF THE CELLAR COUNTS AS SOMETHING HAPPENING. Without
		# this the walk stops on the very turn a barrel finishes lagering and
		# under-reports the stock by a whole cycle — which it did, and the
		# number it printed was six bottles instead of twenty-four.
		var released := BreweryBook.advance_turn(state)
		if not released.is_empty():
			did_anything = true
		if not did_anything and not _anything_lagering(state, sections):
			# Nothing can be worked and nothing is in the cellar — this is
			# where the chain stops, so say what stopped it.
			ran_dry = _what_stopped_it(state, sections)
			break

	print("  After %d turn(s) it made:" % turns_used)
	for one in sections:
		var makes := String(one["makes"])
		var res := BreweryBook.resource(makes)
		var name_text := String(res["name"]) if not res.is_empty() else makes
		print("     %-10s %d" % [name_text, int(made_count.get(makes, 0))])

	print("")
	var bottles := 0
	for one in sections:
		if int(one["order"]) == sections.size():
			bottles = int(made_count.get(String(one["makes"]), 0))
	print("  THE STARTING STOCK IS WORTH %d BOTTLE(S)." % bottles)
	if ran_dry != "":
		print("  It stopped because it ran out of: %s" % ran_dry)
	else:
		print("  It was still going after %d turns — raise TURNS if you want the whole of it." % TURNS)

	print("")
	print("  What is left over:")
	for res in BreweryBook.resources():
		var have := BreweryBook.stock(String(res["id"]), state)
		if have > 0:
			print("     %-10s %d" % [res["name"], have])

	print("")
	if problems == 0:
		print("=== ALL GOOD ===")
	else:
		print("=== %d PROBLEM(S) ===" % problems)
	quit(0)


# =============================================================
#  SMALL THINGS
# =============================================================

## The names inside a condition like "unlocked:Malthouse;unlocked:Mill".
func _unlocks_named(needs: String) -> Array[String]:
	var out: Array[String] = []
	for part in needs.split(";", false):
		var clean := String(part).strip_edges()
		if clean.to_lower().begins_with("unlocked:"):
			var thing := clean.substr(clean.find(":") + 1).strip_edges()
			if thing != "":
				out.append(thing)
	return out


## Which achievement hands this one out, or "" for nobody.
##
## Compared the way GameState compares unlock names — lowercase, letters and
## digits only — so `Master Brewer`, `master_brewer` and `master brewer` are
## one unlock rather than three. Getting this wrong is what made the
## achievement checker report sixteen problems that were not problems.
func _who_grants(thing: String) -> String:
	var want := _squash(thing)
	for row in AchievementBook.rows():
		for handed in row["unlocks"]:
			if _squash(String(handed)) == want:
				return String(row["name"])
	return ""


func _squash(text: String) -> String:
	var out := ""
	for i in text.length():
		var c := text[i].to_lower()
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			out += c
	return out


func _anything_lagering(state: GameState, sections: Array) -> bool:
	for one in sections:
		if BreweryBook.is_waiting(String(one["id"]), state):
			return true
	return false


## The first section that is open and idle, and what it is short of. That is
## the bottleneck, and it is almost never the one you expect.
func _what_stopped_it(state: GameState, sections: Array) -> String:
	for one in sections:
		var short := BreweryBook.missing(String(one["id"]), state)
		if not short.is_empty():
			return "%s at the %s" % [", ".join(short), one["name"]]
	return "nothing obvious"
