class_name TeamBuilder
extends Control

# =============================================================
#  TEAM BUILDER — pick the 9 regulars who take the pitch
#
#  LEFT   Tier I at the top down to Tier IV, three slots each.
#         The tier your Star Players live in is LOCKED — those three Stars
#         always hold it, and the match rotates through them at HOLD UP!.
#  RIGHT  your collection: every card of this class you can field.
#
#  Click a collection card    -> it drops into the first free slot of its tier
#  Click a card in a slot     -> it goes back to the collection
#  Right-click either         -> read the full card
#  READY                      -> kick off with exactly this team
#
#  LIMITING THE COLLECTION: by default you can field every card of your class.
#  Add res://data/Collection.csv with "Card Name,Owned" rows to hide the ones
#  you have not unlocked. No file = everything is available.
# =============================================================

const ALL_TIERS: Array[String] = ["I", "II", "III", "IV"]
const PER_TIER := 3
const COLLECTION_PATH := "res://data/Collection.csv"

var db: CardDatabase
var selection: TeamSelection
var popup: CardPopup

## Tier key -> Array[PlayerData], at most PER_TIER long.
var _chosen: Dictionary = {}
## Every card of this class you are allowed to field, Stars excluded.
var _library: Array[PlayerData] = []

var _tier_column: VBoxContainer
var _collection_grid: GridContainer
var _status: Label
var _ready_button: Button
var _title: Label


func _ready() -> void:
	db = CardDatabase.get_db()
	selection = TeamSelection.fetch(get_tree())

	_build_ui()

	if selection == null or selection.unit_type == "":
		_status.text = "No class chosen — go back and pick one."
		_status.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45))
		return

	_title.text = "BUILD YOUR TEAM  ·  %s" % selection.unit_type
	_load_library()
	for tier in ALL_TIERS:
		if tier != selection.star_tier:
			_chosen[tier] = [] as Array[PlayerData]

	_auto_fill()      # start from a legal team; swap from there
	_refresh()


# -------------------------------------------------------------
#  DATA
# -------------------------------------------------------------

func _load_library() -> void:
	_library = db.roster_for_class(selection.unit_type)

	# Optional Collection.csv trims the library to cards you own.
	var rows := MenuSupport.read_csv(COLLECTION_PATH)
	if rows.is_empty():
		return

	var owned: Dictionary = {}
	for row in rows:
		var card_name := MenuSupport.field(row, "Card Name")
		if card_name == "":
			continue
		var flag := MenuSupport.field(row, "Owned", "true").to_lower()
		owned[MenuSupport.normalise(card_name)] = not (flag in ["false", "0", "no"])

	var filtered: Array[PlayerData] = []
	for card in _library:
		var key := MenuSupport.normalise(card.player_name)
		# A card missing from Collection.csv stays available — the file is a
		# blocklist as much as an allowlist, so a half-filled file is harmless.
		if owned.get(key, true):
			filtered.append(card)
	_library = filtered


## Cards of `tier` that are not already slotted.
func _available_in_tier(tier: String) -> Array[PlayerData]:
	var picked: Array = _chosen.get(tier, [])
	var out: Array[PlayerData] = []
	for card in _library:
		if card.get_tier_clean() != tier:
			continue
		if picked.has(card):
			continue
		out.append(card)
	return out


func _auto_fill() -> void:
	for tier in ALL_TIERS:
		if tier == selection.star_tier:
			continue
		var existing: Array = _chosen.get(tier, [])
		var picked: Array[PlayerData] = []
		picked.assign(existing)
		var spare := _available_in_tier(tier)
		spare.shuffle()
		while picked.size() < PER_TIER and not spare.is_empty():
			picked.append(spare.pop_back())
		_chosen[tier] = picked


func _on_auto_fill() -> void:
	_auto_fill()
	_refresh()


func _clear_team() -> void:
	for tier in ALL_TIERS:
		if tier != selection.star_tier:
			_chosen[tier] = [] as Array[PlayerData]
	_refresh()


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
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	margin.add_child(page)

	_title = MenuSupport.heading("BUILD YOUR TEAM", 32, MenuSupport.COLOUR_ACCENT)
	page.add_child(_title)

	var hint := MenuSupport.heading(
		"Click a card on the right to add it  ·  click one on the left to remove it  ·  right-click any card to read it",
		13, MenuSupport.COLOUR_TEXT_DIM)
	page.add_child(hint)

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 20)
	page.add_child(columns)

	# --- LEFT: your team, tier by tier ---
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.15
	left.add_theme_constant_override("separation", 6)
	columns.add_child(left)

	left.add_child(MenuSupport.heading("YOUR TEAM", 16, MenuSupport.COLOUR_TEXT_DIM))

	var left_scroll := ScrollContainer.new()
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(left_scroll)

	_tier_column = VBoxContainer.new()
	_tier_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tier_column.add_theme_constant_override("separation", 10)
	left_scroll.add_child(_tier_column)

	# --- RIGHT: the collection ---
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	columns.add_child(right)

	right.add_child(MenuSupport.heading("COLLECTION", 16, MenuSupport.COLOUR_TEXT_DIM))

	var right_scroll := ScrollContainer.new()
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(right_scroll)

	_collection_grid = GridContainer.new()
	_collection_grid.columns = 3
	_collection_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_collection_grid.add_theme_constant_override("h_separation", 8)
	_collection_grid.add_theme_constant_override("v_separation", 8)
	right_scroll.add_child(_collection_grid)

	# --- Footer ---
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	page.add_child(footer)

	var back := Button.new()
	back.text = "◀  CHANGE CLASS"
	back.custom_minimum_size = Vector2(180, 52)
	back.pressed.connect(_on_change_class)
	footer.add_child(back)

	var clear := Button.new()
	clear.text = "CLEAR"
	clear.custom_minimum_size = Vector2(110, 52)
	clear.pressed.connect(_clear_team)
	footer.add_child(clear)

	var fill := Button.new()
	fill.text = "AUTO-FILL"
	fill.custom_minimum_size = Vector2(140, 52)
	fill.pressed.connect(_on_auto_fill)
	footer.add_child(fill)

	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	footer.add_child(_status)

	_ready_button = Button.new()
	_ready_button.text = "READY  ▶"
	_ready_button.custom_minimum_size = Vector2(200, 52)
	_ready_button.pressed.connect(_on_ready)
	footer.add_child(_ready_button)

	popup = CardPopup.new()
	popup.db = db
	add_child(popup)


# -------------------------------------------------------------
#  REDRAW
# -------------------------------------------------------------

func _refresh() -> void:
	_rebuild_tiers()
	_rebuild_collection()
	_update_status()


func _rebuild_tiers() -> void:
	for child in _tier_column.get_children():
		child.queue_free()

	for tier in ALL_TIERS:
		var is_star_tier := tier == selection.star_tier
		var picked: Array = selection.star_bundle if is_star_tier else _chosen.get(tier, [])

		var block := PanelContainer.new()
		block.add_theme_stylebox_override("panel", MenuSupport.panel_style(
			MenuSupport.COLOUR_LOCKED if is_star_tier else MenuSupport.COLOUR_PANEL))
		_tier_column.add_child(block)

		var rows := VBoxContainer.new()
		rows.add_theme_constant_override("separation", 6)
		block.add_child(rows)

		var header_text := "TIER %s" % tier
		if is_star_tier:
			header_text += "   🔒  your Star Players — always these three"
		else:
			header_text += "   %d / %d" % [picked.size(), PER_TIER]
		rows.add_child(MenuSupport.heading(header_text, 17,
			MenuSupport.COLOUR_ACCENT if is_star_tier else MenuSupport.COLOUR_TEXT))

		var slots := HBoxContainer.new()
		slots.add_theme_constant_override("separation", 8)
		rows.add_child(slots)

		for i in PER_TIER:
			if i < picked.size():
				var card: PlayerData = picked[i]
				slots.add_child(_make_slot_card(card, is_star_tier, tier))
			else:
				slots.add_child(_make_empty_slot(tier))


func _rebuild_collection() -> void:
	for child in _collection_grid.get_children():
		child.queue_free()

	var any := false
	for tier in ALL_TIERS:
		if tier == selection.star_tier:
			continue
		for card in _available_in_tier(tier):
			_collection_grid.add_child(_make_collection_card(card))
			any = true

	if not any:
		var note := MenuSupport.heading(
			"Every card is on the pitch. Click one on the left to bring it back here.",
			14, MenuSupport.COLOUR_TEXT_DIM)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_collection_grid.add_child(note)


func _update_status() -> void:
	if selection == null:
		return
	var missing: Array[String] = []
	for tier in ALL_TIERS:
		if tier == selection.star_tier:
			continue
		var count: int = (_chosen.get(tier, []) as Array).size()
		if count < PER_TIER:
			missing.append("Tier %s needs %d more" % [tier, PER_TIER - count])

	if missing.is_empty():
		_status.text = "Team is ready — 1 Star + 9 regulars."
		_status.add_theme_color_override("font_color", Color(0.55, 0.85, 0.6))
		_ready_button.disabled = false
	else:
		_status.text = "  ·  ".join(missing)
		_status.add_theme_color_override("font_color", Color(1.0, 0.72, 0.4))
		_ready_button.disabled = true


# -------------------------------------------------------------
#  CARD WIDGETS
# -------------------------------------------------------------

const SLOT_SIZE := Vector2(128, 168)


func _make_empty_slot(tier: String) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = SLOT_SIZE
	panel.add_theme_stylebox_override("panel",
		MenuSupport.panel_style(MenuSupport.COLOUR_SLOT_EMPTY))

	var label := Label.new()
	label.text = "empty\nTier %s" % tier
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	label.add_theme_font_size_override("font_size", 13)
	panel.add_child(label)
	return panel


## A card sitting in your team. Clicking it sends it back to the collection,
## unless it is a Star — those are fixed.
func _make_slot_card(card: PlayerData, locked: bool, tier: String) -> Control:
	var button := _card_button(card, locked)
	if locked:
		button.tooltip_text = "%s is a Star Player and always holds Tier %s.\nRight-click to read the card." \
			% [card.player_name, tier]
	else:
		button.tooltip_text = "Click to send %s back to the collection.\nRight-click to read the card." \
			% card.player_name
		button.pressed.connect(_remove_card.bind(card, tier))
	return button


## A card in the collection. Clicking it slots it into its tier.
func _make_collection_card(card: PlayerData) -> Control:
	var button := _card_button(card, false)
	button.tooltip_text = "Click to put %s into Tier %s.\nRight-click to read the card." \
		% [card.player_name, card.get_tier_clean()]
	button.pressed.connect(_add_card.bind(card))
	return button


## The shared card face: portrait, name, tier badge, power.
func _card_button(card: PlayerData, locked: bool) -> Button:
	var button := Button.new()
	button.custom_minimum_size = SLOT_SIZE
	button.gui_input.connect(_on_card_input.bind(card))

	var tint := MenuSupport.colour_for_tier(card.get_tier_clean())
	if locked:
		tint = MenuSupport.COLOUR_ACCENT
	button.add_theme_stylebox_override("normal",
		MenuSupport.panel_style(MenuSupport.COLOUR_PANEL, tint))
	button.add_theme_stylebox_override("hover",
		MenuSupport.panel_style(MenuSupport.COLOUR_SLOT_EMPTY, tint))
	button.add_theme_stylebox_override("pressed",
		MenuSupport.panel_style(MenuSupport.COLOUR_SLOT_EMPTY, MenuSupport.COLOUR_ACCENT))

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	button.add_child(box)

	var portrait := MenuSupport.portrait_rect(card, db, Vector2(112, 96))
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(portrait)

	var name_label := Label.new()
	name_label.text = card.player_name
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(name_label)

	var footer := Label.new()
	var star_mark := "★ " if card.is_star() else ""
	footer.text = "%sT%s   %d/%d" % [star_mark, card.get_tier_clean(),
		card.get_attack_power(), card.get_defense_power()]
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_font_size_override("font_size", 12)
	footer.add_theme_color_override("font_color", tint.lightened(0.35))
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(footer)

	# Stars carry the pitch badge here too, so the locked Star tier reads as
	# special rather than merely uneditable.
	if card.is_star():
		var badge := StarBadge.make_marker(false, 26.0)
		button.add_child(badge)
		badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		badge.offset_left = -30.0
		badge.offset_top = 3.0
		badge.offset_right = -4.0
		badge.offset_bottom = 29.0

	return button


## Right-click anywhere on a card opens its full text.
func _on_card_input(event: InputEvent, card: PlayerData) -> void:
	if event is InputEventMouseButton \
			and event.pressed \
			and event.button_index == MOUSE_BUTTON_RIGHT:
		popup.show_card(card)
		accept_event()


# -------------------------------------------------------------
#  ADD / REMOVE
# -------------------------------------------------------------

func _add_card(card: PlayerData) -> void:
	var tier := card.get_tier_clean()
	if tier == selection.star_tier:
		return
	var existing: Array = _chosen.get(tier, [])
	var picked: Array[PlayerData] = []
	picked.assign(existing)
	if picked.size() >= PER_TIER:
		_status.text = "Tier %s is full — remove someone first." % tier
		_status.add_theme_color_override("font_color", Color(1.0, 0.72, 0.4))
		return
	if picked.has(card):
		return
	picked.append(card)
	_chosen[tier] = picked
	_refresh()


func _remove_card(card: PlayerData, tier: String) -> void:
	var existing: Array = _chosen.get(tier, [])
	var picked: Array[PlayerData] = []
	picked.assign(existing)
	picked.erase(card)
	_chosen[tier] = picked
	_refresh()


# -------------------------------------------------------------
#  KICK OFF
# -------------------------------------------------------------

func _on_change_class() -> void:
	ScenePaths.go_to(get_tree(), ScenePaths.CLASS_SELECT)


func _on_ready() -> void:
	selection.regulars = _chosen.duplicate(true)
	if not selection.is_complete(ALL_TIERS, PER_TIER):
		_update_status()
		return

	TeamSelection.store(get_tree(), selection)
	print("[team] Kicking off with:\n%s" % selection.describe())
	ScenePaths.go_to(get_tree(), ScenePaths.MATCH)
