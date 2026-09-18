class_name DuelArena
extends CanvasLayer

# =============================================================
#  THE DUEL CUT-AWAY  (Advance Wars style)
#
#  Opens when a tier's attacker receives the ball. LEFT panel is always
#  YOUR side, RIGHT panel is always the enemy — whichever of them is
#  attacking. Both units run at each other, then:
#
#     1. both power numbers appear
#     2. the LOWER number has priority and lights up first
#     3. that unit's ability plate lights and its `ability` animation plays
#     4. then the other unit's number and ability
#     5. the two numbers flash and settle on their final values
#     6. WIN / LOSE stamps, panels close
#
#  Priority ties go to the ATTACKER, same as the rules.
#
#  PACING is entirely from Tuning.csv (`arena_*` rows). Holding SPACE, or
#  clicking, fast-forwards the current duel; nothing is skipped silently,
#  it just runs at `arena_skip_speed`.
#
#  ART: every animation is a row of Animations.csv. This scene asks for
#  `run`, `ability`, `win` and `lose`, falling back to `idle` and then to
#  a still frame, so it works even before you have drawn them.
# =============================================================

signal duel_finished

const VBOX_LEFT := "Dim/Panels/LeftPanel/Margin/VBox"
const VBOX_RIGHT := "Dim/Panels/RightPanel/Margin/VBox"

const DIM_TEXT := Color(0.55, 0.56, 0.62)
const LIVE_TEXT := Color(1.0, 0.95, 0.72)
const WIN_TEXT := Color(0.55, 0.95, 0.55)
const LOSE_TEXT := Color(0.95, 0.45, 0.42)

var db: CardDatabase

## Pacing, all overridden from Tuning.csv.
var speed: float = 1.0
var skip_speed: float = 6.0
var run_in_seconds: float = 0.9
var reveal_seconds: float = 0.5
var ability_seconds: float = 0.9
var compare_seconds: float = 0.8
var result_seconds: float = 1.0

var _running := false
var _skipping := false

var _dim: ColorRect
var _tier_label: Label
var _hint: Label
var _side := {}          # "left"/"right" -> Dictionary of nodes
var _anim := {}          # "left"/"right" -> SpriteAnimator
var _cards := {}         # "left"/"right" -> PlayerData currently on show


func _ready() -> void:
	# NOT MenuEscape here. This screen has its own use for the pause key
	# — it closes the conversation / the cut-away — and MenuEscape would
	# take that key away and offer to quit the game instead. So it takes
	# only the two pieces it does want.
	ControllerFocus.install(self)
	Loc.install()
	_wire()
	if _dim:
		_dim.visible = false


func _wire() -> void:
	if _dim != null:
		return
	_dim = get_node_or_null("Dim") as ColorRect
	if _dim == null:
		push_error("duel_arena.tscn is missing its Dim node.")
		return

	# THIS IS WHY CLICKING DID NOTHING. Dim is a ColorRect covering the whole
	# screen, and a Control swallows the mouse by default — so the click never
	# reached _input() below, and only the keyboard worked. Telling it to
	# ignore the mouse lets clicks through to us.
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tier_label = get_node_or_null("Dim/TierLabel") as Label
	_hint = get_node_or_null("Dim/Hint") as Label

	for key in ["left", "right"]:
		var base: String = VBOX_LEFT if key == "left" else VBOX_RIGHT
		_side[key] = {
			"role": get_node_or_null(base + "/RoleLabel") as Label,
			"stage": get_node_or_null(base + "/Stage") as Control,
			"name": get_node_or_null(base + "/NameLabel") as Label,
			"power": get_node_or_null(base + "/PowerLabel") as Label,
			"ability": get_node_or_null(base + "/AbilityLabel") as Label,
			"result": get_node_or_null(base + "/ResultLabel") as Label,
		}
		var animator := SpriteAnimator.new()
		animator.name = "Animator"
		_anim[key] = animator
		var stage: Control = _side[key]["stage"]
		if stage != null:
			stage.add_child(animator)


func apply_tuning(database: CardDatabase) -> void:
	db = database
	speed = db.tune_float("arena_speed", speed)
	skip_speed = db.tune_float("arena_skip_speed", skip_speed)
	run_in_seconds = db.tune_float("arena_run_in_seconds", run_in_seconds)
	reveal_seconds = db.tune_float("arena_reveal_seconds", reveal_seconds)
	ability_seconds = db.tune_float("arena_ability_seconds", ability_seconds)
	compare_seconds = db.tune_float("arena_compare_seconds", compare_seconds)
	result_seconds = db.tune_float("arena_result_seconds", result_seconds)


func is_running() -> bool:
	return _running


## Fast-forward the duel in progress (also what the skip key does).
func skip() -> void:
	_skipping = true


# =============================================================
#  THE SEQUENCE
#
#  `info` keys, all supplied by main_scene:
#    tier            "I".."IV"
#    left / right    Dictionaries: card, is_attacker, priority,
#                    power_before, power_after, ability (AbilityData|null),
#                    wins (bool)
# =============================================================

func play_duel(info: Dictionary) -> void:
	_wire()
	if _dim == null:
		duel_finished.emit()
		return

	_running = true
	_skipping = false
	_dim.visible = true
	if _tier_label:
		_tier_label.text = "TIER %s" % String(info.get("tier", ""))

	var left: Dictionary = info.get("left", {})
	var right: Dictionary = info.get("right", {})

	_dress("left", left)
	_dress("right", right)

	# --- 0. THE FLIP ---
	#
	# The two cards arrive FACE DOWN and turn over together. It is the moment
	# the duel actually begins — before it, neither side knows what the other
	# has — and it is a hook: anything in Abilities.csv written against the
	# `flip` trigger goes off as the cards land.
	#
	# `duel_flip` in Tuning.csv turns the animation off and the window is
	# simply there, which is how it was.
	await _flip_them_over(String(info.get("tier", "")))

	# --- 1. Both run at each other ---
	await _beat(run_in_seconds)

	# --- 2. Numbers appear ---
	_set_power(_side["left"], int(left.get("power_before", 0)), DIM_TEXT)
	_set_power(_side["right"], int(right.get("power_before", 0)), DIM_TEXT)
	await _beat(reveal_seconds)

	# --- 3. Abilities, lower priority first, attacker breaking the tie ---
	for key in _priority_order(left, right):
		var data: Dictionary = left if key == "left" else right
		await _fire_ability(key, data)

	# --- 4. Final numbers ---
	_set_power(_side["left"], int(left.get("power_after", 0)), LIVE_TEXT)
	_set_power(_side["right"], int(right.get("power_after", 0)), LIVE_TEXT)
	await _beat(compare_seconds)

	# --- 5. Result ---
	_stamp("left", bool(left.get("wins", false)))
	_stamp("right", bool(right.get("wins", false)))
	await _beat(result_seconds)

	_dim.visible = false
	_running = false
	duel_finished.emit()


## Lower ability priority resolves first; the attacker wins a tie.
func _priority_order(left: Dictionary, right: Dictionary) -> Array:
	var lp := int(left.get("priority", 0))
	var rp := int(right.get("priority", 0))
	if lp < rp:
		return ["left", "right"]
	if rp < lp:
		return ["right", "left"]
	return ["left", "right"] if bool(left.get("is_attacker", false)) else ["right", "left"]


func _fire_ability(key: String, data: Dictionary) -> void:
	var nodes: Dictionary = _side[key]

	# The number lights first — that is what "having priority" looks like.
	var power_label: Label = nodes["power"]
	if power_label:
		power_label.add_theme_color_override("font_color", LIVE_TEXT)
	await _beat(reveal_seconds * 0.6)

	var ability = data.get("ability")
	var ability_label: Label = nodes["ability"]
	if ability == null:
		if ability_label:
			ability_label.text = "no ability"
			ability_label.add_theme_color_override("font_color", DIM_TEXT)
		await _beat(reveal_seconds * 0.5)
		return

	if ability_label:
		ability_label.text = _ability_text(ability)
		ability_label.add_theme_color_override("font_color", LIVE_TEXT)

	_play_anim(key, data.get("card"), "ability")
	await _beat(ability_seconds)


func _ability_text(ability) -> String:
	var title: String = ability.display_name if ability.display_name != "" else ability.id
	return "%s\n%s %+d (%s)" % [title, ability.effect, ability.value, ability.scope]


# =============================================================
#  THE FLIP — the WHOLE WINDOW turns over
#
#  A duel arrives face down. What you see is the back of one card: the tier
#  it is, and the two crests. Then the whole window turns over — both panels,
#  both players, everything — and the duel is underneath.
#
#  It is one card, not two. Flipping the two sides separately said that one
#  of them was revealed before the other, which is not what happens: both
#  cards are turned at once and then compared.
#
#  HOW A CARD TURNS. Scale on x to zero and out again. At the moment it has
#  no width, the back is swapped for the front — that one frame is the whole
#  trick, and it is why this reads as a card rather than as a picture fading.
#
#      duel_flip           false and the window is simply there, as before
#      duel_flip_seconds   the whole turn, both halves together
# =============================================================

## The two crests, for the back of the card. main_scene hands these over when
## it builds the arena; blank draws a lettered disc instead.
var left_crest := ""
var right_crest := ""
var left_team := ""
var right_team := ""

var _panels: Control
var _back: Control
var _back_tier: Label
var _back_left: Control
var _back_right: Control


func _flip_them_over(tier: String) -> void:
	if _panels == null:
		_panels = get_node_or_null("Dim/Panels") as Control
	if _panels == null:
		return

	if db != null and not db.tune_bool("duel_flip", true):
		_panels.visible = true
		if _back != null:
			_back.visible = false
		return

	var seconds := 0.42
	if db != null:
		seconds = maxf(0.05, db.tune_float("duel_flip_seconds", 0.42))

	_build_back()
	_back_tier.text = "TIER %s" % tier
	# The back sits exactly where the window does, so the turn happens on the
	# spot rather than somewhere near it.
	_back.position = _panels.position
	_back.size = _panels.size
	_back.pivot_offset = _back.size * 0.5
	_panels.pivot_offset = _panels.size * 0.5

	# THE TITLE OVER THE WINDOW GOES AWAY while the back is up, because the
	# back already says which tier this is, in larger letters, and the same
	# three words twice on one screen reads as a mistake.
	if _tier_label != null:
		_tier_label.visible = false

	_back.visible = true
	_back.scale = Vector2.ONE
	_panels.visible = false

	# HELD FOR A MOMENT BEFORE IT TURNS. A card back that is gone before you
	# have read it may as well not be there.
	var hold := 0.5
	if db != null:
		hold = maxf(0.0, db.tune_float("duel_back_seconds", 0.5))
	if hold > 0.0:
		await _beat(hold)
		if not _running:
			_back.visible = false
			_panels.visible = true
			_panels.scale = Vector2.ONE
			if _tier_label != null:
				_tier_label.visible = true
			return

	var turn := create_tween()
	turn.tween_property(_back, "scale:x", 0.0, seconds * 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await turn.finished
	if not _running:
		_back.visible = false
		_panels.visible = true
		_panels.scale = Vector2.ONE
		if _tier_label != null:
			_tier_label.visible = true
		return

	# THE MOMENT IT HAS NO WIDTH. Swap what the card is showing.
	_back.visible = false
	_panels.visible = true
	_panels.scale = Vector2(0.0, 1.0)
	if _tier_label != null:
		_tier_label.visible = true

	var back_again := create_tween()
	back_again.tween_property(_panels, "scale:x", 1.0, seconds * 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await back_again.finished
	_panels.scale = Vector2.ONE


## The back of the card: the tier, big, with a crest either side of it.
## Built once and then re-used, because a duel happens four times a round.
func _build_back() -> void:
	if _back != null and is_instance_valid(_back):
		_paint_crest(_back_left, left_crest, left_team)
		_paint_crest(_back_right, right_crest, right_team)
		return

	_back = PanelContainer.new()
	_back.name = "CardBack"
	_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back.add_theme_stylebox_override("panel", MenuSupport.panel_style(
		Color(0.09, 0.10, 0.14, 1.0), MenuSupport.COLOUR_ACCENT))
	var dim := get_node_or_null("Dim")
	if dim != null:
		dim.add_child(_back)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 56)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back.add_child(row)

	_back_left = _crest_slot()
	row.add_child(_back_left)

	_back_tier = MenuSupport.heading("TIER", 76, MenuSupport.COLOUR_ACCENT)
	_back_tier.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_back_tier.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_back_tier)

	_back_right = _crest_slot()
	row.add_child(_back_right)

	_paint_crest(_back_left, left_crest, left_team)
	_paint_crest(_back_right, right_crest, right_team)


## A crest with the club's name under it. The window it sits in is the whole
## duel window, so a small crest in the middle of it reads as an accident —
## these are drawn at a size you can see from the back of the room.
func _crest_slot() -> Control:
	var slot := VBoxContainer.new()
	slot.alignment = BoxContainer.ALIGNMENT_CENTER
	slot.add_theme_constant_override("separation", 10)
	slot.custom_minimum_size = Vector2(CREST_BOX, CREST_BOX)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return slot


const CREST_BOX := 230.0


## A crest, or the team's first letter while the art is still to be drawn.
func _paint_crest(slot: Control, art_name: String, team_name: String) -> void:
	if slot == null:
		return
	for child in slot.get_children():
		child.queue_free()

	var art := MenuSupport.icon_texture(art_name)
	if art != null:
		var picture := TextureRect.new()
		picture.texture = art
		picture.custom_minimum_size = Vector2(CREST_BOX, CREST_BOX)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(picture)
	else:
		var pip := Label.new()
		pip.text = team_name.substr(0, 1).to_upper() if team_name != "" else "?"
		pip.custom_minimum_size = Vector2(CREST_BOX, CREST_BOX)
		pip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		pip.add_theme_font_size_override("font_size", 96)
		pip.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(pip)

	if team_name.strip_edges() == "":
		return
	var named := Label.new()
	named.text = team_name.to_upper()
	named.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	named.add_theme_font_size_override("font_size", 18)
	named.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	named.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(named)


func _dress(key: String, data: Dictionary) -> void:
	var nodes: Dictionary = _side[key]
	var card = data.get("card")
	_cards[key] = card
	var is_attacker := bool(data.get("is_attacker", false))

	if nodes["role"]:
		(nodes["role"] as Label).text = "ATTACKER" if is_attacker else "DEFENDER"
	if nodes["name"]:
		(nodes["name"] as Label).text = card.player_name if card != null else "—"
	if nodes["power"]:
		var label: Label = nodes["power"]
		label.text = "?"
		label.add_theme_color_override("font_color", DIM_TEXT)
	if nodes["ability"]:
		var label2: Label = nodes["ability"]
		label2.text = "—"
		label2.add_theme_color_override("font_color", DIM_TEXT)
	if nodes["result"]:
		(nodes["result"] as Label).text = ""

	_mark_star(key, card)

	# Both units run at each other; the attacker is the one carrying the ball.
	_play_anim(key, card, "run")


## A Star Player keeps its badge through the power check, so the moment that
## decides the duel never leaves you guessing which of the two was the Star.
## The marker is created once per side and then just shown or hidden.
func _mark_star(key: String, card) -> void:
	var stage: Control = _side[key]["stage"]
	if stage == null:
		return

	var mark := stage.get_node_or_null("StarMark") as Control
	var wants_mark: bool = card != null and card.is_star()

	if not wants_mark:
		if mark != null:
			mark.visible = false
		return

	if mark == null:
		mark = StarBadge.make_marker(false, 44.0)
		mark.name = "StarMark"
		stage.add_child(mark)
		mark.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		mark.offset_left = -56.0
		mark.offset_top = 6.0
		mark.offset_right = -12.0
		mark.offset_bottom = 50.0
	mark.visible = true


func _play_anim(key: String, card, anim_name: String) -> void:
	var animator: SpriteAnimator = _anim.get(key)
	if animator == null or card == null or db == null:
		return
	var spec := db.get_anim(anim_name, card.unit_type)
	if spec == null:
		spec = db.get_anim("idle", card.unit_type)
	animator.speed_scale = _rate()
	animator.play(card.artwork, spec)
	var stage: Control = _side[key]["stage"]
	animator.fit_into(Vector2(stage.size.x if stage != null and stage.size.x > 1.0 else 600.0, 360.0))


func _set_power(nodes: Dictionary, value: int, colour: Color) -> void:
	var label: Label = nodes["power"]
	if label == null:
		return
	label.text = str(value)
	label.add_theme_color_override("font_color", colour)


func _stamp(key: String, won: bool) -> void:
	var nodes: Dictionary = _side[key]
	var label: Label = nodes["result"]
	if label == null:
		return
	label.text = "WIN" if won else "LOSE"
	label.add_theme_color_override("font_color", WIN_TEXT if won else LOSE_TEXT)
	_play_anim(key, _cards.get(key), "win" if won else "lose")


# =============================================================
#  PACING
# =============================================================

## Is the player leaning on the button RIGHT NOW? Held, not pressed — so the
## duel runs fast for exactly as long as you hold it and drops back the moment
## you let go.
func hurrying() -> bool:
	return Input.is_key_pressed(KEY_SPACE) \
		or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


func _rate() -> float:
	var rate := speed
	if _skipping or hurrying():
		rate = skip_speed
	# Engine.time_scale already speeds up the timers underneath, but the
	# sprite animations are driven from _rate() directly, so they are told
	# about it here too and the two stay in step.
	return maxf(0.05, rate)


## Wait out one step of the duel.
##
## It counts DOWN a budget one frame at a time instead of setting a single
## timer, and it re-reads _rate() every frame. That is the whole fix for
## "the skip only works if I press it at the right moment": pressing halfway
## through a step now shortens the rest of that step immediately, rather than
## waiting for the next one to begin.
func _beat(seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		await get_tree().process_frame
		if not _running:
			return
		left -= get_process_delta_time() * _rate()
		var live := _rate()
		for key in _anim.keys():
			var animator: SpriteAnimator = _anim[key]
			if animator != null:
				animator.speed_scale = live


## _input, not _unhandled_input: the buttons and panels on this cut-away are
## Controls, and a Control that has the mouse over it consumes the event
## before "unhandled" is ever reached.
func _input(event: InputEvent) -> void:
	if not _running:
		return

	var click := event as InputEventMouseButton
	if click != null and click.pressed:
		skip()
		return

	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_SPACE:
		skip()
