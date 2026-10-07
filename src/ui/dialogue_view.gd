class_name DialogueView
extends Control

# =============================================================
#  THE STORY SCREEN
#
#  Full-screen: a backdrop, the people in the scene (see THE STAGE), a name plate,
#  a text box that types itself out, and up to four choices.
#
#  Everything on it comes from a row of Dialogue.csv. This file contains no
#  story at all — change the spreadsheet, change the game.
#
#  DRIVING IT FROM ANOTHER SCREEN
#      DialogueView.play(get_tree(), "chapter1")
#  or set `scene_name` in the Inspector and run dialogue_view.tscn directly.
#
#  PICTURES: data/StoryArt.csv names every face and room (see story_art.gd).
#  A Portrait or Background that is not a row there is a file name in
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
## Seconds a character takes to walk on, walk off or change places.
## 0 = jump straight there (the screenshot tools use that).
@export var transition_time: float = 0.35

var db: CardDatabase
var story: DialogueDB
var state: GameState

var _line: DialogueLine = null
var _typing: bool = false
var _shown_chars: float = 0.0

# --- Nodes, all built in code ---
var _background: TextureRect
var _background_layers: Control      # StoryArt.csv rows behind the people
var _front_layers: Control           # StoryArt.csv rows with Front = yes
var _art: StoryArt
var _backdrop_fill: ColorRect
var _stage: Control                  # the people stand on this layer
## Everybody on screen: key (portrait ID or speaker) -> Dictionary with
## "node", "portrait", "speaker", "side", "mood", "image", "mirror".
var _cast: Dictionary = {}
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
	# NOT MenuEscape here. This screen has its own use for the pause key
	# — it closes the conversation / the cut-away — and MenuEscape would
	# take that key away and offer to quit the game instead. So it takes
	# only the two pieces it does want.
	ControllerFocus.install(self)
	Loc.install()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	db = CardDatabase.get_db()
	story = DialogueDB.get_db()
	_art = StoryArt.get_db()
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

	_background_layers = _layer_box("BackgroundLayers")

	# Keeps white text readable over a bright backdrop.
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.28)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	_stage = _layer_box("Stage")
	_front_layers = _layer_box("FrontLayers")
	_build_text_box()

	_music = AudioStreamPlayer.new()
	_music.name = "Music"
	add_child(_music)


func _layer_box(box_name: String) -> Control:
	var box := Control.new()
	box.name = box_name
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	return box


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
	# The Sound column: a one-off cue (a cheer, a door) as the line shows.
	AudioDirector.play_cue(get_tree(), line.sound)

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
	for box in [_background_layers, _front_layers]:
		for child in box.get_children():
			child.queue_free()
	var layers := _art.background_layers(line.background)
	if not layers.is_empty():
		_background.texture = null
		for layer in layers:
			var picture := _cover_rect(_find_texture(String(layer["image"]), BACKGROUND_DIRS))
			if picture.texture == null:
				print("[Story] %s: StoryArt.csv '%s' has no picture at %s."
					% [line.where(), line.background, layer["image"]])
			(_front_layers if layer["front"] else _background_layers).add_child(picture)
		return
	var art := _find_texture(line.background, BACKGROUND_DIRS)
	_background.texture = art
	if art == null:
		print("[Story] %s: no background art called '%s'." % [line.where(), line.background])


# =============================================================
#  THE STAGE (round AN, Anthony's note)
#
#  Everybody who has spoken in the scene STAYS on screen until somebody
#  takes their place or a line's Leaves column sends them off:
#    - one person on stage stands in the MIDDLE and looks at the player
#      (their front face), whatever the line's Side and View say
#    - two or more stand at their own Side (left / centre / right). The
#      speaker shows the line's Mood and View; the others turn to the room
#      (their side face) and are dimmed, so you can see who is talking
#    - a newcomer on a Side that is taken pushes the old one off
#  Nobody pops: they slide in from their edge, slide over when the stage
#  fills or empties, and slide out again (transition_time).
# =============================================================

const STAGE_X := {"left": 0.04, "centre": 0.34, "right": 0.64}
const OFFSTAGE_X := {"left": -0.36, "centre": 0.34, "right": 1.04}
const STAGE_WIDTH := 0.32
const DIMMED := Color(0.55, 0.55, 0.6, 1.0)


func _apply_portrait(line: DialogueLine) -> void:
	# Leaves: names (Speaker or Portrait ID) separated by ;  or "all".
	for who in line.leaves.split(";", false):
		var name_key := CardDatabase._normalise(who)
		for key in _cast.keys():
			var actor: Dictionary = _cast[key]
			if name_key == "all" or name_key == key \
					or name_key == CardDatabase._normalise(String(actor["speaker"])):
				_exit(key)

	var speaker_key := ""
	var row := _art.portrait_for(line.portrait, line.speaker, line.mood, line.view)
	var file_name: String = row.get("image", line.portrait)
	if file_name.strip_edges() != "":
		speaker_key = CardDatabase._normalise(
			line.portrait if line.portrait.strip_edges() != "" else line.speaker)
		if not _cast.has(speaker_key):
			# Somebody else on that spot walks off to make room.
			for key in _cast.keys():
				if String(_cast[key]["side"]) == line.side:
					_exit(key)
			_enter(speaker_key, line)
		var actor: Dictionary = _cast[speaker_key]
		actor["side"] = line.side
		actor["mood"] = line.mood
		actor["portrait"] = line.portrait
		actor["speaker"] = line.speaker

	_arrange(line, speaker_key)


## Put everybody in their place and give them the right face.
func _arrange(line: DialogueLine, speaker_key: String) -> void:
	var alone := _cast.size() == 1
	for key in _cast.keys():
		var actor: Dictionary = _cast[key]
		var speaking: bool = key == speaker_key
		var view := "front"
		if not alone:
			view = line.view if speaking else "side"
		var row := _art.portrait_for(String(actor["portrait"]), String(actor["speaker"]),
			String(actor["mood"]), view)
		var file_name: String = row.get("image", actor["portrait"])
		var side := "centre" if alone else String(actor["side"])
		# Everybody looks into the room: a face drawn looking right is
		# mirrored on the right-hand side, and the other way round.
		var faces: String = row.get("faces", "")
		if row.get("view", "") == "front":
			faces = ""
		var mirror := (faces == "right" and side == "right") \
			or (faces == "left" and side == "left")
		var animated := speaking and line.animation.strip_edges() != ""
		if file_name != actor.get("image", "") or mirror != actor.get("mirror", false) \
				or animated or actor.get("animated", false):
			_dress(actor, file_name, mirror, line if animated else null)
		actor["animated"] = animated

		var tint := Color.WHITE
		if not alone and speaker_key != "" and not speaking:
			tint = DIMMED
		_move(actor["node"], STAGE_X[side], tint)


func _enter(key: String, line: DialogueLine) -> void:
	var node := Control.new()
	node.name = "Actor_" + key
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.anchor_top = 0.06
	node.anchor_bottom = 0.70
	var start: float = OFFSTAGE_X.get(line.side, OFFSTAGE_X["left"])
	node.anchor_left = start
	node.anchor_right = start + STAGE_WIDTH
	node.modulate = Color(1, 1, 1, 0)
	_stage.add_child(node)
	_cast[key] = {"node": node, "portrait": line.portrait, "speaker": line.speaker,
		"side": line.side, "mood": line.mood, "image": "", "mirror": false}


func _exit(key: String) -> void:
	var actor: Dictionary = _cast[key]
	_cast.erase(key)
	var node: Control = actor["node"]
	var gone := Color(node.modulate.r, node.modulate.g, node.modulate.b, 0.0)
	var tween := _move(node, OFFSTAGE_X.get(String(actor["side"]), OFFSTAGE_X["left"]), gone)
	if tween == null:
		node.queue_free()
	else:
		tween.finished.connect(node.queue_free)


## Slide a person to `x` and tint them. Returns the tween, or null when
## transition_time is 0 and it simply jumped there.
func _move(node: Control, x: float, tint: Color) -> Tween:
	if transition_time <= 0.0 or not is_inside_tree():
		node.anchor_left = x
		node.anchor_right = x + STAGE_WIDTH
		node.modulate = tint
		return null
	var tween := node.create_tween().set_parallel(true) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "anchor_left", x, transition_time)
	tween.tween_property(node, "anchor_right", x + STAGE_WIDTH, transition_time)
	tween.tween_property(node, "modulate", tint, transition_time)
	return tween


## Swap a person's picture. `line` set = play its Animation column.
func _dress(actor: Dictionary, file_name: String, mirror: bool, line: DialogueLine) -> void:
	var node: Control = actor["node"]
	for child in node.get_children():
		child.queue_free()
	actor["image"] = file_name
	actor["mirror"] = mirror
	var sheet := _find_texture(file_name, PORTRAIT_DIRS)
	if sheet == null:
		print("[Story] %s: no portrait art called '%s'."
			% [_line.where() if _line != null else "?", file_name])
		return

	# An Animation column turns the portrait into a spritesheet playing that
	# animation — the same Animations.csv rows the units on the pitch use.
	if line != null:
		var spec: AnimSpec = db.get_anim(line.animation, line.speaker)
		if spec == null:
			print("[Story] %s: no animation called '%s' in Animations.csv."
				% [line.where(), line.animation])
		else:
			var animator := SpriteAnimator.new()
			animator.name = "Animator"
			animator.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			animator.mouse_filter = Control.MOUSE_FILTER_IGNORE
			node.add_child(animator)
			animator.play(sheet, spec)
			animator.fit_into(node.size if node.size.y > 1.0 else Vector2(420, 540))
			return

	var still := TextureRect.new()
	still.texture = sheet
	still.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	still.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	still.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	still.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	still.mouse_filter = Control.MOUSE_FILTER_IGNORE
	still.flip_h = mirror
	node.add_child(still)


func _cover_rect(art: Texture2D) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = art
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


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
		# Both "portrait.png" and a bare "portrait" work, and so does a
		# whole res:// path (what StoryArt.csv writes).
		var tries: Array = [folder + clean, folder + clean + ".png"]
		if clean.begins_with("res://"):
			tries = [clean]
		for candidate in tries:
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
