class_name NewUnlocksPanel
extends Control

# =============================================================
#  "NEW AT THE BASE" — the flash when you walk in having earned something
#
#  You come back from a match, the base loads, and anything you unlocked
#  since you were last here flashes up on top of it with a Continue button.
#  Then it is marked as seen and never flashes again.
#
#  HOW "NEW" IS REMEMBERED
#    A flag per unlock: `seen_unlock_<name>`. That is all. It is an ordinary
#    flag, so a CSV can test it too — `!flag:seen_unlock_brewery` is a
#    perfectly good Requires for a visitor who wants to talk to you about
#    the Brewery the first time you see it.
#
#  It is built in code rather than from a .tscn because it is an overlay
#  that appears on top of whatever screen added it, and there is only one of
#  it. Everything it looks like is in _build() below.
# =============================================================

const SEEN_PREFIX := "seen_unlock_"

signal dismissed

var _names: Array[String] = []
var _clock: float = 0.0
var _cards: Array[Control] = []


## What you have unlocked but not yet been shown. Empty means do not bother
## putting this on screen at all.
static func unseen(state: GameState) -> Array[String]:
	var out: Array[String] = []
	if state == null:
		return out
	for key in state.unlocks.keys():
		var spelling := String(state.unlocks[key])
		if not state.has_flag(SEEN_PREFIX + spelling):
			out.append(spelling)
	out.sort()
	return out


static func mark_all_seen(state: GameState) -> void:
	if state == null:
		return
	for key in state.unlocks.keys():
		state.set_flag(SEEN_PREFIX + String(state.unlocks[key]), true)


## Put it on screen over `host`, if there is anything new. Returns the panel,
## or null when there was nothing to show.
static func show_over(host: Node, state: GameState) -> NewUnlocksPanel:
	var new_ones := unseen(state)
	if new_ones.is_empty() or host == null:
		return null

	var panel := NewUnlocksPanel.new()
	panel.name = "NewUnlocksPanel"
	panel._names = new_ones
	host.add_child(panel)
	return panel


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Above everything the base screen drew, and it takes the mouse so you
	# cannot click a building through it.
	z_index = 100
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func _build() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.72)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)

	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 16)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)

	var heading := Label.new()
	heading.text = "NEW AT THE BASE" if _names.size() > 1 else "NEW AT THE BASE"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 34)
	heading.add_theme_color_override("font_color", MenuSupport.COLOUR_ACCENT)
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(heading)

	for name_text in _names:
		column.add_child(_card(name_text))

	var hint := Label.new()
	hint.text = "%d new thing%s. Have a look around." % [
		_names.size(), "" if _names.size() == 1 else "s"]
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(hint)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(row)

	var go := Button.new()
	go.text = "Continue"
	go.custom_minimum_size = Vector2(220, 50)
	go.focus_mode = Control.FOCUS_NONE
	go.add_theme_font_size_override("font_size", 18)
	go.add_theme_stylebox_override("normal",
		MenuSupport.panel_style(MenuSupport.COLOUR_PANEL, MenuSupport.COLOUR_ACCENT))
	go.add_theme_stylebox_override("hover",
		MenuSupport.panel_style(MenuSupport.COLOUR_SLOT_EMPTY, MenuSupport.COLOUR_ACCENT))
	go.pressed.connect(_close)
	row.add_child(go)


func _card(name_text: String) -> Control:
	var frame := PanelContainer.new()
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	frame.custom_minimum_size = Vector2(460, 0)
	frame.add_theme_stylebox_override("panel",
		MenuSupport.panel_style(MenuSupport.COLOUR_PANEL, MenuSupport.COLOUR_ACCENT))
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right"]:
		pad.add_theme_constant_override(side, 22)
	for side2 in ["margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side2, 14)
	frame.add_child(pad)

	var label := Label.new()
	label.text = name_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(label)

	_cards.append(frame)
	return frame


## The flash. Each card pulses slightly out of step with the next one, so a
## list of three reads as three things rather than one block blinking.
func _process(delta: float) -> void:
	_clock += delta
	for i in _cards.size():
		var card := _cards[i]
		if card == null:
			continue
		var pulse := 0.80 + 0.20 * (0.5 + 0.5 * sin(_clock * 4.0 - float(i) * 0.7))
		card.modulate = Color(1.0, 1.0, 1.0, pulse)


func _close() -> void:
	var state := GameState.fetch(get_tree())
	mark_all_seen(state)
	state.save_to_disk()
	dismissed.emit()
	queue_free()


## Clicking anywhere, or any key, also dismisses it.
func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed:
		_close()
