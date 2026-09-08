class_name UnlockBoard
extends Control

# =============================================================
#  THE UNLOCK BOARD — "why is this locked?"
#
#  Every single thing in the game that can be earned, on one page, with a
#  bar showing how far along you are and a line saying exactly what is
#  missing. Buildings, talents, brews, fixtures, unlocks and achievements.
#
#  WHY THIS EXISTS
#  Finding out why the Pub has not appeared used to mean opening three
#  spreadsheets and following a chain by eye. Now it is one screen, and when
#  someone watching a demo asks "how does the player get that?" you can
#  answer in two seconds.
#
#  IT IS ALSO A CONTENT CHECK. If something sits at 0% with "needs X" and
#  nothing in the game grants X, you have found unreachable content — and
#  that is a thing that will otherwise cost you an afternoon.
#
#  It contains no rules of its own. Everything comes from
#  unlock_progress.gd, which reads every CSV and asks the SAME question the
#  game asks. It cannot disagree with what actually happens.
#
#  THE NODES IT FILLS  (open the .tscn and move them, do not rename them)
#    %Title  %Summary
#    %Filters     <- one button per kind is ADDED here
#    %BoardList   <- the rows are ADDED here
#    %HomeButton
# =============================================================

var db: CardDatabase
var state: GameState
var progress: UnlockProgress

## "" means everything. Otherwise one of UnlockProgress.KINDS.
var _filter: String = ""
var _show_done: bool = true

var _title: Label
var _summary: Label
var _filters: HBoxContainer
var _list: VBoxContainer
var _home: Button


func _ready() -> void:
	GameSpeed.reset()

	db = CardDatabase.get_db()
	state = GameState.fetch(get_tree())

	_title = _grab("Title") as Label
	_summary = _grab("Summary") as Label
	_filters = _grab("Filters") as HBoxContainer
	_list = _grab("BoardList") as VBoxContainer
	_home = _grab("HomeButton") as Button

	if _home != null:
		_home.pressed.connect(func() -> void:
			ScenePaths.go_back(get_tree(), ScenePaths.BASE))

	_rebuild()


func _grab(node_name: String) -> Node:
	var found := find_child(node_name, true, false)
	if found == null:
		push_warning("[unlock board] unlock_board.tscn has no node called '%s'." % node_name)
	return found


# =============================================================
#  BUILDING THE PAGE
# =============================================================

func _rebuild() -> void:
	progress = UnlockProgress.build(state)

	if _summary != null:
		_summary.text = "%d of %d earned   -   %d still to come" % [
			progress.done_count(), progress.entries.size(),
			progress.entries.size() - progress.done_count()]

	_build_filters()
	_build_list()


func _build_filters() -> void:
	if _filters == null:
		return
	for child in _filters.get_children():
		child.queue_free()

	_filters.add_child(_filter_button("Everything", ""))
	for kind in UnlockProgress.KINDS:
		if progress.in_kind(kind).is_empty():
			continue
		_filters.add_child(_filter_button("%ss" % kind, kind))

	var toggle := _make_button("Hide what I have" if _show_done else "Show everything", 190.0)
	toggle.pressed.connect(func() -> void:
		_show_done = not _show_done
		_rebuild())
	_filters.add_child(toggle)


func _filter_button(label: String, kind: String) -> Button:
	var button := _make_button(label, 108.0)
	var lit := _filter == kind
	button.add_theme_color_override("font_color",
		MenuSupport.COLOUR_ACCENT if lit else MenuSupport.COLOUR_TEXT)
	button.add_theme_stylebox_override("normal", MenuSupport.panel_style(
		MenuSupport.COLOUR_SLOT_EMPTY if lit else MenuSupport.COLOUR_PANEL,
		MenuSupport.COLOUR_ACCENT if lit else MenuSupport.COLOUR_TEXT_DIM))
	button.pressed.connect(func() -> void:
		_filter = kind
		_rebuild())
	return button


func _build_list() -> void:
	if _list == null:
		return
	for child in _list.get_children():
		child.queue_free()

	var shown := 0
	for kind in UnlockProgress.KINDS:
		if _filter != "" and _filter != kind:
			continue
		var rows := progress.in_kind(kind)
		if rows.is_empty():
			continue

		var wanted: Array[Dictionary] = []
		for entry in rows:
			if _show_done or not bool(entry["done"]):
				wanted.append(entry)
		if wanted.is_empty():
			continue

		_list.add_child(_section(kind, wanted.size(), rows.size()))
		for entry in wanted:
			_list.add_child(_entry_row(entry))
			shown += 1

	if shown == 0:
		var empty := Label.new()
		empty.text = "Nothing to show. Press \"Show everything\" to include what you already have."
		empty.add_theme_font_size_override("font_size", 15)
		empty.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
		_list.add_child(empty)


func _section(kind: String, showing: int, total: int) -> Control:
	var label := Label.new()
	label.text = "%s   (%d of %d shown)" % [kind.to_upper(), showing, total]
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", MenuSupport.COLOUR_ACCENT)
	return label


func _entry_row(entry: Dictionary) -> Control:
	var done := bool(entry["done"])

	var row := ProgressRow.new()
	var right := String(entry["progress_text"])
	if done:
		right = "yours"

	var note := String(entry["missing"])
	var detail := String(entry["detail"]).strip_edges()
	if not done and detail != "":
		note = "%s      %s" % [note, detail]
	# Where it is written down. When something looks wrong this is the line
	# that tells you which spreadsheet to open.
	note = "%s      [%s]" % [note, entry["where"]]

	row.setup(String(entry["name"]), float(entry["fraction"]), right, note, done)
	return row


func _make_button(label: String, width: float) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(width, 32)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_stylebox_override("normal",
		MenuSupport.panel_style(MenuSupport.COLOUR_PANEL, MenuSupport.COLOUR_TEXT_DIM))
	button.add_theme_stylebox_override("hover",
		MenuSupport.panel_style(MenuSupport.COLOUR_SLOT_EMPTY, MenuSupport.COLOUR_ACCENT))
	button.add_theme_stylebox_override("pressed",
		MenuSupport.panel_style(MenuSupport.COLOUR_SLOT_EMPTY, MenuSupport.COLOUR_ACCENT))
	return button
