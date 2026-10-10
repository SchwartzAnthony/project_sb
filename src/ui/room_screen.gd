class_name RoomScreen
extends Control

# =============================================================
#  THE ROOMS AND THE ACHIEVEMENT BOARD — one script, several scenes
#
#  ROUND AN (Anthony, 10 Oct): THE DORMS LEFT. They are a picture of rooms
#  and beds now, with their own screen - src/ui/dorms_screen.gd. The Club
#  House and the Training Ground followed (clubhouse_screen.gd,
#  training_screen.gd, both on scene_room.gd).
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
#      src/ui/rooms/trophies.tscn        room = "trophies"
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
		"trophies": return "The Trophy Room"
		"stadium": return "The Stadium"
		_: return "Achievements"


# =============================================================
#  FILLING IT
# =============================================================

func _rebuild() -> void:
	for child in _list.get_children():
		child.queue_free()
	match room:
		"trophies": _fill_trophies()
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


# =============================================================
#  SMALL PIECES
# =============================================================

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
