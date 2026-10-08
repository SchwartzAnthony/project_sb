class_name TeamSelect
extends Control

# =============================================================
#  CHOOSE YOUR TEAM — the shelf you pick a side off
#
#  This replaces "Choose your class". Picking a class is now something you
#  do ONCE, while making a team; from then on you pick the team.
#
#      A team card       badge, name, class, how many it fields
#      LOCK IN           straight to the match. No detour.
#      EDIT TEAM         opens the builder on the team you picked
#      CREATE TEAM       the class picker, then the builder
#
#  WITH NO TEAMS SAVED there is one button on the screen and it says CREATE
#  TEAM, because that is the only thing you can do.
#
#  Everything on this screen comes from user://teams.json through
#  TeamRoster. Nothing here knows a class or a card by name.
# =============================================================

const CARD := Vector2(300.0, 132.0)

var db: CardDatabase
var state: GameState
var book: TeamRoster

var _chosen: String = ""
var _list: VBoxContainer
var _detail: Label
var _lock: Button
var _edit: Button


func _ready() -> void:
	GameSpeed.reset()
	db = CardDatabase.get_db()
	state = GameState.fetch(get_tree())
	# Turned players wear their new class, and named recruits are in the
	# list, before anything here sorts cards by class. See transform_book.gd.
	TransformBook.apply_all(db, state)
	book = TeamRoster.load_all()
	MenuEscape.install(self)

	# ============ A MATCH WITH A SQUAD OF ITS OWN (round AN) ============
	#
	# The first match of a new game is not played by your team: the mode
	# names a squad CSV (MatchModes.csv, Squad column) and that side walks
	# straight out. There is nothing to pick, so this screen steps aside.
	var squad := MatchMode.squad_file(get_tree())
	if squad != "":
		var picked := SquadSheet.selection_from(squad, db, state)
		if picked != null:
			TeamSelection.store(get_tree(), picked)
			var scene := String(MatchMode.current(get_tree()).get("scene", "match"))
			ScenePaths.go_to(get_tree(), ScenePaths.for_name(scene))
			return

	_build()
	_fill()

	# Open on the team you played last, so pressing through to a match twice
	# in a row takes two clicks rather than a hunt.
	var last := state.text("last_team", "")
	var shown := _shown_teams()
	if last != "" and shown.has(book.find(last)):
		_pick(last)
	elif not shown.is_empty():
		_pick(String(shown[0]["id"]))
	else:
		_refresh_footer()


# -------------------------------------------------------------
#  LAYOUT
# -------------------------------------------------------------

func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = MenuSupport.COLOUR_BACKGROUND
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 22)
	add_child(margin)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 14)
	margin.add_child(page)

	page.add_child(MenuSupport.heading("CHOOSE YOUR %s" % (
		PlayerRoles.team_label(_kind()).to_upper() if PlayerRoles.on(db) else "TEAM"),
		34, MenuSupport.COLOUR_ACCENT))
	page.add_child(MenuSupport.heading(
		"Pick a side and lock in. Building one is something you do once — after that it is yours.",
		14, MenuSupport.COLOUR_TEXT_DIM))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_list)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	page.add_child(footer)

	var back := MenuSupport.icon_button("back|←", "Back", Vector2(150, 54))
	back.pressed.connect(func() -> void:
		state.save_to_disk()
		ScenePaths.go_back(get_tree(), ScenePaths.BASE))
	footer.add_child(back)

	var make := MenuSupport.icon_button("new_team|+", "Create team", Vector2(210, 54))
	make.tooltip_text = "Pick a class, then build the nine regulars."
	make.pressed.connect(_on_create)
	footer.add_child(make)

	_edit = MenuSupport.icon_button("edit|✎", "Edit team", Vector2(190, 54))
	_edit.tooltip_text = "Change this team's line-up, name or badge."
	_edit.pressed.connect(_on_edit)
	footer.add_child(_edit)

	# ============ KNOW WHO YOU ARE PLAYING ============
	#
	# The ladder makes every legal team the same total power on purpose, so
	# the interesting question is never "are they stronger" — it is "what do
	# their players DO". That question deserves an answer you can go and read
	# BEFORE you choose a side, not one you learn by losing.
	var scout := MenuSupport.icon_button("scout|◎", "Enemy Team Data", Vector2(250, 54))
	scout.tooltip_text = "The side you are about to play: every unit, its power, and what its abilities do."
	scout.pressed.connect(_show_enemy_team)
	footer.add_child(scout)

	_detail = Label.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_theme_font_size_override("font_size", 14)
	_detail.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	footer.add_child(_detail)

	_lock = MenuSupport.icon_button("play|▶", "LOCK IN", Vector2(230, 54))
	_lock.tooltip_text = "Straight to the match with this side."
	_lock.pressed.connect(_on_lock)
	footer.add_child(_lock)


## THE OPPOSITION, BEFORE YOU PICK. A league fixture names the class in
## Season.csv, so their whole squad can be listed. A friendly picks at
## kick-off, so there is nothing to show yet and the window says so rather
## than being missing.
func _show_enemy_team() -> void:
	# ============ AN ADVENTURE RUN IS NOT A LEAGUE SQUAD ============
	#
	# It used to show whichever class the next FIXTURE named, even when you
	# were about to walk into the Marshlands — so the window in front of an
	# Adventure was a list of people you were not going to meet. It reads the
	# run's own biome now.
	var lines := _adventure_enemies()
	if not lines.is_empty():
		EnemyTeamWindow.open(self, db, _adventure_where(), [], [],
			"Everything that lives here. What turns up on any one wave is drawn from this pool by Weight.", lines)
		return

	var klass := _next_opponent_class()
	var squad: Array[PlayerData] = []
	var their_stars: Array[PlayerData] = []
	if klass != "":
		squad = db.roster_for_class(klass)
		their_stars = db.stars_for_class(klass)
		for star in their_stars:
			if not squad.has(star):
				squad.append(star)

	EnemyTeamWindow.open(self, db, klass, squad, their_stars,
		"" if klass != "" else "This is a friendly — the opposition is chosen at kick-off. A league fixture names them in Season.csv.")


## HOW MANY FIT PLAYERS A TIER NEEDS FOR THE MODE YOU ARE ABOUT TO PLAY.
## The `Squad Per Tier` column of MatchModes.csv: three for a league match,
## one for an Adventure run.
func _fit_needed() -> int:
	# A COMPETITION MAY OVERRIDE THE MODE. `season_per_tier` is 0 out of the
	# box, which means "use the mode's own number"; the Per Tier column of
	# SeasonRules.csv lends a different one for the length of a competition.
	var lent := db.tune_int("season_per_tier", 0)
	if lent > 0:
		return lent
	return maxi(1, int(MatchMode.current(get_tree()).get("per_tier", 3)))


## Which class the next fixture puts in front of you, or "" for a friendly.
func _next_opponent_class() -> String:
	var fixture := SeasonDB.get_db().current(state) if SeasonDB.get_db() != null else {}
	if fixture.is_empty():
		return ""
	var named := String(fixture.get("class", "")).strip_edges()
	if named != "":
		return named
	# A fixture that names a TEAM rather than a class: look the team up.
	var team := String(fixture.get("team", "")).strip_edges()
	if team == "":
		return ""
	for row in MenuSupport.read_csv("res://data/Teams.csv"):
		if CardDatabase._normalise(MenuSupport.field(row, "ID")) == CardDatabase._normalise(team) \
				or CardDatabase._normalise(MenuSupport.field(row, "Name")) == CardDatabase._normalise(team):
			return MenuSupport.field(row, "Class").strip_edges()
	return ""


# -------------------------------------------------------------
#  THE SHELF
# -------------------------------------------------------------

## ROUND AN: the kind of team this mode takes - an Adventure run an
## Adventure Team, everything else a Match Team (player_roles.gd).
func _kind() -> String:
	return PlayerRoles.kind_for_mode(get_tree())


## The teams on the shelf: only the right kind while player_roles is on.
func _shown_teams() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in book.teams:
		if not PlayerRoles.on(db) or String(entry.get("kind", "match")) == _kind():
			out.append(entry)
	return out


func _fill() -> void:
	for child in _list.get_children():
		child.queue_free()

	if _shown_teams().is_empty():
		var none := VBoxContainer.new()
		none.add_theme_constant_override("separation", 8)
		none.add_child(MenuSupport.heading("No %ss yet" % PlayerRoles.team_label(_kind())
			if PlayerRoles.on(db) else "No teams yet", 24, MenuSupport.COLOUR_TEXT))
		var line := Label.new()
		line.text = "Press CREATE TEAM. You pick a class, choose nine regulars — one of each power in every tier — give them a name and a badge, and they are yours from then on."
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.custom_minimum_size = Vector2(0, 0)
		line.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
		none.add_child(line)
		_list.add_child(none)
		return

	for entry in _shown_teams():
		_list.add_child(_team_card(entry))


func _team_card(entry: Dictionary) -> Control:
	var id_text := String(entry["id"])
	var trouble := book.trouble(entry, db, _fit_needed())
	if trouble == "":
		trouble = _stars_missing(entry)
	if trouble == "":
		trouble = book.resting(entry, db, state, _fit_needed())

	var button := Button.new()
	button.custom_minimum_size = CARD
	button.focus_mode = Control.FOCUS_NONE
	var lit := id_text == _chosen
	var tint := MenuSupport.COLOUR_ACCENT if lit else MenuSupport.COLOUR_TEXT_DIM
	if trouble != "":
		tint = Color(0.86, 0.48, 0.38)
	button.add_theme_stylebox_override("normal",
		MenuSupport.panel_style(MenuSupport.COLOUR_PANEL, tint))
	button.add_theme_stylebox_override("hover",
		MenuSupport.panel_style(MenuSupport.COLOUR_SLOT_EMPTY, MenuSupport.COLOUR_ACCENT))
	button.pressed.connect(_pick.bind(id_text))

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(row)

	var pad := Control.new()
	pad.custom_minimum_size = Vector2(6, 0)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(pad)

	var badge := TeamRoster.badge(entry, 84.0)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(badge)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 3)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)

	var name_label := Label.new()
	name_label.text = String(entry["name"])
	name_label.add_theme_font_size_override("font_size", 24)
	name_label.add_theme_color_override("font_color",
		MenuSupport.COLOUR_ACCENT if lit else MenuSupport.COLOUR_TEXT)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_label)

	var sub := Label.new()
	sub.text = book.describe(entry, db)
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(sub)

	if trouble != "":
		var warn := Label.new()
		warn.text = "⚠  " + trouble
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		warn.add_theme_font_size_override("font_size", 12)
		warn.add_theme_color_override("font_color", Color(0.90, 0.55, 0.45))
		warn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(warn)

	return button


func _pick(team_id: String) -> void:
	_chosen = team_id
	_fill()
	_refresh_footer()


func _refresh_footer() -> void:
	var entry := book.find(_chosen)
	var has := not entry.is_empty()

	# WITH NOTHING SAVED, CREATE TEAM IS THE ONLY BUTTON. Showing a greyed-out
	# LOCK IN to somebody who has no team to lock in is just noise.
	var any_teams := not _shown_teams().is_empty()
	_lock.visible = any_teams
	_edit.visible = any_teams
	_lock.disabled = not has
	_edit.disabled = not has

	if not has:
		_detail.text = "No team chosen." if any_teams else ""
		return
	var trouble := book.trouble(entry, db, _fit_needed())
	if trouble == "":
		trouble = _stars_missing(entry)
	if trouble != "":
		_lock.disabled = true
		_detail.text = "%s cannot take the pitch — %s" % [entry["name"], trouble]
		return
	# A SIDE THAT IS FINE BUT TIRED. Worded differently on purpose: the team
	# is not broken, it played last week. Adventure asks for one fit player a
	# tier rather than three, so this is also the nudge toward going and
	# earning the rest back.
	var worn := book.resting(entry, db, state, _fit_needed())
	if worn != "":
		_lock.disabled = true
		_detail.text = "%s is too tired — %s" % [entry["name"], worn]
		return
	_detail.text = "%s is ready." % entry["name"]


# -------------------------------------------------------------
#  THE THREE BUTTONS
# -------------------------------------------------------------

func _on_create() -> void:
	# No team id stashed means "make a new one": the class picker opens, and
	# the builder that follows it starts from scratch.
	TeamBuilderHandoff.clear(get_tree())
	TeamBuilderHandoff.set_kind(get_tree(), _kind())
	state.save_to_disk()
	ScenePaths.go_to(get_tree(), ScenePaths.CLASS_SELECT)


func _on_edit() -> void:
	if _chosen == "":
		return
	TeamBuilderHandoff.edit(get_tree(), _chosen)
	state.save_to_disk()
	ScenePaths.go_to(get_tree(), ScenePaths.TEAM_BUILDER)


## LOCK IN GOES TO THE MATCH. Not to the builder — that is what EDIT TEAM
## is for, and separating them is the whole point of this screen.
func _on_lock() -> void:
	var entry := book.find(_chosen)
	if entry.is_empty() or book.trouble(entry, db, _fit_needed()) != "":
		return
	if _stars_missing(entry) != "":
		_detail.text = "%s cannot take the pitch — %s." % [entry["name"], _stars_missing(entry)]
		return
	if book.resting(entry, db, state, _fit_needed()) != "":
		return

	TeamSelection.store(get_tree(), book.to_selection(entry, db))
	state.set_text("last_team", _chosen)
	state.save_to_disk()
	print("[teams] Taking the field as %s." % entry["name"])

	# The mode decides which screen a team walks out onto — the pitch for a
	# league match, the scroll for an Adventure run.
	var scene := String(MatchMode.current(get_tree()).get("scene", "match"))
	ScenePaths.go_to(get_tree(), ScenePaths.for_name(scene))


## WHERE THIS RUN IS GOING, or "" when it is not an Adventure.
func _adventure_where() -> String:
	var run := AdventureRun.current(get_tree())
	return run.biome_name() if run != null else ""


## Everything that lives in this run's biome, one line each. Empty when the
## next thing you are playing is not an Adventure.
func _adventure_enemies() -> Array[String]:
	var out: Array[String] = []
	var run := AdventureRun.current(get_tree())
	if run == null:
		return out
	var adventure := AdventureDB.get_db()
	if adventure == null:
		return out
	var pool := String(run.biome.get("pool", ""))
	if pool == "":
		return out

	# THE BOSS LAST, and marked. It is the one you are walking towards.
	var ordinary: Array[String] = []
	var bosses: Array[String] = []
	for foe in adventure.pool_enemies(pool):
		var words := "%s  ·  attack %d  ·  %d layer(s)  ·  turns up %s" % [
			foe["name"], int(foe.get("attack", 0)),
			AdventureDB.total_layers(foe), _how_often(int(foe.get("weight", 0)))]
		if bool(foe.get("boss", false)):
			bosses.append("THE BOSS — " + words)
		else:
			ordinary.append(words)
	out.append_array(ordinary)
	out.append_array(bosses)
	return out


## A Weight read back in words. A number nobody can feel becomes a sentence
## everybody can: 10 against 2 is "often" against "rarely".
func _how_often(weight: int) -> String:
	if weight >= 10:
		return "often"
	if weight >= 5:
		return "sometimes"
	if weight > 0:
		return "rarely"
	return "only when something calls it"


## ROUND Y: a MATCH needs this team's Stars in the Star Hall. An Adventure
## run does not - you said Adventure comes later. "" when it may go.
func _stars_missing(entry: Dictionary) -> String:
	if String(MatchMode.current(get_tree()).get("scene", "match")) != "match":
		return ""
	if TutorialBase.active(get_tree()):
		return ""
	return TeamBuild.team_trouble(entry, state, db)
