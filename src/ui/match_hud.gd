class_name MatchHUD
extends HBoxContainer

# =============================================================
#  THE MATCH HUD — the speed buttons and the AUTO toggle
#
#  A small strip in the top-left of a match. Two controls:
#
#    1x 2x 4x 8x   how fast time runs. Number keys 1-4 do the same.
#                  Hold F for a blast of 20x, let go to drop back.
#
#    AUTO          the game picks your cards for you at every PLAY MAKER
#                  and every Star swap, so you can sit and watch a whole
#                  match without touching anything.
#
#  AUTO is remembered in your save (as the flag `auto_pick`), so it is still
#  on next match and any CSV can test it with  flag:auto_pick .
#
#  There is no art here on purpose — it is meant to be replaced. Everything
#  it does is two lines of public API that any screen you design later can
#  call instead:
#      GameSpeed.set_speed(4.0)
#      MatchHUD.set_auto_pick(state, true)
# =============================================================

const AUTO_FLAG := "auto_pick"

signal auto_pick_changed(is_on: bool)

var db: CardDatabase
var state: GameState

var _steps: Array[float] = []
var _turbo: float = 20.0
var _chosen: float = 1.0
var _turbo_held: bool = false

var _speed_buttons: Array[Button] = []
var _auto_button: Button = null


# =============================================================
#  IS AUTO-PICK ON?  — the only thing main_scene needs to ask
# =============================================================

static func auto_pick_on(save: GameState) -> bool:
	return save != null and save.has_flag(AUTO_FLAG)


static func set_auto_pick(save: GameState, is_on: bool) -> void:
	if save != null:
		save.set_flag(AUTO_FLAG, is_on)


# =============================================================
#  BUILDING IT
# =============================================================

func setup(database: CardDatabase, save: GameState) -> void:
	db = database
	state = save

	_steps = GameSpeed.steps(db)
	_turbo = GameSpeed.turbo(db)
	_chosen = clampf(db.tune_float("game_speed_start", 1.0),
		GameSpeed.MIN_SPEED, GameSpeed.MAX_SPEED)

	# Tuning.csv sets the STARTING value of AUTO; after that the save wins,
	# so turning it on during a match keeps it on next time.
	if state != null and not state.has_flag(AUTO_FLAG) and db.tune_bool("auto_pick", false):
		state.set_flag(AUTO_FLAG, true)

	add_theme_constant_override("separation", 5)
	_build()

	GameSpeed.set_speed(_chosen)
	_refresh()


func _build() -> void:
	for value in _steps:
		var button := _make_button(GameSpeed.label_for(value), 46.0)
		button.tooltip_text = "Run the game at %s" % GameSpeed.label_for(value)
		button.pressed.connect(_choose.bind(value))
		add_child(button)
		_speed_buttons.append(button)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(10, 0)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(spacer)

	_auto_button = _make_button("AUTO", 66.0)
	_auto_button.tooltip_text = "Let the game pick your cards. Sit back and watch."
	_auto_button.pressed.connect(_toggle_auto)
	add_child(_auto_button)


func _make_button(text: String, width: float) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(width, 30)
	button.focus_mode = Control.FOCUS_NONE   # or SPACE would press it in a duel
	button.add_theme_font_size_override("font_size", 13)
	return button


# =============================================================
#  PRESSING THINGS
# =============================================================

func _choose(value: float) -> void:
	_chosen = value
	if not _turbo_held:
		GameSpeed.set_speed(_chosen)
	_refresh()


func _toggle_auto() -> void:
	var now := not auto_pick_on(state)
	set_auto_pick(state, now)
	if state != null:
		state.save_to_disk()
	print("[auto] Auto-pick is %s." % ("ON" if now else "off"))
	auto_pick_changed.emit(now)
	_refresh()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or key.echo:
		return

	# Number keys pick a speed. KEY_1 is 49, so subtracting gives the index.
	if key.pressed and key.keycode >= KEY_1 and key.keycode <= KEY_9:
		var index := key.keycode - KEY_1
		if index < _steps.size():
			_choose(_steps[index])
			get_viewport().set_input_as_handled()
		return

	if key.keycode == KEY_F:
		_turbo_held = key.pressed
		GameSpeed.set_speed(_turbo if _turbo_held else _chosen)
		_refresh()
		get_viewport().set_input_as_handled()
		return

	if key.pressed and key.keycode == KEY_A:
		_toggle_auto()
		get_viewport().set_input_as_handled()


## Safety net: if the window loses focus while F is held, the key-up never
## arrives and the game would be stuck at 20x forever.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _turbo_held:
		_turbo_held = false
		GameSpeed.set_speed(_chosen)
		_refresh()


# =============================================================
#  SHOWING WHAT IS ON
# =============================================================

func _refresh() -> void:
	for i in _speed_buttons.size():
		var live := is_equal_approx(_steps[i], _chosen) and not _turbo_held
		_paint(_speed_buttons[i], live)

	if _auto_button != null:
		var on := auto_pick_on(state)
		_auto_button.text = "AUTO ON" if on else "AUTO"
		_paint(_auto_button, on)


func _paint(button: Button, lit: bool) -> void:
	var fill := MenuSupport.COLOUR_SLOT_EMPTY if lit else MenuSupport.COLOUR_PANEL
	var edge := MenuSupport.COLOUR_ACCENT if lit else MenuSupport.COLOUR_TEXT_DIM
	button.add_theme_stylebox_override("normal", MenuSupport.panel_style(fill, edge))
	button.add_theme_stylebox_override("hover",
		MenuSupport.panel_style(MenuSupport.COLOUR_SLOT_EMPTY, MenuSupport.COLOUR_ACCENT))
	button.add_theme_stylebox_override("pressed",
		MenuSupport.panel_style(MenuSupport.COLOUR_SLOT_EMPTY, MenuSupport.COLOUR_ACCENT))
	button.add_theme_color_override("font_color",
		MenuSupport.COLOUR_ACCENT if lit else MenuSupport.COLOUR_TEXT)
