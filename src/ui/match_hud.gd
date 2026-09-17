class_name MatchHUD
extends HBoxContainer

# =============================================================
#  THE MATCH HUD — the speed buttons and the AUTO toggle
#
#  A small strip in the top-left of a match:
#
#    1x 2x 4x 8x   how fast time runs. Number keys 1-4 do the same.
#                  Hold F for a blast of 20x, let go to drop back.
#
#    AUTO          the game plays for you — it picks your cards at every
#                  PLAY MAKER and every Star swap, throws the clash and
#                  chooses attack or defend, so you can sit and watch a
#                  whole match without touching anything.
#
#  ============ A LOCKED SPEED IS SHOWN, NOT HIDDEN ============
#
#  1x is always there. 2x, 4x and 8x are shown greyed until they are
#  unlocked, and pressing one says so instead of doing nothing.
#
#  A button you cannot press yet is a thing to want; a button that is not
#  there is a feature the player never learns exists. The words are yours —
#  `game_speed_locked_words` in Tuning.csv.
#
#  ============ AUTO STARTS OFF, EVERY MATCH ============
#
#  It used to be remembered in your save, so turning it on once meant every
#  later match played itself until you noticed and turned it back off. Now
#  every match begins with you in charge, and AUTO is something you switch
#  on deliberately for the match you are in.
#
#  Set `auto_pick,true` in Tuning.csv if you genuinely want it on by default
#  — for a demo, say, or a stream. The flag `auto_pick` still exists during
#  the match, so any CSV can test it with  flag:auto_pick .
#
#  WHILE IT IS ON, YOUR CLICKS ARE LOCKED. The cards and the clash buttons
#  go dim and stop responding, because a half-second race between you and
#  the computer over the same card is how a round gets picked twice. Press
#  AUTO (or A) to take back over, and everything lights up again.
#
#  There is no art here on purpose — it is meant to be replaced. Everything
#  it does is two lines of public API that any screen you design later can
#  call instead:
#      GameSpeed.set_speed(4.0)
#      MatchHUD.set_auto_pick(state, true)
# =============================================================

const AUTO_FLAG := "auto_pick"

signal auto_pick_changed(is_on: bool)

## Somebody pressed a speed they have not unlocked. The match puts the words
## on the screen — this does not, because a HUD strip in the corner is not
## where anybody is looking.
signal speed_locked(words: String)

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

	# EVERY MATCH STARTS WITH YOU IN CHARGE. Whatever the last match left the
	# flag at is thrown away here; only Tuning.csv can start a match on AUTO,
	# and it is off unless you say otherwise.
	set_auto_pick(state, db.tune_bool("auto_pick", false))

	add_theme_constant_override("separation", 5)
	_build()

	GameSpeed.set_speed(_chosen)
	_refresh()


func _build() -> void:
	# ============ THE SPEED BUTTONS ARE A SETTING NOW ============
	#
	# 1x / 2x / 4x / 8x sitting on the HUD from the first match is a strong
	# hint that the match is something to get through rather than something
	# to watch — so whether they are there at all is a row of Tuning.csv, and
	# out of the box they are NOT.
	#
	#     game_speed_buttons        false hides them entirely
	#     game_speed_buttons_needs  a Requires condition, so they can be
	#                               UNLOCKED later instead of hidden for ever
	#
	# THE HOLD-TO-HURRY IS UNTOUCHED. Holding the mouse or the spacebar
	# through a duel still runs it fast; that is a different thing and it is
	# always on. Only these buttons answer to this switch.
	for value in _steps:
		var button := _make_button(GameSpeed.label_for(value), 46.0)
		# NORMAL SPEED IS NEVER LOCKED. Whatever the first step in
		# game_speed_steps is, it is the speed the match already runs at, so
		# locking it would be locking the game.
		var locked := GameSpeed.step_locked(value, db, state)
		button.set_meta("speed", value)
		button.set_meta("locked", locked)
		button.tooltip_text = _locked_words() if locked \
			else "Run the game at %s" % GameSpeed.label_for(value)
		button.pressed.connect(_choose.bind(value))
		add_child(button)
		_speed_buttons.append(button)

	# ============ AUTO LIVES HERE, IN THE CORNER ============
	#
	# It was tried down beside the cards for one round, on the theory that a
	# button belongs next to the thing it takes over. In practice a button
	# sitting in the middle of the pitch for ninety minutes is something you
	# look at every time the ball goes past it, and it is also already in the
	# pause menu — so there was never a moment you could not reach it.
	#
	# Back in the corner, where a control you use twice a match belongs.
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(10, 0)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(spacer)

	_auto_button = _make_button("AUTO", 66.0)
	_auto_button.tooltip_text = "Let the game play for you. Your cards and the clash buttons lock while it is on.\nPress AUTO or A to take back over."
	_auto_button.pressed.connect(_toggle_auto)
	add_child(_auto_button)


## THE RULE ITSELF IS IN GameSpeed, not here — the pause menu has a second
## set of these buttons and has to obey exactly the same thing.
func _locked_words() -> String:
	return GameSpeed.locked_words(db)


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
	# LOCKED MEANS IT SAYS SO. Not that it does nothing — a button that does
	# nothing when you press it reads as a broken game, and the player has no
	# way of learning that there is something here to earn.
	if GameSpeed.step_locked(value, db, state):
		speed_locked.emit(_locked_words())
		print("[speed] %s is locked. %s" % [GameSpeed.label_for(value), _locked_words()])
		return

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

	# THE ACTIONS, NOT THE LETTERS. `formation` and `auto` are rows in
	# Keys.csv; a player who rebinds them in Settings > Keys moves these,
	# and a controller's X and Y buttons do the same jobs.
	if InputMap.has_action("formation") and key.is_action("formation"):
		_turbo_held = key.pressed
		GameSpeed.set_speed(_turbo if _turbo_held else _chosen)
		_refresh()
		get_viewport().set_input_as_handled()
		return

	if GameKeys.pressed(key, "auto"):
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

## Repaint the AUTO button after something else changed the flag — the pause
## menu, or a CSV effect. The two AUTO buttons must never disagree.
func refresh_auto_button() -> void:
	_refresh()


func _refresh() -> void:
	for i in _speed_buttons.size():
		var button := _speed_buttons[i]
		var live := is_equal_approx(_steps[i], _chosen) and not _turbo_held
		_paint(button, live, bool(button.get_meta("locked", false)))

	if _auto_button != null:
		var on := auto_pick_on(state)
		_auto_button.text = "AUTO ON" if on else "AUTO"
		_paint(_auto_button, on)


func _paint(button: Button, lit: bool, locked: bool = false) -> void:
	# A LOCKED BUTTON IS STILL A BUTTON. It keeps its box and its label and
	# goes grey and half-faded, so it reads as "later" rather than "broken".
	# It is deliberately NOT `disabled`: a disabled button swallows the click
	# and so cannot tell you why it did nothing.
	if locked:
		button.modulate = Color(1, 1, 1, 0.45)
		button.add_theme_stylebox_override("normal", MenuSupport.panel_style(
			MenuSupport.COLOUR_PANEL, MenuSupport.COLOUR_TEXT_DIM))
		button.add_theme_stylebox_override("hover", MenuSupport.panel_style(
			MenuSupport.COLOUR_PANEL, MenuSupport.COLOUR_TEXT_DIM))
		button.add_theme_stylebox_override("pressed", MenuSupport.panel_style(
			MenuSupport.COLOUR_PANEL, MenuSupport.COLOUR_TEXT_DIM))
		return

	button.modulate = Color(1, 1, 1, 1)
	var fill := MenuSupport.COLOUR_SLOT_EMPTY if lit else MenuSupport.COLOUR_PANEL
	var edge := MenuSupport.COLOUR_ACCENT if lit else MenuSupport.COLOUR_TEXT_DIM
	button.add_theme_stylebox_override("normal", MenuSupport.panel_style(fill, edge))
	button.add_theme_stylebox_override("hover",
		MenuSupport.panel_style(MenuSupport.COLOUR_SLOT_EMPTY, MenuSupport.COLOUR_ACCENT))
	button.add_theme_stylebox_override("pressed",
		MenuSupport.panel_style(MenuSupport.COLOUR_SLOT_EMPTY, MenuSupport.COLOUR_ACCENT))
	button.add_theme_color_override("font_color",
		MenuSupport.COLOUR_ACCENT if lit else MenuSupport.COLOUR_TEXT)
