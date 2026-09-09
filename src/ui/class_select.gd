class_name ClassSelect
extends Control

# =============================================================
#  CLASS / RACE SELECT — the first half of team building
#
#  LEFT   every class found in your unit CSVs, one button each
#  RIGHT  that class's three Star Players (click one to read its card),
#         plus the formation its Star tier implies
#  BOTTOM  LOCK IN -> the team builder
#
#  ADDING A CLASS: none of this is hard-coded. Drop a unit CSV in
#  res://data/ with rows whose Player Type is "Star" and the class appears
#  here on the next launch. Give it a nicer name, a blurb and a banner by
#  adding a row to res://data/ClassInfo.csv — see MENU_GUIDE.md.
# =============================================================

const ALL_TIERS: Array[String] = ["I", "II", "III", "IV"]
const CLASS_INFO_PATH := "res://data/ClassInfo.csv"

var db: CardDatabase
var popup: CardPopup

var _class_names: Array[String] = []
var _class_info: Dictionary = {}      # normalised class name -> CSV row
var _selected_class: String = ""

var _class_list: VBoxContainer
var _detail: VBoxContainer
var _lock_button: Button


func _ready() -> void:
	db = CardDatabase.get_db()
	_load_class_info()
	_build_ui()
	_collect_classes()

	if _class_names.is_empty():
		_show_no_classes_message()
		return

	_select_class(_opening_class())


## Which class the screen opens on.
##
## THIS IS THE STORY HOOK. A dialogue choice carrying the effect
##     set:next_class=Lorelei
## lands you here already on the Lorelei, so a decision made in a
## conversation is visibly the decision you play. Anything else you want a
## choice to change is wired the same way: read GameState where the thing is
## decided, and write it from a CSV Effects column.
##
## The name is consumed, not kept, so the next match starts free again.
func _opening_class() -> String:
	var state := GameState.fetch(get_tree())
	var wanted := state.text("next_class")
	if wanted != "":
		state.set_text("next_class", "")
		for known in _class_names:
			if MenuSupport.normalise(known) == MenuSupport.normalise(wanted):
				print("[Story] Opening on %s — chosen in dialogue." % known)
				return known
		print("[Story] Dialogue asked for class '%s', which no CSV defines." % wanted)
	return _class_names[0]


# -------------------------------------------------------------
#  DATA
# -------------------------------------------------------------

func _load_class_info() -> void:
	for row in MenuSupport.read_csv(CLASS_INFO_PATH):
		var key := MenuSupport.field(row, "Class")
		if key != "":
			_class_info[MenuSupport.normalise(key)] = row


func _collect_classes() -> void:
	var by_class := db.stars_by_class()
	var names: Array = by_class.keys()
	names.sort()
	for key in names:
		var bundle: Array = by_class[key]
		if bundle.is_empty():
			continue
		_class_names.append(String(key))

	for class_name_text in _class_names:
		var button := Button.new()
		button.text = _display_name(class_name_text)
		button.custom_minimum_size = Vector2(0, 48)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_select_class.bind(class_name_text))
		_class_list.add_child(button)


func _info_row(class_name_text: String) -> Dictionary:
	var found: Dictionary = _class_info.get(MenuSupport.normalise(class_name_text), {})
	return found


func _display_name(class_name_text: String) -> String:
	return MenuSupport.field(_info_row(class_name_text), "Display Name", class_name_text)


# -------------------------------------------------------------
#  LAYOUT
# -------------------------------------------------------------

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var background := ColorRect.new()
	background.color = MenuSupport.COLOUR_BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 16)
	margin.add_child(page)

	page.add_child(MenuSupport.heading("CHOOSE YOUR CLASS", 34, MenuSupport.COLOUR_ACCENT))

	# --- The two columns ---
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 24)
	page.add_child(columns)

	# LEFT: the class list
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(280, 0)
	left.add_theme_constant_override("separation", 8)
	columns.add_child(left)

	left.add_child(MenuSupport.heading("CLASSES", 16, MenuSupport.COLOUR_TEXT_DIM))

	var left_scroll := ScrollContainer.new()
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(left_scroll)

	_class_list = VBoxContainer.new()
	_class_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_class_list.add_theme_constant_override("separation", 6)
	left_scroll.add_child(_class_list)

	# RIGHT: stars + formation for whichever class is highlighted
	var right_panel := PanelContainer.new()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.add_theme_stylebox_override("panel",
		MenuSupport.panel_style(MenuSupport.COLOUR_PANEL))
	columns.add_child(right_panel)

	var right_scroll := ScrollContainer.new()
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_panel.add_child(right_scroll)

	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_theme_constant_override("separation", 14)
	right_scroll.add_child(_detail)

	# --- Footer ---
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	page.add_child(footer)

	var back := Button.new()
	back.text = "◀  BACK"
	back.custom_minimum_size = Vector2(140, 52)
	back.pressed.connect(_on_back)
	footer.add_child(back)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)

	_lock_button = Button.new()
	_lock_button.text = "LOCK IN  ▶"
	_lock_button.custom_minimum_size = Vector2(220, 52)
	_lock_button.disabled = true
	_lock_button.pressed.connect(_on_lock_in)
	footer.add_child(_lock_button)

	# The card popup sits on top of everything.
	popup = CardPopup.new()
	popup.db = db
	add_child(popup)


func _show_no_classes_message() -> void:
	_lock_button.disabled = true
	_detail.add_child(MenuSupport.heading("No classes found", 24, Color(1.0, 0.55, 0.45)))
	var help := Label.new()
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.text = """The game found no Star Players in res://data/.

To get a class to show up here, a CSV in res://data/ needs rows with:
  • a "Unit Type" column (the class name)
  • a "Base Power Left" column
  • at least one row whose "Player Type" is Star

Open the Output panel — CardDatabase prints exactly what it read and what
looked wrong in every CSV."""
	help.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	_detail.add_child(help)


# -------------------------------------------------------------
#  SELECTION
# -------------------------------------------------------------

func _select_class(class_name_text: String) -> void:
	_selected_class = class_name_text
	_lock_button.disabled = false

	# Highlight the chosen button, dim the rest.
	for i in _class_list.get_child_count():
		var button := _class_list.get_child(i) as Button
		if button == null:
			continue
		var is_chosen := i < _class_names.size() and _class_names[i] == class_name_text
		button.add_theme_color_override("font_color",
			MenuSupport.COLOUR_ACCENT if is_chosen else MenuSupport.COLOUR_TEXT)

	_rebuild_detail()


func _rebuild_detail() -> void:
	for child in _detail.get_children():
		child.queue_free()

	var info := _info_row(_selected_class)
	var stars := db.stars_for_class(_selected_class)
	var star_tier: String = ""
	if not stars.is_empty():
		star_tier = stars[0].get_tier_clean()

	# --- Optional banner art, straight from ClassInfo.csv ---
	var banner_path := MenuSupport.field(info, "Banner Art")
	if banner_path != "" and ResourceLoader.exists(banner_path):
		var banner_texture := load(banner_path)
		if banner_texture is Texture2D:
			var banner := TextureRect.new()
			banner.texture = banner_texture
			banner.custom_minimum_size = Vector2(0, 150)
			banner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			banner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			banner.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			_detail.add_child(banner)

	_detail.add_child(MenuSupport.heading(_display_name(_selected_class), 30))

	var blurb := MenuSupport.field(info, "Description")
	if blurb != "":
		var blurb_label := Label.new()
		blurb_label.text = blurb
		blurb_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		blurb_label.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
		_detail.add_child(blurb_label)

	# --- The three Stars ---
	_detail.add_child(MenuSupport.heading(
		"STAR PLAYERS  ·  Tier %s  ·  click a card to read it" % star_tier,
		15, MenuSupport.COLOUR_ACCENT))

	var star_row := HBoxContainer.new()
	star_row.add_theme_constant_override("separation", 12)
	_detail.add_child(star_row)

	if stars.is_empty():
		star_row.add_child(MenuSupport.heading("No Star Players in this class.", 14,
			Color(1.0, 0.55, 0.45)))
	for star in stars:
		star_row.add_child(_make_star_card(star))

	# --- Roster health, so a broken CSV is obvious before the match ---
	_detail.add_child(HSeparator.new())
	_detail.add_child(_make_roster_summary(star_tier))

	# --- Formation ---
	_detail.add_child(HSeparator.new())
	_detail.add_child(MenuSupport.heading("FORMATION", 15, MenuSupport.COLOUR_ACCENT))
	_detail.add_child(_make_formation_view(info, star_tier))


## One clickable Star card: portrait, name, power.
func _make_star_card(card: PlayerData) -> Control:
	var button := Button.new()
	button.custom_minimum_size = Vector2(150, 210)
	button.tooltip_text = "Click to read %s's card" % card.player_name
	button.pressed.connect(func(): popup.show_card(card))

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 4)
	button.add_child(box)

	var portrait := MenuSupport.portrait_rect(card, db, Vector2(134, 130))
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(portrait)

	var name_label := Label.new()
	name_label.text = card.player_name
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name_label)

	var power := Label.new()
	power.text = "★  %d / %d" % [card.get_attack_power(), card.get_defense_power()]
	power.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	power.add_theme_font_size_override("font_size", 14)
	power.add_theme_color_override("font_color", MenuSupport.COLOUR_ACCENT)
	power.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(power)

	# The same badge these three will wear on the pitch, so the marker you
	# learn here is the marker you look for during the match. Swapping
	# assets/ui/star_badge.png changes this corner too.
	var badge := StarBadge.make_marker(false, 30.0)
	button.add_child(badge)
	badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	badge.offset_left = -36.0
	badge.offset_top = 4.0
	badge.offset_right = -6.0
	badge.offset_bottom = 34.0

	return button


## Counts each tier's regulars against the 3-per-tier rule, so you can see a
## data problem here instead of discovering it mid-match.
func _make_roster_summary(star_tier: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)

	var roster := db.roster_for_class(_selected_class)
	for tier in ALL_TIERS:
		if tier == star_tier:
			box.add_child(MenuSupport.heading(
				"Tier %s — your Stars (locked)" % tier, 13, MenuSupport.COLOUR_ACCENT))
			continue
		var count := 0
		for card in roster:
			if card.get_tier_clean() == tier:
				count += 1
		var ok := count >= 3
		box.add_child(MenuSupport.heading(
			"Tier %s — %d card%s available%s" % [
				tier, count, "" if count == 1 else "s",
				"" if ok else "   ⚠ need at least 3"],
			13, MenuSupport.COLOUR_TEXT_DIM if ok else Color(1.0, 0.55, 0.45)))
	return box


## The formation. If ClassInfo.csv names a Formation Art image we show that;
## otherwise we draw the tier columns from the same 3x3 shape the match uses,
## so there is always something to look at.
func _make_formation_view(info: Dictionary, star_tier: String) -> Control:
	var art_path := MenuSupport.field(info, "Formation Art")
	if art_path != "" and ResourceLoader.exists(art_path):
		var texture := load(art_path)
		if texture is Texture2D:
			var rect := TextureRect.new()
			rect.texture = texture
			rect.custom_minimum_size = Vector2(0, 220)
			rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			return rect

	var diagram := FormationDiagram.new()
	diagram.star_tier = star_tier
	diagram.custom_minimum_size = Vector2(0, 220)
	return diagram


# -------------------------------------------------------------
#  NAVIGATION
# -------------------------------------------------------------

## BACK GOES BACK. This screen is reached from the main menu AND from the
## base's "Play a match" button, so it cannot know where you came from —
## which is exactly what the trail in ScenePaths is for. It used to send
## everyone to the main menu, which is the bug where leaving the base to
## look at the classes and changing your mind dumped you out of the base.
func _on_back() -> void:
	ScenePaths.go_back(get_tree(), ScenePaths.MAIN_MENU)


func _on_lock_in() -> void:
	# THE STAR LADDER, not "every Star in the file". A class's three Stars
	# hold ONE tier — one on each rung of it — and this is what stops a
	# Tier IV Star ending up in a Tier I slot at HOLD UP. See tier_ladder.gd.
	var stars := db.star_ladder_for_class(_selected_class)
	if stars.is_empty():
		return

	var selection := TeamSelection.new()
	selection.unit_type = _selected_class
	selection.star_bundle = stars
	selection.active_star = stars[0]
	selection.star_tier = db.star_tier_for_class(_selected_class)
	TeamSelection.store(get_tree(), selection)

	ScenePaths.go_to(get_tree(), ScenePaths.TEAM_BUILDER)


# =============================================================
#  FORMATION DIAGRAM — a little pitch drawn in code
#  Mirrors default_layout() in main_scene.gd: three columns of three,
#  with the Star alone in its own column.
# =============================================================

class FormationDiagram extends Control:
	var star_tier: String = ""

	const TIERS: Array[String] = ["I", "II", "III", "IV"]
	const COLUMN_X := {"I": 0.13, "II": 0.31, "III": 0.49, "IV": 0.67}
	const ROW_Y: Array[float] = [0.22, 0.5, 0.78]

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w < 10.0 or h < 10.0:
			return

		# Pitch
		draw_rect(Rect2(0, 0, w, h), Color(0.13, 0.30, 0.17))
		draw_rect(Rect2(0, 0, w, h), Color(0.9, 0.95, 0.9, 0.5), false, 2.0)
		draw_line(Vector2(w * 0.5, 0), Vector2(w * 0.5, h), Color(0.9, 0.95, 0.9, 0.35), 2.0)
		draw_arc(Vector2(w * 0.5, h * 0.5), h * 0.14, 0.0, TAU, 32,
			Color(0.9, 0.95, 0.9, 0.35), 2.0)
		# Your goal box, on the left — the half your team defends.
		draw_rect(Rect2(0, h * 0.3, w * 0.06, h * 0.4), Color(0.9, 0.95, 0.9, 0.35), false, 2.0)

		var font := ThemeDB.fallback_font
		for tier in TIERS:
			var cx: float = w * float(COLUMN_X[tier])
			var is_star_column := tier == star_tier
			var colour := MenuSupport.COLOUR_ACCENT if is_star_column \
				else MenuSupport.colour_for_tier(tier)

			if is_star_column:
				# The Star stands alone in its tier.
				_dot(Vector2(cx, h * 0.5), colour, true)
			else:
				for fraction in ROW_Y:
					_dot(Vector2(cx, h * float(fraction)), colour, false)

			draw_string(font, Vector2(cx - 12.0, h - 8.0), "T%s" % tier,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.9, 0.95, 0.9, 0.8))

	func _dot(at: Vector2, colour: Color, is_star: bool) -> void:
		var radius := 11.0 if is_star else 8.0
		draw_circle(at, radius + 2.0, Color(0, 0, 0, 0.4))
		draw_circle(at, radius, colour)
		if is_star:
			draw_string(ThemeDB.fallback_font, at + Vector2(-5.0, 5.0), "★",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.1, 0.1, 0.1))
