class_name PubBook
extends RefCounted

# =============================================================
#  TONIGHT'S TEN — who is allowed a drink
#
#  ============ WHAT YOU ASKED FOR ============
#
#  "The Pub: choose 10 players and give them drinks, else basic units."
#
#  So the Pub is two decisions, not one. First WHO is in the room — ten of
#  them, and the number is `pub_capacity` in Tuning.csv. Then what each of
#  them drinks, which is what the Pub already did.
#
#  Anyone not in the room plays as they are: their printed power, no brew,
#  no borrowed class. That is what "else basic units" means, and it is the
#  reason the choice bites — you have more cards than seats.
#
#  ============ WHERE IT LIVES ============
#
#  In the save, as one text: `pub_ten`, a list of card names separated by |.
#  The same shape SquadBook uses for the players you own, for the same
#  reason: no new save format, and you can read it in the inspector.
#
#  ============ IT IS OFF UNTIL YOU TURN IT ON ============
#
#  `pub_ten` in Tuning.csv is FALSE out of the box. While it is false the
#  room is everybody and the Pub behaves exactly as it always has — you can
#  pour on any card. Turn it on the day the squad is big enough for ten to
#  be a choice rather than a chore.
# =============================================================

const KEY := "pub_ten"


static func on(db: CardDatabase) -> bool:
	return db != null and db.tune_bool("pub_ten", false)


static func capacity(db: CardDatabase) -> int:
	return maxi(1, db.tune_int("pub_capacity", 10)) if db != null else 10


## The names in the room. Empty means nobody has been chosen yet, which is
## not the same as "everybody" — see allowed().
static func names(state: GameState) -> Array[String]:
	var out: Array[String] = []
	if state == null:
		return out
	for piece in state.text(KEY).split("|", false):
		var clean := String(piece).strip_edges()
		if clean != "" and not out.has(clean):
			out.append(clean)
	return out


static func _write(list: Array[String], state: GameState) -> void:
	if state != null:
		state.set_text(KEY, "|".join(list))


## Is this card in the room? While the system is off, everybody is.
static func allowed(card: PlayerData, state: GameState, db: CardDatabase) -> bool:
	if card == null:
		return false
	if not on(db):
		return true
	return names(state).has(card.player_name)


## Put somebody in, or take them out again. Returns {"ok", "why"}.
static func toggle(card: PlayerData, state: GameState, db: CardDatabase) -> Dictionary:
	if card == null or state == null:
		return {"ok": false, "why": "nobody there"}
	var list := names(state)
	if list.has(card.player_name):
		list.erase(card.player_name)
		_write(list, state)
		return {"ok": true, "why": "%s goes home." % card.player_name}

	var room := capacity(db)
	if list.size() >= room:
		return {"ok": false, "why": "the room holds %d, and it is full. Send somebody home first." % room}

	# A CARD WITH A BREW ON IT IS ALREADY DRINKING, so letting it in is free;
	# everybody else takes a seat. Nothing special is needed for that here —
	# it is written down so the next person does not add a special case.
	list.append(card.player_name)
	_write(list, state)
	return {"ok": true, "why": "%s takes a seat. %d of %d."
		% [card.player_name, list.size(), room]}


static func clear(state: GameState) -> void:
	if state != null:
		state.set_text(KEY, "")


## How the screen says it: "7 of 10 seats taken".
static func words(state: GameState, db: CardDatabase) -> String:
	if not on(db):
		return "Everybody may drink — `pub_ten` is off in Tuning.csv."
	return "%d of %d seats taken." % [names(state).size(), capacity(db)]
