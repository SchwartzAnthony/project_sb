class_name DevMode
extends RefCounted

# =============================================================
#  THE DEVELOPER'S DOOR — own everything, or own nothing
#
#  ============ WHAT YOU ASKED FOR ============
#
#  "I have added all units that will be used by the enemy and can be
#   collected by the player. For the test, add a feature for me the developer
#   to use all or none of the units."
#
#  So two buttons. OWN EVERYTHING signs every card in every unit CSV, which
#  is how you look at a roster of a hundred and twenty cards without playing
#  for a month. OWN NOTHING clears the lot, which is how you see what a brand
#  new game actually looks like without deleting a save.
#
#  ============ IT IS A DOOR, AND IT IS LOCKED ============
#
#  `dev_mode` in Tuning.csv is FALSE. While it is false:
#
#      the panel does not open
#      the hotkey does nothing
#      nothing on this page can be reached by any means
#
#  Set it to true and a RED STRIP sits across the top of every screen for as
#  long as it is on. That strip is not decoration — it is the thing that
#  stops a build going out with a hundred and twenty free cards in it,
#  because you cannot take a screenshot without seeing it.
#
#  ============ WHY IT WRITES TO THE ORDINARY SAVE ============
#
#  Because a developer switch that uses its own private store is a developer
#  switch that tests something other than the game. OWN EVERYTHING calls the
#  same `SquadBook.sign()` a `sign:Müller` row in Dialogue.csv calls, so what
#  you are testing is the real thing — and `squad_ownership` being FALSE out
#  of the box means neither button changes a single match until you turn the
#  ownership system on.
#
#  ============ WHAT IT DELIBERATELY DOES NOT DO ============
#
#  It does not touch coins, achievements, unlocks or the talent tree. This is
#  about the ROSTER and nothing else: one switch that does six things is a
#  switch nobody can reason about. If you want everything unlocked as well,
#  say so and it becomes a second button next to this one.
# =============================================================


## Is the door open at all?
static func on(db: CardDatabase) -> bool:
	return db != null and db.tune_bool("dev_mode", false)


## What the red strip says. "" when dev mode is off, so a caller can write
## one line and not think about it.
static func banner(db: CardDatabase, state: GameState) -> String:
	if not on(db):
		return ""
	var many := SquadBook.names(state).size()
	if not SquadBook.on(db):
		return "DEV MODE  ·  squad ownership is OFF, so every card is yours anyway"
	return "DEV MODE  ·  %d card(s) signed" % many


# =============================================================
#  THE TWO BUTTONS
# =============================================================

## EVERY CARD IN THE GAME IS YOURS. Returns what it did, in words.
##
## Stars included, every class included, and the opposition's cards too —
## they are rows in the same spreadsheets and a developer looking at a roster
## wants to see all of it.
static func own_everything(state: GameState, db: CardDatabase) -> String:
	if state == null or db == null:
		return "no save"
	var signed := 0
	for card in db.players:
		if card.player_name.strip_edges() == "":
			continue
		if SquadBook.names(state).has(card.player_name):
			continue
		SquadBook.sign(card.player_name, state)
		signed += 1
	state.save_to_disk()
	var words := "signed %d card(s) — %d in the squad now." % [signed, SquadBook.names(state).size()]
	if not SquadBook.on(db):
		words += " `squad_ownership` is FALSE, so this changes nothing in a match until you turn it on."
	print("[dev] %s" % words)
	return words


## AND NOBODY IS. What a new game looks like, without deleting a save.
static func own_nothing(state: GameState, db: CardDatabase) -> String:
	if state == null:
		return "no save"
	var had := SquadBook.names(state).size()
	for card_name in SquadBook.names(state):
		SquadBook.release(card_name, state)
	state.save_to_disk()
	var words := "released %d card(s). The squad is empty." % had
	if db != null and not SquadBook.on(db):
		words += " `squad_ownership` is FALSE, so every card is still fieldable until you turn it on."
	print("[dev] %s" % words)
	return words


## ONE CLASS, for when the whole roster is too much to look at.
static func own_class(unit_type: String, state: GameState, db: CardDatabase) -> String:
	if state == null or db == null:
		return "no save"
	var signed := 0
	for card in db.players:
		if CardDatabase._normalise(card.active_unit_type()) != CardDatabase._normalise(unit_type):
			continue
		if card.player_name.strip_edges() == "" or SquadBook.names(state).has(card.player_name):
			continue
		SquadBook.sign(card.player_name, state)
		signed += 1
	state.save_to_disk()
	print("[dev] signed %d %s card(s)." % [signed, unit_type])
	return "signed %d %s card(s)." % [signed, unit_type]


# =============================================================
#  WHAT IS IN THE GAME, COUNTED
#
#  Not strictly needed to sign anybody — but a developer pressing OWN
#  EVERYTHING wants to know what "everything" turned out to be, and a number
#  that surprises you is the fastest way to find a CSV that did not load.
# =============================================================

static func roster_report(db: CardDatabase) -> Array[String]:
	var out: Array[String] = []
	if db == null:
		return out
	var by_class := {}
	var stars := {}
	for card in db.players:
		var who := card.active_unit_type()
		by_class[who] = int(by_class.get(who, 0)) + 1
		if card.is_star():
			stars[who] = int(stars.get(who, 0)) + 1
	var names: Array[String] = []
	for who in by_class:
		names.append(String(who))
	names.sort()
	for who in names:
		out.append("%-26s %3d card(s), %d Star(s)"
			% [who, int(by_class[who]), int(stars.get(who, 0))])
	out.append("%-26s %3d card(s) in all" % ["EVERYTHING", db.players.size()])
	return out
