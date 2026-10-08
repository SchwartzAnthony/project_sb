class_name RecruitBook
extends RefCounted

# =============================================================
#  NAMED RECRUITS — plain players with names of their own
#
#  ============ WHAT YOU ASKED FOR ============
#
#  "The player can recruit multiple players that are Tier I Power 0, they
#   all have to have unique names, and when they are on a team, on the field
#   or in the player's database they keep that name until they are removed
#   from the base entirely."
#
#  So a recruit is NOT a new row in a spreadsheet. He is a copy of a plain
#  card - BasicTeam's Tier I Power 0, say - wearing a name of his own from
#  Names.csv. Recruit three Tier I Power 0s and you have Johannes, Lukas and
#  Theresa: three men, one card underneath, three names.
#
#  Then the Pub turns him into a class - three beers - and he keeps the name.
#  See transform_book.gd.
#
#  ============ HOW SOMEBODY IS RECRUITED ============
#
#  An action, in any Effects / Do / Action / Reward column:
#
#      recruit:I0              a Tier I, Power 0 plain player, any free name
#      recruit:III3            Tier III, Power 3
#      recruit:I0=Johannes     and call him Johannes, if nobody else is
#
#  And he leaves with the action that was already there:
#
#      release:Johannes        gone from the base, name free again
#
#  ============ IT IS OFF UNTIL YOU TURN IT ON ============
#
#  `named_recruits` in Tuning.csv, FALSE out of the box, exactly like
#  squad_ownership. While it is false a `recruit:` action is still written
#  into the save - so you can write the rows today - but nobody new turns up
#  on any screen. Turn it on together with squad_ownership and the card list
#  becomes your recruits plus whoever else you have signed.
#
#  ============ WHERE IT LIVES ============
#
#  In the save:
#      recruits             "Johannes|Lukas|Theresa"
#      recruit_<name>       "I|0"           his tier and power
#  and his name in `names_held` - see name_book.gd.
# =============================================================

const KEY := "recruits"
const PREFIX := "recruit_"

## The recruit cards currently added to the card list, so they can be taken
## off again before the next lot go on.
static var _added: Array[PlayerData] = []


static func on(db: CardDatabase) -> bool:
	return db != null and db.tune_bool("named_recruits", false)


static func names(state: GameState) -> Array[String]:
	var out: Array[String] = []
	if state == null:
		return out
	for piece in state.text(KEY).split("|"):
		var clean := String(piece).strip_edges()
		if clean != "" and not out.has(clean):
			out.append(clean)
	return out


static func is_recruit(name_text: String, state: GameState) -> bool:
	var wanted := CardDatabase._normalise(name_text)
	for held in names(state):
		if CardDatabase._normalise(held) == wanted:
			return true
	return false


## "I0" -> {"tier": "I", "power": 0}. "III 3", "iii-3" and "III:3" all work.
## Empty if it is not a tier and a power.
static func parse(text: String) -> Dictionary:
	var clean := text.strip_edges().to_upper().replace(" ", "").replace("-", "").replace(":", "")
	var tier := ""
	var i := 0
	while i < clean.length() and clean[i] in ["I", "V"]:
		tier += clean[i]
		i += 1
	var rest := clean.substr(i)
	if not (tier in ["I", "II", "III", "IV"]) or not rest.is_valid_int():
		return {}
	return {"tier": tier, "power": int(rest)}


## The plain card a recruit at this tier and power is a copy of.
static func template_for(tier: String, power: int, db: CardDatabase) -> PlayerData:
	if db == null:
		return null
	var plain := CardDatabase._normalise(db.tune_text("recruit_plain_class", "Normal"))
	for card in db.players:
		if card == null or card.is_star() or _added.has(card):
			continue
		if CardDatabase._normalise(card.unit_type) != plain:
			continue
		if card.get_tier_clean() == tier and card.base_power_left == power:
			return card
	return null


## Sign one. `what` is "I0", or "I0=Johannes". Returns his name, or "".
static func recruit(what: String, state: GameState, db: CardDatabase) -> String:
	if state == null:
		return ""
	var wanted_name := ""
	var spec := what
	var eq := what.find("=")
	if eq >= 0:
		spec = what.substr(0, eq)
		wanted_name = what.substr(eq + 1).strip_edges()
	var slot := parse(spec)
	if slot.is_empty():
		print("[recruits] '%s' is not a tier and a power. Write it like recruit:I0 or recruit:III3." % what)
		return ""
	if db != null and template_for(String(slot["tier"]), int(slot["power"]), db) == null:
		print("[recruits] There is no plain %s card at Tier %s Power %d to copy. Check recruit_plain_class in Tuning.csv."
			% [db.tune_text("recruit_plain_class", "Normal"), slot["tier"], slot["power"]])
		return ""

	var given := NameBook.take(state, db, wanted_name)
	var have := names(state)
	have.append(given)
	state.set_text(KEY, "|".join(have))
	state.set_text(PREFIX + CardDatabase._normalise(given), "%s|%d" % [slot["tier"], slot["power"]])
	# SIGNED AS WELL, so squad_ownership sees him the moment both are on.
	SquadBook.sign(given, state)
	# ROUND AN: he arrives untrained; the Training Ground gives him a role.
	PlayerRoles.arrive(given, "recruit", state, db)
	print("[recruits] %s joins the base: Tier %s, Power %d." % [given, slot["tier"], slot["power"]])
	StatsRules.get_rules().record("player_recruited", {
		"card": given, "tier": String(slot["tier"]),
	}, state)
	return given


## ROUND AN: sign a player who already HAS a name, tier, power and gender -
## the random first team of a new game (squad_sheet.gd). No template card is
## needed: a Tier IV plain player has none in BasicTeam.csv.
static func enlist(name_text: String, tier: String, power: int, gender: String,
		state: GameState, look: String = "", role: String = "") -> void:
	if state == null or name_text == "" or is_recruit(name_text, state):
		return
	var have := names(state)
	have.append(name_text)
	state.set_text(KEY, "|".join(have))
	state.set_text(PREFIX + CardDatabase._normalise(name_text), "%s|%d|%s|%s" % [tier, power, gender, look])
	NameBook.hold(name_text, state)
	SquadBook.sign(name_text, state)
	# ROUND AN: the starting team are Match Players (starting_team_role).
	if role != "":
		PlayerRoles.set_role(name_text, role, state)
	else:
		PlayerRoles.arrive(name_text, "starting", state, CardDatabase.get_db())
	print("[recruits] %s joins the base: Tier %s, Power %d." % [name_text, tier, power])


## He leaves the base for good. Everything about him goes, and his name is
## free for the next man. Called by `release:` - so releasing a card that is
## NOT a recruit is exactly what it always was.
static func release(name_text: String, state: GameState) -> void:
	if state == null or not is_recruit(name_text, state):
		return
	var wanted := CardDatabase._normalise(name_text)
	var kept: Array[String] = []
	for held in names(state):
		if CardDatabase._normalise(held) != wanted:
			kept.append(held)
	state.set_text(KEY, "|".join(kept))
	state.set_text(PREFIX + wanted, "")
	TransformBook.forget_player(name_text, state)
	PlayerRoles.forget(name_text, state)
	NameBook.give_back(name_text, state)
	print("[recruits] %s has left the base." % name_text)


# =============================================================
#  PUTTING THEM IN THE CARD LIST
# =============================================================

## A card for every recruit, made from his plain template and given his name.
static func cards(state: GameState, db: CardDatabase) -> Array[PlayerData]:
	var out: Array[PlayerData] = []
	if state == null or db == null:
		return out
	for name_text in names(state):
		# ROUND AN: a BREWER is a recruit who only brews. He is never a card.
		if BrewerBook.is_brewer(name_text, state):
			continue
		var slot := String(state.text(PREFIX + CardDatabase._normalise(name_text))).split("|")
		if slot.size() < 2 or not String(slot[1]).is_valid_int():
			continue
		var template := template_for(String(slot[0]), int(String(slot[1])), db)
		var card: PlayerData = null
		if template != null:
			card = template.duplicate(true)
		else:
			# ROUND AN: no plain card at this rung (Tier IV), so make one.
			card = PlayerData.new()
			card.unit_type = db.tune_text("recruit_plain_class", "Normal")
			card.tier = String(slot[0])
			card.base_power_left = int(String(slot[1]))
			card.base_power_right = card.base_power_left
			card.element = "None"
		card.player_name = name_text
		# ROUND AN: a recruit with a gender wears that gender's sprite.
		if slot.size() >= 3 and String(slot[2]) != "":
			# The look saved with the player, else the first of that gender.
			var art := String(slot[3]) if slot.size() >= 4 else ""
			if art == "":
				art = db.tune_text("squad_art_" + String(slot[2]), "").get_slice("|", 0).strip_edges()
			if art != "":
				var found := db._find_texture(art, CardDatabase.PLAYER_ART_DIRS)
				if found != null:
					card.artwork = found
		out.append(card)
	return out


## Add the recruits to the card list - only while `named_recruits` is on.
## Takes the last lot off first, so calling it twice never doubles anybody.
## Returns how many are in.
static func apply_all(db: CardDatabase, state: GameState) -> int:
	remove_all(db)
	if not on(db) or state == null:
		return 0
	for card in cards(state, db):
		db.players.append(card)
		_added.append(card)
	return _added.size()


static func remove_all(db: CardDatabase) -> void:
	if db != null:
		for card in _added:
			db.players.erase(card)
	_added.clear()
