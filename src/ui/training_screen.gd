class_name TrainingScreen
extends SceneRoom

# =============================================================
#  THE TRAINING GROUND — the old Turnhalle  (round AN, Anthony 10 Oct: look B)
#
#      AUSBILDUNG          gym kit on the floor, one thing per Training.csv
#                          row with Kind = ausbildung: the handball goal and
#                          gloves (keepers), the vaulting horse (legs), the
#                          climbing ropes (nerve)
#      THE MINI-GAMES      brewery things brought into the gym, one per
#                          Kind = minigame row (a vat for that Brewery
#                          section): the malt heap, the grain mill, the
#                          lauter tub, the brew kettle, the cellar barrels
#      THE ROLES           kit on the wall hooks: the football shirt (Match
#                          Player), the rucksack (Adventure Player), the
#                          brewer's apron (Brewer). Click one: who to train
#      THE TEAM SHEET      the blackboard: every player, his role, and
#                          retraining once Quereinsteiger is open
#
#  Taken trainings stand in full colour; ones you may not buy yet are grey
#  with a padlock; the rest are lit, with a price card. Every place and
#  picture: data/TrainingLayout.csv (`training:<ID>` rows, `role:<role>`
#  rows). The rules are base_rooms.gd and player_roles.gd. The Head Coach
#  explains it the first time (Guide.csv training_explain).
# =============================================================

const LAYOUT_FILE := "res://data/TrainingLayout.csv"


func _layout_file() -> String:
	return LAYOUT_FILE


func _guide_screen() -> String:
	return "training"


func _status_words() -> String:
	var counts := {"ausbildung": [0, 0], "minigame": [0, 0]}
	for entry in BaseRooms.training():
		var kind := String(entry["kind"])
		if not counts.has(kind):
			continue
		counts[kind][1] += 1
		if BaseRooms.trained(String(entry["id"]), state):
			counts[kind][0] += 1
	var waiting := 0
	for who in RecruitBook.names(state):
		if PlayerRoles.role(who, state, db) == PlayerRoles.NEW:
			waiting += 1
	return "AUSBILDUNG %d of %d    MINI-GAMES %d of %d    %d player(s) waiting for a role    %d coins" % [
		counts["ausbildung"][0], counts["ausbildung"][1], counts["minigame"][0], counts["minigame"][1],
		waiting, ShopBook.purse("coins", state)]


func _fill() -> void:
	_fill_trainings()
	if PlayerRoles.on(db) and not PlayerRoles.offered().is_empty():
		_fill_roles()


# ---- AUSBILDUNG AND THE MINI-GAMES ----------------------------

func _fill_trainings() -> void:
	for entry in BaseRooms.training():
		var kind := String(entry["kind"])
		if not kind in ["ausbildung", "minigame"]:
			continue
		var id_text := String(entry["id"])
		var row := "training:" + id_text.to_lower()
		if not has_part(row):
			continue
		var name_text := String(entry["name"])
		if String(entry["section"]) != "":
			var section := BreweryBook.section(String(entry["section"]))
			if not section.is_empty():
				name_text += " - " + String(section["name"])
		var gives := BaseRooms.effect_words(String(entry["effect"]))
		if BaseRooms.trained(id_text, state):
			thing(row, null, "done", [name_text, "Taken.", gives],
				func() -> void: tell("%s is taken." % name_text, true))
			continue
		var needs := String(entry["needs"])
		if not DialogueGrammar.test(needs, state):
			var why := DialogueGrammar.describe(needs)
			thing(row, null, "dim", [name_text, "LOCKED", why],
				func() -> void: tell("%s is locked. %s" % [name_text, why], false), true)
			continue
		var price := int(entry["cost"])
		var cur := String(entry["currency"])
		var kit := thing(row, null, "open", [name_text + "    " + price_words(price, cur), gives], _train.bind(id_text))
		if kit != null:
			card(short_price(price, cur), kit, can_pay(price, cur), _train.bind(id_text))


func _train(id_text: String) -> void:
	say(BaseRooms.train(id_text, state))


# ---- THE ROLES ON THE HOOKS, AND THE TEAM SHEET --------------

func _fill_roles() -> void:
	for role_text in PlayerRoles.offered():
		var row := "role:" + role_text
		if not has_part(row):
			continue
		var entry := PlayerRoles.training_row(role_text)
		var waiting := _who_can_take(role_text).size()
		thing(row, null, "open" if waiting > 0 else "dim",
			[PlayerRoles.label(role_text) + "    " + _price_of(entry), _role_words(role_text),
				"%d player(s) could take it" % waiting],
			_show_role.bind(role_text))
	thing("team_sheet", null, "open", ["The team sheet", "every player and his role",
		_retrain_words()], _show_team_sheet)


func _role_words(role_text: String) -> String:
	match role_text:
		PlayerRoles.MATCH:
			return "plays in your Match Teams"
		PlayerRoles.ADVENTURE:
			return "plays in your Adventure Teams"
		PlayerRoles.BREWER:
			return "works the Brewery machines, never plays again"
	return ""


func _retrain_words() -> String:
	var retrain := PlayerRoles.retrain_row()
	if retrain.is_empty() or not db.tune_bool("role_lock", true):
		return ""
	if PlayerRoles.retrain_open(state):
		return "%s: retrain anybody for %s" % [retrain["name"], _price_of(retrain)]
	return "A role is for good until %s opens" % retrain["name"]


## The players this role could go to now.
func _who_can_take(role_text: String) -> Array[String]:
	var out: Array[String] = []
	for who in RecruitBook.names(state):
		var mine := PlayerRoles.role(who, state, db)
		if mine == role_text:
			continue
		if PlayerRoles.locked(who, state, db) and not PlayerRoles.retrain_open(state):
			continue
		if mine == PlayerRoles.BREWER and not PlayerRoles.locked(who, state, db):
			continue
		out.append(who)
	return out


func _show_role(role_text: String) -> void:
	var entries: Array = []
	for who in _who_can_take(role_text):
		entries.append(_player_entry(who, [role_text]))
	show_sheet("TRAIN AS %s" % PlayerRoles.label(role_text).to_upper(), entries)


func _show_team_sheet() -> void:
	var order: Array[String] = []
	# Untrained first: they are the ones waiting for you.
	for want in [PlayerRoles.NEW, PlayerRoles.MATCH, PlayerRoles.ADVENTURE, PlayerRoles.BREWER]:
		for who in RecruitBook.names(state):
			if PlayerRoles.role(who, state, db) == want:
				order.append(who)
	var entries: Array = []
	for who in order:
		entries.append(_player_entry(who, PlayerRoles.offered()))
	show_sheet("THE TEAM SHEET", entries)


## One player on the paper list, with a button per role he could take.
func _player_entry(who: String, roles: Array) -> Dictionary:
	var mine := PlayerRoles.role(who, state, db)
	var power := BrewerBook.efficiency(who, state)
	var sub := "Tier %s  ·  P:%d  ·  %s" % [BrewerBook.tier(who, state), power, PlayerRoles.label(mine)]
	if mine == PlayerRoles.BREWER:
		sub += "  ·  %d%% at a machine" % BrewerBook.success_for(power)
	var left := RecoveryBook.turns_left_name(who, state)
	if left > 0:
		sub += "  ·  asleep, %d to go" % left
	var locked := PlayerRoles.locked(who, state, db)
	var buttons: Array = []
	var short := {"match": "Match", "adventure": "Adventure", "brewer": "Brewer"}
	if not (locked and not PlayerRoles.retrain_open(state)) and not (mine == PlayerRoles.BREWER and not locked):
		for role_text in roles:
			if role_text == mine:
				continue
			var entry := PlayerRoles.training_row(String(role_text))
			var pay := PlayerRoles.retrain_row() if locked else entry
			if pay.is_empty():
				continue
			buttons.append({
				"label": "%s%s %s" % ["Retrain: " if locked else "", short.get(role_text, role_text), _price_of(pay)],
				"ok": can_pay(int(pay["cost"]), String(pay["currency"])) and DialogueGrammar.test(String(entry["needs"]), state),
				"do": _train_role.bind(who, String(role_text)),
			})
	elif locked:
		sub += "  ·  role locked"
	return {"words": who, "sub": sub, "buttons": buttons}


func _price_of(entry: Dictionary) -> String:
	if entry.is_empty() or int(entry["cost"]) <= 0:
		return "free"
	return short_price(int(entry["cost"]), String(entry["currency"]))


func _train_role(who: String, role_text: String) -> void:
	say(BaseRooms.train_role(who, role_text, state))
