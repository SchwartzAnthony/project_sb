class_name MatchTalkBox
extends CanvasLayer

# =============================================================
#  THE COACH'S BOX OVER THE PITCH  (round AN)
#
#  Plays one Dialogue.csv scene in a box along the bottom of the screen while
#  the match waits (the whole game is paused underneath). Click, Space or
#  Enter for the next line. Which scene, and when, is data/MatchTalk.csv -
#  see match_talk.gd. Choices in a scene are not offered here: an in-match
#  scene is a few lines of explanation, then back to the football.
# =============================================================

signal finished

const PORTRAIT_SIZE := Vector2(220, 220)

var _db: DialogueDB
var _art: StoryArt
var _state: GameState
var _line: DialogueLine
var _portrait: TextureRect
var _name: Label
var _text: Label
var _was_paused := false


## Open the box with `scene` over whatever is on screen. Returns the box, or
## null when the scene has no line to show.
static func play(host: Node, scene: String, state: GameState) -> MatchTalkBox:
	var dialogue := DialogueDB.get_db()
	var first := dialogue.opening_line(scene, state)
	if first == null or host == null:
		return null
	var box := MatchTalkBox.new()
	box._db = dialogue
	box._state = state
	host.add_child(box)
	box._show(first)
	return box


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	_art = StoryArt.get_db()
	_was_paused = get_tree().paused
	get_tree().paused = true

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.gui_input.connect(_on_input)
	add_child(root)

	# A see-through black sheet, then the box itself.
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.25)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)

	_portrait = TextureRect.new()
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait.anchor_top = 1.0
	_portrait.anchor_bottom = 1.0
	_portrait.offset_left = 50
	_portrait.offset_right = 50 + PORTRAIT_SIZE.x
	_portrait.offset_top = -40 - PORTRAIT_SIZE.y
	_portrait.offset_bottom = -40

	var panel := PanelContainer.new()
	var plate := StyleBoxFlat.new()
	# The see-through black every word in the game sits on, a little darker
	# here because it carries whole sentences over a busy pitch.
	plate.bg_color = Color(0, 0, 0, maxf(TextBackdrop.alpha(), 0.8))
	plate.set_corner_radius_all(6)
	plate.content_margin_left = 24
	plate.content_margin_right = 24
	plate.content_margin_top = 14
	plate.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", plate)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.anchor_left = 0.0
	panel.anchor_right = 1.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 40
	panel.offset_right = -40
	panel.offset_top = -250
	panel.offset_bottom = -30
	root.add_child(panel)
	# The face sits in the box, on the left; the words to its right.
	root.add_child(_portrait)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	var room := Control.new()
	room.custom_minimum_size = Vector2(PORTRAIT_SIZE.x + 20, 0)
	room.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(room)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(column)

	_name = Label.new()
	_name.add_theme_font_size_override("font_size", ThemeBook.font_size("heading", 34))
	_name.add_theme_color_override("font_color", ThemeBook.text_colour("heading", Color(1, 0.9, 0.6)))
	column.add_child(_name)

	_text = Label.new()
	_text.add_theme_font_size_override("font_size",
		CardDatabase.get_db().tune_int("match_talk_text_size", 32))
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_text)

	var hint := Label.new()
	hint.text = "Click to continue"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.add_theme_color_override("font_color", ThemeBook.text_colour("small", Color(0.7, 0.65, 0.5)))
	column.add_child(hint)


func _show(line: DialogueLine) -> void:
	_line = line
	if line == null:
		_close()
		return
	line.show_effects(_state)
	AudioDirector.play_cue(get_tree(), line.sound)
	_name.text = line.speaker
	_name.visible = line.speaker.strip_edges() != ""
	_text.text = line.text
	_portrait.texture = _face_for(line)
	_portrait.flip_h = false


func _face_for(line: DialogueLine) -> Texture2D:
	var row := _art.portrait_for(line.portrait, line.speaker, line.mood, line.view)
	var file_name := String(row.get("image", ""))
	if file_name == "" or not ResourceLoader.exists(file_name):
		return null
	return load(file_name) as Texture2D


func _next() -> void:
	if _line == null:
		_close()
		return
	var after: DialogueLine = null
	if _line.next_id != "":
		after = _db.target_line(_line.next_id, _line.scene, _state)
	else:
		after = _db.line_after(_line, _state)
	_show(after)


func _on_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_next()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		_next()
		get_viewport().set_input_as_handled()


func _close() -> void:
	if _state != null:
		_state.save_to_disk()
	get_tree().paused = _was_paused
	finished.emit()
	queue_free()
