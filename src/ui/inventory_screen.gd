class_name InventoryScreen
extends CanvasLayer

# =============================================================
#  THE INVENTORY — one bag, opened from everywhere
#
#  A window with up to three tabs and a grid of square buttons. Each button is the
#  thing's picture with how many you have in the corner; pointing at one
#  writes what it is in the panel underneath. Nothing is labelled, because
#  forty labelled tiles is a wall of words and forty pictures is a bag.
#
#      ITEMS      things you USE — a bottled brew, a bandage, smelling salts
#      RESOURCES  things you SPEND — reed, bog iron, coins
#      KEYS       things you HOLD — a key, a token, a letter
#
#  WHICH TABS SHOW is Tuning.csv `inventory_tabs` (round AN: "items;resources",
#  Anthony took the Keys tab out). A key is still carried and still opens its
#  gate; it is only not listed. Put `keys` back in that row to list them again.
#
#  Which tab a row lands in is decided by Items.csv: the `Tab` column if you
#  filled it in, worked out from `Kind` if you did not. See
#  AdventureDB.tab_of(), which is the only place that rule is written down.
#
#  ============ IT IS THE SAME WINDOW EVERYWHERE ============
#
#  The base, the Bounty Board, an Adventure fight and the match draft all
#  open THIS. They differ only in what a click means, and that is one
#  argument:
#
#      open(on, state, Use.NOTHING)   a reckoning. Nothing is clickable
#      open(on, state, Use.ITEM)      an item may be used — `used` fires
#      open(on, state, Use.ON_CARD)   pick something to use ON A CARD, for
#                                     the draft. `used` fires and the caller
#                                     applies it to the card it had in mind
#
#  WHAT IS CLICKABLE IS DECIDED BY THE `Tags` COLUMN, not by the screen —
#  `adventure_consume` out in a fight, `match_consume` on a card. Most things
#  have neither and are taken at the bar before the team sets off.
#
#  ============ WHY THERE IS NO SEPARATE KIT SCREEN ============
#
#  There used to be one, called YOUR KIT, that listed usable items as lines
#  of text. It showed a third of what you were carrying and it was the only
#  place in the game that looked like that. Everything it did this does.
# =============================================================

enum Use { NOTHING, ITEM, ON_CARD }

## Somebody pressed a thing they can use. `entry` is the row out of Items.csv
## with `held` on top of it — how many you are carrying.
signal used(entry: Dictionary)

const TAB_WORDS := {
	"items": "ITEMS",
	"resources": "RESOURCES",
	"keys": "KEYS",
}

var state: GameState
var mode: int = Use.NOTHING
## Words under the title. The draft puts the card's name here, so it is
## obvious what the brew is about to be poured on.
var subtitle := ""

var _bag: Dictionary = {}
var _tab := "items"
var _grid: GridContainer
var _tab_buttons: Dictionary = {}
var _words: Label
var _title_line: Label


# =============================================================
#  OPENING IT
# =============================================================

## Build it, fill it and show it. Returns the screen so the caller can
## connect to `used` and, if it wants, put a line under the title.
static func open(on: Node, save: GameState, how: int = Use.NOTHING,
		under_title: String = "") -> InventoryScreen:
	var made := InventoryScreen.new()
	made.name = "InventoryScreen"
	made.state = save
	made.mode = how
	made.subtitle = under_title
	on.add_child(made)
	return made


func _ready() -> void:
	layer = 70
	_build()
	refresh()


func close() -> void:
	queue_free()


# =============================================================
#  BUILDING IT
# =============================================================

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.06, 0.74)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The dim catches clicks, so a stray click outside the window does not
	# land on the screen behind it.
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -360.0
	panel.offset_right = 360.0
	panel.offset_top = -280.0
	panel.offset_bottom = 280.0
	panel.add_theme_stylebox_override("panel", MenuSupport.panel_style(
		MenuSupport.COLOUR_PANEL, MenuSupport.COLOUR_ACCENT))
	dim.add_child(panel)

	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right"]:
		pad.add_theme_constant_override(side, 22)
	for side in ["margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 18)
	panel.add_child(pad)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	pad.add_child(column)

	column.add_child(MenuSupport.heading(
		Loc.text("inventory", "Inventory").to_upper(), 26, MenuSupport.COLOUR_ACCENT))

	_title_line = Label.new()
	_title_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_line.add_theme_font_size_override("font_size", 13)
	_title_line.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	_title_line.visible = subtitle != ""
	_title_line.text = subtitle
	column.add_child(_title_line)

	# --- the tabs (Tuning.csv inventory_tabs) ---
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 6)
	column.add_child(tabs)
	if not shown_tabs().has(_tab):
		_tab = shown_tabs()[0]
	for key in shown_tabs():
		var button := MenuSupport.tab_button(String(TAB_WORDS[key]), key == _tab)
		button.pressed.connect(_show_tab.bind(key))
		tabs.add_child(button)
		_tab_buttons[key] = button

	# --- the grid of things ---
	var scroller := ScrollContainer.new()
	scroller.custom_minimum_size = Vector2(0, 280)
	scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroller)

	# CENTRED, NOT LEFT-ALIGNED. Four things in a row seven wide would
	# otherwise huddle against the left edge of a window they do not fill.
	var centre_grid := CenterContainer.new()
	centre_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroller.add_child(centre_grid)

	_grid = GridContainer.new()
	_grid.columns = 7
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	centre_grid.add_child(_grid)

	# --- what you are pointing at ---
	var shelf := PanelContainer.new()
	shelf.custom_minimum_size = Vector2(0, 86)
	shelf.add_theme_stylebox_override("panel", MenuSupport.panel_style(
		MenuSupport.COLOUR_BACKGROUND, MenuSupport.COLOUR_TEXT_DIM))
	column.add_child(shelf)

	_words = Label.new()
	_words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_words.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_words.add_theme_font_size_override("font_size", 14)
	shelf.add_child(_words)

	var close_button := MenuSupport.icon_button("close|✕",
		Loc.text("close", "Close"), Vector2(200, 46))
	close_button.pressed.connect(close)
	var centre := CenterContainer.new()
	centre.add_child(close_button)
	column.add_child(centre)


## The tabs the window shows, in order: Tuning.csv `inventory_tabs`, words
## from AdventureDB.TABS split by `;`. Never empty - a blank or misspelt row
## shows all three, so the bag can never open with nothing to click.
static func shown_tabs() -> Array[String]:
	var out: Array[String] = []
	var said := "items;resources;keys"
	var book := CardDatabase.get_db()
	if book != null:
		said = book.tune_text("inventory_tabs", said)
	for part in said.split(";", false):
		var key := part.strip_edges().to_lower()
		if AdventureDB.TABS.has(key) and not out.has(key):
			out.append(key)
	if out.is_empty():
		out.assign(AdventureDB.TABS)
	return out


# =============================================================
#  FILLING IT
# =============================================================

## Read the save again and redraw. Called on open, and again after something
## has been used, so the count on a tile is never a lie.
func refresh() -> void:
	_bag = AdventureDB.get_db().bag(state)
	_show_tab(_tab)


func _show_tab(which: String) -> void:
	_tab = which if shown_tabs().has(which) else shown_tabs()[0]

	for key in _tab_buttons.keys():
		# The tab you are on is the lit one. Two looks, no third state.
		MenuSupport.paint_tab(_tab_buttons[key] as Button, String(key) == _tab)

	for child in _grid.get_children():
		child.queue_free()

	var things: Array = _bag.get(_tab, [])
	if things.is_empty():
		_words.text = _nothing_here()
		return

	_words.text = "Point at something to read what it is."
	for thing in things:
		_grid.add_child(_tile(thing as Dictionary))


## A line for an empty tab that says what WOULD be here, rather than the word
## "empty". An empty box that explains itself does not look broken.
func _nothing_here() -> String:
	match _tab:
		"items":
			return "Nothing to use yet. Brews are poured at the Pub; bandages and smelling salts drop from bosses."
		"resources":
			return "No materials yet. They come home from Adventure runs — that is what the runs are for."
		"keys":
			return "No keys yet. These are the things a story hands you and never takes back."
	return ""


func _tile(entry: Dictionary) -> Button:
	var usable := _can_use(entry)
	var tint := MenuSupport.COLOUR_ACCENT if usable else MenuSupport.COLOUR_TEXT_DIM
	var button := MenuSupport.slot_button(String(entry.get("art", "")),
		_glyph_for(entry), int(entry.get("held", 1)), Vector2(84, 84), tint)

	# ============ THE DESCRIPTION IS ON HOVER, NOT ON THE TILE ============
	#
	# Godot's own tooltip is a grey box that arrives a second late, over the
	# thing you are pointing at. This writes into the panel at the bottom of
	# the window instead: it is instant, it is always in the same place, and
	# it has room for a real sentence.
	var words := _describe(entry)
	button.mouse_entered.connect(func() -> void: _words.text = words)
	button.focus_entered.connect(func() -> void: _words.text = words)

	if not usable:
		return button

	button.pressed.connect(func() -> void:
		used.emit(entry)
		# THE CALLER DECIDES WHAT HAPPENS NEXT. On the draft it closes the
		# window and pours; in a fight it spends the item and stays open.
		# Either way the counts are re-read, so a tile can never show a
		# number that has already been spent.
		if is_instance_valid(self):
			refresh())
	return button


## ============ CAN THIS BE CLICKED HERE? ============
##
## Three things have to be true, and the third is the interesting one.
##
##   1. this screen allows using anything at all
##   2. the thing has a `Use`, and is therefore on the Items tab
##   3. it is TAGGED for the place you are standing
##
## Most things are taken at the bar before the team sets off, not in the
## middle of a wave and not out of a pocket during a match. So a bandage with
## no tag is a perfectly good item that simply cannot be used from here, and
## it is shown greyed with a line saying where it CAN be used rather than
## hidden or silently dead.
func _can_use(entry: Dictionary) -> bool:
	if mode == Use.NOTHING:
		return false
	if AdventureDB.tab_of(entry) != "items":
		return false
	if String(entry.get("use", "")).strip_edges() == "":
		return false
	if mode == Use.ITEM:
		return AdventureDB.has_tag(entry, "adventure_consume")
	return AdventureDB.has_tag(entry, "match_consume")


func _describe(entry: Dictionary) -> String:
	var lines: Array[String] = []
	var head := String(entry.get("name", "?"))
	var held := int(entry.get("held", 1))
	if held > 1:
		head += "   x%d" % held
	lines.append(head)

	var words := String(entry.get("description", "")).strip_edges()
	if words != "":
		lines.append(words)

	if _can_use(entry):
		lines.append("Click it to pour it on this card." if mode == Use.ON_CARD
			else "Click it to use it.")
	elif mode != Use.NOTHING and AdventureDB.tab_of(entry) == "items":
		lines.append(_where_it_goes(entry))
	return "\n".join(lines)


## Why a usable thing is not usable HERE. Never a bare "you cannot" — it says
## where it can be used instead, because that is the sentence the player
## actually needs.
func _where_it_goes(entry: Dictionary) -> String:
	var here := AdventureDB.has_tag(entry, "adventure_consume")
	var draft := AdventureDB.has_tag(entry, "match_consume")
	if mode == Use.ITEM and draft and not here:
		return "Not out here. This one goes on a player during a match."
	if mode == Use.ON_CARD and here and not draft:
		return "Not on a card. This one is used during an Adventure fight."
	return "Taken at the bar before the team sets off, not out on the pitch."


## The letter drawn on a tile whose art has not been made yet. It is not
## decoration — it is what makes a bag readable months before the icons exist.
func _glyph_for(entry: Dictionary) -> String:
	var name_text := String(entry.get("name", "?")).strip_edges()
	return name_text.substr(0, 1).to_upper() if name_text != "" else "?"
