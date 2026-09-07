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

func _rate() -> float:
	return maxf(0.05, skip_speed if _skipping else speed)


func _beat(seconds: float) -> void:
	var wait := seconds / _rate()
	if wait <= 0.001:
		await get_tree().process_frame
		return
	await get_tree().create_timer(wait).timeout


func _unhandled_input(event: InputEvent) -> void:
	if not _running:
		return
	if event is InputEventMouseButton and event.pressed:
		skip()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		skip()
