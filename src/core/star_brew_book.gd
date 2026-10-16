class_name StarBrewBook
extends RefCounted

# =============================================================
#  STAR ELEMENTAL BREWS  (Anthony, 16 Oct)
#
#  ============ WHAT YOU ASKED FOR ============
#
#  "A star element that drops from the end of Adventure bosses (100% first
#   time then 50% on second time, etc.). This star element, when mixed at the
#   pub with the elemental drink, creates a Star Elemental Brew, that when
#   consumed, the player is then permanently a star player for that element
#   (only players that have the tier can have this mix)."
#  "In the pub, a pub option to 'mix drink'."
#  "Any player can become a star player ... if it is passion beers (cannot be
#   no effect beer) they become a plain star player."
#  "If they are wrong Tier they cannot become a Star, period."
#  "Plain star players will just get the passion brew effects but at random,
#   so whenever they are picked ... what is randomly shown for their attack
#   and defend will be what is used. Fully random: the attack only / defend
#   only of the passion brews is removed."
#
#  ============ THE PIECES (all data) ============
#
#    Items.csv   a STAR ELEMENT has Use  star_element:<element>
#                a STAR BREW    has Use  star_brew:<element>
#                (fire, water, earth, air, passion)
#    Drops.csv   the map bosses drop the Star Elements. Column Next Time x:
#                0.5 = the Chance halves every time that boss is beaten.
#    ClassInfo   Element + Star Tier: which class an element makes, and the
#                ONE Tier that may drink it. Lorelei (Water) II, Unkengeister
#                (Air) II, Bergmannlein (Earth) III, Rauhnacht (Fire) IV.
#    Tuning      star_passion_tier: the Tier a Star Passion Brew needs (II,
#                the same Tier as the starting team's plain Stars).
#
#  ============ IN THE SAVE ============
#
#    became_<name>        the Star card he became (TransformBook), so he plays
#                         with that Star's abilities but keeps his own name
#    recruit_star_<name>  he is a Star (RecruitBook)
#    passionmix_<name>    the Passion beers a plain Star was given at the Pub,
#                         "id|id|id". Gone at the final whistle.
# =============================================================

const MIX_PREFIX := "passionmix_"
const ELEMENTS: Array[String] = ["fire", "water", "earth", "air", "passion"]


# =============================================================
#  THE ITEMS
# =============================================================

## The Items.csv row whose Use is "<kind>:<element>", or {}.
static func item_for(kind: String, element: String) -> Dictionary:
	var adb := AdventureDB.get_db()
	if adb == null:
		return {}
	var wanted := "%s:%s" % [kind, element.to_lower()]
	for key in adb.items.keys():
		var item: Dictionary = adb.items[key]
		if String(item.get("use", "")).strip_edges().to_lower() == wanted:
			return item
	return {}


## "fire" for an item whose Use is star_brew:fire. "" if it is not one.
static func element_of(item: Dictionary, kind: String) -> String:
	var use := String(item.get("use", "")).strip_edges().to_lower()
	if not use.begins_with(kind + ":"):
		return ""
	return use.substr(kind.length() + 1).strip_edges()


# =============================================================
#  WHO MAY BECOME WHAT
# =============================================================

## The class an element makes Stars of, from ClassInfo.csv. "" for Passion
## (a plain Star) or an element with no class yet.
static func class_for(element: String) -> String:
	if element.to_lower() == "passion":
		return ""
	for row in MenuSupport.read_csv("res://data/ClassInfo.csv"):
		if MenuSupport.field(row, "Element").strip_edges().to_lower() == element.to_lower():
			return MenuSupport.field(row, "Class").strip_edges()
	return ""


## The one Tier that can drink this element's Star Brew. "" = nobody can.
static func star_tier(element: String, db: CardDatabase) -> String:
	if element.to_lower() == "passion":
		return db.tune_text("star_passion_tier", "II") if db != null else "II"
	var klass := class_for(element)
	if klass == "" or db == null:
		return ""
	return db.star_tier_for_class(klass)


## Why he cannot drink this Star Brew, in a sentence. "" = he can.
static func refusal(card: PlayerData, element: String, state: GameState, db: CardDatabase) -> String:
	if card == null or state == null:
		return "Nobody there."
	if not RecruitBook.is_recruit(card.player_name, state):
		return "%s is not one of your own players." % card.player_name
	var klass := class_for(element)
	if element.to_lower() != "passion" and klass == "":
		return "No class has the %s element yet, so there is no %s Star to become." % [
			element.capitalize(), element.capitalize()]
	var tier := star_tier(element, db)
	if tier == "" or card.get_tier_clean() != tier:
		return "%s is Tier %s. Only a Tier %s player can become a %s Star." % [
			card.player_name, card.get_tier_clean(), tier, element.capitalize()]
	if element.to_lower() == "passion":
		if RecruitBook.is_plain_star(card.player_name, state):
			return "%s is already a Star." % card.player_name
		return ""
	if RecruitBook.is_plain_star(card.player_name, state) \
			and TransformBook.has_turned(card, state):
		return "%s is already a Star (%s)." % [card.player_name, TransformBook.became(card, state)]
	if role_for(card, element, db) == null:
		return "%s has no Tier %s Star to become." % [klass, tier]
	return ""


## The Star card he becomes: the class's Star at his Tier and Power, or the
## nearest Power when none matches.
static func role_for(card: PlayerData, element: String, db: CardDatabase) -> PlayerData:
	var klass := class_for(element)
	if card == null or db == null or klass == "":
		return null
	var best: PlayerData = null
	var gap := 999
	for star in db.stars_for_class(klass):
		if star == card or star.get_tier_clean() != card.get_tier_clean():
			continue
		if TransformBook._changed.has(star):
			continue          # one of yours who became a Star, not a Star card
		var this_gap := absi(star.base_power_left - card.base_power_left)
		if this_gap < gap:
			gap = this_gap
			best = star
	return best


## The line the Pub shows under a card: "Can become a Water Star" once he
## has an element (a beer of that element on him, or his own) and the Tier
## for it. "" when there is nothing to say.
static func hint(card: PlayerData, state: GameState, db: CardDatabase) -> String:
	if card == null or state == null:
		return ""
	var element := card.brew_element.strip_edges().to_lower()
	if element == "" or element == "none":
		element = card.element.strip_edges().to_lower()
	if not ELEMENTS.has(element):
		return ""
	if refusal(card, element, state, db) != "":
		return ""
	return "Can become a %s Star" % element.capitalize()


# =============================================================
#  MIX DRINK  (at the Pub)
# =============================================================

## The bag bottle that holds a beer of this element, or {}. For Passion the
## pool must also have a Passion beer WITH abilities ("cannot be no effect").
static func bottle_for(element: String, state: GameState) -> Dictionary:
	var adb := AdventureDB.get_db()
	if adb == null or state == null:
		return {}
	for key in adb.items.keys():
		var item: Dictionary = adb.items[key]
		var use := String(item.get("use", "")).strip_edges().to_lower()
		if not use.begins_with("brew:pool:") or state.count(String(item["id"])) <= 0:
			continue
		if not BreweryBook.elements_on(String(item["id"]), state).has(element.to_lower()):
			continue
		if element.to_lower() == "passion" and _passion_with_abilities(use.substr(10), state).is_empty():
			continue
		return item
	return {}


static func _passion_with_abilities(pool: String, state: GameState) -> Array[String]:
	var out: Array[String] = []
	for entry in BrewDB.get_db().brews:
		if not String(entry.get("pool", "")).split("|").has(pool.strip_edges().to_lower()):
			continue
		if CardDatabase._normalise(String(entry.get("element", ""))) != "passion":
			continue
		if not DialogueGrammar.test(String(entry["requires"]), state):
			continue
		if String(entry["attack"]).strip_edges() == "" and String(entry["defend"]).strip_edges() == "":
			continue
		out.append(String(entry["id"]))
	return out


## Why this mix cannot be made now. "" = it can.
static func mix_refusal(element: String, state: GameState) -> String:
	var star := item_for("star_element", element)
	var brew := item_for("star_brew", element)
	if star.is_empty() or brew.is_empty():
		return "Items.csv has no Star %s Element or Star %s Brew row." % [
			element.capitalize(), element.capitalize()]
	if state.count(String(star["id"])) <= 0:
		return "You have no %s." % star["name"]
	if bottle_for(element, state).is_empty():
		if element.to_lower() == "passion":
			return "You need a Passion bottle with a Passion beer that does something."
		return "You need a %s bottle from the Brewery." % element.capitalize()
	return ""


## Star Element + a bottle of that element = one Star Brew.
## {"ok", "why", "bottle"}
static func mix(element: String, state: GameState) -> Dictionary:
	var no := mix_refusal(element, state)
	if no != "":
		return {"ok": false, "why": no}
	var star := item_for("star_element", element)
	var brew := item_for("star_brew", element)
	var bottle := bottle_for(element, state)
	BreweryBook.take_bottle_of(String(bottle["id"]), element.to_lower(), state)
	state.add_count(String(star["id"]), -1)
	state.add_count(String(brew["id"]), 1)
	print("[star brew] Mixed a %s from a %s and a %s." % [brew["name"], star["name"], bottle["name"]])
	return {"ok": true, "bottle": bottle,
		"why": "%s + %s = one %s." % [star["name"], bottle["name"], brew["name"]]}


# =============================================================
#  DRINKING IT
# =============================================================

## He drinks a Star Brew and is a Star for good. {"ok", "why"}
static func drink(card: PlayerData, element: String, state: GameState, db: CardDatabase) -> Dictionary:
	var brew := item_for("star_brew", element)
	if brew.is_empty() or state.count(String(brew["id"])) <= 0:
		return {"ok": false, "why": "No Star %s Brew left." % element.capitalize()}
	var no := refusal(card, element, state, db)
	if no != "":
		return {"ok": false, "why": no}
	state.add_count(String(brew["id"]), -1)
	if element.to_lower() == "passion":
		RecruitBook.make_star(card.player_name, state)
		print("[star brew] %s is now a plain Star." % card.player_name)
		return {"ok": true, "why": "%s drinks the %s and is a plain Star for good." % [
			card.player_name, brew["name"]]}
	var role := role_for(card, element, db)
	TransformBook.complete(card, role, state)
	RecruitBook.make_star(card.player_name, state)
	state.set_text(MIX_PREFIX + BrewDB.card_key(card), "")
	print("[star brew] %s is now a %s Star (%s)." % [card.player_name, role.unit_type, role.player_name])
	return {"ok": true, "why": "%s drinks the %s and is a %s Star for good, with %s's abilities." % [
		card.player_name, brew["name"], role.unit_type, role.player_name]}


# =============================================================
#  A PLAIN STAR'S PASSION BEERS
# =============================================================

## A plain Star with no class: the only kind that takes Passion beers.
static func is_plain(card: PlayerData, state: GameState) -> bool:
	return card != null and state != null \
		and RecruitBook.is_plain_star(card.player_name, state) \
		and not TransformBook.has_turned(card, state)


static func mix_of(card: PlayerData, state: GameState) -> Array[String]:
	var out: Array[String] = []
	if card == null or state == null:
		return out
	for piece in state.text(MIX_PREFIX + BrewDB.card_key(card)).split("|", false):
		out.append(String(piece))
	return out


static func add_passion(card: PlayerData, brew_id: String, state: GameState) -> void:
	var list := mix_of(card, state)
	list.append(brew_id)
	state.set_text(MIX_PREFIX + BrewDB.card_key(card), "|".join(list))


## Every ability of every Passion beer he was given, attack or defend alike.
static func abilities_of(card: PlayerData, state: GameState) -> Array[String]:
	var out: Array[String] = []
	for brew_id in mix_of(card, state):
		var entry := BrewDB.get_db().find(brew_id)
		for field in ["attack", "defend"]:
			var id_text := String(entry.get(field, "")).strip_edges()
			if id_text != "":
				out.append(id_text)
	return out


## Roll his attack and defend from that list, fully at random (both can be
## good, both bad). True = he has something.
static func roll(card: PlayerData, state: GameState) -> bool:
	if not is_plain(card, state):
		return false
	var pool := abilities_of(card, state)
	if pool.is_empty():
		return false
	card.brew_attack_ability = pool[randi() % pool.size()]
	card.brew_defend_ability = pool[randi() % pool.size()]
	if card.brew_element == "":
		card.brew_element = "Passion"
	return true


## The final whistle: the Passion beers wear off. Returns how many.
static func clear_all(state: GameState) -> int:
	if state == null:
		return 0
	var doomed: Array[String] = []
	var prefix := MIX_PREFIX.replace("_", "")
	for key in state.texts.keys():
		if String(key).begins_with(prefix):
			doomed.append(String(key))
	for key in doomed:
		state.texts.erase(key)
	return doomed.size()
