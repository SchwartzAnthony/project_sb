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

## The size used when Tuning.csv has nothing to say. Bigger than the old
## hand-built card on purpose — this is the size you asked for.
const DEFAULT_SIZE := Vector2(220.0, 290.0)

var current_data: PlayerData

## True while AUTO is playing for you. A locked card cannot be clicked and
## is drawn faded, so it is obvious the game is choosing rather than you.
var locked: bool = false

var _face: Button


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

	_apply_lock()


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
