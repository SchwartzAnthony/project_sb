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
	var ultimate: String = ""
	var notes: String = ""


class ClassEntry extends RefCounted:
	var unit_type: String = ""
	## The three Star Players. They hold one tier between them.
	var stars: Array[PlayerData] = []
	var star_tier: String = ""
	## Set id -> EmblemSet. Three of them, in a finished class.
	var sets: Dictionary = {}
	## Emblem id -> Emblem, out of "<Class> Emblems.csv".
	var emblems: Dictionary = {}


static var _classes: Dictionary = {}
static var _loaded := false


static func forget() -> void:
	_classes = {}
	_loaded = false


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
		badge.ultimate = MenuSupport.field(row, "Ultimate Side").strip_edges()
		badge.notes = MenuSupport.field(row, "For AI notes").strip_edges()

		var key := CardDatabase._normalise(badge.unit_type)
		var entry: ClassEntry = _classes.get(key)
		if entry == null:
			entry = ClassEntry.new()
			entry.unit_type = badge.unit_type
			_classes[key] = entry
		entry.emblems[CardDatabase._normalise(badge.id)] = badge
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
		out.append(entry.emblems[key])
	return out


## The nine units an emblem unlocks, or an empty set if no set matches it.
static func set_for(unit_type: String, emblem_id: String) -> EmblemSet:
	var entry := entry_for(unit_type)
	if entry == null:
		return null
	return entry.sets.get(CardDatabase._normalise(emblem_id))


# =============================================================
#  AND CHECKING IT
# =============================================================

## Everything wrong, in words. Empty means the four files agree.
##
## This is the whole reason the file exists today. A class is spread over two
## spreadsheets that have to line up — a Set Name in one has to be an emblem
## Name in the other — and nothing in the game could see that they did not.
static func trouble() -> Array[String]:
	var out: Array[String] = []
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

			# ---- and does an emblem of that name exist ----
			if not entry.emblems.has(set_key):
				out.append("%s: unit set '%s' has no emblem of that name in '%s Emblems.csv'. A set and its emblem are the same thing and have to share a name."
					% [who, kit.id, who])

		for badge_key in entry.emblems:
			var badge: Emblem = entry.emblems[badge_key]
			if not entry.sets.has(badge_key):
				out.append("%s: emblem '%s' has no unit set of that name in the unit CSV, so it unlocks nothing."
					% [who, badge.id])
			if badge.basic.strip_edges() == "":
				out.append("%s: emblem '%s' has an empty Basic Side." % [who, badge.id])
			if badge.condition.strip_edges() != "" and badge.ultimate.strip_edges() == "":
				out.append("%s: emblem '%s' has a Condition but no Ultimate Side to turn into."
					% [who, badge.id])
	return out
