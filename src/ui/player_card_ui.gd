class_name PlayerCardUI
extends Control

# =============================================================
#  THE CARD YOU CLICK DURING A MATCH
#
#  ============ IT IS THE SAME CARD EVERYWHERE NOW ============
#
#  This used to be a hand-laid-out scene — a Panel with a NameLabel, an
#  Artwork and a StatsLabel nailed to fixed positions — which meant the card
#  on the pitch never quite matched the card in the team builder or the card
#  in the Adventure fight. Three screens, three looks, one player.
#
#  It draws itself with MenuSupport.card_face() now, which is the one face
#  all three screens use. Change that function and all three change together.
#
#  ============ HOW BIG IS IT? ============
#
#  Two rows of res://data/Tuning.csv, and nothing else:
#
#      card_width     220
#      card_height    290
#
#  Type a bigger number, press F5, the cards on the pitch are bigger. There
#  is no scene to open and no code to touch. The portrait, the name, the
#  numbers and the Star badge all scale with it.
#
#  ============ WHAT IT STILL DOES ============
#
#  Exactly what it did before, so nothing else in the match had to change:
#    card_hovered / card_unhovered   the stats panel follows your mouse
#    card_selected                   you picked this player
#    set_locked(true)                AUTO is playing; the card greys and
#                                    stops answering the mouse
# =============================================================

signal card_hovered(data: PlayerData)
signal card_unhovered(data: PlayerData)
signal card_selected(data: PlayerData)
## The little flask in the corner was pressed — somebody wants to pour
## something on this card before choosing it. main_scene opens the Inventory.
signal brew_wanted(data: PlayerData)

## The size used when Tuning.csv has nothing to say. Bigger than the old
## hand-built card on purpose — this is the size you asked for.
const DEFAULT_SIZE := Vector2(220.0, 290.0)

var current_data: PlayerData

## True while AUTO is playing for you. A locked card cannot be clicked and
## is drawn faded, so it is obvious the game is choosing rather than you.
var locked: bool = false

var _face: Button
## The little flask, top left. Null when draft_brew_button is off.
var _flask: Button


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The card may be created a frame before setup_card() is called, so give
	# it its footprint straight away — otherwise the row of cards jumps about
	# as each one is filled in.
	custom_minimum_size = card_size()
	_apply_lock()


## The card's footprint, from Tuning.csv. One place, read by every screen
## that shows a match card.
static func card_size() -> Vector2:
	var db := CardDatabase.get_db()
	if db == null:
		return DEFAULT_SIZE
	return Vector2(
		db.tune_float("card_width", DEFAULT_SIZE.x),
		db.tune_float("card_height", DEFAULT_SIZE.y))


func setup_card(data: PlayerData) -> void:
	current_data = data

	for child in get_children():
		child.queue_free()

	var box := card_size()
	custom_minimum_size = box
	size = box

	# THE SHARED FACE. Portrait, name, tier and the two powers, drawn the same
	# way the builder and the Adventure fight draw them.
	_face = MenuSupport.card_face(data, CardDatabase.get_db(), box)
	_face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_face)

	_face.mouse_entered.connect(_on_mouse_entered)
	_face.mouse_exited.connect(_on_mouse_exited)
	_face.pressed.connect(_on_pressed)

	_add_brew_corner(box)
	_apply_lock()


## ============ THE FLASK IN THE CORNER ============
##
## A small second button on top of the card. Pressing the card CHOOSES the
## player; pressing the flask opens the bag and uses something on them first.
##
## Only things tagged `match_consume` in Items.csv can be used here, and using
## one SPENDS it. Nothing is made — a bottled brew is made at the Brewery and
## carried; this is where the bottle is opened.
##
## It has to be a separate button rather than a right-click or a long press,
## because both of those are invisible — nobody discovers a gesture nobody
## told them about, and a card that quietly does two different things
## depending on which mouse button you used is worse than a card with a
## second button on it.
##
## `draft_brew_button` in Tuning.csv takes it off the cards entirely.
func _add_brew_corner(_box: Vector2) -> void:
	var db := CardDatabase.get_db()
	if db != null and not db.tune_bool("draft_brew_button", true):
		return

	_flask = Button.new()
	_flask.text = "⚗"
	_flask.tooltip_text = "Use something on this player before you choose them.\nOnly items tagged match_consume in Items.csv — a bottled brew, say.\nIt wears off at the final whistle."
	_flask.focus_mode = Control.FOCUS_NONE
	_flask.custom_minimum_size = Vector2(30, 30)
	# TOP LEFT, because the Star badge is top right. Two things in one corner
	# is how a Star card ends up with a flask drawn over its badge.
	#
	# Plain offsets from the top-left corner rather than an anchor preset: a
	# TOP_RIGHT preset measures its offsets from the RIGHT edge, so the same
	# numbers would put this a card's width off the side of the card.
	_flask.offset_left = 6.0
	_flask.offset_top = 6.0
	_flask.offset_right = 36.0
	_flask.offset_bottom = 36.0
	_flask.add_theme_font_size_override("font_size", 16)
	_flask.add_theme_stylebox_override("normal", MenuSupport.panel_style(
		MenuSupport.COLOUR_PANEL, MenuSupport.COLOUR_TEXT_DIM))
	_flask.add_theme_stylebox_override("hover", MenuSupport.panel_style(
		MenuSupport.COLOUR_SLOT_EMPTY, MenuSupport.COLOUR_ACCENT))
	_flask.add_theme_stylebox_override("pressed", MenuSupport.panel_style(
		MenuSupport.COLOUR_SLOT_EMPTY, MenuSupport.COLOUR_ACCENT))
	_flask.pressed.connect(func() -> void:
		if current_data != null and not locked:
			brew_wanted.emit(current_data))
	add_child(_flask)


## Called by main_scene whenever AUTO is switched on or off, and once when
## the card is created. Safe to call before setup_card(): it checks.
func set_locked(is_locked: bool) -> void:
	locked = is_locked
	_apply_lock()


func _apply_lock() -> void:
	if _face == null:
		return
	_face.disabled = locked
	# MOUSE_FILTER_IGNORE as well as disabled, so a locked card does not eat
	# the hover either — the stats panel should not follow a card you cannot
	# choose.
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE if locked \
		else Control.MOUSE_FILTER_STOP
	if _flask != null and is_instance_valid(_flask):
		_flask.disabled = locked
		_flask.visible = not locked
	modulate = Color(1, 1, 1, 0.45) if locked else Color(1, 1, 1, 1)


func _on_mouse_entered() -> void:
	if current_data:
		card_hovered.emit(current_data)


func _on_mouse_exited() -> void:
	if current_data:
		card_unhovered.emit(current_data)


func _on_pressed() -> void:
	if current_data:
		card_selected.emit(current_data)
