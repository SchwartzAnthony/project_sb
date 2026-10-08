class_name SquadSheet
extends RefCounted

# =============================================================
#  A SQUAD WRITTEN IN A SPREADSHEET  (round AN)
#
#  Some matches are not played by YOUR team. The first match of a new game
#  is the example: twelve plain players and Koch, no Stars, nobody you have
#  to own. That side is written out row by row in a CSV, and a MatchModes.csv
#  row names the file in its `Squad` column. This file turns the CSV into the
#  TeamSelection the match already knows how to play.
#
#  THE COLUMNS (data/IntroSquad.csv and IntroSquad2.csv ship)
#    ID        a name for this place in the team. A random player is made
#              ONCE per save for each ID and remembered, so another sheet
#              using the same ID gets the same player back - and he or she
#              joins your base as a named player (recruit_book.gd enlist).
#    Tier      I, II, III or IV
#    Power     the card's number. Three per Tier, one of each on the ladder.
#    Name      blank = a random first name from Names.csv of that Gender.
#              Filled in with Class blank = the real card of that name
#              (Belial, a Star, with his ability and Emblem).
#    Class     whose plain card it is. Normal = the club's own players.
#    Gender    m or f. Blank = either, at random.
#    Artwork   blank = Tuning.csv squad_art_m / squad_art_f for Normal, or
#              the class's own sprite (placeholder_art_<Class>) otherwise
#    Star      yes = this player is a Star (a plain one, unless Ability says
#              otherwise). Blank = an ordinary player.
#    Ability   an Abilities.csv ID, used on both sides of the card.
#    Lead      yes on ONE row: that Tier stands where the Stars usually do,
#              and that player kicks off. Blank everywhere = the first row.
#
#  A side with no Star in it is PLAIN: the Lead's Tier stands where the
#  Stars usually do, with no badge and no Emblem (TeamSelection.plain).
# =============================================================

const DATA_DIR := "res://data/"

## Problems from the last read, for the Output panel.
static var problems: Array[String] = []


## The squad in `file_name` as a TeamSelection, or null if it cannot field a
## side. `file_name` is a name in data/ ("IntroSquad.csv") or a res:// path.
static func selection_from(file_name: String, db: CardDatabase,
		state: GameState = null, keep: bool = true) -> TeamSelection:
	problems = []
	var path := file_name if file_name.begins_with("res://") else DATA_DIR + file_name
	if not FileAccess.file_exists(path):
		problems.append("[squad] %s is not there." % path)
		_say()
		return null

	var rows := MenuSupport.read_csv(path)
	var cards: Array[PlayerData] = []
	var lead: PlayerData = null
	var used_names: Array[String] = []

	for row in rows:
		var tier := MenuSupport.field(row, "Tier").strip_edges().to_upper()
		if tier == "":
			continue

		# A REAL CARD: a Name with no Class is that card, Star and all.
		var named := MenuSupport.field(row, "Name").strip_edges()
		if named != "" and MenuSupport.field(row, "Class").strip_edges() == "":
			var real := _card_called(named, db)
			if real == null:
				problems.append("[squad] %s: there is no card called %s." % [path.get_file(), named])
				continue
			cards.append(real)
			used_names.append(named)
			if lead == null and _yes(MenuSupport.field(row, "Lead")):
				lead = real
			continue

		var card := PlayerData.new()
		card.tier = tier
		card.base_power_left = int(MenuSupport.field(row, "Power"))
		card.base_power_right = card.base_power_left
		card.player_type = "Normal"
		card.unit_type = _first(MenuSupport.field(row, "Class"), "Normal")
		card.element = _element_of(card.unit_type, db)
		card.card_set = "SQUAD"

		var gender := MenuSupport.field(row, "Gender").strip_edges().to_lower()
		var name_text := named
		var slot_id := MenuSupport.field(row, "ID").strip_edges()

		# THE SAME ID IS THE SAME PLAYER. Made once per save, then kept.
		# An opposition (keep = false) is made fresh every match: it is not
		# remembered and it does not join your base.
		var kept := _kept(slot_id, state) if keep else []
		var look := ""
		if name_text == "" and not kept.is_empty():
			name_text = String(kept[0])
			gender = String(kept[1])
			look = String(kept[2])
		if gender != "m" and gender != "f":
			gender = "f" if randf() < 0.5 else "m"
		if name_text == "":
			name_text = _random_name(gender, used_names, db, state)
			look = pick_look(gender, db)
			if keep and slot_id != "" and state != null:
				state.set_text(KEEP_PREFIX + CardDatabase._normalise(slot_id),
					"%s|%s|%s" % [name_text, gender, look])
				# ...and they join your base, until you let them go.
				if card.unit_type.to_lower() == db.tune_text("recruit_plain_class", "Normal").to_lower():
					# ROUND AN: the Role column (StartingTeam.csv) says whether he
					# arrives as a Match or an Adventure Player. Blank = starting_team_role.
					RecruitBook.enlist(name_text, tier, card.base_power_left, gender, state, look,
						MenuSupport.field(row, "Role").strip_edges().to_lower())
		used_names.append(name_text)
		card.player_name = name_text

		if _yes(MenuSupport.field(row, "Star")):
			card.player_type = "Star"
		var ability := MenuSupport.field(row, "Ability").strip_edges()
		if ability != "":
			card.attack_ability_id = ability
			card.defend_ability_id = ability
			if db.get_ability(ability) == null:
				problems.append("[squad] %s: %s has ability '%s', which is not in Abilities.csv." % [path.get_file(), name_text, ability])

		var wanted_art := MenuSupport.field(row, "Artwork").strip_edges()
		if wanted_art == "" and card.unit_type.to_lower() == "normal":
			wanted_art = look if look != "" else pick_look(gender, db)
		card.artwork = _art_for(wanted_art, card.unit_type, gender, db)
		if card.artwork == null:
			problems.append("[squad] %s: no sprite found for %s." % [path.get_file(), name_text])

		cards.append(card)
		if lead == null and _yes(MenuSupport.field(row, "Lead")):
			lead = card

	if cards.is_empty():
		problems.append("[squad] %s has no players in it." % path.get_file())
		_say()
		return null
	if lead == null:
		lead = cards[0]

	var picked := TeamSelection.new()
	picked.plain = not lead.is_star()
	picked.unit_type = lead.unit_type
	picked.star_tier = lead.get_tier_clean()
	picked.active_star = lead
	# The lead's Tier rotates in at the STAR PLAYER SWITCH, lead first.
	picked.star_bundle.append(lead)
	for card in cards:
		if card != lead and card.get_tier_clean() == picked.star_tier:
			picked.star_bundle.append(card)
	for card in cards:
		var tier_key := card.get_tier_clean()
		if tier_key == picked.star_tier:
			continue
		if not picked.regulars.has(tier_key):
			picked.regulars[tier_key] = []
		(picked.regulars[tier_key] as Array).append(card)

	var line := PackedStringArray()
	for card in cards:
		line.append("%s (%s %s %d)" % [card.player_name, card.unit_type, card.tier, card.base_power_left])
	print("[squad] %s: %s" % [path.get_file(), ", ".join(line)])
	_say()
	return picked


## Where the player made for an ID is remembered in the save.
const KEEP_PREFIX := "squad_player_"


## [name, gender, look] of the player already made for this ID, or [].
static func _kept(slot_id: String, state: GameState) -> Array:
	if slot_id == "" or state == null:
		return []
	var text := state.text(KEEP_PREFIX + CardDatabase._normalise(slot_id), "")
	var parts := text.split("|")
	if parts.size() < 2 or String(parts[0]) == "":
		return []
	return [String(parts[0]), String(parts[1]), String(parts[2]) if parts.size() > 2 else ""]


## ============ MORE THAN ONE LOOK (round AN, your answer) ============
##
## Tuning.csv squad_art_f (and squad_art_m) may list several sprite sheets
## separated by | . Each new player gets one of them at random, and keeps it:
## the choice is saved with the player.
static func pick_look(gender: String, db: CardDatabase) -> String:
	var looks: Array[String] = []
	for part in db.tune_text("squad_art_" + gender, "").split("|", false):
		if String(part).strip_edges() != "":
			looks.append(String(part).strip_edges())
	if looks.is_empty():
		return ""
	return looks[randi() % looks.size()]


static func _card_called(name_text: String, db: CardDatabase) -> PlayerData:
	var wanted := CardDatabase._normalise(name_text)
	for card in db.players:
		if card != null and CardDatabase._normalise(card.player_name) == wanted:
			return card
	return null


## A first name nobody in this squad has, and that no card already uses.
static func _random_name(gender: String, used: Array[String], db: CardDatabase,
		state: GameState = null) -> String:
	var taken := {}
	for card in db.players:
		taken[card.player_name] = true
	if state != null:
		for held in NameBook.held(state):
			taken[held] = true
	var pool: Array[String] = []
	for row in MenuSupport.read_csv(NameBook.FILE):
		var first := MenuSupport.field(row, "First Name").strip_edges()
		var says := MenuSupport.field(row, "Gender").strip_edges().to_lower()
		if first == "" or used.has(first) or taken.has(first):
			continue
		if says == "" or says == gender:
			pool.append(first)
	if pool.is_empty():
		return "Spieler %d" % (used.size() + 1)
	return pool[randi() % pool.size()]


static func _art_for(wanted: String, unit_type: String, gender: String,
		db: CardDatabase) -> Texture2D:
	var file_name := wanted.strip_edges()
	if file_name == "":
		if unit_type.to_lower() == "normal":
			file_name = db.tune_text("squad_art_" + gender, "")
		if file_name == "":
			file_name = db.tune_text("placeholder_art_" + unit_type, "")
		if file_name == "":
			file_name = db.tune_text("placeholder_art", "")
	if file_name == "":
		return null
	return db._find_texture(file_name, CardDatabase.PLAYER_ART_DIRS)


## The element the class plays as, taken from any card of that class.
static func _element_of(unit_type: String, db: CardDatabase) -> String:
	for card in db.roster_for_class(unit_type):
		if card.element != "" and card.element.to_lower() != "none":
			return card.element
	return "None"


static func _first(text: String, fallback: String) -> String:
	var clean := text.strip_edges()
	return clean if clean != "" else fallback


static func _yes(text: String) -> bool:
	return ["yes", "y", "true", "1", "x"].has(text.strip_edges().to_lower())


static func _say() -> void:
	for line in problems:
		push_warning(line)
