class_name NameBook
extends RefCounted

# =============================================================
#  EVERY PLAYER HAS A NAME OF HIS OWN — data/Names.csv
#
#  ============ WHAT YOU ASKED FOR ============
#
#  "The Goetia names are for the star players. For the other names it would
#   be German names that are common... as the player can recruit multiple
#   players that are Tier I Power 0, they all have to have unique names, and
#   when they are on a team, on the field or in the player's database they
#   keep that name until they are removed from the base entirely."
#
#  ============ HOW A NAME IS CHOSEN ============
#
#      1. A FIRST NAME from the left column that nobody has.     Johannes
#      2. When those run out, a first name AND a surname.        Johannes Bauer
#      3. When even those run out (you would need thousands),    Spieler 1201
#         a number, and the Output panel says to add more names.
#
#  "Nobody has" means: no card in any unit file is called that, and no
#  player at your base is called that. So a recruit is never Gremory, never
#  Müller, and never a second Johannes.
#
#  ============ HOW LONG HE KEEPS IT ============
#
#  For as long as he is at the base. The name is written into the save the
#  moment he arrives and handed back only by release() — `release:Johannes`
#  in any Effects or Do column. Drinking, turning into a Lorelei, being sent
#  off, sitting on the bench: none of those touch his name.
#
#  ============ WHERE IT LIVES ============
#
#  In the save, as one text: `names_held`, separated by |. The same shape as
#  `squad`. Nothing new to learn and readable in the inspector.
# =============================================================

const FILE := "res://data/Names.csv"
const KEY := "names_held"

static var _first: Array[String] = []
static var _last: Array[String] = []
static var _loaded := false


static func forget() -> void:
	_first = []
	_last = []
	_loaded = false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_first = []
	_last = []
	for row in MenuSupport.read_csv(FILE):
		var first := MenuSupport.field(row, "First Name").strip_edges()
		var last := MenuSupport.field(row, "Surname").strip_edges()
		if first != "" and not _first.has(first):
			_first.append(first)
		if last != "" and not _last.has(last):
			_last.append(last)
	if _first.is_empty():
		print("[names] Names.csv has no First Name column, or it is empty. Every recruit will be called Spieler and a number.")
	else:
		print("[names] %d first name(s), %d surname(s)." % [_first.size(), _last.size()])


static func first_names() -> Array[String]:
	_load()
	return _first


static func surnames() -> Array[String]:
	_load()
	return _last


# =============================================================
#  WHO IS ALREADY CALLED WHAT
# =============================================================

## Every name in use, flattened so "Müller" and "müller" are the same name.
static func taken(state: GameState, db: CardDatabase) -> Dictionary:
	var out: Dictionary = {}
	if db != null:
		for card in db.players:
			if card != null:
				out[CardDatabase._normalise(card.player_name)] = true
	for name_text in held(state):
		out[CardDatabase._normalise(name_text)] = true
	return out


## The names the save is holding for players at the base.
static func held(state: GameState) -> Array[String]:
	var out: Array[String] = []
	if state == null:
		return out
	for piece in state.text(KEY).split("|"):
		var clean := String(piece).strip_edges()
		if clean != "" and not out.has(clean):
			out.append(clean)
	return out


static func is_free(name_text: String, state: GameState, db: CardDatabase) -> bool:
	var clean := name_text.strip_edges()
	return clean != "" and not taken(state, db).has(CardDatabase._normalise(clean))


# =============================================================
#  GIVING ONE OUT AND TAKING IT BACK
# =============================================================

## A name nobody has, written into the save straight away so nothing else
## can take it in the meantime. `wanted` is honoured if it is free.
static func take(state: GameState, db: CardDatabase, wanted: String = "") -> String:
	if state == null:
		return ""
	var used := taken(state, db)
	var chosen := ""

	var asked := wanted.strip_edges()
	if asked != "":
		if used.has(CardDatabase._normalise(asked)):
			print("[names] '%s' is already somebody's name, so a fresh one was chosen." % asked)
		else:
			chosen = asked

	if chosen == "":
		var free_first: Array[String] = []
		for first in first_names():
			if not used.has(CardDatabase._normalise(first)):
				free_first.append(first)
		if not free_first.is_empty():
			chosen = free_first.pick_random()

	if chosen == "":
		var pairs: Array[String] = []
		for first in first_names():
			for last in surnames():
				var pair := "%s %s" % [first, last]
				if not used.has(CardDatabase._normalise(pair)):
					pairs.append(pair)
		if not pairs.is_empty():
			chosen = pairs.pick_random()

	if chosen == "":
		var n := held(state).size() + 1
		while used.has(CardDatabase._normalise("Spieler %d" % n)):
			n += 1
		chosen = "Spieler %d" % n
		print("[names] EVERY NAME IN Names.csv IS TAKEN. This one is '%s' - add more rows." % chosen)

	hold(chosen, state)
	return chosen


static func hold(name_text: String, state: GameState) -> void:
	var clean := name_text.strip_edges()
	if clean == "" or state == null:
		return
	var have := held(state)
	if have.has(clean):
		return
	have.append(clean)
	state.set_text(KEY, "|".join(have))


## He has left the base for good. His name is free for the next man.
static func give_back(name_text: String, state: GameState) -> void:
	var clean := name_text.strip_edges()
	if clean == "" or state == null:
		return
	var have := held(state)
	var wanted := CardDatabase._normalise(clean)
	var kept: Array[String] = []
	for name_held in have:
		if CardDatabase._normalise(name_held) != wanted:
			kept.append(name_held)
	if kept.size() == have.size():
		return
	state.set_text(KEY, "|".join(kept))
	print("[names] '%s' is free again." % clean)
