class_name BreweryMinigame
extends CanvasLayer

# =============================================================
#  THE BREWING MINI-GAMES  (round AN - Anthony, 8 Oct)
#
#  "They are extremely simple, just 1-2 actions ... think of very simple
#   flash games that take 5-15 seconds to complete."
#  Then, from the playable mock-ups: the starred game for every machine,
#  "Keep the fire" for the Brew Kettle, and the Fermenting Vat's hold game.
#
#  Clicking a machine in the Brewery opens its game. Win it and the batch is
#  made; lose it and the batch is SPOILED (what it took is gone, nothing is
#  made), exactly like a failed roll used to be.
#
#  ============ ONE ROW PER MACHINE: data/BreweryGames.csv ============
#
#    Section   the BrewerySections.csv ID it belongs to
#    Kind      which game (below)
#    Seconds   the time limit
#    Zone      how forgiving it is for a 100% brewer (each Kind says how)
#    Speed     how fast it moves (each Kind says how)
#    Hits      how much has to be done (each Kind says how)
#    Prompt    the one line telling you what to do
#    Art       a folder of pictures for it (assets/brewery/games/<id>/).
#              A picture that is missing is drawn plainly instead
#
#  ============ THE KINDS ============
#
#    stir      STIR THE MASH (Steeping Tank). Move the mouse in circles over
#              the tank. Stirring soaks the grain; stop and it clumps.
#              Speed = soak per turn. Hits = how slow counts as stopped.
#              Pictures: tank.png, paddle.png
#    rhythm    CRANK RHYTHM (Grain Mill). Left, right, left, right (arrow
#              keys, A/D, or click the left and right half). The same side
#              twice jams the mill. Hits = turns to grind it.
#              Pictures: mill.png, crank.png
#    colour    WATCH THE COLOUR (Lauter Tun). Hold to open the tap while
#              the wort runs clear; cloudy wort in the bucket spoils it.
#              Zone = how much of the time it runs clear. Speed = fill a
#              second. Pictures: tun.png, bucket.png
#    fire      KEEP THE FIRE (Brew Kettle). The heat keeps dropping; click
#              or Space to pump the bellows and keep the needle in the gold.
#              Zone = the gold's width. Hits = seconds in the gold.
#              Pictures: kettle.png, bellows.png
#    hold      (Fermenting Vat) hold to fill, let go in the gold; past the
#              top is spilled. Zone = the gold's width. Speed = fill a
#              second. Pictures: vat.png
#    conveyor  CONVEYOR (Bottling Machine). A bottle stops under the tap:
#              hold to pour, let go at its fill line. Hits = bottles.
#              Zone = how close to the line. Speed = pour a second.
#              Pictures: tap.png, bottle.png, belt.png
#    bar, mash the first two games (round AN), kept for any row that
#              still names them.
#
#  ============ THE BREWER'S TRAINING ============
#
#  "There is failure if the person operating it isn't educated in the tool."
#  The brewer's success % (data/Brewers.csv) makes every game harder the
#  less trained he is: narrower gold, faster clumping, longer jams.
#
#  FORGIVING (the tutorial): a miss is not the end. The game says so and
#  starts again, and only a win closes it.
#
#  No row for a machine = no game: the batch is rolled on the brewer's %
#  as before. Tuning.csv brewery_minigames = false turns every game off.
# =============================================================

signal finished(won: bool)

const FILE := "res://data/BreweryGames.csv"
const STAGE := Vector2(640.0, 320.0)
const BAR_SIZE := STAGE

const GOLD := Color(0.96, 0.76, 0.33)
const BEER := Color(0.91, 0.66, 0.23)
const WATER := Color(0.37, 0.66, 0.85)
const COPPER := Color(0.79, 0.45, 0.24)
const WOOD := Color(0.42, 0.29, 0.18)
const BAD := Color(1.0, 0.54, 0.36)
const GOOD := Color(0.5, 0.83, 0.42)
const INK := Color(0.07, 0.05, 0.04)

static var _rows: Dictionary = {}
static var _loaded := false

## The row of BreweryGames.csv this game plays (see game_for()).
var game: Dictionary = {}
## The brewer's success %, which sets how hard it is.
var chance := 100
## true = a miss starts the game again rather than ending it.
var forgiving := false
## The machine's name, for the title.
var title := ""

# ---- the state of play (public so a test or a tool can read it) ----
var _pos := 0.0           # bar/hold/mash: the marker or the level
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
## The game's own numbers, one dictionary so restart() clears them all.
var s: Dictionary = {}

var _bar: Control
var _status: Label
var _clock: Label
var _art: Dictionary = {}


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
			"art": MenuSupport.field(row, "Art").strip_edges(),
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


func skill() -> float:
	return clampf(chance / 100.0, 0.1, 1.0)


func kind() -> String:
	return String(game.get("kind", "bar"))


# =============================================================
#  BUILDING IT
# =============================================================

func _ready() -> void:
	layer = 155     # over the Brewery, its window, and a match TIME OUT
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_art()

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
		pad.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(pad)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(box)

	var head := MenuSupport.heading(title.to_upper(), 30, MenuSupport.COLOUR_ACCENT)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(head)

	var prompt := MenuSupport.heading(String(game.get("prompt", "")), 19)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt.custom_minimum_size = Vector2(STAGE.x, 0)
	box.add_child(prompt)

	_bar = Control.new()
	_bar.custom_minimum_size = STAGE
	_bar.clip_contents = true
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.draw.connect(_draw_stage)
	box.add_child(_bar)

	_clock = MenuSupport.heading("", 15, MenuSupport.COLOUR_TEXT_DIM)
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_clock)

	_status = MenuSupport.heading("", 16, MenuSupport.COLOUR_TEXT_DIM)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_status)

	restart()


## The row's Art folder: every picture in it, by name without .png.
func _load_art() -> void:
	_art = {}
	var folder := String(game.get("art", ""))
	if folder == "":
		return
	if not folder.begins_with("res://"):
		folder = "res://" + folder
	if not folder.ends_with("/"):
		folder += "/"
	for part: String in ["tank", "paddle", "mill", "crank", "tun", "bucket", "kettle", "bellows",
			"vat", "tap", "bottle", "belt", "background"]:
		var path := folder + part + ".png"
		if ResourceLoader.exists(path):
			_art[part] = load(path)


## Back to the start.
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
	s = {"soak": 0.0, "clump": 0.0, "last_angle": null, "turned": 0.0, "spin": 0.0,
		"ground": 0.0, "last_side": "", "jam": 0.0, "crank": 0.0,
		"t": randf_range(0.0, 6.0), "fill": 0.0, "mud": 0.0,
		"temp": 0.4, "v": 0.0, "held": 0.0,
		"line": randf_range(0.62, 0.86), "done": 0, "shift": 0.0}
	_say(_hint())


func _hint() -> String:
	match kind():
		"stir": return "Move the mouse round and round over the tank."
		"rhythm": return "Left, right, left, right: arrow keys, A and D, or click each half."
		"colour": return "Hold the mouse or Space while it runs clear."
		"fire": return "Click or Space to pump the bellows."
		"conveyor": return "Hold the mouse or Space to pour, let go at the line."
		"hold": return "Hold the mouse or Space. Let go in the gold."
		"mash": return "Click, click, click!"
	var need := int(game.get("hits", 1))
	return "Click or Space in the gold." if need <= 1 else "Click or Space in the gold - %d in a row." % need


# =============================================================
#  PLAYING IT  (tick / press / release / side / stir are public so a test
#  or a tool can drive them)
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
	var out := ""
	match kind():
		"stir": out = _tick_stir(delta)
		"rhythm": out = _tick_rhythm(delta)
		"colour": out = _tick_colour(delta)
		"fire": out = _tick_fire(delta)
		"conveyor": out = _tick_conveyor(delta)
		"hold":
			if _holding:
				_pos += delta * float(game.get("speed", 0.5))
				if _pos >= 1.0:
					_pos = 1.0
					out = "It ran over!"
		"mash":
			_pos = maxf(0.0, _pos - delta * float(game.get("speed", 0.15)))
		_:
			_pos += _dir * delta * float(game.get("speed", 1.0)) * 2.0
			if _pos >= 1.0:
				_pos = 2.0 - _pos
				_dir = -1.0
			elif _pos <= 0.0:
				_pos = -_pos
				_dir = 1.0
	if out == "won":
		_win()
		return
	if out != "":
		_lose(out)
		return
	if _time_left <= 0.0:
		_time_left = 0.0
		_lose("Too slow!")
		return
	if _clock != null:
		_clock.text = "%.1f s" % _time_left
	if _bar != null:
		_bar.queue_redraw()


# ---- STIR THE MASH ----

## The pointer is at `at` (stage pixels): stirring is how far round the
## middle of the tank it has gone.
func stir(at: Vector2) -> void:
	if _over or kind() != "stir":
		return
	var angle := (at - STAGE * Vector2(0.5, 0.56)).angle()
	if s["last_angle"] != null:
		s["turned"] = float(s["turned"]) + absf(wrapf(angle - float(s["last_angle"]), -PI, PI))
	s["last_angle"] = angle


func _tick_stir(delta: float) -> String:
	var turned := minf(float(s["turned"]), 0.6)
	s["turned"] = 0.0
	s["spin"] = float(s["spin"]) + turned
	# Speed = how much one full turn soaks, for a 100% brewer.
	s["soak"] = float(s["soak"]) + turned / TAU * float(game.get("speed", 0.12)) * (0.6 + 0.5 * skill())
	var still := turned / maxf(delta, 0.001) < 1.0
	s["clump"] = clampf(float(s["clump"]) + (delta * 0.35 / skill() if still else -delta * 0.4), 0.0, 1.0)
	if float(s["soak"]) >= 1.0:
		return "won"
	if float(s["clump"]) >= 1.0:
		return "It clumped!"
	return ""


# ---- CRANK RHYTHM ----

## "L" or "R": one pull of the crank.
func side(which: String) -> void:
	if _over or kind() != "rhythm" or float(s["jam"]) > 0.0:
		return
	if which == String(s["last_side"]):
		s["jam"] = 0.7 / skill()
		s["ground"] = maxf(0.0, float(s["ground"]) - 0.05)
		AudioDirector.fire(get_tree(), "brew_game_lost", {"section": game.get("section", "")})
	else:
		s["ground"] = float(s["ground"]) + (1.0 / float(game.get("hits", 22))) * (0.7 + 0.4 * skill()) / 1.1
		s["crank"] = float(s["crank"]) + PI * 0.5
		AudioDirector.fire(get_tree(), "brew_game_hit", {"section": game.get("section", "")})
	s["last_side"] = which


func _tick_rhythm(delta: float) -> String:
	s["jam"] = maxf(0.0, float(s["jam"]) - delta)
	return "won" if float(s["ground"]) >= 1.0 else ""


# ---- WATCH THE COLOUR ----

func clear_now() -> bool:
	# Zone = how much of the time it runs clear, for a 100% brewer.
	var clearness := (sin(float(s["t"])) + 1.0) * 0.5
	return clearness > 1.0 - float(game.get("zone", 0.55)) * skill()


func _tick_colour(delta: float) -> String:
	s["t"] = float(s["t"]) + delta * 1.1
	if _holding:
		if clear_now():
			s["fill"] = float(s["fill"]) + delta * float(game.get("speed", 0.28))
		else:
			s["mud"] = float(s["mud"]) + delta * 0.9
	if float(s["fill"]) >= 1.0:
		return "won"
	if float(s["mud"]) >= 1.0:
		return "Cloudy wort in the bucket!"
	return ""


# ---- KEEP THE FIRE ----

func fire_half() -> float:
	return float(game.get("zone", 0.14)) * (0.43 + 0.57 * skill())


func _tick_fire(delta: float) -> String:
	s["v"] = (float(s["v"]) - delta * 0.55) * pow(0.96, delta * 60.0)
	s["temp"] = clampf(float(s["temp"]) + float(s["v"]) * delta, 0.0, 1.0)
	if absf(float(s["temp"]) - 0.68) < fire_half():
		s["held"] = float(s["held"]) + delta
	return "won" if float(s["held"]) >= float(game.get("hits", 5)) else ""


# ---- CONVEYOR ----

func pour_tolerance() -> float:
	return float(game.get("zone", 0.1)) * (0.4 + 0.6 * skill())


func _tick_conveyor(delta: float) -> String:
	if float(s["shift"]) > 0.0:
		s["shift"] = float(s["shift"]) - delta
		if float(s["shift"]) <= 0.0:
			s["fill"] = 0.0
			s["line"] = randf_range(0.62, 0.86)
		return ""
	if _holding:
		s["fill"] = float(s["fill"]) + delta * float(game.get("speed", 0.45))
		if float(s["fill"]) >= 1.0:
			return "It's overflowing!"
	return ""


# ---- the buttons ----

func press() -> void:
	if _over:
		return
	match kind():
		"colour", "hold":
			_holding = true
		"conveyor":
			if float(s["shift"]) <= 0.0:
				_holding = true
		"fire":
			s["v"] = float(s["v"]) + 0.32
			AudioDirector.fire(get_tree(), "brew_game_hit", {"section": game.get("section", "")})
		"rhythm", "stir":
			pass
		"mash":
			_pos = minf(1.0, _pos + 1.0 / float(maxi(_clicks_needed, 1)))
			AudioDirector.fire(get_tree(), "brew_game_hit", {"section": game.get("section", "")})
			if _pos >= 1.0:
				_win()
		_:
			if in_zone():
				_hits += 1
				AudioDirector.fire(get_tree(), "brew_game_hit", {"section": game.get("section", "")})
				if _hits >= int(game.get("hits", 1)):
					_win()
				else:
					_say("Good! %d more." % (int(game.get("hits", 1)) - _hits))
					_zone_start = randf_range(0.12, maxf(0.12, 0.92 - _zone_size))
			else:
				_lose("Missed!")


func release() -> void:
	if _over or not _holding:
		return
	_holding = false
	match kind():
		"hold":
			if in_zone():
				_win()
			else:
				_lose("Not quite!" if _pos < _zone_start else "Too much!")
		"conveyor":
			var off := float(s["fill"]) - float(s["line"])
			if absf(off) > pour_tolerance():
				_lose("Not full!" if off < 0.0 else "Overfilled!")
				return
			s["done"] = int(s["done"]) + 1
			AudioDirector.fire(get_tree(), "brew_game_hit", {"section": game.get("section", "")})
			if int(s["done"]) >= int(game.get("hits", 3)):
				_win()
			else:
				s["shift"] = 0.5
				_say("Good! %d more." % (int(game.get("hits", 3)) - int(s["done"])))


func in_zone() -> bool:
	return _pos >= _zone_start and _pos <= _zone_start + _zone_size


## A good hand, for the tools that film the games and the tests: one step of
## playing it well. `also_tick` = false when the game runs on its own
## (_process) and the hand only has to press.
func bot_step(delta: float, also_tick := true) -> void:
	if _over:
		if also_tick:
			tick(delta)
		return
	match kind():
		"stir":
			var a := float(s.get("bot_a", 0.0)) + delta * 9.0
			s["bot_a"] = a
			stir(STAGE * Vector2(0.5, 0.56) + Vector2(cos(a) * 150.0, sin(a) * 90.0))
		"rhythm":
			s["bot_t"] = float(s.get("bot_t", 0.0)) + delta
			if float(s["bot_t"]) > 0.16:
				s["bot_t"] = 0.0
				side("R" if String(s["last_side"]) == "L" else "L")
		"colour":
			if clear_now() and not _holding:
				press()
			elif not clear_now() and _holding:
				release()
		"fire":
			if float(s["temp"]) < 0.66 and float(s["v"]) < 0.1:
				press()
		"conveyor":
			if float(s["shift"]) > 0.0:
				pass
			elif not _holding:
				press()
			elif float(s["fill"]) >= float(s["line"]):
				release()
		"hold":
			if not _holding and _pos == 0.0:
				press()
			elif _holding and _pos >= _zone_start + _zone_size * 0.5:
				release()
		"mash":
			press()
		_:
			if in_zone() and _pos > _zone_start + _zone_size * 0.3:
				press()
	if also_tick:
		tick(delta)


func _win() -> void:
	_over = true
	_won = true
	_holding = false
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
	_holding = false
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
			if kind() == "rhythm" and _bar != null:
				side("L" if button.global_position.x < _bar.global_position.x + _bar.size.x * 0.5 else "R")
			press()
		else:
			release()
	var motion := event as InputEventMouseMotion
	if motion != null and kind() == "stir" and _bar != null:
		stir(motion.global_position - _bar.global_position)


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or key.echo:
		return
	if kind() == "rhythm" and key.pressed:
		if key.keycode in [KEY_LEFT, KEY_A]:
			get_viewport().set_input_as_handled()
			side("L")
		elif key.keycode in [KEY_RIGHT, KEY_D]:
			get_viewport().set_input_as_handled()
			side("R")
		return
	if key.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		get_viewport().set_input_as_handled()
		if key.pressed:
			press()
		else:
			release()


# =============================================================
#  DRAWING IT  (a picture from the Art folder when there is one; plain
#  shapes when there is not)
# =============================================================

func _picture(part: String, centre: Vector2, size: Vector2, rot: float = 0.0,
		tint: Color = Color.WHITE) -> bool:
	var tex: Texture2D = _art.get(part)
	if tex == null:
		return false
	_bar.draw_set_transform(centre, rot, Vector2.ONE)
	_bar.draw_texture_rect(tex, Rect2(-size * 0.5, size), false, tint)
	_bar.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return true


func _meter(at: Rect2, fill: float, colour: Color, words: String = "") -> void:
	_bar.draw_rect(at, Color(0, 0, 0))
	_bar.draw_rect(Rect2(at.position, Vector2(at.size.x * clampf(fill, 0.0, 1.0), at.size.y)), colour)
	_bar.draw_rect(at, MenuSupport.COLOUR_TEXT_DIM, false, 2.0)
	if words != "":
		_text(words, at.position + Vector2(0, -6), 14, MenuSupport.COLOUR_TEXT, HORIZONTAL_ALIGNMENT_LEFT)


func _text(words: String, at: Vector2, size: int, colour: Color,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> void:
	var font := ThemeDB.fallback_font
	var width := 400.0
	var start := at - Vector2(width * 0.5, 0) if align == HORIZONTAL_ALIGNMENT_CENTER else at
	_bar.draw_string(font, start, words, align, width, size, colour)


func _draw_stage() -> void:
	_bar.draw_rect(Rect2(Vector2.ZERO, STAGE), INK)
	var back: Texture2D = _art.get("background")
	if back != null:
		_bar.draw_texture_rect(back, Rect2(Vector2.ZERO, STAGE), false, Color(1, 1, 1, 0.5))
	match kind():
		"stir": _draw_stir()
		"rhythm": _draw_rhythm()
		"colour": _draw_colour()
		"fire": _draw_fire()
		"conveyor": _draw_conveyor()
		"hold": _draw_hold()
		_: _draw_bar_game()
	_bar.draw_rect(Rect2(Vector2.ZERO, STAGE), MenuSupport.COLOUR_TEXT_DIM, false, 2.0)


func _draw_stir() -> void:
	var middle := STAGE * Vector2(0.5, 0.56)
	var soak := float(s["soak"])
	# The mash fills the tank's opening: the picture's is smaller and higher
	# than the plain drawing's.
	var mash := middle
	var size := Vector2(130.0, 91.0)
	if _picture("tank", middle, Vector2(330, 250)):
		mash = middle + Vector2(0, -35)
		size = Vector2(100.0, 40.0)
	else:
		_bar.draw_set_transform(middle, 0.0, Vector2(1.0, 0.72))
		_bar.draw_circle(Vector2.ZERO, 155.0, COPPER)
		_bar.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# The grain darkens as it soaks.
	_bar.draw_set_transform(mash, 0.0, Vector2(1.0, size.y / size.x))
	_bar.draw_circle(Vector2.ZERO, size.x, Color(0.8, 0.67, 0.36).lerp(Color(0.45, 0.33, 0.18), soak))
	_bar.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var spin := float(s["spin"])
	for i in 6:
		var a := spin + i * 1.05
		_bar.draw_circle(mash + Vector2(cos(a), sin(a)) * size * 0.6, 5.0, Color(1, 1, 1, 0.35))
	var tip := mash + Vector2(cos(spin), sin(spin)) * size * 0.53
	if not _picture("paddle", tip + Vector2(0, -50), Vector2(60, 130), 0.2 * sin(spin)):
		_bar.draw_line(tip, tip + Vector2(0, -110), WOOD, 10.0)
	_meter(Rect2(40, 30, 220, 18), soak, WATER, "SOAKED")
	_meter(Rect2(380, 30, 220, 18), float(s["clump"]), BAD, "CLUMPS")


func _draw_rhythm() -> void:
	var middle := Vector2(300, 170)
	if not _picture("mill", middle, Vector2(220, 240)):
		_bar.draw_rect(Rect2(200, 70, 200, 200), WOOD)
		_bar.draw_rect(Rect2(230, 40, 140, 40), WOOD.darkened(0.3))
	# On the mill's wheel.
	var hub := Vector2(340, 175) if _art.has("mill") else Vector2(450, 170)
	var crank := float(s["crank"])
	var jammed := float(s["jam"]) > 0.0
	if not _picture("crank", hub + Vector2(cos(crank), sin(crank)) * 30.0, Vector2(70, 70), crank,
			BAD if jammed else Color.WHITE):
		_bar.draw_line(hub, hub + Vector2(cos(crank), sin(crank)) * 60.0, BAD if jammed else GOLD, 10.0)
		_bar.draw_circle(hub, 12.0, MenuSupport.COLOUR_TEXT_DIM)
	var last := String(s["last_side"])
	_text("< LEFT", Vector2(80, 180), 28, GOLD if last != "L" else MenuSupport.COLOUR_TEXT_DIM)
	_text("RIGHT >", Vector2(570, 180), 28, GOLD if last != "R" else MenuSupport.COLOUR_TEXT_DIM)
	if jammed:
		_text("JAMMED!", Vector2(320, 40), 30, BAD)
	_meter(Rect2(120, 290, 400, 16), float(s["ground"]), BEER, "GROUND")


func _draw_colour() -> void:
	var clear := clear_now()
	if not _picture("tun", Vector2(320, 85), Vector2(320, 150)):
		_bar.draw_rect(Rect2(170, 20, 300, 120), COPPER)
	_bar.draw_rect(Rect2(305, 140, 30, 22), MenuSupport.COLOUR_TEXT_DIM)
	if _holding:
		_bar.draw_rect(Rect2(313, 162, 14, 100), BEER if clear else Color(0.48, 0.39, 0.28))
	var fill := float(s["fill"])
	if _picture("bucket", Vector2(320, 285), Vector2(150, 70)):
		# The wort shows in the bucket's mouth, rising to the rim.
		_bar.draw_set_transform(Vector2(320, 268 - 6 * fill), 0.0, Vector2(1.0, 0.2))
		_bar.draw_circle(Vector2.ZERO, 50.0, Color(BEER, clampf(fill * 3.0, 0.0, 1.0)))
		_bar.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		_meter(Rect2(470, 240, 140, 16), fill, BEER, "BUCKET")
	else:
		_bar.draw_rect(Rect2(250, 255, 140, 60), WOOD)
		_bar.draw_rect(Rect2(258, 309 - 50 * fill, 124, 50 * fill), BEER)
	_text("CLEAR" if clear else "CLOUDY", Vector2(540, 100), 32, GOLD if clear else MenuSupport.COLOUR_TEXT_DIM)
	_meter(Rect2(470, 280, 140, 16), float(s["mud"]), BAD, "MUD")


func _draw_fire() -> void:
	if not _picture("kettle", Vector2(140, 210), Vector2(200, 200)):
		_bar.draw_circle(Vector2(140, 220), 80.0, COPPER)
	var pumping := float(s["v"]) > 0.15
	if not _picture("bellows", Vector2(560, 230), Vector2(120, 100) * (0.9 if pumping else 1.0)):
		_bar.draw_rect(Rect2(510, 200, 100, 60 if not pumping else 45), WOOD)
	var centre := Vector2(330, 250)
	var radius := 150.0
	var half := fire_half()
	_bar.draw_arc(centre, radius, PI, TAU, 48, Color(0, 0, 0), 24.0)
	_bar.draw_arc(centre, radius, PI + (0.68 - half) * PI, PI + (0.68 + half) * PI, 16, GOLD, 24.0)
	var a := PI + float(s["temp"]) * PI
	_bar.draw_line(centre, centre + Vector2(cos(a), sin(a)) * (radius - 6.0), MenuSupport.COLOUR_TEXT, 6.0)
	_text("IN THE GOLD  %.1f / %d s" % [float(s["held"]), int(game.get("hits", 5))],
		Vector2(330, 300), 22, GOLD)


func _draw_conveyor() -> void:
	if not _picture("belt", Vector2(320, 285), Vector2(640, 40)):
		_bar.draw_rect(Rect2(0, 270, 640, 20), WOOD.darkened(0.4))
	var shift := float(s["shift"])
	var off := (0.5 - shift) * 400.0 if shift > 0.0 else 0.0
	if not _picture("tap", Vector2(320, 50), Vector2(90, 90)):
		_bar.draw_rect(Rect2(300, 10, 40, 70), MenuSupport.COLOUR_TEXT_DIM)
	if _holding:
		_bar.draw_rect(Rect2(314, 80, 12, 70), BEER)
	var bottom := 270.0
	var tall := 120.0
	var fill := float(s["line"]) if shift > 0.0 else float(s["fill"])
	var x := 320.0 + off
	_bar.draw_rect(Rect2(x - 18, bottom - tall * fill, 36, tall * fill), BEER)
	if not _picture("bottle", Vector2(x, bottom - tall * 0.6), Vector2(48, tall * 1.25)):
		_bar.draw_rect(Rect2(x - 18, bottom - tall, 36, tall), Color(0.31, 0.68, 0.36, 0.5), false, 3.0)
	var tol := pour_tolerance()
	_bar.draw_rect(Rect2(x - 26, bottom - tall * (float(s["line"]) + tol), 52, tall * tol * 2.0), Color(GOLD, 0.6))
	_text("%d / %d" % [int(s["done"]), int(game.get("hits", 3))], Vector2(580, 50), 28, GOLD)


func _draw_hold() -> void:
	if _picture("vat", Vector2(130, 160), Vector2(180, 220)):
		pass
	var frame := Rect2(260, 140, 340, 46)
	_bar.draw_rect(frame, Color(0, 0, 0))
	_bar.draw_rect(Rect2(frame.position + Vector2(frame.size.x * _zone_start, 0),
		Vector2(frame.size.x * _zone_size, frame.size.y)), Color(GOLD, 0.85))
	_bar.draw_rect(Rect2(frame.position, Vector2(frame.size.x * _pos, frame.size.y)),
		Color(GOOD, 0.7) if _won else Color(0.55, 0.78, 0.95, 0.55))
	_bar.draw_line(frame.position + Vector2(frame.size.x * _pos, 0),
		frame.position + Vector2(frame.size.x * _pos, frame.size.y), Color.WHITE, 3.0)
	_bar.draw_rect(frame, MenuSupport.COLOUR_TEXT_DIM, false, 2.0)


func _draw_bar_game() -> void:
	var frame := Rect2(20, 140, 600, 46)
	_bar.draw_rect(frame, Color(0, 0, 0))
	if kind() == "mash":
		_bar.draw_rect(Rect2(frame.position, Vector2(frame.size.x * _pos, frame.size.y)), GOOD if _won else GOLD)
	else:
		_bar.draw_rect(Rect2(frame.position + Vector2(frame.size.x * _zone_start, 0),
			Vector2(frame.size.x * _zone_size, frame.size.y)), Color(GOLD, 0.85))
		var x := frame.position.x + frame.size.x * _pos
		_bar.draw_line(Vector2(x, frame.position.y - 6), Vector2(x, frame.end.y + 6), GOOD if _won else Color.WHITE, 5.0)
	_bar.draw_rect(frame, MenuSupport.COLOUR_TEXT_DIM, false, 2.0)
