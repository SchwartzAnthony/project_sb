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
## Which enemy the pointer is over on the pitch, or -1.
var _hovered: int = -1

## The card chosen for each tier this round, tier key -> PlayerData.
var _picked: Dictionary = {}
var _tier_index: int = 0

## ============ THE PITCH, FOR THE ANIMATION ============
##
## The fight decides what happens; adventure_strike.gd decides what it looks
## like. To show it, this needs three things from the scene: the node the
## ball can be added to, the enemies' nodes, and a way to find the walker
## for a given card. All three are optional — with none of them the fight
## still resolves exactly the same, just without anything to watch.
var stage: Node2D = null
var foe_nodes: Array[Node2D] = []
var walker_for: Callable = Callable()
## The run's own ball, so a kick sends THAT rather than conjuring a new one.
var ball: Node2D = null

var _title: Label
var _prompt: Label
var _foe_row: HBoxContainer
var _detail: Label
var _choice_row: HBoxContainer
var _log: VBoxContainer
var _item_button: Button
var _flee_button: Button
var _log_button: Button
var _log_panel: PanelContainer


# =============================================================
#  OPENING
# =============================================================

static func open(parent: Node, database: CardDatabase, save: GameState,
		the_run: AdventureRun, wave: Array[Dictionary],
		pitch: Node2D = null, nodes: Array[Node2D] = [],
		find_walker: Callable = Callable(),
		the_ball: Node2D = null) -> AdventureEncounter:
	var fight := AdventureEncounter.new()
	fight.db = database
	fight.state = save
	fight.run = the_run
	fight.adventure = AdventureDB.get_db()
	fight.layer = 15
	fight.stage = pitch
	fight.foe_nodes = nodes
	fight.walker_for = find_walker
	fight.ball = the_ball

	# HARDER EVERY TIME YOU COME BACK. The biome's own Difficulty, times how
	# often you have cleared it. Layers and Attack both scale, so a repeat
	# run is genuinely tougher rather than just longer.
	var hard := the_run.difficulty(save, database)
	for entry in wave:
		fight.foes.append(_fresh_foe(entry, hard))
	if hard > 1.01:
		print("[fight] Difficulty x%.2f — enemies are scaled up." % hard)
	parent.add_child(fight)
	return fight


# =============================================================
#  SHOWING IT
# =============================================================

## Where an enemy is standing, or nowhere if the scene did not give us nodes.
func _foe_at(index: int) -> Vector2:
	if index < 0 or index >= foe_nodes.size():
		return Vector2.ZERO
	var node := foe_nodes[index]
	return node.position if node != null and is_instance_valid(node) else Vector2.ZERO


func _foe_node(index: int) -> Node2D:
	if index < 0 or index >= foe_nodes.size():
		return null
	var node := foe_nodes[index]
	return node if node != null and is_instance_valid(node) else null


## The walker standing in for a card, if the scene handed us a way to look
## one up.
func _walker(card: PlayerData) -> Node2D:
	if card == null or not walker_for.is_valid():
		return null
	var found: Variant = walker_for.call(card)
	return found as Node2D if found != null else null


## Can we actually draw any of this? False in a headless test, or if the
## scene did not pass its nodes in.
func _can_show() -> bool:
	return stage != null and is_instance_valid(stage)


# =============================================================
#  PICKING AN ENEMY ON THE PITCH
#
#  You choose by clicking the thing itself, not a button in a list, and
#  hovering one reads it out. The buttons in the panel still work — they
#  are the same choice by another route, and they are what a keyboard or a
#  controller will use later.
#
#  There is no camera on the run, so a world position IS a screen position.
#  That is why this can hit-test with a plain distance check instead of
#  needing an Area2D and a collision shape on every enemy.
# =============================================================

## How near the pointer has to be, in pixels. Generous on purpose — the
## enemies are small and this should never feel fiddly.
const PICK_RADIUS := 46.0


func _unhandled_input(event: InputEvent) -> void:
	if not _can_show():
		return

	var motion := event as InputEventMouseMotion
	if motion != null:
		var over := _foe_under(motion.position)
		if over != _hovered:
			_hovered = over
			if over >= 0:
				_describe_foe(over)
			else:
				_detail.text = ""
			_refresh_foes()
		return

	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		if step != Step.FOCUS:
			return
		var picked := _foe_under(click.position)
		if picked >= 0 and _is_alive(picked):
			_choose_focus(picked)
			get_viewport().set_input_as_handled()


## Which enemy the pointer is over, or -1. The nearest one wins when two
## overlap, so a crowded line is still pickable.
func _foe_under(where: Vector2) -> int:
	var best := -1
	var best_gap := PICK_RADIUS
	for i in foe_nodes.size():
		if not _is_alive(i):
			continue
		var node := _foe_node(i)
		if node == null:
			continue
		var gap := node.position.distance_to(where)
		if gap < best_gap:
			best_gap = gap
			best = i
	return best


## A wave's enemy, with full layers. The CSV row is never written to — the
## damage lives in `left`, exactly the way stamina lives on the run.
## A wave's enemy, with full layers, scaled by how hard the run is.
##
## The CSV row is never written to — the scaled numbers go into a COPY, the
## same way stamina lives on the run rather than on a card. So a Mire Grub
## is still a Mire Grub in the spreadsheet however often you clear the marsh.
static func _fresh_foe(row: Dictionary, hard: float = 1.0) -> Dictionary:
	var source: Array = row.get("layers", [])
	var left: Array[int] = []
	var layers: Array[Dictionary] = []

	for entry in source:
		var layer: Dictionary = entry
		var amount := maxi(1, int(round(float(layer["amount"]) * hard)))
		left.append(amount)
		# The bar draws against the layer's amount, so the scaled amount has
		# to go in the copy too — otherwise a hard enemy would open on a bar
		# that is already half empty.
		var copy := layer.duplicate()
		copy["amount"] = amount
		layers.append(copy)

	var scaled := row.duplicate()
	scaled["attack"] = maxi(1, int(round(float(row.get("attack", 1)) * hard)))
	scaled["layers"] = layers
	return {"row": scaled, "left": left}


func _ready() -> void:
	_build_ui()
	_push_bars()
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
		# THE LAST PLAYER YOU DRAFTED TAKES THE SHOT. They step out of the
		# line, put the ball into the enemy you focused, and the number comes
		# off it. The rules happen either way; this is only the showing.
		await _show_the_kick(dealt)
		var report := _hurt_foe(_focus, dealt)
		_push_bars()
		_note("Your line-up totals %d — %s" % [total, report])
	await _beat(0.35)

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


## The shot. Whoever was drafted LAST — the highest tier that had somebody —
## runs up and kicks at the focused enemy.
func _show_the_kick(dealt: int) -> void:
	if not _can_show():
		return

	# The last tier that actually fielded anybody. Tier IV normally; a lower
	# one if your top tiers have been knocked out.
	var striker: PlayerData = null
	for tier in TierLadder.TIERS:
		var card := _picked.get(tier, null) as PlayerData
		if card != null:
			striker = card

	var target := _foe_at(_focus)
	var from := target - Vector2(360.0, 0.0)
	var kicker := _walker(striker)
	if kicker != null:
		from = kicker.position
		await AdventureStrike.step_up(kicker, target,
			db.tune_float("adventure_stepup_seconds", 0.26))

	await AdventureStrike.kick(stage, from, target,
		db.tune_float("adventure_kick_seconds", 0.42), ball)

	var hit_node := _foe_node(_focus)
	if hit_node != null:
		AdventureStrike.flinch(hit_node, from,
			db.tune_float("adventure_flinch_seconds", 0.22))
	AdventureStrike.number(stage, target, str(dealt), true,
		db.tune_float("adventure_float_seconds", 0.9))


## Copy what is LEFT of every enemy onto its node, so the bars on the pitch
## empty as you hit them. The node draws from this; nothing else reads it.
func _push_bars() -> void:
	for i in foes.size():
		var node := _foe_node(i)
		if node != null:
			node.set_meta("left", (foes[i]["left"] as Array).duplicate())
			node.set_meta("focused", i == _focus and _is_alive(i))
			node.set_meta("hovered", i == _hovered and _is_alive(i))
			node.queue_redraw()


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
	var hit := maxi(1, int(row.get("attack", 1)) * multiplier)
	var how := String(row.get("targeting", "weakest"))

	# THEM COMING AT YOU. A lunge from the enemy towards whoever it picked,
	# then the red number off the player. The single-target case animates the
	# victim; a sweep just shakes the enemy and lets the numbers tell it.
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
		if _can_show():
			var shaker := _foe_node(index)
			if shaker != null:
				AdventureStrike.flinch(shaker, shaker.position + Vector2(60.0, 0.0),
					db.tune_float("adventure_flinch_seconds", 0.22))
		_note("%s sweeps every tier for %d — %d caught." % [
			_foe_name(index), hit, caught])
	else:
		var victim := _target_for(how)
		if victim == null:
			return

		if _can_show():
			var mark := _walker(victim)
			var here := _foe_at(index)
			if mark != null:
				await AdventureStrike.kick(stage, here, mark.position,
					db.tune_float("adventure_kick_seconds", 0.42) * 0.8, ball)
				AdventureStrike.flinch(mark, here,
					db.tune_float("adventure_flinch_seconds", 0.22))
				AdventureStrike.number(stage, mark.position, str(hit), false,
					db.tune_float("adventure_float_seconds", 0.9))

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

	for child in _choice_row.get_children():
		child.queue_free()

	var menu := VBoxContainer.new()
	menu.name = "ItemMenu"
	menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu.add_theme_constant_override("separation", 4)
	_choice_row.add_child(menu)

	menu.add_child(MenuSupport.heading("YOUR KIT", 14, MenuSupport.COLOUR_TEXT_DIM))
	if carried.is_empty():
		menu.add_child(_quiet("Nothing you can use. Items with a Use column in Items.csv show up here."))
	for entry in carried:
		var button := Button.new()
		button.text = "%s  x%d   —   %s" % [entry.get("name", "?"), int(entry.get("held", 1)),
			entry.get("description", "")]
		button.custom_minimum_size = Vector2(0, 34)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_use_item.bind(entry))
		menu.add_child(button)

	var close := Button.new()
	close.text = "Close the kit"
	close.custom_minimum_size = Vector2(0, 32)
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(_refresh)
	menu.add_child(close)


## Items are counters, so "using one" is spending a counter and applying the
## Use column. Everything here works on any item you add tomorrow.
func _use_item(entry: Dictionary) -> void:
	var use := String(entry.get("use", ""))
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
		_push_bars()

	else:
		_note("'%s' is not a Use this game knows. Try revive, heal:6 or hit:4." % use)
		return

	state.add_count(String(entry.get("id", "")), -1)
	state.save_to_disk()
	_note("%s — %s" % [entry.get("name", "It"), did])
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

	# --- the buttons ---
	#
	# THE LOG IS NOT DOWN HERE ANY MORE. Text under the buttons was cramped
	# and pushed everything about, so it has its own little window off to the
	# side that you can shut. See _build_log_window().
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	column.add_child(bottom)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(spacer)

	_log_button = Button.new()
	_log_button.text = "HIDE LOG"
	_log_button.custom_minimum_size = Vector2(120, 42)
	_log_button.focus_mode = Control.FOCUS_NONE
	_log_button.tooltip_text = "Show or hide the blow-by-blow. It opens on its own; close it if you would rather just watch."
	_log_button.pressed.connect(_toggle_log)
	bottom.add_child(_log_button)

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

	_build_log_window(holder)


# =============================================================
#  THE COMBAT LOG WINDOW
#
#  Its own panel, up the right-hand side, out of the way of the pitch and
#  the buttons. It OPENS BY ITSELF because on a first run you want to see
#  what the numbers are doing; one press shuts it and it stays shut for the
#  rest of the fight.
# =============================================================

func _build_log_window(holder: Control) -> void:
	_log_panel = PanelContainer.new()
	_log_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_log_panel.offset_left = -330.0
	_log_panel.offset_right = -18.0
	_log_panel.offset_top = 74.0
	_log_panel.offset_bottom = 300.0
	_log_panel.add_theme_stylebox_override("panel", MenuSupport.panel_style(
		Color(0.09, 0.10, 0.13, 0.92), MenuSupport.COLOUR_TEXT_DIM))
	holder.add_child(_log_panel)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_theme_constant_override("margin_right", 12)
	pad.add_theme_constant_override("margin_top", 10)
	pad.add_theme_constant_override("margin_bottom", 10)
	_log_panel.add_child(pad)

	var inside := VBoxContainer.new()
	inside.add_theme_constant_override("separation", 4)
	pad.add_child(inside)

	inside.add_child(MenuSupport.heading("WHAT HAPPENED", 13,
		MenuSupport.COLOUR_TEXT_DIM))

	_log = VBoxContainer.new()
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.add_theme_constant_override("separation", 3)
	inside.add_child(_log)


func _toggle_log() -> void:
	if _log_panel == null:
		return
	_log_panel.visible = not _log_panel.visible
	_log_button.text = "HIDE LOG" if _log_panel.visible else "SHOW LOG"


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
	_push_bars()
	for child in _foe_row.get_children():
		child.queue_free()

	for i in foes.size():
		var row: Dictionary = foes[i]["row"]
		var alive := _is_alive(i)

		var button := Button.new()
		button.custom_minimum_size = Vector2(180, 78)
		button.focus_mode = Control.FOCUS_NONE
		button.disabled = not alive or step != Step.FOCUS
		button.text = "%s\n%s" % [row.get("name", "?"), _layer_text(i)]
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
		row.get("name", "?"), int(row.get("attack", 0)), row.get("targeting", "weakest"),
		"  |  ".join(parts), row.get("description", "")]


func _layer_text(index: int) -> String:
	var left: Array = foes[index]["left"]
	var total := 0
	for amount in left:
		total += int(amount)
	if total <= 0:
		return "down"
	return "%d left  ·  hits %d" % [total, int((foes[index]["row"] as Dictionary).get("attack", 0))]


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

	# THE SAME CARD FACE AS THE TEAM BUILDER AND THE MATCH DRAFT. One
	# helper draws all three, so a player looks the same wherever you meet
	# them — see MenuSupport.card_face().
	for card in standing:
		var button := MenuSupport.card_face(card, db, Vector2(128, 168),
			"%d hp" % run.stamina_of(card, db))
		button.pressed.connect(_pick_card.bind(card))
		_choice_row.add_child(button)


# =============================================================
#  SMALL THINGS
# =============================================================

func _foe_name(index: int) -> String:
	if index < 0 or index >= foes.size():
		return "it"
	return String((foes[index]["row"] as Dictionary).get("name", "it"))


## One line in the running log. The oldest are dropped so the panel never
## grows past its box.
func _note(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT)
	_log.add_child(label)
	print("[fight] %s" % text)

	# The window holds a dozen lines; older ones drop off the top.
	while _log.get_child_count() > 12:
		var oldest := _log.get_child(0)
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
