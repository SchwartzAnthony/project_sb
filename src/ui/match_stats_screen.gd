class_name MatchStatsScreen
extends Control

# =============================================================
#  THE POST-MATCH SCREEN — what happened, and what you are close to
#
#  Left:  every number that moved during the match, grouped into panels
#         by the Group column of Stats.csv.
#  Right: progress bars for the things you have not unlocked yet, closest
#         first, filling up and shining when finished.
#
#  ---------------------------------------------------------------
#  WHERE THE NUMBERS COME FROM, AND WHY THERE IS NO NEW BOOKKEEPING
#
#  The match takes a photograph of your save at kick-off and another at the
#  whistle. The difference between them IS this match: `duels_won` went from
#  40 to 47, so you won seven duels today.
#
#  That means adding a stat to this screen is a ROW IN Stats.csv and nothing
#  else. Give the row a Group and it appears in that panel. Give it a Label
#  and that is what it is called. There is no list in this file to add it to,
#  and no code here knows what a duel is.
#  ---------------------------------------------------------------
#
#  THE NODES IT FILLS  (same template pattern as season_screen.gd — open the
#  .tscn and move them about, just do not rename them)
#    %Title  %Score
#    %StatsHeading     %StatsList        <- panels are ADDED here
#    %ProgressHeading  %ProgressList     <- bars are ADDED here
#    %ContinueButton  %AgainButton  %HomeButton
# =============================================================

## Set by this screen when you press "Play it again", read by main_scene.
## A rerun does not touch the season table — the result is already in it.
const REPLAY_FLAG := "replay_friendly"

var db: CardDatabase
var state: GameState
var stats: StatsRules

var _report: MatchReport = null
var _summary: Dictionary = {}

var _title: Label
var _score: Label
var _stats_heading: Label
var _stats_list: VBoxContainer
var _progress_heading: Label
var _progress_list: VBoxContainer
var _continue: Button
var _again: Button
var _home: Button


func _ready() -> void:
	GameSpeed.reset()

	db = CardDatabase.get_db()
	state = GameState.fetch(get_tree())
	stats = StatsRules.get_rules()

	# TAKEN, then put back. The season screen wants the same report for its
	# "what you gained" panel, and Continue goes straight there.
	_report = MatchReport.take(get_tree())
	if _report != null:
		_summary = _report.summary
		MatchReport.stash(get_tree(), _report)

	_find_nodes()
	_fill_header()
	_fill_stats()
	_fill_progress()
	_fill_buttons()


func _find_nodes() -> void:
	_title = _grab("Title") as Label
	_score = _grab("Score") as Label
	_stats_heading = _grab("StatsHeading") as Label
	_stats_list = _grab("StatsList") as VBoxContainer
	_progress_heading = _grab("ProgressHeading") as Label
	_progress_list = _grab("ProgressList") as VBoxContainer
	_continue = _grab("ContinueButton") as Button
	_again = _grab("AgainButton") as Button
	_home = _grab("HomeButton") as Button


func _grab(node_name: String) -> Node:
	var found := find_child(node_name, true, false)
	if found == null:
		push_warning("[stats screen] match_stats_screen.tscn has no node called '%s'. That part of the screen will be blank."
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
#  HEADER
# =============================================================

func _fill_header() -> void:
	var scored := int(_summary.get("scored", 0))
	var conceded := int(_summary.get("conceded", 0))

	var word := "FULL TIME"
	if not _summary.is_empty():
		if scored > conceded:
			word = "WON"
		elif scored < conceded:
			word = "LOST"
		else:
			word = "DRAWN"
	_put(_title, word)

	if _title != null and scored < conceded:
		_title.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT)

	if _summary.is_empty():
		_put(_score, "A friendly. Nothing was recorded.")
		return

	var fixture: Dictionary = _summary.get("fixture", {})
	var opponent := "a friendly"
	if not fixture.is_empty():
		opponent = String(fixture.get("opponent", "a friendly"))
	_put(_score, "Your side  %d  -  %d  %s" % [scored, conceded, opponent])


# =============================================================
#  THIS MATCH'S NUMBERS
# =============================================================

func _fill_stats() -> void:
	if _stats_list == null:
		return
	for child in _stats_list.get_children():
		child.queue_free()

	if _report == null:
		_stats_list.add_child(_quiet("No match has finished yet."))
		return

	# Sort every counter that moved into its Group from Stats.csv.
	var by_group: Dictionary = {}
	var order: Array[String] = []
	for entry in _report.counter_gains():
		var key := String(entry["key"])
		var group := stats.group_for(key)
		if group == "":
			group = "Match"
		if not by_group.has(group):
			by_group[group] = [] as Array[Dictionary]
			order.append(group)
		(by_group[group] as Array).append(entry)

	if order.is_empty():
		_stats_list.add_child(_quiet("Nothing was counted this match. Add rows to Stats.csv and they appear here on their own."))
		return

	# Show the panels in the order Stats.csv lists its Groups, so you control
	# the layout from the spreadsheet.
	var wanted := stats.group_names()
	for group in wanted:
		if by_group.has(group):
			_stats_list.add_child(_group_panel(group, by_group[group]))
			order.erase(group)
	for group in order:
		_stats_list.add_child(_group_panel(group, by_group[group]))

	_put(_stats_heading, "THIS MATCH  (%d number%s moved)" % [
		_report.counter_gains().size(),
		"" if _report.counter_gains().size() == 1 else "s"])


func _group_panel(group: String, rows: Array) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)

	var heading := Label.new()
	heading.text = group.to_upper()
	heading.add_theme_font_size_override("font_size", 13)
	heading.add_theme_color_override("font_color", MenuSupport.COLOUR_ACCENT)
	box.add_child(heading)

	for entry in rows:
		box.add_child(_stat_row(entry))

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(gap)
	return box


func _stat_row(entry: Dictionary) -> Control:
	var key := String(entry["key"])
	var rule := stats.row_for(key)

	# The Label column wins; otherwise the spelling the counter was written
	# with, tidied up. A counter made from a {fact} — goals_by_tier_IV — has
	# no useful Label, so the spelling is the honest answer there.
	var title := ""
	if not rule.is_empty():
		title = String(rule["label"]).strip_edges()
	if title == "":
		title = state.pretty(key)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var name_label := Label.new()
	name_label.text = title
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT)
	row.add_child(name_label)

	var today := Label.new()
	today.text = "+%d" % int(entry["delta"])
	today.custom_minimum_size = Vector2(46, 0)
	today.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	today.add_theme_font_size_override("font_size", 15)
	today.add_theme_color_override("font_color", MenuSupport.COLOUR_ACCENT)
	row.add_child(today)

	var total := Label.new()
	total.text = "%d all time" % int(entry["now"])
	total.custom_minimum_size = Vector2(96, 0)
	total.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	total.add_theme_font_size_override("font_size", 13)
	total.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	row.add_child(total)

	return row


# =============================================================
#  THE BARS
# =============================================================

func _fill_progress() -> void:
	if _progress_list == null:
		return
	for child in _progress_list.get_children():
		child.queue_free()

	var progress := UnlockProgress.build(state)

	# The ones you just finished go first and shine, then the ones you are
	# closest to. Anything you have not started is left off — a bar that has
	# never moved says nothing and would crowd out the ones that have.
	var shown := 0
	var limit := db.tune_int("progress_bars_max", 6)

	if _report != null:
		for entry in _report.gains:
			if String(entry["kind"]) != "unlock" or shown >= limit:
				continue
			var row := ProgressRow.new()
			row.setup(String(entry["text"]), 1.0, "done", "Earned this match.", true)
			_progress_list.add_child(row)
			shown += 1

	for entry in progress.nearest(limit - shown):
		var row2 := ProgressRow.new()
		row2.setup("%s  (%s)" % [entry["name"], String(entry["kind"]).to_lower()],
			float(entry["fraction"]), String(entry["progress_text"]),
			String(entry["missing"]), false)
		_progress_list.add_child(row2)
		shown += 1

	if shown == 0:
		_progress_list.add_child(_quiet("Nothing on the way yet. Requirements you have started will show up here."))

	_put(_progress_heading, "WHAT YOU ARE CLOSE TO  (%d of %d earned)" % [
		progress.done_count(), progress.entries.size()])


# =============================================================
#  BUTTONS
# =============================================================

func _fill_buttons() -> void:
	if _continue != null:
		_continue.pressed.connect(func() -> void:
			state.save_to_disk()
			ScenePaths.go_to(get_tree(), ScenePaths.SEASON))

	if _again != null:
		# HONESTY: this is not a replay of what you just watched. There is no
		# recording — the match was not saved anywhere — so this plays the same
		# opposition again from scratch. The result does NOT go into the season
		# table, because that fixture is already recorded.
		_again.text = "Play it again (does not count)"
		_again.tooltip_text = "Plays the same opposition again as a friendly. The season table is not touched."
		_again.pressed.connect(func() -> void:
			state.set_flag(REPLAY_FLAG, true)
			state.save_to_disk()
			ScenePaths.go_to(get_tree(), ScenePaths.MATCH))

	if _home != null:
		_home.pressed.connect(func() -> void:
			state.save_to_disk()
			ScenePaths.go_to(get_tree(), ScenePaths.BASE))


func _quiet(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	return label
