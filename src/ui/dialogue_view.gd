class_name DialogueView
extends Control

# =============================================================
#  THE STORY SCREEN
#
#  Full-screen: a backdrop, a character on the left or right, a name plate,
#  a text box that types itself out, and up to four choices.
#
#  Everything on it comes from a row of Dialogue.csv. This file contains no
#  story at all — change the spreadsheet, change the game.
#
#  DRIVING IT FROM ANOTHER SCREEN
#      DialogueView.play(get_tree(), "chapter1")
#  or set `scene_name` in the Inspector and run dialogue_view.tscn directly.
#
#  ART FOLDERS (all optional — missing art degrades to a coloured panel)
#      res://assets/backgrounds/   the Background column
#      res://assets/portraits/     the Portrait column
#      res://assets/music/         the Music column
#
#  CONTROLS
#      Click, Space or Enter    advance, or finish the typing early
#      Escape                   leave the scene
# =============================================================

signal scene_finished(scene_name: String)

const META_SCENE := "cw_dialogue_scene"
const META_RETURN := "cw_dialogue_return"

const BACKGROUND_DIRS: Array[String] = [
	"res://assets/backgrounds/", "res://assets/scenes/", "res://assets/"]
const PORTRAIT_DIRS: Array[String] = [
	"res://assets/portraits/", "res://assets/players/", "res://assets/"]
const MUSIC_DIRS: Array[String] = ["res://assets/music/", "res://assets/"]

## Which scene from the CSVs to play. Overridden by DialogueView.play().
@export var scene_name: String = "main"
## Characters per second. 0 shows each line instantly.
@export var type_speed: float = 45.0
## Where to go when the scene ends, if nobody said otherwise.
@export var return_to_menu: bool = true

var db: CardDatabase
var story: DialogueDB
var state: GameState

var _line: DialogueLine = null
var _typing: bool = false
var _shown_chars: float = 0.0

# --- Nodes, all built in code ---
var _background: TextureRect
var _backdrop_fill: ColorRect
var _portrait_slots: Dictionary = {}     # "left"/"right"/"centre" -> Control
var _name_plate: Label
var _text_label: RichTextLabel
var _text_panel: PanelContainer
var _choice_box: VBoxContainer
var _prompt: Label
var _music: AudioStreamPlayer


# =============================================================
#  ENTRY
# =============================================================

## Jump to the story screen and play `scene`. `return_scene` is where LEAVING
## it goes — pass a ScenePaths constant, or leave it for the main menu.
static func play(tree: SceneTree, scene: String, return_scene: String = "") -> void:
	if tree == null:
		return
	tree.set_meta(META_SCENE, scene)
	if return_scene != "":
		tree.set_meta(META_RETURN, return_scene)
	ScenePaths.go_to(tree, ScenePaths.STORY)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	db = CardDatabase.get_db()
	story = DialogueDB.get_db()
	state = GameState.fetch(get_tree())

	var tree := get_tree()
	if tree != null and tree.has_meta(META_SCENE):
		scene_name = String(tree.get_meta(META_SCENE))
		tree.remove_meta(META_SCENE)

	_build_ui()

	var opening := story.opening_line(scene_name, state)
	if opening == null:
		_show_missing_scene()
		return
	_show(opening)


# =============================================================
#  BUILDING THE SCREEN
# =============================================================

func _build_ui() -> void:
	_backdrop_fill = ColorRect.new()
	_backdrop_fill.color = MenuSupport.COLOUR_BACKGROUND
	_backdrop_fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_backdrop_fill)

	_background = TextureRect.new()
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)

	# Keeps white text readable over a bright backdrop.
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.28)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	_build_portrait_slots()
	_build_text_box()

	_music = AudioStreamPlayer.new()
	_music.name = "Music"
	add_child(_music)


func _build_portrait_slots() -> void:
	# Three fixed standing spots. A line names one in its Side column, and the
	# other two are emptied, so only the speaker is ever on screen.
	var layout := {
		"left": Vector2(0.04, 0.0),
		"centre": Vector2(0.34, 0.0),
		"right": Vector2(0.64, 0.0),
	}
	for key in ["left", "centre", "right"]:
		var slot := Control.new()
		slot.name = "Portrait_" + String(key)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.set_anchors_preset(Control.PRESET_FULL_RECT)
		var frac: Vector2 = layout[key]
		slot.anchor_left = frac.x
		slot.anchor_right = frac.x + 0.32
		slot.anchor_top = 0.06
		slot.anchor_bottom = 0.70
		slot.offset_left = 0.0
		slot.offset_right = 0.0
		slot.offset_top = 0.0
		slot.offset_bottom = 0.0
		add_child(slot)
		_portrait_slots[key] = slot


func _build_text_box() -> void:
	_text_panel = PanelContainer.new()
	_text_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_text_panel.anchor_top = 0.68
	_text_panel.offset_left = 48.0
	_text_panel.offset_right = -48.0
	_text_panel.offset_top = 0.0
	_text_panel.offset_bottom = -40.0
	_text_panel.add_theme_stylebox_override("panel",
		MenuSupport.panel_style(Color(0.08, 0.09, 0.12, 0.94), MenuSupport.COLOUR_ACCENT))
	_text_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_text_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text_panel.add_child(column)

	_name_plate = Label.new()
	_name_plate.add_theme_font_size_override("font_size", 26)
	_name_plate.add_theme_color_override("font_color", MenuSupport.COLOUR_ACCENT)
	_name_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_name_plate)

	_text_label = RichTextLabel.new()
	_text_label.bbcode_enabled = true
	_text_label.fit_content = false
	_text_label.scroll_active = false
	_text_label.custom_minimum_size = Vector2(0, 132)
	_text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text_label.add_theme_font_size_override("normal_font_size", 21)
	_text_label.add_theme_color_override("default_color", MenuSupport.COLOUR_TEXT)
	_text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_text_label)

	_choice_box = VBoxContainer.new()
	_choice_box.add_theme_constant_override("separation", 6)
	column.add_child(_choice_box)

	_prompt = Label.new()
	_prompt.text = "click, space or enter to continue    ·    esc to leave"
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_prompt.add_theme_font_size_override("font_size", 12)
	_prompt.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_prompt)


# =============================================================
#  PLAYING A LINE
# =============================================================

func _show(line: DialogueLine) -> void:
	_line = line
	if line == null:
		_finish()
		return

	# Effects fire when the line is SHOWN, so a line can hand out a reward or
	# set a flag just by being reached.
	line.show_effects(state)

	_apply_background(line)
	_apply_portrait(line)
	_apply_music(line)

	_name_plate.text = line.speaker
	_name_plate.visible = line.speaker.strip_edges() != ""

	_text_label.text = line.text
	if type_speed > 0.0 and line.text.length() > 0:
		_typing = true
		_shown_chars = 0.0
		_text_label.visible_characters = 0
	else:
		_typing = false
		_text_label.visible_characters = -1

	_rebuild_choices()


func _process(delta: float) -> void:
	if not _typing:
		return
	_shown_chars += type_speed * delta
	var total := _text_label.get_total_character_count()
	if _shown_chars >= float(total):
		_finish_typing()
	else:
		_text_label.visible_characters = int(_shown_chars)


func _finish_typing() -> void:
	_typing = false
	_shown_chars = 0.0
	_text_label.visible_characters = -1
	_rebuild_choices()


## Choices only appear once the line has finished typing — otherwise you can
## answer a question you have not read yet.
func _rebuild_choices() -> void:
	for child in _choice_box.get_children():
		child.queue_free()

	_prompt.text = "click, space or enter to continue    ·    esc to leave"

	if _line == null or _typing or not _line.has_choices():
		_prompt.visible = not _typing
		return

	var options := _line.available_choices(state)
	if options.is_empty():
		# Every branch was gated out. Say so rather than trapping the player.
		_prompt.text = "no option available here    ·    click to continue"
		_prompt.visible = true
		return

	_prompt.visible = false
	for choice in options:
		var button := Button.new()
		button.text = choice.text
		button.add_theme_font_size_override("font_size", 19)
		button.add_theme_stylebox_override("normal",
			MenuSupport.panel_style(MenuSupport.COLOUR_PANEL, MenuSupport.COLOUR_ACCENT))
		button.add_theme_stylebox_override("hover",
			MenuSupport.panel_style(MenuSupport.COLOUR_SLOT_EMPTY, MenuSupport.COLOUR_ACCENT))
		button.pressed.connect(_on_choice.bind(choice))
		_choice_box.add_child(button)


# =============================================================
#  INPUT
# =============================================================

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_advance()
		accept_event()


func _unhandled_input(event: InputEvent) -> void:
	# `pause` gets you out of a conversation, `confirm` moves it along. Both
	# are rows in Keys.csv, so both are rebindable and both answer to a
	# controller — see game_keys.gd. Enter still works as well, because
	# pressing Enter to advance text is a reflex worth honouring.
	if GameKeys.pressed(event, "pause"):
		_finish()
		return
	if GameKeys.pressed(event, "confirm"):
		_advance()
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo \
			and key.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		_advance()


## One click does one thing: finish the typing if it is still running,
## otherwise move on. A line with choices waits for a button instead.
func _advance() -> void:
	if _typing:
		_finish_typing()
		return
	if _line != null and _line.has_choices() \
			and not _line.available_choices(state).is_empty():
		return
	_go_next()


func _on_choice(choice: DialogueChoice) -> void:
	choice.take(state)

	if choice.next_id.strip_edges() == "":
		_finish()
		return
	_show(story.target_line(choice.next_id, _line.scene, state))


func _go_next() -> void:
	if _line == null:
		_finish()
		return

	if _line.next_id.strip_edges() != "":
		_show(story.target_line(_line.next_id, _line.scene, state))
		return

	# No Next written: fall through to the row below, which is what lets a
	# scene be a plain top-to-bottom list.
	var following := story.line_after(_line, state)
	if following == null:
		_finish()
		return
	_show(following)


# =============================================================
#  PRESENTATION
# =============================================================

func _apply_background(line: DialogueLine) -> void:
	if line.background.strip_edges() == "":
		return          # blank means "keep the one already up"
	var art := _find_texture(line.background, BACKGROUND_DIRS)
	_background.texture = art
	if art == null:
		print("[Story] %s: no background art called '%s'." % [line.where(), line.background])


func _apply_portrait(line: DialogueLine) -> void:
	for key in _portrait_slots.keys():
		var slot: Control = _portrait_slots[key]
		for child in slot.get_children():
			child.queue_free()

	if line.portrait.strip_edges() == "":
		return

	var sheet := _find_texture(line.portrait, PORTRAIT_DIRS)
	if sheet == null:
		print("[Story] %s: no portrait art called '%s'." % [line.where(), line.portrait])
		return

	var slot: Control = _portrait_slots.get(line.side, _portrait_slots["left"])

	# An Animation column turns the portrait into a spritesheet playing that
	# animation — the same Animations.csv rows the units on the pitch use.
	var spec: AnimSpec = null
	if line.animation.strip_edges() != "":
		spec = db.get_anim(line.animation, line.speaker)
		if spec == null:
			print("[Story] %s: no animation called '%s' in Animations.csv."
				% [line.where(), line.animation])

	if spec != null:
		var animator := SpriteAnimator.new()
		animator.name = "Animator"
		animator.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		animator.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(animator)
		animator.play(sheet, spec)
		animator.fit_into(slot.size if slot.size.y > 1.0 else Vector2(420, 540))
		return

	var still := TextureRect.new()
	still.texture = sheet
	still.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	still.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	still.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	still.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	still.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(still)


func _apply_music(line: DialogueLine) -> void:
	if line.music.strip_edges() == "":
		return
	for folder in MUSIC_DIRS:
		for ext in [".ogg", ".wav", ".mp3", ""]:
			var path: String = folder + line.music + ext
			if ResourceLoader.exists(path):
				var stream := load(path)
				if stream is AudioStream:
					if _music.stream == stream and _music.playing:
						return
					_music.stream = stream
					_music.play()
					return
	print("[Story] %s: no music called '%s'." % [line.where(), line.music])


func _find_texture(file_name: String, dirs: Array[String]) -> Texture2D:
	var clean := file_name.strip_edges()
	for folder in dirs:
		# Both "portrait.png" and a bare "portrait" work.
		for candidate in [folder + clean, folder + clean + ".png"]:
			if ResourceLoader.exists(candidate):
				var res := load(candidate)
				if res is Texture2D:
					return res as Texture2D
	return null


# =============================================================
#  LEAVING
# =============================================================

func _finish() -> void:
	_typing = false
	state.save_to_disk()

	print("[Story] '%s' finished. Changes this session:" % scene_name)
	if state.history.is_empty():
		print("        (nothing changed)")
	for entry in state.history:
		print("        - ", entry)

	scene_finished.emit(scene_name)

	var tree := get_tree()
	if tree == null:
		return

	var destination := ScenePaths.MAIN_MENU
	if tree.has_meta(META_RETURN):
		destination = String(tree.get_meta(META_RETURN))
		tree.remove_meta(META_RETURN)
	elif not return_to_menu:
		return

	ScenePaths.go_to(tree, destination)


func _show_missing_scene() -> void:
	_name_plate.text = "No story here yet"
	_name_plate.visible = true
	_text_label.visible_characters = -1
	_text_label.text = "Nothing in res://data/ has a Scene called \"%s\".\n\n" % scene_name \
		+ "A dialogue CSV is any file in res://data/ whose header row has a "\
		+ "[b]Node ID[/b] column and a [b]Text[/b] column. The Output panel lists "\
		+ "every scene that did load.\n\nEsc to go back."
	_typing = false
