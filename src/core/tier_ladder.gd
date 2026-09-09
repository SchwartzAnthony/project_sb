class_name TierLadder
extends RefCounted

# =============================================================
#  THE LADDER — one card at each power, in every tier, always
#
#  ============ THIS IS THE RULE THE WHOLE GAME OBEYS ============
#
#      Tier I    holds a 0, a 1 and a 2
#      Tier II   holds a 1, a 2 and a 3
#      Tier III  holds a 2, a 3 and a 4
#      Tier IV   holds a 3, a 4 and a 5
#
#  Three cards per tier, and their powers are always three different
#  numbers in a row. Never three 2s. Never two 5s. Not in the collection,
#  not in the team builder, not on the pitch, not for the enemy.
#
#  WHERE THE NUMBERS COME FROM
#
#  data/TierPowers.csv, which you already have:
#
#      Tier,Min Attack,Max Attack,Min Defense,Max Defense,Notes
#      I,0,2,0,2,...
#      II,1,3,1,3,...
#
#  Min to Max is the tier's ladder. Tier I is 0 to 2, so its RUNGS are
#  0, 1 and 2 — one card on each. Change those numbers and every screen
#  in the game agrees with you next time you press F5. There is no second
#  place to edit.
#
#  A "rung" is just a power with a slot reserved for it. When this file
#  says "the 2 rung of Tier I" it means "the Tier I slot that only a
#  2-power card may stand in".
#
#  WHAT COUNTS AS A CARD'S POWER
#
#  Its Base Power Left column — the attack number. That is the number
#  printed on the card and the number a player means when they say "my
#  2-power lad". Base Power Right (defence) should match it; if it does
#  not, the startup report says so, because then "the 2-power card" no
#  longer means one thing.
#
#  WHAT MAY CHANGE A POWER
#
#  Nothing here. Abilities and elements during a match add their bonuses
#  in AbilityEngine, which holds them beside the card and throws them
#  away at the end of the duel, round, cycle or match. The card itself
#  never changes, so it walks into the next match on its proper rung.
#
#  Season Difficulty used to break this rule — see the note in
#  ability_engine.gd. It now adds to the SHOT instead of to the cards.
# =============================================================

## The tiers, weakest first. Matches PlayerData.TIER_ORDER.
const TIERS: Array[String] = ["I", "II", "III", "IV"]

## Used only when TierPowers.csv is missing or unreadable, so a broken
## install still plays instead of fielding nobody. Tier N starts at N-1.
const FALLBACK_FIRST_RUNG: Dictionary = {"I": 0, "II": 1, "III": 2, "IV": 3}
const FALLBACK_RUNGS := 3


# =============================================================
#  THE RUNGS OF A TIER
# =============================================================

## The powers a tier holds, lowest first. Tier I -> [0, 1, 2].
static func rungs(tier_key: String, db: CardDatabase = null) -> Array[int]:
	var database := db if db != null else CardDatabase.get_db()
	var key := CardDatabase._normalise(tier_key)

	if database != null and database.tier_bands.has(key):
		var band: Dictionary = database.tier_bands[key]
		var low := int(band["minatk"])
		var high := int(band["maxatk"])
		if high >= low:
			var out: Array[int] = []
			for power in range(low, high + 1):
				out.append(power)
			return out

	# No TierPowers.csv. Fall back to the shipped ladder rather than
	# returning nothing, which would field an empty tier.
	var clean := tier_key.strip_edges().to_upper()
	var first := int(FALLBACK_FIRST_RUNG.get(clean, 0))
	var guess: Array[int] = []
	for i in FALLBACK_RUNGS:
		guess.append(first + i)
	return guess


## How many cards a tier holds. Three, unless you widened the band.
static func slot_count(tier_key: String, db: CardDatabase = null) -> int:
	return rungs(tier_key, db).size()


## The power that decides which rung a card stands on.
static func rung_of(card: PlayerData) -> int:
	return card.get_attack_power() if card != null else -1


## May this card stand in this tier at all?
static func fits(card: PlayerData, tier_key: String, db: CardDatabase = null) -> bool:
	if card == null:
		return false
	if card.get_tier_clean() != tier_key.strip_edges().to_upper():
		return false
	return rungs(tier_key, db).has(rung_of(card))


## "Tier I holds a 0, a 1 and a 2." — for tooltips and error messages.
static func describe(tier_key: String, db: CardDatabase = null) -> String:
	var ladder := rungs(tier_key, db)
	if ladder.is_empty():
		return "Tier %s holds nobody." % tier_key
	if ladder.size() == 1:
		return "Tier %s holds a %d." % [tier_key, ladder[0]]

	var words: Array[String] = []
	for power in ladder:
		words.append("a %d" % power)
	var last: String = words.pop_back()
	return "Tier %s holds %s and %s." % [tier_key, ", ".join(words), last]


# =============================================================
#  BUILDING A LEGAL TIER
# =============================================================

## Fill a tier from a pool of cards: one card per rung, lowest first.
##
## Returns {"cards": Array[PlayerData], "missing": Array[int]}.
##   cards   — what could be fielded, in ladder order (weakest first)
##   missing — the rungs nobody in the pool could stand on
##
## `vary` shuffles first, so two matches with the same collection field
## different legal line-ups. Turn it off when you want the same answer
## every time (the startup report does).
##
## `backup` is only reached for a rung `pool` cannot fill. That is how a
## Teams.csv row naming three cards still fields a legal team: its own
## cards are always preferred, and the rest of the class quietly fills
## whatever rung the row forgot.
static func build(pool: Array, tier_key: String, db: CardDatabase = null,
		vary: bool = true, backup: Array = []) -> Dictionary:
	var clean := tier_key.strip_edges().to_upper()

	# Only cards of this tier are candidates, and each is used once.
	# Preferred first, then backup — the search below takes the first match,
	# so anything in `pool` always beats anything in `backup`.
	var candidates: Array[PlayerData] = []
	var reserves: Array[PlayerData] = []
	for entry in pool:
		var card := entry as PlayerData
		if card != null and card.get_tier_clean() == clean:
			candidates.append(card)
	for entry in backup:
		var card := entry as PlayerData
		if card != null and card.get_tier_clean() == clean and not candidates.has(card):
			reserves.append(card)
	if vary:
		candidates.shuffle()
		reserves.shuffle()
	candidates.append_array(reserves)

	var cards: Array[PlayerData] = []
	var missing: Array[int] = []
	var taken: Array[PlayerData] = []

	for power in rungs(clean, db):
		var found: PlayerData = null
		for card in candidates:
			if rung_of(card) != power:
				continue
			if taken.has(card):
				continue
			found = card
			break

		if found == null:
			missing.append(power)
		else:
			taken.append(found)
			cards.append(found)

	return {"cards": cards, "missing": missing}


## Keep whatever in `chosen` is already legal, and fill the gaps from `pool`.
##
## This is what protects a team that was saved before you edited a CSV, and
## what quietly straightens out an enemy squad drawn at random.
static func repair(chosen: Array, pool: Array, tier_key: String,
		db: CardDatabase = null, vary: bool = true) -> Dictionary:
	var clean := tier_key.strip_edges().to_upper()
	var ladder := rungs(clean, db)

	# One keeper per rung: the first legal card offered for it wins, and
	# anything else in `chosen` is dropped because it has nowhere to stand.
	var kept: Dictionary = {}          # power -> PlayerData
	var dropped: Array[PlayerData] = []
	for entry in chosen:
		var card := entry as PlayerData
		if card == null:
			continue
		var power := rung_of(card)
		if card.get_tier_clean() != clean or not ladder.has(power) or kept.has(power):
			dropped.append(card)
			continue
		kept[power] = card

	# Fill what is still empty, never re-using a card already standing.
	var spare: Array[PlayerData] = []
	for entry in pool:
		var card := entry as PlayerData
		if card != null and not kept.values().has(card):
			spare.append(card)
	if vary:
		spare.shuffle()

	var cards: Array[PlayerData] = []
	var missing: Array[int] = []
	for power in ladder:
		if kept.has(power):
			cards.append(kept[power])
			continue
		var found: PlayerData = null
		for card in spare:
			if card.get_tier_clean() == clean and rung_of(card) == power \
					and not cards.has(card):
				found = card
				break
		if found == null:
			missing.append(power)
		else:
			cards.append(found)

	return {"cards": cards, "missing": missing, "dropped": dropped}


# =============================================================
#  CHECKING A TIER
# =============================================================

## Which rungs are empty or doubled up in this line-up?
static func missing_rungs(cards: Array, tier_key: String,
		db: CardDatabase = null) -> Array[int]:
	var seen: Array[int] = []
	for entry in cards:
		var card := entry as PlayerData
		if card == null:
			continue
		var power := rung_of(card)
		if not seen.has(power):
			seen.append(power)

	var gaps: Array[int] = []
	for power in rungs(tier_key, db):
		if not seen.has(power):
			gaps.append(power)
	return gaps


## Is this line-up exactly one card on every rung?
static func legal(cards: Array, tier_key: String, db: CardDatabase = null) -> bool:
	var ladder := rungs(tier_key, db)
	var real := 0
	for entry in cards:
		if entry as PlayerData != null:
			real += 1
	if real != ladder.size():
		return false
	return missing_rungs(cards, tier_key, db).is_empty()


## Plain English for what a half-built tier still needs.
## "Tier I still needs a 1 and a 2" — or "" when it is legal.
static func needs_text(cards: Array, tier_key: String,
		db: CardDatabase = null) -> String:
	var gaps := missing_rungs(cards, tier_key, db)
	if gaps.is_empty():
		return ""
	var words: Array[String] = []
	for power in gaps:
		words.append("a %d" % power)
	if words.size() == 1:
		return "Tier %s still needs %s" % [tier_key, words[0]]
	var last: String = words.pop_back()
	return "Tier %s still needs %s and %s" % [tier_key, ", ".join(words), last]


# =============================================================
#  THE STARTUP REPORT
#
#  Called by content_report.gd. It answers the only question that
#  matters before you press play: can every class actually field a
#  legal team? A class missing its 1-power Tier II card cannot, and
#  you want to hear that at startup rather than at kick-off.
# =============================================================

## Report lines for one class. Empty array means the class is fine.
static func check_class(unit_type: String, db: CardDatabase = null) -> Array[String]:
	var database := db if db != null else CardDatabase.get_db()
	if database == null:
		return []

	var roster := database.roster_for_class(unit_type)
	var lines: Array[String] = []

	# THE STARS MUST SHARE ONE TIER. They hold that tier between them and
	# rotate through it at HOLD UP, stepping into each other's slot on the
	# pitch — so a Star from another tier has nowhere legal to stand, and
	# is left out of the bundle rather than fielded in the wrong place.
	var star_tier := database.star_tier_for_class(unit_type)
	if star_tier != "":
		for card in roster:
			if card.is_star() and card.get_tier_clean() != star_tier:
				lines.append("%s's Star Players hold Tier %s, but '%s' is a Star in Tier %s. It will not be fielded — move it to Tier %s, or make it a Normal card."
					% [unit_type, star_tier, card.player_name,
						card.get_tier_clean(), star_tier])

	for tier in TIERS:
		var ladder := rungs(tier, database)
		if ladder.size() != 3:
			lines.append("TierPowers.csv: Tier %s is %d to %d, which is %d cards. The pitch has three slots per tier — make it a span of three."
				% [tier, ladder[0] if not ladder.is_empty() else 0,
					ladder[ladder.size() - 1] if not ladder.is_empty() else 0,
					ladder.size()])

		# Count what the class owns on each rung, Stars and regulars apart:
		# the Stars fill their own tier, so a Star tier is judged on Stars.
		var star_count: Dictionary = {}
		var normal_count: Dictionary = {}
		for card in roster:
			if card.get_tier_clean() != tier:
				continue
			var power := rung_of(card)
			if card.is_star():
				star_count[power] = int(star_count.get(power, 0)) + 1
			else:
				normal_count[power] = int(normal_count.get(power, 0)) + 1

		var has_stars := not star_count.is_empty()
		for power in ladder:
			var normals := int(normal_count.get(power, 0))
			var stars := int(star_count.get(power, 0))
			if normals == 0 and stars == 0:
				lines.append("%s has no %d-power Tier %s card. %s, so that slot cannot be filled — add one, or change Tier %s's row in TierPowers.csv."
					% [unit_type, power, tier, describe(tier, database), tier])
			elif has_stars and stars == 0 and normals > 0:
				# Only worth saying when the tier is a Star tier.
				pass

		# A Star tier must be a ladder too, because the Stars hold it alone.
		if has_stars:
			for power in ladder:
				if int(star_count.get(power, 0)) == 0:
					lines.append("%s has Star Players in Tier %s but none with %d power. %s, and the Stars hold that tier on their own."
						% [unit_type, tier, power, describe(tier, database)])
				elif int(star_count.get(power, 0)) > 1:
					lines.append("%s has %d Star Players in Tier %s with %d power. Only one card may stand on each rung — give the others a different Base Power Left."
						% [unit_type, int(star_count[power]), tier, power])

	return lines


## THE SAME CARD LOADED TWICE.
##
## CardDatabase reads EVERY .csv in res://data/, so a spare copy of a unit
## file — an export, a backup, an example — silently doubles a whole class.
## The class then has six Star Players instead of three and two cards on
## every rung, which is exactly the shape the ladder cannot make sense of:
## it will field a legal three, but WHICH three becomes arbitrary.
##
## This is the check that finds a duplicate file, because the symptom on
## the pitch ("why is the same lad in twice?") never points at the cause.
static func check_duplicate_names(db: CardDatabase = null) -> Array[String]:
	var database := db if db != null else CardDatabase.get_db()
	if database == null:
		return []

	var seen: Dictionary = {}          # "class|name" -> how many
	for card in database.players:
		var key := "%s|%s" % [CardDatabase._normalise(card.unit_type),
			CardDatabase._normalise(card.player_name)]
		seen[key] = int(seen.get(key, 0)) + 1

	var doubled: Array[String] = []
	for key in seen.keys():
		if int(seen[key]) > 1:
			doubled.append(String(key).split("|")[1])

	if doubled.is_empty():
		return []
	return ["%d card(s) are loaded more than once, including '%s'. Every .csv in res://data/ is read, so a spare copy of a unit file doubles the whole class — six Stars instead of three, two cards on every rung. Move the extra file out of res://data/ (or rename it so it does not end in .csv)."
		% [doubled.size(), doubled[0]]]


## Every card whose attack and defence disagree. A card like that has no
## single "power", so the ladder cannot say where it belongs.
static func check_mirrored_powers(db: CardDatabase = null) -> Array[String]:
	var database := db if db != null else CardDatabase.get_db()
	if database == null:
		return []
	var lines: Array[String] = []
	for card in database.players:
		if card.base_power_left != card.base_power_right:
			lines.append("'%s' has %d attack but %d defence. The ladder places it by its attack (%d) — set Base Power Right to match, or accept that it is a %d on the pitch."
				% [card.player_name, card.base_power_left, card.base_power_right,
					card.base_power_left, card.base_power_left])
	return lines
