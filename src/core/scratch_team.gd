class_name ScratchTeam
extends RefCounted

# =============================================================
#  A SIDE PUT TOGETHER ON THE SPOT
#
#  "Play a match" from the base is not a season fixture. It is a friendly
#  against a team that does not exist until you press the button: an
#  accumulated side, drawn from every card in the game, at roughly YOUR
#  level. Win it and you still collect — see the Rewards columns of
#  MatchModes.csv.
#
#  ============ HOW ONE IS BUILT ============
#
#  1. Work out your side's level          team_level.gd
#  2. Take the band around it             level_per_* rows in Tuning.csv
#  3. Keep every card whose own level is inside that band
#  4. Fill each tier with ONE CARD PER RUNG from what is left   tier_ladder.gd
#  5. Give it a name from ScratchNames.csv
#
#  Step 4 is the important one. A scratch side obeys the tier ladder exactly
#  like yours does — one 0, one 1 and one 2 in Tier I and so on up. Levelling
#  the opposition changes WHICH cards turn up, never how big their numbers
#  are. A level 40 friendly is a harder match because the cards are cleverer,
#  not because they are bigger. That is the rule the whole game rests on and
#  nothing here bends it.
#
#  ============ IT MIXES CLASSES ON PURPOSE ============
#
#  A scratch side is not a club, it is a pick-up team, so Tier II can be
#  Lorelei and Tier III can be Brandteufel. Its three STARS still come from
#  one class, because a Star bundle holds a whole tier between them and
#  mixing those would break the ladder.
#
#  Set `friendly_single_class` to true in Tuning.csv if you would rather
#  friendlies be proper clubs of one class.
#
#  ============ WHAT IT DOES NOT DO ============
#
#  It never writes anything. A scratch team is made, played and forgotten;
#  the only thing that outlives it is whatever you earned. Saved teams are
#  team_roster.gd and are a different thing entirely.
# =============================================================

const NAMES_PATH := "res://data/ScratchNames.csv"

var team_name: String = "Wanderers"
var star_class: String = ""
var level: int = 0
## Every regular this side fields, mixed class, already ladder-legal.
var cards: Array[PlayerData] = []
## Why it looks the way it does, printed to the Output panel.
var notes: Array[String] = []


# =============================================================
#  BUILDING ONE
# =============================================================

## Make an opponent to face a side whose cards average `target_card_level`.
##
## NOTE WHICH NUMBER THIS TAKES. It is the average CARD level of your side,
## not your side's team level — the two are on completely different scales
## and handing over the wrong one asks for cards that do not exist. See the
## long note in team_level.gd.
##
## `avoid_class` is the class YOU are fielding — the scratch side's Stars
## come from somewhere else where possible, so you are not looking at your
## own Star across the halfway line.
static func build(target_card_level: float, db: CardDatabase, state: GameState,
		avoid_class: String = "") -> ScratchTeam:
	var made := ScratchTeam.new()
	if db == null:
		return made

	var window := TeamLevel.band(target_card_level, db)

	# --- 1. Which class do the Stars come from? ---
	var classes: Array[String] = []
	for key in db.stars_by_class().keys():
		var text := String(key)
		if text.strip_edges() == "":
			continue
		if avoid_class != "" \
				and CardDatabase._normalise(text) == CardDatabase._normalise(avoid_class):
			continue
		classes.append(text)
	if classes.is_empty():
		# Only one class in the project. Mirroring is better than no match.
		for key in db.stars_by_class().keys():
			classes.append(String(key))
	if classes.is_empty():
		made.notes.append("No Star Players anywhere — there is nobody to field.")
		return made

	classes.shuffle()
	made.star_class = classes[0]

	# --- 2. The pool ---
	var single := db.tune_bool("friendly_single_class", false)
	var pool: Array[PlayerData] = []
	for card in db.players:
		if card == null or card.is_star():
			continue
		if single and CardDatabase._normalise(card.unit_type) \
				!= CardDatabase._normalise(made.star_class):
			continue
		pool.append(card)

	var in_band: Array[PlayerData] = []
	for card in pool:
		var card_level := card.get_level()
		if card_level >= window.x and card_level <= window.y:
			in_band.append(card)

	# A band with nothing in it is not an error — it means your level is
	# somewhere the collection does not reach yet. Widen until there is
	# something to field, and say so.
	var widened := 0
	while in_band.size() < 12 and widened < 20:
		widened += 1
		window.x = maxi(0, window.x - 2)
		window.y += 2
		in_band.clear()
		for card in pool:
			var card_level := card.get_level()
			if card_level >= window.x and card_level <= window.y:
				in_band.append(card)
	if widened > 0:
		made.notes.append("Widened the level band to %d–%d to find enough cards."
			% [window.x, window.y])
	if in_band.is_empty():
		in_band = pool
		made.notes.append("No card levels matched at all — fielding from the whole collection.")

	# --- 3. One card per rung, tier by tier ---
	var star_tier := db.star_tier_for_class(made.star_class)
	for tier in TierLadder.TIERS:
		if tier == star_tier:
			continue                    # the three Stars hold this tier
		var choices: Array[PlayerData] = []
		for card in in_band:
			if card.get_tier_clean() == tier:
				choices.append(card)

		# TierLadder does the picking, so a scratch side can never come out
		# illegal — and a rung with nothing available comes back EMPTY rather
		# than with a wrong card wedged into it, which the match reads as a
		# free win for you in that tier.
		var built := TierLadder.build(choices, tier, db, true, pool)
		for card in (built["cards"] as Array):
			if card != null:
				made.cards.append(card)
		var gaps: Array = built.get("missing", [])
		if not gaps.is_empty():
			# An empty rung is not a bug — it is a tier they cannot fill, and
			# the match reads that as a free win for you. Worth printing so
			# you know why a friendly was easy.
			var words: Array[String] = []
			for power in gaps:
				words.append("%d-power" % int(power))
			made.notes.append("Tier %s has nobody at %s — that tier is a free win for you."
				% [tier, ", ".join(words)])

	# THE SIDE'S OWN LEVEL, measured from what it actually came out as rather
	# than from what was asked for. Its three Stars count, the same way they
	# count on yours.
	var whole: Array = made.cards.duplicate()
	for star in db.star_ladder_for_class(made.star_class):
		if star != null:
			whole.append(star)
	made.level = TeamLevel.of_cards(whole, db)

	made.team_name = _pick_name(made.level)
	return made


# =============================================================
#  THE NAME
#
#  res://data/ScratchNames.csv, two columns:
#
#      First,Second
#      Reedbank,Wanderers
#      Hollow,Rovers
#
#  One word is taken from each column at random, so twenty rows give you
#  four hundred club names. Add rows, get names. A missing file falls back
#  to a small built-in list so a friendly always has an opponent with a name.
# =============================================================

static func _pick_name(for_level: int) -> String:
	var firsts: Array[String] = []
	var seconds: Array[String] = []

	for row in MenuSupport.read_csv(NAMES_PATH):
		var first := MenuSupport.field(row, "First")
		var second := MenuSupport.field(row, "Second")
		if first != "":
			firsts.append(first)
		if second != "":
			seconds.append(second)

	if firsts.is_empty():
		firsts = ["Reedbank", "Hollow", "Ashford", "Millgate", "Stonebrook"]
	if seconds.is_empty():
		seconds = ["Wanderers", "Rovers", "Athletic", "Town", "United"]

	var name_text := "%s %s" % [
		firsts[randi() % firsts.size()], seconds[randi() % seconds.size()]]

	# A number after the name is a cheap, readable way to see at a glance
	# whether the game is matching you properly. Turn it off in Tuning.csv
	# with show_friendly_level once you are happy with the numbers.
	if CardDatabase.get_db().tune_bool("show_friendly_level", true):
		name_text += "  (level %d)" % for_level
	return name_text


# =============================================================
#  WHAT IT CAME OUT AS
# =============================================================

func describe() -> String:
	var lines: Array[String] = []
	lines.append("%s — Stars are %s, %d regular(s), level %d" % [
		team_name, star_class, cards.size(), level])
	for tier in TierLadder.TIERS:
		var row: Array[String] = []
		for card in cards:
			if card.get_tier_clean() == tier:
				row.append("%s (%d power, level %d)" % [
					card.player_name, card.get_attack_power(), card.get_level()])
		if not row.is_empty():
			lines.append("  Tier %s: %s" % [tier, ", ".join(row)])
	for note in notes:
		lines.append("  ! " + note)
	return "\n".join(lines)
