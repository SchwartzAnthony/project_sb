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

	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 24)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	_sheet.add_child(column)

	var kind := MenuSupport.heading(_match_words(), 18, MenuSupport.COLOUR_TEXT_DIM)
	kind.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(kind)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 40)
	column.add_child(row)

	row.add_child(_side(mine, stars, false))

	var versus := MenuSupport.heading("VS", 54, MenuSupport.COLOUR_ACCENT)
	versus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	versus.custom_minimum_size = Vector2(140, 0)
	versus.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(versus)

	row.add_child(_side(theirs, stars, true))

	# ---- the loading bar ----
	var bar_line := CenterContainer.new()
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
	_waiting.add_theme_font_size_override("font_size", 14)
	_waiting.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
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


## One side of the sheet: crest, name, and the Stars who are playing.
func _side(team: Dictionary, stars: int, theirs: bool) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	panel.add_theme_stylebox_override("panel", MenuSupport.panel_style(
		MenuSupport.COLOUR_PANEL,
		MenuSupport.COLOUR_TEXT_DIM if theirs else MenuSupport.COLOUR_ACCENT))

	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 18)
	panel.add_child(pad)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	pad.add_child(column)

	column.add_child(_crest_and_name(team, 120))

	var line := HBoxContainer.new()
	line.alignment = BoxContainer.ALIGNMENT_CENTER
	line.add_theme_constant_override("separation", 10)
	column.add_child(line)

	var shown := 0
	for entry in (team.get("stars", []) as Array):
		if shown >= stars:
			break
		var card := entry as PlayerData
		if card == null:
			continue
		line.add_child(_star_face(card))
		shown += 1
	if shown == 0:
		column.add_child(_quiet("No Star Players named for this side."))

	return panel


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


## A Star's face, drawn with the same helper every other screen uses so the
## player you see here is the player you see on the pitch.
func _star_face(card: PlayerData) -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	column.custom_minimum_size = Vector2(150, 0)

	# ============ NO HOVER. IT IS PRINTED ============
	#
	# There used to be a hover panel over this portrait that opened with both
	# abilities in full — and underneath it, the same two abilities printed on
	# the sheet. Two copies of the same sentence, one of which you had to go
	# looking for with a mouse.
	#
	# "The star players abilities are listed twice, remove the hovering over
	#  the star player."
	#
	# So the hover is gone and the printed lines are the only copy. They are
	# what needed the work anyway — see _ability_line().
	var portrait := MenuSupport.portrait_rect(card, db, Vector2(150, 150))
	column.add_child(portrait)

	var title := Label.new()
	title.text = NamePlate.short_name(card)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 13)
	title.clip_text = true
	column.add_child(title)

	var under := Label.new()
	under.text = "Tier %s  ·  P: %d" % [card.get_tier_clean(), card.get_attack_power()]
	under.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	under.add_theme_font_size_override("font_size", 11)
	under.add_theme_color_override("font_color",
		MenuSupport.colour_for_tier(card.get_tier_clean()).lightened(0.35))
	column.add_child(under)

	# ============ WHAT THEY DO, ON THE TEAM SHEET ============
	#
	# Three Stars a side with nothing written under them is three pictures.
	# The whole reason you are being shown the opposition before kick-off is
	# so that you know what is coming, and that is the abilities.
	# BOTH SIDES, ALWAYS, IN THEIR OWN COLOURS — and the word None where there
	# is nothing, because a blank where an ability should be reads as a bug
	# while "None" reads as information you can plan around.
	for pair in [[true, card.active_attack_ability()],
			[false, card.active_defend_ability()]]:
		var line := _ability_line(bool(pair[0]), String(pair[1]))
		if line != null:
			column.add_child(line)
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
	row.custom_minimum_size = Vector2(150, 0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# THE TAG IS A FIXED WIDTH so that the sentences beside it all start on
	# the same line down the column, which is what makes six of them scan as
	# a list instead of as six separate scraps.
	var tag := Label.new()
	tag.text = Loc.text("atk_tag", "ATK") if attacking else Loc.text("def_tag", "DEF")
	tag.custom_minimum_size = Vector2(30, 0)
	tag.add_theme_font_size_override("font_size", 10)
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
	said.add_theme_font_size_override("font_size", 10)

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
