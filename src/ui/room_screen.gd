class_name RoomScreen
extends Control

# =============================================================
#  THE ROOMS AND THE ACHIEVEMENT BOARD — one script, several scenes
#
#  ROUND AN (Anthony, 10 Oct): THE DORMS LEFT. They are a picture of rooms
#  and beds now, with their own screen - src/ui/dorms_screen.gd.
#
#  ============ WHY ONE SCRIPT ============
#
#  The Achievement board, the Dorms, the Club House, the Trophy Room and the
#  Training Ground are the same screen five times: a line of explanation, a
#  list read out of a spreadsheet, and sometimes a button on each row. Five
#  files would have been five places for the frame to drift apart.
#
#  So there is one script and five one-line scenes, each setting `room`:
#
#      src/ui/rooms/achievements.tscn    room = "achievements"
#      src/ui/rooms/clubhouse.tscn       room = "clubhouse"  (the upgrade shop)
#      src/ui/rooms/trophies.tscn        room = "trophies"
#      src/ui/rooms/training.tscn        room = "training"
#
#  ADDING A SIXTH ROOM is a scene file, a word in the match below, and a
#  `_fill_<word>` function. Nothing else moves.
#
#  ============ THEY ALL OPEN AS WINDOWS ============
#
#  Over the base, never instead of it — see base_window.gd. They still work
#  full-screen if something says `goto:dorms`, which is why the background
#  and the Back button are still in here behind a flag.
# =============================================================

## Which room this scene is. Set in the .tscn, not in code.
@export var room: String = "achievements"

var db: CardDatabase
var state: GameState

var _intro: Label
var _list: VBoxContainer
var _status: Label


func _ready() -> void:
	var windowed := MenuSupport.in_a_window(self)
	if not windowed:
		MenuEscape.install(self)
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	db = CardDatabase.get_db()
	state = GameState.fetch(get_tree())
	# A ROOM IS A GOOD MOMENT TO CHECK. You may have earned something on the
	# way here, and a board that shows yesterday's answer is worse than none.
	AchievementBook.review(state)

	_build_chrome(windowed)
	_rebuild()


# =============================================================
#  CHROME
# =============================================================

func _build_chrome(windowed: bool) -> void:
	if not windowed:
		var fill := ColorRect.new()
		fill.color = MenuSupport.COLOUR_BACKGROUND
		fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(fill)

	var page := VBoxContainer.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_theme_constant_override("separation", 8)
	add_child(page)

	if not windowed:
		var title := MenuSupport.heading(_title().to_upper(), 30, MenuSupport.COLOUR_ACCENT)
		page.add_child(title)

	_intro = Label.new()
	_intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_intro.add_theme_font_size_override("font_size", 15)
	_intro.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	page.add_child(_intro)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(0, 30)
	_status.add_theme_font_size_override("font_size", 15)
	_status.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	page.add_child(_status)

	if not windowed:
		var back := MenuSupport.icon_button("◇", "Back to the base", Vector2(200, 42))
		back.add_theme_stylebox_override("normal",
			MenuSupport.panel_style(MenuSupport.COLOUR_PANEL, MenuSupport.COLOUR_ACCENT))
		back.pressed.connect(func() -> void:
			state.save_to_disk()
			ScenePaths.go_back(get_tree(), ScenePaths.BASE))
		page.add_child(back)


func _title() -> String:
	match room:
		"clubhouse": return "The Club House"
		"trophies": return "The Trophy Room"
		"training": return "The Training Ground"
		"stadium": return "The Stadium"
		_: return "Achievements"


# =============================================================
#  FILLING IT
# =============================================================

func _rebuild() -> void:
	for child in _list.get_children():
		child.queue_free()
	match room:
		"clubhouse": _fill_clubhouse()
		"trophies": _fill_trophies()
		"training": _fill_training()
		"stadium": _fill_stadium()
		_: _fill_achievements()


# ---- ACHIEVEMENTS -------------------------------------------

func _fill_achievements() -> void:
	var board := AchievementBook.board(state)
	_intro.text = "%d of %d earned. Everything in this game is unlocked here first — a room, a Brewery section, a brew, an emblem, a floodlight." % [
		AchievementBook.earned_count(state), AchievementBook.rows().size()]
	for row in board:
		var got := bool(row["earned"])
		var line := _row_frame(got)
		var words := _row_words(line)
		words.add_child(_name_label(String(row["name"]), got))
		words.add_child(_small(String(row["description"])))
		if got:
			var hands: Array = row["unlocks"]
			if not hands.is_empty():
				words.add_child(_small("Opened: " + ", ".join(PackedStringArray(hands))))
		# ROUND AN: an achievement can also put an upgrade on sale at the
		# Club House. It grants the right to buy, never the upgrade itself.
		var wares: Array[String] = []
		for upgrade in BaseRooms.upgrades_from(String(row["id"])):
			wares.append(String(upgrade["name"]))
		if not wares.is_empty():
			words.add_child(_small(("On sale at the Club House: " if got
				else "Earn it to buy at the Club House: ") + ", ".join(PackedStringArray(wares))))
		else:
			words.add_child(_small(DialogueGrammar.describe(String(row["needs"]))))


# ---- THE CLUB HOUSE -----------------------------------------
#
# ROUND AN (Anthony): THE UPGRADE SHOP. An achievement only grants the right
# to buy an upgrade; it is bought here (data/Upgrades.csv). The recruitment
# board stays underneath. Resting moved to the Dorms.

func _fill_clubhouse() -> void:
	var for_sale := 0
	var all := BaseRooms.upgrades()
	for entry in all:
		if BaseRooms.upgrade_state(entry, state) == "for_sale":
			for_sale += 1
	_intro.text = "Keys and upgrades for the club. An achievement gives you the right to buy one; the money is yours to find. A building or a Brewery machine opens only with its key. %d on sale now." % for_sale

	if all.is_empty():
		_list.add_child(_small("Nothing to sell. Add rows to data/Upgrades.csv."))
	# ROUND AN: THE KEYS FIRST — a building or a Brewery machine opens only
	# with its key. Then the upgrades. Each list: on sale, locked, owned.
	for shelf in ["key", "upgrade"]:
		var any_here := false
		for entry in all:
			if (String(entry["kind"]) == "key") == (shelf == "key"):
				any_here = true
		if not any_here:
			continue
		_list.add_child(MenuSupport.heading("KEYS" if shelf == "key" else "UPGRADES",
			17, MenuSupport.COLOUR_ACCENT))
		_fill_shelf(all, shelf)

	# ROUND AH (phase P3): THE RECRUITMENT BOARD - see recruit_board.gd and
	# data/RecruitBoard.csv.
	_fill_recruit_board()


func _fill_shelf(all: Array[Dictionary], shelf: String) -> void:
	for kind in ["for_sale", "locked", "bought"]:
		for entry in all:
			if (String(entry["kind"]) == "key") != (shelf == "key"):
				continue
			if BaseRooms.upgrade_state(entry, state) != kind:
				continue
			var line := _row_frame(kind != "locked")
			var words := _row_words(line)
			words.add_child(_name_label(String(entry["name"]), kind != "locked"))
			words.add_child(_small(String(entry["description"])))
			match kind:
				"bought":
					words.add_child(_small("Bought."))
				"locked":
					words.add_child(_small("LOCKED — " + BaseRooms.upgrade_lock_words(entry, state)))
				_:
					var cur := ShopBook.currency(String(entry["currency"]))
					var price := "%d %s" % [int(entry["cost"]), cur.get("name", entry["currency"])] \
						if int(entry["cost"]) > 0 else "Free"
					line.add_child(_buy_button("Buy · " + price,
						_can_pay(int(entry["cost"]), String(entry["currency"])),
						_buy_upgrade.bind(String(entry["id"]))))


func _buy_upgrade(id_text: String) -> void:
	_say(BaseRooms.buy_upgrade(id_text, state))


# ---- THE RECRUITMENT BOARD (round AH, phase P3) -------------

func _fill_recruit_board() -> void:
	if not RecruitBoard.on(db):
		return
	var coins := ShopBook.purse("coins", state)
	var free := RecruitBoard.beds_free(state, db)
	_list.add_child(MenuSupport.heading("THE RECRUITMENT BOARD", 17, MenuSupport.COLOUR_ACCENT))
	_list.add_child(_small("Plain players looking for a club. Sign one and he joins under his own name; at the Pub a brew turns him into a class. New faces after every match.  You have %d coins · beds for %d more recruit(s)." % [coins, maxi(free, 0)]))
	var list := RecruitBoard.offers(state, db)
	for i in list.size():
		var entry: Dictionary = list[i]
		var row: Dictionary = entry["row"]
		var kind := String(entry["state"])
		var line := _row_frame(kind == "open")
		var words := _row_words(line)
		match kind:
			"open":
				words.add_child(_name_label("%s  ·  Tier %s  ·  P:%d" % [entry["name"], entry["tier"], int(entry["power"])], true))
				words.add_child(_small("A plain player. Brew him at the Pub to give him a class."))
				var cur := ShopBook.currency(String(row["currency"]))
				var price := "%d %s" % [int(row["cost"]), cur.get("name", row["currency"])] if int(row["cost"]) > 0 else "Free"
				line.add_child(_buy_button("Sign · " + price,
					_can_pay(int(row["cost"]), String(row["currency"])) and free > 0,
					_sign_recruit.bind(i)))
			"signed":
				words.add_child(_name_label("Tier %s  ·  signed" % entry["tier"], false))
				words.add_child(_small("Somebody new is up after the next match."))
			_:
				words.add_child(_name_label("Tier %s  ·  LOCKED" % entry["tier"], false))
				words.add_child(_small(DialogueGrammar.describe(String(row["requires"]))))
	var reroll := db.tune_int("recruit_board_reroll_cost", 10)
	if reroll > 0:
		var line := _row_frame(false)
		var words := _row_words(line)
		words.add_child(_small("Nobody you like? Put new men up now."))
		line.add_child(_buy_button("New board · %d coins" % reroll, coins >= reroll, _reroll_board))

	var mine := RecruitBook.names(state)
	if not mine.is_empty():
		_list.add_child(MenuSupport.heading("YOUR RECRUITS", 17, MenuSupport.COLOUR_ACCENT))
		for who in mine:
			var line := _row_frame(true)
			var words := _row_words(line)
			var turned := state.text(TransformBook.BECAME_PREFIX + CardDatabase._normalise(who))
			words.add_child(_name_label(who, true))
			words.add_child(_small(("Brewed at the Pub - he plays as %s's double now." % turned) if turned != ""
				else "Still a plain player - the Pub can brew him into a class."))
			line.add_child(_buy_button("Release", true, _release_recruit.bind(who)))


func _sign_recruit(index: int) -> void:
	_say(RecruitBoard.sign(index, state, db))


func _reroll_board() -> void:
	_say(RecruitBoard.reroll(state, db))


func _release_recruit(who: String) -> void:
	_say(RecruitBoard.release(who, state))


# ---- THE TROPHY ROOM ----------------------------------------

func _fill_trophies() -> void:
	var many := BaseRooms.trophies_won(state)
	_intro.text = "%d of %d on the shelf. A trophy is a row of data/Trophies.csv and a condition — it does not have to come from a competition." % [
		many, BaseRooms.trophies().size()]
	for cup in BaseRooms.trophies():
		var got := BaseRooms.won(cup, state)
		var line := _row_frame(got)
		var words := _row_words(line)
		words.add_child(_name_label(String(cup["name"]), got))
		if got:
			words.add_child(_small("Won." + ("" if String(cup["competition"]) == ""
				else "  %s." % cup["competition"])))
		else:
			words.add_child(_small(DialogueGrammar.describe(String(cup["won_when"]))))


# ---- THE STADIUM --------------------------------------------

func _fill_stadium() -> void:
	# NOTHING IS BOUGHT IN HERE. Every layer of the ground is unlocked by an
	# achievement, which is the rule the whole game runs on — so this room is
	# a READ-OUT, not a shop. What it is for is telling you what your ground
	# would look like if you went and earned the next one.
	var layers := StadiumBook.layers()
	var on := 0
	for layer in layers:
		if StadiumBook.allowed(layer, state):
			on += 1
	_intro.text = "%d of %d layer(s) showing. Your ground is drawn from data/Stadium.csv, back to front — the stadium behind, then the crowd, then the grass, then the lights over everything." % [
		on, layers.size()]

	for layer in layers:
		var showing := StadiumBook.allowed(layer, state)
		var drawn := String(layer["image"]) != ""
		var line := _row_frame(showing and drawn)
		var words := _row_words(line)
		var box: Vector2 = layer["size"]
		words.add_child(_name_label("%s  ·  %d x %d"
			% [layer["layer"], int(box.x), int(box.y)], showing and drawn))

		if not showing:
			var door := _who_opens(String(layer["requires"]))
			if door == "":
				words.add_child(_small("LOCKED — " + DialogueGrammar.describe(String(layer["requires"]))))
			else:
				words.add_child(_small("LOCKED — %s" % door))
		elif not drawn:
			# UNLOCKED AND NOT DRAWN is the ordinary state of a game being
			# made, and it is worth saying out loud rather than showing an
			# empty row that looks broken.
			words.add_child(_small("Open, and nothing drawn yet. Put a PNG in assets/field/ and name it in the Image column."))
		else:
			words.add_child(_small("Showing: %s.png  ·  parallax %.2f"
				% [layer["image"], float(layer["parallax"])]))


## Which achievement opens a Stadium layer, in words. Same question the
## Brewery map asks about its sections — and the same answer: nothing stores
## it, the board is asked who hands out the name.
func _who_opens(requires: String) -> String:
	for part in requires.split(";", false):
		var clean := String(part).strip_edges()
		if not clean.to_lower().begins_with("unlocked:"):
			continue
		var wanted := clean.substr(clean.find(":") + 1).strip_edges()
		for entry in AchievementBook.rows():
			for handed in entry["unlocks"]:
				if MenuSupport.normalise(String(handed)) == MenuSupport.normalise(wanted):
					return "%s: %s" % [entry["name"], entry["description"]]
	return ""


# ---- THE TRAINING GROUND ------------------------------------

func _fill_training() -> void:
	_intro.text = "Ausbildung trains a number for the whole side. A mini-game automates one Brewery section — today it buys that section another vat, which is the foundation the played game will sit on. And here your players are trained as MATCH, ADVENTURE or BREWER players."
	for kind in ["ausbildung", "minigame"]:
		var heading := MenuSupport.heading(
			"AUSBILDUNG" if kind == "ausbildung" else "THE FIVE MINI-GAMES",
			17, MenuSupport.COLOUR_ACCENT)
		_list.add_child(heading)
		for entry in BaseRooms.training():
			if String(entry["kind"]) != kind:
				continue
			var taken := BaseRooms.trained(String(entry["id"]), state)
			var line := _row_frame(taken)
			var words := _row_words(line)
			var label := String(entry["name"])
			if String(entry["section"]) != "":
				label += "  ·  %s" % entry["section"]
			words.add_child(_name_label(label, taken))
			words.add_child(_small(_effect_words(String(entry["effect"]))))
			if taken:
				words.add_child(_small("Taken."))
			else:
				words.add_child(_small(DialogueGrammar.describe(String(entry["needs"]))))
				line.add_child(_buy_button("%d %s" % [int(entry["cost"]), entry["currency"]],
					_can_pay(int(entry["cost"]), String(entry["currency"]))
						and DialogueGrammar.test(String(entry["needs"]), state),
					_train.bind(String(entry["id"]))))
	_fill_brewers()


# ---- YOUR PLAYERS: MATCH, ADVENTURE OR BREWER (round AN) -----
#
# "The player can train new player units as Adventure Player, Match Player
#  and Brewer Player ... they have to choose new player units where to send
#  them and what they will be working on." Every one of your players is
# listed with a button for each role he could be trained for. The roles and
# their prices are Training.csv rows (Kind match_player, adventure_player,
# brewer). See player_roles.gd and brewer_book.gd.

func _fill_brewers() -> void:
	var roles := PlayerRoles.offered()
	if roles.is_empty() or not PlayerRoles.on(db):
		return
	_list.add_child(MenuSupport.heading("YOUR PLAYERS", 17, MenuSupport.COLOUR_ACCENT))
	var bits: PackedStringArray = []
	for r in roles:
		bits.append("%s %s" % [PlayerRoles.label(r), _role_price(r)])
	_list.add_child(_small("Choose what each player works on: %s. A Match Player plays in your Match Teams, an Adventure Player in your Adventure Teams. A Brewer works the Brewery machines - his power is his efficiency, his chance at a machine (Brewers.csv). New players arrive untrained." % ", ".join(bits)))
	# ROUND AN: a role is for good, until Quereinsteiger retrains him.
	var retrain := PlayerRoles.retrain_row()
	var lock_on := db.tune_bool("role_lock", true)
	if lock_on and not retrain.is_empty():
		if PlayerRoles.retrain_open(state):
			_list.add_child(MenuSupport.heading(String(retrain["name"]).to_upper(), 15, MenuSupport.COLOUR_ACCENT))
			_list.add_child(_small("Put any trained player in and retrain him for a new role: %s each." % _price_of(retrain)))
		else:
			_list.add_child(_small("A role is for good. Once %s is unlocked, a trained player can be retrained for %s." % [
				retrain["name"], _price_of(retrain)]))

	# Untrained first: they are the ones waiting for you.
	var order: Array[String] = []
	for want in [PlayerRoles.NEW, PlayerRoles.MATCH, PlayerRoles.ADVENTURE, PlayerRoles.BREWER]:
		for name_text in RecruitBook.names(state):
			if PlayerRoles.role(name_text, state, db) == want:
				order.append(name_text)

	for name_text in order:
		var mine := PlayerRoles.role(name_text, state, db)
		var power := BrewerBook.efficiency(name_text, state)
		var left := RecoveryBook.turns_left_name(name_text, state)
		var line := _row_frame(mine != PlayerRoles.NEW)
		var words := _row_words(line)
		words.add_child(_name_label("%s  ·  Tier %s  ·  P:%d  ·  %s" % [
			name_text, BrewerBook.tier(name_text, state), power, PlayerRoles.label(mine)],
			mine != PlayerRoles.NEW))
		var note := ""
		if mine == PlayerRoles.BREWER:
			note = "Efficiency %d, %d%% at a machine." % [power, BrewerBook.success_for(power)]
		elif mine == PlayerRoles.NEW:
			note = "Not in any team until he is trained."
		else:
			note = "Plays in your %ss." % PlayerRoles.team_label(mine)
		if left > 0:
			note += "  Resting in the Dorms - %d fixture(s) to go." % left
		var locked := PlayerRoles.locked(name_text, state, db)
		if locked and not PlayerRoles.retrain_open(state):
			note += "  Role locked."
		words.add_child(_small(note))
		if locked and not PlayerRoles.retrain_open(state):
			continue
		if mine == PlayerRoles.BREWER and not locked:
			continue
		var short := {"match": "Match", "adventure": "Adventure", "brewer": "Brewer"}
		for r in roles:
			if r == mine:
				continue
			var entry := PlayerRoles.training_row(r)
			var pay := retrain if locked else entry
			line.add_child(_buy_button("%s%s · %s" % ["Retrain: " if locked else "", short.get(r, r), _price_of(pay)],
				_can_pay(int(pay["cost"]), String(pay["currency"]))
					and DialogueGrammar.test(String(entry["needs"]), state),
				_train_role.bind(name_text, r)))


func _role_price(role_text: String) -> String:
	return _price_of(PlayerRoles.training_row(role_text))


func _price_of(entry: Dictionary) -> String:
	if entry.is_empty() or int(entry["cost"]) <= 0:
		return "free"
	return "%d %s" % [int(entry["cost"]), entry["currency"]]


func _train_role(name_text: String, role_text: String) -> void:
	_say(BaseRooms.train_role(name_text, role_text, state))


func _train(id_text: String) -> void:
	_say(BaseRooms.train(id_text, state))


# =============================================================
#  SMALL PIECES
# =============================================================

func _say(result: Dictionary) -> void:
	_status.text = String(result["why"])
	_status.add_theme_color_override("font_color",
		MenuSupport.COLOUR_TEXT if bool(result["ok"]) else Color(1.0, 0.72, 0.4))
	if bool(result["ok"]):
		state.save_to_disk()
	_rebuild()


func _can_pay(price: int, currency_id: String) -> bool:
	if price <= 0:
		return true
	return ShopBook.purse(currency_id, state) >= price


## One row: a frame whose edge says at a glance whether you have it.
##
## ============ THIS ADDS THE ROW TO THE LIST ITSELF ============
##
## Read that twice, because it is the whole trap. What comes BACK is not the
## frame — it is the HBoxContainer *inside* the frame, already parented and
## ready for words. So a caller fills it and stops. It must NOT finish with
## `_list.add_child(line)`: that asks Godot to give a node a second parent,
## which it refuses, once per row, in red, in the Output panel.
##
## All six callers used to do exactly that. Every room you opened printed a
## hundred-odd errors that changed nothing on screen — the rows drew fine,
## because the frame was already in the list. That is the worst shape a bug
## can take: harmless, loud and constant, so the Output panel fills with
## noise and the one line that matters scrolls away. The whole point of
## printing a spreadsheet's problems there is that you can still see them.
func _row_frame(lit: bool) -> HBoxContainer:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", MenuSupport.panel_style(
		MenuSupport.COLOUR_PANEL,
		MenuSupport.COLOUR_ATTACK if lit else MenuSupport.COLOUR_SLOT_EMPTY))
	# HERE. The frame goes into the list here, and nowhere else.
	_list.add_child(frame)
	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right"]:
		pad.add_theme_constant_override(side, 12)
	for side in ["margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 8)
	frame.add_child(pad)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	pad.add_child(row)
	return row


func _row_words(row: HBoxContainer) -> VBoxContainer:
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", 1)
	row.add_child(words)
	return words


func _name_label(words: String, lit: bool) -> Label:
	var label := MenuSupport.heading(words, 17,
		MenuSupport.COLOUR_TEXT if lit else MenuSupport.COLOUR_TEXT_DIM)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _small(words: String) -> Label:
	var label := Label.new()
	label.text = words
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	return label


func _buy_button(words: String, allowed: bool, what: Callable) -> Button:
	var button := Button.new()
	button.text = words
	button.custom_minimum_size = Vector2(180.0, 40.0)
	button.disabled = not allowed
	var tint := MenuSupport.COLOUR_ATTACK if allowed else MenuSupport.COLOUR_TEXT_DIM
	button.add_theme_stylebox_override("normal",
		MenuSupport.panel_style(MenuSupport.COLOUR_PANEL, tint))
	button.add_theme_stylebox_override("hover",
		MenuSupport.panel_style(MenuSupport.COLOUR_SLOT_EMPTY, tint))
	button.add_theme_stylebox_override("disabled",
		MenuSupport.panel_style(MenuSupport.COLOUR_BACKGROUND, tint))
	button.add_theme_stylebox_override("focus", MenuSupport.focus_style())
	button.add_theme_color_override("font_color", tint)
	button.add_theme_color_override("font_disabled_color", tint)
	button.pressed.connect(what)
	return button


## WHAT A TRAINING DOES, IN A SENTENCE.
##
## `DialogueGrammar.describe()` is for CONDITIONS — "Needs matches won: at
## least 3" — and running an EFFECT through it produces "Needs any tune
## keeper stamina base+3", which is not English and is not true. So the two
## effects a training may have get their own words here.
##
## Anything else falls back to printing the term, which is honest: a designer
## who writes an effect this does not know about sees exactly what they typed
## rather than a sentence that is wrong.
func _effect_words(effect: String) -> String:
	var said: Array[String] = []
	for piece in effect.split(";", false):
		var term := String(piece).strip_edges()
		if not term.to_lower().begins_with("count:"):
			said.append(term)
			continue
		var body := term.substr(6).strip_edges()
		var at := -1
		for i in range(body.length() - 1, 0, -1):
			if body[i] == "+" or body[i] == "-":
				at = i
				break
		if at <= 0:
			said.append(term)
			continue
		var counter := body.substr(0, at)
		var amount := body.substr(at)

		# A VAT. The one a mini-game buys — see brewery_book.gd.
		if counter.begins_with(BreweryBook.BATCHES_PREFIX):
			var which := counter.substr(BreweryBook.BATCHES_PREFIX.length())
			var section := BreweryBook.section(which)
			said.append("%s more vat at the %s" % [amount.lstrip("+"),
				String(section["name"]) if not section.is_empty() else which])
			continue

		# A TUNING ROW. `tune_<key>` edits any number in Tuning.csv.
		if counter.begins_with("tune_"):
			said.append("%s to %s" % [amount, counter.substr(5).replace("_", " ")])
			continue

		said.append("%s %s" % [amount, counter.replace("_", " ")])
	return ("Gives " + ", ".join(said) + ".") if not said.is_empty() else ""
