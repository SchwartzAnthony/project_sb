class_name TeamLevel
extends RefCounted

# =============================================================
#  WHAT A TEAM IS WORTH
#
#  One number that says how far into the game a side is, so a friendly can
#  put you against somebody your own size instead of a random pile of cards.
#
#  ============ WHAT GOES INTO IT ============
#
#  You said it should be "how many unique players they have, and how strong
#  the different players are". So it is exactly those two things, and both
#  are weighted from Tuning.csv:
#
#      level_per_unique     what each DIFFERENT card on the side adds
#      level_per_card_level the share of the average card's Level column
#      level_per_power      the share of the average card's power
#      level_star_bonus     what fielding Stars is worth on top
#
#  In words: a side of nine different cards is worth more than a side that
#  fields the same three cards over and over, and a side of late-game cards
#  is worth more than a side of starters. Nothing else is in it.
#
#  ============ WHERE A CARD'S LEVEL COMES FROM ============
#
#  The Level column of your unit CSV. Leave it blank and the card's level is
#  guessed from its tier and its power — see PlayerData.get_level(). So you
#  can ignore levels entirely and this still works; filling the column in is
#  how you say "this Tier I card is a late-game card", which is a thing the
#  tier ladder will not let you say with power.
#
#  ============ WHAT IT IS NOT ============
#
#  It is NOT power, and it never becomes power. A level 30 side still fields
#  one 0, one 1 and one 2 in Tier I, exactly like a level 3 side. Level
#  decides WHO YOU MEET; the ladder decides what they bring. Keeping those
#  two apart is the whole reason the game is readable.
# =============================================================


## The level of a plain list of cards.
static func of_cards(cards: Array, db: CardDatabase = null) -> int:
	if cards.is_empty():
		return 0
	if db == null:
		db = CardDatabase.get_db()

	var unique: Dictionary = {}
	var level_total := 0
	var power_total := 0
	var stars := 0
	var counted := 0

	for item in cards:
		var card := item as PlayerData
		if card == null:
			continue
		counted += 1
		unique[CardDatabase._normalise(card.player_name)] = true
		level_total += card.get_level()
		power_total += card.get_attack_power()
		if card.is_star():
			stars += 1

	if counted == 0:
		return 0

	var per_unique := db.tune_float("level_per_unique", 1.0)
	var per_level := db.tune_float("level_per_card_level", 1.0)
	var per_power := db.tune_float("level_per_power", 1.5)
	var star_bonus := db.tune_float("level_star_bonus", 2.0)

	var average_level := float(level_total) / float(counted)
	var average_power := float(power_total) / float(counted)

	var score := float(unique.size()) * per_unique \
		+ average_level * per_level \
		+ average_power * per_power \
		+ float(stars) * star_bonus

	return maxi(1, int(round(score)))


## The level of a saved team off the shelf, Stars included.
static func of_team(entry: Dictionary, db: CardDatabase = null) -> int:
	if entry.is_empty():
		return 0
	if db == null:
		db = CardDatabase.get_db()

	var book := TeamRoster.new()
	var by_tier := book.cards_for(entry, db)
	var flat: Array = []
	for tier in by_tier.keys():
		for card in (by_tier[tier] as Array):
			flat.append(card)

	# The three Stars are part of the side, so they count.
	for star in db.star_ladder_for_class(String(entry.get("class", ""))):
		if star != null:
			flat.append(star)

	return of_cards(flat, db)


## The level of whatever is currently chosen, which is what a match asks.
static func of_selection(selection: TeamSelection, db: CardDatabase = null) -> int:
	if selection == null:
		return 0
	var flat: Array = []
	for card in selection.all_regulars():
		flat.append(card)
	for star in selection.star_bundle:
		if star != null:
			flat.append(star)
	return of_cards(flat, db)


## A short line for a screen: "Level 24  ·  9 different cards".
static func describe(cards: Array, db: CardDatabase = null) -> String:
	var unique: Dictionary = {}
	for item in cards:
		var card := item as PlayerData
		if card != null:
			unique[CardDatabase._normalise(card.player_name)] = true
	return "Level %d   ·   %d different card%s" % [
		of_cards(cards, db), unique.size(), "" if unique.size() == 1 else "s"]


# =============================================================
#  TWO NUMBERS, AND THEY ARE NOT THE SAME NUMBER
#
#  This tripped me up building it and it will trip you up reading it, so it
#  is worth being blunt about:
#
#      TEAM LEVEL     what a whole side is worth. A headline number, tens
#                     rather than units. This is what you compare sides by
#                     and what gets printed after an opponent's name.
#
#      CARD LEVEL     what ONE card is worth, from its Level column. Ones
#                     and tens, on whatever scale you choose to use.
#
#  A friendly matches you on CARD level, because that is what it has to go
#  shopping with — it is picking cards, not picking a finished team. Handing
#  a team level to a card search asks for cards at level 29 when your whole
#  collection tops out at 12, finds nothing, and quietly fields anybody.
#
#  So: of_cards() for showing a side off, average_card_level() for finding
#  one to play against.
# =============================================================

## The average card level of a side. THIS is the number a friendly bands
## around, because it is on the same scale as the cards it is choosing from.
static func average_card_level(cards: Array) -> float:
	var total := 0
	var counted := 0
	for item in cards:
		var card := item as PlayerData
		if card == null:
			continue
		total += card.get_level()
		counted += 1
	if counted == 0:
		return 0.0
	return float(total) / float(counted)


## The average card level of whatever is currently chosen.
static func card_level_of_selection(selection: TeamSelection) -> float:
	if selection == null:
		return 0.0
	var flat: Array = []
	for card in selection.all_regulars():
		flat.append(card)
	for star in selection.star_bundle:
		if star != null:
			flat.append(star)
	return average_card_level(flat)


## THE BAND A FRIENDLY SHOPS IN, around an average CARD level. A side whose
## cards average 7 is offered cards between 7 - spread and 7 + spread, so
## the same team does not meet the identical opposition every time.
##
##     friendly_level_spread    how far either way, in card levels
static func band(card_level: float, db: CardDatabase = null) -> Vector2i:
	if db == null:
		db = CardDatabase.get_db()
	var spread := db.tune_int("friendly_level_spread", 4)
	var middle := int(round(card_level))
	return Vector2i(maxi(0, middle - spread), middle + spread)


# =============================================================
#  A WORD ABOUT THE DEFAULT GUESS
#
#  With the Level column of your unit CSVs left blank, every card's level is
#  guessed from its tier and its power — and here is the catch: THE TIER
#  LADDER MEANS EVERY LEGAL TEAM HAS THE SAME POWERS. One 0, one 1, one 2 in
#  Tier I, and so on up. So every legal side guesses out at the same level,
#  and every friendly is the same difficulty.
#
#  That is not a fault in this file. It is the ladder doing exactly its job,
#  and it is precisely why you asked for a Level column: power cannot say
#  "this card is a late-game card" because power is spoken for. Level can.
#
#  FILL THE LEVEL COLUMN IN and friendlies start matching you. Leave it
#  blank and they are all the same, which is a perfectly playable prototype
#  and is what you had before. The Output panel says which you are getting.
# =============================================================

## True when no card anywhere has a Level of its own, which means matching
## cannot tell one side from another yet.
static func levels_are_unset(db: CardDatabase = null) -> bool:
	if db == null:
		db = CardDatabase.get_db()
	for card in db.players:
		if card != null and card.level > 0:
			return false
	return true
