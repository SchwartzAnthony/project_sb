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

var _running := 0


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

	_running = 0
	for child in _left_box.get_children():
		child.queue_free()
	for child in _right_box.get_children():
		child.queue_free()
	_total_label.text = "0"
	_combo_label.text = ""
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
	hide()
	finished.emit()


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

	left_column.add_child(MenuSupport.heading("THE MOVE", 20, MenuSupport.COLOUR_ACCENT))

	_left_box = VBoxContainer.new()
	_left_box.add_theme_constant_override("separation", 6)
	_left_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_column.add_child(_left_box)

	left_column.add_child(HSeparator.new())

	var total_row := HBoxContainer.new()
	total_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_column.add_child(total_row)

	var total_word := Label.new()
	total_word.text = "SHOT"
	total_word.add_theme_font_size_override("font_size", 15)
	total_word.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	total_word.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	total_word.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	total_word.mouse_filter = Control.MOUSE_FILTER_IGNORE
	total_row.add_child(total_word)

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

	right_column.add_child(MenuSupport.heading("THEY ANSWER", 20,
		Color(0.92, 0.52, 0.45)))

	var note := Label.new()
	note.text = "Every pass gives them time."
	note.add_theme_font_size_override("font_size", 13)
	note.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_column.add_child(note)

	_right_box = VBoxContainer.new()
	_right_box.add_theme_constant_override("separation", 6)
	_right_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_column.add_child(_right_box)


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
