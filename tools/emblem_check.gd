extends SceneTree

# =============================================================
#  THE EMBLEMS, READ BACK — and the race priced in duels
#
#  ============ WHAT IT ANSWERS ============
#
#  Every other checker in this project prices a system in a unit you can feel.
#  This one prices THE RACE: how many duels it takes each Emblem to complete
#  its Condition, side by side, so you can see at a glance which of a class's
#  three is the one that always wins and which one nobody will ever finish.
#
#  That is the number that matters now. Three Emblems ride onto the pitch and
#  only the FIRST to complete turns over, so if Gremory needs three and Buer
#  needs eight, Buer's Ultimate does not exist — it is written, it is drawn,
#  and no player will ever see it.
#
#  ============ WHAT IT PRINTS ============
#
#      1. every class, its element, its Star tier, its three sets
#      2. every Emblem: its Star, its set, its token, who feeds it
#      3. THE RACE — duels to complete, and who wins
#      4. the element rule, worked through with a real card
#      5. everything that does not line up
#
#  godot --headless --script res://tools/emblem_check.gd
# =============================================================

const LINE := "  ────────────────────────────────────────────────────────────"


func _initialize() -> void:
	print("")
	print("=== THE EMBLEMS ===")
	print("")

	var db := CardDatabase.get_db()
	if db == null:
		print("  no card database — nothing to check.")
		quit()
		return

	_classes()
	_emblems()
	_race(db)
	_element_rule()
	_trouble()

	quit()


# =============================================================
#  1. THE CLASSES
# =============================================================

func _classes() -> void:
	print("  === THE CLASSES ===")
	print("  %-24s %-7s %-6s %s" % ["class", "element", "stars", "the three sets of nine"])
	print(LINE)
	for key in ClassBook.classes():
		var entry: ClassBook.ClassEntry = ClassBook.classes()[key]
		if entry.stars.is_empty() and entry.sets.is_empty():
			continue
		var info := ClassBook.info_row(entry.unit_type)
		var sets: Array[String] = []
		for set_key in entry.sets:
			var one: ClassBook.EmblemSet = entry.sets[set_key]
			sets.append("%s(%d)" % [one.id, one.cards.size()])
		sets.sort()
		print("  %-24s %-7s %-6s %s" % [
			entry.unit_type,
			String(info.get("element", "—")),
			"Tier " + entry.star_tier if entry.star_tier != "" else "—",
			", ".join(PackedStringArray(sets)) if not sets.is_empty() else "none",
		])
		# THE SHEET AND THE CARDS HAVE TO AGREE ABOUT THE STAR TIER. One is
		# what a screen shows before anything is loaded and the other is what
		# is really on the cards; a disagreement is invisible until a player
		# sees the wrong thing.
		var said := String(info.get("star_tier", ""))
		if said != "" and entry.star_tier != "" and said != entry.star_tier:
			print("      ClassInfo.csv says Star Tier %s and the cards are Tier %s."
				% [said, entry.star_tier])
	print("")


# =============================================================
#  2. THE EMBLEMS
# =============================================================

func _emblems() -> void:
	print("  === EVERY EMBLEM ===")
	print("  %-12s %-12s %-10s %-16s %s" % ["emblem", "star", "set", "token", "basic side feeds"])
	print(LINE)
	for key in ClassBook.classes():
		var entry: ClassBook.ClassEntry = ClassBook.classes()[key]
		for badge in EmblemBook.for_class(entry.unit_type):
			var nine := ClassBook.set_for(entry.unit_type, badge.id)
			var how := badge.feeds
			if how == "element":
				var element := ClassBook.element_of(entry.unit_type)
				how = "any %s unit" % element.to_lower() if element != "" else "its own class"
			elif how == "class":
				how = "%s only" % entry.unit_type
			else:
				how = "anybody"
			print("  %-12s %-12s %-10s %-16s %s" % [
				badge.id, badge.star,
				"%s(%d)" % [badge.set_id, nine.cards.size() if nine != null else 0],
				badge.token if badge.token != "" else "—",
				how,
			])
			# THE ONE LINE THAT USED TO BE A COMPLAINT AND IS NOW A FACT.
			if CardDatabase._normalise(badge.id) != CardDatabase._normalise(badge.set_id):
				print("      the Star is %s and the nine are the %s set — that is allowed, the Set column says so."
					% [badge.id, badge.set_id])
	print("")


# =============================================================
#  3. THE RACE — the number that decides which Ultimate exists
# =============================================================

func _race(db: CardDatabase) -> void:
	print("  === THE RACE ===")
	print("  Only the FIRST Emblem to complete turns over (`emblem_race`), and a")
	print("  goal puts every one of them back (`emblem_reset_on_goal`). So the")
	print("  Emblem with the SHORTEST condition is the only one most matches see.")
	print("")

	var racing := db.tune_bool("emblem_race", true)
	var on := db.tune_bool("emblems_on_field", true)
	print("  emblems_on_field %s   ·   emblem_race %s   ·   element feeds basic %s"
		% [str(on), str(racing), str(db.tune_bool("emblem_element_feeds_basic", true))])
	print("")

	for key in ClassBook.classes():
		var entry: ClassBook.ClassEntry = ClassBook.classes()[key]
		var badges := EmblemBook.for_class(entry.unit_type)
		if badges.is_empty():
			continue
		print("  %s" % entry.unit_type)
		print("  %-12s %-34s %s" % ["emblem", "counter it waits on", "needs"])
		var shortest := 999999
		var winner := ""
		var unfinishable: Array[String] = []
		for badge in badges:
			var found := _counter_in(badge.turns_on)
			if found.is_empty():
				print("  %-12s %-34s %s" % [badge.id, "—", "never turns over"])
				unfinishable.append(badge.id)
				continue
			var need := int(found["need"])
			print("  %-12s %-34s %d" % [badge.id, String(found["counter"]), need])
			if need < shortest:
				shortest = need
				winner = badge.id
		if winner != "":
			print("      SHORTEST: %s at %d. Unless a match is unusual, that is the" % [winner, shortest])
			print("      Ultimate a player sees — the others are written for a game")
			print("      that has already been decided.")
			var spread := 0
			for badge in badges:
				var found := _counter_in(badge.turns_on)
				if not found.is_empty():
					spread = maxi(spread, int(found["need"]) - shortest)
			if spread >= 3:
				print("      SPREAD IS %d. That is a lot: the longest condition is %d more"
					% [spread, spread])
				print("      than the shortest, so it will almost never be the one that wins.")
				print("      Bring them within one or two of each other, or give the long")
				print("      one a counter that ticks faster.")
			else:
				print("      Spread is %d — close enough that which one wins depends on how" % spread)
				print("      the match goes, which is what you want.")
		for one in unfinishable:
			print("      '%s' has no counter in Turns On, so it can never win the race." % one)
		print("")


func _counter_in(term: String) -> Dictionary:
	for part in term.split(";", false):
		var clean := String(part).strip_edges()
		if not clean.to_lower().begins_with("count:"):
			continue
		var body := clean.substr(clean.find(":") + 1)
		for mark in [">=", "==", ">", "="]:
			var at := body.find(mark)
			if at > 0:
				return {
					"counter": body.substr(0, at).strip_edges(),
					"need": int(body.substr(at + mark.length()).strip_edges()),
				}
	return {}


# =============================================================
#  4. THE ELEMENT RULE, WORKED THROUGH
# =============================================================

func _element_rule() -> void:
	print("  === ELEMENT FEEDS THE BASIC SIDE, CLASS FULFILS THE CONDITION ===")
	print("  The rule that makes the other water classes worth writing. Here it")
	print("  is with real cards rather than in the abstract.")
	print("")

	var db := CardDatabase.get_db()
	if db == null:
		return
	# One emblem, and one card of every class, so the two columns can be read
	# straight down rather than taken on trust.
	var badge: ClassBook.Emblem = null
	var owner_class := ""
	for key in ClassBook.classes():
		var entry: ClassBook.ClassEntry = ClassBook.classes()[key]
		var list := EmblemBook.for_class(entry.unit_type)
		if not list.is_empty():
			badge = list[0]
			owner_class = entry.unit_type
			break
	if badge == null:
		return

	print("  Emblem: %s (%s, %s)" % [badge.id, owner_class, ClassBook.element_of(owner_class)])
	print("  %-26s %-8s %-8s %s" % ["a card of…", "element", "basic?", "condition?"])
	print(LINE)
	var seen := {}
	# `db.players` IS ALREADY Array[PlayerData], so `card` comes out typed and
	# `var who := card.active_unit_type()` can be inferred. Iterating an
	# untyped array here is the mistake that has cost this project four
	# rounds — see THE TYPED-ARRAY RULE in the manual.
	for card in db.players:
		var who := card.active_unit_type()
		if who == "" or seen.has(who):
			continue
		seen[who] = true
		print("  %-26s %-8s %-8s %s" % [
			who,
			card.active_element(),
			"YES" if EmblemBook.feeds_basic(card, badge) else "no",
			"YES" if EmblemBook.feeds_condition(card, badge) else "no",
		])
	print("")
	print("  Read the two columns together. A class with YES/no is one you may")
	print("  splash in for the engine and which can never hand you the Ultimate.")
	print("  That is the whole trade, and it costs no code — it is the `Basic")
	print("  Feeds` column and the Element column of ClassInfo.csv.")
	print("")


# =============================================================
#  5. WHAT DOES NOT LINE UP
# =============================================================

func _trouble() -> void:
	var found := EmblemBook.problems()
	if found.is_empty():
		print("=== ALL GOOD ===")
		return
	print("=== %d PROBLEM(S) ===" % found.size())
	for one in found:
		print("  . %s" % one)
