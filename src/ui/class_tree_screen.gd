class_name ClassTreeScreen
extends Control

# =============================================================
#  THE CLASS TREE, ON SCREEN
#
#  One column per class. Down each column:
#
#      THE THREE NODES     one per emblem set. Each one wants a Star, and
#                          when it has one that set's nine units are yours
#      THE EMBLEM          choosable once all three are filled. ONE of the
#                          three, and it cannot be changed afterwards
#      THE TEAM SPIRIT     forged at the same moment, and unlocking it is
#                          the whole of what forging does — the drink is a
#                          row of Brews.csv like every other drink
#
#  ============ NOTHING HERE IS POSITIONED BY HAND ============
#
#  The columns come from the classes that have Star Players; the nodes come
#  from that class's emblem sets; the emblems come from "<Class> Emblems.csv".
#  Add a class to your unit spreadsheets tomorrow and it has a column here
#  this afternoon, with no edit to this file or any other.
#
#  Reached from the Training Ground on the base screen, from the TALENTS
#  screen's own button, or from anywhere with  goto:classtree .
# =============================================================

const COLUMN_WIDTH := 430.0
const COLUMN_GAP := 28.0

var db: CardDatabase
var state: GameState

var _scroll: ScrollContainer
var _row: HBoxContainer
var _points: Label
var _status: Label
## The class whose Star picker is open, or "" — only one at a time.
var _picking: String = ""
var _picking_set: String = ""


func _ready() -> void:
	# Escape, controller navigation, key bindings, settings and language, all
	# from this one line. See menu_escape.gd.
	# THE WINDOW DOES ALL THREE when this screen is opened over the base:
	# the background, the Back button and Escape. See base_window.gd.
	var windowed := MenuSupport.in_a_window(self)
	if not windowed:
		MenuEscape.install(self)
		# A WINDOW SIZES THIS SCREEN ITSELF. Pinning it to the whole viewport
		# from in here would fight the container it has been put in.
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	db = CardDatabase.get_db()
	state = GameState.fetch(get_tree())
	ClassTree.review(state, db)

	_build_chrome()
	_rebuild()


# =============================================================
#  CHROME
# =============================================================

func _build_chrome() -> void:
	# NO BACKGROUND OF ITS OWN IN A WINDOW — the window has one, and a second
	# opaque rectangle would paint over the dimmed base behind it.
	if not MenuSupport.in_a_window(self):
		var fill := ColorRect.new()
		fill.color = MenuSupport.COLOUR_BACKGROUND
		fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(fill)

	var title := MenuSupport.heading(
		Loc.text("class_tree_title", "THE CLASS TREE"), 34, MenuSupport.COLOUR_ACCENT)
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_left = 40.0
	title.offset_top = 24.0
	title.offset_bottom = 72.0
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# THE WINDOW'S TITLE BAR ALREADY SAYS THIS. Hidden rather than removed,
	# so the layout below keeps the breathing room it was drawn with.
	title.visible = not MenuSupport.in_a_window(self)
	add_child(title)

	_points = Label.new()
	_points.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_points.offset_left = 40.0
	_points.offset_right = -40.0
	_points.offset_top = 66.0
	_points.offset_bottom = 96.0
	_points.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_points.add_theme_font_size_override("font_size", 18)
	_points.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT)
	_points.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_points)

	_scroll = ScrollContainer.new()
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll.offset_top = 104.0
	_scroll.offset_left = 30.0
	_scroll.offset_right = -30.0
	_scroll.offset_bottom = -72.0
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(_scroll)

	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", int(COLUMN_GAP))
	_scroll.add_child(_row)

	_status = Label.new()
	_status.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_status.offset_left = 40.0
	_status.offset_right = -40.0
	_status.offset_top = -62.0
	_status.offset_bottom = -18.0
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 16)
	_status.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_status)


# =============================================================
#  THE COLUMNS
# =============================================================

func _rebuild() -> void:
	for child in _row.get_children():
		child.queue_free()

	_points.text = Loc.text("talent_points", "Talent points: %d") % state.count(ClassTree.POINTS)

	var any := false
	for key in ClassBook.classes():
		var entry: ClassBook.ClassEntry = ClassBook.classes()[key]
		# A class with no Star Players has no tree — there is nothing to put
		# in a node. BasicTeam has Stars, so your own club gets a column too.
		if entry.stars.is_empty() or entry.sets.is_empty():
			continue
		_row.add_child(_column_for(entry))
		any = true

	if not any:
		var nothing := Label.new()
		nothing.text = "No class has both Star Players and emblem sets yet.\nRun tools/class_tree_check.gd — it names what is missing."
		nothing.add_theme_font_size_override("font_size", 18)
		nothing.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
		_row.add_child(nothing)


func _column_for(entry: ClassBook.ClassEntry) -> Control:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(COLUMN_WIDTH, 0.0)
	frame.add_theme_stylebox_override("panel", MenuSupport.styled(
		"panel", "", MenuSupport.COLOUR_PANEL, MenuSupport.COLOUR_ACCENT))

	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right"]:
		pad.add_theme_constant_override(side, 18)
	for side in ["margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 16)
	frame.add_child(pad)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	pad.add_child(column)

	var who := entry.unit_type
	var heading := MenuSupport.heading(who.to_upper(), 22, MenuSupport.COLOUR_ACCENT)
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(heading)

	var costs := ClassTree.costs_for(who)
	column.add_child(_small("%d Star node(s) · a node costs %d, your element %d, the spirit %d"
		% [entry.sets.size(), int(costs["node"]), int(costs["element"]), int(costs["spirit"])]))

	# ---- the nodes ----
	for node in ClassTree.nodes_for(who, state):
		column.add_child(_node_tile(who, node))

	column.add_child(HSeparator.new())

	# ---- the emblem ----
	column.add_child(_emblem_block(entry))

	# ---- the team spirit ----
	column.add_child(_spirit_block(who))
	return frame


func _node_tile(who: String, node: Dictionary) -> Control:
	var set_id := String(node["set_id"])
	var filled := bool(node["filled"])

	# ============ A FLAT TILE, NOT THE SKINNED ONE ============
	#
	# The `slot` row of Theme.csv is a cream beer-mat with a blue-and-white
	# lozenge band across it, which is lovely behind a card and murder behind
	# a paragraph: light text on cream is invisible, and I only saw that in a
	# screenshot. A plinth is a block of colour, and the column around it is
	# still wearing the skin.
	var tile := PanelContainer.new()
	tile.add_theme_stylebox_override("panel", MenuSupport.panel_style(
		MenuSupport.COLOUR_SLOT_EMPTY,
		MenuSupport.COLOUR_ATTACK if filled else MenuSupport.COLOUR_TEXT_DIM))

	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 10)
	tile.add_child(pad)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	pad.add_child(box)

	var line := MenuSupport.heading("%s — %d units" % [set_id, int(node["cards"])],
		18, MenuSupport.COLOUR_TEXT)
	box.add_child(line)

	if filled:
		box.add_child(_small("%s stands here. The %s units are yours."
			% [ClassTree.star_label(String(node["star"])), set_id]))
	else:
		box.add_child(_small("Empty. Put a Star here to open these %d units."
			% int(node["cards"])))
		var button := _button("PUT A STAR IN", MenuSupport.COLOUR_ATTACK)
		button.pressed.connect(_open_picker.bind(who, set_id))
		box.add_child(button)

	# The Star picker opens INSIDE the node it is for, rather than as a
	# floating window — so there is never a question of which node you are
	# filling.
	if not filled and _picking == who and _picking_set == set_id:
		box.add_child(_picker_for(who, set_id))
	return tile


func _picker_for(who: String, set_id: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)

	var taken := ClassTree.stars_placed(who, state)
	var offered := 0
	for star in ClassTree.stars_you_own(who, state, db):
		if taken.has(ClassTree.star_key(star)):
			continue
		var button := _button("%s   (Tier %s, P:%d, card %d)" % [
			star.player_name, star.get_tier_clean(), star.base_power_left,
			star.card_number],
			MenuSupport.COLOUR_DEFEND)
		button.pressed.connect(_place.bind(who, set_id, star))
		box.add_child(button)
		offered += 1

	if offered == 0:
		box.add_child(_small("You have no Star of this class left to place."))
	return box


func _emblem_block(entry: ClassBook.ClassEntry) -> Control:
	var who := entry.unit_type
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)

	# ============ THIS PANEL NO LONGER SELLS YOU AN EMBLEM ============
	#
	# It used to: fill three nodes, then choose ONE emblem, for points. That
	# is gone. An Emblem arrives with its Star — field the Star and it is on
	# the bar along the top of the pitch.
	#
	# So the panel reads them back instead of selling them, and the node that
	# was here sells an ELEMENT: permission to field units of other classes
	# that share yours. See ClassTree.open_element().

	box.add_child(MenuSupport.heading("EMBLEMS", 18, MenuSupport.COLOUR_ACCENT))
	if entry.emblems.is_empty():
		box.add_child(_small("No \"%s Emblems.csv\" yet. Write one and this fills in." % who))
	else:
		box.add_child(_small("Each Star carries one onto the pitch. All three collect; the first to complete its Condition turns over, and a goal puts them all back."))
		for badge in EmblemBook.for_class(who):
			var line := "%s  ·  %s" % [badge.id, badge.token if badge.token != "" else "no token yet"]
			box.add_child(MenuSupport.heading(line, 16, MenuSupport.COLOUR_TEXT))
			box.add_child(_small(badge.basic))
			if badge.turns_on == "":
				box.add_child(_small("No Turns On condition yet, so it can never turn over."))
			else:
				box.add_child(_small("Turns over when: %s"
					% DialogueGrammar.describe(badge.turns_on)))

	# ---- THE ELEMENT NODE ----
	if ClassTree.element_node_offered(who, db):
		box.add_child(HSeparator.new())
		var word := ClassTree.element_unlock(who)
		box.add_child(MenuSupport.heading(word.to_upper(), 18, MenuSupport.COLOUR_ACCENT))
		var others := ClassBook.classes_of_element(ClassBook.element_of(who))
		others.erase(who)
		var said := ", ".join(PackedStringArray(others)) if not others.is_empty() \
			else "nothing else of this element is written yet — the node is ready for the day one is"
		if ClassTree.element_open(who, state):
			box.add_child(_small("OPEN. You may field: %s" % said))
		elif not ClassTree.all_placed(who, state):
			box.add_child(_small("Fill all three nodes first. Then: %s" % said))
		else:
			var cost := int(ClassTree.costs_for(who)["element"])
			var button := _button("Open %s  —  %d point(s)" % [word, cost],
				MenuSupport.COLOUR_ACCENT)
			button.pressed.connect(_open_element.bind(who))
			box.add_child(button)
			box.add_child(_small("Lets you field units of other classes that share your element. An Emblem's Basic side already counts any %s unit; this is what puts one on the pitch."
				% ClassBook.element_of(who).to_lower()))
	return box


func _spirit_block(who: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.add_child(MenuSupport.heading("TEAM SPIRIT", 18, MenuSupport.COLOUR_ACCENT))

	var costs := ClassTree.costs_for(who)
	if String(costs["brew"]) == "":
		box.add_child(_small("No Spirit Brew is named for %s in ClassTree.csv." % who))
		return box

	if ClassTree.spirit_forged(who, state):
		box.add_child(_small("Forged. The Pub can pour it."))
		return box
	if not ClassTree.all_placed(who, state):
		box.add_child(_small("Fill all three nodes to forge it."))
		return box

	var button := _button("FORGE THE TEAM SPIRIT (%d)" % int(costs["spirit"]),
		MenuSupport.COLOUR_ATTACK)
	button.pressed.connect(_forge.bind(who))
	box.add_child(button)
	return box


# =============================================================
#  DOING THINGS
# =============================================================

func _open_picker(who: String, set_id: String) -> void:
	# Clicking the same node again closes it, which is what everybody tries.
	if _picking == who and _picking_set == set_id:
		_picking = ""
		_picking_set = ""
	else:
		_picking = who
		_picking_set = set_id
	_rebuild()


func _place(who: String, set_id: String, star: PlayerData) -> void:
	var result := ClassTree.place_star(who, set_id, star, state, db)
	_picking = ""
	_picking_set = ""
	_say(result)
	_rebuild()


func _open_element(who: String) -> void:
	_say(ClassTree.open_element(who, state, db))
	_rebuild()


func _forge(who: String) -> void:
	_say(ClassTree.forge_spirit(who, state, db))
	_rebuild()


## Everything that changes the save goes through here, so there is exactly
## one place that writes to disk.
func _say(result: Dictionary) -> void:
	if bool(result["ok"]) and state != null:
		state.save_to_disk()
	_status.text = String(result["why"])
	_status.add_theme_color_override("font_color",
		MenuSupport.COLOUR_TEXT if bool(result["ok"]) else Color(1.0, 0.72, 0.4))


# =============================================================
#  SMALL PIECES
# =============================================================

func _small(words: String) -> Label:
	var label := Label.new()
	label.text = words
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	return label


func _button(words: String, tint: Color) -> Button:
	var button := Button.new()
	button.text = words
	button.custom_minimum_size = Vector2(0.0, 34.0)
	button.add_theme_stylebox_override("normal",
		MenuSupport.styled("button", "", MenuSupport.COLOUR_PANEL, tint))
	button.add_theme_stylebox_override("hover",
		MenuSupport.styled("button", "hover", MenuSupport.COLOUR_SLOT_EMPTY, tint))
	button.add_theme_stylebox_override("pressed",
		MenuSupport.styled("button", "pressed", MenuSupport.COLOUR_SLOT_EMPTY, tint))
	button.add_theme_stylebox_override("focus", MenuSupport.focus_style())
	button.add_theme_color_override("font_color", tint)
	return button
