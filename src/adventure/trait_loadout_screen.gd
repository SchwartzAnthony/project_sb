class_name TraitLoadoutScreen
extends CanvasLayer

# =============================================================
#  EDIT ELEMENT BONUS — which eight icons go into a run
#
#  You may write forty icons in AdventureTraits.csv and unlock every one of
#  them. Only EIGHT are carried — `adventure_trait_slots` in Tuning.csv — and
#  this is where the player says which eight.
#
#  An icon that is not in the eight does NOTHING: no bar along the top, no
#  icons on the pile, no breakpoints. It is not a smaller bonus, it is not
#  there. That is what makes this a decision rather than a settings page, and
#  it is why the screen says how many are left rather than quietly refusing.
#
#  ============ HOW IT READS ============
#
#  Every icon you have unlocked is on the shelf. The ones you are carrying
#  are lit and numbered; the rest are grey. Clicking a lit one puts it back,
#  clicking a grey one takes it — and once you have eight, the grey ones say
#  so rather than doing nothing.
#
#  ============ WHERE THE CHOICE LIVES ============
#
#  One line of text in the save: TraitDB.LOADOUT_KEY. Not in a CSV — it is
#  the player's decision, not the designer's. What the DESIGNER decides is
#  which icons exist, what they do, and what has to be unlocked before one
#  can be chosen at all, and all three of those are in AdventureTraits.csv.
# =============================================================

var state: GameState
var db: CardDatabase

var _room := 8
var _have: Array[Dictionary] = []
var _picked: Array[String] = []

var _shelf: GridContainer
var _count: Label
var _words: Label


static func open(on: Node, save: GameState, database: CardDatabase) -> TraitLoadoutScreen:
	var made := TraitLoadoutScreen.new()
	made.name = "TraitLoadoutScreen"
	made.state = save
	made.db = database
	on.add_child(made)
	return made


func _ready() -> void:
	layer = 70
	_room = TraitDB.slots(db)
	_have = TraitDB.unlocked(state)

	# START FROM WHAT IS ACTUALLY IN PLAY, not from an empty shelf. If the
	# player has never opened this screen, refresh_loadout() has already
	# filled the eight from the top of the list, and those are the eight they
	# have been playing with — so those are the ones showing.
	_picked = []
	for entry in TraitDB.refresh_loadout(state, db):
		_picked.append(String(entry["id"]))

	_build()
	_repaint()


# =============================================================
#  BUILDING IT
# =============================================================

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.06, 0.76)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -380.0
	panel.offset_right = 380.0
	panel.offset_top = -280.0
	panel.offset_bottom = 280.0
	panel.add_theme_stylebox_override("panel", MenuSupport.panel_style(
		MenuSupport.COLOUR_PANEL, MenuSupport.COLOUR_ACCENT))
	dim.add_child(panel)

	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right"]:
		pad.add_theme_constant_override(side, 24)
	for side in ["margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 18)
	panel.add_child(pad)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	pad.add_child(column)

	column.add_child(MenuSupport.heading("EDIT ELEMENT BONUS", 26,
		MenuSupport.COLOUR_ACCENT))

	_count = Label.new()
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count.add_theme_font_size_override("font_size", 14)
	column.add_child(_count)

	var scroller := ScrollContainer.new()
	scroller.custom_minimum_size = Vector2(0, 300)
	scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroller)

	_shelf = GridContainer.new()
	_shelf.columns = 4
	_shelf.add_theme_constant_override("h_separation", 8)
	_shelf.add_theme_constant_override("v_separation", 8)
	_shelf.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroller.add_child(_shelf)

	var shelf_words := PanelContainer.new()
	shelf_words.custom_minimum_size = Vector2(0, 62)
	shelf_words.add_theme_stylebox_override("panel", MenuSupport.panel_style(
		MenuSupport.COLOUR_BACKGROUND, MenuSupport.COLOUR_TEXT_DIM))
	column.add_child(shelf_words)

	_words = Label.new()
	_words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_words.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_words.add_theme_font_size_override("font_size", 13)
	shelf_words.add_child(_words)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 10)
	column.add_child(buttons)

	var reset := MenuSupport.icon_button("reset|↺", "Start again", Vector2(200, 46))
	reset.tooltip_text = "Put the first %d back, the way a new save has them." % _room
	reset.pressed.connect(_reset)
	buttons.add_child(reset)

	var done := MenuSupport.icon_button("tick|✔", "Done", Vector2(200, 46))
	done.pressed.connect(_done)
	buttons.add_child(done)


# =============================================================
#  DRAWING THE SHELF
# =============================================================

func _repaint() -> void:
	for child in _shelf.get_children():
		child.queue_free()

	if _have.is_empty():
		_words.text = "No icons are unlocked yet. Every row of AdventureTraits.csv with a blank Requires is available from the first run; the rest need unlocking."
	elif _picked.size() >= _room:
		_words.text = "Full. Put one back before you take another."
	else:
		_words.text = "Point at an icon to read what it does."

	_count.text = "%d of %d carried" % [_picked.size(), _room]
	_count.add_theme_color_override("font_color",
		MenuSupport.COLOUR_ACCENT if _picked.size() >= _room
		else MenuSupport.COLOUR_TEXT_DIM)

	for entry in _have:
		_shelf.add_child(_tile(entry))


func _tile(entry: Dictionary) -> Button:
	var id_text := String(entry["id"])
	var at := _picked.find(id_text)
	var carried := at >= 0
	var tint: Color = entry["colour"]

	var button := Button.new()
	button.custom_minimum_size = Vector2(160, 62)
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_stylebox_override("normal", MenuSupport.panel_style(
		Color(tint.r * 0.30, tint.g * 0.30, tint.b * 0.30, 0.92) if carried
			else MenuSupport.COLOUR_PANEL,
		tint if carried else MenuSupport.COLOUR_TEXT_DIM))
	button.add_theme_stylebox_override("hover", MenuSupport.panel_style(
		MenuSupport.COLOUR_SLOT_EMPTY, MenuSupport.COLOUR_ACCENT))
	button.add_theme_stylebox_override("pressed", MenuSupport.panel_style(
		MenuSupport.COLOUR_SLOT_EMPTY, MenuSupport.COLOUR_ACCENT))
	button.add_theme_stylebox_override("focus", MenuSupport.focus_style())

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 8.0
	row.offset_right = -8.0
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(row)

	# The picture, or a coloured pip while the art is still to be drawn.
	var art := MenuSupport.icon_texture(String(entry["icon"]))
	if art != null:
		var picture := TextureRect.new()
		picture.texture = art
		picture.custom_minimum_size = Vector2(38, 38)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(picture)
	else:
		var pip := Label.new()
		pip.text = "●"
		pip.custom_minimum_size = Vector2(38, 0)
		pip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		pip.add_theme_font_size_override("font_size", 24)
		pip.add_theme_color_override("font_color",
			tint if carried else Color(0.40, 0.43, 0.48))
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(pip)

	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.add_theme_constant_override("separation", 0)
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(words)

	var title := Label.new()
	title.text = String(entry["name"])
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color",
		MenuSupport.COLOUR_TEXT if carried else MenuSupport.COLOUR_TEXT_DIM)
	# clip_text keeps a long name from widening the tile and breaking the grid.
	title.clip_text = true
	words.add_child(title)

	var under := Label.new()
	# CARRIED ONES ARE NUMBERED. The order is the order they sit in along the
	# top of the fight screen, so the shelf and the bar read the same way.
	under.text = ("carried · %d" % (at + 1)) if carried else "on the shelf"
	under.add_theme_font_size_override("font_size", 11)
	under.add_theme_color_override("font_color",
		tint.lightened(0.3) if carried else Color(0.44, 0.47, 0.52))
	under.clip_text = true
	words.add_child(under)

	var described := _describe(entry, carried)
	button.mouse_entered.connect(func() -> void: _words.text = described)
	button.focus_entered.connect(func() -> void: _words.text = described)
	button.pressed.connect(_toggle.bind(id_text))
	return button


## What an icon is worth, read out of AdventureCombos.csv rather than typed
## here — so a breakpoint you add tomorrow shows up on this screen by itself.
func _describe(entry: Dictionary, carried: bool) -> String:
	var lines: Array[String] = []
	lines.append(String(entry["name"]))

	var steps := TraitDB.steps_of(String(entry["id"]))
	if steps.is_empty():
		lines.append("Nothing happens when you collect these — no row of AdventureCombos.csv has this icon as its Trait.")
	else:
		var bits: Array[String] = []
		for step in steps:
			bits.append("at %d: %s" % [int(step["at"]), String(step["name"])])
		lines.append("  ·  ".join(bits))

	if carried:
		lines.append("Carried. Click to put it back on the shelf.")
	elif _picked.size() >= _room:
		lines.append("You are already carrying %d. Put one back first." % _room)
	else:
		lines.append("Click to carry it.")
	return "\n".join(lines)


# =============================================================
#  CHANGING IT
# =============================================================

func _toggle(id_text: String) -> void:
	var at := _picked.find(id_text)
	if at >= 0:
		_picked.remove_at(at)
	elif _picked.size() < _room:
		_picked.append(id_text)
	else:
		# FULL SAYS SO. A button that does nothing reads as broken.
		_words.text = "You are already carrying %d. Put one back first." % _room
		return
	_repaint()


func _reset() -> void:
	_picked = []
	for entry in _have:
		if _picked.size() >= _room:
			break
		_picked.append(String(entry["id"]))
	_repaint()


func _done() -> void:
	TraitDB.choose(_picked, state)
	TraitDB.refresh_loadout(state, db)
	if state != null:
		state.save_to_disk()
	print("[traits] Carrying: %s" % ", ".join(_picked))
	queue_free()
