class_name TeamBuildScreen
extends Control

# =============================================================
#  TEAM BUILD — the hub (round Y)
#
#  The building that used to be the Talent Tree. Up to three tabs - which
#  ones show is Tuning.csv `team_build_tabs` (round AN: "Star Hall;Your
#  Teams", Anthony took the Talents tab out; add `Talents` to bring it back):
#
#      STAR HALL    place your three Stars. Nothing is played without them,
#                   and the Stars you place decide which set cards you may
#                   pick (class_tree_gates_units).
#      YOUR TEAMS   every side you have built, how many of 12 it has, and
#                   whether it may take the pitch. Create and Edit open the
#                   same builder as always.
#      TALENTS      the talent tree, unchanged. It still waits for
#                   `unlocked:Talent Tree`, exactly as the building did.
#
#  Across the top, the two things that open the Pub and every match:
#
#      ✔ Stars placed  3 / 3        ✖ Team  9 / 12
#
#  The rule itself is in src/core/team_build.gd. This screen only shows it.
#  Opened by the base building (`window:teambuild`), by the "Your teams"
#  button, and by any door the gate turns away.
# =============================================================

const TABS: Array[String] = ["Star Hall", "Your Teams", "Talents"]
const TALENT_UNLOCK := "Talent Tree"

## Which tab opens first. A door the gate turned away can set this before
## opening the window, so you land on the thing you are missing.
static var open_on := ""

var db: CardDatabase
var state: GameState
var _tab := ""
var _strip: HBoxContainer
var _tabs: HBoxContainer
var _body: Control
var _note: Label


func _ready() -> void:
	if not MenuSupport.in_a_window(self):
		MenuEscape.install(self)
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	db = CardDatabase.get_db()
	state = GameState.fetch(get_tree())
	TransformBook.apply_all(db, state)
	_build()
	var first := open_on
	open_on = ""
	if first == "":
		first = TeamBuild.tab_for(state, db)
	_show(first)


func _build() -> void:
	if not MenuSupport.in_a_window(self):
		var bg := ColorRect.new()
		bg.color = MenuSupport.COLOUR_BACKGROUND
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(bg)

	var page := VBoxContainer.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_theme_constant_override("separation", 8)
	add_child(page)

	_strip = HBoxContainer.new()
	_strip.add_theme_constant_override("separation", 24)
	page.add_child(_strip)

	_note = Label.new()
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.add_theme_font_size_override("font_size", 14)
	page.add_child(_note)

	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 6)
	page.add_child(_tabs)

	_body = Control.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(_body)


# =============================================================
#  THE STRIP: what is still missing
# =============================================================

func _refresh_strip() -> void:
	for child in _strip.get_children():
		child.queue_free()
	var now := TeamBuild.status(state, db)
	var stars_ok := int(now["stars"]) >= int(now["of"])
	var team_ok := int(now["players"]) >= TeamBuild.TEAM_SIZE
	_strip.add_child(_tick(stars_ok, "Stars placed  %d / %d" % [now["stars"], now["of"]]))
	_strip.add_child(_tick(team_ok, "Team  %d / %d%s" % [now["players"], TeamBuild.TEAM_SIZE,
		("  (%s)" % now["team"]) if String(now["team"]) != "" else ""]))
	if bool(now["ok"]):
		_note.text = "Ready. The Pub and every match are open."
		_note.add_theme_color_override("font_color", MenuSupport.COLOUR_ACCENT)
	else:
		_note.text = String(now["why"]) + "  The Pub and matches open when both are ticked."
		_note.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)


func _tick(good: bool, words: String) -> Label:
	var label := Label.new()
	label.text = ("✔  " if good else "✖  ") + words
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color",
		MenuSupport.COLOUR_ACCENT if good else Color(0.9, 0.55, 0.4))
	return label


# =============================================================
#  THE TABS
# =============================================================

## The tabs that show, in order: Tuning.csv `team_build_tabs`, names from
## TABS split by `;`. A blank or misspelt row shows them all.
static func shown_tabs() -> Array[String]:
	var out: Array[String] = []
	var said := ";".join(TABS)
	var book := CardDatabase.get_db()
	if book != null:
		said = book.tune_text("team_build_tabs", said)
	for part in said.split(";", false):
		for name_text in TABS:
			if name_text.to_lower() == part.strip_edges().to_lower() and not out.has(name_text):
				out.append(name_text)
	if out.is_empty():
		out.assign(TABS)
	return out


func _show(which: String) -> void:
	var shown := shown_tabs()
	_tab = which if shown.has(which) else shown[0]
	for child in _tabs.get_children():
		child.queue_free()
	for name_text in shown:
		var button := Button.new()
		button.text = name_text.to_upper()
		button.custom_minimum_size = Vector2(170, 38)
		button.add_theme_stylebox_override("normal", MenuSupport.styled("tab",
			"selected" if name_text == _tab else ""))
		button.add_theme_stylebox_override("hover", MenuSupport.styled("tab", "selected"))
		if name_text == "Talents" and not state.is_unlocked(TALENT_UNLOCK):
			button.tooltip_text = "Opens with the Talent Tree unlock."
		button.pressed.connect(_show.bind(name_text))
		_tabs.add_child(button)

	for child in _body.get_children():
		child.queue_free()
	match _tab:
		"Star Hall":
			_embed(ScenePaths.CLASS_TREE)
		"Your Teams":
			_body.add_child(_teams_panel())
		"Talents":
			if state.is_unlocked(TALENT_UNLOCK):
				_embed(ScenePaths.TALENTS)
			else:
				_body.add_child(_words("The talents open with the Talent Tree unlock - the same achievement that used to put the building on the base."))
	_refresh_strip()


## Put an existing screen inside the tab, told it is in a window so it
## leaves the background, the title and the Back button to us.
func _embed(scene_path: String) -> void:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		_body.add_child(_words("%s is missing." % scene_path))
		return
	var screen := packed.instantiate() as Control
	screen.set_meta("windowed", true)
	screen.set_meta("in_team_build", true)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Whatever happens in there - a Star placed - the strip says so on the
	# way out of the tab. Cheap, and never stale for more than one click.
	screen.tree_exiting.connect(_refresh_strip)
	_body.add_child(screen)


func _words(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	label.add_theme_font_size_override("font_size", 16)
	return label


# =============================================================
#  YOUR TEAMS
# =============================================================

func _teams_panel() -> Control:
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 8)

	var book := TeamRoster.load_all()
	if book.teams.is_empty():
		column.add_child(_words("No teams yet. Create one: pick a class, and its three Stars and nine more make the twelve."))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)

	for entry in book.teams:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		var count := TeamBuild.team_count(entry)
		var short := book.trouble(entry, db)
		var stars := TeamBuild.stars_trouble(String(entry["class"]), state)
		var line := Label.new()
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var players := TeamBuild.TEAM_SIZE if short == "" else count
		var gaps: PackedStringArray = []
		if short != "":
			gaps.append(short)
		if stars != "":
			gaps.append(stars)
		line.text = "%s   ·   %s%s   ·   %d / %d players%s" % [entry["name"],
			(PlayerRoles.team_label(String(entry.get("kind", "match"))) + "   ·   ") if PlayerRoles.on(db) else "",
			entry["class"],
			players, TeamBuild.TEAM_SIZE,
			"" if gaps.is_empty() else "   —   " + "; ".join(gaps)]
		line.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT
			if (short == "" and stars == "") else MenuSupport.COLOUR_TEXT_DIM)
		row.add_child(line)
		var edit := MenuSupport.icon_button("edit|✎", "Edit", Vector2(150, 44))
		edit.pressed.connect(func() -> void:
			state.set_text("last_team", String(entry["id"]))
			TeamBuilderHandoff.edit(get_tree(), String(entry["id"]))
			state.save_to_disk()
			ScenePaths.go_to(get_tree(), ScenePaths.TEAM_BUILDER))
		row.add_child(edit)
		list.add_child(row)

	var make := MenuSupport.icon_button("new_team|+", "Create a team", Vector2(240, 54))
	make.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	make.pressed.connect(func() -> void:
		TeamBuilderHandoff.clear(get_tree())
		# A Match Team to start with; the builder's button switches it.
		TeamBuilderHandoff.set_kind(get_tree(), PlayerRoles.MATCH)
		state.save_to_disk()
		ScenePaths.go_to(get_tree(), ScenePaths.CLASS_SELECT))
	column.add_child(make)
	return column
