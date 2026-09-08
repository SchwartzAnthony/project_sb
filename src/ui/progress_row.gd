class_name ProgressRow
extends VBoxContainer

# =============================================================
#  A PROGRESS BAR — fills up, and shines when it is finished
#
#  Used by the post-match screen and by the unlock board. It is one file so
#  that restyling the bars restyles them everywhere.
#
#      Master Brewer                              3 of 5
#      [==================>              ]
#      Brews drunk: 3 of 5
#
#  Nothing in here decides ANYTHING. It is handed a name, a fraction, a line
#  of text and whether it is done. All of that comes from unlock_progress.gd.
#
#  THE SHINE
#    A finished bar pulses gently rather than sitting still, because a
#    static full bar and a static nearly-full bar look the same at a glance.
#    It is a sine wave on the fill colour, and it costs nothing: a row that
#    is not shining turns its own _process off.
# =============================================================

const BAR_HEIGHT := 12.0
const CORNER := 4.0

var fraction: float = 0.0
var shining: bool = false

var _bar: Control
var _clock: float = 0.0

var _fill_colour := MenuSupport.COLOUR_ACCENT
var _track_colour := Color(0.10, 0.11, 0.14, 1.0)


## `value` is 0 to 1. `note` is the line under the bar — what is missing, or
## what you got. `right` is the small number on the right of the title.
func setup(title: String, value: float, right: String, note: String,
		is_done: bool) -> void:
	fraction = clampf(value, 0.0, 1.0)
	shining = is_done
	add_theme_constant_override("separation", 3)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	add_child(head)

	var name_label := Label.new()
	name_label.text = title
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color",
		MenuSupport.COLOUR_ACCENT if is_done else MenuSupport.COLOUR_TEXT)
	head.add_child(name_label)

	if right != "":
		var value_label := Label.new()
		value_label.text = right
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_label.add_theme_font_size_override("font_size", 14)
		value_label.add_theme_color_override("font_color",
			MenuSupport.COLOUR_ACCENT if is_done else MenuSupport.COLOUR_TEXT_DIM)
		head.add_child(value_label)

	_bar = Control.new()
	_bar.custom_minimum_size = Vector2(0, BAR_HEIGHT)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.draw.connect(_draw_bar)
	add_child(_bar)

	if note != "":
		var note_label := Label.new()
		note_label.text = note
		note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note_label.add_theme_font_size_override("font_size", 13)
		note_label.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
		add_child(note_label)

	# A bar that will never change does not need a frame-by-frame update.
	set_process(shining)


func _process(delta: float) -> void:
	_clock += delta
	if _bar != null:
		_bar.queue_redraw()


func _draw_bar() -> void:
	if _bar == null:
		return
	var box := Rect2(Vector2.ZERO, _bar.size)
	if box.size.x < 2.0:
		return

	_bar.draw_rect(box, _track_colour, true)

	var filled := box
	filled.size.x = box.size.x * fraction
	if filled.size.x < 1.0:
		return

	var colour := _fill_colour
	if shining:
		# 0.78 to 1.0 and back, about three times a second. Enough to read as
		# "this one is finished" without being a distraction.
		var pulse := 0.89 + 0.11 * sin(_clock * 6.0)
		colour = Color(_fill_colour.r * pulse + (1.0 - pulse),
			_fill_colour.g * pulse + (1.0 - pulse) * 0.95,
			_fill_colour.b * pulse + (1.0 - pulse) * 0.75, 1.0)
	_bar.draw_rect(filled, colour, true)

	# A brighter cap on the leading edge, so a part-filled bar has an end to
	# it rather than fading into the track.
	if fraction < 0.999:
		var cap := Rect2(Vector2(filled.size.x - 2.0, 0.0), Vector2(2.0, box.size.y))
		_bar.draw_rect(cap, colour.lightened(0.35), true)
