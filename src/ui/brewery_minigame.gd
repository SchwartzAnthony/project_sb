class_name BreweryMinigame
extends CanvasLayer

# =============================================================
#  THE BREWING MINI-GAMES  (round AN - Anthony, 8 Oct)
#
#  "They are extremely simple, just 1-2 actions, like hitting the right
#   temperature is a bar that goes back and forth having to hit the right
#   spot to heat up, think of very simple flash games that take 5-15
#   seconds to complete."
#
#  Clicking a machine in the Brewery opens its game. Win it and the batch is
#  made; lose it and the batch is SPOILED (what it took is gone, nothing is
#  made), exactly like a failed roll used to be.
#
#  ============ ONE ROW PER MACHINE: data/BreweryGames.csv ============
#
#    Section   the BrewerySections.csv ID it belongs to
#    Kind      bar    a marker sweeps back and forth; click (or Space) when
#                     it is in the gold. Hits = how many times in a row
#              hold   hold the mouse (or Space) to fill; let go when the
#                     level is in the gold. Past the top = spilled
#              mash   click as fast as you can; the meter drains on its own.
#                     Fill it before the time runs out
#    Seconds   the time limit
#    Zone      how wide the gold is, as a share of the bar (0.15 = 15%),
#              for a brewer who never fails (100%)
#    Speed     bar: sweeps a second. hold: how much of the bar a second of
#              holding fills. mash: how much of the meter drains a second
#    Hits      bar: gold hits needed. mash: clicks to fill the meter
#    Prompt    the one line telling you what to do
#
#  ============ THE BREWER'S TRAINING IS THE GOLD ============
#
#  "There is failure if the person operating it isn't educated in the tool."
#  The brewer's success % (data/Brewers.csv) shrinks the gold: a 100% brewer
#  gets the whole Zone, a 55% brewer a little over half of it, nobody at all
#  (40%) a sliver. A mash game needs more clicks the less trained he is.
#
#  FORGIVING (the tutorial): a miss is not the end. The game says so and
#  starts again, and only a win closes it.
#
#  No row for a machine = no game: the batch is rolled on the brewer's %
#  as before. Tuning.csv brewery_minigames = false turns every game off.
# =============================================================

signal finished(won: bool)

const FILE := "res://data/BreweryGames.csv"
const BAR_SIZE := Vector2(640.0, 56.0)

static var _rows: Dictionary = {}
static var _loaded := false

## The row of BreweryGames.csv this game plays (see game_for()).
var game: Dictionary = {}
## The brewer's success %, which sets how wide the gold is.
var chance := 100
## true = a miss starts the game again rather than ending it.
var forgiving := false
## The machine's name, for the title.
var title := ""

# ---- the state of play ----
var _pos := 0.0           # bar: where the marker is, 0..1. hold/mash: the level
var _dir := 1.0
var _zone_start := 0.0
var _zone_size := 0.15
var _hits := 0
var _clicks_needed := 10
var _holding := false
var _time_left := 10.0
var _over := false
var _result_shown := 0.0
var _won := false

var _bar: Control
var _status: Label
var _clock: Label


# =============================================================
#  THE CSV
# =============================================================

static func reload() -> void:
	_loaded = false
	_load()


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_rows = {}
	for row in MenuSupport.read_csv(FILE):
		var id_text := CardDatabase._normalise(MenuSupport.field(row, "Section"))
		if id_text == "":
			continue
		_rows[id_text] = {
			"section": MenuSupport.field(row, "Section").strip_edges(),
			"kind": MenuSupport.field(row, "Kind", "bar").strip_edges().to_lower(),
			"seconds": MenuSupport.field_float(row, "Seconds", 10.0),
			"zone": clampf(MenuSupport.field_float(row, "Zone", 0.15), 0.02, 0.9),
			"speed": MenuSupport.field_float(row, "Speed", 1.0),
			"hits": maxi(1, MenuSupport.field_int(row, "Hits", 1)),
			"prompt": MenuSupport.field(row, "Prompt").strip_edges(),
		}


## The game for a Brewery section, or {} when it has none (or games are off).
static func game_for(section_id: String) -> Dictionary:
	var db := CardDatabase.get_db()
	if db != null and not db.tune_bool("brewery_minigames", true):
		return {}
	_load()
	return _rows.get(CardDatabase._normalise(section_id), {})


## How wide the gold is for this brewer: the row's Zone times his success %.
static func zone_for(row: Dictionary, success: int) -> float:
	return clampf(float(row.get("zone", 0.15)) * clampf(success / 100.0, 0.1, 1.0), 0.02, 0.9)


## How many clicks a mash game needs from this brewer: more, the less he is
## trained (40% needs 1.6 times the row's Hits).
static func clicks_for(row: Dictionary, success: int) -> int:
	return int(ceil(float(row.get("hits", 10)) * (2.0 - clampf(success / 100.0, 0.1, 1.0))))


## Open the game over everything. Wait on `finished`.
static func open(host: Node, row: Dictionary, success: int, machine: String,
		is_forgiving: bool = false) -> BreweryMinigame:
	var view := BreweryMinigame.new()
	view.game = row
	view.chance = success
	view.title = machine
	view.forgiving = is_forgiving
	host.add_child(view)
	return view


# =============================================================
#  BUILDING IT
# =============================================================

func _ready() -> void:
	layer = 155     # over the Brewery, its window, and a match TIME OUT
	process_mode = Node.PROCESS_MODE_ALWAYS

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.gui_input.connect(_on_input)
	add_child(root)

	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",
		MenuSupport.panel_style(MenuSupport.COLOUR_PANEL, MenuSupport.COLOUR_ACCENT))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	# Grows out from the middle, so it stays centred whatever it holds.
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(panel)

	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 26)
	panel.add_child(pad)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(box)

	var head := MenuSupport.heading(title.to_upper(), 30, MenuSupport.COLOUR_ACCENT)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(head)

	var prompt := MenuSupport.heading(String(game.get("prompt", "")), 20)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt.custom_minimum_size = Vector2(BAR_SIZE.x, 0)
	box.add_child(prompt)

	_bar = Control.new()
	_bar.custom_minimum_size = BAR_SIZE
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.draw.connect(_draw_bar)
	box.add_child(_bar)

	_clock = MenuSupport.heading("", 15, MenuSupport.COLOUR_TEXT_DIM)
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_clock)

	_status = MenuSupport.heading("", 16, MenuSupport.COLOUR_TEXT_DIM)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_status)

	restart()


## Back to the start: a new gold spot, the clock full.
func restart() -> void:
	_zone_size = zone_for(game, chance)
	_clicks_needed = clicks_for(game, chance)
	_zone_start = randf_range(0.12, maxf(0.12, 0.92 - _zone_size))
	if kind() == "hold":
		# The level has to rise into it, so the gold is never at the bottom.
		_zone_start = randf_range(0.45, maxf(0.45, 0.92 - _zone_size))
	_pos = 0.0
	_dir = 1.0
	_hits = 0
	_holding = false
	_time_left = float(game.get("seconds", 10.0))
	_over = false
	_won = false
	_result_shown = 0.0
	_say(_hint())


func kind() -> String:
	return String(game.get("kind", "bar"))


func _hint() -> String:
	match kind():
		"hold": return "Hold the mouse or Space. Let go in the gold."
		"mash": return "Click, click, click!"
	var need := int(game.get("hits", 1))
	return "Click or Space in the gold." if need <= 1 else "Click or Space in the gold - %d in a row." % need


# =============================================================
#  PLAYING IT  (tick / press / release are public so a test can drive them)
# =============================================================

func _process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	if _over:
		_result_shown += delta
		if _result_shown >= 1.1:
			_end()
		return
	_time_left -= delta
	match kind():
		"bar":
			_pos += _dir * delta * float(game.get("speed", 1.0)) * 2.0
			if _pos >= 1.0:
				_pos = 2.0 - _pos
				_dir = -1.0
			elif _pos <= 0.0:
				_pos = -_pos
				_dir = 1.0
		"hold":
			if _holding:
				_pos += delta * float(game.get("speed", 0.5))
				if _pos >= 1.0:
					_pos = 1.0
					_lose("It ran over!")
					return
		"mash":
			_pos = maxf(0.0, _pos - delta * float(game.get("speed", 0.15)))
	if _time_left <= 0.0:
		_time_left = 0.0
		_lose("Too slow!")
		return
	if _clock != null:
		_clock.text = "%.1f s" % _time_left
	if _bar != null:
		_bar.queue_redraw()


func press() -> void:
	if _over:
		return
	match kind():
		"bar":
			if in_zone():
				_hits += 1
				AudioDirector.fire(get_tree(), "brew_game_hit", {"section": game.get("section", "")})
				if _hits >= int(game.get("hits", 1)):
					_win()
				else:
					_say("Good! %d more." % (int(game.get("hits", 1)) - _hits))
					# A new spot for the next one.
					_zone_start = randf_range(0.12, maxf(0.12, 0.92 - _zone_size))
			else:
				_lose("Missed!")
		"hold":
			_holding = true
		"mash":
			_pos = minf(1.0, _pos + 1.0 / float(maxi(_clicks_needed, 1)))
			AudioDirector.fire(get_tree(), "brew_game_hit", {"section": game.get("section", "")})
			if _pos >= 1.0:
				_win()


func release() -> void:
	if _over or kind() != "hold" or not _holding:
		return
	_holding = false
	if in_zone():
		_win()
	else:
		_lose("Not quite!" if _pos < _zone_start else "Too much!")


func in_zone() -> bool:
	return _pos >= _zone_start and _pos <= _zone_start + _zone_size


func _win() -> void:
	_over = true
	_won = true
	_say("PERFECT!", MenuSupport.COLOUR_ACCENT)
	AudioDirector.fire(get_tree(), "brew_game_won", {"section": game.get("section", "")})
	if _bar != null:
		_bar.queue_redraw()


func _lose(why: String) -> void:
	AudioDirector.fire(get_tree(), "brew_game_lost", {"section": game.get("section", "")})
	if forgiving:
		# THE TUTORIAL: say it, and go again.
		restart()
		_say("%s Again!" % why, Color(1.0, 0.72, 0.4))
		return
	_over = true
	_won = false
	_say("%s The batch is spoiled." % why, Color(1.0, 0.55, 0.4))
	if _bar != null:
		_bar.queue_redraw()


func _end() -> void:
	set_process(false)
	finished.emit(_won)
	queue_free()


func _say(words: String, colour: Color = MenuSupport.COLOUR_TEXT_DIM) -> void:
	if _status == null:
		return
	_status.text = words
	_status.add_theme_color_override("font_color", colour)


func _on_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			press()
		else:
			release()


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or key.echo:
		return
	if key.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		get_viewport().set_input_as_handled()
		if key.pressed:
			press()
		else:
			release()


# =============================================================
#  DRAWING IT
# =============================================================

func _draw_bar() -> void:
	var size := _bar.size
	var frame := Rect2(Vector2.ZERO, size)
	_bar.draw_rect(frame, Color(0.08, 0.08, 0.10))
	var gold := MenuSupport.COLOUR_ACCENT
	var won_colour := Color(0.45, 0.85, 0.4)
	if kind() == "mash":
		var fill := Rect2(Vector2.ZERO, Vector2(size.x * _pos, size.y))
		_bar.draw_rect(fill, won_colour if _won else gold)
	else:
		var zone := Rect2(Vector2(size.x * _zone_start, 0.0), Vector2(size.x * _zone_size, size.y))
		_bar.draw_rect(zone, Color(gold, 0.85))
		if kind() == "hold":
			var fill := Rect2(Vector2.ZERO, Vector2(size.x * _pos, size.y))
			_bar.draw_rect(fill, Color(0.95, 0.85, 0.45, 0.55) if not _won else Color(won_colour, 0.7))
			_bar.draw_line(Vector2(size.x * _pos, 0), Vector2(size.x * _pos, size.y), Color.WHITE, 3.0)
		else:
			var x := size.x * _pos
			_bar.draw_line(Vector2(x, -6), Vector2(x, size.y + 6), won_colour if _won else Color.WHITE, 5.0)
	_bar.draw_rect(frame, MenuSupport.COLOUR_TEXT_DIM, false, 2.0)
