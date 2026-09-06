extends SceneTree

# =============================================================
#  HEADLESS MATCH TEST RIG
#
#  Runs a whole 90-minute match with no window and no clicking, printing
#  every draft, duel, shot and goal. A full match takes ~25 seconds.
#
#  Put this at the project root, then run from a terminal:
#
#     godot --headless --path . --script res://test_run.gd
#
#  It auto-picks the FIRST card in every draft, so it is a smoke test and a
#  balance sampler, not a strategy test. Run it a few times and watch the
#  final scores — that is how the goalie stamina table was measured.
# =============================================================

const MAIN_SCENE_PATH := "res://src/formations/main_scene.tscn"
const SPEED := 45.0          # in-game minutes per real second
const REAL_TIME_LIMIT := 100.0

var main: Node
var started := false
var elapsed := 0.0


func _initialize() -> void:
	main = load(MAIN_SCENE_PATH).instantiate()
	root.add_child(main)
	main.time_scale = SPEED


func _process(delta: float) -> bool:
	elapsed += delta

	if not is_instance_valid(main):
		push_error("main_scene was freed unexpectedly")
		return true

	# Kick off once the button appears.
	if not started and main.start_draft_button.visible:
		started = true
		main.start_draft_button.pressed.emit()
		return false

	# Whenever cards are on screen, take the first one.
	var cards: Node = main.card_container
	if cards.get_child_count() > 0:
		var card = cards.get_child(0)
		if card.current_data != null:
			card.card_selected.emit(card.current_data)

	if main.current_state == main.MatchState.FULL_TIME:
		print(">>> FULL TIME reached cleanly — %d : %d" % [main.player_score, main.enemy_score])
		return true

	if elapsed > REAL_TIME_LIMIT:
		push_error("Timed out before full time — match state stuck at %s" % main.current_state)
		return true

	return false
