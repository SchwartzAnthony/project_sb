class_name ClassTree
extends RefCounted

# =============================================================
#  THE CLASS TREE — where a Star becomes a squad
#
#  ============ WHAT YOU ASKED FOR ============
#
#  "Talent Tree: brew recipes, unit-type limits, resources, adventure maps,
#   switches on Star Players, and if you have three matching Stars you get
#   Emblems."
#
#  Four of those six are already a row of Talents.csv and always were —
#  `unlock:Fire Brew` is a brew recipe, `count:res_hops+6` is resources,
#  `unlock:Marshlands` is an adventure map, `count:limit_lorelei+1` is a
#  limit. They needed spreadsheet rows, not code, and they have them.
#
#  THE TWO THAT NEEDED CODE ARE THE STARS AND THE EMBLEMS, and that is what
#  this file is.
#
#  ============ THE SHAPE, WHICH YOUR SPREADSHEETS ALREADY DESCRIBE ============
#
#  A class is ONE STAR SET plus THREE EMBLEM SETS — see class_book.gd. So:
#
#      THREE NODES, one per set of nine.
#
#      Put one of your Star Players into a node
#          -> that set's NINE UNITS become yours to field
#
#      All three nodes filled
#          -> the class section opens. You may open the ELEMENT NODE
#          -> and you may FORGE THE TEAM SPIRIT
#
#  ============ WHAT CHANGED, AND WHY IT IS BETTER ============
#
#  THE EMBLEM IS NOT BOUGHT HERE ANY MORE. It arrives with its Star: field
#  the Star and the Emblem is on the bar along the top of the pitch; take the
#  Star out and the Emblem goes with them. See emblem_book.gd.
#
#  The old tree made you fill three nodes and then CHOOSE ONE emblem, which
#  meant two of your three Stars were carrying nothing — and the choice was
#  made at a menu, before you had played a minute of the match it decided.
#  Now all three ride on, all three collect, and the first to complete its
#  Condition turns over. The choice is made by PLAY.
#
#  So the node that sold you an emblem sells you an ELEMENT instead:
#
#      OPEN WATER (or Open Fire, Open Earth, Open Air)
#          -> you may field units of OTHER classes that share your element
#
#  That is the door the other water classes walk through. A Lorelei Emblem's
#  Basic side is already fed by ANY water unit — this node is what lets you
#  put one on the pitch.
#
#  The tree is therefore not written down anywhere: it is READ OFF THE UNIT
#  SPREADSHEETS. Add a fourth emblem set to a class tomorrow and its tree has
#  four nodes this afternoon, with no second file to keep in step. That is
#  the whole reason there is no ClassNodes.csv — a tree written twice is a
#  tree that will disagree with itself.
#
#  What IS in data/ClassTree.csv is the part the sets cannot tell us: what a
#  node costs, what an emblem costs, what the Team Spirit costs, and which
#  row of Brews.csv the Team Spirit is.
#
#  ============ AN EMBLEM IS A TWO-SIDED CARD ============
#
#      Basic Side     what it does from the moment you choose it
#      Condition      the PROSE. What a player reads
#      Turns On       the same thing in the condition language, so the GAME
#                     can read it. Empty means it never turns over
#      Ultimate Side  what it does afterwards. The basic side stays live
#
#  Two columns for one idea, on purpose. Your Conditions are paragraphs —
#  "If all three Tier I Units that were removed to create Rose Token Units
#  were Lorelei" — and that is exactly right for the card and impossible for
#  a program. So the prose stays for the player and `Turns On` is what the
#  game tests. They are allowed to drift; `tools/class_tree_check.gd` says so
#  when they do.
#
#  ============ IT ADDS, IT DOES NOT TAKE AWAY ============
#
#  `class_tree` in Tuning.csv is TRUE out of the box and everything above is
#  additive: nodes to fill, an emblem to pick, a drink to forge.
#
#  `class_tree_gates_units` is FALSE. That is the subtractive half — the day
#  you turn it on, an emblem set's nine units are NOT yours until its Star is
#  placed. Leaving it off means this whole phase can go in without changing a
#  single match you play today, which is the only safe way to ship a gate.
# =============================================================

const FILE := "res://data/ClassTree.csv"

## One pool of points for both trees. A player has "talent points", not
## "tactics points and class points" — see talent_db.gd.
const POINTS := "talent_points"

## THE SAVE VOCABULARY. Every one of these is an ordinary GameState entry, so
## every one of them can be tested from any spreadsheet in the game.
const STAR_PREFIX := "star_in_"          # text: which Star is in which node
## THE ELEMENT NODE. `element_lorelei` — a flag, because it is bought once
## and never chosen between. The emblem_ key that used to be here is gone:
## nothing chooses an emblem any more, the Stars bring all three.
const ELEMENT_PREFIX := "open_element_"

const SPIRIT_PREFIX := "spirit_"         # flag: the Team Spirit is forged
## Kept for old saves only. Nothing sets it any more: EmblemBook owns the
## turning-over now and uses its own `emblem_flipped_` key. A save made before
## the rework still has these flags and they simply do nothing.
const FLIPPED_PREFIX := "flipped_"
const THREE_OF_A_KIND := "three_of_a_kind"

static var _costs: Dictionary = {}
static var _problems: Array[String] = []
static var _loaded := false


static func forget() -> void:
	_costs = {}
	_problems = []
	_loaded = false


# =============================================================
#  data/ClassTree.csv — the four numbers a class needs
# =============================================================

static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_costs = {}
	_problems = []

	for row in MenuSupport.read_csv(FILE):
		var klass := MenuSupport.field(row, "Class").strip_edges()
		if klass == "":
			continue
		_costs[_key(klass)] = {
			"class": klass,
			"node": maxi(0, MenuSupport.field_int(row, "Node Cost", 1)),
			# `Emblem Cost` became `Element Cost` when emblems stopped being
			# bought. The old name is still read as a fallback so a sheet you
			# have not updated yet keeps working rather than silently costing
			# nothing.
			"element": maxi(0, MenuSupport.field_int(row, "Element Cost",
				MenuSupport.field_int(row, "Emblem Cost", 2))),
			"spirit": maxi(0, MenuSupport.field_int(row, "Spirit Cost", 3)),
			"brew": MenuSupport.field(row, "Spirit Brew").strip_edges(),
			"requires": MenuSupport.field(row, "Requires").strip_edges(),
		}

	if not _costs.has(_key("*")):
		_problems.append("ClassTree.csv has no `*` row. That is the fallback every class without a row of its own uses, so a class you add later would have no costs at all.")


static func problems() -> Array[String]:
	_load()
	return _problems


## The costs for a class, falling back to the `*` row. Never empty.
static func costs_for(unit_type: String) -> Dictionary:
	_load()
	var mine: Dictionary = _costs.get(_key(unit_type), {})
	if not mine.is_empty():
		return mine
	var any: Dictionary = _costs.get(_key("*"), {})
	if not any.is_empty():
		return any
	return {"class": unit_type, "node": 1, "element": 2, "spirit": 3,
		"brew": "", "requires": ""}


## Lowercase, letters and digits only — the SAME rule GameState uses on an
## unlock name. `Rauhnacht-Feuergeister`, `rauhnacht feuergeister` and
## `Rauhnacht_Feuergeister` are one class, not three. Getting this wrong once
## cost me sixteen imaginary problems in the achievement checker.
static func _key(text: String) -> String:
	var out := ""
	for i in text.length():
		var c := text[i].to_lower()
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			out += c
	return out


static func on(db: CardDatabase) -> bool:
	return db == null or db.tune_bool("class_tree", true)


static func gates_units(db: CardDatabase) -> bool:
	return db != null and db.tune_bool("class_tree_gates_units", false)


# =============================================================
#  THE NODES
# =============================================================

## The three nodes of a class, read straight off its emblem sets.
##
## Each one is:
##     set        the EmblemSet — its id, its nine cards
##     emblem     the Emblem card of the same name, or null if none is written
##     star       the name of the Star standing in it, or ""
##     filled     whether one is
##     cards      how many units it opens
static func nodes_for(unit_type: String, state: GameState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var entry := ClassBook.entry_for(unit_type)
	if entry == null:
		return out

	var ids: Array[String] = []
	for key in entry.sets:
		ids.append(String((entry.sets[key] as ClassBook.EmblemSet).id))
	ids.sort()      # ALWAYS THE SAME ORDER on screen, whatever order the CSV loaded in

	for set_id in ids:
		var kit: ClassBook.EmblemSet = entry.sets[CardDatabase._normalise(set_id)]
		var who := star_in(unit_type, set_id, state)
		out.append({
			"set": kit,
			"set_id": set_id,
			"emblem": entry.emblems.get(CardDatabase._normalise(set_id)),
			"star": who,
			"filled": who != "",
			"cards": kit.cards.size(),
		})
	return out


static func _star_slot(unit_type: String, set_id: String) -> String:
	return "%s%s_%s" % [STAR_PREFIX, _key(unit_type), _key(set_id)]


## The name of the Star standing in this node, or "".
static func star_in(unit_type: String, set_id: String, state: GameState) -> String:
	if state == null:
		return ""
	return state.text(_star_slot(unit_type, set_id))


## Is this emblem set's nine units open?
##
## Asked with the ORDINARY unlock words, so a Progression row, a dialogue
## line or an achievement can open a set without knowing this file exists —
## and so a scripted opening can hand you one before you have any Stars.
static func set_is_open(unit_type: String, set_id: String, state: GameState) -> bool:
	if state == null:
		return false
	return state.is_unlocked(unlock_name(unit_type, set_id))


static func unlock_name(unit_type: String, set_id: String) -> String:
	return "%s %s" % [unit_type, set_id]


## The Stars of this class that you may put into a node.
##
## While `squad_ownership` is off that is every Star in the spreadsheets,
## which is what the game has always done. With it on it is the ones you have
## actually signed.
static func stars_you_own(unit_type: String, state: GameState,
		db: CardDatabase) -> Array[PlayerData]:
	var out: Array[PlayerData] = []
	var entry := ClassBook.entry_for(unit_type)
	if entry == null:
		return out
	for star in entry.stars:
		if SquadBook.owns(star, state, db):
			out.append(star)
	return out


## HOW A STAR IS REMEMBERED IN THE SAVE.
##
## Its name AND its card number, because a name on its own is not an
## identity: every Star in Unit_Set_Lorelei.csv is currently called "Unit
## Name", and with names alone the first one placed blocked the other two —
## the tree reported "you have no Star left" with three sitting there. The
## card number is the thing your spreadsheets already guarantee is unique.
static func star_key(star: PlayerData) -> String:
	if star == null:
		return ""
	if star.card_number > 0:
		return "%s#%d" % [star.player_name, star.card_number]
	return star.player_name


## And how it is written on screen: the name, without the bookkeeping.
static func star_label(key: String) -> String:
	var hash_at := key.rfind("#")
	return key.substr(0, hash_at) if hash_at > 0 else key


## Which Stars are already standing in a node of this class.
static func stars_placed(unit_type: String, state: GameState) -> Array[String]:
	var out: Array[String] = []
	for node in nodes_for(unit_type, state):
		var who := String(node["star"])
		if who != "" and not out.has(who):
			out.append(who)
	return out


## Put a Star into a node. Returns {"ok": bool, "why": String}.
##
## One Star, one node. A Star already standing somewhere else cannot be in
## two places, and a node already filled is not swapped by accident — this is
## a decision, and a decision you can undo without thinking is not one.
static func place_star(unit_type: String, set_id: String, star: PlayerData,
		state: GameState, db: CardDatabase) -> Dictionary:
	if state == null or star == null:
		return {"ok": false, "why": "nothing to place"}
	if not on(db):
		return {"ok": false, "why": "the class tree is turned off in Tuning.csv"}
	if star_in(unit_type, set_id, state) != "":
		return {"ok": false, "why": "that node already has a Star in it"}
	if stars_placed(unit_type, state).has(star_key(star)):
		return {"ok": false, "why": "%s is already in another node" % star.player_name}

	var cost := int(costs_for(unit_type)["node"])
	# ============ THE FIRST THREE ARE ON THE HOUSE (round Y) ============
	# A match now needs your Stars placed, and talent points come FROM
	# matches - so a new game could never start. `team_build_free_stars`
	# Stars cost nothing; after that the Node Cost applies as before.
	if db != null and every_star_placed(state) < db.tune_int("team_build_free_stars", 3):
		cost = 0
	if state.count(POINTS) < cost:
		return {"ok": false, "why": "you need %d talent point(s) and have %d"
			% [cost, state.count(POINTS)]}

	state.add_count(POINTS, -cost)
	state.set_text(_star_slot(unit_type, set_id), star_key(star))
	# ============ AND THE NINE UNITS OPEN ============
	state.unlock(unlock_name(unit_type, set_id))
	review(state, db)
	# NOT SAVED HERE. The screen saves, once, after it has told you what
	# happened — because tools/class_tree_check.gd walks the whole tree on a
	# throwaway save, and when this function wrote to disk the checker
	# cheerfully spent the player's real talent points every time it ran.
	return {"ok": true, "why": "%s takes the %s node — its %d units are yours."
		% [star.player_name, set_id, _cards_in(unit_type, set_id)]}


## How many Stars stand in nodes across EVERY class. For the free ones.
static func every_star_placed(state: GameState) -> int:
	if state == null:
		return 0
	var many := 0
	var prefix := CardDatabase._normalise(STAR_PREFIX)
	for key in state.texts.keys():
		if String(key).begins_with(prefix) and String(state.texts[key]).strip_edges() != "":
			many += 1
	return many


static func _cards_in(unit_type: String, set_id: String) -> int:
	var kit := ClassBook.set_for(unit_type, set_id)
	return kit.cards.size() if kit != null else 0


## Are all of this class's nodes filled? The gate on the emblem and the
## Team Spirit, and the thing "three matching Stars" means.
static func all_placed(unit_type: String, state: GameState) -> bool:
	var nodes := nodes_for(unit_type, state)
	if nodes.is_empty():
		return false
	for node in nodes:
		if not bool(node["filled"]):
			return false
	return true


# =============================================================
#  THE ELEMENT NODE — where the other classes of your element come in
#
#  ============ WHAT IT REPLACED ============
#
#  This is where you used to buy an Emblem. Emblems arrive with their Stars
#  now, so the node was free to become the thing the four-element plan
#  actually needs: permission to field units of OTHER classes that share your
#  element.
#
#  It is a FLAG and not a choice. There is one element per class and nothing
#  to pick between, so buying it is a yes and not a menu — which also means it
#  can be handed out by an achievement, a dialogue line or a Progression row
#  with the ordinary unlock words and no knowledge of this file.
# =============================================================

## The unlock an Element node hands over. Anything may test it:
## `unlocked:Open Water`.
static func element_unlock(unit_type: String) -> String:
	var element := ClassBook.element_of(unit_type)
	if element == "":
		return ""
	return "Open %s" % element.capitalize()


static func element_open(unit_type: String, state: GameState) -> bool:
	if state == null:
		return false
	if state.has_flag(ELEMENT_PREFIX + _key(unit_type)):
		return true
	var word := element_unlock(unit_type)
	return word != "" and state.is_unlocked(word)


## Is the node even offered? A class with no Element in ClassInfo.csv has
## nothing to open, and `class_tree_element_node` FALSE turns it off for
## everybody.
static func element_node_offered(unit_type: String, db: CardDatabase) -> bool:
	if db != null and not db.tune_bool("class_tree_element_node", true):
		return false
	return ClassBook.element_of(unit_type) != ""


## Buy it. Returns {"ok": bool, "why": String}.
static func open_element(unit_type: String, state: GameState,
		db: CardDatabase) -> Dictionary:
	if state == null:
		return {"ok": false, "why": "no save"}
	if not element_node_offered(unit_type, db):
		return {"ok": false, "why": "%s has no Element in ClassInfo.csv, so there is nothing to open" % unit_type}
	if element_open(unit_type, state):
		return {"ok": false, "why": "it is already open"}
	if not all_placed(unit_type, state):
		return {"ok": false, "why": "all three nodes need a Star first"}

	var cost := int(costs_for(unit_type)["element"])
	if state.count(POINTS) < cost:
		return {"ok": false, "why": "you need %d talent point(s) and have %d"
			% [cost, state.count(POINTS)]}

	state.add_count(POINTS, -cost)
	state.set_flag(ELEMENT_PREFIX + _key(unit_type), true)
	var word := element_unlock(unit_type)
	if word != "":
		state.unlock(word)
	review(state, db)
	var others := ClassBook.classes_of_element(ClassBook.element_of(unit_type))
	others.erase(unit_type)
	var said := ", ".join(PackedStringArray(others)) if not others.is_empty() \
		else "nothing else yet — write another class of this element and it lands here"
	return {"ok": true, "why": "%s is open. You may field: %s"
		% [word, said]}


## MAY THIS CARD BE FIELDED ALONGSIDE THIS CLASS?
##
## Its own class always. Another class of the same element once the Element
## node is open. Anything else, no.
##
## This is the whole of the cross-class rule and it lives in one function on
## purpose: the day you want to loosen it, loosen it here and every screen
## follows.
static func may_field(card: PlayerData, unit_type: String,
		state: GameState) -> bool:
	if card == null:
		return false
	if _key(card.active_unit_type()) == _key(unit_type):
		return true
	if not element_open(unit_type, state):
		return false
	var mine := ClassBook.element_of(unit_type)
	return mine != "" and _key(card.active_element()) == _key(mine)


# =============================================================
#  THE TEAM SPIRIT
# =============================================================

## The unlock a Team Spirit hands over. Its Brews.csv row asks for exactly
## this in its Requires column.
static func spirit_unlock(unit_type: String) -> String:
	return "Team Spirit %s" % unit_type


static func spirit_forged(unit_type: String, state: GameState) -> bool:
	if state == null:
		return false
	return state.has_flag(SPIRIT_PREFIX + _key(unit_type))


## Forge it. It unlocks a row of Brews.csv and nothing else — so the drink
## itself is written where every other drink is written.
static func forge_spirit(unit_type: String, state: GameState,
		db: CardDatabase) -> Dictionary:
	if state == null:
		return {"ok": false, "why": "no save"}
	if spirit_forged(unit_type, state):
		return {"ok": false, "why": "already forged"}
	if not all_placed(unit_type, state):
		return {"ok": false, "why": "all three nodes need a Star first"}

	var costs := costs_for(unit_type)
	var brew_id := String(costs["brew"])
	if brew_id == "":
		return {"ok": false, "why": "no Spirit Brew is named for %s in ClassTree.csv" % unit_type}

	var cost := int(costs["spirit"])
	# brew_id is not looked up — it is checked. See tools/class_tree_check.gd,
	# which is where "that row does not exist" is caught, before a save does.
	if state.count(POINTS) < cost:
		return {"ok": false, "why": "you need %d talent point(s) and have %d"
			% [cost, state.count(POINTS)]}

	state.add_count(POINTS, -cost)
	state.set_flag(SPIRIT_PREFIX + _key(unit_type), true)
	# ============ ONE NAME, AND THE BREW ROW ASKS FOR IT ============
	#
	# `Team Spirit Lorelei` is unlocked here, and the Brews.csv row named in
	# the Spirit Brew column says `unlocked:Team Spirit Lorelei` in its
	# Requires. Nothing looks the brew up — the two halves meet on a name,
	# the same way every other unlock in the game works, which means you can
	# rewrite the drink completely without touching a line of code.
	state.unlock(spirit_unlock(unit_type))
	review(state, db)
	return {"ok": true, "why": "The Team Spirit is forged. The Pub can pour it."}


# =============================================================
#  THE THINGS THAT HAPPEN BY THEMSELVES
# =============================================================

## Called after anything changes, and when a screen opens. It sets the flags
## that other spreadsheets are waiting on, so nothing else has to remember to.
##
## IDEMPOTENT — it only ever turns things on, so calling it a hundred times
## does nothing a hundred times.
static func review(state: GameState, db: CardDatabase) -> void:
	if state == null or not on(db):
		return

	# ---- THREE OF A KIND ----
	#
	# The `star_collector` achievement has been waiting on this flag since it
	# was written, and this is where it comes true: three Stars of one class
	# standing in that class's three nodes.
	if not state.has_flag(THREE_OF_A_KIND):
		for key in ClassBook.classes():
			var entry: ClassBook.ClassEntry = ClassBook.classes()[key]
			# THREE STARS, not "every node filled". A class that only has one
			# emblem set written so far would otherwise earn three-of-a-kind
			# with a single Star in it, which is not what the words mean.
			if stars_placed(entry.unit_type, state).size() >= 3:
				state.set_flag(THREE_OF_A_KIND, true)
				print("[class tree] Three of a kind: %s." % entry.unit_type)
				break

	# ============ AN EMBLEM NO LONGER TURNS OVER HERE ============
	#
	# It used to: you chose one emblem in this tree, and this loop watched its
	# Turns On and set a flag when it came true, outside any match.
	#
	# That is gone, and the reason is the whole of the rework. An Emblem is a
	# MATCH-TIME thing now — three of them ride onto the pitch with their
	# Stars, they race, one turns over, and a goal puts them all back. None of
	# that is a save-file question, so none of it belongs in the tree.
	#
	# EmblemBook.settle() runs the race and EmblemBook.reset_after_goal()
	# ends it. If you are looking for the code that turns an emblem over,
	# it is there and it is the only copy.


# =============================================================
#  THE GATE ON THE NINE UNITS
# =============================================================

## Trim a list of cards to the ones the tree has opened.
##
## Called by the team builder. While `class_tree_gates_units` is false this
## hands the list straight back, which is why the whole phase can go in
## without changing a match you play today.
##
## A card is kept when:
##     the gate is off                     everything, as it always was
##     it is a Star                        your Stars are never taken away
##     its Set Name is not an emblem set   nothing else is touched
##     that set's node has a Star in it    the nine units are yours
## `force` answers "what WOULD the gate do", for the checker — with the gate
## off the honest answer is always "everything", which measures nothing.
## RETURNS Array[PlayerData], NOT Array — and that typing is not decoration.
## It returned a plain Array first, and assigning one to the team builder's
## `Array[PlayerData]` is refused at runtime: the gate silently did nothing,
## the collection kept every card, and because the gate ships OFF nobody
## would have noticed until the day it was switched on. A throwaway test
## that opened the builder with it forced on is what caught it.
static func gate_cards(cards: Array, state: GameState, db: CardDatabase,
		force: bool = false) -> Array[PlayerData]:
	var out: Array[PlayerData] = []
	if state == null or (not force and not gates_units(db)):
		for thing in cards:
			var keep := thing as PlayerData
			if keep != null:
				out.append(keep)
		return out
	for thing in cards:
		var card := thing as PlayerData
		if card == null:
			continue
		if card.is_star() or card.card_set.strip_edges() == "":
			out.append(card)
			continue
		var kit := ClassBook.set_for(card.unit_type, card.card_set)
		if kit == null:
			out.append(card)      # not an emblem set — not this file's business
			continue
		if set_is_open(card.unit_type, kit.id, state):
			out.append(card)
	return out


## Why a card is missing, in words a screen can print. "" when it is not.
static func why_missing(card: PlayerData, state: GameState, db: CardDatabase) -> String:
	if card == null or not gates_units(db):
		return ""
	var kit := ClassBook.set_for(card.unit_type, card.card_set)
	if kit == null or set_is_open(card.unit_type, kit.id, state):
		return ""
	return "Put a Star in the %s node to field the %s units." % [kit.id, kit.id]
