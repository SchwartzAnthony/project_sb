class_name PlayerRoles
extends RefCounted

# =============================================================
#  WHAT EACH OF YOUR PLAYERS IS FOR — Match, Adventure or Brewer (round AN)
#
#  ============ WHAT YOU SAID ============
#
#  "The player can train new player units as Adventure Player, Match Player
#   and Brewer Player. There is also a separate Adventure Team and Match
#   Team. So at the building where the Ausbildung is, they have to choose
#   new player units where to send them and what they will be working on."
#
#  So every named player of yours (a recruit) has ONE role:
#
#      match        plays matches: only Match Teams take him
#      adventure    goes on Adventures: only Adventure Teams take him
#      brewer       works the Brewery machines (brewer_book.gd), never plays
#      new          not trained yet: no team takes him until he is
#
#  The roles are rows of data/Training.csv:
#      Kind = match_player       the Match Player row
#      Kind = adventure_player   the Adventure Player row
#      Kind = brewer             the Brewer's Apprenticeship (brewer_book.gd)
#  Their Cost, Currency and Needs are what training him costs.
#
#  A team is a Match Team or an Adventure Team (`kind` in teams.json, see
#  team_roster.gd). A Match Team only lists Match Players, an Adventure Team
#  only Adventure Players. The plain CSV cards are not anybody's players and
#  play for both, as they always did.
#
#  ============ SWITCHES (Tuning.csv) ============
#
#      player_roles         false = nobody has a role, every team takes
#                           everybody, as before
#      new_player_role      what a player signed at the Club House arrives
#                           as (new = untrained)
#      starting_team_role   what the starting team arrives as (match)
#      player_role_default  what a player from an older save, with no role
#                           written down, counts as (match)
#      role_lock            true = a role is for good until Quereinsteiger
#
#  ============ A ROLE IS FOR GOOD (Anthony, 8 Oct) ============
#
#  "Once you pick someone for a role that is stuck, until the player unlocks
#   Quereinsteiger, which then will allow a player to put in a player unit
#   and then retrain them for a high fee."
#
#  An untrained player is trained once, at the role's own price. After that
#  his role is locked. The Training.csv row with Kind = retrain (Quereinsteiger)
#  opens when its Needs are met (the Quereinsteiger achievement) and then
#  retrains anybody, a Brewer too, into any other role for ITS Cost.
#
#  ============ WHERE IT LIVES ============
#
#  In the save: role_<name> = "match" / "adventure" / "new". A brewer is in
#  `brewers` (brewer_book.gd), and that wins over anything written here.
# =============================================================

const PREFIX := "role_"
const MATCH := "match"
const ADVENTURE := "adventure"
const BREWER := "brewer"
const NEW := "new"

## The Training.csv Kind for each role.
const KIND_OF := {"match": "match_player", "adventure": "adventure_player", "brewer": "brewer"}


static func on(db: CardDatabase) -> bool:
	return db != null and db.tune_bool("player_roles", true)


## The save of the game that is running, for code that has no tree to hand.
static func current_state() -> GameState:
	var tree := Engine.get_main_loop() as SceneTree
	return GameState.fetch(tree) if tree != null else null


static func _clean(role: String) -> String:
	var r := role.strip_edges().to_lower()
	if r in ["match", "match_player"]:
		return MATCH
	if r in ["adventure", "adventure_player"]:
		return ADVENTURE
	if r in ["brewer", "brew"]:
		return BREWER
	if r in ["new", "untrained", ""]:
		return NEW
	return NEW


## His role. "" when he is not one of your named players.
static func role(name_text: String, state: GameState, db: CardDatabase = null) -> String:
	if state == null or not RecruitBook.is_recruit(name_text, state):
		return ""
	if BrewerBook.is_brewer(name_text, state):
		return BREWER
	var written := String(state.text(PREFIX + CardDatabase._normalise(name_text))).strip_edges()
	if written == "":
		var fallback := db.tune_text("player_role_default", MATCH) if db != null else MATCH
		return _clean(fallback)
	return _clean(written)


## Write his role down. Brewer goes through brewer_book.gd, not here.
static func set_role(name_text: String, role_text: String, state: GameState) -> void:
	if state == null or name_text == "":
		return
	state.set_text(PREFIX + CardDatabase._normalise(name_text), _clean(role_text))


## Called when a player joins the base. `why` is "recruit" (the Club House
## board) or "starting" (the starting team, the Dev screen).
static func arrive(name_text: String, why: String, state: GameState, db: CardDatabase) -> void:
	if state == null:
		return
	var row := "starting_team_role" if why == "starting" else "new_player_role"
	var given := db.tune_text(row, MATCH if why == "starting" else NEW) if db != null \
		else (MATCH if why == "starting" else NEW)
	set_role(name_text, given, state)


static func forget(name_text: String, state: GameState) -> void:
	if state != null:
		state.set_text(PREFIX + CardDatabase._normalise(name_text), "")


## The words for a role, for any screen.
static func label(role_text: String) -> String:
	match role_text:
		MATCH: return "Match Player"
		ADVENTURE: return "Adventure Player"
		BREWER: return "Brewer"
		NEW: return "Not trained yet"
	return ""


# =============================================================
#  WHICH TEAM TAKES WHOM
# =============================================================

## May this card stand in a team of this kind ("match" or "adventure")?
## A plain CSV card always may. One of your players only in his own kind.
static func fits(card: PlayerData, team_kind: String, state: GameState, db: CardDatabase) -> bool:
	if card == null:
		return false
	if not on(db) or state == null:
		return true
	var mine := role(card.player_name, state, db)
	if mine == "":
		return true
	return mine == team_kind_clean(team_kind)


## Keep only the cards a team of this kind may field.
static func filter(cards: Array[PlayerData], team_kind: String, state: GameState,
		db: CardDatabase) -> Array[PlayerData]:
	if not on(db) or state == null:
		return cards
	var out: Array[PlayerData] = []
	for card in cards:
		if fits(card, team_kind, state, db):
			out.append(card)
	return out


static func team_kind_clean(kind: String) -> String:
	return ADVENTURE if kind.strip_edges().to_lower() in ["adventure", "adventure_player"] else MATCH


## Which kind of team the mode you are about to play needs: the scroll of an
## Adventure run takes an Adventure Team, everything else a Match Team.
static func kind_for_mode(tree: SceneTree) -> String:
	if tree == null:
		return MATCH
	var mode := MatchMode.current(tree)
	return ADVENTURE if String(mode.get("scene", "match")) == "adventure" else MATCH


static func team_label(kind: String) -> String:
	return "Adventure Team" if team_kind_clean(kind) == ADVENTURE else "Match Team"


# =============================================================
#  TRAINING HIM — at the Training Ground
# =============================================================

## The Training.csv row for a role, or {}.
static func training_row(role_text: String) -> Dictionary:
	var kind := String(KIND_OF.get(_clean(role_text), ""))
	for one in BaseRooms.training():
		if String(one["kind"]) == kind:
			return one
	return {}


## The roles the Training Ground offers, in order, that Training.csv has a
## row for.
static func offered() -> Array[String]:
	var out: Array[String] = []
	for r in [MATCH, ADVENTURE, BREWER]:
		if not training_row(r).is_empty():
			out.append(r)
	return out


## The Training.csv row with Kind = retrain (Quereinsteiger), or {}.
static func retrain_row() -> Dictionary:
	for one in BaseRooms.training():
		if String(one["kind"]) == "retrain":
			return one
	return {}


## Is his role locked? True for anyone already trained (Match, Adventure or
## Brewer) while role_lock is on. An untrained player is never locked.
static func locked(name_text: String, state: GameState, db: CardDatabase) -> bool:
	if db != null and not db.tune_bool("role_lock", true):
		return false
	var mine := role(name_text, state, db)
	return mine != "" and mine != NEW


## Is retraining open - the retrain row exists and its Needs are met?
static func retrain_open(state: GameState) -> bool:
	var entry := retrain_row()
	return not entry.is_empty() and DialogueGrammar.test(String(entry["needs"]), state)
