class_name AdventureEncounter
extends CanvasLayer

# =============================================================
#  THE ENCOUNTER — Phase 3
#
#  The party has stopped, the enemies are in the way, and this is the fight.
#
#  ============ ONE ROUND, IN ORDER ============
#
#   1. FOCUS      Pick one enemy. Hover any of them to read what it is —
#                 what it hits for, and the layers you would have to chew
#                 through. Everything your four tiers do this round goes
#                 into the one you pick.
#   2. ITEMS      Optional, and only before the drafting starts. Revive
#                 somebody, patch somebody up, or throw something.
#   3. DRAFT      Tier I, then II, then III, then IV. One card each, from
#                 whoever is still standing in that tier.
#   4. FLEE       Available until you commit the FOURTH tier. After that you
#                 are in it.
#   5. YOUR HIT   The four powers are added up and go into the focused
#                 enemy's outermost layer, minus that layer's soak.
#   6. THEIR HIT  THEN every living enemy strikes back, one after another.
#
#  ============ WHY ENEMIES HAVE NO TIERS ============
#
#  They used to, and the fight was four separate duels. It is one fight now:
#  your whole line-up hits the enemy you chose, and then the enemies hit
#  you. An enemy is two numbers — Attack, and Layers — which is far easier
#  to write content for and far easier to read on screen.
#
#  ============ THE TWO RULES THAT KEEP IT FAIR ============
#
#  A TIER WITH NOBODY LEFT IS A WALKOVER. Not a thin tier — a COMPLETELY
#  empty one, every player in it knocked out. That tier adds nothing to your
#  hit, and the enemies' damage is doubled for the round. Losing a whole
#  tier is meant to hurt.
#
#  ENEMIES SPREAD THEIR DAMAGE. Each one hits the weakest player in
#  whichever tier currently has the MOST players standing, lowest tier
#  first on a tie. So the tiers stay level with each other and no single
#  tier is quietly wiped out — which is what would create the walkover
#  above. An enemy whose Targeting column says `strongest`,
#  `lowest_stamina` or `aoe` breaks that rule on purpose.
#
#  Everything here is driven by AdventureEnemies.csv, Items.csv and the
#  adventure_* rows of Tuning.csv. No enemy, item or number is named in
#  this file.
# =============================================================

signal finished(cleared: bool, fled: bool)

enum Step { FOCUS, DRAFT, RESOLVING, DONE }

var db: CardDatabase
var adventure: AdventureDB
var state: GameState
var run: AdventureRun

var step: Step = Step.FOCUS

## One entry per enemy in the wave:
##   {"row": the CSV row, "left": Array[int] of layer amounts remaining}
var foes: Array[Dictionary] = []
var _focus: int = -1

## The card chosen for each tier this round, tier key -> PlayerData.
var _picked: Dictionary = {}
var _tier_index: int = 0

var _title: Label
var _prompt: Label
var _foe_row: HBoxContainer
var _detail: Label
var _choice_row: HBoxContainer
var _log: VBoxContainer
var _item_button: Button
var _flee_button: Button


# =============================================================
#  OPENING
# =============================================================

static func open(parent: Node, database: CardDatabase, save: GameState,
		the_run: AdventureRun, wave: Array[Dictionary]) -> AdventureEncounter:
	var fight := AdventureEncounter.new()
	fight.db = database
	fight.state = save
	fight.run = the_run
	fight.adventure = AdventureDB.get_db()
	fight.layer = 15
	for entry in wave:
		fight.foes.append(_fresh_foe(entry))
	parent.add_child(fight)
	return fight


## A wave's enemy, with full layers. The CSV row is never written to — the
## damage lives in `left`, exactly the way stamina lives on the run.
static func _fresh_foe(row: Dictionary) -> Dictionary:
	var left: Array[int] = []
	for layer in (row.get("layers", []) as Array):
		left.append(int((layer as Dictionary)["amount"]))
	return {"row": row, "left": left}


func _ready() -> void:
	_build_ui()
	_begin_round()


# =============================================================
#  A ROUND
# =============================================================

func _begin_round() -> void:
	step = Step.FOCUS
	_picked.clear()
	_tier_index = 0
	if _focus < 0 or not _is_alive(_focus):
		_focus = _first_living()
	_refresh()


func _is_alive(index: int) -> bool:
	if index < 0 or index >= foes.size():
		return false
	for amount in (foes[index]["left"] as Array):
		if int(amount) > 0:
			return true
	return false


func _first_living() -> int:
	for i in foes.size():
		if _is_alive(i):
			return i
	return -1


func _living_count() -> int:
	var n := 0
	for i in foes.size():
		if _is_alive(i):
			n += 1
	return n


## The tier being drafted right now, or "" once all four are in.
func _current_tier() -> String:
	if _tier_index < 0 or _tier_index >= TierLadder.TIERS.size():
		return ""
	return TierLadder.TIERS[_tier_index]


# =============================================================
#  DRAFTING
# =============================================================

func _choose_focus(index: int) -> void:
	if step != Step.FOCUS:
		return
	_focus = index
	step = Step.DRAFT
	_tier_index = 0
	_note("Focusing %s." % _foe_name(index))
	_refresh()


func _pick_card(card: PlayerData) -> void:
	if step != Step.DRAFT:
		return
	var tier := _current_tier()
	if tier == "":
		return
	_picked[tier] = card
	_tier_index += 1
	_note("Tier %s: %s (%d)" % [tier, card.player_name, card.get_attack_power()])

	_refresh()


## Walk past any tier with nobody left in it, marking each as empty so the
## walkover can be counted when the round resolves.
##
## Done in ONE loop before anything is drawn. The first version skipped from
## inside the drawing code, which re-entered it half way through and then
## drew buttons for the tier it had just left behind.
func _advance_past_empty_tiers() -> bool:
	var skipped := false
	while step == Step.DRAFT and _current_tier() != "":
		var tier := _current_tier()
		if not run.standing_in(tier, db).is_empty():
			break
		_picked[tier] = null
		_tier_index += 1
		skipped = true
		_note("Tier %s has nobody left — they come straight through it." % tier)
	return skipped


# =============================================================
#  RESOLVING
# =============================================================

func _resolve() -> void:
	step = Step.RESOLVING
	_refresh()

	# --- YOUR HIT: the four tiers added up ---
	var total := 0
	var empty_tiers := 0
	for tier in TierLadder.TIERS:
		var card := _picked.get(tier, null) as PlayerData
		if card == null:
			empty_tiers += 1
		else:
			total += card.get_attack_power()

	var scale := db.tune_float("adventure_damage_scale", 1.0)
	var least := db.tune_int("adventure_damage_minimum", 1)
	var dealt := maxi(least, int(round(float(total) * scale)))

	if _focus >= 0 and _is_alive(_focus):
		var report := _hurt_foe(_focus, dealt)
		_note("Your line-up totals %d — %s" % [total, report])
	await _beat()

	# --- THEIR HIT: after yours, every one of them ---
	if _living_count() == 0:
		_note("The way is clear.")
		step = Step.DONE
		await _beat()
		finished.emit(true, false)
		return

	# A COMPLETELY EMPTY TIER DOUBLES WHAT THEY DO. Not a thin one — an
	# empty one. See the header.
	var multiplier := 1
	if empty_tiers > 0:
		multiplier = db.tune_int("adventure_walkover_multiplier", 2)
		_note("%d tier(s) empty — everything they do lands twice." % empty_tiers)

	for i in foes.size():
		if not _is_alive(i):
			continue
		await _enemy_strikes(i, multiplier)
		if run.party_is_down():
			break

	_refresh()
	await _beat()

	if run.party_is_down():
		_note("Everybody is down.")
		step = Step.DONE
		finished.emit(false, false)
		return

	_begin_round()


## Damage into the outermost layer that is still there, minus its soak.
## Returns a sentence for the log.
func _hurt_foe(index: int, amount: int) -> String:
	var foe: Dictionary = foes[index]
	var row: Dictionary = foe["row"]
	var left: Array = foe["left"]
	var layers: Array = row.get("layers", [])
	var least := db.tune_int("adventure_damage_minimum", 1)

	for i in left.size():
		if int(left[i]) <= 0:
			continue
		var soak := int((layers[i] as Dictionary)["soak"])
		# The minimum is applied AFTER the soak, so a thick layer always
		# gives way eventually. A soak is a wall that slows you, never one
		# that stops you.
		var through := maxi(least, amount - soak)
		left[i] = maxi(0, int(left[i]) - through)

		var layer_name := String((layers[i] as Dictionary)["name"])
		if int(left[i]) <= 0:
			if i == left.size() - 1:
				return "%d through the %s. %s is finished." % [
					through, layer_name, _foe_name(index)]
			return "%d through the %s — it breaks." % [through, layer_name]
		return "%d into %s's %s (%d left)." % [
			through, _foe_name(index), layer_name, int(left[i])]

	return "%s was already down." % _foe_name(index)


## One enemy's turn. Who it hits is its Targeting column; how hard is its
## Attack, doubled when a tier of yours stood empty.
func _enemy_strikes(index: int, multiplier: int) -> void:
	var row: Dictionary = foes[index]["row"]
	var hit := maxi(1, int(row["attack"]) * multiplier)
	var how := String(row["targeting"])

	if how == "aoe":
		# ONE PER TIER, not everybody on the pitch. Hitting all twelve made an
		# aoe enemy three times stronger than any other and it decided fights
		# on its own; the weakest of each tier is four targets, which is a
		# proper sweep without being a different game.
		var caught := 0
		for tier in TierLadder.TIERS:
			var standing := run.standing_in(tier, db)
			if standing.is_empty():
				continue
			if run.hurt(standing[0], hit, db):
				_note("%s is knocked out." % standing[0].player_name)
			caught += 1
		_note("%s sweeps every tier for %d — %d caught." % [
			_foe_name(index), hit, caught])
	else:
		var victim := _target_for(how)
		if victim == null:
			return
		var went_down := run.hurt(victim, hit, db)
		_note("%s hits %s for %d.%s" % [_foe_name(index), victim.player_name, hit,
			"  KNOCKED OUT." if went_down else ""])

	_refresh()
	await _beat(0.45)


## ============ WHO AN ENEMY GOES FOR ============
##
## `weakest` is the default and the one that matters: the weakest player in
## whichever tier has the MOST still standing, lowest tier first on a tie.
##
## That is what keeps your four tiers level with each other. Hitting Tier I
## every time would empty it, and an empty tier doubles their damage — so
## the default rule is the one that does NOT spiral. Enemies that break it
## are the interesting ones, and they say so in their Targeting column.
func _target_for(how: String) -> PlayerData:
	var everyone: Array[PlayerData] = []
	var best_tier := ""
	var best_count := 0

	for tier in TierLadder.TIERS:
		var standing := run.standing_in(tier, db)
		everyone.append_array(standing)
		if standing.size() > best_count:
			best_count = standing.size()
			best_tier = tier

	if everyone.is_empty():
		return null

	match how:
		"strongest":
			var strongest: PlayerData = everyone[0]
			for card in everyone:
				if card.get_attack_power() > strongest.get_attack_power():
					strongest = card
			return strongest
		"lowest_stamina":
			var hurt_most: PlayerData = everyone[0]
			for card in everyone:
				if run.stamina_of(card, db) < run.stamina_of(hurt_most, db):
					hurt_most = card
			return hurt_most
		_:
			# `weakest`, and anything unrecognised.
			var fullest := run.standing_in(best_tier, db)
			return fullest[0] if not fullest.is_empty() else everyone[0]


# =============================================================
#  ITEMS
# =============================================================

func _open_items() -> void:
	if step != Step.FOCUS and step != Step.DRAFT:
		return
	var carried := adventure.usable_items(state)
	_choice_row.visible = false

	for child in _log.get_children():
		if child.name == "ItemMenu":
			child.queue_free()

	var menu := VBoxContainer.new()
	menu.name = "ItemMenu"
	menu.add_theme_constant_override("separation", 4)
	_log.add_child(menu)
	_log.move_child(menu, 0)

	menu.add_child(MenuSupport.heading("YOUR KIT", 14, MenuSupport.COLOUR_TEXT_DIM))
	if carried.is_empty():
		menu.add_child(_quiet("Nothing you can use. Items with a Use column in Items.csv show up here."))
	for entry in carried:
		var button := Button.new()
		button.text = "%s  x%d   —   %s" % [entry["name"], int(entry["held"]),
			entry["description"]]
		button.custom_minimum_size = Vector2(0, 34)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_use_item.bind(entry))
		menu.add_child(button)

	var close := Button.new()
	close.text = "Close the kit"
	close.custom_minimum_size = Vector2(0, 32)
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func() -> void:
		menu.queue_free()
		_refresh())
	menu.add_child(close)


## Items are counters, so "using one" is spending a counter and applying the
## Use column. Everything here works on any item you add tomorrow.
func _use_item(entry: Dictionary) -> void:
	var use := String(entry["use"])
	var did := ""

	if use.begins_with("revive"):
		if run.knocked_out.is_empty():
			_note("Nobody is down.")
			return
		var back: PlayerData = run.knocked_out[0]
		run.knocked_out.erase(back)
		var half := maxi(1, int(AdventureRun.stamina_for(back, db) / 2))
		run.stamina[back] = half
		did = "%s is back on, at %d stamina." % [back.player_name, half]

	elif use.begins_with("heal"):
		var amount := _number_in(use, 4)
		var everyone := use.contains("all")
		var mended := 0
		for tier in TierLadder.TIERS:
			for card in run.standing_in(tier, db):
				var cap := AdventureRun.stamina_for(card, db)
				run.stamina[card] = mini(cap, run.stamina_of(card, db) + amount)
				mended += 1
				if not everyone:
					break
			if mended > 0 and not everyone:
				break
		did = "%d stamina back to %d player(s)." % [amount, mended]

	elif use.begins_with("hit"):
		if _focus < 0 or not _is_alive(_focus):
			_note("Pick something to throw it at first.")
			return
		did = _hurt_foe(_focus, _number_in(use, 3))

	else:
		_note("'%s' is not a Use this game knows. Try revive, heal:6 or hit:4." % use)
		return

	state.add_count(String(entry["id"]), -1)
	state.save_to_disk()
	_note("%s — %s" % [entry["name"], did])
	for child in _log.get_children():
		if child.name == "ItemMenu":
			child.queue_free()
	_refresh()


## The number in "heal:6" or "hit:4".
static func _number_in(text: String, fallback: int) -> int:
	var at := text.find(":")
	if at < 0:
		return fallback
	var rest := text.substr(at + 1)
	var digits := ""
	for c in rest:
		if c >= "0" and c <= "9":
			digits += c
		elif digits != "":
			break
	return int(digits) if digits != "" else fallback


# =============================================================
#  FLEEING
# =============================================================

func _flee() -> void:
	# THE FOURTH TIER IS THE POINT OF NO RETURN. Up to then you may walk.
	if step == Step.RESOLVING or step == Step.DONE:
		return

	var keep := db.tune_float("adventure_flee_keep", 0.8)
	var lost := run.flee_loss(keep)
	var words: Array[String] = []
	for key in lost.keys():
		var known := adventure.item(String(key))
		words.append("%d %s" % [int(lost[key]),
			String(known["name"]) if not known.is_empty() else String(key)])

	_confirm("Leave now?",
		"You keep %d%% of what you are carrying.%s" % [int(keep * 100.0),
			("\n\nYou would lose:  " + "  ·  ".join(words)) if not words.is_empty()
			else "\n\nYou are carrying nothing, so it costs you nothing."],
		"Run for it", func() -> void:
			step = Step.DONE
			finished.emit(false, true))


# =============================================================
#  DRAWING IT
# =============================================================

func _build_ui() -> void:
	var holder := Control.new()
	holder.name = "Holder"
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(holder)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = 20.0
	panel.offset_right = -20.0
	panel.offset_top = -300.0
	panel.offset_bottom = -16.0
	panel.add_theme_stylebox_override("panel", MenuSupport.panel_style(
		Color(0.09, 0.10, 0.13, 0.94), MenuSupport.COLOUR_ACCENT))
	holder.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	_title = MenuSupport.heading("COMBAT", 24, MenuSupport.COLOUR_ACCENT)
	column.add_child(_title)

	_prompt = Label.new()
	_prompt.add_theme_font_size_override("font_size", 15)
	_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_prompt)

	# --- the enemies ---
	_foe_row = HBoxContainer.new()
	_foe_row.add_theme_constant_override("separation", 10)
	column.add_child(_foe_row)

	_detail = Label.new()
	_detail.add_theme_font_size_override("font_size", 13)
	_detail.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.custom_minimum_size = Vector2(0, 34)
	column.add_child(_detail)

	# --- the cards on offer ---
	_choice_row = HBoxContainer.new()
	_choice_row.add_theme_constant_override("separation", 10)
	column.add_child(_choice_row)

	# --- the running log, and the two always-there buttons ---
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	column.add_child(bottom)

	_log = VBoxContainer.new()
	_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log.add_theme_constant_override("separation", 2)
	bottom.add_child(_log)

	_item_button = Button.new()
	_item_button.text = "ITEMS"
	_item_button.custom_minimum_size = Vector2(120, 42)
	_item_button.focus_mode = Control.FOCUS_NONE
	_item_button.tooltip_text = "Revive somebody, patch somebody up, or throw something. Before the drafting only."
	_item_button.pressed.connect(_open_items)
	bottom.add_child(_item_button)

	_flee_button = Button.new()
	_flee_button.text = "FLEE"
	_flee_button.custom_minimum_size = Vector2(120, 42)
	_flee_button.focus_mode = Control.FOCUS_NONE
	_flee_button.pressed.connect(_flee)
	bottom.add_child(_flee_button)


func _refresh() -> void:
	if step == Step.DRAFT:
		_advance_past_empty_tiers()
		if _current_tier() == "":
			# Every tier is in (or empty). Resolve on the next frame rather
			# than from inside a redraw.
			_resolve.call_deferred()
			return

	_refresh_foes()
	_refresh_choices()

	var alive := _living_count()
	_title.text = "COMBAT   ·   %d left" % alive

	match step:
		Step.FOCUS:
			_prompt.text = "Pick who to go after. Everything your four tiers do this round lands on them."
		Step.DRAFT:
			var tier := _current_tier()
			var standing := run.standing_in(tier, db)
			if standing.is_empty():
				_prompt.text = "Tier %s has nobody left." % tier
			else:
				_prompt.text = "Tier %s — choose who takes it. (%d of 4)" % [
					tier, _tier_index + 1]
		Step.RESOLVING:
			_prompt.text = "..."
		Step.DONE:
			_prompt.text = ""

	# THE POINT OF NO RETURN. Flee is live until the fourth tier is in.
	_flee_button.disabled = step == Step.RESOLVING or step == Step.DONE
	_flee_button.text = "FLEE" if not _flee_button.disabled else "—"
	_item_button.disabled = step == Step.RESOLVING or step == Step.DONE


func _refresh_foes() -> void:
	for child in _foe_row.get_children():
		child.queue_free()

	for i in foes.size():
		var row: Dictionary = foes[i]["row"]
		var alive := _is_alive(i)

		var button := Button.new()
		button.custom_minimum_size = Vector2(180, 78)
		button.focus_mode = Control.FOCUS_NONE
		button.disabled = not alive or step != Step.FOCUS
		button.text = "%s\n%s" % [row["name"], _layer_text(i)]
		button.add_theme_font_size_override("font_size", 13)

		var lit := (i == _focus and alive)
		var tint := MenuSupport.COLOUR_ACCENT if lit else MenuSupport.COLOUR_TEXT_DIM
		button.add_theme_stylebox_override("normal", MenuSupport.panel_style(
			MenuSupport.COLOUR_PANEL if alive else MenuSupport.COLOUR_LOCKED, tint))
		button.add_theme_stylebox_override("disabled", MenuSupport.panel_style(
			MenuSupport.COLOUR_PANEL if alive else MenuSupport.COLOUR_LOCKED, tint))
		button.add_theme_stylebox_override("hover", MenuSupport.panel_style(
			MenuSupport.COLOUR_SLOT_EMPTY, MenuSupport.COLOUR_ACCENT))

		# HOVER TO READ IT. This is the JRPG bit: everything about an enemy
		# is one mouse-over away, before you commit anything.
		button.mouse_entered.connect(_describe_foe.bind(i))
		button.mouse_exited.connect(func() -> void: _detail.text = "")
		if alive and step == Step.FOCUS:
			button.pressed.connect(_choose_focus.bind(i))
		_foe_row.add_child(button)


func _describe_foe(index: int) -> void:
	var row: Dictionary = foes[index]["row"]
	var left: Array = foes[index]["left"]
	var layers: Array = row.get("layers", [])

	var parts: Array[String] = []
	for i in layers.size():
		var layer: Dictionary = layers[i]
		var soak := int(layer["soak"])
		parts.append("%s %d/%d%s" % [layer["name"], int(left[i]),
			int(layer["amount"]),
			"  (soaks %d)" % soak if soak > 0 else ""])

	_detail.text = "%s — hits for %d, goes for the %s.   %s   %s" % [
		row["name"], int(row["attack"]), row["targeting"],
		"  |  ".join(parts), row["description"]]


func _layer_text(index: int) -> String:
	var left: Array = foes[index]["left"]
	var total := 0
	for amount in left:
		total += int(amount)
	if total <= 0:
		return "down"
	return "%d left  ·  hits %d" % [total, int(foes[index]["row"]["attack"])]


func _refresh_choices() -> void:
	for child in _choice_row.get_children():
		child.queue_free()
	if step != Step.DRAFT:
		return

	var tier := _current_tier()
	if tier == "":
		return

	# _advance_past_empty_tiers() ran first, so there is always somebody here.
	var standing := run.standing_in(tier, db)
	_choice_row.visible = true

	for card in standing:
		var button := Button.new()
		button.custom_minimum_size = Vector2(140, 74)
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 13)
		button.text = "%s\npower %d  ·  %d hp" % [card.player_name,
			card.get_attack_power(), run.stamina_of(card, db)]
		var tint := MenuSupport.colour_for_tier(tier)
		button.add_theme_stylebox_override("normal",
			MenuSupport.panel_style(MenuSupport.COLOUR_PANEL, tint))
		button.add_theme_stylebox_override("hover",
			MenuSupport.panel_style(MenuSupport.COLOUR_SLOT_EMPTY, MenuSupport.COLOUR_ACCENT))
		button.pressed.connect(_pick_card.bind(card))
		_choice_row.add_child(button)


# =============================================================
#  SMALL THINGS
# =============================================================

func _foe_name(index: int) -> String:
	if index < 0 or index >= foes.size():
		return "it"
	return String((foes[index]["row"] as Dictionary)["name"])


## One line in the running log. The oldest are dropped so the panel never
## grows past its box.
func _note(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT)
	_log.add_child(label)
	print("[fight] %s" % text)

	while _log.get_child_count() > 5:
		var oldest := _log.get_child(0)
		if oldest.name == "ItemMenu":
			break
		_log.remove_child(oldest)
		oldest.queue_free()


func _beat(seconds: float = 0.7) -> void:
	await get_tree().create_timer(seconds).timeout


func _quiet(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	return label


## A yes/no box. Used by Flee, and ready for anything else that should ask.
func _confirm(title: String, body: String, yes_text: String,
		on_yes: Callable) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_node("Holder").add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -240.0
	panel.offset_right = 240.0
	panel.offset_top = -130.0
	panel.offset_bottom = 130.0
	panel.add_theme_stylebox_override("panel", MenuSupport.panel_style(
		MenuSupport.COLOUR_PANEL, MenuSupport.COLOUR_ACCENT))
	dim.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	column.add_child(MenuSupport.heading(title, 22, MenuSupport.COLOUR_ACCENT))
	column.add_child(_quiet(body))

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	column.add_child(buttons)

	var yes := Button.new()
	yes.text = yes_text
	yes.custom_minimum_size = Vector2(180, 44)
	yes.focus_mode = Control.FOCUS_NONE
	yes.pressed.connect(func() -> void:
		dim.queue_free()
		on_yes.call())
	buttons.add_child(yes)

	var no := Button.new()
	no.text = "Stay and fight"
	no.custom_minimum_size = Vector2(180, 44)
	no.focus_mode = Control.FOCUS_NONE
	no.pressed.connect(func() -> void: dim.queue_free())
	buttons.add_child(no)
