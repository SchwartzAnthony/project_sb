class_name TeamBuilder
extends Control

# =============================================================
#  BUILD YOUR TEAM — name it, badge it, pick the 9 regulars
#
#  TOP    the team's NAME and its BADGE. Both are what you will see on the
#         CHOOSE YOUR TEAM shelf, so this is where a side becomes a thing
#         you own rather than a line-up you rebuild every time.
#  LEFT   Tier I at the top down to Tier IV, three slots each.
#         The tier your Star Players live in is LOCKED — those three Stars
#         always hold it, and the match rotates through them at HOLD UP!.
#  RIGHT  your collection: every card of this class you can field.
#
#  Click a collection card    -> it takes its own POWER SLOT in its tier
#  Click a card in a slot     -> it goes back to the collection
#  Right-click either         -> read the full card
#  SAVE                       -> keep it and go back to the shelf
#  LOCK IN                    -> keep it AND walk straight out onto the pitch
#
#  ============ THE SLOTS ARE THE LADDER ============
#
#  A tier does not have "three free spaces". It has one slot per power:
#
#      Tier I     [ 0 ] [ 1 ] [ 2 ]
#      Tier II    [ 1 ] [ 2 ] [ 3 ]
#      Tier III   [ 2 ] [ 3 ] [ 4 ]
#      Tier IV    [ 3 ] [ 4 ] [ 5 ]
#
#  A 2-power card can only ever go in the 2 slot. Click one while another
#  2 is already standing there and they swap — the old one goes back to
#  the collection. That is the whole rule, and it means you can never
#  build a team of three 5s, and neither can the opposition.
#
#  The numbers come from data/TierPowers.csv. This screen does not know
#  them; it asks TierLadder, which reads that file. See tier_ladder.gd.
#
#  ============ WHERE THE TEAM GOES ============
#
#  Into user://teams.json, through team_roster.gd. It is stored by card NAME,
#  so editing a card's power in your CSV updates every saved team that fields
#  it instead of leaving a stale copy behind.
#
#  LIMITING THE COLLECTION: by default you can field every card of your class.
#  Add res://data/Collection.csv with "Card Name,Owned" rows to hide the ones
#  you have not unlocked. No file = everything is available.
# =============================================================

const ALL_TIERS: Array[String] = ["I", "II", "III", "IV"]
const COLLECTION_PATH := "res://data/Collection.csv"

## How many cards a tier holds when TierPowers.csv cannot be read. The real
## number is always TierLadder.slot_count(tier) — this is only the value
## handed to TeamSelection.is_complete(), which predates the ladder.
const PER_TIER := 3

## THE CARD FACE, AND IT IS BIGGER NOW. One number, and every card on this
## screen grows with it. The match pitch and the Adventure fight read their
## own size from Tuning.csv (`card_width` / `card_height`) so all three can be
## tuned without opening a script — see player_card_ui.gd.
const SLOT_SIZE := Vector2(168.0, 222.0)

var db: CardDatabase
var selection: TeamSelection
var state: GameState
var popup: CardPopup

## The saved team this screen is writing to, and the book it lives in.
var book: TeamRoster
var entry: Dictionary = {}

## Tier key -> { power: PlayerData }.
##
## Keyed BY POWER, not by position, because that is the rule: a card lives
## on the rung its power names. An absent key is an empty slot.
var _chosen: Dictionary = {}
## Every card of this class you are allowed to field, Stars excluded.
var _library: Array[PlayerData] = []

var _tier_column: VBoxContainer
var _collection_grid: GridContainer
var _status: Label
var _lock_button: Button
var _save_button: Button
var _title: Label
var _name_field: LineEdit
var _badge_slot: PanelContainer
var _badge_picker: Control


func _ready() -> void:
	db = CardDatabase.get_db()
	state = GameState.fetch(get_tree())
	MenuEscape.install(self)

	_load_team()
	_build_ui()

	if selection == null or selection.unit_type == "":
		_status.text = "No class chosen — go back and pick one."
		_status.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45))
		return

	_title.text = "BUILD YOUR TEAM  ·  %s" % selection.unit_type
	_load_library()

	# A team being EDITED arrives with cards already in it; a new one starts
	# empty and is auto-filled below into a legal line-up you then change.
	_read_saved_cards()
	_auto_fill()
	_refresh()


# -------------------------------------------------------------
#  WHICH TEAM AM I EDITING?
# -------------------------------------------------------------

## Two ways in, and this is the only place that has to tell them apart:
##
##   EDIT TEAM     the shelf stashed a team id, so we load that team and its
##                 class, and SAVE writes back over it.
##   CREATE TEAM   no id, so the class picker has just put a fresh
##                 TeamSelection on the tree and we start a brand new team
##                 from it.
func _load_team() -> void:
	book = TeamRoster.load_all()
	var wanted := TeamBuilderHandoff.current(get_tree())

	if wanted != "":
		entry = book.find(wanted)
		if not entry.is_empty():
			selection = book.to_selection(entry, db)
			print("[teams] Editing '%s'." % entry["name"])
			return
		print("[teams] The team being edited is gone from the save — starting a new one.")

	selection = TeamSelection.fetch(get_tree())
	if selection == null or selection.unit_type == "":
		entry = {}
		return
	entry = TeamRoster.blank(selection.unit_type, selection.star_tier)


## Put the saved line-up back in the slots. Any card the CSVs no longer have
## is simply missing, and AUTO-FILL below quietly replaces it — which is why
## deleting a card from a spreadsheet never breaks a saved team.
func _read_saved_cards() -> void:
	for tier in ALL_TIERS:
		if tier != selection.star_tier:
			_chosen[tier] = {}

	if entry.is_empty():
		return
	var saved := book.cards_for(entry, db)
	for tier in ALL_TIERS:
		if tier == selection.star_tier:
			continue
		var by_power: Dictionary = {}
		for card: PlayerData in (saved.get(tier, []) as Array):
			if card != null:
				by_power[TierLadder.rung_of(card)] = card
		_chosen[tier] = by_power


## The cards standing in a tier, weakest rung first. Gaps are simply absent,
## so this is never null-padded and callers can iterate it safely.
func _slotted(tier: String) -> Array[PlayerData]:
	var out: Array[PlayerData] = []
	var by_power: Dictionary = _chosen.get(tier, {})
	for power in TierLadder.rungs(tier, db):
		if by_power.has(power):
			out.append(by_power[power])
	return out


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
	var picked := _slotted(tier)
	var out: Array[PlayerData] = []
	for card in _library:
		if card.get_tier_clean() != tier:
			continue
		if picked.has(card):
			continue
		out.append(card)
	return out


## Fill every empty rung, leaving whatever you already chose where it stands.
##
## TierLadder does the choosing, so AUTO-FILL can never produce a team the
## rule would reject — and a tier with no card of some power comes back with
## that rung still empty rather than with a wrong card wedged into it.
func _auto_fill() -> void:
	for tier in ALL_TIERS:
		if tier == selection.star_tier:
			continue
		var result := TierLadder.repair(_slotted(tier), _available_in_tier(tier), tier, db)
		var by_power: Dictionary = {}
		for card: PlayerData in (result["cards"] as Array):
			by_power[TierLadder.rung_of(card)] = card
		_chosen[tier] = by_power


func _on_auto_fill() -> void:
	_auto_fill()
	_refresh()


func _clear_team() -> void:
	for tier in ALL_TIERS:
		if tier != selection.star_tier:
			_chosen[tier] = {}
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

	page.add_child(_build_identity_row())

	var hint := MenuSupport.heading(
		"Every tier holds one card of each power  ·  click a card on the right and it takes its own slot  ·  right-click any card to read it",
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

	var back := MenuSupport.icon_button("←", "Back", Vector2(150, 54))
	back.pressed.connect(_on_back)
	footer.add_child(back)

	var clear := MenuSupport.icon_button("✕", "Clear", Vector2(140, 54))
	clear.pressed.connect(_clear_team)
	footer.add_child(clear)

	var fill := MenuSupport.icon_button("⚄", "Auto-fill", Vector2(180, 54))
	fill.tooltip_text = "Fill every empty slot with a legal card."
	fill.pressed.connect(_on_auto_fill)
	footer.add_child(fill)

	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 14)
	_status.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	footer.add_child(_status)

	_save_button = MenuSupport.icon_button("💾", "Save", Vector2(170, 54))
	_save_button.tooltip_text = "Keep this team and go back to the shelf."
	_save_button.pressed.connect(_on_save_only)
	footer.add_child(_save_button)

	_lock_button = MenuSupport.icon_button("▶", "LOCK IN", Vector2(210, 54))
	_lock_button.tooltip_text = "Keep this team and take the pitch with it now."
	_lock_button.pressed.connect(_on_lock_in)
	footer.add_child(_lock_button)

	popup = CardPopup.new()
	popup.db = db
	add_child(popup)

	_build_badge_picker()


# -------------------------------------------------------------
#  THE NAME AND THE BADGE
# -------------------------------------------------------------

## The row that makes a line-up into a TEAM: what it is called and what mark
## it wears. Both are shown on the CHOOSE YOUR TEAM shelf, so this row is the
## only place either of them is set.
func _build_identity_row() -> Control:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel",
		MenuSupport.panel_style(MenuSupport.COLOUR_PANEL, MenuSupport.COLOUR_TEXT_DIM))

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 14)
	pad.add_theme_constant_override("margin_right", 14)
	pad.add_theme_constant_override("margin_top", 10)
	pad.add_theme_constant_override("margin_bottom", 10)
	frame.add_child(pad)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	pad.add_child(row)

	# The badge, as it will look on the shelf.
	_badge_slot = PanelContainer.new()
	_badge_slot.custom_minimum_size = Vector2(72, 72)
	_badge_slot.add_theme_stylebox_override("panel",
		MenuSupport.panel_style(MenuSupport.COLOUR_SLOT_EMPTY))
	row.add_child(_badge_slot)

	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	words.add_theme_constant_override("separation", 3)
	row.add_child(words)

	words.add_child(MenuSupport.heading("TEAM NAME", 12, MenuSupport.COLOUR_TEXT_DIM))

	_name_field = LineEdit.new()
	_name_field.placeholder_text = "Name this team"
	_name_field.max_length = 28
	_name_field.text = String(entry.get("name", ""))
	_name_field.add_theme_font_size_override("font_size", 22)
	_name_field.custom_minimum_size = Vector2(0, 40)
	_name_field.text_changed.connect(_on_name_typed)
	words.add_child(_name_field)

	var pick := MenuSupport.icon_button("◈", "Choose badge", Vector2(210, 54))
	pick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pick.tooltip_text = "Pick the shape and colour this team wears on the shelf.\nDrop a PNG in assets/team_icons/ and it is offered here too."
	pick.pressed.connect(func() -> void: _badge_picker.show())
	row.add_child(pick)

	_refresh_badge()
	return frame


func _on_name_typed(new_text: String) -> void:
	if not entry.is_empty():
		entry["name"] = new_text


## The name a blank field falls back to, so a team is never called "".
func _final_name() -> String:
	var typed := String(entry.get("name", "")).strip_edges()
	if typed != "":
		return typed
	return "%s XI" % selection.unit_type


func _refresh_badge() -> void:
	if _badge_slot == null:
		return
	for child in _badge_slot.get_children():
		child.queue_free()
	if entry.is_empty():
		return
	var badge := TeamRoster.badge(entry, 60.0)
	badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_badge_slot.add_child(badge)


## The badge chooser: twelve shapes across the top, six colours under them.
## Every one of them is drawn in code, so a team has a badge on day one and
## you can replace any of them later by dropping a PNG into
## assets/team_icons/ named after the shape.
func _build_badge_picker() -> void:
	_badge_picker = Control.new()
	_badge_picker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_badge_picker.hide()
	add_child(_badge_picker)

	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.66)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_badge_picker.add_child(shade)

	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge_picker.add_child(centre)

	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel",
		MenuSupport.panel_style(MenuSupport.COLOUR_PANEL, MenuSupport.COLOUR_ACCENT))
	centre.add_child(frame)

	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 22)
	frame.add_child(pad)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	pad.add_child(column)

	column.add_child(MenuSupport.heading("CHOOSE A BADGE", 26, MenuSupport.COLOUR_ACCENT))

	var shapes := GridContainer.new()
	shapes.columns = 6
	shapes.add_theme_constant_override("h_separation", 8)
	shapes.add_theme_constant_override("v_separation", 8)
	column.add_child(shapes)

	for shape in TeamRoster.EMBLEMS:
		shapes.add_child(_badge_option(shape))

	column.add_child(MenuSupport.heading("COLOUR", 12, MenuSupport.COLOUR_TEXT_DIM))

	var colours := HBoxContainer.new()
	colours.add_theme_constant_override("separation", 8)
	column.add_child(colours)

	for i in TeamRoster.EMBLEM_COLOURS.size():
		colours.add_child(_colour_option(i))

	var done := MenuSupport.icon_button("✓", "Done", Vector2(200, 50))
	done.pressed.connect(func() -> void: _badge_picker.hide())
	column.add_child(done)


func _badge_option(shape: String) -> Control:
	var button := Button.new()
	button.custom_minimum_size = Vector2(76, 76)
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = shape.capitalize()
	button.add_theme_stylebox_override("normal",
		MenuSupport.panel_style(MenuSupport.COLOUR_SLOT_EMPTY, MenuSupport.COLOUR_TEXT_DIM))
	button.add_theme_stylebox_override("hover",
		MenuSupport.panel_style(MenuSupport.COLOUR_SLOT_EMPTY, MenuSupport.COLOUR_ACCENT))
	button.pressed.connect(func() -> void:
		if not entry.is_empty():
			entry["icon"] = shape
			_refresh_badge())

	var face := Control.new()
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(face)
	# Drawn live, so changing the colour repaints every shape in the grid.
	face.draw.connect(func() -> void:
		var tint := TeamRoster.colour_of(entry) if not entry.is_empty() \
			else MenuSupport.COLOUR_ACCENT
		TeamRoster.draw_emblem(face, shape, tint, Rect2(Vector2.ZERO, face.size)))
	return button


func _colour_option(index: int) -> Control:
	var button := Button.new()
	button.custom_minimum_size = Vector2(60, 40)
	button.focus_mode = Control.FOCUS_NONE
	var tint := TeamRoster.EMBLEM_COLOURS[index]
	button.add_theme_stylebox_override("normal",
		MenuSupport.panel_style(tint, MenuSupport.COLOUR_TEXT_DIM))
	button.add_theme_stylebox_override("hover",
		MenuSupport.panel_style(tint.lightened(0.2), MenuSupport.COLOUR_ACCENT))
	button.pressed.connect(func() -> void:
		if entry.is_empty():
			return
		entry["colour"] = index
		_refresh_badge()
		# Repaint the shape grid so it shows the new colour straight away.
		_badge_picker.queue_redraw()
		for node in _badge_picker.find_children("", "Control", true, false):
			node.queue_redraw())
	return button


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
		var ladder := TierLadder.rungs(tier, db)

		# The Star tier is held by the three Stars, so it is shown from the
		# bundle and cannot be edited. Every other tier is shown rung by rung.
		var by_power: Dictionary = {}
		if is_star_tier:
			for card: PlayerData in selection.star_bundle:
				if card != null:
					by_power[TierLadder.rung_of(card)] = card
		else:
			by_power = _chosen.get(tier, {})

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
			header_text += "   %d / %d" % [by_power.size(), ladder.size()]
		var header := MenuSupport.heading(header_text, 17,
			MenuSupport.COLOUR_ACCENT if is_star_tier else MenuSupport.COLOUR_TEXT)
		header.tooltip_text = TierLadder.describe(tier, db)
		# A Label ignores the mouse by default, so its tooltip never appears.
		header.mouse_filter = Control.MOUSE_FILTER_STOP
		rows.add_child(header)

		var slots := HBoxContainer.new()
		slots.add_theme_constant_override("separation", 8)
		rows.add_child(slots)

		# ONE SLOT PER POWER, weakest on the left — the same order the cards
		# are offered in during a match, so the two screens read alike.
		for power in ladder:
			if by_power.has(power):
				slots.add_child(_make_slot_card(by_power[power], is_star_tier, tier, power))
			else:
				slots.add_child(_make_empty_slot(tier, power))


func _rebuild_collection() -> void:
	for child in _collection_grid.get_children():
		child.queue_free()

	# Grouped by tier, then weakest rung first — so the collection reads in
	# the same order as the slots it is going to fill.
	var any := false
	for tier in ALL_TIERS:
		if tier == selection.star_tier:
			continue
		var spare := _available_in_tier(tier)
		for power in TierLadder.rungs(tier, db):
			for card in spare:
				if TierLadder.rung_of(card) != power:
					continue
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
	# Named gaps, not counts. "Tier II still needs a 3" tells you which card
	# to look for; "Tier II needs 1 more" does not.
	var missing: Array[String] = []
	for tier in ALL_TIERS:
		if tier == selection.star_tier:
			continue
		var gap := TierLadder.needs_text(_slotted(tier), tier, db)
		if gap != "":
			missing.append(gap)

	if missing.is_empty():
		_status.text = "%s is ready — 1 Star + 9 regulars, one of every power." % _final_name()
		_status.add_theme_color_override("font_color", Color(0.55, 0.85, 0.6))
		_lock_button.disabled = false
		_save_button.disabled = false
	else:
		_status.text = "  ·  ".join(missing)
		_status.add_theme_color_override("font_color", Color(1.0, 0.72, 0.4))
		_lock_button.disabled = true
		# SAVING AN UNFINISHED TEAM IS ALLOWED. You can put a side half
		# together, go and look at something, and come back to it — the shelf
		# marks it as not ready to play rather than losing your work.
		_save_button.disabled = false


# -------------------------------------------------------------
#  CARD WIDGETS
# -------------------------------------------------------------

## An empty rung. It says which power it is waiting for, because "empty"
## on its own does not tell you which card in the collection would fill it.
func _make_empty_slot(tier: String, power: int) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = SLOT_SIZE
	panel.add_theme_stylebox_override("panel",
		MenuSupport.panel_style(MenuSupport.COLOUR_SLOT_EMPTY))
	panel.tooltip_text = "Only a %d-power Tier %s card fits here. %s" % [
		power, tier, TierLadder.describe(tier, db)]

	var label := Label.new()
	label.text = "%d\npower\n\nTier %s" % [power, tier]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	label.add_theme_font_size_override("font_size", 14)
	panel.add_child(label)
	return panel


## A card sitting in your team. Clicking it sends it back to the collection,
## unless it is a Star — those are fixed.
func _make_slot_card(card: PlayerData, locked: bool, tier: String, power: int) -> Control:
	var button := _card_button(card, locked)
	if locked:
		button.tooltip_text = "%s is a Star Player and always holds the %d slot of Tier %s.\nRight-click to read the card." \
			% [card.player_name, power, tier]
	else:
		button.tooltip_text = "%s holds the %d slot of Tier %s.\nClick to send it back to the collection.\nRight-click to read the card." \
			% [card.player_name, power, tier]
		button.pressed.connect(_remove_card.bind(card, tier))
	return button


## A card in the collection. Clicking it takes its own rung, swapping out
## whoever is standing there — so the tooltip says which of the two it is.
func _make_collection_card(card: PlayerData) -> Control:
	var button := _card_button(card, false)
	var tier := card.get_tier_clean()
	var power := TierLadder.rung_of(card)
	var standing := (_chosen.get(tier, {}) as Dictionary).get(power, null) as PlayerData

	if standing == null:
		button.tooltip_text = "Click to put %s in the %d slot of Tier %s.\nRight-click to read the card." \
			% [card.player_name, power, tier]
	else:
		button.tooltip_text = "Click to swap %s in for %s — both are %d power, and Tier %s holds one of each.\nRight-click to read the card." \
			% [card.player_name, standing.player_name, power, tier]
	button.pressed.connect(_add_card.bind(card))
	return button


## The shared card face, so the builder, the match draft and the Adventure
## fight all draw a player the same way. `locked` marks a Star's own tier.
func _card_button(card: PlayerData, locked: bool) -> Button:
	var button := MenuSupport.card_face(card, db, SLOT_SIZE)
	if locked:
		button.add_theme_stylebox_override("normal", MenuSupport.panel_style(
			MenuSupport.COLOUR_PANEL, MenuSupport.COLOUR_ACCENT))
	button.gui_input.connect(_on_card_input.bind(card))
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

## Put a card on its own rung. Whoever was standing there goes back to the
## collection — a straight swap, never a rejection, because there is exactly
## one slot this card could ever want and you have just asked for it.
func _add_card(card: PlayerData) -> void:
	var tier := card.get_tier_clean()
	if tier == selection.star_tier:
		return

	var power := TierLadder.rung_of(card)
	if not TierLadder.rungs(tier, db).has(power):
		# Only reachable if a CSV was edited while the screen was open.
		_status.text = "%s is %d power, and %s" % [
			card.player_name, power, TierLadder.describe(tier, db).to_lower()]
		_status.add_theme_color_override("font_color", Color(1.0, 0.72, 0.4))
		return

	var by_power: Dictionary = _chosen.get(tier, {})
	var replaced := by_power.get(power, null) as PlayerData
	by_power[power] = card
	_chosen[tier] = by_power

	_refresh()
	if replaced != null and replaced != card:
		_status.text = "%s takes the %d slot — %s goes back to the collection." % [
			card.player_name, power, replaced.player_name]
		_status.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)


func _remove_card(card: PlayerData, tier: String) -> void:
	var by_power: Dictionary = _chosen.get(tier, {})
	var power := TierLadder.rung_of(card)
	if by_power.get(power, null) == card:
		by_power.erase(power)
	_chosen[tier] = by_power
	_refresh()


# -------------------------------------------------------------
#  KEEPING IT
# -------------------------------------------------------------

## Write the team to user://teams.json. Returns the line-up tier by tier so
## LOCK IN can hand the same thing straight to the match.
func _save_team() -> Dictionary:
	var flat: Dictionary = {}
	# Reached with no class chosen only if this screen was opened directly
	# from the editor. Better to do nothing than to crash on it.
	if selection == null or selection.unit_type == "":
		return flat
	for tier in ALL_TIERS:
		if tier == selection.star_tier:
			continue
		flat[tier] = _slotted(tier)

	if entry.is_empty():
		return flat

	entry["name"] = _final_name()
	entry["class"] = selection.unit_type
	entry["star_tier"] = selection.star_tier
	TeamRoster.set_cards(entry, flat)
	book.put(entry)
	book.save()
	return flat


func _on_back() -> void:
	# LEAVING WITHOUT SAVING IS NOT A TRAP. Half-built teams are kept, so
	# Back is never the button that loses twenty minutes of work.
	_save_team()
	ScenePaths.go_back(get_tree(), TeamBuilderHandoff.back_to(get_tree()))


func _on_save_only() -> void:
	_save_team()
	state.set_text("last_team", String(entry.get("id", "")))
	state.save_to_disk()
	ScenePaths.go_to(get_tree(), ScenePaths.TEAM_SELECT)


## LOCK IN — keep the team AND play with it right now. This is the button
## the shelf's own LOCK IN skips the builder for; here it does both.
func _on_lock_in() -> void:
	if selection == null or selection.unit_type == "":
		return
	for tier in ALL_TIERS:
		if tier == selection.star_tier:
			continue
		if not TierLadder.legal(_slotted(tier), tier, db):
			_update_status()
			return

	var flat := _save_team()
	selection.regulars = flat
	if not selection.is_complete(ALL_TIERS, PER_TIER):
		_update_status()
		return

	TeamSelection.store(get_tree(), selection)
	state.set_text("last_team", String(entry.get("id", "")))
	state.save_to_disk()
	print("[team] Kicking off as %s:\n%s" % [_final_name(), selection.describe()])

	# WHERE THIS TEAM IS GOING is decided by the mode's Scene column, not by
	# this screen. A league match goes to the pitch; an Adventure run goes to
	# the scroll. Point a new mode at a new screen and this needs no edit.
	var scene := String(MatchMode.current(get_tree()).get("scene", "match"))
	ScenePaths.go_to(get_tree(), ScenePaths.for_name(scene))
