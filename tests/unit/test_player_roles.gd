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
	RecruitBook.enlist("Wastl", "II", 2, "m", state)
	var cost := int(PlayerRoles.training_row("adventure")["cost"])
	var r := BaseRooms.train_role("Wastl", "adventure", state)
	assert_true(bool(r["ok"]), String(r["why"]))
	assert_eq(state.count("coins"), 2000 - cost)
	assert_true(PlayerRoles.fits(_card("Wastl"), "adventure", state, db))
	assert_false(PlayerRoles.fits(_card("Wastl"), "match", state, db))
	assert_false(bool(BaseRooms.train_role("Wastl", "adventure", state)["ok"]), "trained twice")


func test_a_brewer_plays_for_nobody_and_cannot_be_retrained() -> void:
	RecruitBook.enlist("Hias", "I", 3, "m", state)
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
