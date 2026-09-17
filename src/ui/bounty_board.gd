class_name BountyBoard
extends Control

# =============================================================
#  THE BOUNTY BOARD — where an Adventure run starts
#
#      LEFT    the biomes. Locked ones are greyed and say what would open
#              them, the same way the unlock board does.
#      RIGHT   the bounties pinned up for the biome you clicked. A BOUNTY IS
#              A BOSS: the job is to go into that biome and kill the thing
#              named on the paper.
#      BOTTOM  what the chosen job pays, and START EXPLORING.
#
#  Everything on this screen is read from Biomes.csv and Bounties.csv.
#  Nothing here names a place, a boss or a reward.
#
#  WHAT START EXPLORING DOES, TODAY (Phase 1)
#    It opens the run, remembers which bounty you took, and sends you to the
#    class select and team builder so you can pick the squad you set off
#    with. The run then plays as an ordinary match.
#
#    THE SCROLLING FIELD, THE ENCOUNTERS AND THE LOOT ARE PHASE 2 ONWARDS.
#    This screen and its spreadsheets are finished; what happens after you
#    press the button is not, and that is deliberate — the board is worth
#    getting right before anything is built on top of it.
#
#  THIS SCREEN IS BUILT IN CODE, like the base and the unlock board. If you
#  would rather lay it out in the editor, season_screen.tscn is the pattern
#  to copy: the scene decides what it looks like and the script only fills
#  in nodes it finds by name.
# =============================================================

const CARD_SIZE := Vector2(250.0, 96.0)

var db: CardDatabase
var adventure: AdventureDB
var state: GameState

var _chosen_biome: Dictionary = {}
var _chosen_bounty: Dictionary = {}

var _biome_list: VBoxContainer
var _bounty_list: VBoxContainer
var _bounty_heading: Label
var _detail: Label
var _start: Button


func _ready() -> void:
	# Escape, controller navigation, the key bindings, the player's
	# settings and the language — all five from this one line. See
	# menu_escape.gd.
	MenuEscape.install(self)
	GameSpeed.reset()
	db = CardDatabase.get_db()
	adventure = AdventureDB.get_db()
	state = GameState.fetch(get_tree())

	_build_ui()
	_fill_biomes()

	# Open on the furthest biome you can actually walk into, so a returning
	# player is not made to click through the ones they have finished.
	var open := adventure.open_biomes(state)
	if not open.is_empty():
		_choose_biome(open[open.size() - 1])
	else:
		_refresh_bounties()


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

	page.add_child(MenuSupport.heading("THE BOUNTY BOARD", 32,
		MenuSupport.COLOUR_ACCENT))
	page.add_child(MenuSupport.heading(
		"Pick where you are going, then pick what you are going for. A bounty is the thing waiting at the end of it.",
		14, MenuSupport.COLOUR_TEXT_DIM))

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 20)
	page.add_child(columns)

	# --- LEFT: the biomes ---
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 6)
	columns.add_child(left)
	left.add_child(MenuSupport.heading("WHERE", 16, MenuSupport.COLOUR_TEXT_DIM))

	var left_scroll := ScrollContainer.new()
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(left_scroll)

	_biome_list = VBoxContainer.new()
	_biome_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_biome_list.add_theme_constant_override("separation", 8)
	left_scroll.add_child(_biome_list)

	# --- RIGHT: the bounties ---
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.4
	right.add_theme_constant_override("separation", 6)
	columns.add_child(right)

	_bounty_heading = MenuSupport.heading("WHAT", 16, MenuSupport.COLOUR_TEXT_DIM)
	right.add_child(_bounty_heading)

	var right_scroll := ScrollContainer.new()
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(right_scroll)

	_bounty_list = VBoxContainer.new()
	_bounty_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bounty_list.add_theme_constant_override("separation", 8)
	right_scroll.add_child(_bounty_list)

	# --- Footer: the standard one, Back on the left like every screen ---
	_detail = Label.new()
	var footer := MenuSupport.footer_bar(self, func() -> void:
		state.save_to_disk()
		ScenePaths.go_back(get_tree(), ScenePaths.BASE))
	footer.add_child(MenuSupport.footer_gap(_detail))
	page.add_child(footer)

	# THE INVENTORY, IN THE MIDDLE OF THE BOTTOM. The same bag that opens
	# from the base, from a fight and from the match draft — see
	# inventory_screen.gd. It used to be a screen of its own called YOUR KIT
	# that listed a third of what you were carrying as lines of text.
	#
	# EDIT ELEMENT BONUS SITS BESIDE IT, because both are things you settle
	# before you set off and neither belongs on a page of biomes. The two are
	# pinned as a PAIR - pinning them one at a time would put them both in the
	# middle, on top of each other.
	var middle := HBoxContainer.new()
	middle.add_theme_constant_override("separation", 10)
	add_child(middle)

	var items := MenuSupport.footer_button("inventory|\u2692",
		Loc.text("inventory", "Inventory"))
	items.tooltip_text = "Everything you are carrying \u2014 what you can use, what you can spend, and what you are holding on to."
	items.pressed.connect(_show_inventory)
	middle.add_child(items)

	var loadout := MenuSupport.footer_button("traits|\u25c8",
		Loc.text("edit_element_bonus", "Edit Element Bonus"))
	loadout.tooltip_text = "Which %d icons you carry into a run. Everything else you have unlocked stays on the shelf and does nothing." % TraitDB.slots(db)
	loadout.pressed.connect(_show_loadout)
	middle.add_child(loadout)

	# Its own footprint, or the pin would size it as a single button and the
	# pair would sit half off centre. Two buttons plus the gap between them.
	middle.custom_minimum_size = Vector2(
		MenuSupport.FOOTER_BUTTON.x * 2.0 + 10.0, MenuSupport.FOOTER_BUTTON.y)
	MenuSupport.pin_bottom_centre(middle)

	_start = MenuSupport.footer_primary("play|▶", "START EXPLORING")
	_start.disabled = true
	_start.pressed.connect(_on_start)
	footer.add_child(_start)


# -------------------------------------------------------------
#  THE BIOMES
# -------------------------------------------------------------

func _fill_biomes() -> void:
	for child in _biome_list.get_children():
		child.queue_free()

	var all := adventure.all_biomes()
	if all.is_empty():
		_biome_list.add_child(_quiet(
			"No biomes. Put rows in data/Biomes.csv and they appear here."))
		return

	for entry in all:
		_biome_list.add_child(_biome_card(entry))


func _biome_card(entry: Dictionary) -> Control:
	var open := DialogueGrammar.test(String(entry.get("requires", "")), state)

	var button := Button.new()
	button.custom_minimum_size = CARD_SIZE
	button.disabled = not open
	button.focus_mode = Control.FOCUS_NONE

	var tint := MenuSupport.COLOUR_ACCENT if open else MenuSupport.COLOUR_TEXT_DIM
	button.add_theme_stylebox_override("normal",
		MenuSupport.panel_style(MenuSupport.COLOUR_PANEL, tint))
	button.add_theme_stylebox_override("hover",
		MenuSupport.panel_style(MenuSupport.COLOUR_SLOT_EMPTY, tint))
	button.add_theme_stylebox_override("disabled",
		MenuSupport.panel_style(MenuSupport.COLOUR_LOCKED, MenuSupport.COLOUR_TEXT_DIM))

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("margin_left", 10)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	button.add_child(box)

	var title := Label.new()
	title.text = String(entry.get("name", "?"))
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color",
		MenuSupport.COLOUR_TEXT if open else MenuSupport.COLOUR_TEXT_DIM)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(title)

	var line := Label.new()
	if open:
		line.text = "%d wave%s   ·   %s" % [int(entry.get("waves", 1)),
			"" if int(entry.get("waves", 1)) == 1 else "s",
			String(entry.get("description", ""))]
	else:
		# THE SAME SENTENCE THE UNLOCK BOARD WOULD GIVE YOU. A locked place
		# always says what would open it, never just "locked".
		line.text = "🔒  %s" % DialogueGrammar.describe(String(entry.get("requires", "")))
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.add_theme_font_size_override("font_size", 12)
	line.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(line)

	if open:
		button.pressed.connect(_choose_biome.bind(entry))
	return button


func _choose_biome(entry: Dictionary) -> void:
	_chosen_biome = entry
	_chosen_bounty = {}
	_refresh_bounties()
	_refresh_footer()


# -------------------------------------------------------------
#  THE BOUNTIES
# -------------------------------------------------------------

func _refresh_bounties() -> void:
	for child in _bounty_list.get_children():
		child.queue_free()

	if _chosen_biome.is_empty():
		_bounty_heading.text = "WHAT"
		_bounty_list.add_child(_quiet(
			"Pick a biome on the left and its bounties are pinned up here."))
		return

	_bounty_heading.text = "WHAT  ·  %s" % String(_chosen_biome.get("name", "?"))

	var jobs := adventure.bounties_in(String(_chosen_biome.get("id", "")), state)
	if jobs.is_empty():
		_bounty_list.add_child(_quiet(
			"Nothing pinned up for %s. Add rows to data/Bounties.csv with Biome = %s."
			% [_chosen_biome.get("name", "?"), _chosen_biome.get("id", "")]))
		return

	for job in jobs:
		_bounty_list.add_child(_bounty_card(job))


func _bounty_card(job: Dictionary) -> Control:
	var open := bool(job.get("open", true))
	var done := bool(job.get("done", false))
	var boss := adventure.enemy(String(job.get("boss", "")))

	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 104)
	button.disabled = not open
	button.focus_mode = Control.FOCUS_NONE

	var tint := MenuSupport.COLOUR_TEXT_DIM
	if open:
		tint = MenuSupport.COLOUR_ACCENT if not done else MenuSupport.COLOUR_TEXT
	button.add_theme_stylebox_override("normal",
		MenuSupport.panel_style(MenuSupport.COLOUR_PANEL, tint))
	button.add_theme_stylebox_override("hover",
		MenuSupport.panel_style(MenuSupport.COLOUR_SLOT_EMPTY, tint))
	button.add_theme_stylebox_override("disabled",
		MenuSupport.panel_style(MenuSupport.COLOUR_LOCKED, MenuSupport.COLOUR_TEXT_DIM))

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(row)

	# The boss's picture, or a placeholder square — same rule as everywhere.
	var portrait := PanelContainer.new()
	portrait.custom_minimum_size = Vector2(84, 84)
	portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.add_theme_stylebox_override("panel",
		MenuSupport.panel_style(MenuSupport.COLOUR_SLOT_EMPTY, tint))
	var art := MenuSupport.icon_texture(String(job.get("art", "")))
	if art == null and not boss.is_empty():
		art = MenuSupport.icon_texture(String(boss.get("art", "")))
	if art != null:
		var rect := TextureRect.new()
		rect.texture = art
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portrait.add_child(rect)
	row.add_child(portrait)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	column.add_theme_constant_override("separation", 3)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(column)

	var title := Label.new()
	title.text = String(job.get("name", "?"))
	if done:
		title.text += "   ✓ claimed"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color",
		MenuSupport.COLOUR_TEXT if open else MenuSupport.COLOUR_TEXT_DIM)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(title)

	var line := Label.new()
	if open:
		line.text = _boss_line(boss, job)
	else:
		line.text = "🔒  %s" % DialogueGrammar.describe(String(job.get("requires", "")))
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.add_theme_font_size_override("font_size", 12)
	line.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(line)

	var pays := Label.new()
	pays.text = "Pays:  %s" % _reward_words(String(job.get("reward", "")))
	pays.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pays.add_theme_font_size_override("font_size", 12)
	pays.add_theme_color_override("font_color",
		MenuSupport.COLOUR_ACCENT if open else MenuSupport.COLOUR_TEXT_DIM)
	pays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(pays)

	if open:
		button.pressed.connect(_choose_bounty.bind(job))
	return button


## "The Marsh King — 3 layers, 42 deep, hits for 3. Suggested power 2."
##
## The layer count is the honest measure of how hard a boss is, so it is
## said out loud rather than left for you to work out from the CSV.
func _boss_line(boss: Dictionary, job: Dictionary) -> String:
	if boss.is_empty():
		return String(job.get("description", ""))

	# EVERY LOOKUP HERE USES .get() WITH A DEFAULT, on purpose.
	#
	# This line crashed the game once: the enemy's `damage` key was renamed to
	# `attack` when enemies lost their tiers, and this screen was still asking
	# for the old name. A missing key on a Dictionary is a hard error in
	# GDScript — it takes the whole game down rather than printing a warning.
	#
	# So a screen never demands a key. It asks for one with a sensible
	# fallback, and the worst a renamed or half-filled column can now do is
	# show a 0 where a number should be.
	var layers: Array = boss.get("layers", [])
	var bits: Array[String] = []
	bits.append("%s — %d layer%s, %d deep, hits for %d" % [
		boss.get("name", "it"), layers.size(), "" if layers.size() == 1 else "s",
		AdventureDB.total_layers(boss), int(boss.get("attack", 0))])
	if int(job.get("power", 0)) > 0:
		bits.append("suggested power %d" % int(job.get("power", 0)))
	var blurb := String(job.get("description", ""))
	if blurb != "":
		bits.append(blurb)
	return "   ·   ".join(bits)


## Turn an Effects string into something a player reads. `count:coins+120`
## becomes `120 coins`, and an item's real name comes from Items.csv.
func _reward_words(reward: String) -> String:
	var words: Array[String] = []
	for term in reward.split(";"):
		var part := String(term).strip_edges()
		if part == "":
			continue
		var lower := part.to_lower()
		if lower.begins_with("unlock:"):
			words.append(part.substr(7).strip_edges())
		elif lower.begins_with("count:"):
			var rest := part.substr(6)
			var at := rest.find("+")
			if at > 0:
				var item_id := rest.substr(0, at).strip_edges()
				var amount := rest.substr(at + 1).strip_edges()
				var known := adventure.item(item_id)
				words.append("%s %s" % [amount,
					String(known["name"]) if not known.is_empty() else item_id])
			else:
				words.append(rest.strip_edges())
		else:
			words.append(part)
	return "  ·  ".join(words) if not words.is_empty() else "nothing yet"


func _choose_bounty(job: Dictionary) -> void:
	_chosen_bounty = job
	_refresh_footer()


func _refresh_footer() -> void:
	if _chosen_bounty.is_empty():
		_detail.text = "Choose a bounty."
		_start.disabled = true
		return

	_start.disabled = false
	_detail.text = "%s  ·  %s  ·  %d wave%s before the boss." % [
		_chosen_bounty.get("name", "?"), _chosen_biome.get("name", "?"),
		maxi(0, int(_chosen_biome.get("waves", 1)) - 1),
		"" if int(_chosen_biome.get("waves", 1)) - 1 == 1 else "s"]


# -------------------------------------------------------------
#  SETTING OFF
# -------------------------------------------------------------

## THE INVENTORY, BEFORE YOU GO. Nothing is spent here — it is a reckoning,
## not a shop, so it opens with nothing clickable. The version that opens
## during a fight is the same window with Use.ITEM instead.
func _show_loadout() -> void:
	TraitLoadoutScreen.open(self, state, db)


func _show_inventory() -> void:
	InventoryScreen.open(self, state, InventoryScreen.Use.NOTHING,
		"Everything here comes with you. There is no packing.")


func _on_start() -> void:
	if _chosen_bounty.is_empty() or _chosen_biome.is_empty():
		return

	# The run is opened here and rides on the SceneTree from now on. Nothing
	# is written to your save until you carry a haul home — see
	# adventure_run.gd for why that matters.
	AdventureRun.begin(get_tree(), _chosen_bounty, _chosen_biome)

	MatchMode.choose(get_tree(), "adventure")
	state.save_to_disk()

	print("[adventure] Setting off: %s in %s (%d waves, boss %s)." % [
		_chosen_bounty.get("name", "?"), _chosen_biome.get("name", "?"),
		int(_chosen_biome.get("waves", 1)), _chosen_bounty.get("boss", "")])

	# THE TEAM SHELF, exactly the same one a league match uses. You pick a
	# side you already own, edit it, or build a new one — an Adventure squad
	# is not a different kind of thing from a league side, so it should not
	# be chosen a different way.
	#
	# The mode chosen just above is what sends LOCK IN to the scroll instead
	# of the pitch: MatchModes.csv gives `adventure` a Scene of `adventure`,
	# and team_select.gd reads that column. Nothing here names a screen.
	ScenePaths.go_to(get_tree(), ScenePaths.TEAM_SELECT)


# -------------------------------------------------------------
#  SMALL THINGS
# -------------------------------------------------------------

## THIS SCREEN'S BUTTONS ARE THE SHARED ONES NOW.
##
## It used to build its own plain Button here, which is why Back looked
## different depending on which screen you were standing on. It hands the job
## to MenuSupport.icon_button() instead, so every call site in this file gets
## the standard icon-and-label face without one of them being edited.
##
## `label` may carry its icon in front of it — "back|←  Back" — and otherwise
## a generic mark is used.
func _make_button(label: String, size: Vector2) -> Button:
	var icon := "◇"
	var words := label
	var bar := label.find("|")
	if bar >= 0:
		icon = label.substr(0, bar)
		words = label.substr(bar + 1)
	return MenuSupport.icon_button("%s|%s" % [icon, icon], words, size)
func _quiet(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	return label
