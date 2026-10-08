extends GutTest

# =============================================================
#  MATCH PLAYERS, ADVENTURE PLAYERS AND BREWERS  (round AN, GUT)
#
#  Every one of your players has one role, chosen at the Training Ground
#  (Training.csv Kind match_player / adventure_player / brewer), and a team
#  is a Match Team or an Adventure Team. A pretend save in memory.
# =============================================================

var db: CardDatabase
var state: GameState


func before_each() -> void:
	db = CardDatabase.get_db()
	BaseRooms.forget()
	state = GameState.new()
	state.set_count("coins", 2000)
	state.unlock("Training Ground")


func _card(name_text: String) -> PlayerData:
	var card := PlayerData.new()
	card.player_name = name_text
	return card


func test_the_starting_team_are_match_players() -> void:
	RecruitBook.enlist("Rolf", "I", 1, "m", state)
	assert_eq(PlayerRoles.role("Rolf", state, db), PlayerRoles.MATCH)


func test_a_player_signed_at_the_club_house_arrives_untrained() -> void:
	var who := RecruitBook.recruit("I0", state, db)
	if who == "":
		pass_test("no plain Tier I Power 0 card to copy")
		return
	assert_eq(PlayerRoles.role(who, state, db), PlayerRoles.NEW)
	assert_false(PlayerRoles.fits(_card(who), "match", state, db), "untrained plays nowhere")
	assert_false(PlayerRoles.fits(_card(who), "adventure", state, db))


func test_training_an_adventure_player_moves_him_to_the_adventure_team() -> void:
	RecruitBook.enlist("Wastl", "II", 2, "m", state, "", "new")
	var cost := int(PlayerRoles.training_row("adventure")["cost"])
	var r := BaseRooms.train_role("Wastl", "adventure", state)
	assert_true(bool(r["ok"]), String(r["why"]))
	assert_eq(state.count("coins"), 2000 - cost)
	assert_true(PlayerRoles.fits(_card("Wastl"), "adventure", state, db))
	assert_false(PlayerRoles.fits(_card("Wastl"), "match", state, db))
	assert_false(bool(BaseRooms.train_role("Wastl", "adventure", state)["ok"]), "trained twice")


func test_a_brewer_plays_for_nobody_and_is_locked_without_quereinsteiger() -> void:
	RecruitBook.enlist("Hias", "I", 3, "m", state, "", "new")
	assert_true(bool(BaseRooms.train_role("Hias", "brewer", state)["ok"]))
	assert_eq(PlayerRoles.role("Hias", state, db), PlayerRoles.BREWER)
	assert_false(PlayerRoles.fits(_card("Hias"), "match", state, db))
	assert_false(bool(BaseRooms.train_role("Hias", "match", state)["ok"]))


func test_a_plain_csv_card_plays_for_both() -> void:
	assert_true(PlayerRoles.fits(_card("Nobody In Particular"), "match", state, db))
	assert_true(PlayerRoles.fits(_card("Nobody In Particular"), "adventure", state, db))


func test_an_old_team_is_a_match_team() -> void:
	var entry := TeamRoster._tidy({"id": "old", "name": "Old", "class": "Normal"})
	assert_eq(String(entry["kind"]), "match")
	assert_eq(String(TeamRoster.blank("Normal", "IV", "adventure")["kind"]), "adventure")


func test_every_role_has_a_training_row() -> void:
	assert_eq(PlayerRoles.offered(), ["match", "adventure", "brewer"] as Array[String])


func test_the_stars_tier_is_never_short_of_rested_players() -> void:
	var was: Variant = db.tuning.get("recovery", null)
	db.tuning["recovery"] = "true"
	var book := TeamRoster.new()
	var entry := TeamRoster.blank("Normal", "IV")
	var why := book.resting(entry, db, state, 1)
	assert_false(why.contains("Tier IV"), why)
	if was == null:
		db.tuning.erase("recovery")
	else:
		db.tuning["recovery"] = was


# ---- round AN, Anthony 8 Oct: some Adventure players to start with, and a
# role is for good until Quereinsteiger ----

func test_the_starting_team_csv_has_adventure_players() -> void:
	var roles := {}
	for row in MenuSupport.read_csv("res://data/" + db.tune_text("starting_team", "StartingTeam.csv")):
		var r := MenuSupport.field(row, "Role").strip_edges().to_lower()
		if r != "":
			roles[r] = int(roles.get(r, 0)) + 1
	assert_gt(int(roles.get("adventure", 0)), 0, "a fresh game needs Adventure Players")
	assert_gt(int(roles.get("match", 0)), 0)


func test_the_starting_team_role_column_is_used() -> void:
	RecruitBook.enlist("Kathi", "I", 1, "f", state, "", "adventure")
	assert_eq(PlayerRoles.role("Kathi", state, db), PlayerRoles.ADVENTURE)


func test_a_trained_player_is_locked_until_quereinsteiger() -> void:
	RecruitBook.enlist("Vevi", "II", 2, "f", state, "", "new")
	assert_false(PlayerRoles.locked("Vevi", state, db), "untrained is never locked")
	assert_true(bool(BaseRooms.train_role("Vevi", "match", state)["ok"]))
	assert_true(PlayerRoles.locked("Vevi", state, db))
	var coins := state.count("coins")
	var r := BaseRooms.train_role("Vevi", "adventure", state)
	assert_false(bool(r["ok"]), "locked without Quereinsteiger")
	assert_eq(state.count("coins"), coins, "nothing paid")
	assert_string_contains(String(r["why"]), "Quereinsteiger")


func test_quereinsteiger_retrains_for_the_high_fee() -> void:
	var fee := int(PlayerRoles.retrain_row()["cost"])
	assert_gt(fee, int(PlayerRoles.training_row("adventure")["cost"]), "the fee is high")
	RecruitBook.enlist("Girgl", "III", 3, "m", state)
	state.unlock("Quereinsteiger")
	assert_true(PlayerRoles.retrain_open(state))
	var r := BaseRooms.train_role("Girgl", "adventure", state)
	assert_true(bool(r["ok"]), String(r["why"]))
	assert_eq(state.count("coins"), 2000 - fee)
	assert_eq(PlayerRoles.role("Girgl", state, db), PlayerRoles.ADVENTURE)


func test_quereinsteiger_takes_a_brewers_apron_off() -> void:
	RecruitBook.enlist("Hias", "I", 3, "m", state, "", "new")
	assert_true(bool(BaseRooms.train_role("Hias", "brewer", state)["ok"]))
	assert_false(bool(BaseRooms.train_role("Hias", "match", state)["ok"]), "locked")
	state.unlock("Quereinsteiger")
	assert_true(bool(BaseRooms.train_role("Hias", "match", state)["ok"]))
	assert_false(BrewerBook.is_brewer("Hias", state))
	assert_eq(PlayerRoles.role("Hias", state, db), PlayerRoles.MATCH)
	assert_true(PlayerRoles.fits(_card("Hias"), "match", state, db))


func test_a_locked_match_player_cannot_slip_into_the_brewery() -> void:
	RecruitBook.enlist("Resi", "II", 2, "f", state)
	assert_false(bool(BaseRooms.train_brewer("Resi", state)["ok"]))
	assert_false(BrewerBook.is_brewer("Resi", state))


func test_a_fresh_games_starting_team_has_adventure_players() -> void:
	SquadSheet.selection_from(db.tune_text("starting_team", "StartingTeam.csv"), db, state, true)
	var count := {}
	for name_text in RecruitBook.names(state):
		var r := PlayerRoles.role(name_text, state, db)
		count[r] = int(count.get(r, 0)) + 1
	assert_eq(int(count.get(PlayerRoles.ADVENTURE, 0)), 4, str(count))
	assert_eq(int(count.get(PlayerRoles.MATCH, 0)), 8, str(count))
