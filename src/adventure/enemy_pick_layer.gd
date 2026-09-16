class_name EnemyPickLayer
extends CanvasLayer

# =============================================================
#  THE ENEMIES ARE THE BUTTONS
#
#  You do not pick a target off a list in a panel any more. You point at the
#  thing on the pitch and click it, and hovering it reads the whole card out
#  — picture, power, armour, element, ability — in a little window beside it.
#
#  ============ WHY THIS IS A LAYER AND NOT A DISTANCE CHECK ============
#
#  The first version worked out which enemy the mouse was nearest to. That
#  is fine for clicking and useless for everything else: no hover highlight
#  from the engine, no tooltips, nothing for a controller to move between,
#  and an enemy behind a panel was still clickable through it.
#
#  So each living enemy gets a REAL Button, invisible, sitting exactly on top
#  of it and following it every frame. Godot then does the hovering, the
#  clicking and the focus order for us, and the same layer will work with a
#  controller the day you want one.
#
#  ============ WHAT THE HOVER WINDOW SHOWS ============
#
#  Everything a row of AdventureEnemies.csv has to say about that enemy:
#
#      Art          the picture, if you have drawn one
#      Name         and whether it is the boss
#      Attack       what it hits for
#      Layers       its armour, layer by layer, and what is left of each
#      Element      what it counts as
#      Ability      the row of Abilities.csv it uses, in that ability's words
#      Targeting    who it goes after
#      Description  yours
#
#  Add a column to that spreadsheet and show it here in one line. Nothing in
#  this file knows the name of a single enemy.
# =============================================================

signal hovered(index: int)
signal chosen(index: int)

## The enemy nodes on the pitch, in the same order the fight holds them.
var foe_nodes: Array[Node2D] = []
## Asked before a button is offered: is this one still standing?
var alive_check: Callable = Callable()
## Asked for the CSV row and what is left of it: index -> Dictionary.
var describe_source: Callable = Callable()

var db: CardDatabase

var _buttons: Array[Button] = []
var _card: PanelContainer
var _card_body: VBoxContainer
var _live: bool = false


static func make(database: CardDatabase) -> EnemyPickLayer:
	var made := EnemyPickLayer.new()
	made.name = "EnemyPickLayer"
	made.db = database
	return made


func _ready() -> void:
	# Above the pitch, below the combat bar and well below the pause menu.
	layer = 40
	_build_card()


# =============================================================
#  TURNING PICKING ON AND OFF
# =============================================================

## Picking is only live while the fight is waiting for a target. At every
## other moment the buttons are gone, so a stray click during the animation
## cannot re-target the shot half way through it.
func set_live(on: bool) -> void:
	_live = on
	_rebuild()
	if not on:
		_card.hide()


func refresh() -> void:
	_rebuild()


func _rebuild() -> void:
	for button in _buttons:
		if is_instance_valid(button):
			button.queue_free()
	_buttons.clear()
	if not _live:
		return

	for i in foe_nodes.size():
		if not _is_alive(i):
			continue
		var node := foe_nodes[i]
		if node == null or not is_instance_valid(node):
			continue

		var button := Button.new()
		button.focus_mode = Control.FOCUS_ALL
		button.flat = true
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		# INVISIBLE ON PURPOSE. The enemy underneath already draws its own
		# hover ring and its own focus ring — see _draw_foe() in
		# adventure_scene.gd — so a second box around it would only be a
		# second thing to look at.
		button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		button.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
		button.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
		button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

		var reach := _reach_of(i)
		button.custom_minimum_size = reach
		button.size = reach

		button.mouse_entered.connect(_on_enter.bind(i))
		button.focus_entered.connect(_on_enter.bind(i))
		button.mouse_exited.connect(_on_leave)
		button.pressed.connect(func() -> void: chosen.emit(i))

		add_child(button)
		_buttons.append(button)

	_follow()


## How big the clickable box is. Generous around a small enemy so picking one
## never feels fiddly, and it grows with a boss.
func _reach_of(index: int) -> Vector2:
	var side := 64.0
	var row := _row_of(index)
	if _is_boss(row):
		side = 96.0
	if db != null:
		side *= db.tune_float("adventure_enemy_reach_scale", 1.0)
	return Vector2(side, side)


func _process(_delta: float) -> void:
	if _live:
		_follow()


## Keep every button sitting on its enemy. The enemies walk in from the right
## at the start of a wave, so this cannot be done once and forgotten.
func _follow() -> void:
	var at := 0
	for i in foe_nodes.size():
		if not _is_alive(i):
			continue
		if at >= _buttons.size():
			return
		var node := foe_nodes[i]
		if node != null and is_instance_valid(node):
			var button := _buttons[at]
			# There is no camera on the run, so a world position is already
			# a screen position. If you ever add one, this is the single
			# line that would need the transform.
			button.position = node.global_position - button.size * 0.5
		at += 1


# =============================================================
#  THE HOVER WINDOW
# =============================================================

func _on_enter(index: int) -> void:
	hovered.emit(index)
	_show_card(index)


func _on_leave() -> void:
	_card.hide()
	# -1 means "nothing", so whatever was reading the enemy out can stop.
	hovered.emit(-1)


func _build_card() -> void:
	_card = PanelContainer.new()
	_card.custom_minimum_size = Vector2(340, 0)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_theme_stylebox_override("panel", MenuSupport.panel_style(
		Color(0.07, 0.08, 0.11, 0.96), MenuSupport.COLOUR_ACCENT))
	_card.hide()
	add_child(_card)

	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 12)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(pad)

	_card_body = VBoxContainer.new()
	_card_body.add_theme_constant_override("separation", 5)
	_card_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(_card_body)


func _show_card(index: int) -> void:
	for child in _card_body.get_children():
		child.queue_free()

	var told: Dictionary = {}
	if describe_source.is_valid():
		told = describe_source.call(index)
	var row: Dictionary = told.get("row", {})
	if row.is_empty():
		_card.hide()
		return

	var boss := _is_boss(row)

	# --- picture ---
	var art := MenuSupport.icon_texture(String(row.get("art", "")))
	if art != null:
		var picture := TextureRect.new()
		picture.texture = art
		picture.custom_minimum_size = Vector2(0, 120)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_card_body.add_child(picture)

	# --- name ---
	var title := MenuSupport.heading(
		"%s%s" % [row.get("name", "?"), "   ☠ BOSS" if boss else ""],
		20, MenuSupport.COLOUR_ACCENT)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_body.add_child(title)

	# --- the numbers ---
	_card_body.add_child(_line("Hits for %d" % int(row.get("attack", 0)),
		MenuSupport.COLOUR_TEXT, 16))
	_card_body.add_child(_line("Goes for the %s"
		% row.get("targeting", "weakest"), MenuSupport.COLOUR_TEXT_DIM, 13))

	var element := String(row.get("element", "")).strip_edges()
	if element != "":
		_card_body.add_child(_line("Element: %s" % element,
			MenuSupport.COLOUR_TEXT_DIM, 13))

	# --- the armour, layer by layer ---
	var layers: Array = row.get("layers", [])
	var left: Array = told.get("left", [])
	if not layers.is_empty():
		_card_body.add_child(HSeparator.new())
		for i in layers.size():
			var layer: Dictionary = layers[i]
			var remaining := int(left[i]) if i < left.size() else int(layer.get("amount", 0))
			var soak := int(layer.get("soak", 0))
			var gone := remaining <= 0
			_card_body.add_child(_line(
				"%s   %d / %d%s" % [layer.get("name", "Layer"), remaining,
					int(layer.get("amount", 0)),
					"   soaks %d" % soak if soak > 0 else ""],
				MenuSupport.COLOUR_TEXT_DIM if gone else MenuSupport.COLOUR_TEXT, 14))

	# --- the ability, in the ability's own words ---
	var ability_id := String(row.get("ability", "")).strip_edges()
	if ability_id != "" and db != null:
		var ability := db.abilities.get(ability_id.to_lower(), null) as AbilityData
		_card_body.add_child(HSeparator.new())
		if ability != null:
			var shown := ability.display_name
			if shown.strip_edges() == "":
				shown = ability_id
			_card_body.add_child(_line(shown, MenuSupport.COLOUR_ACCENT, 15))
			var words := ability.notes
			if words.strip_edges() == "":
				# No note written yet, so say what it mechanically does. Better
				# than a blank line, and it is a nudge to write the note.
				words = "%s %s %+d (%s)" % [ability.trigger, ability.effect,
					ability.value, ability.target]
			_card_body.add_child(_line(words, MenuSupport.COLOUR_TEXT_DIM, 13))
		else:
			# Naming an ability that is not in Abilities.csv is a content
			# mistake worth seeing, not worth hiding.
			_card_body.add_child(_line(
				"Ability '%s' is not in Abilities.csv" % ability_id,
				Color(0.95, 0.6, 0.45), 13))

	# --- the designer's own line ---
	var blurb := String(row.get("description", "")).strip_edges()
	if blurb != "":
		_card_body.add_child(HSeparator.new())
		_card_body.add_child(_line(blurb, MenuSupport.COLOUR_TEXT_DIM, 13))

	_card.show()
	_place_card(index)


## Beside the enemy, and always ON the screen — a card that runs off the
## right edge is a card you cannot read.
func _place_card(index: int) -> void:
	var node: Node2D = foe_nodes[index] if index < foe_nodes.size() else null
	if node == null or not is_instance_valid(node):
		return

	# One frame for the panel to work out how tall it is, then place it.
	await get_tree().process_frame
	if not is_instance_valid(_card):
		return

	var screen := get_viewport().get_visible_rect().size
	var box := _card.size
	var spot := node.global_position + Vector2(56.0, -box.y * 0.5)

	if spot.x + box.x > screen.x - 16.0:
		spot.x = node.global_position.x - box.x - 56.0
	spot.x = clampf(spot.x, 16.0, maxf(16.0, screen.x - box.x - 16.0))
	spot.y = clampf(spot.y, 16.0, maxf(16.0, screen.y - box.y - 16.0))
	_card.position = spot


# =============================================================
#  SMALL THINGS
# =============================================================

func _line(text: String, tint: Color, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", tint)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _is_alive(index: int) -> bool:
	if not alive_check.is_valid():
		return true
	return bool(alive_check.call(index))


func _row_of(index: int) -> Dictionary:
	if not describe_source.is_valid():
		return {}
	var told: Dictionary = describe_source.call(index)
	return told.get("row", {})


static func _is_boss(row: Dictionary) -> bool:
	var flag: Variant = row.get("boss", false)
	if flag is bool:
		return flag
	return String(flag).strip_edges().to_lower() in ["yes", "true", "1"]
