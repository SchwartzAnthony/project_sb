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
## ROUND AN: false over a menu (Guide.csv) - nothing there needs to stop.
var _pause := true
## ROUND AN - THE TUTORIAL: what the coach points at while he talks. Each is
## {"rect": Rect2 on the screen, "ring": bool}; a gold box (or circle) is drawn
## round it in the duel highlight's gold (Tuning.csv duel_hl_*).
var _spots: Array = []
var _panel: PanelContainer


## Open the box with `scene` over whatever is on screen. Returns the box, or
## null when the scene has no line to show.
static func play(host: Node, scene: String, state: GameState,
		pause: bool = true, spots: Array = []) -> MatchTalkBox:
	var dialogue := DialogueDB.get_db()
	var first := dialogue.opening_line(scene, state)
	if first == null or host == null:
		return null
	var box := MatchTalkBox.new()
	box._db = dialogue
	box._state = state
	box._pause = pause
	box._spots = spots
	host.add_child(box)
	box._show(first)
	return box


func _ready() -> void:
	layer = 150   # above a window over the base (BaseWindow is 120)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_art = StoryArt.get_db()
	_was_paused = get_tree().paused
	if _pause:
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
	_panel = panel
	if not _spots.is_empty():
		root.add_child(CoachSpots.make(_spots))
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
	_out_of_the_way()


## A box along the bottom would sit on top of what the coach is pointing at
## when that is low on the screen; then the box (and the face) go to the top.
func _out_of_the_way() -> void:
	var low := false
	var screen := get_viewport().get_visible_rect().size
	for spot in _spots:
		var rect: Rect2 = spot.get("rect", Rect2())
		if rect.end.y > screen.y - 260.0:
			low = true
	if not low:
		return
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 0.0
	_panel.offset_top = 30
	_panel.offset_bottom = 250
	_portrait.anchor_top = 0.0
	_portrait.anchor_bottom = 0.0
	_portrait.offset_top = 30
	_portrait.offset_bottom = 30 + PORTRAIT_SIZE.y


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
	if _pause:
		get_tree().paused = _was_paused
	finished.emit()
	queue_free()


## THE GOLD ROUND WHAT THE COACH IS TALKING ABOUT (round AN, the tutorial).
## The same gold and the same pretzel-cornered box as the duel highlights
## (Tuning.csv duel_hl_colour, duel_hl_box_art, duel_hl_art_scale,
## duel_hl_box_margin), so the player learns one look for "look here".
class CoachSpots extends Control:
	var spots: Array = []
	var colour := Color(0.98, 0.78, 0.16)
	var art: Texture2D
	var art_scale := 3.0
	var margin := 17
	var _t := 0.0

	static func make(list: Array) -> CoachSpots:
		var made := CoachSpots.new()
		made.spots = list
		made.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		made.mouse_filter = Control.MOUSE_FILTER_IGNORE
		made.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var db := CardDatabase.get_db()
		var gold := db.tune_text("duel_hl_colour", "")
		if Color.html_is_valid(gold):
			made.colour = Color.html(gold)
		var path := db.tune_text("duel_hl_box_art", "")
		if path != "" and ResourceLoader.exists(path):
			made.art = load(path) as Texture2D
		made.art_scale = maxf(1.0, db.tune_float("duel_hl_art_scale", 3.0))
		made.margin = db.tune_int("duel_hl_box_margin", 17)
		# Each box is a NinePatch child, so the art stretches like the duel's.
		for spot in list:
			if bool(spot.get("ring", false)) or made.art == null:
				continue
			var rect: Rect2 = (spot.get("rect", Rect2()) as Rect2).grow(14.0)
			var patch := NinePatchRect.new()
			patch.texture = made.art
			patch.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			patch.mouse_filter = Control.MOUSE_FILTER_IGNORE
			patch.patch_margin_left = made.margin
			patch.patch_margin_right = made.margin
			patch.patch_margin_top = made.margin
			patch.patch_margin_bottom = made.margin
			patch.position = rect.position
			patch.scale = Vector2.ONE * made.art_scale
			patch.size = rect.size / made.art_scale
			made.add_child(patch)
		return made

	func _process(delta: float) -> void:
		_t += delta
		# A slow pulse, so the eye finds it.
		modulate.a = 0.75 + 0.25 * sin(_t * 4.0)
		queue_redraw()

	func _draw() -> void:
		for spot in spots:
			var rect: Rect2 = (spot.get("rect", Rect2()) as Rect2).grow(14.0)
			if bool(spot.get("ring", false)):
				var radius := maxf(rect.size.x, rect.size.y) * 0.5 + 6.0
				draw_arc(rect.get_center(), radius, 0.0, TAU, 96, colour, 6.0, true)
			else:
				draw_rect(rect, Color(colour.r, colour.g, colour.b, 0.10), true)
				if art == null:
					draw_rect(rect, colour, false, 5.0)
