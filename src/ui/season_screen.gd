class_name SeasonScreen
extends Control

# =============================================================
#  THE SEASON SCREEN — full time, and the table
#
#  ============ THIS FILE IS THE TEMPLATE ============
#
#  Every other screen in the project builds its layout in CODE. This one
#  does not, and it is the pattern to copy for anything you want to design
#  yourself. The rule is:
#
#      THE .TSCN DECIDES WHAT IT LOOKS LIKE.
#      THIS FILE ONLY PUTS WORDS INTO IT.
#
#  So you can open season_screen.tscn in Godot, drag the panels around,
#  change every font and colour, drop in a background image, and this file
#  keeps working — because it never says where anything is. It only ever
#  says "put this text in the node called Title".
#
#  THE NODES IT FILLS  (all marked with the % icon in the scene tree)
#    %Title          the big word: FULL TIME / CHAMPIONS / THE SEASON
#    %Score          the scoreline, or what is next
#    %Subheading     the quiet line under it
#    %GainsHeading   the little "WHAT YOU GAINED" label
#    %GainsList      one row per thing you gained  <- rows are ADDED here
#    %TableHeading   "SEASON 1"
#    %Record         P W D L, goals, points
#    %FixtureList    one row per fixture           <- rows are ADDED here
#    %PrimaryButton  play the next match / start a new season
#    %HomeButton     back to the base
#
#  HOW TO REDESIGN IT  (no code)
#    1. Open src/ui/season_screen.tscn
#    2. Move, restyle, re-parent anything you like
#    3. DO NOT rename the nodes above, and leave their "Access as Unique
#       Name" (the % icon, right-click a node) switched ON
#    4. Press F5
#
#  If you delete one of them by accident nothing crashes: the Output panel
#  says exactly which node is missing and the rest of the screen still
#  works. That is what _grab() below is for.
# =============================================================

var db: CardDatabase
var season: SeasonDB
var state: GameState

var _report: MatchReport = null
var _summary: Dictionary = {}

# The nodes from the scene. Any of them may be null if you deleted it.
var _title: Label
var _score: Label
var _subheading: Label
var _gains_heading: Label
var _gains_list: VBoxContainer
var _table_heading: Label
var _record: Label
var _fixture_list: VBoxContainer
var _primary: Button
var _home: Button


func _ready() -> void:
	# Escape, controller navigation, the key bindings, the player's
	# settings and the language — all five from this one line. See
	# menu_escape.gd.
	MenuEscape.install(self)
	# Time runs at whatever speed you left it. On a menu that is silly, and
	# it makes the buttons feel broken, so it goes back to normal here.
	GameSpeed.reset()

	db = CardDatabase.get_db()
	season = SeasonDB.get_db()
	state = GameState.fetch(get_tree())

	# take(), not fetch(): the gains belong to the match that just finished,
	# and coming back here later should not show them a second time.
	_report = MatchReport.take(get_tree())
	if _report != null:
		_summary = _report.summary

	_find_nodes()
	_fill_header()
	_fill_gains()
	_fill_table()
	_fill_buttons()


# =============================================================
#  FINDING THE SCENE'S NODES
#
#  find_child() searches the WHOLE scene, not just the direct children, so
#  it keeps working after you re-parent something in the editor. That is
#  the whole point — and it is the bug that crashed the first version of
#  this screen, which used get_node("Body") and only ever looked one level
#  down.
# =============================================================

func _find_nodes() -> void:
	_title = _grab("Title") as Label
	_score = _grab("Score") as Label
	_subheading = _grab("Subheading") as Label
	_gains_heading = _grab("GainsHeading") as Label
	_gains_list = _grab("GainsList") as VBoxContainer
	_table_heading = _grab("TableHeading") as Label
	_record = _grab("Record") as Label
	_fixture_list = _grab("FixtureList") as VBoxContainer
	_primary = _grab("PrimaryButton") as Button
	_home = _grab("HomeButton") as Button


## Find a node by name anywhere in this scene, and say so plainly if it is
## gone rather than bringing the game down.
func _grab(node_name: String) -> Node:
	var found := find_child(node_name, true, false)
	if found == null:
		push_warning("[season screen] season_screen.tscn has no node called '%s'. That part of the screen will be blank — add a node of that name back, or ignore this if you meant to remove it."
			% node_name)
	return found


## Put text into one of the scene's labels, if that label still exists.
##
## It is called _put and NOT _set. `_set` is one of Godot's own built-in
## methods — every Object has `_set(StringName, Variant) -> bool` — so a
## function of that name with different arguments does not override it, it
## COLLIDES with it, and the whole script refuses to compile:
##
##   "The function signature doesn't match the parent."
##
## The same trap is waiting on _get, _draw, _init, _notification and
## _to_string. If you add a helper of your own, do not start its name with an
## underscore followed by a common word.
func _put(label: Label, text: String) -> void:
	if label != null:
		label.text = text


# =============================================================
#  THE HEADER
# =============================================================

func _fill_header() -> void:
	var over := SeasonDB.is_over(state)

	# THE TITLE IS THE SEASON'S NAME. It used to say FULL TIME whenever there
	# was a match summary to show — which was left over from the last game
	# you played and read as a bug, because you had not just finished one.
	# The scoreline under it already says what the last result was; the title
	# says where you are.
	var book := SeasonBook.get_db()
	var here := book.find(SeasonBook.chosen_id())
	var title_text := String(here.get("name", "THE SEASON")).to_upper()
	if over:
		title_text = SeasonDB.verdict(state)
	_put(_title, title_text)

	if _title != null and over and not state.has_flag(SeasonDB.CHAMPION_FLAG):
		_title.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT)

	_put(_score, _scoreline())
	_put(_subheading, _under())


func _scoreline() -> String:
	if not _summary.is_empty():
		var fixture: Dictionary = _summary.get("fixture", {})
		var opponent := "a friendly"
		if not fixture.is_empty():
			opponent = String(fixture.get("opponent", "a friendly"))
		return "Your side  %d  -  %d  %s" % [
			int(_summary.get("scored", 0)), int(_summary.get("conceded", 0)), opponent]

	if SeasonDB.is_over(state):
		return "Season %d is finished." % maxi(1, state.count(SeasonDB.NUMBER))

	var next := season.current(state)
	if next.is_empty():
		return "No fixture left to play."
	return "Next up: %s" % next["opponent"]


func _under() -> String:
	if SeasonDB.is_over(state):
		var points := state.count(SeasonDB.POINTS)
		return "%d played  -  %d point%s  -  press below to go round again" % [
			SeasonDB.played(state), points, "" if points == 1 else "s"]

	var next := season.current(state)
	if next.is_empty():
		return ""

	var bits: Array[String] = ["Matchday %d of %d" % [
		int(next["number"]), season.last_number()]]
	if bool(next["final"]):
		bits.append("THE FINAL")
	if int(next["difficulty"]) > 0:
		bits.append("difficulty %d" % int(next["difficulty"]))
	var blurb := String(next["description"])
	if blurb != "":
		bits.append(blurb)
	return "   -   ".join(bits)


# =============================================================
#  WHAT YOU GAINED
# =============================================================

func _fill_gains() -> void:
	if _gains_list == null:
		return
	for child in _gains_list.get_children():
		child.queue_free()

	if _report == null:
		_gains_list.add_child(_quiet("Nothing yet - this is the table between matches."))
		return

	var rows := _report.top(db.tune_int("gains_max_rows", 8))
	if rows.is_empty():
		_gains_list.add_child(_quiet("Nothing new this match. Talents and unlocks will show up here."))
		return

	_put(_gains_heading, "WHAT YOU GAINED  (%d)" % _report.gains.size())
	for entry in rows:
		_gains_list.add_child(_gain_row(entry))


func _gain_row(entry: Dictionary) -> Control:
	var kind := String(entry["kind"])

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var pip := Label.new()
	pip.custom_minimum_size = Vector2(22, 0)
	pip.add_theme_font_size_override("font_size", 18)
	match kind:
		"unlock":
			pip.text = "*"
			pip.add_theme_color_override("font_color", MenuSupport.COLOUR_ACCENT)
		"flag":
			pip.text = "+"
			pip.add_theme_color_override("font_color", MenuSupport.COLOUR_ACCENT)
		"counter":
			pip.text = "+"
			pip.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT)
		_:
			pip.text = "-"
			pip.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	row.add_child(pip)

	var text := Label.new()
	text.text = String(entry["text"])
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("font_size", 17 if kind == "unlock" else 16)
	text.add_theme_color_override("font_color",
		MenuSupport.COLOUR_ACCENT if kind == "unlock" else MenuSupport.COLOUR_TEXT)
	row.add_child(text)

	var detail := String(entry["detail"])
	if detail != "":
		var side := Label.new()
		side.text = detail
		side.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		side.add_theme_font_size_override("font_size", 13)
		side.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
		row.add_child(side)

	return row


# =============================================================
#  THE TABLE
# =============================================================

func _fill_table() -> void:
	_put(_table_heading, "SEASON %d" % maxi(1, state.count(SeasonDB.NUMBER)))
	_put(_record, "P %d    W %d  D %d  L %d    %d-%d    %d pts" % [
		SeasonDB.played(state),
		state.count(SeasonDB.WINS), state.count(SeasonDB.DRAWS),
		state.count(SeasonDB.LOSSES),
		state.count(SeasonDB.GOALS_FOR), state.count(SeasonDB.GOALS_AGAINST),
		state.count(SeasonDB.POINTS)])

	if _fixture_list == null:
		return
	for child in _fixture_list.get_children():
		child.queue_free()

	if season.fixtures.is_empty():
		_fixture_list.add_child(_quiet("No fixtures. Put rows in data/Season.csv."))
		return

	var next_number := SeasonDB.current_number(state)
	for entry in season.fixtures:
		_fixture_list.add_child(_fixture_row(entry, next_number))


func _fixture_row(entry: Dictionary, next_number: int) -> Control:
	var number := int(entry["number"])
	var result := SeasonDB.result_for(String(entry["id"]), state)
	var is_next := number == next_number and not SeasonDB.is_over(state)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var index := Label.new()
	index.text = "%d" % number
	index.custom_minimum_size = Vector2(26, 0)
	index.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	index.add_theme_font_size_override("font_size", 14)
	index.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	row.add_child(index)

	var who := Label.new()
	who.text = String(entry["opponent"])
	if bool(entry["final"]):
		who.text += "   (final)"
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.add_theme_font_size_override("font_size", 15)
	who.add_theme_color_override("font_color",
		MenuSupport.COLOUR_ACCENT if is_next else MenuSupport.COLOUR_TEXT)
	row.add_child(who)

	var score := Label.new()
	score.custom_minimum_size = Vector2(78, 0)
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score.add_theme_font_size_override("font_size", 15)
	if result != "":
		score.text = "%s  %s" % [result, _letter(result)]
		score.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT)
	elif is_next:
		score.text = "next"
		score.add_theme_color_override("font_color", MenuSupport.COLOUR_ACCENT)
	else:
		score.text = "-"
		score.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	row.add_child(score)

	return row


## "3-1" -> "W". Read back off the stored result so the table needs no extra
## save data of its own.
static func _letter(result: String) -> String:
	var parts := result.split("-")
	if parts.size() != 2:
		return ""
	var scored := int(parts[0])
	var conceded := int(parts[1])
	if scored > conceded:
		return "W"
	if scored < conceded:
		return "L"
	return "D"


# =============================================================
#  THE BUTTONS
# =============================================================

func _fill_buttons() -> void:
	if _primary != null:
		# BOTTOM RIGHT, not bottom centre. The table is the thing on this page
		# and it wants the middle of the screen; the action that takes you off
		# the page belongs in the corner opposite Back, where the eye finishes
		# rather than where it is reading.
		MenuSupport.pin_bottom_right(_primary)
		if SeasonDB.is_over(state):
			MenuSupport.restyle(_primary, "season|▦",
				"Start season %d" % (maxi(1, state.count(SeasonDB.NUMBER)) + 1), true)
			_primary.pressed.connect(func() -> void:
				SeasonDB.new_season(state)
				state.save_to_disk()
				ScenePaths.go_to(get_tree(), ScenePaths.SEASON))
		else:
			var next := season.current(state)
			var word := Loc.text("play_season", "Play")
			if next.is_empty():
				MenuSupport.restyle(_primary, "play|▶", "%s the next match" % word, true)
			else:
				MenuSupport.restyle(_primary, "play|▶",
					"%s: %s" % [word, next["opponent"]], true)
			_primary.pressed.connect(func() -> void:
				state.save_to_disk()
				# THE LEAGUE IS PLAYED FROM HERE. The base's "Play a match"
				# is a friendly against a scratch side; this is the fixture,
				# and it is the only button that sets the `season` mode.
				MatchMode.choose(get_tree(), "season")
				ScenePaths.go_to(get_tree(), ScenePaths.TEAM_SELECT))

	# BACK GOES BOTTOM-LEFT, like every other screen, and PLAY sits in the
	# opposite corner. Both buttons come from the scene file, so they are
	# restyled and repositioned here rather than in the editor — which means
	# you never have to open season_screen.tscn to keep them in step with the
	# rest of the game.
	if _home != null:
		MenuSupport.restyle(_home, "back|←", Loc.text("back", "Back"))
		MenuSupport.pin_bottom_left(_home)
		_home.name = "BackButton"        # so B on a controller finds it
		_home.pressed.connect(func() -> void:
			state.save_to_disk()
			ScenePaths.go_back(get_tree(), ScenePaths.SEASON_PICKER))


func _quiet(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	return label
