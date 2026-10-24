class_name SideBanner
extends CanvasLayer

# =============================================================
#  ARE YOU ATTACKING OR DEFENDING? — the one thing you can never not know
#
#  ============ WHAT WAS WRONG ============
#
#  The clash decides which way round the round is played, and then it said so
#  ONCE, in a line of small text on a screen that closes a second later. From
#  that moment you were choosing four cards — and which card is the right one
#  depends entirely on whether you are attacking or defending, because one
#  reads a card's attack and the other reads its defence.
#
#  So the single most important fact in the draft was the least visible.
#
#  ============ WHAT IT DOES NOW ============
#
#  Two things, both loud:
#
#    THE CALL     the moment the clash decides, the word lands across the
#                 middle of the screen, in its own colour, for
#                 `side_call_seconds`.
#    THE BANNER   and then it STAYS, as a strip pinned above the row of
#                 cards, for the whole of the draft. It says which tier you
#                 are choosing and which way round you are, and it says the
#                 second thing in the same colour and the same words.
#
#  It is a CanvasLayer of its own so it sits over the pitch and under the
#  windows, and it is removed when the draft ends.
#
#  ============ WHY IT SAYS WHAT IT SAYS ============
#
#  "ATTACKING" and "DEFENDING" rather than "you attack" — a single word reads
#  from the corner of your eye, and this is a thing you should be able to
#  read without looking at it. (24 Oct 2026: the small line under it that
#  said which number counts is gone, Anthony's call. The word sits centred
#  on a flag now, see THE FLAG below.)
# =============================================================

# THE COLOURS LIVE IN THE PALETTE, not here. The team sheet tags a Star's
# attack and defence abilities with the same two, so the strip above the
# cards and the sheet before kick-off teach each other. See MenuSupport.
static func attack_colour() -> Color:
	return MenuSupport.COLOUR_ATTACK


static func defend_colour() -> Color:
	return MenuSupport.COLOUR_DEFEND

var attacking := true
var tier := ""

## ============ THE FLAG (24 Oct 2026) ============
##
## Anthony picked the waving flag on a pole (look B of four free drafts:
## /mnt/project-files/art_tool/side_banner/). Red cloth when you attack,
## blue when you defend, the tier on a cream patch sewn on by the pole, and
## the one word centred on the cloth. No small line under it any more.
##
## The pictures are named in Tuning.csv (side_banner_art_attack / _defend);
## a blank or missing picture falls back to the old dark strip.
const FLAG_ATTACK := "res://assets/ui/side_banner/flag_attack.png"
const FLAG_DEFEND := "res://assets/ui/side_banner/flag_defend.png"
# The same flags without the tier patch, for the big call in the middle.
const CALL_ATTACK := "res://assets/ui/side_banner/flag_attack_plain.png"
const CALL_DEFEND := "res://assets/ui/side_banner/flag_defend_plain.png"
# Where the words sit on the flag picture, as fractions of its size.
const PATCH_X := 0.126
const CLOTH_LEFT := 0.037
const CLOTH_RIGHT := 0.99
const WORD_Y := 0.522
const TIER_WORD_Y := 0.444
const TIER_NUMBER_Y := 0.578
const INK := Color(0.10, 0.07, 0.04)
const CREAM := Color(0.98, 0.94, 0.84)

var _strip: Control
var _flag: TextureRect
var _tier_word: Label
var _tier_number: Label
var _word: Label
var _call: CanvasLayer


static func make(on: Node) -> SideBanner:
	var found := find_on(on)
	if found != null:
		return found
	var made := SideBanner.new()
	made.name = "SideBanner"
	on.add_child(made)
	return made


static func find_on(node: Node) -> SideBanner:
	for child in node.get_children():
		if child is SideBanner:
			return child as SideBanner
	return null


func _ready() -> void:
	# Over the pitch, under a dialog (180) and under the pause menu (200).
	layer = 120
	_build()


# =============================================================
#  THE FLAG
# =============================================================

static func flag_texture(is_attacking: bool, plain: bool = false) -> Texture2D:
	var db := CardDatabase.get_db()
	var path := FLAG_ATTACK if is_attacking else FLAG_DEFEND
	var key := "side_banner_art_attack" if is_attacking else "side_banner_art_defend"
	if plain:
		path = CALL_ATTACK if is_attacking else CALL_DEFEND
		key = "side_call_art_attack" if is_attacking else "side_call_art_defend"
	if db != null:
		path = db.tune_text(key, path)
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


## One flag with its words on, `width` pixels wide. With a tier it is the
## strip (patch by the pole); without one it is the plain flag of the big
## call, the word centred on the whole cloth.
static func make_flag(is_attacking: bool, width: float, word: String, tier_key: String = "") -> Control:
	var tex := flag_texture(is_attacking, tier_key == "")
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.set_meta(TextBackdrop.NO_PLATES, true)
	if tex == null:
		return holder
	var box := Vector2(width, width * float(tex.get_height()) / float(tex.get_width()))
	holder.custom_minimum_size = box
	holder.size = box
	var flag := TextureRect.new()
	flag.name = "Flag"
	flag.texture = tex
	flag.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	flag.stretch_mode = TextureRect.STRETCH_SCALE
	flag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flag.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(flag)
	var main := attack_colour_flag() if is_attacking else defend_colour_flag()
	# The word, centred on the cloth right of the patch (or on all of it).
	var cloth_left := box.x * (PATCH_X * 2.0) if tier_key != "" else box.x * CLOTH_LEFT
	_flag_label(holder, "Word", word, Rect2(cloth_left, box.y * 0.22,
			box.x * CLOTH_RIGHT - cloth_left, box.y * 0.6), WORD_Y, box, 0.34, CREAM, true)
	if tier_key != "":
		var patch := Rect2(box.x * PATCH_X - box.x * 0.07, 0.0, box.x * 0.14, box.y)
		_flag_label(holder, "TierWord", Loc.text("tier", "TIER"), patch, TIER_WORD_Y, box, 0.085, main, false)
		_flag_label(holder, "TierNumber", tier_key, patch, TIER_NUMBER_Y, box, 0.17, INK, false)
	return holder


static func _flag_label(on: Control, label_name: String, words: String, area: Rect2,
		centre_y: float, box: Vector2, height: float, colour: Color, outlined: bool) -> Label:
	var label := Label.new()
	label.name = label_name
	label.text = words
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	label.add_theme_constant_override("shadow_outline_size", 0)
	label.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	var font_size := maxi(8, int(box.y * height))
	var font := label.get_theme_font("font")
	if font != null:
		# A long word is made smaller rather than spilling off the cloth.
		var wide := font.get_string_size(words, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		if wide > area.size.x * 0.94:
			font_size = maxi(8, int(font_size * area.size.x * 0.94 / wide))
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_constant_override("outline_size", 0)
	var tall := box.y * 0.5
	label.position = Vector2(area.position.x, box.y * centre_y - tall * 0.5)
	label.size = Vector2(area.size.x, tall)
	if outlined:
		# A thick ink edge, like every word on the drawn signs. The game font
		# is a bitmap font, which Godot cannot outline, so it is the same word
		# in ink, laid behind it in a ring.
		var edge := maxf(2.0, font_size * 0.07)
		for step in 16:
			var turn := TAU * float(step) / 16.0
			var ink := label.duplicate() as Label
			ink.name = "%sInk%d" % [label_name, step]
			ink.add_theme_color_override("font_color", INK)
			ink.position += Vector2(cos(turn), sin(turn)) * edge
			on.add_child(ink)
	on.add_child(label)
	return label


# The cloth colours, for the TIER word on the patch.
static func attack_colour_flag() -> Color:
	return Color(0.84, 0.20, 0.13)


static func defend_colour_flag() -> Color:
	return Color(0.14, 0.41, 0.77)


func _build() -> void:
	_strip = Control.new()
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_strip)


## Tell it the round's shape. Called once when the clash decides.
func set_side(is_attacking: bool) -> void:
	attacking = is_attacking
	_repaint()


## Tell it which tier is being chosen. Called at the top of every phase.
func set_tier(tier_key: String) -> void:
	tier = tier_key
	_repaint()


func _repaint() -> void:
	if _strip == null:
		return
	for child in _strip.get_children():
		_strip.remove_child(child)
		child.queue_free()
	var word := Loc.text("attacking", "ATTACKING") if attacking \
		else Loc.text("defending", "DEFENDING")
	var db := CardDatabase.get_db()
	var width := db.tune_float("side_banner_width", 640.0) if db != null else 640.0
	var flag := make_flag(attacking, width, word, tier)
	if flag.get_child_count() == 0:
		flag.queue_free()
		_old_strip(word)
	else:
		_strip.add_child(flag)
		_strip.size = flag.size
	_place()


## No flag picture: the dark strip it used to be.
func _old_strip(word: String) -> void:
	var tint := attack_colour() if attacking else defend_colour()
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel",
		MenuSupport.panel_style(Color(0.06, 0.07, 0.10, 0.94), tint))
	var label := Label.new()
	label.text = (("TIER %s    " % tier) if tier != "" else "") + word
	label.add_theme_font_size_override("font_size", 30)
	label.add_theme_color_override("font_color", tint)
	panel.add_child(label)
	_strip.add_child(panel)
	panel.reset_size()
	_strip.size = panel.size


## Pinned above the row of cards, centred, never off the top of the window.
## Re-placed on every repaint because the window can be resized mid-match.
func _place() -> void:
	if _strip == null:
		return
	var db := CardDatabase.get_db()
	var row_y := 0.5
	var card_box := PlayerCardUI.card_size()
	var lift := 150.0
	var top_gap := 4.0
	if db != null:
		row_y = db.tune_float("card_row_y", 0.5)
		lift = db.tune_float("side_banner_lift", 150.0)
		top_gap = db.tune_float("side_banner_top_gap", 4.0)
	var view := get_viewport().get_visible_rect().size if get_viewport() != null \
		else Vector2(1920, 1080)
	var box := _strip.size
	var bottom := view.y * row_y - card_box.y * 0.5 - lift
	var top := maxf(top_gap, bottom - box.y)
	_strip.position = Vector2((view.x - box.x) * 0.5, top)


func hide_it() -> void:
	visible = false


func show_it() -> void:
	visible = true
	_place()


# =============================================================
#  THE CALL: the same flag, big, in the middle of the screen
# =============================================================

## Shows "YOU ARE ATTACKING" (or DEFENDING) on a big flag for `seconds`.
## Returns false when there is no flag picture, so the caller can fall back
## to the plain coloured words.
func call_out(is_attacking: bool, word: String, seconds: float) -> bool:
	var db := CardDatabase.get_db()
	var width := db.tune_float("side_call_width", 1100.0) if db != null else 1100.0
	var flag := make_flag(is_attacking, width, word)
	if flag.get_child_count() == 0:
		flag.queue_free()
		return false
	if _call != null and is_instance_valid(_call):
		_call.queue_free()
	# Its own layer, just over the strip, so it shows even while the strip
	# itself is hidden.
	var layer_node := CanvasLayer.new()
	layer_node.layer = layer + 1
	_call = layer_node
	get_parent().add_child(layer_node)
	layer_node.add_child(flag)
	var view := get_viewport().get_visible_rect().size
	flag.position = (view - flag.size) * 0.5
	flag.pivot_offset = flag.size * 0.5
	flag.scale = Vector2(0.6, 0.6)
	var grow := flag.create_tween()
	grow.tween_property(flag, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(seconds).timeout
	if is_instance_valid(layer_node):
		layer_node.queue_free()
	return true
