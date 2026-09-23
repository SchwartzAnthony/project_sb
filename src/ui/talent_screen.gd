class_name TalentScreen
extends Control

# =============================================================
#  THE TALENT TREE
#
#  Everything on this screen comes from res://data/Talents.csv. The layout
#  is worked out for you: one COLUMN per Tree, one ROW per Tier, and a
#  line drawn from every talent to its Parent.
#
#  You never position anything. Add a row with a new Tree name and a new
#  column appears; add one with a higher Tier and the tree grows downward.
#
#  Reached from the Training Ground on the base screen, or from anywhere
#  with  goto:talents .
# =============================================================

const ART_DIRS: Array[String] = ["res://assets/talents/", "res://assets/base/", "res://assets/"]

const CARD_SIZE := Vector2(210.0, 104.0)
const COLUMN_GAP := 56.0
const ROW_GAP := 44.0
const TOP_MARGIN := 132.0

var db: TalentDB
var state: GameState

var _lines: TalentLines
var _cards: Control
var _detail: Label
var _points: Label


func _ready() -> void:
	# Escape, controller navigation, the key bindings, the player's
	# settings and the language — all five from this one line. See
	# menu_escape.gd.
	# THE WINDOW DOES ALL THREE when this screen is opened over the base:
	# the background, the Back button and Escape. See base_window.gd.
	var windowed := MenuSupport.in_a_window(self)
	if not windowed:
		MenuEscape.install(self)
		# A WINDOW SIZES THIS SCREEN ITSELF. Pinning it to the whole viewport
		# from in here would fight the container it has been put in.
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	db = TalentDB.get_db()
	state = GameState.fetch(get_tree())

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

	# The connector lines are drawn UNDER the cards, so this goes in first.
	_lines = TalentLines.new()
	_lines.name = "Lines"
	_lines.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_lines)

	_cards = Control.new()
	_cards.name = "Cards"
	_cards.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cards.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cards)
	_cards.resized.connect(_rebuild)

	var title := MenuSupport.heading("TALENTS", 34, MenuSupport.COLOUR_ACCENT)
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_left = 40.0
	title.offset_top = 26.0
	title.offset_bottom = 74.0
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# THE WINDOW'S TITLE BAR ALREADY SAYS THIS. Hidden rather than removed,
	# so the layout below keeps the breathing room it was drawn with.
	title.visible = not MenuSupport.in_a_window(self)
	add_child(title)

	_points = Label.new()
	_points.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_points.add_theme_font_size_override("font_size", 20)
	_points.add_theme_color_override("font_color", MenuSupport.COLOUR_ACCENT)
	_points.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_points.offset_top = 78.0
	_points.offset_bottom = 108.0
	_points.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_points)

	_detail = Label.new()
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail.add_theme_font_size_override("font_size", 17)
	_detail.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT)
	_detail.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_detail.offset_left = 60.0
	_detail.offset_right = -60.0
	_detail.offset_top = -74.0
	_detail.offset_bottom = -20.0
	_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_detail)

	var back := MenuSupport.icon_button("◇", "Back to the base", Vector2(210, 46))
	back.add_theme_font_size_override("font_size", 17)
	back.add_theme_stylebox_override("normal",
		MenuSupport.panel_style(MenuSupport.COLOUR_PANEL, MenuSupport.COLOUR_ACCENT))
	back.add_theme_stylebox_override("hover",
		MenuSupport.panel_style(MenuSupport.COLOUR_SLOT_EMPTY, MenuSupport.COLOUR_ACCENT))
	back.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	back.offset_left = -240.0
	back.offset_top = 26.0
	back.offset_right = -30.0
	back.offset_bottom = 72.0
	# THE WINDOW HAS A ✕. Two ways out of one screen is one too many.
	back.visible = not MenuSupport.in_a_window(self)
	# THE WINDOW HAS A ✕. Two ways out of one screen is one too many.
	back.visible = not MenuSupport.in_a_window(self)
	back.pressed.connect(func() -> void:
		state.save_to_disk()
		ScenePaths.go_back(get_tree(), ScenePaths.BASE))
	add_child(back)

	# ============ AND THE OTHER HALF OF THE TREE ============
	#
	# The Stars and the Emblems are a second screen, because they are a
	# different SHAPE — three plinths and a choice, not a grid of nodes with
	# lines between them. Trying to draw both on one screen made each of them
	# worse. They share one pool of points, which is what makes them one tree.
	var stars := MenuSupport.icon_button("★", "The Star Hall", Vector2(210, 46))
	stars.add_theme_font_size_override("font_size", 17)
	stars.add_theme_stylebox_override("normal",
		MenuSupport.panel_style(MenuSupport.COLOUR_PANEL, MenuSupport.COLOUR_ATTACK))
	stars.add_theme_stylebox_override("hover",
		MenuSupport.panel_style(MenuSupport.COLOUR_SLOT_EMPTY, MenuSupport.COLOUR_ATTACK))
	stars.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	stars.offset_left = -470.0
	stars.offset_top = 26.0
	stars.offset_right = -260.0
	stars.offset_bottom = 72.0
	stars.pressed.connect(func() -> void:
		state.save_to_disk()
		# IN A WINDOW, SWAP THE WINDOW. Going to a whole new scene from
		# inside a panel over the base would throw the base away, which is
		# the one thing a window is for not doing. BaseWindow closes the
		# open one before it opens another, so this is a swap and not a pile.
		if MenuSupport.in_a_window(self):
			var over := get_tree().current_scene
			if over != null:
				BaseWindow.open(over, "The Star Hall", ScenePaths.CLASS_TREE)
			return
		ScenePaths.go_to(get_tree(), ScenePaths.CLASS_TREE))
	add_child(stars)


# =============================================================
#  LAYOUT — worked out from the CSV, never positioned by hand
# =============================================================

func _rebuild() -> void:
	if _cards == null:
		return
	for child in _cards.get_children():
		child.queue_free()

	var trees := db.tree_names()
	if trees.is_empty():
		_detail.text = "No talents yet. Add rows to res://data/Talents.csv — every row needs an ID, a Tree and a Tier."
		_lines.links.clear()
		_lines.queue_redraw()
		_refresh_points()
		return

	var area := _cards.size
	if area.x < 2.0:
		area = get_viewport_rect().size

	# Columns are centred as a group, so one tree sits in the middle and
	# four spread evenly, with no numbers to tweak.
	var total_width := float(trees.size()) * CARD_SIZE.x + float(trees.size() - 1) * COLUMN_GAP
	var left := maxf((area.x - total_width) * 0.5, 20.0)

	var centres: Dictionary = {}      # talent id -> centre of its card

	for column in trees.size():
		var tree := trees[column]
		var x := left + float(column) * (CARD_SIZE.x + COLUMN_GAP)

		var heading := Label.new()
		heading.text = tree.to_upper()
		heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		heading.add_theme_font_size_override("font_size", 19)
		heading.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
		heading.position = Vector2(x, TOP_MARGIN - 34.0)
		heading.size = Vector2(CARD_SIZE.x, 26.0)
		heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_cards.add_child(heading)

		for entry in db.in_tree(tree):
			var tier := maxi(int(entry["tier"]), 1)
			var y := TOP_MARGIN + float(tier - 1) * (CARD_SIZE.y + ROW_GAP)

			var card := _make_card(entry)
			card.position = Vector2(x, y)
			_cards.add_child(card)
			centres[CardDatabase._normalise(String(entry["id"]))] = \
				Vector2(x, y) + CARD_SIZE * 0.5

	_rebuild_lines(centres)
	_refresh_points()


## One line per parent-to-child link, drawn behind the cards. Gold once the
## parent is taken, so the path you have walked is visible at a glance.
func _rebuild_lines(centres: Dictionary) -> void:
	_lines.links.clear()
	for entry in db.talents:
		var parent := String(entry["parent"]).strip_edges()
		if parent == "":
			continue
		var from_key := CardDatabase._normalise(parent)
		var to_key := CardDatabase._normalise(String(entry["id"]))
		if not (centres.has(from_key) and centres.has(to_key)):
			continue
		_lines.links.append({
			"from": centres[from_key],
			"to": centres[to_key],
			"lit": state.is_unlocked(parent),
		})
	_lines.queue_redraw()


func _make_card(entry: Dictionary) -> Control:
	var state_text := TalentDB.status(entry, state, db)
	var taken := state_text == "taken"
	var available := state_text == "available"

	var button := Button.new()
	button.custom_minimum_size = CARD_SIZE
	button.size = CARD_SIZE
	button.tooltip_text = String(entry["description"])

	var edge := MenuSupport.COLOUR_SLOT_EMPTY
	var fill := MenuSupport.COLOUR_BACKGROUND
	if taken:
		edge = MenuSupport.COLOUR_ACCENT
		fill = MenuSupport.COLOUR_LOCKED
	elif available:
		edge = MenuSupport.COLOUR_ACCENT
		fill = MenuSupport.COLOUR_PANEL

	button.add_theme_stylebox_override("normal", MenuSupport.panel_style(fill, edge))
	button.add_theme_stylebox_override("hover",
		MenuSupport.panel_style(MenuSupport.COLOUR_SLOT_EMPTY, edge))
	button.add_theme_stylebox_override("pressed",
		MenuSupport.panel_style(MenuSupport.COLOUR_SLOT_EMPTY, MenuSupport.COLOUR_ACCENT))

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 1)
	button.add_child(box)

	var name_label := Label.new()
	name_label.text = String(entry["name"])
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color",
		MenuSupport.COLOUR_TEXT if (taken or available) else MenuSupport.COLOUR_TEXT_DIM)
	name_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name_label)

	var badge := Label.new()
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.add_theme_font_size_override("font_size", 13)
	var cost := int(entry["cost"])
	if taken:
		badge.text = "TAKEN"
		badge.add_theme_color_override("font_color", MenuSupport.COLOUR_ACCENT)
	elif cost > 0:
		badge.text = "%d point%s" % [cost, "" if cost == 1 else "s"]
		badge.add_theme_color_override("font_color",
			MenuSupport.COLOUR_TEXT if available else MenuSupport.COLOUR_TEXT_DIM)
	else:
		badge.text = "free"
		badge.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(badge)

	button.pressed.connect(_on_talent.bind(entry))
	return button


# =============================================================
#  CLICKING
# =============================================================

func _on_talent(entry: Dictionary) -> void:
	var state_text := TalentDB.status(entry, state, db)
	var name_text := String(entry["name"])

	if state_text == "taken":
		_detail.text = "%s — %s" % [name_text, entry["description"]]
		return

	if state_text == "locked":
		var reason := TalentDB.why_locked(entry, state, db)
		_detail.text = "%s is locked. %s" % [name_text, reason]
		return

	var deferred := TalentDB.take(entry, state, db)
	_detail.text = "%s taken. %s" % [name_text, entry["description"]]
	state.save_to_disk()

	# A talent could ask to play a story or jump elsewhere. Rare, but the
	# same words work here as everywhere else, so it costs nothing to allow.
	for action in deferred:
		var kind := String(action["kind"])
		var value := String(action["value"])
		match kind:
			"announce":
				_detail.text = value
			"story":
				DialogueView.play(get_tree(), value, ScenePaths.TALENTS)
				return
			"goto":
				ScenePaths.go_to(get_tree(), ScenePaths.for_name(value))
				return

	_rebuild()


func _refresh_points() -> void:
	if _points == null or state == null:
		return
	var have := state.count(TalentDB.POINTS)
	_points.text = "%d talent point%s" % [have, "" if have == 1 else "s"]
	if not db.problems.is_empty():
		_points.text += "    ⚠ %d problem%s in Talents.csv — see the Output panel" % [
			db.problems.size(), "" if db.problems.size() == 1 else "s"]


# =============================================================
#  THE CONNECTOR LINES
#
#  A tiny Control that does nothing but draw the parent-to-child links
#  underneath the cards. Kept separate so the cards stay ordinary Buttons.
# =============================================================

class TalentLines extends Control:
	## Each: from (Vector2), to (Vector2), lit (bool)
	var links: Array[Dictionary] = []

	func _draw() -> void:
		for link in links:
			var lit := bool(link["lit"])
			var colour := MenuSupport.COLOUR_ACCENT if lit else MenuSupport.COLOUR_SLOT_EMPTY
			colour.a = 0.9 if lit else 0.55

			var from: Vector2 = link["from"]
			var to: Vector2 = link["to"]

			# Elbow rather than a diagonal: it reads as a tree rather than a
			# cat's cradle once a parent has three children.
			var middle_y := (from.y + to.y) * 0.5
			draw_line(from, Vector2(from.x, middle_y), colour, 3.0, true)
			draw_line(Vector2(from.x, middle_y), Vector2(to.x, middle_y), colour, 3.0, true)
			draw_line(Vector2(to.x, middle_y), to, colour, 3.0, true)
