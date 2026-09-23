class_name RoomScreen
extends Control

# =============================================================
#  THE FOUR ROOMS AND THE ACHIEVEMENT BOARD — one script, five scenes
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
#      src/ui/rooms/dorms.tscn           room = "dorms"
#      src/ui/rooms/clubhouse.tscn       room = "clubhouse"
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
		"dorms": return "The Dorms"
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
		"dorms": _fill_dorms()
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
		else:
			words.add_child(_small(DialogueGrammar.describe(String(row["needs"]))))


# ---- THE DORMS ----------------------------------------------

func _fill_dorms() -> void:
	var beds := BaseRooms.beds(state)
	var here := BaseRooms.current_dorm(state)
	var squad := SquadBook.names(state).size()
	_intro.text = "%s — %d bed(s). You are keeping %d player(s).%s" % [
		String(here["name"]) if not here.is_empty() else "No dorm",
		beds, squad,
		"  The Club House is where they rest." if beds > 0 else ""]

	for dorm in BaseRooms.dorms():
		var owned := int(dorm["price"]) == 0 or BaseRooms.owns_dorm(String(dorm["id"]), state)
		var line := _row_frame(owned)
		var words := _row_words(line)
		words.add_child(_name_label("%s — %d beds" % [dorm["name"], int(dorm["beds"])], owned))
		if int(dorm["price"]) == 0:
			words.add_child(_small("Yours from the first minute."))
		elif owned:
			words.add_child(_small("Bought."))
		else:
			words.add_child(_small(DialogueGrammar.describe(String(dorm["requires"]))))
			line.add_child(_buy_button("%d %s" % [int(dorm["price"]), dorm["currency"]],
				_can_pay(int(dorm["price"]), String(dorm["currency"]))
					and int(dorm["beds"]) > beds
					and DialogueGrammar.test(String(dorm["requires"]), state),
				_buy_dorm.bind(String(dorm["id"]))))


func _buy_dorm(id_text: String) -> void:
	_say(BaseRooms.buy_dorm(id_text, state))


# ---- THE CLUB HOUSE -----------------------------------------

func _fill_clubhouse() -> void:
	# THE CLUB HOUSE HAS NO SPREADSHEET OF ITS OWN. It is a view onto
	# recovery_book.gd, which already knows who is tired and for how long.
	var on := db != null and db.tune_bool("recovery", false)
	var tail := "That is why you want a deep squad — the Dorms say how deep it may be."
	if not on:
		tail = "RECOVERY IS OFF — `recovery` in Tuning.csv. Nobody gets tired, so this room lists who is fit, which is everybody."
	_intro.text = "Everybody rests after a match or an adventure, and a player's P:x is how many fixtures it takes them. " + tail

	var resting := 0
	for card in db.players:
		if card.is_star():
			continue
		var left := RecoveryBook.turns_left(card, state)
		if left <= 0 and on:
			continue
		var fit := left <= 0
		var line := _row_frame(fit)
		var words := _row_words(line)
		words.add_child(_name_label("%s  ·  Tier %s  ·  P:%d"
			% [card.player_name, card.get_tier_clean(), card.base_power_left], fit))
		if fit:
			words.add_child(_small("Fit."))
		else:
			resting += 1
			words.add_child(_small("Resting — %d fixture(s) to go." % left))

	if on and resting == 0:
		_list.add_child(_small("Nobody is resting. The whole squad is fit."))


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
	_intro.text = "Ausbildung trains a number for the whole side. A mini-game automates one Brewery section — today it buys that section another vat, which is the foundation the played game will sit on."
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
