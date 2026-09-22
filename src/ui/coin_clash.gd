class_name CoinClash
extends CanvasLayer

# =============================================================
#  THE COIN — who attacks first in the Tier I duel
#
#  ============ WHAT REPLACED WHAT ============
#
#  This was rock, paper, scissors. Three buttons, and the only thing you
#  could bring to it was a guess about what the opposition would throw —
#  which, against a computer picking at random, is nothing at all.
#
#  It is a NUMBER GUESS now. Both sides pick a number from one to ten, a coin
#  spins up and lands on one, and whoever guessed closer chooses whether to
#  attack or defend. Still luck, but ten doors instead of three, and a coin
#  you actually watch land.
#
#  ============ THE SHAPE OF IT ============
#
#      1  2  3  4  5  6  7  8  9  10     <- THEM, face down until the reveal
#
#                 ( 7 )                  <- the coin, spinning
#
#      1  2  3  4  5  6  7  8  9  10     <- YOU. Ten buttons, plus RANDOM
#
#  ============ WHY A TIE IS IMPOSSIBLE ============
#
#  Their number is drawn from the nine you did NOT pick. So the two guesses
#  can never be the same distance from the coin by being the same number, and
#  there is never a rule to explain about what happens on a draw. Your choice
#  genuinely narrows theirs, which is a small thing but it is more than rock
#  paper scissors ever gave you.
#
#  An equal distance is still possible — you pick 4, they get 6, the coin
#  lands on 5. That goes to YOU. The tie-break favours the player on purpose;
#  losing a coin flip you drew level on is the least satisfying way to lose
#  anything.
#
#  ============ WHAT IT IS ASKED FOR ============
#
#  The same five things rock/paper/scissors was asked for, so main_scene.gd
#  did not have to learn anything new:
#
#      start()            put it up and wait for a pick
#      set_locked(bool)   AUTO is playing; take the buttons away
#      auto_play(...)     AUTO plays it, both halves
#      is_running()       is it up?
#      clash_finished     emitted with true when YOUR side attacks
#
#  ============ TUNING ============
#
#      use_rps_minigame       false = a silent coin flip, no screen at all
#      enemy_attack_chance    their odds of choosing ATTACK when they win
#      coin_spin_seconds      how long the coin turns before it lands
#      rps_reveal_seconds     the pause on the reveal
#      rps_result_seconds     the pause on the decision
#      coin_faces             how many numbers. 10 out of the box
# =============================================================

signal clash_finished(player_attacks: bool)

var db: CardDatabase

## Read by main_scene.gd out of Tuning.csv — see _tune_rps() there.
var enemy_attack_chance: float = 0.5
var reveal_seconds: float = 0.9
var result_seconds: float = 1.0
var spin_seconds: float = 1.4
var faces: int = 10

var _running := false
var _locked := false
var _picked := -1
var _theirs := -1
var _landed := -1

var _title: Label
var _status: Label
var _coin: Label
var _their_row: HBoxContainer
var _my_row: HBoxContainer
var _choice_row: HBoxContainer
var _their_buttons: Array[Button] = []
var _my_buttons: Array[Button] = []
var _random_button: Button


static func make(database: CardDatabase) -> CoinClash:
	var made := CoinClash.new()
	made.name = "CoinClash"
	made.db = database
	return made


func _ready() -> void:
	layer = 60
	if db != null:
		faces = maxi(2, db.tune_int("coin_faces", 10))
		spin_seconds = db.tune_float("coin_spin_seconds", 1.4)
	_build()
	hide()


# =============================================================
#  BUILDING IT
# =============================================================

func _build() -> void:
	# ============ HOW DARK THE BACKDROP IS ============
	#
	# Only what is BEHIND the window. The panel is a sibling drawn after it,
	# so nothing inside the clash is dimmed by this — what used to make the
	# whole screen look dark was the chips themselves fading almost out (see
	# _mark_chip), not this rectangle. It is still a little lighter than it
	# was, because the pitch behind is worth seeing.
	var dim := ColorRect.new()
	var shade := 0.55
	if db != null:
		shade = clampf(db.tune_float("clash_backdrop_dim", 0.55), 0.0, 1.0)
	dim.color = Color(0.03, 0.04, 0.06, shade)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var middle := CenterContainer.new()
	middle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(middle)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", MenuSupport.panel_style(
		Color(0.07, 0.08, 0.11, 0.98), MenuSupport.COLOUR_ACCENT))
	middle.add_child(panel)

	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right"]:
		pad.add_theme_constant_override(side, 26)
	for side in ["margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 20)
	panel.add_child(pad)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	pad.add_child(column)

	_title = MenuSupport.heading("CALL IT", 26, MenuSupport.COLOUR_ACCENT)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_title)

	# --- THEM, face down ---
	var their_word := Label.new()
	their_word.text = "THEIR CALL"
	their_word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	their_word.add_theme_font_size_override("font_size", 12)
	their_word.add_theme_color_override("font_color", Color(0.86, 0.48, 0.42))
	column.add_child(their_word)

	_their_row = _number_row(column)
	for i in faces:
		var chip := _number_chip(i + 1, false)
		_their_row.add_child(chip)
		_their_buttons.append(chip)

	# --- the coin ---
	_coin = Label.new()
	_coin.text = "?"
	_coin.custom_minimum_size = Vector2(96, 96)
	_coin.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_coin.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_coin.add_theme_font_size_override("font_size", 46)
	_coin.add_theme_color_override("font_color", MenuSupport.COLOUR_ACCENT)
	_coin.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(_coin)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(520, 0)
	_status.add_theme_font_size_override("font_size", 14)
	_status.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	column.add_child(_status)

	# --- YOU ---
	var my_word := Label.new()
	my_word.text = "YOUR CALL"
	my_word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	my_word.add_theme_font_size_override("font_size", 12)
	my_word.add_theme_color_override("font_color", MenuSupport.COLOUR_ACCENT)
	column.add_child(my_word)

	_my_row = _number_row(column)
	for i in faces:
		var button := _number_chip(i + 1, true)
		button.pressed.connect(_pick.bind(i + 1))
		_my_row.add_child(button)
		_my_buttons.append(button)

	# THE RANDOM BUTTON. Ten numbers is a decision the first three times and
	# a chore the thirtieth, so there is a button that decides for you and
	# still lets you watch the coin.
	var extras := HBoxContainer.new()
	extras.alignment = BoxContainer.ALIGNMENT_CENTER
	extras.add_theme_constant_override("separation", 10)
	column.add_child(extras)

	_random_button = Button.new()
	_random_button.text = "RANDOM"
	_random_button.custom_minimum_size = Vector2(130, 36)
	_random_button.focus_mode = Control.FOCUS_NONE
	_random_button.tooltip_text = "Pick a number for me. The coin still has to land."
	_random_button.pressed.connect(func() -> void: _pick(1 + randi() % faces))
	extras.add_child(_random_button)

	# --- attack or defend, shown only once you have won ---
	_choice_row = HBoxContainer.new()
	_choice_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_choice_row.add_theme_constant_override("separation", 12)
	_choice_row.visible = false
	column.add_child(_choice_row)

	var attack := _big_button("ATTACK")
	attack.pressed.connect(_choose.bind(true))
	_choice_row.add_child(attack)
	var defend := _big_button("DEFEND")
	defend.pressed.connect(_choose.bind(false))
	_choice_row.add_child(defend)


func _number_row(into: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	into.add_child(row)
	return row


func _number_chip(number: int, mine: bool) -> Button:
	var button := Button.new()
	button.text = str(number)
	button.custom_minimum_size = Vector2(46, 44)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 18)
	if not mine:
		# THEIRS ARE FACE DOWN. They are drawn as buttons so the two rows line
		# up exactly, but they are dead and dim until the reveal.
		button.disabled = true
		button.text = "?"
	return button


## ============ MARKING THE ONE THAT WAS CALLED ============
##
## The chosen chip is marked by COLOUR, not by fading everything else almost
## out. Nine numbers at 30% alpha is nine numbers you cannot read, and with
## two rows of them it made the whole window look as though the game had
## dimmed itself — which is exactly what it looked like, because it had.
##
## The others stay legible. They are still part of the answer: "you said 7,
## they said 3, it came up 2" only makes sense if you can see the row.
## Back to an unmarked chip. A clash that opens with last round's number
## still ringed in gold has answered the question before it is asked.
func _plain_chip(button: Button) -> void:
	for style in ["normal", "disabled"]:
		button.remove_theme_stylebox_override(style)
	for colour in ["font_color", "font_disabled_color"]:
		button.remove_theme_color_override(colour)


func _mark_chip(button: Button, called: bool) -> void:
	button.modulate = Color(1, 1, 1, 1.0 if called else 0.72)
	if called:
		button.add_theme_stylebox_override("normal", MenuSupport.panel_style(
			MenuSupport.COLOUR_SLOT_EMPTY, MenuSupport.COLOUR_ACCENT))
		button.add_theme_stylebox_override("disabled", MenuSupport.panel_style(
			MenuSupport.COLOUR_SLOT_EMPTY, MenuSupport.COLOUR_ACCENT))
		button.add_theme_color_override("font_color", MenuSupport.COLOUR_ACCENT)
		button.add_theme_color_override("font_disabled_color", MenuSupport.COLOUR_ACCENT)
	else:
		button.add_theme_color_override("font_disabled_color",
			MenuSupport.COLOUR_TEXT_DIM)


func _big_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(150, 44)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 17)
	return button


# =============================================================
#  PLAYING IT
# =============================================================

func start() -> void:
	_running = true
	_picked = -1
	_landed = -1
	# THEIR NUMBER IS DRAWN FROM THE NINE YOU DID NOT PICK — but you have not
	# picked yet, so it is settled the moment you do. See _pick().
	_theirs = -1

	for i in _their_buttons.size():
		_their_buttons[i].text = "?"
		_their_buttons[i].disabled = true
		_their_buttons[i].modulate = Color(1, 1, 1, 0.45)
		_plain_chip(_their_buttons[i])
	for button in _my_buttons:
		button.disabled = _locked
		button.modulate = Color(1, 1, 1, 1)
		_plain_chip(button)
	_random_button.disabled = _locked
	_random_button.visible = true
	_my_row.visible = true
	_choice_row.visible = false
	_coin.text = "?"
	_coin.rotation = 0.0
	# BACK TO A PLAIN COIN. An exact call leaves it gold and mid-swell, and a
	# clash that opens gold has given the answer away before it is asked.
	_coin.scale = Vector2.ONE
	_coin.add_theme_color_override("font_color", MenuSupport.COLOUR_ACCENT)
	_title.text = "CALL IT"
	_status.text = "Pick a number. The coin lands on one of the %d — whoever called closer chooses to attack or defend." % faces
	show()


func is_running() -> bool:
	return _running


## AUTO is playing. The buttons go dead but the screen stays up, so you can
## still watch what it chose.
func set_locked(is_locked: bool) -> void:
	_locked = is_locked
	for button in _my_buttons:
		button.disabled = is_locked or _picked > 0
	if _random_button != null:
		_random_button.disabled = is_locked or _picked > 0
	for child in _choice_row.get_children():
		(child as Button).disabled = is_locked


## AUTO plays the whole thing — the call AND the attack/defend choice — so
## "sit back and watch" means the whole match rather than the whole match
## except the two buttons in the middle of it.
func auto_play(pause: float, attack_chance: float) -> void:
	await get_tree().create_timer(maxf(0.05, pause)).timeout
	if not _running:
		return
	if _picked <= 0:
		_pick(1 + randi() % faces)

	# ============ WAIT FOR THE BUTTONS. DO NOT GUESS WHEN ============
	#
	# THIS WAS A MATCH-ENDING HANG and it is worth the paragraph.
	#
	# It used to sleep for `pause + spin_seconds + reveal_seconds` and then
	# press whatever happened to be on screen. That arithmetic was a copy of
	# the landing sequence's timing — and the landing sequence grew a beat
	# that this copy never heard about: calling the coin EXACTLY holds for
	# `coin_exact_seconds` first.
	#
	# So on roughly one clash in ten, AUTO woke up nine tenths of a second
	# early, found no buttons, and went home. The choice row then appeared
	# with nobody left to press it, and the match sat there for ever.
	#
	# Two things worth taking from it. First: a duplicated timing is a bug
	# waiting for somebody to add a beat, and somebody always does. Polling
	# for the thing itself cannot drift out of step with a sequence it does
	# not model. Second: `tools/match_soak.gd` caught this on its first run,
	# which is the entire argument for having written it.
	#
	# It gives up after thirty seconds rather than looping for ever, because
	# a tool that hangs is no better than the bug it was looking for.
	for i in 600:
		await get_tree().create_timer(0.05).timeout
		if not _running:
			return          # they won the call and it finished itself
		if _choice_row.visible:
			_choose(randf() < attack_chance)
			return


## Used by the keyboard and controller handling in main_scene.gd.
func awaiting_throw() -> bool:
	return _running and _picked <= 0


func awaiting_choice() -> bool:
	return _running and _choice_row.visible


# =============================================================
#  THE FLIP
# =============================================================

func _pick(number: int) -> void:
	if not _running or _picked > 0:
		return
	_picked = clampi(number, 1, faces)

	# THEIR CALL IS DRAWN FROM THE NINE YOU DID NOT PICK, so the two can
	# never be the same number and there is no draw to explain.
	var pool: Array[int] = []
	for i in faces:
		if i + 1 != _picked:
			pool.append(i + 1)
	_theirs = pool[randi() % pool.size()] if not pool.is_empty() else _picked

	for i in _my_buttons.size():
		_my_buttons[i].disabled = true
		_mark_chip(_my_buttons[i], i + 1 == _picked)
	_random_button.disabled = true
	_status.text = "You called %d." % _picked
	await _spin()


## The coin turns, showing a different face each step, slowing as it goes.
func _spin() -> void:
	_title.text = "THE COIN"
	var steps := 18
	var spent := 0.0
	for i in steps:
		if not _running:
			return
		_coin.text = str(1 + randi() % faces)
		# Slowing down: each step is a little longer than the last.
		var step := spin_seconds * (0.3 + 1.4 * float(i) / float(steps)) / float(steps)
		spent += step
		var tick := _coin.create_tween()
		tick.tween_property(_coin, "scale", Vector2(1.12, 0.88), step * 0.5)
		tick.tween_property(_coin, "scale", Vector2.ONE, step * 0.5)
		await get_tree().create_timer(step).timeout

	_landed = 1 + randi() % faces
	_coin.text = str(_landed)
	var land := _coin.create_tween()
	land.tween_property(_coin, "scale", Vector2(1.35, 1.35), 0.10) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	land.tween_property(_coin, "scale", Vector2.ONE, 0.16)

	await _reveal()


func _reveal() -> void:
	# THEIR CALL TURNS OVER. Only theirs is revealed; yours has been on the
	# screen since you pressed it.
	for i in _their_buttons.size():
		var button := _their_buttons[i]
		button.text = str(i + 1)
		_mark_chip(button, i + 1 == _theirs)

	var mine_off := absi(_picked - _landed)
	var theirs_off := absi(_theirs - _landed)
	# AN EQUAL DISTANCE GOES TO YOU. Losing a coin flip you drew level on is
	# the least satisfying way to lose anything.
	var i_won := mine_off <= theirs_off

	# ============ CALLING IT EXACTLY ============
	#
	# There are two ways to win the call and they are not the same thing.
	# Being nearer is arithmetic. Naming the number is the moment worth
	# leaning on, and it deserves to look different from the other one —
	# otherwise the best thing that can happen in the clash goes past
	# unnoticed, in a line of small grey text, at the same speed as everything
	# else.
	#
	#     coin_exact_words      what it says. Yours to rewrite
	#     coin_exact_seconds    how long the extra celebration is held for
	#
	# `coin_exact` is also a JUICE MOMENT, so a row in Juice.csv hangs a
	# sound, a shake and a flash on it with no code — see the manual.
	var exact_mine := mine_off == 0
	var exact_theirs := theirs_off == 0

	if exact_mine:
		_title.text = _words("coin_exact_words", "CALLED IT!")
	elif exact_theirs:
		_title.text = _words("coin_exact_them_words", "THEY CALLED IT")
	else:
		_title.text = "YOU CALLED CLOSER" if i_won else "THEY CALLED CLOSER"

	_status.text = "The coin came up %d. You said %d (%d away), they said %d (%d away)." % [
		_landed, _picked, mine_off, _theirs, theirs_off]

	if exact_mine or exact_theirs:
		_celebrate(exact_mine)
		await get_tree().create_timer(
			maxf(0.05, _number("coin_exact_seconds", 0.9))).timeout
		if not _running:
			return

	await get_tree().create_timer(maxf(0.05, reveal_seconds)).timeout
	if not _running:
		return

	if i_won:
		_my_row.visible = false
		_random_button.visible = false
		_choice_row.visible = true
		for child in _choice_row.get_children():
			(child as Button).disabled = _locked
		_status.text += "   Attack first, or hold and defend?"
		return

	# THEY WON, so they choose — and which way they go is a coin of its own.
	var they_attack := randf() < enemy_attack_chance
	_status.text += "   They choose to %s." % ("attack" if they_attack else "defend")
	await get_tree().create_timer(maxf(0.05, result_seconds)).timeout
	# If they attack, we defend. The signal says what YOUR side does.
	_finish(not they_attack)


## ============ THE EXACT-CALL CELEBRATION ============
##
## The coin swells and turns gold, and the chip that named it pulses beside
## it. Two objects moving and nothing else, so it reads in the half second it
## is on the screen.
##
## Drawn here rather than in Juice.csv because it happens on a screen of its
## own with no pitch behind it — there is nothing for a screen shake to shake.
## The Juice row is fired as well, and that is where the SOUND belongs.
func _celebrate(mine: bool) -> void:
	var gold := Color(1.0, 0.84, 0.35)
	_coin.add_theme_color_override("font_color", gold if mine
		else Color(0.92, 0.55, 0.45))

	var swell := _coin.create_tween()
	swell.tween_property(_coin, "scale", Vector2(1.9, 1.9), 0.14) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	swell.tween_property(_coin, "scale", Vector2(1.25, 1.25), 0.20)
	swell.tween_property(_coin, "scale", Vector2(1.55, 1.55), 0.16)
	swell.tween_property(_coin, "scale", Vector2.ONE, 0.22)

	# The chip that named it, pulsing. Theirs when it was their call.
	var row := _my_buttons if mine else _their_buttons
	var index := (_picked if mine else _theirs) - 1
	if index >= 0 and index < row.size():
		var chip := row[index]
		chip.modulate = Color(1, 1, 1, 1)
		var beat := chip.create_tween()
		beat.set_loops(3)
		beat.tween_property(chip, "modulate", gold, 0.12)
		beat.tween_property(chip, "modulate", Color(1, 1, 1, 1), 0.12)

	# A SOUND AND A SHAKE WITHOUT CODE. Write a `coin_exact` row in Juice.csv
	# and it plays here; write none and nothing happens, which is the same
	# rule as every other moment.
	Juice.fire(self, "coin_exact", {"who": "player" if mine else "enemy"})
	print("[clash] Called it exactly — %s." % ("you" if mine else "they"))


## A line of words out of Tuning.csv, so the wording is yours.
func _words(key: String, fallback: String) -> String:
	return db.tune_text(key, fallback) if db != null else fallback


func _number(key: String, fallback: float) -> float:
	return db.tune_float(key, fallback) if db != null else fallback


func _choose(attack: bool) -> void:
	if not _running or not _choice_row.visible:
		return
	_choice_row.visible = false
	_status.text = "You %s." % ("attack" if attack else "defend")
	await get_tree().create_timer(maxf(0.05, result_seconds)).timeout
	_finish(attack)


func _finish(player_attacks: bool) -> void:
	if not _running:
		return
	_running = false
	hide()
	clash_finished.emit(player_attacks)
