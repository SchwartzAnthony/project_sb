extends SceneTree

# =============================================================
#  THE CLASS TREE, READ BACK TO YOU — AND WALKED
#
#  A class is spread over FOUR files that have to agree: the unit CSV (Set
#  Name), the "<Class> Emblems.csv" (Name), ClassTree.csv (the costs and the
#  Spirit Brew) and Brews.csv (the drink itself). Nothing but a tool can see
#  that they line up, and three of them already disagreed once.
#
#      godot --headless --script res://tools/class_tree_check.gd
#
#  WHAT IT DOES
#
#      1. every class's tree read back: its nodes, its emblems, its costs
#      2. THE FOUR-WAY CHECK — a Set Name with no emblem, an emblem with no
#         set, a Spirit Brew with no row in Brews.csv, and a brew whose
#         Requires does not ask for what the tree actually unlocks
#      3. WHICH EMBLEMS CAN NEVER TURN OVER — an emblem with no `Turns On`
#         is prose only. Not wrong; unwritten. It is listed apart
#      4. THE WALK — a new save, every node filled, an emblem chosen, the
#         spirit forged, and the points counted. This is where "the tree
#         costs 6 points and you have 4" turns up, before a player finds it
#
#  A tool, not part of the game. Nothing loads it.
# =============================================================


func _initialize() -> void:
	var problems := 0
	var db := CardDatabase.get_db()

	print("")
	print("=== The class tree ===")
	for problem in ClassTree.problems():
		print("  ! %s" % problem)
		problems += 1

	if db != null and not ClassTree.on(db):
		print("  NOTE: `class_tree` is false in Tuning.csv, so nothing below is")
		print("  reachable in the game right now.")
	if db != null and not ClassTree.gates_units(db):
		print("  NOTE: `class_tree_gates_units` is false, so the nine units of a")
		print("  set are yours whether or not its node has a Star in it. That is")
		print("  the safe setting while you are still writing the opening.")

	var brews := BrewDB.get_db()
	var trees := 0

	for key in ClassBook.classes():
		var entry: ClassBook.ClassEntry = ClassBook.classes()[key]
		var who := entry.unit_type
		if entry.stars.is_empty() or entry.sets.is_empty():
			continue
		trees += 1

		var costs := ClassTree.costs_for(who)
		print("")
		print("  %s" % who.to_upper())
		print("    %d Star(s), %d emblem set(s), %d emblem card(s)"
			% [entry.stars.size(), entry.sets.size(), entry.emblems.size()])
		print("    costs: node %d, emblem %d, spirit %d"
			% [int(costs["node"]), int(costs["emblem"]), int(costs["spirit"])])

		# ============ A CLASS WITH NO EMBLEM FILE IS NOT BROKEN ============
		#
		# It is unwritten, which is the ordinary state of a game being made.
		# BasicTeam and the Brandteufel both have Stars and one set each and
		# no "<Class> Emblems.csv" at all — reporting four problems for that
		# would be a tool crying wolf, and a tool that cries wolf gets
		# ignored on the day it is right.
		if entry.emblems.is_empty():
			print("    . no \"%s Emblems.csv\" yet, so this class has no emblems to check." % who)
			continue

		# ---- THE FOUR-WAY CHECK, half one: sets and emblems ----
		for set_key in entry.sets:
			var kit: ClassBook.EmblemSet = entry.sets[set_key]
			var badge: ClassBook.Emblem = entry.emblems.get(set_key)
			if badge == null:
				print("    ! set '%s' (%d cards) has no emblem of that name. A node with no emblem can be filled and then leads nowhere."
					% [kit.id, kit.cards.size()])
				problems += 1
			else:
				print("    node %-12s %2d units  ->  emblem %s"
					% [kit.id, kit.cards.size(), badge.id])
		for emblem_key in entry.emblems:
			if not entry.sets.has(emblem_key):
				var lonely: ClassBook.Emblem = entry.emblems[emblem_key]
				print("    ! emblem '%s' has no unit set of that name, so choosing it would open nothing."
					% lonely.id)
				problems += 1

		# ---- half two: the Team Spirit ----
		var brew_id := String(costs["brew"])
		if brew_id == "":
			print("    . no Spirit Brew named in ClassTree.csv — the Team Spirit cannot be forged for this class yet")
		elif brews == null:
			pass
		else:
			var row := brews.find(brew_id)
			if row.is_empty():
				print("    ! Spirit Brew '%s' is not a row of Brews.csv." % brew_id)
				problems += 1
			else:
				var wanted := ClassTree.spirit_unlock(who)
				var asks := String(row["requires"])
				if _squash(asks).find(_squash("unlocked:" + wanted)) < 0:
					print("    ! '%s' asks for `%s`, but forging unlocks `%s`. Those two have to be the same words or the drink never appears."
						% [brew_id, asks, wanted])
					problems += 1
				else:
					print("    spirit       %-12s <- unlocked:%s" % [brew_id, wanted])

	if trees == 0:
		print("")
		print("  No class has both Star Players and emblem sets, so there is no tree.")

	# ============ 3. THE EMBLEMS THAT CANNOT TURN OVER ============
	#
	# Apart from the problems on purpose. An emblem whose Condition is still
	# only prose is a card you have written and not yet wired, which is the
	# ordinary state of a game being made — not a mistake.
	print("")
	print("  === TURNING OVER ===")
	var prose_only := 0
	for key in ClassBook.classes():
		var entry: ClassBook.ClassEntry = ClassBook.classes()[key]
		for emblem_key in entry.emblems:
			var badge: ClassBook.Emblem = entry.emblems[emblem_key]
			if badge.turns_on == "":
				prose_only += 1
				continue
			var complaint := DialogueGrammar.complaints(badge.turns_on, false)
			if complaint.is_empty():
				print("  %-12s turns over when: %s"
					% [badge.id, DialogueGrammar.describe(badge.turns_on)])
			else:
				for line in complaint:
					print("  %-12s ! %s" % [badge.id, line])
					problems += 1
	if prose_only > 0:
		print("  %d emblem(s) have a Condition but no `Turns On`, so they can never" % prose_only)
		print("  turn over. That is prose waiting for a counter, not a mistake —")
		print("  write the condition in the `Turns On` column when the mechanic exists.")

	# ============ 4. THE WALK ============
	print("")
	print("  === THE WALK: a new save, every node filled ===")
	var state := GameState.new()
	for key in ClassBook.classes():
		var entry: ClassBook.ClassEntry = ClassBook.classes()[key]
		if entry.stars.is_empty() or entry.sets.is_empty():
			continue
		var who := entry.unit_type
		var costs := ClassTree.costs_for(who)
		var needed := entry.sets.size() * int(costs["node"]) \
			+ int(costs["emblem"]) + int(costs["spirit"])
		state.set_count(ClassTree.POINTS, needed)

		# WHAT THE GATE WOULD DO WITH NOTHING PLACED. Measured before a
		# single Star goes in, because "27 of 27 after" only means something
		# beside the number before it.
		var every_card: Array = []
		for set_key in entry.sets:
			every_card.append_array((entry.sets[set_key] as ClassBook.EmblemSet).cards)
		var before := ClassTree.gate_cards(every_card, state, db, true).size()

		var spent := 0
		for node in ClassTree.nodes_for(who, state):
			var free_star: PlayerData = null
			var taken := ClassTree.stars_placed(who, state)
			for star in ClassTree.stars_you_own(who, state, db):
				if not taken.has(ClassTree.star_key(star)):
					free_star = star
					break
			if free_star == null:
				print("  %s: ran out of Stars at the %s node — %d node(s), %d Star(s)."
					% [who, node["set_id"], entry.sets.size(), entry.stars.size()])
				problems += 1
				break
			var placed := ClassTree.place_star(who, String(node["set_id"]),
				free_star, state, db)
			if not bool(placed["ok"]):
				print("  %s: could not fill the %s node — %s"
					% [who, node["set_id"], placed["why"]])
				problems += 1
				break
			spent += int(costs["node"])

		if not ClassTree.all_placed(who, state):
			continue

		var first := ""
		for emblem_key in entry.emblems:
			first = (entry.emblems[emblem_key] as ClassBook.Emblem).id
			break
		if first != "":
			var chose := ClassTree.choose_emblem(who, first, state, db)
			if bool(chose["ok"]):
				spent += int(costs["emblem"])
			else:
				print("  %s: could not choose an emblem — %s" % [who, chose["why"]])
				problems += 1

		var forged := ClassTree.forge_spirit(who, state, db)
		if bool(forged["ok"]):
			spent += int(costs["spirit"])
		elif String(costs["brew"]) != "":
			print("  %s: could not forge the Team Spirit — %s" % [who, forged["why"]])
			problems += 1

		print("  %-26s THE WHOLE TREE COSTS %d POINT(S)." % [who + ":", spent])
		print("     three of a kind: %s   emblem: %s   spirit: %s" % [
			"yes" if state.has_flag(ClassTree.THREE_OF_A_KIND) else "NO",
			ClassTree.chosen_emblem(who, state),
			"forged" if ClassTree.spirit_forged(who, state) else "no"])

		# WHAT THE GATE WOULD DO. Asked with the gate forced on, because that
		# is the state this is all FOR — and with it off the answer is always
		# "everything", which tells you nothing.
		var after := ClassTree.gate_cards(every_card, state, db, true).size()
		print("     the gate: %d of %d set cards before, %d after." % [
			before, every_card.size(), after])

	print("")
	if problems == 0:
		print("=== ALL GOOD ===")
	else:
		print("=== %d PROBLEM(S) ===" % problems)
	quit(0)


func _squash(text: String) -> String:
	var out := ""
	for i in text.length():
		var c := text[i].to_lower()
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			out += c
	return out
