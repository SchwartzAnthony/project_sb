class_name SquadBook
extends RefCounted

# =============================================================
#  WHICH PLAYERS ARE ACTUALLY YOURS
#
#  ============ WHY THIS DID NOT EXIST ============
#
#  Up to now, every card in your unit CSVs belonged to you from the first
#  minute of a new game. That was the right call while the CSVs WERE the
#  game — but it makes four things in the story impossible to write:
#
#      "a new game starts with three Star Players"       you start with all
#      "you need more players before you can go on"      you never do
#      "sign somebody at the end of the season"          nothing to sign
#      "this one is injured and out of the squad"        nothing to take out
#
#  So a save can now hold a list of the cards you own, and an Effects column
#  anywhere in the game can add to it:
#
#      sign:Müller;sign:Weber;sign:Koch
#      release:Müller
#
#  ============ IT IS OFF UNTIL YOU TURN IT ON ============
#
#  `squad_ownership` in Tuning.csv is FALSE out of the box, and while it is
#  false nothing reads the list: every card in your CSVs is yours, exactly as
#  today, and the whole of this file is inert. You can therefore write the
#  `sign:` rows into Progression.csv and Dialogue.csv now, play the game, and
#  see no difference at all — and the day the opening scene is finished you
#  set one row to true and the game starts with three players.
#
#  That order matters. Turning it on before there is a scene that signs
#  anybody would start a new game with a squad of nobody.
#
#  ============ WHERE IT LIVES ============
#
#  In the save, as one text: `squad`, a list of card names separated by |.
#  Same as everything else, no new save format, readable in the inspector.
# =============================================================

const KEY := "squad"


static func on(db: CardDatabase) -> bool:
	return db != null and db.tune_bool("squad_ownership", false)


## The names you own. Empty while the system is off, which is not the same as
## "you own nobody" — see owns().
static func names(state: GameState) -> Array[String]:
	var out: Array[String] = []
	if state == null:
		return out
	for piece in state.text(KEY).split("|"):
		var clean := String(piece).strip_edges()
		if clean != "" and not out.has(clean):
			out.append(clean)
	return out


static func sign(card_name: String, state: GameState) -> void:
	var clean := card_name.strip_edges()
	if clean == "" or state == null:
		return
	var have := names(state)
	if have.has(clean):
		return
	have.append(clean)
	state.set_text(KEY, "|".join(have))
	print("[squad] Signed %s. Squad is now %d." % [clean, have.size()])


static func release(card_name: String, state: GameState) -> void:
	var clean := card_name.strip_edges()
	if clean == "" or state == null:
		return
	var have := names(state)
	if not have.has(clean):
		return
	have.erase(clean)
	state.set_text(KEY, "|".join(have))
	print("[squad] Released %s. Squad is now %d." % [clean, have.size()])


## DO YOU OWN THIS CARD? True for everything while `squad_ownership` is off,
## which is what makes this safe to call from anywhere today.
static func owns(card: PlayerData, state: GameState, db: CardDatabase) -> bool:
	if not on(db):
		return true
	if card == null:
		return false
	var wanted := CardDatabase._normalise(card.player_name)
	for held in names(state):
		if CardDatabase._normalise(held) == wanted:
			return true
	return false


## Your cards, out of a list. The one call a screen needs.
static func mine(cards: Array, state: GameState, db: CardDatabase) -> Array:
	if not on(db):
		return cards
	var out: Array = []
	for card in cards:
		if owns(card, state, db):
			out.append(card)
	return out


## A line for a screen: "9 players" — or, while ownership is off, "".
static func words(state: GameState, db: CardDatabase) -> String:
	if not on(db):
		return ""
	var many := names(state).size()
	return "%d player%s signed" % [many, "" if many == 1 else "s"]
