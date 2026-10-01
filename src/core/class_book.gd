class_name ClassBook
extends RefCounted

# =============================================================
#  A CLASS, AN EMBLEM, AND THE TEAM SPIRIT — the shape of the whole game
#
#  ============ WHAT YOUR NEW SPREADSHEETS SAY ============
#
#  Unit_Set_Lorelei.csv and Unit_Set_Rauhnacht_Feuergeister.csv are not flat
#  lists of cards. Read the `Set Name` column and the structure falls out:
#
#      Lorelei
#        Set "Star"      3 cards, all Tier II      <- the three Star Players
#        Set "Sitri"     9 cards, Tiers I/III/IV   <- an EMBLEM SET
#        Set "Zepar"     9 cards, Tiers I/III/IV   <- an EMBLEM SET
#        Set "Sallos"    9 cards, Tiers I/III/IV   <- an EMBLEM SET
#
#  So a class is ONE STAR SET plus THREE EMBLEM SETS. The Star set holds one
#  tier between its three cards — that is the tier ladder rule the game has
#  always had — and each emblem set fills the other three tiers with nine
#  cards, three per tier, one of each rung.
#
#  And "<Class> Emblems.csv" names the emblems themselves. An emblem is a
#  TWO-SIDED CARD:
#
#      Basic Side     what it does from the moment you have it
#      Condition      what has to happen for it to turn over
#      Ultimate Side  what it does afterwards. The basic side stays live
#
#  ============ HOW THEY FIT TOGETHER ============
#
#      one Star Player        is tied to one emblem set
#      putting that Star      unlocks that emblem's nine units for
#      into a talent node     you to brew and field
#      all three Stars in     the class section of the tree opens, you choose
#      of the same class      ONE of its three Emblems, and you may forge the
#                             TEAM SPIRIT drink
#
#  That is why the Star set is three cards and the emblem sets are three: the
#  tree has three starting nodes and each one wants a Star.
#
#  ============ WHAT THIS FILE DOES AND DOES NOT DO ============
#
#  It READS the structure and it CHECKS it. It does not yet build a talent
#  tree, award an emblem or brew anything — those are the next phase, and
#  they will be built on top of this rather than instead of it.
#
#  What it gives you today:
#
#      classes()                every class it can see, with its sets
#      emblems_for("Lorelei")   the emblem cards for that class
#      set_for(emblem)          the nine units an emblem unlocks
#      trouble()                every way the four files disagree
#
#  The checking is the point. Three of the four files already disagree with
#  each other and there was no way to know — see tools/class_check.gd.
# =============================================================

## The name a Set Name column uses for the Star players. Not a tier and not
## an emblem: the three cards that go into the talent tree's starting nodes.
const STAR_SET := "star"


class EmblemSet extends RefCounted:
	## "Sitri", "Zepar" — matches an emblem's Name and a Set Name column.
	var id: String = ""
	var unit_type: String = ""
	var cards: Array[PlayerData] = []
	## Tier -> how many cards of that tier are in the set.
	var by_tier: Dictionary = {}


class Emblem extends RefCounted:
	var id: String = ""
	var unit_type: String = ""
	var art: String = ""
	var basic: String = ""
	var condition: String = ""
	## THE SAME CONDITION, IN THE LANGUAGE THE GAME READS.
	##
	## `condition` above is the prose that goes on the card — "If all three
	## Tier I Units that were removed to create Rose Token Units were
	## Lorelei" — which is exactly right for a player and impossible for a
	## program. So there is a second column, `Turns On`, holding the same idea
	## as `count:rose_lorelei>=3`, and THAT is what ClassTree tests.
	##
	## Two columns for one idea, on purpose. Empty means the emblem never
	## turns over, which is a perfectly good state for one you are still
	## writing — tools/class_tree_check.gd says so rather than complaining.
	var turns_on: String = ""
	var ultimate: String = ""
	var notes: String = ""

	# ============ THE FIVE COLUMNS THAT CAME WITH THE REWORK ============
	#
	# An Emblem is no longer bought in the talent tree. It ARRIVES WITH ITS
	# STAR: field the Star and the Emblem is on the bar along the top of the
	# pitch; take the Star out and the Emblem goes with them. These five are
	# what that needs.

	## Which Star Player carries it. Blank in the sheet means "the Star with
	## my name", which is how both files are written today.
	var star: String = ""

	## WHICH SET OF NINE CAN COMPLETE IT — and the column that closed a
	## complaint the checker made on every single run.
	##
	## The old code assumed a Star's name and its set's name were the same
	## word. Gremory's nine are the SITRI set, so it was reported as broken
	## when nothing was: the data was right and the assumption was wrong. A
	## Star and its set may share a name or not, and this column says which.
	var set_id: String = ""

	## THE SET'S OWN WORD — Rose Unit, Swan, Song counter, burn counter,
	## Teufel Mask. It is what the nine units of that set make and spend, and
	## it is the single thing that makes nine cards read as a set that belongs
	## together rather than nine cards that happen to share a class. The
	## workbench fills `{token}` with it when it rolls a unit's ability.
	var token: String = ""

	## `element` (the default), `class` or `any` — who may feed the BASIC
	## side. See EmblemBook.feeds_basic(); the Condition is always class-only
	## and no column can loosen that.
	var feeds: String = "element"

	## Left to right on the emblem bar.
	var order: int = 0


class ClassEntry extends RefCounted:
	var unit_type: String = ""
	## The three Star Players. They hold one tier between them.
	var stars: Array[PlayerData] = []
	var star_tier: String = ""
	## Set id -> EmblemSet. Three of them, in a finished class.
	var sets: Dictionary = {}
	## Emblem id -> Emblem, out of "<Class> Emblems.csv".
	##
	## EVERY EMBLEM IS IN HERE TWICE when its own name and its Star's name
	## differ — once under each — so a Star can find its Emblem whatever the
	## row is called. `aliases` below says which keys are the second name.
	var emblems: Dictionary = {}
	## The keys of `emblems` that are a Star's name rather than the emblem's
	## own. Anything COUNTING emblems skips these, or a class with three
	## emblems reports six.
	var aliases: Dictionary = {}


static var _classes: Dictionary = {}
static var _loaded := false


static func forget() -> void:
	_classes = {}
	_loaded = false
	# ClassInfo.csv is cached separately, so it has to be forgotten separately
	# — a tool that reloads the data and then asks for an element would
	# otherwise get the answer from before its own edit.
	_info = {}
	_info_loaded = false


# =============================================================
#  READING IT
# =============================================================

static func classes() -> Dictionary:
	if _loaded:
		return _classes
	_loaded = true
	_classes = {}

	# ---- the cards, grouped by class and then by Set Name ----
	var db := CardDatabase.get_db()
	if db != null:
		for card in db.players:
			var klass := card.unit_type.strip_edges()
			if klass == "":
				continue
			var entry: ClassEntry = _classes.get(CardDatabase._normalise(klass))
			if entry == null:
				entry = ClassEntry.new()
				entry.unit_type = klass
				_classes[CardDatabase._normalise(klass)] = entry

			var set_id := card.card_set.strip_edges()
			# A CARD MARKED Star IS A STAR whatever its Set Name says, and a
			# card in a set called "Star" is one too. Believing only the
			# column would miss a class whose sheet does not use it.
			if card.is_star() or CardDatabase._normalise(set_id) == STAR_SET:
				entry.stars.append(card)
				continue
			if set_id == "":
				continue
			var kit: EmblemSet = entry.sets.get(CardDatabase._normalise(set_id))
			if kit == null:
				kit = EmblemSet.new()
				kit.id = set_id
				kit.unit_type = klass
				entry.sets[CardDatabase._normalise(set_id)] = kit
			kit.cards.append(card)
			var tier := card.get_tier_clean()
			kit.by_tier[tier] = int(kit.by_tier.get(tier, 0)) + 1

	# ---- the tier the Stars hold between them ----
	for key in _classes:
		var entry: ClassEntry = _classes[key]
		var counts: Dictionary = {}
		for star in entry.stars:
			var tier := star.get_tier_clean()
			counts[tier] = int(counts.get(tier, 0)) + 1
		var best := ""
		var most := 0
		for tier in PlayerData.TIER_ORDER:
			if int(counts.get(tier, 0)) > most:
				most = int(counts[tier])
				best = tier
		entry.star_tier = best

	_read_emblems()
	return _classes


## Any file with Name, Unit Type and Basic Side columns is an emblem file,
## whatever it is called — the same rule every other loader in the game uses.
static func _read_emblems() -> void:
	var folder := DirAccess.open("res://data")
	if folder == null:
		return
	folder.list_dir_begin()
	var file_name := folder.get_next()
	while file_name != "":
		if not folder.current_is_dir() and file_name.to_lower().ends_with(".csv"):
			_read_emblem_file("res://data/%s" % file_name)
		file_name = folder.get_next()
	folder.list_dir_end()


static func _read_emblem_file(path: String) -> void:
	var rows := MenuSupport.read_csv(path)
	if rows.is_empty():
		return
	var first: Dictionary = rows[0]
	if not (first.has("basicside") and first.has("unittype") and first.has("name")):
		return

	var found := 0
	for row in rows:
		var badge := Emblem.new()
		badge.id = MenuSupport.field(row, "Name").strip_edges()
		if badge.id == "":
			continue
		badge.unit_type = MenuSupport.field(row, "Unit Type").strip_edges()
		badge.art = MenuSupport.field(row, "Emblem").strip_edges()
		badge.basic = MenuSupport.field(row, "Basic Side").strip_edges()
		badge.condition = MenuSupport.field(row, "Condition").strip_edges()
		badge.turns_on = MenuSupport.field(row, "Turns On").strip_edges()
		badge.ultimate = MenuSupport.field(row, "Ultimate Side").strip_edges()
		badge.notes = MenuSupport.field(row, "For AI notes").strip_edges()

		# ---- the rework's five ----
		#
		# A BLANK Star OR Set MEANS "THE ONE WITH MY NAME". That is the
		# ordinary case and it keeps the sheet short; the columns exist for
		# when they differ, which for Gremory they do.
		badge.star = MenuSupport.field(row, "Star").strip_edges()
		if badge.star == "":
			badge.star = badge.id
		badge.set_id = MenuSupport.field(row, "Set").strip_edges()
		if badge.set_id == "":
			badge.set_id = badge.id
		badge.token = MenuSupport.field(row, "Token").strip_edges()
		var feeds := MenuSupport.field(row, "Basic Feeds").strip_edges().to_lower()
		badge.feeds = feeds if feeds == "class" or feeds == "any" else "element"
		badge.order = MenuSupport.field_int(row, "Order", found + 1)

		var key := CardDatabase._normalise(badge.unit_type)
		var entry: ClassEntry = _classes.get(key)
		if entry == null:
			entry = ClassEntry.new()
			entry.unit_type = badge.unit_type
			_classes[key] = entry
		entry.emblems[CardDatabase._normalise(badge.id)] = badge

		# ============ AN EMBLEM IS ALSO FINDABLE BY ITS STAR ============
		#
		# Your emblem rows are called "Gremory's Emblem" and your Star is
		# called "Gremory". Both are right: one is the name of a thing on a
		# card and the other is the name of a person. The code used to need
		# them to be the same word, so a Star went looking for its Emblem and
		# found nothing — silently, which is the worst way for it to fail.
		#
		# So the same Emblem is filed under BOTH names. It is the same object
		# either way, so nothing is duplicated and nothing can drift, and
		# `aliases` remembers which keys are the second name so that anything
		# counting emblems does not count them twice.
		#
		# The upshot for you: name an emblem row whatever reads best on the
		# card. `Star` is the column that ties it to a player.
		var star_key := CardDatabase._normalise(badge.star)
		if star_key != "" and star_key != CardDatabase._normalise(badge.id):
			entry.emblems[star_key] = badge
			entry.aliases[star_key] = true

		found += 1
	if found > 0:
		print("[class] %d emblem(s) from %s" % [found, path.get_file()])


# =============================================================
#  ASKING IT THINGS
# =============================================================

static func entry_for(unit_type: String) -> ClassEntry:
	return classes().get(CardDatabase._normalise(unit_type))


static func emblems_for(unit_type: String) -> Array[Emblem]:
	var out: Array[Emblem] = []
	var entry := entry_for(unit_type)
	if entry == null:
		return out
	for key in entry.emblems:
		# SKIP THE SECOND NAME. Every emblem is filed under its own name and
		# under its Star's, so walking the whole dictionary would report a
		# class of three as a class of six.
		if entry.aliases.has(key):
			continue
		out.append(entry.emblems[key])
	return out


## The nine units an emblem answers for, or null if no set matches it.
##
## ============ IT ASKS THE EMBLEM WHICH SET IS ITS OWN ============
##
## It used to look the emblem's own NAME up in the set list, which quietly
## assumed a Star and its set share a word. Gremory's nine are the SITRI set,
## so that lookup failed and the checker reported a problem with nothing to
## fix. Now the emblem's `Set` column is asked, and it falls back to the name
## for the ordinary case where they do match.
static func set_for(unit_type: String, emblem_id: String) -> EmblemSet:
	var entry := entry_for(unit_type)
	if entry == null:
		return null
	var wanted := emblem_id
	var badge: Emblem = entry.emblems.get(CardDatabase._normalise(emblem_id))
	if badge != null and badge.set_id != "":
		wanted = badge.set_id
	return entry.sets.get(CardDatabase._normalise(wanted))


# =============================================================
#  ONE ROW OF ClassInfo.csv
#
#  ============ WHY IT MOVED HERE ============
#
#  Three different screens were each opening ClassInfo.csv and picking out
#  the row they wanted, which is three places for the same question and three
#  places to edit when a column is added. It is one place now, and the two
#  columns the rework added — `Element` and `Star Tier` — are read here.
#
#  ELEMENT IS THE IMPORTANT ONE. It is what a class shares with OTHER classes,
#  and the whole of "a water unit of any class feeds a Lorelei Emblem's Basic
#  side" hangs off it.
# =============================================================

static var _info: Dictionary = {}
static var _info_loaded := false


static func info_row(unit_type: String) -> Dictionary:
	if not _info_loaded:
		_info_loaded = true
		_info = {}
		for row in MenuSupport.read_csv("res://data/ClassInfo.csv"):
			var who := MenuSupport.field(row, "Class").strip_edges()
			if who == "":
				continue
			_info[CardDatabase._normalise(who)] = {
				"class": who,
				"name": MenuSupport.field(row, "Display Name", who).strip_edges(),
				"description": MenuSupport.field(row, "Description").strip_edges(),
				"element": MenuSupport.field(row, "Element").strip_edges(),
				"star_tier": MenuSupport.field(row, "Star Tier").strip_edges(),
				"banner": MenuSupport.field(row, "Banner Art").strip_edges(),
				"formation": MenuSupport.field(row, "Formation Art").strip_edges(),
				"requires": MenuSupport.field(row, "Requires").strip_edges(),
				"hidden": MenuSupport.field(row, "Hidden").strip_edges(),
			}
	return _info.get(CardDatabase._normalise(unit_type), {})


## A class's element, or "" — the one question EmblemBook asks most.
static func element_of(unit_type: String) -> String:
	return String(info_row(unit_type).get("element", ""))


## Every class that shares an element, including this one.
static func classes_of_element(element_text: String) -> Array[String]:
	var out: Array[String] = []
	if element_text.strip_edges() == "":
		return out
	info_row("")  # make sure the file is read
	for key in _info:
		if CardDatabase._normalise(String(_info[key]["element"])) == CardDatabase._normalise(element_text):
			out.append(String(_info[key]["class"]))
	out.sort()
	return out


# =============================================================
#  AND CHECKING IT
# =============================================================

## Everything wrong, in words. Empty means the four files agree.
##
## This is the whole reason the file exists today. A class is spread over two
## spreadsheets that have to line up — a Set Name in one has to be an emblem
## Name in the other — and nothing in the game could see that they did not.
## Things that are not wrong, only unwritten. See trouble() for the reason
## these are kept apart from the real findings.
static var _waiting: Array[String] = []


## Classes whose emblem file does not exist yet. Filled by trouble(), so call
## that first — class_check.gd does.
static func waiting() -> Array[String]:
	return _waiting


static func trouble() -> Array[String]:
	var out: Array[String] = []
	_waiting = []
	for key in classes():
		var entry: ClassEntry = classes()[key]
		var who := entry.unit_type

		# ---- the Stars ----
		if entry.stars.is_empty():
			out.append("%s: no Star Players. A class needs three, holding one tier between them." % who)
		elif entry.stars.size() != 3:
			out.append("%s: %d Star Player(s), not 3. The talent tree has three starting nodes and each one wants a Star."
				% [who, entry.stars.size()])
		var loose: Array[String] = []
		for star in entry.stars:
			if star.get_tier_clean() != entry.star_tier:
				loose.append("%s is Tier %s" % [star.player_name, star.get_tier_clean()])
		if not loose.is_empty():
			out.append("%s: the Stars should share one tier (Tier %s here), but %s."
				% [who, entry.star_tier, ", ".join(loose)])

		# ---- the emblem sets ----
		if entry.sets.is_empty() and entry.emblems.is_empty():
			continue

		# ============ A CLASS WITH NO EMBLEM FILE IS NOT A PROBLEM ============
		#
		# It is a class you have not got to yet, and there is a difference.
		# Asking a class with no '<name> Emblems.csv' for three matching emblem
		# sets produced four complaints per class about a file that does not
		# exist — which buried the ONE finding that was real (Lorelei's Sitri
		# against Gremory) under noise about work not yet started.
		#
		# So it says so once, in waiting() rather than here, and every
		# cross-check below is skipped. The moment you write the file, all of
		# them come back.
		if entry.emblems.is_empty():
			_waiting.append("%s: no '%s Emblems.csv' yet, so its %d unit set(s) are not checked against anything. Write the file and this becomes three real checks."
				% [who, who, entry.sets.size()])
			continue

		if entry.sets.size() != 3 and not entry.sets.is_empty():
			out.append("%s: %d emblem set(s) in the unit CSV, not 3. One per Star."
				% [who, entry.sets.size()])

		for set_key in entry.sets:
			var kit: EmblemSet = entry.sets[set_key]
			# THE LADDER, per set. Three cards in each tier the Stars do not
			# hold, one of each rung.
			for tier in PlayerData.TIER_ORDER:
				if tier == entry.star_tier:
					if int(kit.by_tier.get(tier, 0)) > 0:
						out.append("%s / set '%s': has a Tier %s card, but Tier %s belongs to the Stars."
							% [who, kit.id, tier, tier])
					continue
				var many := int(kit.by_tier.get(tier, 0))
				if many != 3:
					out.append("%s / set '%s': %d card(s) in Tier %s, not 3."
						% [who, kit.id, many, tier])

		# ============ IT ASKS THE Set COLUMN, NOT THE NAME ============
		#
		# This used to pair a set with an emblem BY NAME, which quietly
		# assumed a Star and its set share a word. Gremory's nine are the
		# SITRI set, so it reported two problems on every run — one for the
		# set with "no emblem" and one for the emblem with "no set" — and
		# there was nothing to fix. The data was right and the check was
		# wrong.
		#
		# An emblem's `Set` column names its set now, so the pairing is read
		# rather than guessed.
		var claimed := {}
		# EMBLEMS, NOT KEYS. Each one is filed under its own name and under
		# its Star's, so walking the dictionary reports every problem twice.
		for pairing in ClassBook.emblems_for(who):
			var mine := ClassBook.set_for(who, pairing.id)
			if mine == null:
				out.append("%s: emblem '%s' names the set '%s' and there is no set of that name in the unit CSV, so it unlocks nothing."
					% [who, pairing.id, pairing.set_id])
			else:
				claimed[CardDatabase._normalise(mine.id)] = true
		for set_key2 in entry.sets:
			if claimed.has(set_key2):
				continue
			var orphan: EmblemSet = entry.sets[set_key2]
			out.append("%s: unit set '%s' is named by no emblem's Set column, so nothing opens it."
				% [who, orphan.id])

		for badge in ClassBook.emblems_for(who):
			if badge.basic.strip_edges() == "":
				out.append("%s: emblem '%s' has an empty Basic Side." % [who, badge.id])
			if badge.condition.strip_edges() != "" and badge.ultimate.strip_edges() == "":
				out.append("%s: emblem '%s' has a Condition but no Ultimate Side to turn into."
					% [who, badge.id])
	return out
