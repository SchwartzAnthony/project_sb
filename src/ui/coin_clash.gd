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
var _their_row: Container
var _my_row: Container
var _choice_row: Container
var _their_buttons: Array[Button] = []
var _my_buttons: Array[Button] = []
var _random_button: Button

## THE WHEEL LOOK (Anthony, 24 Oct 2026: "I like the wheel!"). data/ClashLook.csv.
var _wheel_on := false
var _wheel: Control          ## the painted face and its numbers; this turns
var _hub: TextureRect
var _burst: TextureRect
var _burst_words: Label
var _rings: Array[TextureRect] = []


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
	_wheel_on = ClashLook.enabled(faces)
	if _wheel_on:
		_build_wheel()
	else:
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


# =============================================================
#  THE WHEEL LOOK  (Anthony, 24 Oct 2026: "I like the wheel!")
#
#  The same game, dressed as a fairground booth. Every place and picture is
#  in data/ClashLook.csv (pieces from tools/art/clash_wheel_pieces.py). The
#  status line is built but never shown: "Remove the instructions on the
#  bottom please." What the line used to say lands on the sign instead.
# =============================================================

func _build_wheel() -> void:
	var dim := ColorRect.new()
	var shade := 0.55
	if db != null:
		shade = clampf(db.tune_float("clash_backdrop_dim", 0.55), 0.0, 1.0)
	dim.color = Color(0.03, 0.04, 0.06, shade)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var ink := ClashLook.colour("ink", Color(0.09, 0.06, 0.04))
	var cream := ClashLook.colour("cream", Color(0.96, 0.92, 0.82))

	# --- the booth: two posts, then the awning over them ---
	var post := ClashLook.picture("post")
	if post != null:
		var xs := ClashLook.pair("posts_x", Vector2(105, 1725))
		for i in 2:
			var stick := _picture_at(post, Vector2(xs.x if i == 0 else xs.y, ClashLook.number("posts_y", 110)))
			stick.flip_h = i == 1
	_picture_at(ClashLook.picture("awning"), Vector2.ZERO)

	var box := _rect("title_box", Rect2(700, 22, 520, 104))
	_title = _words_label("CALL IT", int(ClashLook.number("title_size", 72)),
		ClashLook.colour("title_colour", Color(0.8, 0.15, 0.13)), ink, 6)
	_title.position = box.position
	_title.size = box.size
	add_child(_title)

	# --- the wheel: the face and its numbers turn, the rim and flap do not ---
	var centre := ClashLook.pair("wheel_centre", Vector2(960, 510))
	var face := ClashLook.picture("wheel_face")
	var face_size := face.get_size() if face != null else Vector2(600, 600)
	_wheel = Control.new()
	_wheel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wheel.size = face_size
	_wheel.position = centre - face_size / 2.0
	_wheel.pivot_offset = face_size / 2.0
	add_child(_wheel)
	if face != null:
		var painted := TextureRect.new()
		painted.texture = face
		painted.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_wheel.add_child(painted)
	var colours := ClashLook.value("wedge_colours", "#cd2622,#fcfaf4,#2262c4,#fac41e,#3c963c").split(",")
	var reach := ClashLook.number("wheel_radius", 290.0) * ClashLook.number("number_radius", 0.72)
	for i in faces:
		var angle := -PI / 2.0 + TAU * float(i) / float(faces)
		var wedge := Color.from_string(colours[i % colours.size()].strip_edges(), Color.RED)
		var light := wedge.get_luminance() > 0.6
		var number := _words_label(str(i + 1), int(ClashLook.number("number_size", 60)),
			ink if light else cream, ink, 0 if light else 5)
		number.size = Vector2(120, 90)
		number.pivot_offset = number.size / 2.0
		number.position = face_size / 2.0 + Vector2(cos(angle), sin(angle)) * reach - number.size / 2.0
		number.rotation = angle + PI / 2.0
		_wheel.add_child(number)

	var rim := ClashLook.picture("wheel_rim")
	if rim != null:
		_picture_at(rim, centre - rim.get_size() / 2.0)
	var hub := ClashLook.picture("hub")
	_hub = _picture_at(hub, centre - (hub.get_size() if hub != null else Vector2.ZERO) / 2.0)
	_hub.pivot_offset = _hub.size / 2.0
	var flap := ClashLook.picture("pointer")
	if flap != null:
		# The flap's tip is near its bottom; it sits just inside the rim.
		_picture_at(flap, Vector2(centre.x - flap.get_size().x / 2.0,
			centre.y - ClashLook.number("wheel_radius", 290.0) - flap.get_size().y + 30.0))

	# --- the two headings and the tickets ---
	var heading := int(ClashLook.number("heading_size", 34))
	for pair in [["THEIR CALL", "their_heading", Vector2(400, 240)], ["YOUR CALL", "your_heading", Vector2(1520, 240)]]:
		var words := _words_label(pair[0], heading, cream, ink, 4)
		words.size = Vector2(400, 60)
		words.position = ClashLook.pair(pair[1], pair[2]) - words.size / 2.0
		add_child(words)

	var their_grid := _ticket_grid(ClashLook.pair("their_grid", Vector2(250, 290)))
	_their_row = their_grid
	for i in faces:
		var chip := _ticket_button("?", "ticket_theirs", cream)
		chip.disabled = true
		their_grid.add_child(chip)
		_their_buttons.append(chip)

	var my_grid := _ticket_grid(ClashLook.pair("your_grid", Vector2(1390, 290)))
	_my_row = my_grid
	var ring_picture := ClashLook.picture("ring")
	for i in faces:
		var button := _ticket_button(str(i + 1), "ticket_mine", ink)
		button.pressed.connect(_pick.bind(i + 1))
		my_grid.add_child(button)
		_my_buttons.append(button)
		var ring := TextureRect.new()
		ring.texture = ring_picture
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ring.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ring.stretch_mode = TextureRect.STRETCH_SCALE
		var ticket := ClashLook.pair("ticket_size", Vector2(130, 86))
		ring.size = ticket * Vector2(1.3, 1.36)
		ring.position = (ticket - ring.size) / 2.0
		ring.visible = false
		button.add_child(ring)
		_rings.append(ring)

	# RANDOM, under your tickets. Blank in the CSV = no button.
	var random_box := _rect("random_box", Rect2(1390, 840, 280, 70))
	_random_button = _ticket_button("RANDOM", "random", ink)
	_random_button.position = random_box.position
	_random_button.size = random_box.size
	_random_button.custom_minimum_size = random_box.size
	_random_button.add_theme_font_size_override("font_size", ClashLook.fit_size(
		_random_button.get_theme_font("font"), "RANDOM", random_box.size - Vector2(70, 26), 44))
	_random_button.tooltip_text = "Pick a number for me. The wheel still has to stop."
	_random_button.pressed.connect(func() -> void: _pick(1 + randi() % faces))
	add_child(_random_button)
	if ClashLook.value("random") == "":
		_random_button.modulate = Color(1, 1, 1, 0)
		_random_button.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# --- ATTACK / DEFEND, the same size, the word filling the ticket ---
	_choice_row = Container.new()
	_choice_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_choice_row.visible = false
	_choice_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_choice_row)
	var choice := ClashLook.pair("choice_size", Vector2(340, 110))
	for side in [["ATTACK", "attack", "attack_at", Vector2(470, 930), cream, true],
			["DEFEND", "defend", "defend_at", Vector2(1110, 930), ink, false]]:
		var button := _ticket_button(side[0], side[1], side[4])
		button.position = ClashLook.pair(side[2], side[3])
		button.size = choice
		button.custom_minimum_size = choice
		button.add_theme_font_size_override("font_size", ClashLook.fit_size(
			button.get_theme_font("font"), side[0], choice - Vector2(60, 30),
			int(ClashLook.number("choice_text_size", 72))))
		if side[4] == cream:
			button.add_theme_constant_override("outline_size", 8)
			button.add_theme_color_override("font_outline_color", ink)
		button.pressed.connect(_choose.bind(side[5]))
		_choice_row.add_child(button)

	# --- the burst for an exact call ---
	var burst_size := ClashLook.number("burst_size", 270.0)
	_burst = _picture_at(ClashLook.picture("burst"),
		ClashLook.pair("burst_centre", Vector2(960, 972)) - Vector2(burst_size, burst_size) / 2.0)
	_burst.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_burst.stretch_mode = TextureRect.STRETCH_SCALE
	_burst.size = Vector2(burst_size, burst_size)
	_burst.pivot_offset = _burst.size / 2.0
	_burst.visible = false
	_burst_words = _words_label("", 40, ClashLook.colour("burst_colour", Color(0.8, 0.15, 0.13)), ink, 3)
	_burst_words.size = _burst.size * 0.7
	_burst_words.position = (_burst.size - _burst_words.size) / 2.0
	_burst_words.pivot_offset = _burst_words.size / 2.0
	_burst_words.rotation = deg_to_rad(-6.0)
	_burst.add_child(_burst_words)

	# Built so the rest of the game keeps working, never shown.
	_status = Label.new()
	_status.visible = false
	add_child(_status)
	_coin = Label.new()
	_coin.visible = false
	add_child(_coin)


func _rect(key: String, fallback: Rect2) -> Rect2:
	var parts := ClashLook.value(key).split(",")
	if parts.size() != 4:
		return fallback
	return Rect2(float(parts[0]), float(parts[1]), float(parts[2]), float(parts[3]))


func _picture_at(texture: Texture2D, at: Vector2) -> TextureRect:
	var picture := TextureRect.new()
	picture.texture = texture
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.position = at
	if texture != null:
		picture.size = texture.get_size()
	add_child(picture)
	return picture


func _words_label(words: String, size: int, colour: Color, outline: Color, outline_size: int) -> Label:
	var label := Label.new()
	label.text = words
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	# The game's theme gives every Label a dark backing box; not on a drawing.
	label.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	if outline_size > 0:
		label.add_theme_constant_override("outline_size", outline_size)
		label.add_theme_color_override("font_outline_color", outline)
	return label


## The title, shrunk until it fits the sign.
func _set_title(words: String) -> void:
	_title.text = words
	if _wheel_on:
		_title.add_theme_font_size_override("font_size", ClashLook.fit_size(
			_title.get_theme_font("font"), words, _title.size - Vector2(30, 10),
			int(ClashLook.number("title_size", 72))))


func _ticket_grid(at: Vector2) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	var gap := ClashLook.pair("ticket_gap", Vector2(20, 22))
	grid.add_theme_constant_override("h_separation", int(gap.x))
	grid.add_theme_constant_override("v_separation", int(gap.y))
	grid.position = at
	add_child(grid)
	return grid


func _ticket_button(words: String, picture: String, colour: Color) -> Button:
	var button := Button.new()
	button.text = words
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = ClashLook.pair("ticket_size", Vector2(130, 86))
	button.add_theme_font_size_override("font_size", int(ClashLook.number("ticket_text_size", 50)))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(state, colour)
	_ticket(button, picture)
	return button


func _ticket(button: Button, picture: String) -> void:
	button.add_theme_stylebox_override("normal", ClashLook.face(picture))
	button.add_theme_stylebox_override("disabled", ClashLook.face(picture))
	button.add_theme_stylebox_override("hover", ClashLook.face(picture, Color(1.0, 0.92, 0.75)))
	button.add_theme_stylebox_override("pressed", ClashLook.face(picture, Color(0.85, 0.8, 0.7)))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


## Sends the wheel round `spin_turns` times and on to `number`, under the flap.
func _turn_wheel_to(number: int, seconds: float) -> void:
	var stop := -TAU * float(number - 1) / float(faces)
	var from := fposmod(_wheel.rotation, TAU)
	_wheel.rotation = from
	var target := from + TAU * maxf(1.0, ClashLook.number("spin_turns", 3)) + fposmod(stop - from, TAU)
	var turn := _wheel.create_tween()
	turn.tween_property(_wheel, "rotation", target, maxf(0.1, seconds)) \
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)


## The burst between ATTACK and DEFEND, its words on two lines filling it.
func _show_burst(words: String) -> void:
	var parts := words.split(" ", false)
	var best := words
	var widest := INF
	for cut in range(1, parts.size()):
		var top := " ".join(parts.slice(0, cut))
		var bottom := " ".join(parts.slice(cut))
		if maxf(top.length(), bottom.length()) < widest:
			widest = maxf(top.length(), bottom.length())
			best = top + "\n" + bottom
	_burst_words.text = best
	_burst_words.add_theme_font_size_override("font_size", ClashLook.fit_size(
		_burst_words.get_theme_font("font"), best, _burst_words.size,
		int(ClashLook.number("burst_text_size", 56))))
	_burst.visible = true
	_burst.scale = Vector2(0.3, 0.3)
	var pop := _burst.create_tween()
	pop.tween_property(_burst, "scale", Vector2(1.15, 1.15), 0.14) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(_burst, "scale", Vector2.ONE, 0.12)


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
	if _wheel_on:
		_ticket(button, "ticket_mine" if _my_buttons.has(button) else "ticket_theirs")
		return
	for style in ["normal", "disabled"]:
		button.remove_theme_stylebox_override(style)
	for colour in ["font_color", "font_disabled_color"]:
		button.remove_theme_color_override(colour)


func _mark_chip(button: Button, called: bool) -> void:
	if _wheel_on:
		var mine := _my_buttons.has(button)
		button.modulate = Color(1, 1, 1, 1)
		if called:
			_ticket(button, "ticket_mine_called" if mine else "ticket_theirs_called")
		if mine:
			var index := _my_buttons.find(button)
			if index >= 0 and index < _rings.size():
				_rings[index].visible = called
		return
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
	ScreenLook.plank(button, "match_window")
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
		_their_buttons[i].modulate = Color(1, 1, 1, 1.0 if _wheel_on else 0.45)
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
	if _wheel_on:
		for ring in _rings:
			ring.visible = false
		_burst.visible = false
		_hub.scale = Vector2.ONE
	_set_title("CALL IT")
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
	_set_title(ClashLook.value("spin_title", "THE WHEEL") if _wheel_on else "THE COIN")
	var steps := 18
	var spent := 0.0
	# WHERE IT LANDS IS SETTLED BEFORE IT TURNS, so the wheel can be sent
	# there. Nobody sees it any earlier: their call is still face down and
	# yours is already in.
	_land()
	if _wheel_on:
		_turn_wheel_to(_landed, spin_seconds * 0.96)
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

	_coin.text = str(_landed)
	var land := _coin.create_tween()
	land.tween_property(_coin, "scale", Vector2(1.35, 1.35), 0.10) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	land.tween_property(_coin, "scale", Vector2.ONE, 0.16)

	await _reveal()


func _land() -> void:
	_landed = 1 + randi() % faces
	# Anthony, 24 Oct: THE AI NEVER CALLS IT EXACTLY IN THE TUTORIAL. Their
	# number is still face down, so it quietly moves to another one that is
	# neither yours nor the coin. `coin_no_ai_exact_modes` in Tuning.csv
	# lists the MatchModes.csv rows this holds for; blank = never.
	if _theirs == _landed and _no_ai_exact_here():
		var others: Array[int] = []
		for i in faces:
			if i + 1 != _picked and i + 1 != _landed:
				others.append(i + 1)
		if not others.is_empty():
			_theirs = others[randi() % others.size()]


func _no_ai_exact_here() -> bool:
	if db == null:
		return false
	var mode := String(MatchMode.current(get_tree()).get("id", ""))
	for word in db.tune_text("coin_no_ai_exact_modes", "tutorial;intro;intro2").split(";", false):
		if word.strip_edges() == mode:
			return true
	return false


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
		_set_title(_words("coin_exact_words", "CALLED IT!"))
	elif exact_theirs:
		_set_title(_words("coin_exact_them_words", "THEY CALLED IT"))
	else:
		_set_title("YOU CALLED CLOSER" if i_won else "THEY CALLED CLOSER")

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
		# The wheel look keeps your tickets up, your call ringed (as drawn).
		_my_row.visible = _wheel_on
		_random_button.visible = false
		_choice_row.visible = true
		for child in _choice_row.get_children():
			(child as Button).disabled = _locked
		_status.text += "   Attack first, or hold and defend?"
		return

	# THEY WON, so they choose — and which way they go is a coin of its own.
	var they_attack := randf() < enemy_attack_chance
	_status.text += "   They choose to %s." % ("attack" if they_attack else "defend")
	if _wheel_on:
		_set_title("THEY ATTACK" if they_attack else "THEY DEFEND")
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
	if _wheel_on:
		_show_burst(_words("coin_exact_words", "CALLED IT!") if mine
			else _words("coin_exact_them_words", "THEY CALLED IT"))
		var pop := _hub.create_tween()
		pop.tween_property(_hub, "scale", Vector2(1.35, 1.35), 0.12) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		pop.tween_property(_hub, "scale", Vector2.ONE, 0.2)
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
