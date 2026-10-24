class_name AnimWindow
extends CanvasLayer

# =============================================================
#  THE ANIMATION WINDOW — a caption and a picture, over the pitch
#
#  ============ "WITH A TEMPLATE SO IT RUNS BEFORE ANY ART EXISTS" ============
#
#  That is the whole design brief, and it is the reason this is not simply a
#  place to put a video. A moment in the game — somebody puts the ball out,
#  somebody scores — should be watchable TODAY, with the spritesheets you
#  already have, and should get better when you draw something. So the window
#  shows, in order of preference:
#
#      an IMAGE    whatever you name in the row's `Art` column, shown whole
#      an ANIMATION a row of Animations.csv played on THAT PLAYER'S OWN sheet
#      NOTHING     the caption alone, on an empty stage
#
#  Art wins over an animation, because a picture you went and drew is the
#  more deliberate of the two. And the third case is not a failure: a window
#  with a caption and no picture is still a beat, and the match keeps going.
#
#  ============ WHY IT IS ITS OWN FILE ============
#
#  The goal celebration had one of these first. The out-of-bounds sequence
#  wants exactly the same thing, and two copies of a window is two windows
#  that drift apart — one gets a new corner style and the other does not,
#  and a year later the game has two looks for the same idea.
#
#  So there is one, and both use it. It takes its frame from the `window` row
#  of Theme.csv, which is how it came out of Phase 3 wearing stained oak and
#  brass without anybody editing it.
# =============================================================

## How big the picture inside the window is. The panel is this plus its
## padding and its caption, so widening it widens the window.
const STAGE := Vector2(420.0, 260.0)

var db: CardDatabase

var _frame: PanelContainer
var _caption: Label
var _stage: CenterContainer
var _anim: SpriteAnimator
var _picture: TextureRect
# Tuning.csv anim_window_style drawn (24 Oct 2026): the beer mat panel with
# the outdoor field behind the player, like the player card.
var _drawn := false


## Put one up over `on`. It is invisible until show_panel() is called.
static func open(on: Node, database: CardDatabase, above: int = 150) -> AnimWindow:
	var made := AnimWindow.new()
	made.name = "AnimWindow"
	made.db = database
	made.layer = above
	on.add_child(made)
	return made


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func _build() -> void:
	_frame = PanelContainer.new()
	_frame.visible = false
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_theme_stylebox_override("panel", MenuSupport.styled(
		"window", "", Color(0.06, 0.07, 0.10, 0.95), MenuSupport.COLOUR_ACCENT))
	add_child(_frame)
	_drawn = db != null and db.tune_text("anim_window_style", "drawn").strip_edges().to_lower() == "drawn"
	if _drawn:
		_mat_behind()

	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right"]:
		pad.add_theme_constant_override(side, 34)
	for side in ["margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 26)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _drawn:
		pad.add_theme_constant_override("margin_left", 54)
		pad.add_theme_constant_override("margin_right", 54)
		pad.add_theme_constant_override("margin_top", 50)
		pad.add_theme_constant_override("margin_bottom", 40)
	_frame.add_child(pad)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(column)

	# A CentreContainer, because an anchor preset is applied ONCE against the
	# size the child has at that moment — and the animation has no size until
	# fit_into() gives it one, which happens later. The first version of the
	# celebration window pinned the figure by its top-left corner to the
	# middle of the panel and it hung down over the caption.
	_stage = CenterContainer.new()
	_stage.custom_minimum_size = STAGE
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_stage)
	if _drawn:
		# THE OUTDOOR FIELD behind the player, like the meadow on the card.
		var field := TextureRect.new()
		field.texture = ScreenLook.picture(db.tune_text("anim_window_field",
			"res://assets/ui/anim_window/meadow.png"))
		field.custom_minimum_size = STAGE
		field.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		field.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		field.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		field.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_stage.add_child(field)

	_picture = TextureRect.new()
	_picture.custom_minimum_size = STAGE
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picture.visible = false
	_stage.add_child(_picture)

	_anim = SpriteAnimator.new()
	_anim.visible = false
	if _drawn:
		# Down on the grass rather than floating in front of the houses.
		var lower := MarginContainer.new()
		lower.custom_minimum_size = STAGE
		lower.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lower.add_theme_constant_override("margin_top", int(db.tune_float("anim_window_drop", 90.0)))
		var middle := CenterContainer.new()
		middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lower.add_child(middle)
		middle.add_child(_anim)
		_stage.add_child(lower)
	else:
		_stage.add_child(_anim)

	if _drawn:
		# A thick ink edge round the field, like the card's picture window.
		var edge := Panel.new()
		edge.custom_minimum_size = STAGE
		edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var line := StyleBoxFlat.new()
		line.draw_center = false
		line.border_color = _ink()
		line.set_border_width_all(5)
		line.set_corner_radius_all(6)
		edge.add_theme_stylebox_override("panel", line)
		_stage.add_child(edge)

	_caption = MenuSupport.heading("", 34, _ink() if _drawn else MenuSupport.COLOUR_ACCENT)
	if _drawn:
		_caption.add_theme_color_override("font_color", _ink())
		_caption.add_theme_constant_override("outline_size", 0)
		_caption.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
		_caption.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.custom_minimum_size = Vector2(STAGE.x, 0.0)
	column.add_child(_caption)


## Show it, or swap what is inside it. `fallbacks` are the animations to try
## after the one you asked for, so a card with no `lose` still shows
## something rather than an empty stage.
func show_panel(caption: String, art: String, animation: String,
		card: PlayerData, fallbacks: Array[String] = ["idle"]) -> void:
	_caption.text = caption
	_caption.visible = caption != ""

	var picture: Texture2D = MenuSupport.icon_texture(art)
	_picture.visible = picture != null
	_picture.texture = picture

	# ROUND AN: the figure this player has on the pitch, if there is one.
	var sheet: Texture2D = card.artwork if card != null else null
	var spec: AnimSpec = null
	var pitch := PitchSprite.window_sheet(card) if picture == null else null
	if pitch != null and animation != "":
		sheet = pitch
		spec = PitchSprite.window_spec(pitch, animation, 1)
	elif picture == null and db != null and card != null and animation != "":
		var tries: Array[String] = [animation]
		tries.append_array(fallbacks)
		for candidate in tries:
			spec = db.get_anim(candidate, card.unit_type)
			if spec != null:
				break
	var playing := spec != null and card != null and sheet != null
	_anim.visible = playing
	if playing:
		_anim.play(sheet, spec)
		_anim.fit_into(STAGE - Vector2(20.0, 20.0 + (db.tune_float("anim_window_drop", 90.0) if _drawn else 0.0)))

	# ============ NOTHING TO SHOW? DO NOT LEAVE THE HOLE ============
	#
	# A caption with no picture is still a beat and the match keeps going —
	# but a 420x260 empty stage above one line of text makes the window look
	# BROKEN rather than plain, which is the opposite of what the fallback is
	# for. So the stage collapses when there is nothing in it and the window
	# is just the words.
	#
	# Found by looking at tools/foul_shot.gd's picture, which is the whole
	# argument for photographing a thing rather than reasoning about it.
	var has_picture := playing or picture != null or _drawn
	_stage.visible = has_picture
	_stage.custom_minimum_size = STAGE if has_picture else Vector2(STAGE.x, 0.0)

	if not _frame.visible:
		_frame.visible = true
		_frame.modulate.a = 0.0
		var fade := create_tween()
		fade.tween_property(_frame, "modulate:a", 1.0, 0.22)
	_place()


func hide_panel() -> void:
	if _frame != null:
		_frame.visible = false
		if _anim != null:
			_anim.stop()


func is_open() -> bool:
	return _frame != null and _frame.visible


## Centred, its own size, re-measured every time because the contents change
## between panels and the window should fit whichever is up.
func _place() -> void:
	_frame.reset_size()
	var box := _frame.size
	var view := get_viewport()
	var screen: Vector2 = Vector2(view.get_visible_rect().size) if view != null \
		else Vector2(1920, 1080)
	_frame.set_anchors_preset(Control.PRESET_TOP_LEFT, true)
	_frame.position = (screen - box) * 0.5


func close() -> void:
	hide_panel()
	queue_free()


func _ink() -> Color:
	return Color.from_string(BeerMatCard.value("ink", "#19110a"), Color(0.1, 0.07, 0.04))


## The cream beer mat panel behind everything, kept the frame's size.
func _mat_behind() -> void:
	_frame.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(holder)
	var edge := int(BeerMatCard.number("inventory_edge", 60.0))
	var patch := InventoryScreen._mat(STAGE, edge, 0.9)
	holder.add_child(patch)
	holder.resized.connect(func() -> void:
		patch.size = holder.size / patch.scale.x)
