class_name EmblemBook
extends RefCounted

# =============================================================
#  THE EMBLEMS ON THE PITCH — the rules, not the reading
#
#  ============ WHAT YOU ASKED FOR ============
#
#  "Star Units when coming into the field place their emblem, which has the
#   conditions on it. Each Star Player has their own Emblem. Star Players have
#   their normal ability; the Ultimate form is their other side when their
#   Emblem condition is met."
#
#  So an Emblem is no longer something you buy in the talent tree. IT ARRIVES
#  WITH THE STAR. Field the Star and the Emblem is on the bar along the top of
#  the pitch; take the Star out and the Emblem goes with them.
#
#  That is a better deal than what it replaces. The old tree made you collect
#  three matching Stars and then CHOOSE one emblem — which meant two of your
#  three Stars were carrying nothing.
#
#  ============ WHERE THE FILES ARE READ ============
#
#  NOT HERE. `class_book.gd` reads every `<Class> Emblems.csv` and every unit
#  file and holds the roster. This file is the RULES on top of it, and it owns
#  no data of its own.
#
#  That split is deliberate and it is the one I would keep: two readers of the
#  same spreadsheet is two answers to the same question, and the day they
#  disagree nothing tells you which one a screen believed.
#
#  ============ THE THREE RULES ============
#
#  1. A RACE. All three Emblems ride on and all three collect on their Basic
#     side all match. THE FIRST TO MEET ITS CONDITION TURNS OVER, and the
#     other two are held on Basic until the reset. `emblem_race` in
#     Tuning.csv; FALSE lets all three turn over, which is simpler and much
#     more explosive — a real choice, not a safety switch.
#
#  2. ELEMENT FEEDS THE BASIC SIDE, CLASS FULFILS THE CONDITION. A water unit
#     of ANY class counts toward a Lorelei Emblem's Basic side; only a Lorelei
#     can complete the Condition that turns it over. So a mixed water team
#     gets a broader engine and gives up the Ultimate, and a mono-class team
#     gets the Ultimate and a narrower engine. That is the whole reason the
#     other water classes you write later will have somewhere to go.
#     `emblem_element_feeds_basic`, and one Emblem may override it in its own
#     `Basic Feeds` column.
#
#  3. A GOAL ENDS THE RACE. Everything turns back to Basic, the counters the
#     Conditions watch go to zero, and the next race starts level.
#     `emblem_reset_on_goal`.
#
#  ============ THE SWITCH THAT PUTS IT ALL BACK ============
#
#  `emblems_on_field` FALSE and none of this happens: no bar, no race, no
#  turning over. That is how this went in without changing a match you could
#  already play — the only safe way to ship something this size.
# =============================================================

## Save keys. Every one is an ordinary GameState entry, so every one can be
## tested from any spreadsheet in the game with `flag:` or `count:`.
const ASCENDED := "emblem_ascended"        ## text: which Emblem turned over
const FLIPPED_PREFIX := "emblem_flipped_"  ## flag: this one turned over


static func _key(text: String) -> String:
	return CardDatabase._normalise(text)


static func _on() -> bool:
	return _tuned_bool("emblems_on_field", true)


static func _tuned_bool(key: String, fallback: bool) -> bool:
	var db := CardDatabase.get_db()
	if db == null:
		return fallback
	return db.tune_bool(key, fallback)


# =============================================================
#  ASKING IT THINGS — all of it through ClassBook
# =============================================================

## The three emblems of a class, left to right.
static func for_class(class_text: String) -> Array[ClassBook.Emblem]:
	var out := ClassBook.emblems_for(class_text)
	out.sort_custom(func(a: ClassBook.Emblem, b: ClassBook.Emblem) -> bool:
		return a.order < b.order)
	return out


## The emblem a Star Player brings onto the pitch. `null` for a normal unit,
## and for a Star whose Emblem column names something that is not there —
## which is worth finding but not worth stopping a match for.
static func for_star(card: PlayerData) -> ClassBook.Emblem:
	if card == null or not card.is_star():
		return null
	var entry := ClassBook.entry_for(card.active_unit_type())
	if entry == null:
		return null
	return entry.emblems.get(_key(card.emblem_id()))


## THE EMBLEMS A SIDE BRINGS, read off the cards it actually fielded.
##
## This is the whole of "the Star places their emblem": nothing stores a list
## anywhere. It is read off the team sheet every time it is asked for, so a
## substitution changes the bar and there is no second copy to go stale.
static func on_the_field(squad: Array) -> Array[ClassBook.Emblem]:
	var out: Array[ClassBook.Emblem] = []
	if not _on():
		return out
	var seen := {}
	for thing in squad:
		var card := thing as PlayerData
		if card == null:
			continue
		var badge := for_star(card)
		if badge == null:
			continue
		var key := _key(badge.id)
		if seen.has(key):
			continue
		seen[key] = true
		out.append(badge)
	out.sort_custom(func(a: ClassBook.Emblem, b: ClassBook.Emblem) -> bool:
		return a.order < b.order)
	return out


# =============================================================
#  THE TWO RULES THAT DECIDE WHAT A UNIT DOES FOR AN EMBLEM
# =============================================================

## Does this card feed that Emblem's BASIC side?
##
## By default yes if it shares the ELEMENT — so a water unit of any class
## feeds a Lorelei Emblem. `Basic Feeds: class` on the row, or
## `emblem_element_feeds_basic` FALSE in Tuning.csv, narrows it to the class.
static func feeds_basic(card: PlayerData, badge: ClassBook.Emblem) -> bool:
	if card == null or badge == null:
		return false
	if badge.feeds == "any":
		return true
	if badge.feeds == "class" or not _tuned_bool("emblem_element_feeds_basic", true):
		return _key(card.active_unit_type()) == _key(badge.unit_type)
	var element := ClassBook.element_of(badge.unit_type)
	if element == "":
		# A CLASS WITH NO ELEMENT CANNOT SHARE ONE, so the element rule has
		# nothing to say and it falls back to the class. That is what happens
		# for a class whose ClassInfo.csv row has an empty Element column, and
		# it is a sensible state rather than a bug.
		return _key(card.active_unit_type()) == _key(badge.unit_type)
	return _key(card.active_element()) == _key(element)


## Does this card count toward that Emblem's CONDITION — the thing that turns
## it over?
##
## ALWAYS CLASS-ONLY, whatever the Basic rule says. This is the line that
## keeps a mono-class team the only route to an Ultimate, and it is the one
## rule here that no column can loosen. If you ever want to loosen it, loosen
## it on purpose and in one place: right here.
static func feeds_condition(card: PlayerData, badge: ClassBook.Emblem) -> bool:
	if card == null or badge == null:
		return false
	return _key(card.active_unit_type()) == _key(badge.unit_type)


## In words, for a screen: what this card is doing for this Emblem.
static func what_it_does(card: PlayerData, badge: ClassBook.Emblem) -> String:
	if not feeds_basic(card, badge):
		return "nothing — wrong element"
	if not feeds_condition(card, badge):
		return "feeds the Basic side, cannot complete the Condition"
	return "feeds the Basic side and counts toward the Condition"


# =============================================================
#  THE RACE
# =============================================================

## How far along an Emblem is, as {have, need, done, counter}.
##
## READ OUT OF `Turns On` RATHER THAN STORED ANYWHERE. A condition is
## `count:<counter>>=<n>` — which is a counter and a target, everything a
## progress bar needs. So there is no second column to keep in step, and a
## Condition you rewrite tomorrow moves its own bar this afternoon.
static func progress(badge: ClassBook.Emblem, state: GameState) -> Dictionary:
	var out := {"have": 0, "need": 0, "done": false, "counter": ""}
	if badge == null or state == null:
		return out
	var term := badge.turns_on
	out["done"] = term != "" and DialogueGrammar.test(term, state)
	var found := _counter_in(term)
	if found.is_empty():
		return out
	out["counter"] = found["counter"]
	out["need"] = int(found["need"])
	out["have"] = mini(state.count(String(found["counter"])), maxi(int(found["need"]), 1))
	return out


## The first `count:<name><op><n>` in a condition, as {counter, need}.
## Empty when there is none — an Emblem whose Turns On is a flag test has no
## bar to draw, which is fine and is not a complaint.
static func _counter_in(term: String) -> Dictionary:
	for part in term.split(";", false):
		var clean := String(part).strip_edges()
		if not clean.to_lower().begins_with("count:"):
			continue
		var body := clean.substr(clean.find(":") + 1)
		for mark in [">=", "==", ">", "="]:
			var at := body.find(mark)
			if at > 0:
				return {
					"counter": body.substr(0, at).strip_edges(),
					"need": int(body.substr(at + mark.length()).strip_edges()),
				}
	return {}


## Which Emblem, if any, has turned over. "" while the race is still on.
static func ascended(state: GameState) -> String:
	if state == null:
		return ""
	return state.text(ASCENDED, "")


## Is this one face up right now?
static func is_up(badge: ClassBook.Emblem, state: GameState) -> bool:
	if badge == null or state == null or not _on():
		return false
	if not _tuned_bool("emblem_race", true):
		return bool(progress(badge, state)["done"])
	return _key(ascended(state)) == _key(badge.id)


## Is this one held on its Basic side because somebody else got there first?
static func is_locked(badge: ClassBook.Emblem, state: GameState) -> bool:
	if badge == null or not _tuned_bool("emblem_race", true):
		return false
	var winner := ascended(state)
	return winner != "" and _key(winner) != _key(badge.id)


## RUN THE RACE. Call it whenever a counter may have moved — the end of a
## duel, the end of a cycle. Returns the Emblem that turned over on this call,
## or `null` when nothing changed.
##
## Deliberately cheap and deliberately idempotent: calling it twice in a row
## changes nothing the second time, so no caller ever has to remember whether
## it has already been called. That is what lets it be hung off three
## different moments without a flag to coordinate them.
static func settle(squad: Array, state: GameState) -> ClassBook.Emblem:
	if state == null or not _on():
		return null
	var racing := _tuned_bool("emblem_race", true)
	if racing and ascended(state) != "":
		return null
	for badge in on_the_field(squad):
		if not bool(progress(badge, state)["done"]):
			continue
		if state.has_flag(FLIPPED_PREFIX + _key(badge.id)):
			continue
		if racing:
			state.set_text(ASCENDED, badge.id)
		state.set_flag(FLIPPED_PREFIX + _key(badge.id), true)
		print("[emblems] %s ASCENDED — %s" % [badge.id, badge.condition])
		return badge
	return null


## A GOAL ENDS THE RACE. Everything goes back to its Basic side and the
## counters the Conditions watch go to zero, so the next race starts level.
## `emblem_reset_on_goal` FALSE makes an Ultimate last the rest of the match.
static func reset_after_goal(state: GameState) -> void:
	if state == null or not _on():
		return
	if not _tuned_bool("emblem_reset_on_goal", true):
		return
	print("[emblems] a goal — every Emblem back to its Basic side.")
	state.set_text(ASCENDED, "")
	for class_key in ClassBook.classes():
		var entry: ClassBook.ClassEntry = ClassBook.classes()[class_key]
		for badge in for_class(entry.unit_type):
			state.set_flag(FLIPPED_PREFIX + _key(badge.id), false)
			var found := _counter_in(badge.turns_on)
			if not found.is_empty():
				state.set_count(String(found["counter"]), 0)


# =============================================================
#  THE OTHER SIDE OF THE STAR
# =============================================================

## What a Star's card should say right now — its Front Side, or its Ultimate
## Side once its Emblem is up.
##
## ONE PLACE, so the figure on the pitch, the card popup and the hover window
## can never disagree about which face a Star is showing.
static func star_text(card: PlayerData, state: GameState) -> String:
	if card == null:
		return ""
	if card.has_ultimate() and is_up(for_star(card), state):
		return card.ultimate_text
	return card.attack_text


## And which face to draw. Falls back to the front art, so a Star with one
## drawing works — it simply does not change when it turns over.
static func star_art(card: PlayerData, state: GameState) -> Texture2D:
	if card == null:
		return null
	if card.ultimate_artwork != null and is_up(for_star(card), state):
		return card.ultimate_artwork
	return card.artwork


## Is this Star showing its other side right now?
static func star_is_ultimate(card: PlayerData, state: GameState) -> bool:
	return card != null and card.has_ultimate() and is_up(for_star(card), state)


# =============================================================
#  AND CHECKING IT
# =============================================================

## Everything wrong, in words. Empty means the sheets agree.
##
## These are the things a spreadsheet cannot check about itself: that a
## Condition a player can read has a machine condition to go with it, that
## turning an Emblem over does something, that its set exists, and that its
## Star exists. `tools/emblem_check.gd` prints them.
static func problems() -> Array[String]:
	var out: Array[String] = []
	for class_key in ClassBook.classes():
		var entry: ClassBook.ClassEntry = ClassBook.classes()[class_key]
		if entry.emblems.is_empty():
			continue
		# COUNT THE EMBLEMS, not the keys. Each one is filed under its own
		# name and under its Star's, so `emblems.size()` is six for a class
		# of three — `for_class()` walks the names only.
		var many := for_class(entry.unit_type).size()
		if many != 3:
			out.append("%s has %d Emblem(s), not 3. A class is three Stars and each one carries one."
				% [entry.unit_type, many])
		# WHICH STARS ARE HERE, filed under every name they might be looked
		# up by: their own, and whatever their Emblem column says. The emblem
		# row is called "Vassago's Emblem" and the Star is called "Vassago",
		# so matching on one name alone reported every new class as carried
		# by nobody.
		var stars := {}
		for star in entry.stars:
			stars[_key(star.player_name)] = star
			stars[_key(star.emblem_id())] = star
		for badge in for_class(entry.unit_type):
			var who := "%s (%s)" % [badge.id, entry.unit_type]

			if badge.turns_on == "" and badge.condition != "":
				out.append("%s has a Condition written for the player and nothing in Turns On, so the game can never turn it over. It will sit on its Basic side forever."
					% who)
			for complaint in DialogueGrammar.complaints(badge.turns_on, false):
				out.append("%s Turns On: %s" % [who, complaint])
			if badge.ultimate == "":
				out.append("%s has no Ultimate Side, so turning it over does nothing." % who)
			if badge.token == "":
				out.append("%s has no Token. That is the word its nine units make and spend — without one the set has no engine and the Condition will not fill."
					% who)
			if not (stars.has(_key(badge.id)) or stars.has(_key(badge.star))):
				out.append("%s is carried by no Star Player. An Emblem reaches the pitch on a Star and no other way, so this one can never be in a match."
					% who)
			var nine := ClassBook.set_for(entry.unit_type, badge.id)
			if nine == null:
				out.append("%s names the set '%s', and there is no set of that name. Check the Set column against the Set Name column of the unit file."
					% [who, badge.set_id])
			elif nine.cards.size() != 9:
				out.append("%s's set '%s' has %d card(s), not 9."
					% [who, badge.set_id, nine.cards.size()])
	return out
