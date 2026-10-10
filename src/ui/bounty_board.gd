class_name BountyBoard
extends Control

# =============================================================
#  THE BOUNTY BOARD — where an Adventure run starts
#  (adventure-look, 10 Oct: now the SOCCER & TRAINING BOARD in a beer cave)
#
#      TOP     the biomes, one tab each. Locked ones are greyed and say in
#              their tooltip what would open them.
#      MIDDLE  the board, with the jobs for that biome pinned on it as
#              scrolls. A BOUNTY IS A BOSS: the job is to go into that biome
#              and kill the thing named on the paper.
#      CLICK   a scroll and it unrolls in its own window: the quest, what you
#              need, what it pays, BACK and ACCEPT CONTRACT.
#
#  Everything on this screen is read from Biomes.csv and Bounties.csv.
#  Nothing here names a place, a boss or a reward.
#
#  WHAT ACCEPT CONTRACT DOES (it was START EXPLORING), TODAY (Phase 1)
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

## ============ THE SOCCER & TRAINING BOARD  (adventure-look, 10 Oct) ============
##
## Anthony: the Bounty board becomes a soccer & training board in a Bavarian
## beer cave. The jobs hang on it as scrolls; clicking one UNROLLS it in its
## own window (contract_scroll.gd) with the rewards, the quest text, what you
## need and ACCEPT CONTRACT. Back rolls it up and you can read another.
##
## THE PICTURES are Tuning.csv rows, so new art is a file name, not code:
##     adventure_board_background   the beer cave behind everything
##     adventure_board_art          the board the scrolls hang on
##     adventure_board_pin_art      one rolled-up scroll on the board
## Blank or missing: plain colours stand in, and the screen still works.
##
## WHERE EACH SCROLL HANGS is Bounties.csv: Pin X and Pin Y, from 0 (left /
## top of the board) to 1 (right / bottom). Blank = laid out in rows.
## Kind (Match, Training ...) is written over the name on the scroll.

const PIN_SIZE := Vector2(190.0, 118.0)
const WOOD := Color(0.36, 0.22, 0.12)
const WOOD_EDGE := Color(0.18, 0.10, 0.05)
const SCROLL_PAPER := Color(0.86, 0.76, 0.56)

var db: CardDatabase
var adventure: AdventureDB
var state: GameState

var _chosen_biome: Dictionary = {}
var _chosen_bounty: Dictionary = {}

var _biome_tabs: HBoxContainer
var _board: Control
var _pins: Control
var _bounty_heading: Label
var _detail: Label
var _scroll: ContractScroll = null


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
	# ROUND AN: the Head Coach's Guide.csv rows for the Adventure board.
	(func() -> void: Guide.check(self, "bounty", state)).call_deferred()

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

func _picture(key: String) -> Texture2D:
	return MenuSupport.icon_texture(db.tune_text(key, "")) if db != null else null


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# THE BEER CAVE. Its colour first, the picture over it when there is one.
	var background := ColorRect.new()
	background.color = Color(0.10, 0.07, 0.06)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var cave := _picture("adventure_board_background")
	if cave != null:
		var cave_rect := TextureRect.new()
		cave_rect.texture = cave
		cave_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		cave_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		cave_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		cave_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		cave_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(cave_rect)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	margin.add_child(page)

	page.add_child(MenuSupport.heading(
		Loc.text("adventure_board_title", "THE SOCCER & TRAINING BOARD"), 32,
		MenuSupport.COLOUR_ACCENT))

	# WHERE: one tab per biome across the top. A locked one is greyed and
	# says in its tooltip what would open it.
	_biome_tabs = HBoxContainer.new()
	_biome_tabs.add_theme_constant_override("separation", 8)
	_biome_tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	page.add_child(_biome_tabs)

	_bounty_heading = MenuSupport.heading("", 16, MenuSupport.COLOUR_TEXT)
	_bounty_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(_bounty_heading)

	# THE BOARD, in the middle, with the scrolls hanging on it.
	var holder := CenterContainer.new()
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(holder)

	var board_size := Vector2(
		db.tune_float("adventure_board_width", 1000.0),
		db.tune_float("adventure_board_height", 520.0))
	var art := _picture("adventure_board_art")
	if art != null:
		var board_rect := TextureRect.new()
		board_rect.texture = art
		board_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		board_rect.stretch_mode = TextureRect.STRETCH_SCALE
		board_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_board = board_rect
	else:
		var panel := Panel.new()
		panel.add_theme_stylebox_override("panel", _wood())
		_board = panel
	_board.custom_minimum_size = board_size
	holder.add_child(_board)

	_pins = Control.new()
	_pins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var inset := db.tune_float("adventure_board_inset", 48.0)
	_pins.offset_left = inset
	_pins.offset_top = inset
	_pins.offset_right = -inset
	_pins.offset_bottom = -inset
	_board.add_child(_pins)

	# --- Footer: the standard one, Back on the left like every screen ---
	_detail = Label.new()
	var footer := MenuSupport.footer_bar(self, func() -> void:
		state.save_to_disk()
		ScenePaths.go_back(get_tree(), ScenePaths.BASE))
	footer.add_child(MenuSupport.footer_gap(_detail))
	page.add_child(footer)

	# THE INVENTORY, IN THE MIDDLE OF THE BOTTOM, with EDIT ELEMENT BONUS
	# beside it - both are things you settle before you set off. Pinned as a
	# PAIR so they do not land on top of each other. See inventory_screen.gd.
	var middle := HBoxContainer.new()
	middle.add_theme_constant_override("separation", 10)
	add_child(middle)

	var items := MenuSupport.footer_button("inventory|⚒",
		Loc.text("inventory", "Inventory"))
	items.tooltip_text = "Everything you are carrying — what you can use, what you can spend, and what you are holding on to."
	items.pressed.connect(_show_inventory)
	middle.add_child(items)

	var loadout := MenuSupport.icon_button("traits|◈",
		Loc.text("edit_element_bonus", "Edit Element Bonus"),
		Vector2(290, MenuSupport.FOOTER_BUTTON.y))
	loadout.tooltip_text = "Which %d icons you carry into a run. Everything else you have unlocked stays on the shelf and does nothing." % TraitDB.slots(db)
	loadout.pressed.connect(_show_loadout)
	middle.add_child(loadout)

	middle.custom_minimum_size = Vector2(
		MenuSupport.FOOTER_BUTTON.x + 290.0 + 10.0, MenuSupport.FOOTER_BUTTON.y)
	MenuSupport.pin_bottom_centre(middle)


func _wood() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = WOOD
	style.border_color = WOOD_EDGE
	style.set_border_width_all(10)
	style.set_corner_radius_all(6)
	return style


# -------------------------------------------------------------
#  THE BIOMES
# -------------------------------------------------------------

func _fill_biomes() -> void:
	for child in _biome_tabs.get_children():
		child.queue_free()

	var all := adventure.all_biomes()
	if all.is_empty():
		_biome_tabs.add_child(_quiet(
			"No biomes. Put rows in data/Biomes.csv and they appear here."))
		return

	for entry in all:
		_biome_tabs.add_child(_biome_tab(entry))


func _biome_tab(entry: Dictionary) -> Control:
	var open := DialogueGrammar.test(String(entry.get("requires", "")), state)
	# The button's own text is the biome's name: the Head Coach's Guide.csv
	# rows find it by those words.
	var tab := Button.new()
	tab.text = String(entry.get("name", "?")) if open \
		else "🔒 " + String(entry.get("name", "?"))
	tab.custom_minimum_size = Vector2(200, 44)
	tab.disabled = not open
	tab.focus_mode = Control.FOCUS_NONE
	if open:
		tab.tooltip_text = "%d waves  ·  %s" % [int(entry.get("waves", 1)),
			String(entry.get("description", ""))]
		tab.pressed.connect(_choose_biome.bind(entry))
	else:
		# A locked place always says what would open it, never just "locked".
		tab.tooltip_text = DialogueGrammar.describe(String(entry.get("requires", "")))
	var chosen := String(entry.get("id", "")) == String(_chosen_biome.get("id", "-"))
	var tint := MenuSupport.COLOUR_ACCENT if chosen else MenuSupport.COLOUR_TEXT_DIM
	tab.add_theme_stylebox_override("normal",
		MenuSupport.panel_style(MenuSupport.COLOUR_PANEL, tint))
	tab.add_theme_stylebox_override("hover",
		MenuSupport.panel_style(MenuSupport.COLOUR_SLOT_EMPTY, MenuSupport.COLOUR_ACCENT))
	tab.add_theme_stylebox_override("disabled",
		MenuSupport.panel_style(MenuSupport.COLOUR_LOCKED, MenuSupport.COLOUR_TEXT_DIM))
	return tab


func _choose_biome(entry: Dictionary) -> void:
	_chosen_biome = entry
	_chosen_bounty = {}
	_fill_biomes()
	_refresh_bounties()
	_refresh_footer()


# -------------------------------------------------------------
#  THE SCROLLS ON THE BOARD
# -------------------------------------------------------------

func _refresh_bounties() -> void:
	for child in _pins.get_children():
		child.queue_free()

	if _chosen_biome.is_empty():
		_bounty_heading.text = ""
		_pins.add_child(_quiet(
			"Pick a place at the top and its jobs are pinned up here."))
		return

	_bounty_heading.text = String(_chosen_biome.get("name", "?"))

	var jobs := adventure.bounties_in(String(_chosen_biome.get("id", "")), state)
	if jobs.is_empty():
		_pins.add_child(_quiet(
			"Nothing pinned up for %s. Add rows to data/Bounties.csv with Biome = %s."
			% [_chosen_biome.get("name", "?"), _chosen_biome.get("id", "")]))
		return

	# Where each one hangs: its own Pin X / Pin Y, or the next slot in rows.
	var room := _board.custom_minimum_size - Vector2.ONE * 2.0 \
		* db.tune_float("adventure_board_inset", 48.0)
	var per_row := maxi(1, int(room.x / (PIN_SIZE.x + 16.0)))
	var slot := 0
	for job in jobs:
		var pin := _scroll_pin(job)
		var spot := Vector2(float(job.get("pin_x", -1.0)), float(job.get("pin_y", -1.0)))
		if spot.x < 0.0 or spot.y < 0.0:
			spot = Vector2(
				(float(slot % per_row) + 0.5) / float(per_row),
				(float(slot / per_row) + 0.5) / maxf(1.0, ceilf(float(jobs.size()) / per_row)))
			slot += 1
		pin.position = Vector2(spot.x * room.x, spot.y * room.y) - PIN_SIZE * 0.5
		# A slight tilt each, so it reads as paper someone pinned up by hand.
		pin.pivot_offset = PIN_SIZE * 0.5
		pin.rotation_degrees = float(hash(String(job.get("id", ""))) % 7 - 3)
		_pins.add_child(pin)


## One rolled-up scroll on the board: its kind, its name, and what it pays.
func _scroll_pin(job: Dictionary) -> Control:
	var open := bool(job.get("open", true))
	var done := bool(job.get("done", false))

	var button := Button.new()
	button.name = "Pin_" + String(job.get("id", ""))
	button.custom_minimum_size = PIN_SIZE
	button.size = PIN_SIZE
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = String(job.get("description", ""))

	var pin_art := _picture("adventure_board_pin_art")
	if pin_art != null:
		var flat := StyleBoxTexture.new()
		flat.texture = pin_art
		for state_name in ["normal", "hover", "pressed", "disabled"]:
			button.add_theme_stylebox_override(state_name, flat)
	else:
		var paper := SCROLL_PAPER if open else SCROLL_PAPER.darkened(0.45)
		button.add_theme_stylebox_override("normal", MenuSupport.panel_style(paper, WOOD_EDGE))
		button.add_theme_stylebox_override("hover",
			MenuSupport.panel_style(paper.lightened(0.12), MenuSupport.COLOUR_ACCENT))
		button.add_theme_stylebox_override("pressed", MenuSupport.panel_style(paper, WOOD_EDGE))
	if not open:
		button.modulate = Color(0.7, 0.7, 0.7)

	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 2)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(column)

	var kind := String(job.get("kind", ""))
	if kind != "":
		column.add_child(_pin_line(kind.to_upper(), 11, MenuSupport.COLOUR_ACCENT))
	var title := String(job.get("name", "?"))
	if done:
		title += "  ✓"
	column.add_child(_pin_line(title, 15, MenuSupport.COLOUR_TEXT))
	if not open:
		column.add_child(_pin_line("🔒", 13, MenuSupport.COLOUR_TEXT_DIM))
	elif int(job.get("power", 0)) > 0:
		column.add_child(_pin_line("P %d" % int(job.get("power", 0)), 12,
			MenuSupport.COLOUR_TEXT_DIM))

	# Even a locked scroll opens: it says what you still need.
	button.pressed.connect(_open_scroll.bind(job))
	return button


## Light words on the see-through black plate, the one rule for text.
func _pin_line(text: String, font_size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	label.add_theme_stylebox_override("normal", TextBackdrop.plate())
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


# -------------------------------------------------------------
#  THE SCROLL WINDOW
# -------------------------------------------------------------

func _open_scroll(job: Dictionary) -> void:
	if _scroll != null and is_instance_valid(_scroll):
		return
	_chosen_bounty = job
	_refresh_footer()
	_scroll = ContractScroll.open(self, _scroll_words(job))
	_scroll.accepted.connect(_on_start)
	_scroll.closed.connect(func() -> void:
		_scroll = null
		_chosen_bounty = {}
		_refresh_footer())


## Everything the scroll says, from the CSV row.
func _scroll_words(job: Dictionary) -> Dictionary:
	var boss := adventure.enemy(String(job.get("boss", "")))
	var quest := String(job.get("quest", ""))
	if quest == "":
		quest = String(job.get("description", ""))

	var needs: Array[String] = []
	var requires := String(job.get("requires", "")).strip_edges()
	if requires != "":
		var met := bool(job.get("open", true))
		needs.append("%s%s" % ["" if met else "🔒 ",
			DialogueGrammar.describe(requires)])
	if int(job.get("power", 0)) > 0:
		needs.append("Suggested power %d" % int(job.get("power", 0)))
	var waves := int(job.get("waves", 0))
	if waves <= 0:
		waves = int(_chosen_biome.get("waves", 1))
	needs.append("%d wave%s, then %s" % [maxi(0, waves - 1),
		"" if waves - 1 == 1 else "s", _boss_line(boss, {})])

	var rewards: Array[String] = []
	for bit in _reward_words(String(job.get("reward", ""))).split("  ·  "):
		rewards.append(bit)
	if not bool(job.get("repeatable", false)):
		rewards.append("Once only")

	return {
		"title": String(job.get("name", "?")),
		"kind": String(job.get("kind", "")),
		"quest": quest,
		"requirements": needs,
		"rewards": rewards,
		"open": bool(job.get("open", true)) and not bool(job.get("done", false)),
	}


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


func _refresh_footer() -> void:
	if _chosen_bounty.is_empty():
		_detail.text = "Click a scroll on the board to read it."
		return
	_detail.text = "%s  ·  %s" % [
		_chosen_bounty.get("name", "?"), _chosen_biome.get("name", "?")]


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
