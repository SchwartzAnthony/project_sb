class_name TeamBuild
extends RefCounted

# =============================================================
#  TEAM BUILD — the gate in front of the Pub and every match (round Y)
#
#  ============ WHAT YOU ASKED FOR ============
#
#  "A team has to be made before entering a pub, so if they have 0 teams they
#   have to make one first... They also need to add the three star players to
#   their talent tree before they can enter the pub or start a match. These
#   are mandatory players and dictate their build entirely."
#
#  And your answers: a team is TWELVE - three Stars plus nine - because that
#  is exactly who takes the field; and the Stars decide which set cards you
#  may pick (class_tree_gates_units is on).
#
#  ============ THE RULE, IN ONE SENTENCE ============
#
#  You are READY when at least one saved team is complete (12 of 12, a whole
#  ladder) AND every node of that team's class in the Star Hall has a Star
#  standing in it.
#
#  Until then the Pub door and the two match buttons on the base open TEAM
#  BUILD instead, with a line saying what is missing. Adventure is NOT gated -
#  you said Adventure comes later.
#
#  ============ THE TWO THINGS THAT WOULD HAVE LOCKED A NEW GAME ============
#
#      Stars cost talent points, and talent points come from matches.
#          -> `team_build_free_stars` (Tuning.csv, 3): the first three Stars
#             you ever place cost nothing.
#      The Talent Tree building only appeared after an unlock.
#          -> Team Build has no Requires. The TALENTS tab inside it still
#             waits for `unlocked:Talent Tree`, exactly as the building did.
#
#  `team_build_gate` FALSE in Tuning.csv switches all of it off.
# =============================================================

const TEAM_SIZE := 12


static func on(db: CardDatabase) -> bool:
	return db == null or db.tune_bool("team_build_gate", true)


## The players a saved team puts out: its Stars' whole tier plus the nine.
static func team_count(entry: Dictionary) -> int:
	if entry.is_empty():
		return 0
	var many := 3                      # the Stars always hold their tier
	var cards: Dictionary = entry.get("cards", {})
	for tier in cards.keys():
		if String(tier) == String(entry.get("star_tier", "")):
			continue
		many += mini(3, (cards[tier] as Array).size())
	return mini(many, TEAM_SIZE)


## "" when every node of this class has a Star, otherwise the sentence.
static func stars_trouble(unit_type: String, state: GameState) -> String:
	var nodes := ClassTree.nodes_for(unit_type, state)
	if nodes.is_empty():
		return ""                      # a class with no tree has nothing to place
	var placed := 0
	for node in nodes:
		if bool(node["filled"]):
			placed += 1
	if placed >= nodes.size():
		return ""
	return "place your %s Stars in the Star Hall (%d of %d)" % [unit_type, placed, nodes.size()]


## Everything a screen needs to say where you are.
##     ok        may you go to the Pub / take the pitch
##     why       the sentence when you may not
##     team      the best team you have ("" if none)
##     players   how many of 12 that team has
##     stars     placed / of, for that team's class
static func status(state: GameState, db: CardDatabase) -> Dictionary:
	var out := {"ok": true, "why": "", "team": "", "players": 0, "stars": 0, "of": 3, "class": ""}
	if not on(db) or state == null:
		return out
	var book := TeamRoster.load_all()
	var best: Dictionary = {}
	var best_score := -1
	for entry in book.teams:
		var count := team_count(entry)
		var nodes := ClassTree.nodes_for(String(entry["class"]), state)
		var placed := 0
		for node in nodes:
			if bool(node["filled"]):
				placed += 1
		var score := count * 10 + placed
		if book.trouble(entry, db) == "" and stars_trouble(String(entry["class"]), state) == "":
			score += 1000              # a team that is actually ready always wins
		if score > best_score:
			best_score = score
			best = entry
			out["players"] = count if book.trouble(entry, db) != "" else TEAM_SIZE
			out["stars"] = placed
			out["of"] = maxi(1, nodes.size())
	if best.is_empty():
		# NO TEAM YET: report the class whose Star Hall is furthest along,
		# because the Stars come first - they open the units a team is made of.
		for unit_type in db.stars_by_class().keys():
			var nodes2 := ClassTree.nodes_for(String(unit_type), state)
			var placed2 := 0
			for node in nodes2:
				if bool(node["filled"]):
					placed2 += 1
			if placed2 > int(out["stars"]) and not nodes2.is_empty():
				out["stars"] = placed2
				out["of"] = nodes2.size()
				out["class"] = String(unit_type)
		out["ok"] = false
		out["why"] = ("Place your three Stars in the Star Hall, then build a team of %d." % TEAM_SIZE) \
			if int(out["stars"]) < int(out["of"]) \
			else ("Build a team of %d - your %s Stars and nine more." % [TEAM_SIZE, out["class"]])
		return out
	out["team"] = String(best["name"])
	out["class"] = String(best["class"])
	var gaps: Array[String] = []
	var short := book.trouble(best, db)
	if short != "":
		gaps.append("finish %s (%d of %d): %s" % [best["name"], out["players"], TEAM_SIZE, short])
	var stars := stars_trouble(String(best["class"]), state)
	if stars != "":
		gaps.append(stars)
	if not gaps.is_empty():
		out["ok"] = false
		out["why"] = "Team Build first: " + "; and ".join(gaps) + "."
	return out


static func ready(state: GameState, db: CardDatabase) -> bool:
	return bool(status(state, db)["ok"])


## For one team, before it takes the pitch. "" = it may.
static func team_trouble(entry: Dictionary, state: GameState, db: CardDatabase) -> String:
	if not on(db) or entry.is_empty():
		return ""
	return stars_trouble(String(entry["class"]), state)


## Which tab a player who was turned away should land on.
static func tab_for(state: GameState, db: CardDatabase) -> String:
	var now := status(state, db)
	return "Your Teams" if int(now["stars"]) >= int(now["of"]) else "Star Hall"
