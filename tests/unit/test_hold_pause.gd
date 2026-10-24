extends GutTest

# =============================================================
#  HOLD RIGHT CLICK TO PAUSE  (Anthony, 24 Oct)
#
#  The key row, the freeze and let-go, and the Head Coach's stop the first
#  time Koch's ability goes off. A pretend save in memory.
# =============================================================

const HOLD_PAUSE := preload("res://src/core/hold_pause.gd")


func after_each() -> void:
	Input.action_release(HOLD_PAUSE.ACTION)
	Engine.time_scale = 1.0


func test_keys_csv_binds_right_mouse_and_a_trigger() -> void:
	GameKeys.install(get_tree(), true)
	assert_true(InputMap.has_action("hold_pause"), "Keys.csv has hold_pause")
	var mouse := false
	var trigger := false
	for event in InputMap.action_get_events("hold_pause"):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
			mouse = true
		if event is InputEventJoypadMotion and event.axis == JOY_AXIS_TRIGGER_RIGHT:
			trigger = true
	assert_true(mouse, "right mouse button")
	assert_true(trigger, "right trigger (until Anthony picks, Q269)")

	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	assert_true(HOLD_PAUSE.is_hold_event(click), "right click is the hold")
	click.button_index = MOUSE_BUTTON_LEFT
	assert_false(HOLD_PAUSE.is_hold_event(click), "left click still skips")


func test_holding_freezes_and_letting_go_carries_on() -> void:
	GameKeys.install(get_tree(), true)
	var node: Node = HOLD_PAUSE.attach(self)
	autofree(node)
	Engine.time_scale = 2.0
	Input.action_press(HOLD_PAUSE.ACTION)
	node._process(0.016)
	assert_eq(Engine.time_scale, 0.0, "held: time stands still")
	assert_true(HOLD_PAUSE.active)
	Input.action_release(HOLD_PAUSE.ACTION)
	node._process(0.016)
	assert_eq(Engine.time_scale, 2.0, "let go: back to the 2x it had")
	assert_false(HOLD_PAUSE.active)


func test_coach_explains_it_the_first_time_koch_ability_fires() -> void:
	MatchTalk.reload()
	var state := GameState.new()
	var other := MatchTalk.row_for("ability_fired", "tutorial", state,
		{"round": "4", "tier": "I", "player": "Hans"})
	assert_true(other.is_empty(), "someone else's ability: no stop")
	var row := MatchTalk.row_for("ability_fired", "tutorial", state,
		{"round": "4", "tier": "IV", "player": "Koch"})
	assert_eq(String(row.get("scene", "")), "tut-hold-pause", "Koch's: the Head Coach")
	var again := MatchTalk.row_for("ability_fired", "tutorial", state,
		{"round": "5", "tier": "IV", "player": "Koch"})
	assert_true(again.is_empty(), "only the first time")
	assert_false(DialogueDB.get_db().scene_names().is_empty())
	assert_true(DialogueDB.get_db().scene_names().has("tut-hold-pause"), "the lines are in Dialogue.csv")
