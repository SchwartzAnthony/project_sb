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
#  read without looking at it. And under it, in small letters, the reason it
#  matters: which of the two numbers on a card is the one that counts.
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

var _strip: PanelContainer
var _tier_label: Label
var _side_label: Label
var _why_label: Label


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
#  THE STRIP
# =============================================================

func _build() -> void:
	_strip = PanelContainer.new()
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_strip)

	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right"]:
		pad.add_theme_constant_override(side, 26)
	for side in ["margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 8)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.add_child(pad)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 28)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(row)

	_tier_label = Label.new()
	_tier_label.add_theme_font_size_override("font_size", 22)
	_tier_label.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	_tier_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_tier_label)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(column)

	_side_label = Label.new()
	_side_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_side_label.add_theme_font_size_override("font_size", 30)
	column.add_child(_side_label)

	_why_label = Label.new()
	_why_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_why_label.add_theme_font_size_override("font_size", 13)
	_why_label.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	column.add_child(_why_label)


## Tell it the round's shape. Called once when the clash decides.
func set_side(is_attacking: bool) -> void:
	attacking = is_attacking
	_repaint()


## Tell it which tier is being chosen. Called at the top of every phase.
func set_tier(tier_key: String) -> void:
	tier = tier_key
	_repaint()


func _repaint() -> void:
	if _side_label == null:
		return
	var tint := attack_colour() if attacking else defend_colour()
	_side_label.text = Loc.text("attacking", "ATTACKING") if attacking \
		else Loc.text("defending", "DEFENDING")
	_side_label.add_theme_color_override("font_color", tint)
	# THE REASON IT MATTERS, in small letters. Which of the two numbers on a
	# card is the one being compared — that is the whole of why you need to
	# know, so it is said rather than left to be remembered.
	_why_label.text = "their defence is what beats you — pick on ATTACK" if attacking \
		else "their attack is what beats you — pick on DEFENCE"
	_tier_label.text = ("TIER %s" % tier) if tier != "" else ""
	_strip.add_theme_stylebox_override("panel",
		MenuSupport.panel_style(Color(0.06, 0.07, 0.10, 0.94), tint))
	_place()


## Pinned just above the row of cards, centred, the width of its contents.
## Re-placed on every repaint because the window can be resized mid-match.
func _place() -> void:
	if _strip == null:
		return
	var db := CardDatabase.get_db()
	var row_y := 0.5
	var card_box := PlayerCardUI.card_size()
	var lift := 150.0
	if db != null:
		row_y = db.tune_float("card_row_y", 0.5)
		lift = db.tune_float("side_banner_lift", 150.0)
	_strip.set_anchors_preset(Control.PRESET_TOP_WIDE, true)
	_strip.anchor_left = 0.5
	_strip.anchor_right = 0.5
	_strip.anchor_top = row_y
	_strip.anchor_bottom = row_y
	_strip.reset_size()
	var box := _strip.size
	_strip.offset_left = -box.x * 0.5
	_strip.offset_right = box.x * 0.5
	# ABOVE the cards, and above the reveal strip when that is up too.
	_strip.offset_bottom = -card_box.y * 0.5 - lift
	_strip.offset_top = _strip.offset_bottom - box.y


func hide_it() -> void:
	visible = false


func show_it() -> void:
	visible = true
	_place()
