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

## ============ SOMEBODY'S STAMINA CHANGED ============
##
## THE BUG THIS FIXES: the run holds the stamina, and the walkers on the
## pitch only DRAW it. Nothing put the two in step until the whole fight was
## over, so you watched a player get hit and the bar under them did not
## move — no feedback at all that damage had been done.
##
## The fight emits this the instant anything changes a player: taking a hit,
## being knocked out, being revived, drinking something. The scene hears it
## and repaints every bar. One signal covers all of those and every one you
## add later.
signal party_changed

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
var _detail: Label

## THE ENEMIES ARE THE BUTTONS. There is no list of them in a panel any
## more — you point at the thing on the pitch. See enemy_pick_layer.gd.
var _picker: EnemyPickLayer

## THE CARDS HAVE THEIR OWN WINDOW, in the middle of the screen where you
## are looking, rather than being squeezed into the bottom of the command
## bar. It is only up while a tier is being drafted.
var _choice_window: PanelContainer
var _choice_row: HFlowContainer
var _choice_title: Label

## The two side panels that show the move going in. See adventure_buildup.gd.
var _buildup: AdventureBuildup

## What the enemies gained by watching you build the move, index -> amount.
## Cleared at the start of every round.
var _their_gain: Dictionary = {}

## ============ WHAT AN ORDINARY HIT LOOKS LIKE ============
##
## The screen shake grows with the size of a hit — which only means something
## if the game knows what an ORDINARY hit is. Rather than making you guess a
## number in Tuning.csv, it keeps a running average of everything landed so
## far in this fight, one average per kind of hit.
##
## So the FIRST hit of a fight is average by definition and shakes exactly
## what the Shake column of Juice.csv says. After that, a hit twice the size
## of what you have been doing shakes harder — and that stays true whether
## your side hits for 4 or for 40, which is why there is no number to keep
## re-tuning as the game grows.
##
## If you would rather pin it: `juice_average_hit` in Tuning.csv. Anything
## above 0 is used instead of the running average.
var _averages: Dictionary = {}

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
#  PICKING AN ENEMY
#
#  THE ENEMY IS THE BUTTON. There is no list of enemies in a panel any more:
#  you point at the thing standing on the pitch, it lights up, a window
#  beside it tells you everything about it, and you click it.
#
#  None of that is done here. enemy_pick_layer.gd puts a real, invisible
#  Button on top of each enemy and follows it about, so the hovering, the
#  clicking and the keyboard focus are Godot's job rather than this file
#  guessing from mouse distances. It calls back into _choose_focus() and
#  _foe_facts() above, and that is the whole of the connection between them.
#
#  What is left here is only when picking is LIVE, which is while the fight
#  is waiting for a target and at no other moment — so a stray click during
#  the build-up cannot re-aim a shot that is already on its way.
# =============================================================


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

	# THE ENEMIES BECOME THE BUTTONS. A real Button rides on top of each one,
	# so Godot does the hovering and the clicking rather than this file
	# guessing from mouse distance. See enemy_pick_layer.gd.
	_picker = EnemyPickLayer.make(db)
	_picker.foe_nodes = foe_nodes
	_picker.alive_check = Callable(self, "_is_alive")
	_picker.describe_source = Callable(self, "_foe_facts")
	_picker.hovered.connect(_on_foe_hovered)
	_picker.chosen.connect(_choose_focus)
	add_child(_picker)

	# The two side windows that show the move being built.
	_buildup = AdventureBuildup.make(db)
	add_child(_buildup)

	_push_bars()
	_begin_round()


## Everything the hover window needs about one enemy, handed over as data so
## that the picker never reaches into this file's variables.
func _foe_facts(index: int) -> Dictionary:
	if index < 0 or index >= foes.size():
		return {}
	return {
		"row": foes[index]["row"],
		"left": foes[index]["left"],
		"alive": _is_alive(index),
	}


## The picker says what the mouse is over; this puts the one-line version in
## the command bar and lights the ring on the pitch. The full card is drawn
## by the picker itself, beside the enemy.
func _on_foe_hovered(index: int) -> void:
	_hovered = index
	if index >= 0 and index < foes.size():
		_describe_foe(index)
	else:
		_detail.text = ""
	_push_bars()


# =============================================================
#  A ROUND
# =============================================================

func _begin_round() -> void:
	step = Step.FOCUS
	_picked.clear()
	_their_gain.clear()
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

	# THEY ARE SPENT NOW, exactly as in a league match: this player sits out
	# until everyone else in their tier has had a turn too. See the note on
	# `spent` in adventure_run.gd.
	var came_round := run.use_up(card, db)
	_note("Tier %s: %s (%d)%s" % [tier, card.player_name, card.get_attack_power(),
		"   — Tier %s comes back round." % tier if came_round else ""])

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
		# AVAILABLE, not merely standing. A tier whose players are all spent
		# this cycle has nobody to offer even though they are on their feet,
		# and it is skipped the same way an empty one is.
		if not run.available_in(tier, db).is_empty():
			break
		_picked[tier] = null
		_tier_index += 1
		skipped = true
		if run.standing_in(tier, db).is_empty():
			_note("Tier %s has nobody left — they come straight through it." % tier)
		else:
			_note("Tier %s has all had their turn — nobody to send. They come through it."
				% tier)
	return skipped


# =============================================================
#  RESOLVING
# =============================================================

func _resolve() -> void:
	step = Step.RESOLVING
	_refresh()

	# --- YOUR HIT: the four tiers, plus whatever the move was worth ---
	#
	# THE CHAIN, weakest tier first, with a null where a tier had nobody. It
	# is passed about as one list because that is what it is: the order the
	# ball went in.
	var chain: Array = []
	var total := 0
	var empty_tiers := 0
	for tier in TierLadder.TIERS:
		var card := _picked.get(tier, null) as PlayerData
		chain.append(card)
		if card == null:
			empty_tiers += 1
		else:
			total += card.get_attack_power()

	# WHAT THE MOVE ITSELF WAS WORTH, from Combos.csv. It is added to the
	# SHOT and never to a card, so the tier ladder is untouched by it — the
	# same rule the season's Difficulty obeys. See combo_db.gd.
	var combo := AdventureBuildup.combo_bonus(chain)
	if combo > 0:
		var named: Array[String] = []
		for rule in ComboDB.fired(chain):
			named.append(ComboDB.describe(rule))
		_note("The move comes off — %s" % "   ".join(named))
		Juice.fire(self, "combo_fired", {})

	# WHAT THEY GAINED WHILE YOU BUILT IT. Every pass gives an enemy with a
	# Buff column that much more to hit you with, this round only.
	_their_gain.clear()
	for i in foes.size():
		if not _is_alive(i):
			continue
		var gained := AdventureBuildup.buff_gained(foes[i]["row"], chain)
		if gained > 0:
			_their_gain[i] = gained

	# --- WATCH IT GO IN ---
	#
	# Two windows: your players arriving one at a time on the left, theirs
	# getting angrier on the right. Both close before the shot, leaving the
	# pitch clear for the kick. It decides nothing — everything above is
	# already worked out — so turning it off in Tuning.csv changes only what
	# you see. See adventure_buildup.gd.
	var alive_now: Array = []
	for i in foes.size():
		alive_now.append(_is_alive(i))
	if _buildup != null:
		await _buildup.play(chain, foes, alive_now)

	var scale := db.tune_float("adventure_damage_scale", 1.0)
	var least := db.tune_int("adventure_damage_minimum", 1)
	var dealt := maxi(least, int(round(float(total + combo) * scale)))

	if _focus >= 0 and _is_alive(_focus):
		# THE LAST PLAYER YOU DRAFTED TAKES THE SHOT. They step out of the
		# line, put the ball into the enemy you focused, and the number comes
		# off it. The rules happen either way; this is only the showing.
		await _show_the_kick(dealt)
		var was_alive := _is_alive(_focus)
		var report := _hurt_foe(_focus, dealt)
		_push_bars()
		# IF THAT KILLED IT, IT GOES DOWN ON SCREEN. The Animations.csv row
		# named by adventure_death_animation, or a fade and a slump if you
		# have not drawn one yet.
		if was_alive and not _is_alive(_focus):
			await _show_the_death(_focus)
		_note("Your line-up totals %d%s — %s" % [
			total, "  (+%d from the move)" % combo if combo > 0 else "", report])
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

	# --- WATCH THEIRS GO IN TOO ---
	#
	# The mirror of the window above. The enemies still standing come on one
	# at a time, their abilities are named out of Abilities.csv, and their
	# combos fire out of the same Combos.csv yours do. It decides nothing that
	# is not already decided here — see adventure_buildup.gd.
	var striking: Array[int] = []
	var still_up: Array = []
	for i in foes.size():
		still_up.append(_is_alive(i))
		if _is_alive(i):
			striking.append(i)

	var their_bonus := 0
	if db.tune_bool("adventure_enemy_combos", true):
		their_bonus = AdventureBuildup.their_combo_bonus(foes, still_up)
		if their_bonus > 0:
			var theirs: Array[String] = []
			var facts: Array[Dictionary] = []
			for i in striking:
				facts.append(AdventureBuildup.enemy_facts(foes[i]["row"]))
			for rule in ComboDB.fired_from(facts, facts.size()):
				theirs.append(ComboDB.describe(rule))
			_note("They have a move of their own — %s" % "   ".join(theirs))

	if _buildup != null:
		await _buildup.play_their_turn(foes, still_up, _their_gain, _bracing_lines())

	# THEIR BONUS GOES TO ONE HIT — the last of them to strike — for the same
	# reason yours goes to the shot and never to a card. Six enemies each
	# carrying it would be six times what your side gets for the same combo.
	for slot in striking.size():
		var i := striking[slot]
		if not _is_alive(i):
			continue
		var extra := their_bonus if slot == striking.size() - 1 else 0
		await _enemy_strikes(i, multiplier, extra)
		if run.party_is_down():
			break

	# ============ AND AN END TO IT ============
	#
	# The enemy phase used to stop without saying so: the last red number
	# floated up and then nothing happened until you noticed your cards were
	# live again. Now it is bracketed, so there is never a moment where you
	# are waiting on the game and the game is waiting on you.
	if _buildup != null and not run.party_is_down():
		await _buildup.announce("THEIR TURN IS OVER", MenuSupport.COLOUR_ACCENT,
			db.tune_float("adventure_turn_over_seconds", 0.7))

	_refresh()
	await _beat()

	if run.party_is_down():
		_note("Everybody is down.")
		step = Step.DONE
		finished.emit(false, false)
		return

	_begin_round()


# =============================================================
#  JUICE
#
#  Nothing in this file decides what a hit LOOKS like. It only says what
#  happened — "enemy_hit", "enemy_died" — and res://data/Juice.csv decides
#  the shake, the flash, the pop, the slow-motion and the sound.
#
#  So if a hit does not feel right, the file to open is the spreadsheet, not
#  this one. See juice_db.gd for the columns.
# =============================================================

## One of yours has run out of stamina.
##
## The rules part already happened — run.hurt() took the stamina and
## run.retire() took their place in the rotation. This is the SHOWING of it:
## the player drops where they stood (adventure_scene.gd puts every walker in
## step with the run, so all this has to do is ask) and Juice.csv decides what
## that looks and sounds like.
##
## They stay on the ground for the rest of the fight. Two players who are not
## on your team come and carry them off once the last enemy is down — see
## _carry_off_the_fallen() in adventure_scene.gd.
func _went_down(card: PlayerData) -> void:
	party_changed.emit()
	if not _can_show():
		return
	var mark := _walker(card)
	if mark == null:
		return
	if mark.has_method("lie_down"):
		mark.call("lie_down")
	Juice.fire(self, "player_exhausted", {"node": mark})


## Record this hit and hand back what an ordinary one has been up to now.
##
## Called once per hit, and it does BOTH jobs on purpose — there is then no
## way to record a hit and forget to, or to compare against an average that
## has drifted. The first hit of a kind returns 0, which Juice reads as
## "no scaling", so it shakes exactly the Shake column.
func _average_so_far(key: String, amount: int) -> float:
	var pinned := db.tune_float("juice_average_hit", 0.0)
	if pinned > 0.0:
		return pinned
	var seen: Array = _averages.get(key, [0, 0])
	var count := int(seen[0])
	var total := int(seen[1])
	_averages[key] = [count + 1, total + absi(amount)]
	if count <= 0:
		return 0.0
	return float(total) / float(count)


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

	# THE ONE YOU ASKED FOR: the harder the hit, the harder the screen shakes.
	# `amount` is this hit, `average` is what your hits have been worth so far
	# this fight, and Juice.csv's `Shake Scale` column decides how much that
	# difference is allowed to matter. Two rows answer to `enemy_hit` — one
	# shakes the ENEMY, one shakes the SCREEN — and both fire from this line.
	var usual := _average_so_far("shot", dealt)
	Juice.fire(self, "shot_struck", {"amount": dealt, "average": usual})
	Juice.fire(self, "enemy_hit",
		{"node": hit_node, "amount": dealt, "average": usual})


## ============ AN ENEMY GOING DOWN ============
##
## It is knocked backwards, spins a little, fades and is gone. That is a
## placeholder in the same spirit as everything else here: it reads properly
## today and it is replaced the moment you draw something.
##
## TO GIVE IT A REAL DEATH: add a row to Animations.csv whose Animation
## column is the word in `adventure_death_animation` (Tuning.csv, `lose` out
## of the box, because that animation already exists in your sheet). An
## enemy with an Art column pointing at a sheet will play it.
func _show_the_death(index: int) -> void:
	if not _can_show():
		return
	var node := _foe_node(index)
	if node == null or not is_instance_valid(node):
		return

	_note("%s goes down." % _foe_name(index))
	Juice.fire(self, "enemy_died", {"node": node})

	var seconds := db.tune_float("adventure_death_seconds", 0.55)
	var away := node.position + Vector2(64.0, -18.0)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(node, "position", away, seconds) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "rotation", 1.1, seconds)
	tween.tween_property(node, "modulate:a", 0.0, seconds)
	await tween.finished

	# It stays in the list — the fight counts the dead — but it is no longer
	# on the pitch and no longer has a button on it.
	node.visible = false
	if _picker != null:
		_picker.refresh()


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
## Tell the scene to repaint the bars, and put a red number over the player
## who just took it so the damage is visible ON THE PITCH and not only in the
## log. Called from every place a player is hurt or healed.
func _party_changed(card: PlayerData = null, amount: int = 0) -> void:
	party_changed.emit()
	if card == null or amount == 0 or not _can_show():
		return
	var mark := _walker(card)
	if mark == null:
		return
	# A red number rising off the player, and a shove backwards, so a hit is
	# something you SEE rather than something you read about afterwards.
	AdventureStrike.number(stage, mark.position + Vector2(0.0, -30.0),
		str(absi(amount)), amount < 0,
		db.tune_float("adventure_float_seconds", 0.9))
	AdventureStrike.flinch(mark, mark.position + Vector2(-40.0, 0.0),
		db.tune_float("adventure_flinch_seconds", 0.22))

	# A NEGATIVE AMOUNT IS A HEAL — that is the same rule the floating number
	# above uses to decide whether to come up green or red.
	if amount < 0:
		Juice.fire(self, "player_healed", {"node": mark})
	else:
		Juice.fire(self, "player_hurt", {"node": mark, "amount": amount,
			"average": _average_so_far("taken", amount)})


## One tier of yours per line, for the right-hand side of THEIR window. What
## matters while they are picking a target is how many of you are on your
## feet, because an empty tier is what doubles everything they do.
func _bracing_lines() -> Array:
	var out: Array = []
	for tier in TierLadder.TIERS:
		out.append({"tier": tier, "standing": run.standing_in(tier, db).size()})
	return out


## `extra` is their combo bonus, and it is handed to ONE of them — see the
## note where it is worked out.
func _enemy_strikes(index: int, multiplier: int, extra: int = 0) -> void:
	var row: Dictionary = foes[index]["row"]
	# WHAT IT GAINED WATCHING YOU BUILD THE MOVE, added here and nowhere
	# else, so it lasts exactly one round — see the Buff column of
	# AdventureEnemies.csv and the right-hand build-up window.
	var gained := int(_their_gain.get(index, 0))
	var hit := maxi(1, (int(row.get("attack", 1)) + gained) * multiplier + extra)
	if gained > 0:
		_note("%s had time to wind up: +%d." % [_foe_name(index), gained])
		Juice.fire(self, "enemy_windup", {"node": _foe_node(index)})
	if extra > 0:
		_note("%s finishes their move: +%d." % [_foe_name(index), extra])
		Juice.fire(self, "combo_fired", {})
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
				_went_down(standing[0])
			# The bar under that player empties NOW, not when the fight ends.
			_party_changed(standing[0], hit)
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
		# The number and the shove were already shown above as part of the
		# kick, so this only repaints the bars.
		_party_changed()
		_note("%s hits %s for %d.%s" % [_foe_name(index), victim.player_name, hit,
			"  KNOCKED OUT." if went_down else ""])
		if went_down:
			_went_down(victim)

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
		# A GREEN number, because negative means healing to _party_changed().
		_party_changed(back, -half)
		did = "%s is back on, at %d stamina." % [back.player_name, half]

	elif use.begins_with("heal"):
		var amount := _number_in(use, 4)
		var everyone := use.contains("all")
		var mended := 0
		for tier in TierLadder.TIERS:
			for card in run.standing_in(tier, db):
				var cap := AdventureRun.stamina_for(card, db)
				run.stamina[card] = mini(cap, run.stamina_of(card, db) + amount)
				_party_changed(card, -amount)
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
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)

	_build_command_bar(holder)
	_build_choice_window(holder)


# -------------------------------------------------------------
#  THE COMMAND BAR
#
#  What used to be a 300-pixel panel across the bottom holding the enemies,
#  the cards and the buttons all at once. It is a slim strip now, because
#  the enemies moved onto the pitch and the cards moved into the middle of
#  the screen. All that is left in it is what the fight is asking you for
#  and the three things you can always do.
# -------------------------------------------------------------

func _build_command_bar(holder: Control) -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = 20.0
	panel.offset_right = -20.0
	panel.offset_top = -104.0
	panel.offset_bottom = -16.0
	panel.add_theme_stylebox_override("panel", MenuSupport.panel_style(
		Color(0.09, 0.10, 0.13, 0.94), MenuSupport.COLOUR_ACCENT))
	holder.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 18)
	margin.add_child(bar)

	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	words.add_theme_constant_override("separation", 2)
	bar.add_child(words)

	_title = MenuSupport.heading("COMBAT", 22, MenuSupport.COLOUR_ACCENT)
	words.add_child(_title)

	_prompt = Label.new()
	_prompt.add_theme_font_size_override("font_size", 15)
	_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.add_child(_prompt)

	# The line that reads out whatever you are pointing at. The full card is
	# in the hover window beside the enemy; this is the one-line version, so
	# there is something to read even with the mouse still.
	_detail = Label.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_detail.add_theme_font_size_override("font_size", 13)
	_detail.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.custom_minimum_size = Vector2(380, 0)
	bar.add_child(_detail)

	_log_button = Button.new()
	_log_button.text = "HIDE LOG"
	_log_button.custom_minimum_size = Vector2(120, 46)
	_log_button.focus_mode = Control.FOCUS_NONE
	_log_button.tooltip_text = "Show or hide the blow-by-blow. It opens on its own; close it if you would rather just watch."
	_log_button.pressed.connect(_toggle_log)
	bar.add_child(_log_button)

	_item_button = Button.new()
	_item_button.text = "ITEMS"
	_item_button.custom_minimum_size = Vector2(120, 46)
	_item_button.focus_mode = Control.FOCUS_NONE
	_item_button.tooltip_text = "Revive somebody, patch somebody up, or throw something. Before the drafting only."
	_item_button.pressed.connect(_open_items)
	bar.add_child(_item_button)

	_flee_button = Button.new()
	_flee_button.text = "FLEE"
	_flee_button.custom_minimum_size = Vector2(120, 46)
	_flee_button.focus_mode = Control.FOCUS_NONE
	_flee_button.pressed.connect(_flee)
	bar.add_child(_flee_button)


# -------------------------------------------------------------
#  THE CARD WINDOW
#
#  Its own panel, in the middle of the screen, and up ONLY while a tier is
#  being drafted. The cards used to live along the bottom of the big combat
#  panel, which put the thing you were choosing as far as possible from the
#  thing you were choosing it for.
#
#  Where it sits is Tuning.csv:
#      adventure_choice_y   0 = the top, 0.5 = the middle, 1 = the bottom
# -------------------------------------------------------------

func _build_choice_window(holder: Control) -> void:
	_choice_window = PanelContainer.new()
	_choice_window.add_theme_stylebox_override("panel", MenuSupport.panel_style(
		Color(0.07, 0.08, 0.11, 0.96), MenuSupport.COLOUR_ACCENT))

	# ============ IT CANNOT RUN OFF THE SCREEN ANY MORE ============
	#
	# The old version worked out its own height from the card size and pinned
	# it there. That was fine for three cards and wrong for six — the row now
	# holds the players who are READY plus the ones who are RESTING — and the
	# bottom of it went off the bottom of the window.
	#
	# It is anchored to the whole screen with a margin instead, so it is
	# never taller than what you can see, and the cards inside WRAP and
	# SCROLL rather than overflowing. adventure_choice_y still nudges it up
	# and down within that.
	var where := clampf(db.tune_float("adventure_choice_y", 0.5), 0.05, 0.95)
	var top_gap := db.tune_float("adventure_choice_top", 90.0)
	var bottom_gap := db.tune_float("adventure_choice_bottom", 130.0)

	_choice_window.set_anchors_preset(Control.PRESET_FULL_RECT, true)
	_choice_window.anchor_left = 0.5
	_choice_window.anchor_right = 0.5
	_choice_window.anchor_top = 0.0
	_choice_window.anchor_bottom = 1.0
	_choice_window.offset_left = -560.0
	_choice_window.offset_right = 560.0
	# Clear of the wave banner at the top and the command bar at the bottom,
	# then leaned towards `where` within what is left.
	_choice_window.offset_top = top_gap + (where - 0.5) * 80.0
	_choice_window.offset_bottom = -bottom_gap + (where - 0.5) * 80.0
	_choice_window.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_choice_window.hide()
	holder.add_child(_choice_window)

	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right"]:
		pad.add_theme_constant_override(side, 20)
	pad.add_theme_constant_override("margin_top", 12)
	pad.add_theme_constant_override("margin_bottom", 14)
	_choice_window.add_child(pad)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	pad.add_child(column)

	_choice_title = MenuSupport.heading("TIER I", 20, MenuSupport.COLOUR_ACCENT)
	_choice_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_choice_title)

	# A scroller around the cards. With three it never scrolls and you would
	# not know it was there; with eight it does, and nothing is lost.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	# HFlowContainer, not HBoxContainer: a seventh card wraps onto a second
	# line instead of squeezing the other six.
	_choice_row = HFlowContainer.new()
	_choice_row.alignment = FlowContainer.ALIGNMENT_CENTER
	_choice_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_choice_row.add_theme_constant_override("h_separation", 14)
	_choice_row.add_theme_constant_override("v_separation", 12)
	scroll.add_child(_choice_row)

	var hint := Label.new()
	hint.text = "Point at a player to read what they do. A greyed card has already had a turn this cycle."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	column.add_child(hint)


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

	_push_bars()
	_refresh_choices()

	# PICKING IS LIVE ONLY WHILE A TARGET IS WANTED. At any other moment the
	# buttons on the enemies are taken away, so a click during the build-up
	# cannot re-aim a shot that is already going in.
	if _picker != null:
		_picker.set_live(step == Step.FOCUS)

	var alive := _living_count()
	_title.text = "COMBAT   ·   %d left" % alive

	match step:
		Step.FOCUS:
			_prompt.text = "Point at an enemy to read it, click it to go after it. Everything your four tiers do this round lands on them."
		Step.DRAFT:
			var tier := _current_tier()
			var standing := run.standing_in(tier, db)
			if standing.is_empty():
				_prompt.text = "Tier %s has nobody left." % tier
			else:
				_prompt.text = "Tier %s — choose who takes it. (%d of 4)" % [
					tier, _tier_index + 1]
		Step.RESOLVING:
			_prompt.text = "The move is going in..."
		Step.DONE:
			_prompt.text = ""

	# THE POINT OF NO RETURN. Flee is live until the fourth tier is in.
	_flee_button.disabled = step == Step.RESOLVING or step == Step.DONE
	_flee_button.text = "FLEE" if not _flee_button.disabled else "—"
	_item_button.disabled = step == Step.RESOLVING or step == Step.DONE


## THE OLD LIST OF ENEMY BUTTONS IS GONE. The enemies on the pitch are the
## buttons now — enemy_pick_layer.gd — so all that is left of this is
## keeping the rings and the health bars under them up to date, which is
## _push_bars(). Anything that used to call _refresh_foes() calls that.


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

	var gained := int(_their_gain.get(index, 0))
	var hits := int(row.get("attack", 0)) + gained
	_detail.text = "%s — hits for %d%s, goes for the %s.   %s" % [
		row.get("name", "?"), hits,
		"  (+%d from your passes)" % gained if gained > 0 else "",
		row.get("targeting", "weakest"), "  |  ".join(parts)]


func _layer_text(index: int) -> String:
	var left: Array = foes[index]["left"]
	var total := 0
	for amount in left:
		total += int(amount)
	if total <= 0:
		return "down"
	return "%d left  ·  hits %d" % [total, int((foes[index]["row"] as Dictionary).get("attack", 0))]


## The card window. Up only while a tier is being drafted, and gone the
## moment the fourth card is in — which is what leaves the middle of the
## screen clear for the move to be played out on.
func _refresh_choices() -> void:
	for child in _choice_row.get_children():
		child.queue_free()

	if step != Step.DRAFT:
		_choice_window.hide()
		return

	var tier := _current_tier()
	if tier == "":
		_choice_window.hide()
		return

	# _advance_past_empty_tiers() ran first, so there is always somebody here.
	var ready_now := run.available_in(tier, db)
	var resting := run.resting_in(tier, db)
	_choice_window.show()
	_choice_title.text = "TIER %s   ·   who takes it?   (%d of %d)" % [
		tier, _tier_index + 1, TierLadder.TIERS.size()]

	# THE SAME CARD FACE AS THE TEAM BUILDER AND THE MATCH DRAFT. One
	# helper draws all three, so a player looks the same wherever you meet
	# them — see MenuSupport.card_face().
	# The size is Tuning.csv, not a number typed here, so the cards in a fight
	# and the cards on the pitch can be kept the same size without opening a
	# script: adventure_card_width / adventure_card_height.
	var face_size := Vector2(
		db.tune_float("adventure_card_width", 200.0),
		db.tune_float("adventure_card_height", 264.0))

	for card in ready_now:
		var button := MenuSupport.card_face(card, db, face_size,
			"%d hp" % run.stamina_of(card, db))
		_explain_card(button, card, "")
		button.pressed.connect(_pick_card.bind(card))
		_choice_row.add_child(button)

	# WHO IS RESTING, shown greyed rather than hidden. Seeing that your best
	# Tier III is sitting this cycle out is half of knowing what you have —
	# hiding them just makes the row look short for no stated reason.
	for card in resting:
		var button := MenuSupport.card_face(card, db, face_size, "resting")
		button.disabled = true
		button.modulate = Color(1, 1, 1, 0.42)
		_explain_card(button, card, "Already had a turn. Back when the rest of Tier %s have had theirs." % tier)
		_choice_row.add_child(button)


## ============ WHAT THIS PLAYER DOES ============
##
## Hovering a card reads its abilities out, exactly as it does in a league
## match — the same Abilities.csv rows, in the same words. That is the whole
## point: a card does not behave differently in Adventure, so it should not
## be described differently either.
##
## It goes in the tooltip AND in the command bar's detail line, so it is
## there whether you are pointing at the card or have just stopped moving.
func _explain_card(button: Button, card: PlayerData, extra: String) -> void:
	var lines: Array[String] = []
	if extra != "":
		lines.append(extra)

	lines.append("%s   ·   Tier %s   ·   %d power   ·   %d / %d stamina" % [
		card.player_name, card.get_tier_clean(), card.get_attack_power(),
		run.stamina_of(card, db), AdventureRun.stamina_for(card, db)])

	var element := card.element.strip_edges()
	if element != "" and not ComboDB.NOT_AN_ELEMENT.has(element.to_lower()):
		lines.append("Element: %s   — counts towards the element combos." % element)

	# THE ABILITIES, from the same place the league match reads them.
	for pair in [[card.attack_ability_id, "Attacking"],
			[card.defend_ability_id, "Defending"]]:
		var id_text := String(pair[0]).strip_edges()
		if id_text == "":
			continue
		var ability := db.abilities.get(id_text.to_lower(), null) as AbilityData
		if ability == null:
			lines.append("%s: '%s' is not in Abilities.csv" % [pair[1], id_text])
			continue
		var words := ability.notes
		if words.strip_edges() == "":
			words = "%s %s %+d (%s)" % [ability.trigger, ability.effect,
				ability.value, ability.target]
		var shown := ability.display_name
		if shown.strip_edges() == "":
			shown = id_text
		lines.append("%s — %s: %s" % [pair[1], shown, words])

	# The printed card text, which is what a designer actually wrote.
	for text in [card.attack_text, card.defend_text]:
		var clean := String(text).strip_edges()
		if clean != "":
			lines.append(clean)

	button.tooltip_text = "\n".join(lines)
	var one_line := "   ·   ".join(lines)
	button.mouse_entered.connect(func() -> void: _detail.text = one_line)
	button.focus_entered.connect(func() -> void: _detail.text = one_line)
	button.mouse_exited.connect(func() -> void: _detail.text = "")


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
