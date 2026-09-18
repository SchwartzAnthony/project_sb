class_name NamePlate
extends Node2D

# =============================================================
#  THE NAMEPLATE — one player, labelled the same way everywhere
#
#  A player is drawn in two completely different scenes: the league pitch
#  and the Adventure scroll. They were labelled differently in each, which
#  meant the same card read as two different things depending on which mode
#  you were in. This is the one description of how a player is labelled, and
#  both modes now ask it.
#
#  ============ THE SHAPE ============
#
#            Silver-Rhine Lorelei        <- the NAME, over the head, centred
#                  ,---.
#                 ( o o )                <- the artwork
#                  `-^-'
#            Tier I         P: 2         <- at the feet. Tier left, power right
#            [============    ]          <- the stamina bar, hugging them
#
#  THE BAR IS ADVENTURE ONLY. A league player has no stamina — only the
#  keeper does — so there is nothing to draw one from, and a bar under every
#  player on the pitch would be twenty-two bars saying the same thing.
#
#  ============ WHY IT MEASURES THE ARTWORK ============
#
#  A card's spritesheet frame is mostly empty. The drawn character sits
#  somewhere in the middle of it with a lot of transparent padding, and how
#  much padding differs from sheet to sheet.
#
#  Placing a label from the FRAME meant placing it from the padding — which
#  is why the stamina bar floated a long way under a player's feet and the
#  cross over a fallen one sat well above their head. Neither was wrong
#  arithmetic; both were measuring the wrong thing.
#
#  box_of() reads the frame ONCE and finds the rectangle the character
#  actually occupies. Everything is placed from that, so a label hugs the
#  drawn body whatever the padding is, and it keeps working when you replace
#  the art.
#
#  ============ WHY IT IS A NODE AND NOT A DRAW CALL ============
#
#  It used to draw its text with draw_string() straight onto the player. That
#  looks identical at full size and goes to mush the moment the window is made
#  smaller, because the project stretches the canvas (`canvas_items`) and
#  Godot only oversamples fonts for real Label nodes — a string drawn by hand
#  in _draw() is rasterised at its written size and then scaled down with
#  everything else.
#
#  So the words are three Labels that this node owns, and only the things that
#  scale cleanly — the dark panel, the stamina bar, the cross — are still
#  drawn. The arithmetic below is exactly what it was; only who puts the
#  glyphs on the screen has changed.
#
#  ============ TUNING ============
#
#      plate_name_size      the name over the head
#      plate_stat_size      the Tier and the Power at the feet
#      plate_gap            pixels between the body and the first label
#      plate_names          false hides every name in both modes
#      adventure_bar_gap    the stamina bar's gap under the stats
# =============================================================


## Where the drawn character actually sits inside a texture, as a fraction of
## that texture — {0,0,1,1} for art that fills its frame, something smaller
## for art with padding around it.
##
## MEASURED ONCE AND REMEMBERED on the texture itself, because reading an
## image back off the GPU is not something to do every frame.
static func box_of(texture: Texture2D) -> Rect2:
	if texture == null:
		return Rect2(0, 0, 1, 1)
	if texture.has_meta("opaque_box"):
		return texture.get_meta("opaque_box")

	var found := Rect2(0, 0, 1, 1)
	var image := texture.get_image()
	if image != null:
		if image.is_compressed():
			image.decompress()
		var used := image.get_used_rect()
		var whole := Vector2(maxf(1.0, float(image.get_width())),
			maxf(1.0, float(image.get_height())))
		if used.size.x > 0 and used.size.y > 0:
			found = Rect2(float(used.position.x) / whole.x,
				float(used.position.y) / whole.y,
				float(used.size.x) / whole.x,
				float(used.size.y) / whole.y)
	texture.set_meta("opaque_box", found)
	return found


## The four numbers a caller needs, in the caller's own coordinates.
##
##   `top`     the top of the drawn character
##   `bottom`  the bottom of it — their feet
##   `left`    / `right`  the sides of it
##
## `box` is what box_of() returned; `at` and `size` are where the artwork is
## being drawn and how big it is.
static func edges(box: Rect2, at: Vector2, size: Vector2) -> Dictionary:
	return {
		"top": at.y + box.position.y * size.y,
		"bottom": at.y + (box.position.y + box.size.y) * size.y,
		"left": at.x + box.position.x * size.x,
		"right": at.x + (box.position.x + box.size.x) * size.x,
		"middle": at.x + (box.position.x + box.size.x * 0.5) * size.x,
	}




# =============================================================
#  THE NODE ITSELF
#
#  Add one as a child of whatever is being labelled, then call place() from
#  that thing's _draw() — or whenever what it says changes. The Labels are
#  built once; place() only moves them and rewrites them.
# =============================================================

var _name_label: Label
var _tier_label: Label
var _power_label: Label

# Worked out by place() and used by _draw(), which is the only reason these
# are members: a _draw() cannot be handed arguments.
var _panel := Rect2()
var _bar := Rect2()
var _fill := Rect2()
var _tint := Color(1, 1, 1)
var _bar_colour := Color(1, 1, 1)
var _down := false
var _cross_at := Vector2.ZERO
var _cross_span := 0.0
var _show_bar := false
var _show_cross := false


static func make() -> NamePlate:
	var plate := NamePlate.new()
	plate.name = "NamePlate"
	return plate


func _ready() -> void:
	# ON TOP OF THE PLAYER, not behind them. A plate drawn under the artwork
	# is a plate you cannot read.
	z_index = 4
	_name_label = _label(13)
	_tier_label = _label(11)
	_power_label = _label(11)


func _label(size: int) -> Label:
	var made := Label.new()
	made.mouse_filter = Control.MOUSE_FILTER_IGNORE
	made.add_theme_font_size_override("font_size", size)
	# The dark edge that keeps a name readable over grass, over a white shirt
	# and over a background you have not drawn yet. It was four draw_string
	# calls before; it is one theme override now.
	made.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	made.add_theme_constant_override("shadow_outline_size", 3)
	made.add_theme_constant_override("shadow_offset_x", 0)
	made.add_theme_constant_override("shadow_offset_y", 0)
	add_child(made)
	return made


## Put the plate where the caller says, in the caller's own coordinates.
##
##   edge      what edges() gave back
##   card      who this is
##   fraction  0 to 1 of stamina, or -1 for "this mode has no stamina"
##   down      true for a player who is out — the name greys and a cross goes
##             over the middle of them rather than over their head
func place(edge: Dictionary, card: PlayerData,
		fraction: float = -1.0, down: bool = false) -> void:
	if card == null or _name_label == null:
		return

	var db := CardDatabase.get_db()
	var wanted := db == null or db.tune_bool("plate_names", true)
	visible = wanted
	if not wanted:
		return

	var name_size := 13
	var stat_size := 11
	var gap := 5.0
	var widest := 150.0
	var name_room_scale := 1.0
	var bar_gap := 3.0
	if db != null:
		name_size = db.tune_int("plate_name_size", 13)
		stat_size = db.tune_int("plate_stat_size", 11)
		gap = db.tune_float("plate_gap", 5.0)
		widest = db.tune_float("plate_width_max", 150.0)
		name_room_scale = maxf(0.5, db.tune_float("plate_name_width", 1.0))
		bar_gap = db.tune_float("adventure_bar_gap", 3.0)

	var top: float = edge["top"]
	var bottom: float = edge["bottom"]
	var middle: float = edge["middle"]

	_down = down
	_tint = MenuSupport.colour_for_tier(card.get_tier_clean())
	var ink: Color = MenuSupport.COLOUR_TEXT if not down else Color(0.66, 0.58, 0.58)

	# ============ HOW WIDE THE PLATE IS ============
	#
	# NOT the width of the player. A drawn character is about thirty pixels
	# across and "Tier I" and "P: 2" together are ninety, so hanging one off
	# the left edge of the body and the other off the right edge put them on
	# top of each other — which is how "P: 2 III" happened.
	#
	# The plate is as wide as its CONTENTS need, centred on the body, and
	# never wider than plate_width_max. So it is the same size for every
	# player whatever their artwork, and the two stats always have room.
	var tier_text := "Tier %s%s" % [card.get_tier_clean(), " ★" if card.is_star() else ""]
	var power_text := "P: %d" % card.get_attack_power()

	_tier_label.add_theme_font_size_override("font_size", stat_size)
	_power_label.add_theme_font_size_override("font_size", stat_size)
	_name_label.add_theme_font_size_override("font_size", name_size)

	_tier_label.text = tier_text
	_power_label.text = power_text
	var tier_wide := _tier_label.get_minimum_size().x
	var power_wide := _power_label.get_minimum_size().x
	var pad := 6.0
	var plate_wide := clampf(tier_wide + power_wide + pad * 3.0, 54.0, widest)
	var left := middle - plate_wide * 0.5
	var right := middle + plate_wide * 0.5

	# ============ THE NAME ============
	#
	# A SHORT NAME. Your cards are called "Songbound Shore Lorelei" — the
	# class is on the end of every one of them, and it is already obvious
	# from the player standing there. The full name is still on the card, in
	# the log and in the team builder.
	#
	# AND NO WIDER THAN THE WINDOW UNDER IT, or in a crowd the names collide
	# while the windows underneath them sit neatly side by side.
	var name_room := plate_wide * name_room_scale
	var label := short_name(card)
	_name_label.text = label
	while _name_label.get_minimum_size().x > name_room and label.length() > 4:
		label = label.substr(0, label.length() - 2) + "…"
		_name_label.text = label
	var name_size_box := _name_label.get_minimum_size()
	_name_label.position = Vector2(middle - name_size_box.x * 0.5,
		top - gap - name_size_box.y)
	_name_label.add_theme_color_override("font_color", ink)

	# ============ THE LITTLE WINDOW AT THEIR FEET ============
	var line_high := float(stat_size) + 4.0
	var bar_high := 0.0
	_show_bar = fraction >= 0.0
	if _show_bar:
		bar_high = maxf(4.0, float(stat_size) * 0.42)

	var panel_top := bottom + gap
	var panel_high := line_high + (bar_high + bar_gap if _show_bar else 0.0) + 4.0
	_panel = Rect2(Vector2(left, panel_top), Vector2(plate_wide, panel_high))

	var text_y := panel_top + 1.0
	_tier_label.position = Vector2(left + pad, text_y)
	_power_label.position = Vector2(right - pad - power_wide, text_y)
	_tier_label.add_theme_color_override("font_color",
		_tint.lightened(0.35) if not down else ink)
	_power_label.add_theme_color_override("font_color",
		MenuSupport.COLOUR_ACCENT if not down else ink)

	if _show_bar:
		_bar = Rect2(Vector2(left + pad, text_y + line_high + bar_gap),
			Vector2(plate_wide - pad * 2.0, bar_high))
		_fill = _bar
		_fill.size.x = _bar.size.x * clampf(fraction, 0.0, 1.0)
		# Green, amber, red. Read at a glance, no numbers.
		_bar_colour = Color(0.45, 0.78, 0.45)
		if fraction < 0.34:
			_bar_colour = Color(0.85, 0.35, 0.32)
		elif fraction < 0.67:
			_bar_colour = Color(0.88, 0.68, 0.32)

	queue_redraw()


## A cross over a fallen player. The caller says where the middle of them is,
## because only the caller knows whether they are standing or lying down.
func mark_down(middle: Vector2, span: float) -> void:
	_show_cross = true
	_cross_at = middle
	_cross_span = span
	queue_redraw()


func clear_down_mark() -> void:
	if not _show_cross:
		return
	_show_cross = false
	queue_redraw()


func _draw() -> void:
	# ONLY THE THINGS THAT SCALE CLEANLY. Rectangles and lines look the same
	# at any window size; text does not, which is what the Labels are for.
	if _panel.size.x > 0.0:
		draw_rect(_panel, Color(0.06, 0.07, 0.10, 0.78), true)
		draw_rect(_panel, Color(_tint.r, _tint.g, _tint.b,
			0.55 if not _down else 0.25), false, 1.0)

	if _show_bar and _bar.size.x > 0.0:
		draw_rect(_bar, Color(0.10, 0.11, 0.14, 0.95), true)
		if not _down and _fill.size.x > 0.0:
			draw_rect(_fill, _bar_colour, true)

	if _show_cross:
		var dead := Color(0.90, 0.38, 0.36)
		draw_line(_cross_at + Vector2(-_cross_span, -_cross_span),
			_cross_at + Vector2(_cross_span, _cross_span), dead, 3.0)
		draw_line(_cross_at + Vector2(-_cross_span, _cross_span),
			_cross_at + Vector2(_cross_span, -_cross_span), dead, 3.0)


## A card's name with the class taken off the end of it.
##
## "Songbound Shore Lorelei" -> "Songbound Shore". The class is on the end of
## every card in a set and it is already obvious from who is standing there,
## so on the pitch it is eight wasted characters per player.
##
## A name that IS just the class is left alone, and so is one that does not
## end in it — nothing is ever reduced to nothing.
static func short_name(card: PlayerData) -> String:
	if card == null:
		return ""
	var full := card.player_name.strip_edges()
	var klass := card.unit_type.strip_edges()
	if klass == "" or full.to_lower() == klass.to_lower():
		return full
	if full.to_lower().ends_with(" " + klass.to_lower()):
		var cut := full.substr(0, full.length() - klass.length() - 1).strip_edges()
		if cut != "":
			return cut
	return full
