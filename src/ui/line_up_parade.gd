class_name LineUpParade
extends CanvasLayer

# =============================================================
#  THE TEAMS WALK OUT — one player at a time, yours and then theirs
#
#  ============ WHY IT EXISTS ============
#
#  "Missing when the match starts. After the loading screen, when a player
#  hits continue, the game then shows the line up of all the player units the
#  player is playing, and then it goes through the line up of the enemy."
#
#  The team sheet tells you the two crests and the six Stars. It does not
#  introduce the twenty other people about to play, and those twenty are the
#  cards you will be choosing between for the next ninety minutes. A player
#  you have been shown once is a player you recognise in the draft.
#
#  ============ WHERE IT SITS ============
#
#      the team sheet      both crests, both sets of Stars, a bar, START
#      THE LINE-UPS        <- here
#      the countdown       3 - 2 - 1 - START
#      the match
#
#  ============ IT CAN ALWAYS BE SKIPPED ============
#
#  A click, space, enter or escape ends it immediately — the whole thing, not
#  one player. It is a flourish, and a flourish you cannot get out of is an
#  obstacle. `line_up_parade` in Tuning.csv turns it off for good.
#
#  ============ HOW IT IS BUILT ============
#
#  Every card gets a row on a list that fills downward, so by the end you are
#  looking at the whole side rather than at the last player of it. The rows
#  arrive one at a time and each one slides in, which is the only animation
#  in here — twenty separate cut-aways would take a minute and a half.
# =============================================================

## How wide the list is. A team sheet is a narrow thing — you read DOWN it.
const LIST_WIDTH := 900.0
## How big a face is on a row.
const FACE := Vector2(72, 72)

signal finished

var db: CardDatabase
var mine: Array[PlayerData] = []
var theirs: Array[PlayerData] = []
var my_name := "YOUR SIDE"
var their_name := "THEM"

var _done := false
var _column: VBoxContainer
var _title: Label
var _hint: Label


## Put it up over `on` and return it. Await its `finished` signal.
static func open(on: Node, database: CardDatabase, your_side: Array,
		other_side: Array, your_title: String, other_title: String) -> LineUpParade:
	var made := LineUpParade.new()
	made.name = "LineUpParade"
	made.db = database
	for card in your_side:
		if card is PlayerData:
			made.mine.append(card)
	for card in other_side:
		if card is PlayerData:
			made.theirs.append(card)
	if your_title != "":
		made.my_name = your_title
	if other_title != "":
		made.their_name = other_title
	on.add_child(made)
	return made


func _ready() -> void:
	# Above the pitch and above the team sheet's gate, below a dialog.
	layer = 160
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_run()


# =============================================================
#  THE SCREEN
# =============================================================

func _build() -> void:
	var back := ColorRect.new()
	back.color = Color(0.04, 0.05, 0.07, 0.96)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_STOP
	back.gui_input.connect(func(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click != null and click.pressed:
			skip())
	add_child(back)

	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# ============ A COLUMN, NOT THE WHOLE SCREEN ============
	#
	# The rows used to stretch the full width of the window, which at 1920 put
	# a player's name and his two numbers about fourteen hundred pixels apart
	# with nothing in between. A team sheet is a narrow thing — you read DOWN
	# it — so the side margin is whatever it takes to leave a column of
	# LIST_WIDTH in the middle, and a wider window gives it more margin rather
	# than longer rows.
	#
	# Done with the margin rather than by wrapping it in a CenterContainer,
	# which was the first attempt and collapsed the list to nothing: a
	# CenterContainer sizes its child to the child's MINIMUM, and a scrolling
	# list's minimum height is zero.
	var screen: Vector2 = get_viewport().get_visible_rect().size
	var side_gap := maxf(40.0, (screen.x - LIST_WIDTH) * 0.5)
	for side in ["margin_left", "margin_right"]:
		pad.add_theme_constant_override(side, int(side_gap))
	for side in ["margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 60)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(pad)

	var frame := VBoxContainer.new()
	frame.add_theme_constant_override("separation", 14)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(frame)

	_title = MenuSupport.heading(my_name, 40, MenuSupport.COLOUR_ACCENT)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	frame.add_child(_title)

	# THE LIST FILLS DOWNWARD and the whole side stays on screen, so the last
	# thing you see is the team rather than the last player in it.
	var scroller := ScrollContainer.new()
	scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroller.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(scroller)

	_column = VBoxContainer.new()
	_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_column.add_theme_constant_override("separation", 6)
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroller.add_child(_column)

	_hint = Label.new()
	_hint.text = "Click, space or escape to skip"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 14)
	_hint.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	frame.add_child(_hint)


# =============================================================
#  THE WALK-OUT
# =============================================================

func _run() -> void:
	var gap := 0.18
	var between := 0.9
	if db != null:
		gap = maxf(0.0, db.tune_float("line_up_gap", 0.18))
		between = maxf(0.0, db.tune_float("line_up_between_sides", 0.9))

	await _parade(mine, my_name, false, gap)
	if _done:
		return
	await _wait(between)
	if _done:
		return
	await _parade(theirs, their_name, true, gap)
	if _done:
		return
	await _wait(between)
	_end()


func _parade(cards: Array[PlayerData], title: String, is_enemy: bool,
		gap: float) -> void:
	if _done:
		return
	_title.text = title
	_title.add_theme_color_override("font_color",
		Color(0.92, 0.55, 0.45) if is_enemy else MenuSupport.COLOUR_ACCENT)
	for child in _column.get_children():
		child.queue_free()

	# BY TIER, in ladder order, because that is the order they are drafted in
	# and therefore the order you will meet them.
	var sorted := cards.duplicate()
	sorted.sort_custom(func(a: PlayerData, b: PlayerData) -> bool:
		var ai := PlayerData.TIER_ORDER.find(a.get_tier_clean())
		var bi := PlayerData.TIER_ORDER.find(b.get_tier_clean())
		if ai != bi:
			return ai < bi
		return a.get_attack_power() < b.get_attack_power())

	for card in sorted:
		if _done:
			return
		_column.add_child(_row_for(card, is_enemy))
		await _wait(gap)


func _row_for(card: PlayerData, is_enemy: bool) -> Control:
	var frame := PanelContainer.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", MenuSupport.panel_style(
		MenuSupport.COLOUR_PANEL,
		MenuSupport.COLOUR_ACCENT if card.is_star() else MenuSupport.COLOUR_TEXT_DIM))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(row)

	var face := MenuSupport.portrait_rect(card, db, FACE)
	row.add_child(face)

	var tier := Label.new()
	tier.text = "TIER %s" % card.get_tier_clean()
	tier.custom_minimum_size = Vector2(110, 0)
	tier.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tier.add_theme_font_size_override("font_size", 16)
	tier.add_theme_color_override("font_color",
		MenuSupport.colour_for_tier(card.get_tier_clean()).lightened(0.35))
	row.add_child(tier)

	var named := Label.new()
	named.text = "%s%s" % [card.player_name, "   ★" if card.is_star() else ""]
	named.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	named.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	named.add_theme_font_size_override("font_size", 20)
	row.add_child(named)

	var stats := Label.new()
	stats.text = "P %d   ·   D %d" % [card.get_attack_power(), card.get_defense_power()]
	stats.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stats.add_theme_font_size_override("font_size", 17)
	stats.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	row.add_child(stats)

	# THE ONLY ANIMATION IN HERE. Twenty cut-aways would take a minute and a
	# half; a row sliding in takes a fifth of a second and reads as the same
	# thing.
	frame.modulate.a = 0.0
	var slide := create_tween()
	slide.tween_property(frame, "modulate:a", 1.0, 0.18)
	return frame


func _wait(seconds: float) -> void:
	if seconds <= 0.0 or _done:
		return
	await get_tree().create_timer(seconds, true, false, true).timeout


# =============================================================
#  GETTING OUT OF IT
# =============================================================

func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode in [KEY_ESCAPE, KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		get_viewport().set_input_as_handled()
		skip()


func skip() -> void:
	if _done:
		return
	print("[lineup] skipped.")
	_end()


func _end() -> void:
	if _done:
		return
	_done = true
	finished.emit()
	queue_free()
