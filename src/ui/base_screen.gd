class_name BaseScreen
extends Control

# =============================================================
#  THE BASE — your hub between matches
#
#  Everything on this screen comes from two spreadsheets:
#    res://data/Buildings.csv    what stands here
#    res://data/Visitors.csv     who is here and what they want
#
#  Nothing in this file needs editing to add either. Put a row in the CSV,
#  press F5, it is on the screen.
#
#  ART (all optional — it works with none of it)
#    res://assets/base/background.png    behind everything: the town map,
#        built from data/BaseTown.csv by tools/make_base_town.py
#    res://assets/base/<Art>.png         a building, named in Buildings.csv
#    res://assets/portraits/<Portrait>.png   a visitor
#
#  Without art you get a labelled plaque for a building and a lettered
#  circle for a visitor, so you can lay the whole base out and play it
#  before drawing anything.
# =============================================================

const BACKGROUND_DIRS: Array[String] = ["res://assets/base/", "res://assets/backgrounds/"]
const BUILDING_DIRS: Array[String] = ["res://assets/base/", "res://assets/buildings/", "res://assets/"]
const MAP_ART_DIRS: Array[String] = ["res://assets/base/map/"]
const PORTRAIT_DIRS: Array[String] = ["res://assets/portraits/", "res://assets/players/", "res://assets/"]

const BUILDING_SIZE := Vector2(190.0, 132.0)
const VISITOR_SIZE := Vector2(120.0, 150.0)

## How far from the left edge the exit buttons may start. It keeps them off
## the "THE BASE" title; below this the row simply wraps onto a second line.
const EXITS_LEFT_MARGIN := 270.0

## The size of one exit button. They are icon-and-text buttons now — a small
## picture on the left, the words on the right, one button — so they want a
## little more room than a plain label did.
const EXIT_SIZE := Vector2(196.0, 52.0)

## The flag banners that replace the exit buttons once drawn (round AN):
## a PixelLab cloth on the one shared rod, hanging from the top of the screen.
const BANNER_DIR := "res://assets/ui/banners/"
const BANNERS_LEFT := 556.0
const BANNER_SOUND := "banner_flutter"
const BANNERS_RIGHT := 490.0
## A banner from tools/make_banners.py, drawn 1:1; seven fit between
## the Pub's roof and the Club House's (Dev is not one of them).
const BANNER_SIZE := Vector2(129.0, 168.0)

var db: CardDatabase
var base: BaseDB
var state: GameState
var steps: Progression

var _world: Control
var _detail: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	db = CardDatabase.get_db()
	base = BaseDB.get_db()
	state = GameState.fetch(get_tree())
	steps = Progression.get_rules()

	# Escape ends the game from here, as it does from every screen that is
	# not a live match. See menu_escape.gd.
	MenuEscape.install(self)

	_build_chrome()
	_report_problems()
	_rebuild()

	# ============ A BRAND NEW SAVE ============
	#
	# `new_game` fires ONCE per save, the first time the base is opened on a
	# slot that has never been played. That is the moment the opening of the
	# game belongs to: the three players you are given, the flag that makes
	# the first match the scripted one, the first scene.
	#
	# It is a flag in the save rather than a check on whether the file
	# exists, because a save is written the moment anything happens and
	# "has this save ever been played" then stops being answerable.
	if state != null and not state.has_flag("game_begun"):
		state.set_flag("game_begun")
		state.save_to_disk()
		_advance_progression("new_game")
		# ROUND AN (Anthony, 7 Oct): "would you like to do the Tutorial? If
		# not, you can find it later on the main menu." Yes plays it in this
		# save; no gives the base its starting team and nothing else.
		if Tutorial.offer_on_new_game() and not TutorialBase.active(get_tree()) \
				and not Tutorial.active(get_tree()):
			await get_tree().process_frame
			if await Tutorial.ask(self):
				Tutorial.start(get_tree(), false)
				return
			Tutorial.give_starting_team(state)
			_rebuild()

	# Anything Progression.csv wants to happen when the base is opened. This
	# is where the prologue now lives, rather than firing at launch.
	_advance_progression("base_opened")

	# Anything you unlocked since you were last here flashes up on top, with a
	# Continue button, and is then marked as seen. One frame's wait lets the
	# base finish drawing so the panel lands over a finished screen.
	await get_tree().process_frame
	_flash_new_unlocks()


## The bottom line only shows its plate while it has something to say.
func _process(_delta: float) -> void:
	if _detail != null:
		_detail.visible = _detail.text != ""


# =============================================================
#  LAYOUT
# =============================================================

func _build_chrome() -> void:
	var fill := ColorRect.new()
	fill.color = MenuSupport.COLOUR_BACKGROUND
	fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fill)

	var art := _find_texture("background", BACKGROUND_DIRS)
	if art != null:
		var backdrop := TextureRect.new()
		backdrop.texture = art
		backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		backdrop.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(backdrop)

	# A see-through black sheet over the town map so the plaques read on it.
	# `base_map_shade` in Tuning.csv: 0 shows the map at full colour.
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, clampf(db.tune_float("base_map_shade", 0.30), 0.0, 1.0))
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	# Buildings and visitors live in here, positioned by their X,Y fractions.
	_world = Control.new()
	_world.name = "World"
	_world.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_world)
	_world.resized.connect(_rebuild)

	var in_tutorial := TutorialBase.active(get_tree())
	var title := MenuSupport.heading(
		"TUTORIAL BASE" if in_tutorial else "THE BASE",
		34, MenuSupport.COLOUR_ACCENT)
	# Only as wide as its words, so its see-through plate (TextBackdrop)
	# hugs the title instead of running across the town map.
	title.position = Vector2(40.0, 26.0)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)
	TextBackdrop.give(title)

	# The line that explains whatever you last clicked.
	# Centred at the bottom and only as wide as its words, on a see-through
	# black plate so it reads on the town map. Hidden while it says nothing.
	_detail = Label.new()
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail.add_theme_font_size_override("font_size", 17)
	_detail.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT)
	_detail.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_detail.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_detail.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_detail.offset_bottom = -80.0
	_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail.visible = false
	add_child(_detail)
	TextBackdrop.give(_detail)

	# ============ NO FOOTER ============
	#
	# There used to be a line along the bottom listing every unlock you had
	# ever earned. It was a DEVELOPER'S line — useful to me while wiring
	# content, and to a player a wall of small text under their base saying
	# things they already know. The Achievements building says all of it
	# properly, and says what is still missing as well.
	#
	# If you ever want it back while writing content, the same information is
	# one line: `print(state.unlocked_names())`.

	_build_exits()


## THE EXIT BUTTONS, ACROSS THE MIDDLE OF THE TOP.
##
## Two things changed here and both are worth knowing about.
##
## FIRST, WHERE THEY SIT. They used to be crushed into the top-right corner
## inside a fixed 810-pixel box, which cut the left-most ones off as soon as
## a sixth button existed. They are centred across the top now, in an
## HFlowContainer — a row that WRAPS onto a second line instead of
## overflowing. So:
##   * nothing is ever cut off, at any window size
##   * on a narrow screen (the Steam Deck is 1280 wide) the row becomes two
##   * you can add a seventh and eighth button without touching this code
##
## SECOND, WHAT THEY LOOK LIKE. Each one is a single button in two parts: a
## picture on the left, the words on the right. The picture is real art the
## moment you drop a PNG into res://assets/icons/ named after the word before
## the `|` — icons/season.png, icons/play.png, icons/adventure.png — and a
## drawn symbol until then. You never have to come back to this file for it.
##
## THERE IS NO "MAIN MENU" BUTTON. Escape leaves the game from anywhere, so
## the base does not need a door back to the title screen.
func _build_exits() -> void:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", -6)
	row.add_theme_constant_override("v_separation", 8)
	row.set_anchors_preset(Control.PRESET_TOP_WIDE)
	# Clear of the title on the left, a margin in from the right, and centred
	# in what is left — which on any ordinary window is the middle of the top.
	# The banners hang in the sky between the Pub's roof and the Club
	# House's (BANNERS_LEFT / BANNERS_RIGHT); the old buttons used the width.
	var banners := ResourceLoader.exists(BANNER_DIR + "play.png")
	row.offset_left = BANNERS_LEFT if banners else EXITS_LEFT_MARGIN
	row.offset_top = 0.0
	row.offset_right = -BANNERS_RIGHT if banners else -30.0
	# Tall enough for two wrapped lines. It is only a ceiling — one line of
	# buttons still draws as one line.
	row.offset_bottom = BANNER_SIZE.y * 2.0 + 8.0
	row.alignment = FlowContainer.ALIGNMENT_CENTER
	# The buttons are the only thing here that should catch a click; the gaps
	# between them belong to the base underneath.
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)

	# The developer tools. `show_dev_tools` in Tuning.csv hides this button
	# before you show the game to anyone; the screen itself stays put.
	# ROUND AN: it is NOT one of the banners. The banner row is laid out the
	# way the released game shows it, and Dev sits on its own, small, in the
	# bottom-left corner while we test.
	if db.tune_bool("show_dev_tools", true):
		var to_dev := MenuSupport.icon_button("dev|⚙", "Dev", Vector2(110, 40))
		to_dev.tooltip_text = "The save inspector. Jump straight to any unlock. Testing only."
		to_dev.pressed.connect(func() -> void:
			state.save_to_disk()
			ScenePaths.go_to(get_tree(), ScenePaths.INSPECTOR))
		to_dev.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		to_dev.offset_left = 12.0
		to_dev.offset_top = -52.0
		to_dev.offset_right = 122.0
		to_dev.offset_bottom = -12.0
		add_child(to_dev)

	# ============ THE UNLOCKS BUTTON IS GONE ============
	#
	# It showed everything you can earn and what is missing — which is
	# exactly what the ACHIEVEMENTS building on the base now shows, in the
	# same words, from the same file. Two doors to one room is one door too
	# many, and the one that is a building is the one that belongs.
	#
	# The screen itself is still in the project and still works: `goto:board`
	# opens it, and tools/unlock_progress.gd still reports through it.

	# ACHIEVEMENTS, up here since round AN: Anthony took its building off the
	# town map, and it is the root of every unlock, so it still needs a door.
	# It runs the same `window:achievements` the building's Action did.
	var to_achievements := _exit("achievements|★",
		Loc.text("achievements_button", "Achievements"), EXIT_SIZE)
	to_achievements.tooltip_text = "Everything in this game is unlocked here first."
	to_achievements.pressed.connect(func() -> void:
		_carry_out(Progression.run_actions("window:achievements", state)))
	row.add_child(to_achievements)

	# THE BAG, WHERE YOU ARE STANDING. Everything you have carried home is in
	# it, and the base is where you are when you want to know what that is.
	# It opens the same window the Bounty Board, an Adventure fight and the
	# match draft open — see inventory_screen.gd — and it is built with the
	# same icon_button() as everything else in this row, so it looks like a
	# door rather than a new kind of control.
	var to_bag := _exit("inventory|⚒",
		Loc.text("inventory", "Inventory"), EXIT_SIZE)
	to_bag.tooltip_text = "Everything you are carrying: what you can use, what you can spend, and what you are holding on to."
	to_bag.pressed.connect(func() -> void:
		InventoryScreen.open(self, state, InventoryScreen.Use.NOTHING))
	row.add_child(to_bag)

	# THE STADIUM FLAG IS GONE (round AN, Anthony: "remove the soccer field
	# flag"). The Stadium screen itself still works - ScenePaths.STADIUM, or a
	# `window:stadium` Action in Buildings.csv brings a door back.
	# Inventory hangs in its place, second from the left.

	# THE SEASONS SHELF, not the table. There is more than one competition
	# now — Seasons.csv — and the table is what opens when you pick one.
	var to_season := _exit("season|▦",
		Loc.text("the_season", "The season"), EXIT_SIZE)
	to_season.tooltip_text = "Every competition you can enter. Pick one and its table opens."
	to_season.pressed.connect(func() -> void:
		if _turned_away():
			return
		state.save_to_disk()
		ScenePaths.go_to(get_tree(), ScenePaths.SEASON_PICKER))
	row.add_child(to_season)

	# PLAY A MATCH IS NOT THE SEASON. It is a friendly against a side put
	# together on the spot at roughly your own level, and you still collect
	# for playing it — the `friendly` row of MatchModes.csv says both, through
	# its Opponent column and its two Rewards columns. The league is behind
	# "The season" next door.
	var to_match := _exit("play|▶", "Play a match", EXIT_SIZE)
	to_match.tooltip_text = "A friendly against a side at your own level. Nothing goes in the table, but you still come away with something."
	to_match.pressed.connect(func() -> void:
		# ROUND AN (Anthony): the flag opens THE MATCH MAKER first - a 3, 2
		# or 1 cycle match, data/MatchMaker.csv. Not while a story match
		# stands in for the friendly (the first match of a new game): that
		# one has its own length, so it starts straight away as before.
		if MatchMode.stand_in_for("friendly", state) != "friendly":
			_play_match("friendly")
			return
		MatchMaker.open(self, state, _play_match))
	row.add_child(to_match)

	# ADVENTURE FROM THE BASE. This is where you are standing when you realise
	# you need materials and the buildings that would make them are not built
	# yet, so the button belongs beside the buildings rather than only on the
	# title screen. It opens the Bounty Board, not a match.
	var to_adventure := _exit("adventure|⛰", "Adventure", EXIT_SIZE)
	to_adventure.tooltip_text = "The Bounty Board. Pick a biome and a boss, then set off for materials and recipes."
	to_adventure.pressed.connect(func() -> void:
		state.save_to_disk()
		ScenePaths.go_to(get_tree(), ScenePaths.BOUNTY_BOARD))
	row.add_child(to_adventure)

	var to_teams := _exit("teams|⚑", "Your teams", EXIT_SIZE)
	to_teams.tooltip_text = "Team Build: your Stars and your sides."
	to_teams.pressed.connect(func() -> void:
		# ROUND Y: the same hub as the building, opened on the teams tab.
		state.save_to_disk()
		TeamBuildScreen.open_on = "Your Teams"
		var opened := BaseWindow.open(self, "Team Build", ScenePaths.TEAM_BUILD)
		if opened != null:
			opened.closed.connect(_rebuild))
	row.add_child(to_teams)

	# THE WAY OUT OF THE TUTORIAL, and only there. In the real base there is
	# nothing to leave — Escape ends the game.
	if TutorialBase.active(get_tree()):
		var leave := _exit("exit|⏏", "Leave tutorial", EXIT_SIZE)
		leave.tooltip_text = "Back to the title screen. Your real save is untouched by anything in here."
		leave.pressed.connect(func() -> void:
			TutorialBase.leave(get_tree()))
		row.add_child(leave)

	_same_thread_size(row)


## Every banner's name in the same size of thread (Anthony: the banners look
## the same, only the emblem and the name differ). Each banner shrinks its own
## name until it fits; this then gives all of them the smallest of those.
func _same_thread_size(row: Control) -> void:
	var names: Array[Label] = []
	var smallest := 999
	for door in row.get_children():
		for child in door.get_children():
			if child is Label and child.has_theme_font_size_override("font_size"):
				names.append(child)
				smallest = mini(smallest, child.get_theme_font_size("font_size"))
	for words in names:
		words.add_theme_font_size_override("font_size", smallest)


## One door on the top row. ROUND AN: a FLAG BANNER (MenuSupport.banner_button)
## when its banner is drawn - assets/ui/banners/<name>.png, the name being
## the part of `icon` before the | - and the old icon button until then.
func _exit(icon: String, label: String, box: Vector2 = EXIT_SIZE) -> Button:
	var art_name := icon.split("|")[0].strip_edges()
	var path := BANNER_DIR + art_name + ".png"
	if ResourceLoader.exists(path):
		var banner := MenuSupport.banner_button(load(path) as Texture2D, label, BANNER_SIZE)
		# The cloth folds in the wind when you point at it (Audio.csv).
		banner.mouse_entered.connect(func() -> void:
			AudioDirector.play_cue(get_tree(), BANNER_SOUND))
		banner.focus_entered.connect(func() -> void:
			AudioDirector.play_cue(get_tree(), BANNER_SOUND))
		return banner
	return MenuSupport.icon_button(icon, label, box)


# =============================================================
#  BUILDING THE BASE FROM THE CSVs
# =============================================================

func _rebuild() -> void:
	if _world == null:
		return
	# ROUND AN: the Head Coach's Guide.csv rows for the base, once the yard
	# is drawn (and again after any window over it closes).
	(func() -> void: Guide.check(self, "base", state)).call_deferred()
	for child in _world.get_children():
		child.queue_free()

	# ============ BUILDINGS FIRST, AND THEY KEEP THEIR SPOTS ============
	#
	# A building's X and Y are a promise: the Brewery is where you left it.
	# Every rectangle it takes is remembered so the visitors can be fitted
	# around them.
	_taken.clear()
	for entry in base.buildings_for(state):
		var plaque := _make_building(entry)
		_world.add_child(plaque)
		_taken.append(Rect2(plaque.position, plaque.size))

	# ============ AND THEN THE VISITORS, INTO WHATEVER IS LEFT ============
	#
	# "Not in the middle of the screen but rather on any empty space, please
	#  do not layer them."
	#
	# So a visitor's own X and Y are only a PREFERENCE now. If where they
	# want to stand is on top of a building or on top of another visitor,
	# they are moved to the nearest place that is free — and if the yard is
	# genuinely full they are not drawn at all, because a visitor you cannot
	# read is worse than a visitor who is not there.
	var spots := _visitor_spots()
	for entry in base.visitors_for(state):
		# ROUND AN: a visitor stands at a building's door, on its path
		# (data/BaseSpots.csv), a different one each time the base opens.
		var at_door := _door_for(entry, spots)
		if not at_door.is_empty():
			entry = entry.duplicate()
			entry["x"] = at_door["x"]
			entry["y"] = at_door["y"]
		var who := _make_visitor(entry)
		var found: Variant = who.position if not at_door.is_empty() \
			else _free_spot_near(who.position, VISITOR_SIZE)
		if found == null:
			who.queue_free()
			print("[base] No free space for %s — they wait outside." % entry["name"])
			continue
		var spot: Vector2 = found
		who.position = spot
		_world.add_child(who)
		_taken.append(Rect2(spot, VISITOR_SIZE))


## Every rectangle already standing in the yard this rebuild.
var _taken: Array[Rect2] = []

const SPOTS_FILE := "res://data/BaseSpots.csv"

## Which door each visitor picked, by visitor ID. Picked once per visit to
## the base, so closing a window (which rebuilds the yard) does not move them.
var _door_of: Dictionary = {}


## The doors visitors may stand at: every BaseSpots.csv row whose Building
## is on the map now (blank Building = always). Each is {spot, x, y}.
func _visitor_spots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not FileAccess.file_exists(SPOTS_FILE):
		return out
	var here: Dictionary = {}
	for entry in base.buildings_for(state):
		here[String(entry["id"])] = true
	var file := FileAccess.open(SPOTS_FILE, FileAccess.READ)
	var header := file.get_csv_line()
	var col: Dictionary = {}
	for i in header.size():
		col[CardDatabase._normalise(header[i])] = i
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() < header.size() or row[0].strip_edges() == "":
			continue
		var building := row[col.get("building", 1)].strip_edges()
		if building != "" and not here.has(building):
			continue
		out.append({"spot": row[0].strip_edges(), "building": building,
			"x": float(row[col.get("x", 2)]), "y": float(row[col.get("y", 3)])})
	return out


## The door this visitor stands at this visit, or {} for the old behaviour
## (their own X and Y, moved to free space). Two visitors never share one.
## A visitor with a Building in Visitors.csv only uses that building's doors
## (the Brewer stands at the Brewery); blank = any door.
func _door_for(entry: Dictionary, all_spots: Array[Dictionary]) -> Dictionary:
	var home := String(entry.get("building", "")).strip_edges()
	var spots: Array[Dictionary] = []
	for spot in all_spots:
		if home == "" or String(spot["building"]) == home:
			spots.append(spot)
	if spots.is_empty():
		return {}
	var who := String(entry["id"])
	var used: Dictionary = {}
	for other in _door_of:
		if other != who:
			used[_door_of[other]] = true
	if not _door_of.has(who) or used.has(_door_of[who]):
		var free: Array[String] = []
		for spot in spots:
			if not used.has(spot["spot"]):
				free.append(String(spot["spot"]))
		if free.is_empty():
			return {}
		_door_of[who] = free.pick_random()
	for spot in spots:
		if spot["spot"] == _door_of[who]:
			return spot
	_door_of.erase(who)
	return {}


## The nearest free place to `wanted` that a `box` fits in, or null.
##
## It searches outward in rings rather than scanning the whole yard from the
## top-left, so a visitor written at 0.5,0.5 ends up NEAR the middle rather
## than in the top-left corner — their column still means something, it is
## just no longer allowed to overlap anything.
func _free_spot_near(wanted: Vector2, box: Vector2) -> Variant:
	var area := _world.size
	if area.x < 2.0 or area.y < 2.0:
		area = get_viewport_rect().size
	var low := Vector2(8.0, 78.0)
	var high := Vector2(maxf(area.x - box.x - 8.0, 8.0), maxf(area.y - box.y - 130.0, 78.0))

	var step := 26.0
	for ring in 24:
		var reach := float(ring) * step
		# Ring 0 is the spot they asked for; after that, eight directions.
		#
		# WRITTEN OUT RATHER THAN AS A TERNARY, and that is not style. An
		# `a if c else b` over two Array literals is an untyped Array, and
		# assigning one to an Array[Vector2] is refused AT RUNTIME — the
		# whole search silently did nothing and every visitor was told there
		# was no room. Third time this project has met that rule.
		var tries: Array[Vector2] = []
		if ring == 0:
			tries.append(wanted)
		else:
			tries.append(wanted + Vector2(reach, 0.0))
			tries.append(wanted + Vector2(-reach, 0.0))
			tries.append(wanted + Vector2(0.0, reach))
			tries.append(wanted + Vector2(0.0, -reach))
			tries.append(wanted + Vector2(reach, reach))
			tries.append(wanted + Vector2(-reach, reach))
			tries.append(wanted + Vector2(reach, -reach))
			tries.append(wanted + Vector2(-reach, -reach))
		for candidate in tries:
			var spot := Vector2(clampf(candidate.x, low.x, high.x),
				clampf(candidate.y, low.y, high.y))
			if _is_clear(Rect2(spot, box)):
				return spot
	return null


## Nothing already in the yard touches this rectangle. A small margin is
## added so two plaques never end up shoulder to shoulder with no gap.
func _is_clear(box: Rect2) -> bool:
	var padded := box.grow(10.0)
	for other in _taken:
		if padded.intersects(other):
			return false
	return true


## Where a 0..1 fraction lands on the actual screen, with the plaque centred
## on that point so a row of 0.5 really is the middle.
##
## `scenery` is for a building drawn as its own picture on the town map: it
## may reach the very edges of the screen (it is part of the landscape), so
## only the plaques keep clear of the top buttons and the bottom line.
func _place(node: Control, entry: Dictionary, box: Vector2, scenery: bool = false) -> void:
	var area := _world.size
	if area.x < 2.0 or area.y < 2.0:
		area = get_viewport_rect().size

	var low := Vector2(0.0, 0.0) if scenery else Vector2(8.0, 78.0)
	var high := area - box if scenery else area - box - Vector2(8.0, 130.0)
	high = Vector2(maxf(high.x, low.x), maxf(high.y, low.y))
	node.custom_minimum_size = box
	node.size = box
	node.position = Vector2(
		clampf(area.x * float(entry["x"]) - box.x * 0.5, low.x, high.x),
		clampf(area.y * float(entry["y"]) - box.y * 0.5, low.y, high.y))


func _make_building(entry: Dictionary) -> Control:
	var unlocked := bool(entry["unlocked"])
	var name_text := String(entry["name"])

	# A building that has its town-map picture IS that picture: no plaque.
	var map_art := _find_texture(String(entry.get("map_art", "")), MAP_ART_DIRS)
	if map_art != null:
		return _make_map_building(entry, map_art)

	var button := Button.new()
	button.tooltip_text = String(entry["description"])
	_place(button, entry, BUILDING_SIZE)

	var edge := MenuSupport.COLOUR_ACCENT if unlocked else MenuSupport.COLOUR_SLOT_EMPTY
	var fill := MenuSupport.COLOUR_PANEL if unlocked else MenuSupport.COLOUR_BACKGROUND
	button.add_theme_stylebox_override("normal", MenuSupport.panel_style(fill, edge))
	button.add_theme_stylebox_override("hover",
		MenuSupport.panel_style(MenuSupport.COLOUR_SLOT_EMPTY, edge))
	button.add_theme_stylebox_override("pressed",
		MenuSupport.panel_style(MenuSupport.COLOUR_SLOT_EMPTY, MenuSupport.COLOUR_ACCENT))

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	button.add_child(box)

	var art := _find_texture(String(entry["art"]), BUILDING_DIRS)
	if art != null:
		var picture := TextureRect.new()
		picture.texture = art
		picture.custom_minimum_size = Vector2(0, 78)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		picture.size_flags_vertical = Control.SIZE_EXPAND_FILL
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not unlocked:
			picture.modulate = Color(0.35, 0.35, 0.40, 1.0)
		box.add_child(picture)

	var label := Label.new()
	label.text = name_text if unlocked else name_text + "  (locked)"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color",
		MenuSupport.COLOUR_TEXT if unlocked else MenuSupport.COLOUR_TEXT_DIM)
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(label)

	button.pressed.connect(_on_building.bind(entry))
	return button


## THE BUILDING AS ITS OWN PICTURE (round AN). Buildings.csv `Map Art` names
## a picture in assets/base/map/; `Map Size` is how big it is drawn on the
## screen, WIDTHxHEIGHT (blank = the picture's own size x2). The picture is the button: hover brightens it, a locked
## building is drawn dark, and its name sits under it on a see-through plate.
func _make_map_building(entry: Dictionary, art: Texture2D) -> Control:
	var unlocked := bool(entry["unlocked"])
	var name_text := String(entry["name"])
	var box := Vector2(art.get_size()) * 2.0
	var wanted := String(entry.get("map_size", "")).to_lower().split("x")
	if wanted.size() == 2 and wanted[0].is_valid_float() and wanted[1].is_valid_float():
		box = Vector2(float(wanted[0]), float(wanted[1]))

	# Only its drawn pixels take the click (map_building.gd), so two
	# buildings whose empty corners overlap never open each other.
	var button := MapBuilding.new()
	button.use_picture(art)
	button.tooltip_text = String(entry["description"])
	var flat := StyleBoxEmpty.new()
	for look in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(look, flat)
	_place(button, entry, box, true)

	var picture := TextureRect.new()
	picture.texture = art
	picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var resting := Color.WHITE if unlocked else Color(0.35, 0.35, 0.40, 1.0)
	picture.modulate = resting
	button.add_child(picture)
	button.mouse_entered.connect(func() -> void:
		picture.modulate = resting * Color(1.25, 1.25, 1.25, 1.0))
	button.mouse_exited.connect(func() -> void:
		picture.modulate = resting)

	var label := Label.new()
	label.text = name_text if unlocked else name_text + "  (locked)"
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color",
		MenuSupport.COLOUR_TEXT if unlocked else MenuSupport.COLOUR_TEXT_DIM)
	# On the picture's bottom edge rather than under it, so a building at
	# the bottom of the screen keeps its name on screen.
	label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	# Buildings.csv `Name Offset` (x,y in screen pixels) moves the name off
	# the bottom middle, e.g. when a smaller building stands in front.
	var nudge := String(entry.get("name_offset", "")).split(",")
	if nudge.size() == 2 and nudge[0].strip_edges().is_valid_float() \
			and nudge[1].strip_edges().is_valid_float():
		var by := Vector2(float(nudge[0]), float(nudge[1]))
		label.offset_left += by.x
		label.offset_right += by.x
		label.offset_top += by.y
		label.offset_bottom += by.y
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(label)
	# Set here, not by TextBackdrop.give(): that skips words inside a Button,
	# and this button has no panel of its own to read them on.
	label.add_theme_stylebox_override("normal", TextBackdrop.plate())

	button.pressed.connect(_on_building.bind(entry))
	return button


func _make_visitor(entry: Dictionary) -> Control:
	var button := Button.new()
	button.tooltip_text = "Talk to %s" % entry["name"]
	_place(button, entry, VISITOR_SIZE)
	button.add_theme_stylebox_override("normal",
		MenuSupport.panel_style(Color(0.12, 0.13, 0.18, 0.85), MenuSupport.COLOUR_TEXT_DIM))
	button.add_theme_stylebox_override("hover",
		MenuSupport.panel_style(MenuSupport.COLOUR_SLOT_EMPTY, MenuSupport.COLOUR_ACCENT))

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(box)

	var art := _find_texture(String(entry["portrait"]), PORTRAIT_DIRS)
	if art != null:
		var picture := TextureRect.new()
		picture.texture = art
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		picture.size_flags_vertical = Control.SIZE_EXPAND_FILL
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(picture)
	else:
		# No portrait drawn yet: a big initial, so the base is still playable.
		var initial := Label.new()
		initial.text = String(entry["name"]).substr(0, 1).to_upper()
		initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		initial.add_theme_font_size_override("font_size", 54)
		initial.add_theme_color_override("font_color", MenuSupport.COLOUR_ACCENT)
		initial.size_flags_vertical = Control.SIZE_EXPAND_FILL
		initial.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(initial)

	var label := Label.new()
	label.text = String(entry["name"])
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(label)

	button.pressed.connect(_on_visitor.bind(entry))
	return button


# =============================================================
#  CLICKING
# =============================================================

func _on_building(entry: Dictionary) -> void:
	var name_text := String(entry["name"])

	if not bool(entry["unlocked"]):
		# Say WHY it is locked, in the designer's own words from the CSV.
		_detail.text = "%s is locked. %s" % [name_text,
			DialogueGrammar.describe(String(entry["requires"]))]
		return

	var description := String(entry["description"])
	_detail.text = description if description != "" else name_text
	_play_building_sounds(entry)

	var action := String(entry["action"])
	if action.strip_edges() == "":
		return
	_carry_out(Progression.run_actions(action, state))


## CLICKING A BUILDING (round AN): its own sound (Buildings.csv `Sound` - the
## Brewery bubbles, the Pub cheers), then its door opening (`Door Sound`),
## `base_door_sound_delay` seconds later. Both are Audio.csv rows.
func _play_building_sounds(entry: Dictionary) -> void:
	var tree := get_tree()
	AudioDirector.play_cue(tree, String(entry.get("sound", "")))
	var door := String(entry.get("door_sound", ""))
	if door.strip_edges() == "":
		return
	var gap := maxf(db.tune_float("base_door_sound_delay", 1.0), 0.0)
	if gap <= 0.0:
		AudioDirector.play_cue(tree, door)
		return
	# A scene-tree timer, so the door still sounds after the window has
	# opened over the base.
	tree.create_timer(gap).timeout.connect(func() -> void:
		AudioDirector.play_cue(tree, door))


## The words over a window. The building's own Name if we can find it, so
## the title says "TRAINING GROUND" rather than "TRAINING".
## THE GATE (round Y). True when the player may NOT go on yet - and in that
## case Team Build has been opened for them, on the tab they are missing,
## with the reason on the base's detail line. See src/core/team_build.gd.
## The tutorial walks its own path and is never turned away.
## Start a friendly of one MatchModes.csv mode - what the Match Maker's
## buttons (and, in the first match of a new game, the flag itself) do.
func _play_match(mode_id: String) -> void:
	# ROUND AN: choose first. The first match of a new game plays with a
	# squad of its own (MatchModes.csv `intro`), so it needs no team of
	# yours and Team Build must not turn you away from it.
	MatchMode.choose(get_tree(), mode_id)
	if MatchMode.squad_file(get_tree()) == "" and _turned_away():
		return
	state.save_to_disk()
	# THE TEAM SHELF, not the class picker. You pick a side you already
	# own; making a new one is a button on that screen.
	ScenePaths.go_to(get_tree(), ScenePaths.TEAM_SELECT)


func _turned_away() -> bool:
	if TutorialBase.active(get_tree()):
		return false
	var now := TeamBuild.status(state, CardDatabase.get_db())
	if bool(now["ok"]):
		return false
	_detail.text = String(now["why"])
	print("[team build] turned away: %s" % now["why"])
	state.save_to_disk()
	TeamBuildScreen.open_on = TeamBuild.tab_for(state, CardDatabase.get_db())
	var opened := BaseWindow.open(self, "Team Build", ScenePaths.TEAM_BUILD)
	if opened != null:
		opened.closed.connect(_rebuild)
	return true


func _window_title(screen_word: String) -> String:
	for entry in base.buildings_for(state):
		if String(entry["action"]).to_lower().ends_with(screen_word.to_lower()):
			return String(entry["name"])
	return screen_word


func _on_visitor(entry: Dictionary) -> void:
	# Their own grunt or hello (Visitors.csv `Sound`, round AN).
	AudioDirector.play_cue(get_tree(), String(entry.get("sound", "")))
	var scene := String(entry["story"]).strip_edges()
	if bool(entry["once"]):
		BaseDB.mark_talked(String(entry["id"]), state)

	if scene == "":
		_detail.text = "%s has nothing to say yet." % entry["name"]
		_rebuild()
		return

	state.save_to_disk()
	DialogueView.play(get_tree(), scene, ScenePaths.BASE)


## Show what is new, if anything is. Rebuilding afterwards means a building
## you just unlocked is drawn unlocked the moment you press Continue.
func _flash_new_unlocks() -> void:
	var panel := NewUnlocksPanel.show_over(self, state)
	if panel != null:
		panel.dismissed.connect(_rebuild)


func _advance_progression(trigger: String) -> void:
	if steps == null or state == null:
		return
	_carry_out(steps.fire(trigger, state))


## Do the things that needed the scene tree. Only one screen change can
## happen, so the first one wins and the rest is dropped.
func _carry_out(actions: Array[Dictionary]) -> void:
	for action in actions:
		var kind := String(action["kind"])
		var value := String(action["value"])
		match kind:
			"announce":
				_detail.text = value
			"story":
				state.save_to_disk()
				DialogueView.play(get_tree(), value, ScenePaths.BASE)
				return
			"goto":
				state.save_to_disk()
				ScenePaths.go_to(get_tree(), ScenePaths.for_name(value))
				return
			"match":
				# ROUND AN: `match:intro` starts that MatchModes.csv row. A
				# mode with a Squad needs no team of yours; any other mode
				# still has to get past Team Build.
				MatchMode.choose(get_tree(), value)
				if MatchMode.squad_file(get_tree()) == "" and _turned_away():
					return
				state.save_to_disk()
				# A squad match walks straight through Team Select, so the
				# screen goes black from this click, not from the next one.
				if MatchMode.squad_file(get_tree()) != "" and MatchLoader.enabled():
					MatchLoader.cover(get_tree())
				ScenePaths.go_to(get_tree(), ScenePaths.TEAM_SELECT)
				return
			"window":
				# ============ THE PUB WAITS FOR TEAM BUILD (round Y) ============
				if ScenePaths.for_name(value) == ScenePaths.PUB and _turned_away():
					return
				# ============ A WINDOW, NOT A SCENE CHANGE ============
				#
				# The base stays where it is and the screen opens on top of
				# it. `window:brewery` and `goto:brewery` name the same
				# screen through the same ScenePaths word — the only
				# difference is whether the base goes away.
				state.save_to_disk()
				var opened := BaseWindow.open(self, _window_title(value),
					ScenePaths.for_name(value))
				if opened != null:
					# REBUILD ON CLOSE. You may have unlocked something in
					# there, and a base that still shows the old doors is a
					# base you will click twice.
					opened.closed.connect(_rebuild)
				return

	state.save_to_disk()
	_rebuild()


# =============================================================
#  CHROME HELPERS
# =============================================================

## A quiet line showing what you have earned. Handy while writing content:
## if an unlock is not appearing, this says whether the game thinks you have it.
## A PROBLEM IN A SPREADSHEET STILL HAS TO BE SAID, just not across the
## bottom of the screen. It goes to the Output panel, where every other
## loader's complaints already go — and ONCE, when the base opens, rather
## than on every rebuild.
func _report_problems() -> void:
	if base == null or base.problems.is_empty():
		return
	for problem in base.problems:
		print("[base] %s" % problem)


## A plain labelled button. The exits across the top use
## MenuSupport.icon_button() instead; this is kept for anything you add here
## that wants words and no picture.
## THIS SCREEN'S BUTTONS ARE THE SHARED ONES NOW.
##
## It used to build a plain Button here, which is why Back looked different
## depending on which screen you were standing on. It hands the job to
## MenuSupport.icon_button() instead, so every call site in this file gets
## the standard icon-and-label face without one of them being edited.
func _make_button(label: String, box: Vector2) -> Button:
	return MenuSupport.icon_button("◇", label, box)


func _find_texture(file_name: String, dirs: Array[String]) -> Texture2D:
	var clean := file_name.strip_edges()
	if clean == "":
		return null
	for folder in dirs:
		for candidate in [folder + clean, folder + clean + ".png"]:
			if ResourceLoader.exists(candidate):
				var res := load(candidate)
				if res is Texture2D:
					return res as Texture2D
	return null
