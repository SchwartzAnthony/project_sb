class_name RpsClash
extends CanvasLayer

# =============================================================
#  ROCK / PAPER / SCISSORS CLASH
#
#  Fires at the start of every PLAY MAKER, before the tier draft.
#
#     you throw  ->  enemy throws  ->  reveal
#         tie      -> throw again
#         winner   -> chooses ATTACK or DEFEND
#                     (the enemy rolls 50/50 when it wins)
#         ->  emits clash_finished(player_attacks)
#
#  `player_attacks == true` means YOUR side is the attacker in the Tier I
#  duel, and therefore starts the round on the ball.
#
#  It is a CanvasLayer overlay rather than a real OS Window: it dims the
#  pitch behind it, it cannot be dragged off screen or lost behind the game
#  on the Steam Deck, and it still works under --headless for the test rig.
# =============================================================

signal clash_finished(player_attacks: bool)

enum Throw { ROCK, PAPER, SCISSORS }

const THROW_NAMES: Dictionary = {
	Throw.ROCK: "ROCK",
	Throw.PAPER: "PAPER",
	Throw.SCISSORS: "SCISSORS",
}

## Chance the enemy picks ATTACK when it wins the throw.
@export var enemy_attack_chance: float = 0.5
@export var reveal_seconds: float = 0.9
@export var result_seconds: float = 1.0

# Resolved lazily rather than with @onready: a caller can legitimately reach
# start() before this node's _ready() has run (adding to a tree that has not
# started processing defers _ready), and @onready would leave these null.
var dim: ColorRect
var title: Label
var player_throw_label: Label
var enemy_throw_label: Label
var status_label: Label
var throw_buttons: HBoxContainer
var choice_buttons: HBoxContainer

var _busy: bool = false
var _running: bool = false
var _wired: bool = false

const VBOX := "Dim/Center/Panel/Margin/VBox"


func _resolve_nodes() -> bool:
	if dim != null:
		return true
	dim = get_node_or_null("Dim") as ColorRect
	if dim == null:
		push_error("rps_clash.tscn is missing its Dim node.")
		return false
	title = get_node_or_null(VBOX + "/Title") as Label
	player_throw_label = get_node_or_null(VBOX + "/Reveal/PlayerThrow") as Label
	enemy_throw_label = get_node_or_null(VBOX + "/Reveal/EnemyThrow") as Label
	status_label = get_node_or_null(VBOX + "/Status") as Label
	throw_buttons = get_node_or_null(VBOX + "/ThrowButtons") as HBoxContainer
	choice_buttons = get_node_or_null(VBOX + "/ChoiceButtons") as HBoxContainer
	return true


func _ready() -> void:
	_wire()
	dim.visible = false


func _wire() -> void:
	if _wired or not _resolve_nodes():
		return
	_wired = true

	# Throw buttons are wired by their order in the scene, which matches the
	# Throw enum: Rock, Paper, Scissors.
	var index := 0
	for child in throw_buttons.get_children():
		var button := child as Button
		if button != null:
			button.pressed.connect(_on_throw_pressed.bind(index))
			index += 1

	for child in choice_buttons.get_children():
		var button := child as Button
		if button != null:
			button.pressed.connect(_on_choice_pressed.bind(button.name == "AttackButton"))


# =============================================================
#  PUBLIC
# =============================================================

## Open the clash. Await `clash_finished` for the result.
func start() -> void:
	_wire()
	if dim == null:
		clash_finished.emit(randi() % 2 == 0)   # never stall the match
		return
	_running = true
	_busy = false
	dim.visible = true
	title.text = "PLAY MAKER!"
	status_label.text = "Choose your throw."
	player_throw_label.text = "—"
	enemy_throw_label.text = "—"
	choice_buttons.visible = false
	throw_buttons.visible = true
	_set_throws_enabled(true)


func is_running() -> bool:
	return _running


## True while the player still has to throw (used by the headless test rig).
## AUTO plays this whole thing for you.
##
## It waits `pause` before each press so you can still see what happened —
## without that the clash flickers past and the match looks like it skipped a
## step. It re-checks after the wait, because you may have pressed a button
## yourself while it was waiting, or turned AUTO back off.
##
## `attack_chance` is the odds of choosing ATTACK when you win the throw.
## 0.5 is a coin. 1.0 always attacks; 0.0 always defends.
func auto_play(pause: float, attack_chance: float) -> void:
	while _running:
		await get_tree().process_frame
		if not _running:
			return

		if awaiting_throw():
			await get_tree().create_timer(pause).timeout
			if awaiting_throw():
				var throw_index := randi() % 3
				print("[auto] Threw %s for you." % ["rock", "paper", "scissors"][throw_index])
				_on_throw_pressed(throw_index)

		elif awaiting_choice():
			await get_tree().create_timer(pause).timeout
			if awaiting_choice():
				var attack := randf() < attack_chance
				print("[auto] Chose %s for you." % ("ATTACK" if attack else "DEFEND"))
				_on_choice_pressed(attack)


func awaiting_throw() -> bool:
	return _running and not _busy and throw_buttons.visible


## True while the player still has to pick attack or defend.
func awaiting_choice() -> bool:
	return _running and not _busy and choice_buttons.visible


# =============================================================
#  FLOW
# =============================================================

func _on_throw_pressed(throw_index: int) -> void:
	if _busy or not _running:
		return
	_busy = true
	_set_throws_enabled(false)

	var mine: int = throw_index
	var theirs: int = randi() % 3
	player_throw_label.text = String(THROW_NAMES[mine])
	enemy_throw_label.text = String(THROW_NAMES[theirs])

	var outcome := _compare(mine, theirs)

	if outcome == 0:
		status_label.text = "TIE — throw again."
		await _wait(reveal_seconds)
		if not _running:
			return
		_busy = false
		_set_throws_enabled(true)
		return

	if outcome > 0:
		status_label.text = "You win the clash. Attack or defend?"
		await _wait(reveal_seconds)
		if not _running:
			return
		throw_buttons.visible = false
		choice_buttons.visible = true
		_busy = false
		return

	# --- Enemy won the throw: it decides for itself ---
	status_label.text = "The enemy wins the clash."
	await _wait(reveal_seconds)
	if not _running:
		return
	var enemy_attacks := randf() < enemy_attack_chance
	status_label.text = "Enemy chooses to %s." % ("ATTACK" if enemy_attacks else "DEFEND")
	await _wait(result_seconds)
	# If the enemy defends, YOU attack.
	_finish(not enemy_attacks)


func _on_choice_pressed(attack: bool) -> void:
	if _busy or not _running:
		return
	_busy = true
	choice_buttons.visible = false
	status_label.text = "You choose to %s." % ("ATTACK" if attack else "DEFEND")
	await _wait(result_seconds)
	_finish(attack)


func _finish(player_attacks: bool) -> void:
	_running = false
	_busy = false
	dim.visible = false
	clash_finished.emit(player_attacks)


# =============================================================
#  HELPERS
# =============================================================

## 1 = a beats b, -1 = b beats a, 0 = tie.
## Rock(0) > Scissors(2), Paper(1) > Rock(0), Scissors(2) > Paper(1).
func _compare(a: int, b: int) -> int:
	if a == b:
		return 0
	return 1 if (a - b + 3) % 3 == 1 else -1


func _set_throws_enabled(enabled: bool) -> void:
	for child in throw_buttons.get_children():
		var button := child as Button
		if button != null:
			button.disabled = not enabled


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
