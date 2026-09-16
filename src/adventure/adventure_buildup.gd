class_name AdventureBuildup
extends CanvasLayer

# =============================================================
#  THE BUILD-UP — watching the move come together
#
#  This is the Adventure answer to PLAY MAKER on the pitch. When your four
#  tiers are in, you do not just see a number appear on an enemy. You watch
#  the move:
#
#      LEFT WINDOW     your players come on one at a time, weakest tier
#                      first. Each one adds its power to a running total,
#                      and any COMBO it completes flashes up beside it.
#      RIGHT WINDOW    the enemies, all of them, gaining whatever their Buff
#                      column says with every pass. They are not waiting
#                      politely — the longer the move, the harder the reply.
#
#  When the last player is on, BOTH WINDOWS GO, and that player is left
#  standing on the pitch to take the shot. The kick, the ball and the enemy
#  going down are adventure_strike.gd and the fight itself; this file's job
#  ends the moment the windows close.
#
#  ============ NOTHING HERE DECIDES ANYTHING ============
#
#  The fight has already worked out who is in the chain, what it totals and
#  what the enemies will hit back for. This shows that and only that, which
#  is why turning it off changes nothing about the outcome:
#
#      adventure_buildup            false skips the whole sequence
#      adventure_buildup_step       seconds each player takes to come on
#      adventure_buildup_hold       seconds the finished move is held
#
#  all in Tuning.csv. On a fast replay you will want it off; on a
#  presentation you will want it slow.
# =============================================================

signal finished

var db: CardDatabase

var _left_box: VBoxContainer
var _right_box: VBoxContainer
var _left_panel: PanelContainer
var _right_panel: PanelContainer
var _total_label: Label
var _combo_label: Label

## The words at the top of each window. They are members rather than one-off
## labels because THE SAME TWO WINDOWS ARE USED FOR BOTH TURNS — your move,
## and then theirs. Only the writing and the trim change.
var _left_heading: Label
var _right_heading: Label
var _right_note: Label
var _total_word: Label

## The big word across the middle of the screen. Used for THEIR TURN and for
## THEIR TURN IS OVER, so an enemy phase has a clear start and a clear end.
var _banner: Label

var _running := 0

## True while the two side windows are on screen. announce() reads it so that
## a banner shown between rounds does not leave the whole layer up, and one
## shown during the build-up does not tear it down.
var _windows_up := false


static func make(database: CardDatabase) -> AdventureBuildup:
	var made := AdventureBuildup.new()
	made.name = "AdventureBuildup"
	made.db = database
	return made


func _ready() -> void:
	# Over the pitch and over the enemy buttons, under the pause menu.
	layer = 90
	_build()
	hide()


# =============================================================
#  PLAYING IT
# =============================================================

## Show the move going in.
##
##   chain    the cards you drafted, weakest tier first (nulls allowed for
##            a tier that had nobody — they are shown as a broken pass)
##   foes     one entry per enemy: {"row": the CSV row, "left": what is left}
##   alive    which of those are still standing
##
## Returns when the windows have closed. The caller then plays the kick.
func play(chain: Array, foes: Array, alive: Array) -> void:
	if db == null or not db.tune_bool("adventure_buildup", true):
		finished.emit()
		return

	_dress_for(true)
	_running = 0
	for child in _left_box.get_children():
		child.queue_free()
	for child in _right_box.get_children():
		child.queue_free()
	_total_label.text = "0"
	_combo_label.text = ""
	_windows_up = true
	show()

	var step := db.tune_float("adventure_buildup_step", 0.55)
	var hold := db.tune_float("adventure_buildup_hold", 0.9)

	# The enemies are listed once and then edited in place, so their numbers
	# climb rather than the list being rebuilt under you.
	var foe_rows: Array[Label] = []
	var foe_gain: Array[int] = []
	for i in foes.size():
		var row: Dictionary = (foes[i] as Dictionary).get("row", {})
		var standing := i < alive.size() and bool(alive[i])
		var label := _foe_line(row, standing)
		_right_box.add_child(label)
		foe_rows.append(label)
		foe_gain.append(0)

	# --- the chain, one player at a time ---
	var so_far: Array[PlayerData] = []
	for i in chain.size():
		var card := chain[i] as PlayerData
		var tier := TierLadder.TIERS[i] if i < TierLadder.TIERS.size() else "?"

		if card == null:
			_left_box.add_child(_broken_line(tier))
			await _wait(step * 0.6)
			continue

		so_far.append(card)
		_running += card.get_attack_power()

		_left_box.add_child(_player_line(card, tier))
		_total_label.text = str(_running)
		_bump(_total_label)

		# A COMBO IS ANNOUNCED THE MOMENT IT COMPLETES, which is the whole
		# pleasure of it — you see the third Water player arrive and the
		# window says so before the shot goes in.
		var combos := ComboDB.fired(so_far)
		if not combos.is_empty():
			var words: Array[String] = []
			for rule in combos:
				words.append(ComboDB.describe(rule))
			_combo_label.text = "   ·   ".join(words)
			_bump(_combo_label)

		# --- every pass makes them angrier ---
		for f in foes.size():
			if f >= alive.size() or not bool(alive[f]):
				continue
			var row: Dictionary = (foes[f] as Dictionary).get("row", {})
			var buff := int(row.get("buff", 0))
			if buff <= 0:
				continue
			foe_gain[f] += buff
			foe_rows[f].text = _foe_text(row, true, foe_gain[f])
			foe_rows[f].add_theme_color_override("font_color", Color(0.95, 0.55, 0.45))

		await _wait(step)

	# --- what the move was worth in the end ---
	var bonus := ComboDB.bonus_for(so_far)
	if bonus > 0:
		_running += bonus
		_total_label.text = "%d" % _running
		_combo_label.text += "      = %d" % _running
		_bump(_total_label)

	await _wait(hold)

	# BOTH WINDOWS GO. What is left on the screen is the pitch, the enemy you
	# chose, and the player who is about to kick at it.
	await _fade_out()
	_windows_up = false
	hide()
	finished.emit()


# =============================================================
#  THEIR TURN
#
#  ============ WHY THIS EXISTS ============
#
#  You could watch your own move come together and then simply be told, in a
#  line of the log, that you had been hit for eleven. That is not a fight —
#  it is a receipt. So the enemies now get the same treatment your side gets:
#  they come on one at a time, each adds what it hits for to a running total,
#  their abilities are named, and ANY COMBO THEY COMPLETE FLASHES UP exactly
#  the way yours does.
#
#  ============ THEY USE YOUR COMBOS.CSV ============
#
#  Not a second table. The same one. Three Water enemies in a wave set off
#  the same Chained row that three Water players in your move would, because
#  a combo rule is written about elements and classes rather than about whose
#  side somebody is on. An enemy's Pool stands in for its class — marsh
#  things belong with marsh things — and a Boss counts as the Star.
#
#  Their bonus goes to ONE HIT, the last enemy to strike, for the same reason
#  yours goes to the shot and never to a card: a bonus on a card would move
#  the tier ladder, and a bonus on each of six enemies would be six times the
#  size of yours. One move, one bonus, both sides.
#
#      adventure_enemy_buildup     false and their window never opens. The
#                                  combos still fire — this only hides them
#      adventure_enemy_combos      false and their combos do not fire at all
# =============================================================

## Show their move coming together, the mirror of play().
##
##   foes    one entry per enemy: {"row": the CSV row, "left": what is left}
##   alive   which of those are still standing
##   gains   index -> what that enemy gained watching you build, or {}
##   bracing one line per tier of yours: {"tier": "I", "standing": 3}
##
## Returns when the windows have closed and they are ready to strike.
func play_their_turn(foes: Array, alive: Array, gains: Dictionary,
		bracing: Array) -> void:
	if db == null or not db.tune_bool("adventure_buildup", true) \
			or not db.tune_bool("adventure_enemy_buildup", true):
		finished.emit()
		return

	_dress_for(false)
	_running = 0
	for child in _left_box.get_children():
		child.queue_free()
	for child in _right_box.get_children():
		child.queue_free()
	_total_label.text = "0"
	_combo_label.text = ""
	_windows_up = true
	show()

	var step := db.tune_float("adventure_buildup_step", 0.55)
	var hold := db.tune_float("adventure_buildup_hold", 0.9)

	# --- RIGHT: your side, bracing. One line per tier. ---
	for entry in bracing:
		var line: Dictionary = entry
		_right_box.add_child(_bracing_line(String(line.get("tier", "?")),
			int(line.get("standing", 0))))

	# --- LEFT: them, one at a time ---
	var facts: Array[Dictionary] = []
	var slots := 0
	for i in foes.size():
		if i >= alive.size() or not bool(alive[i]):
			continue
		slots += 1
		var row: Dictionary = (foes[i] as Dictionary).get("row", {})
		var gained := int(gains.get(i, 0))
		facts.append(enemy_facts(row))
		_running += int(row.get("attack", 0)) + gained

		_left_box.add_child(_enemy_line(row, gained))
		_total_label.text = str(_running)
		_bump(_total_label)

		# THEIR COMBO IS ANNOUNCED THE MOMENT IT COMPLETES, the same as yours.
		if db.tune_bool("adventure_enemy_combos", true):
			var combos := ComboDB.fired_from(facts, slots)
			if not combos.is_empty():
				var words: Array[String] = []
				for rule in combos:
					words.append(ComboDB.describe(rule))
				_combo_label.text = "   ·   ".join(words)
				_bump(_combo_label)

		await _wait(step)

	var bonus := their_combo_bonus(foes, alive)
	if bonus > 0:
		_running += bonus
		_total_label.text = "%d" % _running
		_combo_label.text += "      = %d" % _running
		_bump(_total_label)

	await _wait(hold)
	await _fade_out()
	_windows_up = false
	hide()
	finished.emit()


## What THEIR combos are worth. Asked for separately because the fight needs
## the number whether or not their window was watched — exactly the same
## arrangement as combo_bonus() below.
static func their_combo_bonus(foes: Array, alive: Array) -> int:
	var facts: Array[Dictionary] = []
	for i in foes.size():
		if i >= alive.size() or not bool(alive[i]):
			continue
		facts.append(enemy_facts((foes[i] as Dictionary).get("row", {})))
	if facts.size() < 2:
		return 0
	return ComboDB.bonus_from(facts, facts.size())


## One enemy, reduced to the four things a combo rule asks about. See the
## header of combo_db.gd for why it is a plain dictionary and not a card.
static func enemy_facts(row: Dictionary) -> Dictionary:
	return {
		"element": String(row.get("element", "")),
		# ITS POOL STANDS IN FOR A CLASS. A pool is the group an enemy belongs
		# to, which is the nearest thing an enemy has to a club.
		"class": String(row.get("pool", "")),
		"power": int(row.get("attack", 0)),
		# A BOSS COUNTS AS THE STAR, so `star_last` fires when the boss strikes
		# last. That is the enemy version of your Star taking the shot.
		"star": bool(row.get("boss", false)),
	}


# =============================================================
#  THE BIG WORD IN THE MIDDLE
# =============================================================

## THE INDICATOR THAT THEIR TURN IS OVER.
##
## A fight used to end its enemy phase silently: the last red number floated
## up and then nothing happened until you noticed the cards were live again.
## Now the phase is bracketed — THEIR TURN when it starts, THEIR TURN IS OVER
## when it ends — so there is never a moment where you are waiting on the
## game and the game is waiting on you.
##
## Awaited, so a caller can let it be read before moving on.
func announce(text: String, tint: Color = MenuSupport.COLOUR_ACCENT,
		seconds: float = 0.8) -> void:
	if _banner == null:
		return
	_banner.text = text
	_banner.add_theme_color_override("font_color", tint)
	_banner.modulate.a = 0.0
	_banner.scale = Vector2(0.86, 0.86)
	_banner.pivot_offset = _banner.size * 0.5
	_banner.visible = true
	show()

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_banner, "modulate:a", 1.0, 0.16)
	tween.tween_property(_banner, "scale", Vector2.ONE, 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween.finished

	await _wait(seconds)

	var out := create_tween()
	out.tween_property(_banner, "modulate:a", 0.0, 0.2)
	await out.finished
	_banner.visible = false
	if not _windows_up:
		hide()


## Which set of words the two windows are wearing. One function so the two
## turns can never drift apart in look.
func _dress_for(mine: bool) -> void:
	if _left_heading == null:
		return
	_left_heading.text = "THE MOVE" if mine else "THEIR MOVE"
	_left_heading.add_theme_color_override("font_color",
		MenuSupport.COLOUR_ACCENT if mine else Color(0.92, 0.52, 0.45))
	_total_word.text = "SHOT" if mine else "THEY HIT FOR"
	_total_label.add_theme_color_override("font_color",
		MenuSupport.COLOUR_ACCENT if mine else Color(0.95, 0.55, 0.45))

	_right_heading.text = "THEY ANSWER" if mine else "YOU BRACE"
	_right_heading.add_theme_color_override("font_color",
		Color(0.92, 0.52, 0.45) if mine else MenuSupport.COLOUR_ACCENT)
	_right_note.text = "Every pass gives them time." if mine \
		else "An empty tier is a hole they come through."

	_trim(_left_panel, MenuSupport.COLOUR_ACCENT if mine else Color(0.62, 0.30, 0.30))
	_trim(_right_panel, Color(0.62, 0.30, 0.30) if mine else MenuSupport.COLOUR_ACCENT)
	_left_panel.visible = true
	_right_panel.visible = true


func _trim(panel: PanelContainer, edge: Color) -> void:
	if panel == null:
		return
	panel.add_theme_stylebox_override("panel", MenuSupport.panel_style(
		Color(0.07, 0.08, 0.11, 0.93), edge))


## What the combos added, so the fight can use the same number the window
## just showed. Asked for separately because the fight needs it whether or
## not the build-up was watched.
static func combo_bonus(chain: Array) -> int:
	var so_far: Array[PlayerData] = []
	for item in chain:
		var card := item as PlayerData
		if card != null:
			so_far.append(card)
	return ComboDB.bonus_for(so_far)


## What the enemies gained from watching you build it. One pass per player
## who actually touched the ball.
static func buff_gained(row: Dictionary, chain: Array) -> int:
	var buff := int(row.get("buff", 0))
	if buff <= 0:
		return 0
	var passes := 0
	for item in chain:
		if item != null:
			passes += 1
	return buff * passes


# =============================================================
#  THE TWO WINDOWS
# =============================================================

func _build() -> void:
	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)

	# --- LEFT: your move ---
	_left_panel = _window(holder, true)
	var left_column := _column(_left_panel)

	_left_heading = MenuSupport.heading("THE MOVE", 20, MenuSupport.COLOUR_ACCENT)
	left_column.add_child(_left_heading)

	_left_box = VBoxContainer.new()
	_left_box.add_theme_constant_override("separation", 6)
	_left_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_column.add_child(_left_box)

	left_column.add_child(HSeparator.new())

	var total_row := HBoxContainer.new()
	total_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_column.add_child(total_row)

	_total_word = Label.new()
	_total_word.text = "SHOT"
	_total_word.add_theme_font_size_override("font_size", 15)
	_total_word.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	_total_word.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_total_word.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_total_word.mouse_filter = Control.MOUSE_FILTER_IGNORE
	total_row.add_child(_total_word)

	_total_label = Label.new()
	_total_label.text = "0"
	_total_label.add_theme_font_size_override("font_size", 40)
	_total_label.add_theme_color_override("font_color", MenuSupport.COLOUR_ACCENT)
	_total_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	total_row.add_child(_total_label)

	_combo_label = Label.new()
	_combo_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_combo_label.add_theme_font_size_override("font_size", 14)
	_combo_label.add_theme_color_override("font_color", Color(0.55, 0.85, 0.6))
	_combo_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_column.add_child(_combo_label)

	# --- RIGHT: what they are doing about it ---
	_right_panel = _window(holder, false)
	var right_column := _column(_right_panel)

	_right_heading = MenuSupport.heading("THEY ANSWER", 20,
		Color(0.92, 0.52, 0.45))
	right_column.add_child(_right_heading)

	_right_note = Label.new()
	_right_note.text = "Every pass gives them time."
	_right_note.add_theme_font_size_override("font_size", 13)
	_right_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_right_note.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	_right_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_column.add_child(_right_note)

	_right_box = VBoxContainer.new()
	_right_box.add_theme_constant_override("separation", 6)
	_right_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_column.add_child(_right_box)

	# --- THE BIG WORD IN THE MIDDLE ---
	#
	# Added last so it draws over both windows. It is empty and hidden until
	# announce() is called, and it never takes the mouse.
	_banner = Label.new()
	_banner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 46)
	_banner.add_theme_constant_override("outline_size", 8)
	_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.visible = false
	holder.add_child(_banner)


## One of the two side panels. They hug the edges and leave the MIDDLE OF
## THE SCREEN EMPTY on purpose — that is where the pitch is, and where the
## shot is about to happen.
func _window(holder: Control, on_the_left: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(380, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", MenuSupport.panel_style(
		Color(0.07, 0.08, 0.11, 0.93),
		MenuSupport.COLOUR_ACCENT if on_the_left else Color(0.62, 0.30, 0.30)))

	if on_the_left:
		panel.set_anchors_preset(Control.PRESET_CENTER_LEFT)
		panel.offset_left = 24.0
		panel.offset_right = 404.0
	else:
		panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
		panel.offset_left = -404.0
		panel.offset_right = -24.0
	panel.offset_top = -220.0
	panel.offset_bottom = 220.0

	holder.add_child(panel)
	return panel


func _column(panel: PanelContainer) -> VBoxContainer:
	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 16)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(pad)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(column)
	return column


# =============================================================
#  THE LINES IN THEM
# =============================================================

func _player_line(card: PlayerData, tier: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var face := MenuSupport.portrait_rect(card, db, Vector2(52, 52))
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(face)

	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	words.add_theme_constant_override("separation", 1)
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(words)

	var name_label := Label.new()
	name_label.text = card.player_name
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_child(name_label)

	var under := Label.new()
	under.text = "Tier %s%s" % [tier, "   ★" if card.is_star() else ""]
	under.add_theme_font_size_override("font_size", 12)
	under.add_theme_color_override("font_color",
		MenuSupport.colour_for_tier(tier).lightened(0.3))
	under.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_child(under)

	var power := Label.new()
	power.text = "+%d" % card.get_attack_power()
	power.add_theme_font_size_override("font_size", 24)
	power.add_theme_color_override("font_color", MenuSupport.COLOUR_ACCENT)
	power.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	power.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(power)

	_slide_in(row, -40.0)
	return row


## A tier with nobody left in it. The move still goes on, it just loses a
## pass — and you can see exactly where it broke down.
func _broken_line(tier: String) -> Control:
	var label := Label.new()
	label.text = "Tier %s — nobody. The pass goes nowhere." % tier
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.85, 0.55, 0.45))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slide_in(label, -30.0)
	return label


func _foe_line(row: Dictionary, standing: bool) -> Label:
	var label := Label.new()
	label.text = _foe_text(row, standing, 0)
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color",
		MenuSupport.COLOUR_TEXT if standing else MenuSupport.COLOUR_TEXT_DIM)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _foe_text(row: Dictionary, standing: bool, gained: int) -> String:
	if not standing:
		return "%s — down" % row.get("name", "?")
	var base := int(row.get("attack", 0))
	if gained <= 0:
		return "%s   hits %d" % [row.get("name", "?"), base]
	return "%s   hits %d  ▲ +%d" % [row.get("name", "?"), base + gained, gained]


## ONE ENEMY ARRIVING in their build-up window — the mirror of
## _player_line(). It names what it hits for, what it gained watching you,
## and its Ability out of Abilities.csv if it has one.
func _enemy_line(row: Dictionary, gained: int) -> Control:
	var line := VBoxContainer.new()
	line.add_theme_constant_override("separation", 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(top)

	var name_label := Label.new()
	name_label.text = String(row.get("name", "?"))
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(name_label)

	var power := Label.new()
	power.text = "+%d" % (int(row.get("attack", 0)) + gained)
	power.add_theme_font_size_override("font_size", 24)
	power.add_theme_color_override("font_color", Color(0.95, 0.55, 0.45))
	power.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	power.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(power)

	var bits: Array[String] = []
	var element := String(row.get("element", "")).strip_edges()
	if element != "":
		bits.append(element)
	var ability := _ability_words(String(row.get("ability", "")))
	if ability != "":
		bits.append(ability)
	if gained > 0:
		bits.append("wound up +%d" % gained)

	var under := Label.new()
	under.text = "   ·   ".join(bits) if not bits.is_empty() else "plain"
	under.add_theme_font_size_override("font_size", 12)
	under.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	under.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	under.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(under)

	_slide_in(line, -40.0)
	return line


## An enemy's Ability column, read out of Abilities.csv the same way a
## player's is — so the two sides describe themselves in the same words. An
## id nothing answers to is printed as it was written, which is a hint that
## the row is missing rather than a silent blank.
func _ability_words(ability_id: String) -> String:
	var clean := ability_id.strip_edges()
	if clean == "" or db == null:
		return ""
	var ability := db.get_ability(clean)
	if ability == null:
		return clean
	var shown := ability.display_name.strip_edges()
	return shown if shown != "" else clean


## One tier of yours, in their window. Not a list of names: what matters
## while they are choosing a target is HOW MANY are still on their feet,
## because a tier with nobody in it is what doubles everything they do.
func _bracing_line(tier: String, standing: int) -> Control:
	var label := Label.new()
	if standing <= 0:
		label.text = "Tier %s — nobody. Everything they do lands twice." % tier
		label.add_theme_color_override("font_color", Color(0.90, 0.45, 0.40))
	else:
		label.text = "Tier %s — %d standing" % [tier, standing]
		label.add_theme_color_override("font_color",
			MenuSupport.colour_for_tier(tier).lightened(0.3))
	label.add_theme_font_size_override("font_size", 14)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slide_in(label, -30.0)
	return label


# =============================================================
#  MOVEMENT
# =============================================================

## A line arriving. Small and quick — this happens four times a round and a
## slow flourish would be tiresome by the third fight.
##
## IT FADES AND GROWS, IT DOES NOT SLIDE. The lines live in a VBoxContainer,
## and a container rewrites its children's positions every frame — so a
## tween on `position` is overwritten before it is ever seen. `modulate` and
## `scale` are not touched by the container, so those are what move.
func _slide_in(node: Control, _unused: float) -> void:
	node.modulate.a = 0.0
	node.pivot_offset = Vector2(0.0, 16.0)
	node.scale = Vector2(0.94, 0.94)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(node, "modulate:a", 1.0, 0.18)
	tween.tween_property(node, "scale", Vector2.ONE, 0.22) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## A number that just changed, so the eye goes to it.
func _bump(node: Control) -> void:
	node.pivot_offset = node.size * 0.5
	var tween := create_tween()
	tween.tween_property(node, "scale", Vector2(1.22, 1.22), 0.08)
	tween.tween_property(node, "scale", Vector2.ONE, 0.14)


func _fade_out() -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_left_panel, "modulate:a", 0.0, 0.25)
	tween.tween_property(_right_panel, "modulate:a", 0.0, 0.25)
	await tween.finished
	_left_panel.modulate.a = 1.0
	_right_panel.modulate.a = 1.0


## Waits in real seconds AND respects the speed control, so turning the game
## up to 8x speeds the build-up up too rather than leaving it plodding.
func _wait(seconds: float) -> void:
	var scaled := seconds / maxf(GameSpeed.current(), 0.05)
	await get_tree().create_timer(maxf(0.02, scaled), true, false, true).timeout
