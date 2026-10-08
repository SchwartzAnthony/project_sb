class_name TeamSheet
extends CanvasLayer

# =============================================================
#  BEFORE A MATCH — the team sheet, then the START button
#
#  A match used to begin the instant the screen changed, with no moment to
#  see who you were playing. This is that moment, and it is two of them:
#
#  ============ ONE: THE TEAM SHEET ============
#
#  A full screen with both sides on it. Your crest, your name and your three
#  Star Players on the left; theirs on the right; a big VS between them; and
#  a bar filling along the bottom.
#
#  THE BAR IS HONEST WHEN IT CAN BE. `load_step()` is called as each real
#  piece of work finishes, and the bar shows that. When there is nothing slow
#  left to do it fills smoothly over `team_sheet_seconds` instead — because a
#  loading bar that jumps to full in one frame is worse than no bar at all,
#  and this beat is doing a job whether or not the computer needs it.
#
#  ============ TWO: THE KICK-OFF GATE ============
#
#  The sheet fades, the pitch is there with both sides in position, and the
#  two crests stay at the top with a START button between them. Nothing
#  happens until it is pressed.
#
#  That is the whole reason this exists: you should get to look at the two
#  teams standing on the grass and start the match yourself.
#
#  ============ TUNING ============
#
#      team_sheet              false skips all of this. A match then opens
#                              straight into the 3 - 2 - 1 as before
#      team_sheet_seconds      how long the sheet is held
#      team_sheet_stars        how many Stars are shown a side. 3
#      kickoff_needs_button    false starts the countdown by itself once the
#                              sheet is done, with no START to press
# =============================================================

## START was pressed — or, with `kickoff_needs_button` off, the gate opened by
## itself. The match begins its countdown here and not before.
signal kick_off_wanted

var db: CardDatabase

## Chalk on the beer menu, and the board itself when there is no picture.
const CHALK := Color(0.95, 0.95, 0.90)
const CHALK_BOARD := Color(0.16, 0.27, 0.21)

var _bar: ColorRect
var _bar_room: Control
var _sheet: Control
var _gate: Control
var _start_button: Button
## The START button on the SHEET, for when the sheet waits rather than lifting.
var _sheet_start: Button
var _waiting: Label
var _progress := 0.0
var _steps_done := 0
var _steps_total := 1
var _opened := false


static func make(database: CardDatabase) -> TeamSheet:
	var made := TeamSheet.new()
	made.name = "TeamSheet"
	made.db = database
	return made


func _ready() -> void:
	# ABOVE THE PITCH AND ABOVE THE HUD, below the pause menu.
	layer = 55


# =============================================================
#  SHOWING IT
# =============================================================

## Fill it in and put it up.
##
##   mine / theirs  {"name", "crest", "stars"} — stars is an Array[PlayerData]
func show_for(mine: Dictionary, theirs: Dictionary) -> void:
	_build(mine, theirs)
	_sheet.modulate = Color(1, 1, 1, 0)
	var fade := create_tween()
	fade.tween_property(_sheet, "modulate", Color(1, 1, 1, 1), 0.25)


## Say how many real pieces of work there are, so the bar can follow them.
## Called before any of them start. 0 means "nothing slow to do" and the bar
## simply fills over the held time.
func expect_steps(how_many: int) -> void:
	_steps_total = maxi(1, how_many)
	_steps_done = 0


## One of those pieces of work is finished.
func load_step() -> void:
	_steps_done += 1


func _process(delta: float) -> void:
	if _bar == null or not is_instance_valid(_bar) or _opened:
		return
	var held := maxf(0.6, db.tune_float("team_sheet_seconds", 2.6) if db != null else 2.6)
	# The bar moves at whichever is FURTHER ALONG: the real work, or the
	# clock. So it never stalls on a fast machine and never lies on a slow one.
	var by_clock := _progress + delta / held
	var by_work := float(_steps_done) / float(_steps_total)
	# NO BAR (round AN): the loading screen before the match already did the
	# waiting, so a sheet that waits for START shows it at once.
	if not _shows_bar() and _sheet_waits():
		by_work = 1.0
	_progress = clampf(maxf(by_clock, by_work), 0.0, 1.0)
	_paint_bar()
	if _progress >= 1.0:
		_open_the_gate()


## ============ THE SHEET WAITS FOR YOU ============
##
## `team_sheet_hold` keeps the sheet up until START is pressed, rather than
## lifting it on a timer. With it on, the bar fills, the words change to say
## the button is live, and the sheet stays where it is — which is what you
## want when there are six Star Players with abilities to read on it.
func _sheet_waits() -> bool:
	return db != null and db.tune_bool("team_sheet_hold", true) \
		and db.tune_bool("kickoff_needs_button", true)


## `team_sheet_bar` in Tuning.csv. Off since round AN: the ball rolling into
## the goal on the loading screen is the loading bar now, and two in a row
## was one too many (Anthony).
func _shows_bar() -> bool:
	return db != null and db.tune_bool("team_sheet_bar", false)


func _paint_bar() -> void:
	if _bar_room == null:
		return
	_bar.size = Vector2(_bar_room.size.x * _progress, _bar_room.size.y)


# =============================================================
#  THE GATE
# =============================================================

func _open_the_gate() -> void:
	if _opened:
		return
	_opened = true
	set_process(false)

	# THE SHEET MAY STAY UP. With team_sheet_hold on, the START button is put
	# on the sheet itself and the pitch is not shown until it is pressed —
	# because the sheet is where the six Stars and their abilities are, and
	# taking it away after two seconds is taking the reading away.
	if _sheet_waits():
		_waiting.text = "Read them. Press START when you are ready."
		_waiting.add_theme_color_override("font_color", MenuSupport.COLOUR_ACCENT)
		_sheet_start.visible = true
		_sheet_start.modulate = Color(1, 1, 1, 0)
		var arrive_here := create_tween()
		arrive_here.tween_property(_sheet_start, "modulate", Color(1, 1, 1, 1), 0.3)
		return

	# The sheet gets out of the way so the pitch can be seen. The crests stay.
	var fade := create_tween()
	fade.tween_property(_sheet, "modulate", Color(1, 1, 1, 0), 0.35)
	await fade.finished
	if not is_instance_valid(self):
		return
	_sheet.visible = false
	_gate.visible = true

	if db != null and not db.tune_bool("kickoff_needs_button", true):
		# No button: a short beat to see the two sides, then away.
		await get_tree().create_timer(0.6).timeout
		_go()
		return

	_start_button.modulate = Color(1, 1, 1, 0)
	var arrive := create_tween()
	arrive.tween_property(_start_button, "modulate", Color(1, 1, 1, 1), 0.3)


func _go() -> void:
	for button in [_start_button, _sheet_start]:
		if button != null and is_instance_valid(button):
			button.disabled = true
	# When the sheet held the START button, it has to get out of the way now.
	if _sheet != null and is_instance_valid(_sheet) and _sheet.visible:
		var lift := create_tween()
		lift.tween_property(_sheet, "modulate", Color(1, 1, 1, 0), 0.3)
	kick_off_wanted.emit()
	var fade := create_tween()
	fade.tween_property(_gate, "modulate", Color(1, 1, 1, 0), 0.3)
	await fade.finished
	queue_free()


func _unhandled_key_input(event: InputEvent) -> void:
	# Enter or space starts it too. A button you can only reach with a mouse
	# is a button somebody on a controller cannot press.
	if not _opened:
		return
	var showing := (_gate != null and _gate.visible) \
		or (_sheet_start != null and is_instance_valid(_sheet_start) and _sheet_start.visible)
	if not showing:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		get_viewport().set_input_as_handled()
		_go()


# =============================================================
#  BUILDING IT
# =============================================================

func _build(mine: Dictionary, theirs: Dictionary) -> void:
	var stars := 3
	if db != null:
		stars = maxi(1, db.tune_int("team_sheet_stars", 3))

	# ---- the full-screen sheet ----
	_sheet = Control.new()
	_sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_sheet)

	var back := ColorRect.new()
	# OPAQUE. It is a loading screen; the score and the clock showing faintly
	# through it read as a bug rather than as atmosphere.
	back.color = Color(0.05, 0.06, 0.08, 1.0)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sheet.add_child(back)

	# THE BEER TENT behind the two menus (round AN). vs_background in
	# Tuning.csv; vs_background_dim darkens it so the menus stand out.
	var tent := _picture("vs_background", "res://assets/team/vs/vs_tent.png")
	if tent != null:
		var hall := TextureRect.new()
		hall.texture = tent
		hall.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hall.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		hall.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		hall.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		hall.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var dim := clampf(_tune_f("vs_background_dim", 0.55), 0.0, 1.0)
		hall.modulate = Color(1.0 - dim, 1.0 - dim, 1.0 - dim, 1.0)
		_sheet.add_child(hall)

	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 12)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	_sheet.add_child(column)

	var kind := MenuSupport.heading(_match_words(), 30, MenuSupport.COLOUR_ACCENT)
	kind.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kind.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	_outline(kind, 8)
	column.add_child(kind)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	column.add_child(row)

	row.add_child(_menu_board(mine, stars, false))
	row.add_child(_versus())
	row.add_child(_menu_board(theirs, stars, true))

	# ---- the loading bar ----
	var bar_line := CenterContainer.new()
	bar_line.visible = _shows_bar()
	column.add_child(bar_line)

	# ============ A PLAIN CONTROL, NOT A CONTAINER ============
	#
	# The fill is positioned by hand every frame, and a container lays its
	# children out again every time it is told to — so a PanelContainer here
	# quietly undid the width on the very next layout pass and the bar crawled
	# along at whatever the container felt like. A Control does not lay
	# anything out, which is exactly what is wanted.
	_bar_room = Control.new()
	_bar_room.custom_minimum_size = Vector2(620, 16)
	_bar_room.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_line.add_child(_bar_room)

	var trough := ColorRect.new()
	trough.color = Color(0.10, 0.11, 0.14, 1.0)
	trough.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	trough.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_room.add_child(trough)

	_bar = ColorRect.new()
	_bar.color = MenuSupport.COLOUR_ACCENT
	_bar.position = Vector2.ZERO
	_bar.size = Vector2(0, 16)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_room.add_child(_bar)

	_waiting = Label.new()
	_waiting.text = "Walking out…"
	_waiting.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_waiting.add_theme_font_size_override("font_size", 16)
	_waiting.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	_waiting.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	_outline(_waiting, 6)
	column.add_child(_waiting)

	# The START button that lives ON the sheet, for when the sheet waits.
	_sheet_start = MenuSupport.icon_button("play|▶", "START", Vector2(260, 60))
	_sheet_start.tooltip_text = "Kick off. Enter or space does the same."
	_sheet_start.add_theme_font_size_override("font_size", 20)
	_sheet_start.pressed.connect(_go)
	_sheet_start.visible = false
	var start_here := CenterContainer.new()
	start_here.add_child(_sheet_start)
	column.add_child(start_here)

	# ---- the gate: crests at the top, START between them ----
	_gate = Control.new()
	_gate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_gate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gate.visible = false
	add_child(_gate)

	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_top = 74.0
	top.offset_bottom = 210.0
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_theme_constant_override("separation", 46)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gate.add_child(top)

	top.add_child(_crest_and_name(mine, 96))

	_start_button = MenuSupport.icon_button("play|▶", "START", Vector2(230, 64))
	_start_button.tooltip_text = "Kick off. Enter or space does the same."
	_start_button.add_theme_font_size_override("font_size", 20)
	_start_button.pressed.connect(_go)
	var holder := CenterContainer.new()
	holder.custom_minimum_size = Vector2(240, 0)
	holder.add_child(_start_button)
	top.add_child(holder)

	top.add_child(_crest_and_name(theirs, 96))


# =============================================================
#  THE BEER MENUS  (round AN)
#
#  Anthony: "the VS loading screen should have each team be in a beer menu,
#  and the star player sprites that are correct are here too."
#
#  Each side is a chalkboard Bierkarte. At the top the crest and the team
#  name, then the Stars like the beers on a menu: the figure the Star plays
#  as on the pitch (standing in idle), the name, the tier and power where a
#  price would be, and what they do in two tagged lines.
#
#  Tuning.csv
#      vs_menu_board       the board picture (res:// path)
#      vs_board_width      how wide a board may be, share of the screen
#      vs_board_height     how tall a board is, as a share of the screen
#      vs_board_patch      the wooden frame round the chalk, in the
#                          picture's pixels: left top right bottom
#      vs_versus           the picture between the two boards
#      vs_background       the beer tent behind it all
#      vs_background_dim   0 = the tent at full colour, 1 = black
#      vs_star_size        how tall a Star's figure is, in screen pixels
# =============================================================

func _menu_board(team: Dictionary, stars: int, theirs: bool) -> Control:
	var screen := get_viewport().get_visible_rect().size if get_viewport() != null \
		else Vector2(1920, 1080)
	var art := _picture("vs_menu_board", "res://assets/team/vs/vs_menu_board.png")
	var patch := _patch()
	var wide := screen.x * clampf(_tune_f("vs_board_width", 0.44), 0.1, 0.5)
	var tall := screen.y * clampf(_tune_f("vs_board_height", 0.62), 0.2, 1.0)

	# A Panel with no box of its own: the match puts a dark plate behind every
	# word (TextBackdrop), and words written in chalk on a board need none.
	var board := Panel.new()
	board.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# ============ THE BOARD GROWS DOWNWARD, IT NEVER SMEARS ============
	#
	# The picture is blown up by a WHOLE number (hard pixels), as wide as it
	# fits in vs_board_width. The frame top (crest, bunting) and bottom stay
	# as drawn; the rows of chalk and side posts in between repeat to make the
	# board as tall as vs_board_height asks, so there is room for the Stars'
	# abilities however long they are.
	var zoom := 1
	if art != null:
		zoom = maxi(1, int(floor(wide / float(art.get_width()))))
		var big := art.get_image()
		big.resize(art.get_width() * zoom, art.get_height() * zoom, Image.INTERPOLATE_NEAREST)
		var picture := NinePatchRect.new()
		picture.texture = ImageTexture.create_from_image(big)
		picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		picture.patch_margin_left = patch[0] * zoom
		picture.patch_margin_top = patch[1] * zoom
		picture.patch_margin_right = patch[2] * zoom
		picture.patch_margin_bottom = patch[3] * zoom
		picture.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_TILE_FIT
		picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		board.add_child(picture)
		wide = float(art.get_width() * zoom)
		tall = maxf(tall, float((patch[1] + patch[3]) * zoom) + 120.0)
	else:
		var plain := Panel.new()
		plain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		plain.add_theme_stylebox_override("panel", MenuSupport.panel_style(
			CHALK_BOARD, MenuSupport.COLOUR_ACCENT))
		board.add_child(plain)
	board.custom_minimum_size = Vector2(wide, tall)

	# The chalk: the part of the picture that is the green board. The Stars
	# stand side by side on it, like three beers on the menu.
	var pad := 6.0
	var chalk := HBoxContainer.new()
	chalk.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	chalk.offset_left = patch[0] * zoom + pad
	chalk.offset_top = patch[1] * zoom + pad
	chalk.offset_right = -(patch[2] * zoom + pad)
	chalk.offset_bottom = -(patch[3] * zoom + pad)
	chalk.add_theme_constant_override("separation", 6)
	chalk.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.add_child(chalk)

	var shown := 0
	for entry in (team.get("stars", []) as Array):
		if shown >= stars:
			break
		var card := entry as PlayerData
		if card == null:
			continue
		if shown > 0:
			chalk.add_child(_chalk_rule())
		chalk.add_child(_menu_line(card, theirs))
		shown += 1
	if shown == 0:
		chalk.add_child(_quiet("No Star Players named for this side."))
	# LONG ABILITIES MAKE THE BOARD TALLER rather than spill off the chalk.
	# Measured once the words are laid out; the extra rows repeat like the rest.
	var frame_rows := float(patch[1] + patch[3]) * zoom + pad * 2.0
	_grow_to_fit.call_deferred(board, chalk, frame_rows, screen.y)

	# ---- crest and name over the board, like the name of the house ----
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 4)
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override("separation", 10)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side.add_child(head)
	var crest := MenuSupport.icon_texture(String(team.get("crest", "")))
	if crest != null:
		var badge := TextureRect.new()
		badge.texture = crest
		badge.custom_minimum_size = Vector2(64, 64)
		badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(badge)
	var title := MenuSupport.heading(String(team.get("name", "?")), 38,
		Color(0.92, 0.55, 0.45) if theirs else MenuSupport.COLOUR_ACCENT)
	title.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_outline(title, 10)
	head.add_child(title)
	side.add_child(board)
	return side


## One Star, written up like a beer on the menu: the figure, the name, the
## tier and power where the price would be, and what they do.
func _menu_line(card: PlayerData, theirs: bool) -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 1)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_stretch_ratio = 1.0
	column.custom_minimum_size = Vector2(60, 0)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# THE FIGURE FROM THE PITCH, standing in idle facing us: the same look
	# the Star wears in the match (PitchSprite.window_sheet). A card with no
	# pitch sheet yet falls back to its portrait.
	var tall := maxf(40.0, _tune_f("vs_star_size", 120.0))
	var figure_box := CenterContainer.new()
	figure_box.custom_minimum_size = Vector2(0, tall)
	figure_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(figure_box)
	var pitch := PitchSprite.window_sheet(card)
	var spec := PitchSprite.window_spec(pitch, "idle", 2) if pitch != null else null
	if spec != null:
		var figure := SpriteAnimator.new()
		figure_box.add_child(figure)
		figure.play(pitch, spec)
		figure.fit_into(Vector2(tall, tall))
		if theirs:
			figure.flip_h = true
	else:
		figure_box.add_child(MenuSupport.portrait_rect(card, db, Vector2(tall * 0.8, tall)))

	var named := MenuSupport.heading(NamePlate.short_name(card), 20, CHALK)
	named.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	named.clip_text = true
	column.add_child(named)

	# Where a beer has its price, a Star has its tier and power.
	var price := Label.new()
	price.text = "Tier %s  ·  P %d  ·  D %d" % [card.get_tier_clean(),
		card.get_attack_power(), card.get_defense_power()]
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price.add_theme_font_size_override("font_size", 13)
	price.add_theme_color_override("font_color",
		MenuSupport.colour_for_tier(card.get_tier_clean()).lightened(0.45))
	price.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(price)

	for pair in [[true, card.active_attack_ability()],
			[false, card.active_defend_ability()]]:
		var line := _ability_line(bool(pair[0]), String(pair[1]))
		if line != null:
			column.add_child(line)
	return column


## Make `board` tall enough for everything written on `chalk`, but never
## taller than vs_board_max of the screen. If it still does not fit there,
## the ability sentences get smaller, a size at a time, down to
## vs_ability_size_min.
func _grow_to_fit(board: Control, chalk: Control, frame_rows: float, screen_tall: float) -> void:
	if not is_instance_valid(board) or not is_instance_valid(chalk):
		return
	var cap := screen_tall * clampf(_tune_f("vs_board_max", 0.74), 0.2, 1.0)
	var smallest := int(_tune_f("vs_ability_size_min", 9.0))
	for attempt in 8:
		var needed := chalk.get_combined_minimum_size().y + frame_rows
		if needed > board.custom_minimum_size.y:
			board.custom_minimum_size.y = minf(needed, cap)
		if needed <= cap:
			return
		var shrank := false
		for said in chalk.find_children("*", "Label", true, false):
			var words := said as Label
			if words == null or words.autowrap_mode == TextServer.AUTOWRAP_OFF:
				continue
			var now := words.get_theme_font_size("font_size")
			if now > smallest:
				words.add_theme_font_size_override("font_size", now - 1)
				shrank = true
		if not shrank:
			return
		# Let the words wrap again at the new size before measuring.
		await get_tree().process_frame
		if not is_instance_valid(board) or not is_instance_valid(chalk):
			return


## A thin chalk line between the menu's entries.
func _chalk_rule() -> Control:
	var rule := ColorRect.new()
	rule.color = Color(CHALK.r, CHALK.g, CHALK.b, 0.35)
	rule.custom_minimum_size = Vector2(2, 0)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rule


## The two steins clinking between the boards, with VS over them.
func _versus() -> Control:
	var holder := PanelContainer.new()
	holder.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var middle := VBoxContainer.new()
	middle.alignment = BoxContainer.ALIGNMENT_CENTER
	middle.custom_minimum_size = Vector2(160, 0)
	middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(middle)
	var art := _picture("vs_versus", "res://assets/team/vs/vs_steins.png")
	if art != null:
		var steins := TextureRect.new()
		steins.texture = art
		steins.custom_minimum_size = Vector2(160, 160)
		steins.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		steins.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		steins.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		steins.mouse_filter = Control.MOUSE_FILTER_IGNORE
		middle.add_child(steins)
	var versus := MenuSupport.heading("VS", 64, MenuSupport.COLOUR_ACCENT)
	versus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_outline(versus, 10)
	middle.add_child(versus)
	return holder


## A black comic outline round big words over the tent.
func _outline(label: Label, size: int) -> void:
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", size)


## vs_board_patch: the frame round the chalk on the board picture, in the
## picture's own pixels: left top right bottom. Everything inside is chalk.
func _patch() -> Array[int]:
	var said := db.tune_text("vs_board_patch", "16 46 17 16") if db != null else "16 46 17 16"
	var parts := said.replace(",", " ").split(" ", false)
	var out: Array[int] = [16, 46, 17, 16]
	for i in mini(4, parts.size()):
		out[i] = maxi(0, int(parts[i]))
	return out


## A picture named in Tuning.csv, or the fallback, or null.
func _picture(key: String, fallback: String) -> Texture2D:
	var path := db.tune_text(key, fallback).strip_edges() if db != null else fallback
	for each in [path, fallback]:
		if each != "" and ResourceLoader.exists(each):
			return load(each) as Texture2D
	return null


func _tune_f(key: String, otherwise: float) -> float:
	return db.tune_float(key, otherwise) if db != null else otherwise


func _crest_and_name(team: Dictionary, crest_size: float) -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var art := MenuSupport.icon_texture(String(team.get("crest", "")))
	if art != null:
		var picture := TextureRect.new()
		picture.texture = art
		picture.custom_minimum_size = Vector2(crest_size, crest_size)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(picture)
	else:
		# NO CREST YET IS NOT AN ERROR. A lettered disc holds the place until
		# the art arrives, the same way a missing icon draws as a pip.
		var pip := Label.new()
		pip.text = String(team.get("name", "?")).substr(0, 1).to_upper()
		pip.custom_minimum_size = Vector2(crest_size, crest_size)
		pip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		pip.add_theme_font_size_override("font_size", int(crest_size * 0.5))
		pip.add_theme_color_override("font_color", MenuSupport.COLOUR_ACCENT)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(pip)

	var title := Label.new()
	title.text = String(team.get("name", "?"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(title)
	return column


# =============================================================
#  ONE ABILITY, AND WHICH HALF OF THE GAME IT BELONGS TO
#
#  ============ WHAT WAS WRONG ============
#
#  "Make the attack and defender abilities more distinctive, right now they
#   look the same."
#
#  They were two grey sentences in the same font, one above the other, and
#  nothing on screen said which was which. You had to know that the first one
#  is always the attack — which is exactly the kind of knowing that a player
#  has to be taught and then has to remember.
#
#  ============ WHAT IT DOES NOW ============
#
#  A TAG, in one of the two colours the game has already taught you:
#
#      ATK  Open Hand — see one of their cards before you pick
#      DEF  Stone Wall — the first shot at you is stopped
#
#  ATK is the warm colour and DEF is the cool one, and they are THE SAME TWO
#  COLOURS as the ATTACKING / DEFENDING strip above the row of cards. They
#  live in the palette (MenuSupport.COLOUR_ATTACK / COLOUR_DEFEND) rather
#  than in either file, so the two can never drift apart and the Colour tab
#  moves both at once.
#
#  That is the whole trick: the strip in the draft teaches the colours, the
#  team sheet uses them, and after one match you can read a Star's sheet
#  without reading the words.
# =============================================================

## One ability, tagged. Null only when the sheet has been told not to print
## abilities at all — a card with no ability still gets a line saying so.
func _ability_line(attacking: bool, ability_id: String) -> Control:
	if db == null:
		return null
	# team_sheet_abilities = false prints the Stars and nothing under them, for
	# a shorter sheet or for a stream where the opposition stays a surprise.
	if not db.tune_bool("team_sheet_abilities", true):
		return null

	var tint := MenuSupport.COLOUR_ATTACK if attacking else MenuSupport.COLOUR_DEFEND

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	row.custom_minimum_size = Vector2(60, 0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# THE TAG IS A FIXED WIDTH so that the sentences beside it all start on
	# the same line down the column, which is what makes six of them scan as
	# a list instead of as six separate scraps.
	var tag := Label.new()
	tag.text = Loc.text("atk_tag", "ATK") if attacking else Loc.text("def_tag", "DEF")
	tag.custom_minimum_size = Vector2(30, 0)
	tag.add_theme_font_size_override("font_size", 12)
	tag.add_theme_color_override("font_color", tint)
	tag.add_theme_stylebox_override("normal", MenuSupport.panel_style(
		Color(tint.r, tint.g, tint.b, 0.16), tint))
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# TOP, not centre. A long ability wraps to three lines and a tag floating
	# beside the middle one looks like it belongs to that line rather than to
	# the paragraph. At the top it reads as the label it is.
	tag.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(tag)

	var said := Label.new()
	said.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	said.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	said.add_theme_font_size_override("font_size", 12)

	var clean := ability_id.strip_edges()
	var ability: AbilityData = db.abilities.get(clean.to_lower()) if clean != "" else null
	if ability == null:
		said.text = Loc.text("ability_none", "None")
		said.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM.darkened(0.2))
	else:
		said.text = "%s — %s" % [ability.display_name, ability.plain()]
		said.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	row.add_child(said)
	return row


func _quiet(text: String) -> Label:
	var made := Label.new()
	made.text = text
	made.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	made.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	made.add_theme_font_size_override("font_size", 13)
	made.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	return made


## "LEAGUE MATCH", "FRIENDLY" — whatever MatchModes.csv calls today's game.
func _match_words() -> String:
	var mode := MatchMode.current(get_tree())
	var said := String(mode.get("name", "")).strip_edges()
	return said.to_upper() if said != "" else "KICK-OFF"
