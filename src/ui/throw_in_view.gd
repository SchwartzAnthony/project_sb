class_name ThrowInView
extends CanvasLayer

# =============================================================
#  THE THROW-IN — and the choice that used to be a coin
#
#  ============ WHAT THIS REPLACES ============
#
#  A round used to open by asking you to call a number between one and ten,
#  and whoever called closer chose attack or defend. It worked, and it was a
#  fairground game bolted onto a football match — you were guessing a coin,
#  not playing football.
#
#  Now: somebody gives the ball away, the other side throws it back in, and
#  THE SIDE TAKING THE THROW CHOOSES. The choice is the same choice. What
#  changed is that you earn it by not being the one who put it out, rather
#  than by guessing a number.
#
#  ============ WHEN IT IS THEIRS ============
#
#  The window still opens, and it still says what they chose and for how
#  long — `throw_in_read_seconds`. Watching the opposition decide is
#  information; a screen that only appears when it is your turn teaches you
#  nothing about the half of the match you do not control.
#
#  ============ AUTO ============
#
#  `auto_play()` answers it, because "sit back and watch" has to mean the
#  whole match rather than the whole match except one button. It POLLS for
#  the buttons rather than sleeping for a computed time — see the comment in
#  coin_clash.gd for the match-ending hang that taught me that.
# =============================================================

signal chosen(player_attacks: bool)

var db: CardDatabase

var _yours := true
var _running := false
var _choice_row: HBoxContainer
var _title: Label
var _status: Label
var _read_seconds := 1.4
var _enemy_attack_chance := 0.5


## Put it up. `yours` is whether YOU are taking the throw; `where` is a line
## of words about it, e.g. "Bauer throws in from the left touchline".
static func open(on: Node, database: CardDatabase, yours: bool,
		where: String) -> ThrowInView:
	var made := ThrowInView.new()
	made.name = "ThrowInView"
	made.db = database
	made._yours = yours
	made.layer = 170
	on.add_child(made)
	made._begin(where)
	return made


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _begin(where: String) -> void:
	if db != null:
		_read_seconds = db.tune_float("throw_in_read_seconds", 1.4)
		_enemy_attack_chance = db.tune_float("enemy_attack_chance", 0.5)
	_build(where)
	_running = true
	if not _yours:
		_they_decide()


func _build(where: String) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(640, 0)
	frame.add_theme_stylebox_override("panel", MenuSupport.styled(
		"window", "", MenuSupport.COLOUR_PANEL, MenuSupport.COLOUR_ACCENT))
	centre.add_child(frame)

	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right"]:
		pad.add_theme_constant_override(side, 30)
	for side in ["margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 24)
	frame.add_child(pad)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	pad.add_child(column)

	_title = MenuSupport.heading(
		Loc.text("throw_in_yours", "YOUR THROW") if _yours
		else Loc.text("throw_in_theirs", "THEIR THROW"),
		34, MenuSupport.COLOUR_ACCENT)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_title)

	var line := Label.new()
	line.text = where
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.add_theme_font_size_override("font_size", 17)
	line.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	column.add_child(line)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 16)
	column.add_child(_status)

	_choice_row = HBoxContainer.new()
	_choice_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_choice_row.add_theme_constant_override("separation", 16)
	_choice_row.visible = false
	column.add_child(_choice_row)

	if _yours:
		# ============ THE TWO COLOURS DO THE EXPLAINING ============
		#
		# Warm for attack, cool for defend — the same two the strip above the
		# card row uses and the same two the team sheet tags abilities with.
		# By the time a player reaches this screen they have been taught what
		# those colours mean three times.
		_choice_row.add_child(_make_button(
			Loc.text("choose_attack", "ATTACK"),
			Loc.text("choose_attack_why", "you take them on — your attack against their defence"),
			MenuSupport.COLOUR_ATTACK, true))
		_choice_row.add_child(_make_button(
			Loc.text("choose_defend", "DEFEND"),
			Loc.text("choose_defend_why", "you hold — their attack against your defence"),
			MenuSupport.COLOUR_DEFEND, false))
		_choice_row.visible = true
		_status.text = Loc.text("throw_in_ask", "Attack first, or hold and defend?")
		_status.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT)


func _make_button(words: String, why: String, tint: Color, attack: bool) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(260, 92)
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_stylebox_override("normal",
		MenuSupport.styled("button", "", MenuSupport.COLOUR_PANEL, tint))
	button.add_theme_stylebox_override("hover",
		MenuSupport.styled("button", "hover", MenuSupport.COLOUR_SLOT_EMPTY, tint))
	button.add_theme_stylebox_override("pressed",
		MenuSupport.styled("button", "pressed", MenuSupport.COLOUR_SLOT_EMPTY, tint))
	button.add_theme_stylebox_override("focus", MenuSupport.focus_style())
	button.pressed.connect(_choose.bind(attack))

	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 2)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	button.add_child(column)

	var big := MenuSupport.heading(words, 26, tint)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(big)

	var small := Label.new()
	small.text = why
	small.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	small.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	small.add_theme_font_size_override("font_size", 12)
	small.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	small.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(small)
	return button


# =============================================================
#  DECIDING
# =============================================================

func _choose(attack: bool) -> void:
	if not _running:
		return
	_finish(attack)


## Their throw. They decide, it is shown for a beat, and the round begins.
func _they_decide() -> void:
	var they_attack := randf() < _enemy_attack_chance
	_status.text = Loc.text("they_attack", "They come forward.") if they_attack \
		else Loc.text("they_defend", "They sit back and hold.")
	_status.add_theme_color_override("font_color",
		MenuSupport.COLOUR_ATTACK if they_attack else MenuSupport.COLOUR_DEFEND)
	await get_tree().create_timer(maxf(0.2, _read_seconds), true, false, true).timeout
	# THE SIGNAL SAYS WHAT YOUR SIDE DOES. If they attack, you defend.
	_finish(not they_attack)


func awaiting_choice() -> bool:
	return _running and _choice_row != null and _choice_row.visible


## AUTO answers it. Polls rather than guessing when the buttons will be
## there — see coin_clash.gd for the hang that taught that lesson.
func auto_play(pause: float, attack_chance: float) -> void:
	await get_tree().create_timer(maxf(0.05, pause), true, false, true).timeout
	for i in 600:
		if not _running:
			return
		if awaiting_choice():
			_choose(randf() < attack_chance)
			return
		await get_tree().create_timer(0.05, true, false, true).timeout


func _unhandled_key_input(event: InputEvent) -> void:
	if not awaiting_choice():
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	# A and D, because they are the two words. Left and right work as well
	# through the ordinary focus handling.
	if key.keycode == KEY_A:
		get_viewport().set_input_as_handled()
		_choose(true)
	elif key.keycode == KEY_D:
		get_viewport().set_input_as_handled()
		_choose(false)


func _finish(player_attacks: bool) -> void:
	if not _running:
		return
	_running = false
	chosen.emit(player_attacks)
	queue_free()
