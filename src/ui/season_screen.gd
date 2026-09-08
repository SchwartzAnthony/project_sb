class_name SeasonScreen
extends Control

# =============================================================
#  THE SEASON SCREEN — full time, and the table
#
#  It does two jobs and works out for itself which one it is doing:
#
#    STRAIGHT AFTER A MATCH   the score, everything you gained, and the
#                             season record. The match scene leaves a
#                             MatchReport behind and this picks it up.
#
#    OPENED FROM THE BASE     no MatchReport waiting, so it is just the
#                             table and the next fixture.
#
#  Everything on it comes from Season.csv and from GameState. There is no
#  content in this file — no team names, no fixture list, nothing you would
#  have to come in here and edit.
# =============================================================

const PANEL_MIN := Vector2(360, 300)

var db: CardDatabase
var season: SeasonDB
var state: GameState

var _report: MatchReport = null
var _summary: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	db = CardDatabase.get_db()
	season = SeasonDB.get_db()
	state = GameState.fetch(get_tree())

	# take(), not fetch(): the gains belong to the match that just finished,
	# and coming back here later should not show them a second time.
	_report = MatchReport.take(get_tree())
	if _report != null:
		_summary = _report.summary

	_build()


# =============================================================
#  LAYOUT
# =============================================================

func _build() -> void:
	var fill := ColorRect.new()
	fill.color = MenuSupport.COLOUR_BACKGROUND
	fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fill)

	var page := MarginContainer.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right"]:
		page.add_theme_constant_override(side, 48)
	page.add_theme_constant_override("margin_top", 26)
	page.add_theme_constant_override("margin_bottom", 22)
	add_child(page)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	page.add_child(column)

	_build_header(column)

	var middle := HBoxContainer.new()
	middle.add_theme_constant_override("separation", 22)
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(middle)

	middle.add_child(_build_gains_panel())
	middle.add_child(_build_table_panel())

	column.add_child(_build_buttons())


func _build_header(column: VBoxContainer) -> void:
	var over := SeasonDB.is_over(state)
	var title_text := "THE SEASON"
	var colour := MenuSupport.COLOUR_ACCENT

	if over:
		title_text = SeasonDB.verdict(state)
		colour = MenuSupport.COLOUR_ACCENT if state.has_flag(SeasonDB.CHAMPION_FLAG) \
			else MenuSupport.COLOUR_TEXT
	elif not _summary.is_empty():
		title_text = "FULL TIME"

	var title := MenuSupport.heading(title_text, 42, colour)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	var line := Label.new()
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.add_theme_font_size_override("font_size", 22)
	line.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT)
	line.text = _headline()
	column.add_child(line)

	var under := Label.new()
	under.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	under.add_theme_font_size_override("font_size", 14)
	under.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	under.text = _subheading()
	column.add_child(under)


## The big line: the score if a match just ended, otherwise what is next.
func _headline() -> String:
	if not _summary.is_empty():
		var fixture: Dictionary = _summary.get("fixture", {})
		var opponent := String(fixture.get("opponent", "a friendly")) if not fixture.is_empty() \
			else "a friendly"
		return "Your side  %d  –  %d  %s" % [
			int(_summary.get("scored", 0)), int(_summary.get("conceded", 0)), opponent]

	if SeasonDB.is_over(state):
		return "Season %d is finished." % maxi(1, state.count(SeasonDB.NUMBER))

	var next := season.current(state)
	if next.is_empty():
		return "No fixture left to play."
	return "Next up: %s" % next["opponent"]


func _subheading() -> String:
	if SeasonDB.is_over(state):
		return "%d played  ·  %d point%s  ·  press below to go round again" % [
			SeasonDB.played(state), state.count(SeasonDB.POINTS),
			"" if state.count(SeasonDB.POINTS) == 1 else "s"]

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
	return "  ·  ".join(bits)


# =============================================================
#  WHAT YOU GAINED
# =============================================================

func _build_gains_panel() -> Control:
	var panel := _panel("WHAT YOU GAINED")
	var body := panel.get_node("Body") as VBoxContainer

	if _report == null:
		body.add_child(_quiet("Nothing yet — this is the table between matches."))
		return panel

	var rows := _report.top(db.tune_int("gains_max_rows", 8))
	if rows.is_empty():
		body.add_child(_quiet("Nothing new this match. Talents and unlocks will show up here."))
		return panel

	for entry in rows:
		body.add_child(_gain_row(entry))
	return panel


func _gain_row(entry: Dictionary) -> Control:
	var kind := String(entry["kind"])

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var pip := Label.new()
	pip.custom_minimum_size = Vector2(22, 0)
	pip.add_theme_font_size_override("font_size", 18)
	match kind:
		"unlock":
			pip.text = "★"
			pip.add_theme_color_override("font_color", MenuSupport.COLOUR_ACCENT)
		"flag":
			pip.text = "✓"
			pip.add_theme_color_override("font_color", MenuSupport.COLOUR_ACCENT)
		"counter":
			pip.text = "+"
			pip.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT)
		_:
			pip.text = "·"
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

func _build_table_panel() -> Control:
	var panel := _panel("SEASON %d" % maxi(1, state.count(SeasonDB.NUMBER)))
	var body := panel.get_node("Body") as VBoxContainer

	var record := Label.new()
	record.add_theme_font_size_override("font_size", 17)
	record.add_theme_color_override("font_color", MenuSupport.COLOUR_ACCENT)
	record.text = "P %d    W %d  D %d  L %d    %d-%d    %d pts" % [
		SeasonDB.played(state),
		state.count(SeasonDB.WINS), state.count(SeasonDB.DRAWS),
		state.count(SeasonDB.LOSSES),
		state.count(SeasonDB.GOALS_FOR), state.count(SeasonDB.GOALS_AGAINST),
		state.count(SeasonDB.POINTS)]
	body.add_child(record)

	if season.fixtures.is_empty():
		body.add_child(_quiet("No fixtures. Put rows in data/Season.csv."))
		return panel

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 3)
	scroll.add_child(list)

	var next_number := SeasonDB.current_number(state)
	for entry in season.fixtures:
		list.add_child(_fixture_row(entry, next_number))
	return panel


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
		score.text = "—"
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
#  BUTTONS
# =============================================================

func _build_buttons() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)

	if SeasonDB.is_over(state):
		var again := _button("Start season %d" % (maxi(1, state.count(SeasonDB.NUMBER)) + 1),
			Vector2(230, 50))
		again.pressed.connect(func() -> void:
			SeasonDB.new_season(state)
			state.save_to_disk()
			ScenePaths.go_to(get_tree(), ScenePaths.SEASON))
		row.add_child(again)
	else:
		var next := season.current(state)
		var label := "Play the next match"
		if not next.is_empty():
			label = "Play: %s" % next["opponent"]
		var play := _button(label, Vector2(280, 50))
		play.pressed.connect(func() -> void:
			state.save_to_disk()
			ScenePaths.go_to(get_tree(), ScenePaths.CLASS_SELECT))
		row.add_child(play)

	var home := _button("Back to the base", Vector2(200, 50))
	home.pressed.connect(func() -> void:
		state.save_to_disk()
		ScenePaths.go_to(get_tree(), ScenePaths.BASE))
	row.add_child(home)

	return row


# =============================================================
#  SMALL PIECES
# =============================================================

## A titled box with a "Body" VBox inside for the caller to fill.
func _panel(title_text: String) -> Control:
	var frame := PanelContainer.new()
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.custom_minimum_size = PANEL_MIN
	frame.add_theme_stylebox_override("panel",
		MenuSupport.panel_style(MenuSupport.COLOUR_PANEL, MenuSupport.COLOUR_SLOT_EMPTY))

	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 16)
	frame.add_child(pad)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	pad.add_child(box)

	var heading := Label.new()
	heading.text = title_text
	heading.add_theme_font_size_override("font_size", 15)
	heading.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	box.add_child(heading)

	var body := VBoxContainer.new()
	body.name = "Body"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	box.add_child(body)

	return frame


func _quiet(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	return label


func _button(label: String, box: Vector2) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = box
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_stylebox_override("normal",
		MenuSupport.panel_style(MenuSupport.COLOUR_PANEL, MenuSupport.COLOUR_ACCENT))
	button.add_theme_stylebox_override("hover",
		MenuSupport.panel_style(MenuSupport.COLOUR_SLOT_EMPTY, MenuSupport.COLOUR_ACCENT))
	button.add_theme_stylebox_override("pressed",
		MenuSupport.panel_style(MenuSupport.COLOUR_SLOT_EMPTY, MenuSupport.COLOUR_TEXT))
	return button
