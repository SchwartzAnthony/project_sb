class_name TraitBar
extends PanelContainer

# =============================================================
#  THE BAR ACROSS THE TOP
#
#  Every icon in AdventureTraits.csv, always, in Order order. A trait you
#  have none of is still there — greyed out, reading 0/2 — because knowing
#  what you are NOT building is half of knowing what to send next.
#
#  ONE TILE PER TRAIT:
#
#      the picture      the Icon of the highest breakpoint you have reached,
#                       so the image changes as you climb. No file yet = a
#                       coloured pip with the trait's initial, which plays
#                       perfectly well
#      the name         from the spreadsheet
#      3/4              what you have, and what the next breakpoint needs
#      the line under    what the breakpoint you are on does
#
#  NOTHING IS DECIDED HERE. The stack is trait_stack.gd and the rules are
#  AdventureCombos.csv. This draws what they say and nothing else, which is
#  why you can delete every row of the spreadsheet and the bar simply goes
#  empty instead of the fight breaking.
#
#  Where it sits and how big it is:
#      adventure_trait_bar        false and there is no bar at all
#      adventure_trait_bar_top    how far down the screen it starts
#      adventure_trait_tile_width how wide one tile is
# =============================================================

const FALLBACK_WIDTH := 164.0

var db: CardDatabase
var stack: TraitStack

var _row: HFlowContainer
## trait id -> the bits of its tile that get repainted.
var _tiles: Dictionary = {}

## ============ WHAT THE CARD YOU ARE POINTING AT WOULD DO ============
##
## Hovering a card in the choice window used to grey the card and write a
## sentence in the bar along the bottom — which put the answer as far from
## the question as it is possible to get on a 1920-wide screen.
##
## Now the ICONS THAT PLAYER CARRIES BLINK, up here where you are already
## looking, and their tiles read `2 → 3` instead of `2/3`. If that step would
## cross a breakpoint, the tile shows the one it would reach. You can see
## what a card is worth without reading anything.
##
## It is a preview and nothing more: the stack itself is untouched until you
## actually click.
var _preview: Array[String] = []
var _blinks: Array[Tween] = []


static func make(database: CardDatabase, the_stack: TraitStack) -> TraitBar:
	var bar := TraitBar.new()
	bar.name = "TraitBar"
	bar.db = database
	bar.stack = the_stack
	return bar


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", MenuSupport.panel_style(
		Color(0.07, 0.08, 0.11, 0.88), MenuSupport.COLOUR_ACCENT))

	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right"]:
		pad.add_theme_constant_override(side, 8)
	for side in ["margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 8)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(pad)

	_row = HFlowContainer.new()
	_row.add_theme_constant_override("h_separation", 4)
	_row.add_theme_constant_override("v_separation", 8)
	_row.alignment = FlowContainer.ALIGNMENT_CENTER
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(_row)

	_build()
	refresh()


## Put it across the top of a full-rect holder, centred, growing downward as
## it wraps. It is placed here rather than by the caller so that every screen
## that ever shows a trait bar puts it in the same place.
func place_in(holder: Control) -> void:
	var width := db.tune_float("adventure_trait_tile_width", FALLBACK_WIDTH)
	holder.add_child(self)
	set_anchors_preset(Control.PRESET_TOP_WIDE)
	# A MARGIN WIDE ENOUGH TO CLEAR THE HEADLINE on the left and the haul on
	# the right. The bar is centred inside whatever is left.
	#
	# EIGHT TILES FIT ON ONE LINE at the default width. A ninth wraps onto a
	# second, the bar gets taller, and you will want to raise
	# adventure_choice_top so the card window still clears it — or narrow
	# adventure_trait_tile_width, which is usually the easier answer.
	offset_left = db.tune_float("adventure_trait_bar_left", 260.0)
	offset_right = -db.tune_float("adventure_trait_bar_right", 240.0)
	offset_top = db.tune_float("adventure_trait_bar_top", 22.0)
	# GROW DOWNWARD. The offsets above give it a starting box; as the tiles
	# wrap onto a second line the panel gets taller, and it must get taller
	# DOWNWARDS or it would climb off the top of the screen.
	grow_vertical = Control.GROW_DIRECTION_END
	offset_bottom = offset_top + 96.0
	custom_minimum_size = Vector2(width * 2.0, 0)


# =============================================================
#  BUILDING IT ONCE
# =============================================================

func _build() -> void:
	for child in _row.get_children():
		child.queue_free()
	_tiles.clear()

	var width := db.tune_float("adventure_trait_tile_width", FALLBACK_WIDTH)
	for entry in TraitDB.live():
		_row.add_child(_tile(entry, width))


func _tile(entry: Dictionary, width: float) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(width, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 7)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(pad)

	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(line)

	# --- the picture, or a pip with the first letter in it ---
	var picture := TextureRect.new()
	picture.custom_minimum_size = Vector2(28, 28)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(picture)

	var pip := Label.new()
	pip.text = String(entry["name"]).substr(0, 1).to_upper()
	pip.custom_minimum_size = Vector2(28, 28)
	pip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pip.add_theme_font_size_override("font_size", 17)
	pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(pip)

	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	words.add_theme_constant_override("separation", 0)
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(words)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_child(top)

	# ============ A TILE MUST NOT BE ABLE TO GROW ============
	#
	# custom_minimum_size is a MINIMUM. A PanelContainer takes the size its
	# contents ask for, so the moment a label inside wanted more room the tile
	# got wider — and eight tiles that each grew by ten pixels pushed the last
	# one onto a second line. That happened the first time a tile read
	# `0 → 1` instead of `0/2`.
	#
	# clip_text makes a Label's minimum width zero: it takes the room it is
	# given and cuts off anything that does not fit. With that on the name,
	# and a fixed width reserved for the count, the tile is exactly as wide as
	# adventure_trait_tile_width says and never a pixel more.
	var name_label := Label.new()
	name_label.text = String(entry["name"])
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(name_label)

	var score := Label.new()
	score.add_theme_font_size_override("font_size", 13)
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score.clip_text = true
	score.custom_minimum_size = Vector2(40, 0)
	score.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(score)

	# TWO SHORT LINES, NOT ONE LONG ONE. A tile is 150 pixels wide. The
	# breakpoint's name and what it does were on one line and both were being
	# cut off mid-word, which reads as a bug rather than as a summary. One
	# line each, and they fit. The full sentence you wrote in the Description
	# column is in the tooltip, where there is room for it.
	var step_name := Label.new()
	step_name.add_theme_font_size_override("font_size", 11)
	step_name.clip_text = true
	step_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_child(step_name)

	var step_tag := Label.new()
	step_tag.add_theme_font_size_override("font_size", 11)
	step_tag.clip_text = true
	step_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_child(step_tag)

	_tiles[String(entry["id"]).to_lower()] = {
		"panel": panel, "picture": picture, "pip": pip,
		"name": name_label, "score": score,
		"step_name": step_name, "step_tag": step_tag,
		"entry": entry,
	}
	return panel


# =============================================================
#  REPAINTING IT
# =============================================================

## Called after every pick, and after the cycle empties the stack.
func refresh() -> void:
	if stack == null:
		return
	for key in _tiles.keys():
		_paint(String(key), _tiles[key] as Dictionary)


## Show what adding these icons WOULD do. Called as the mouse goes over a
## card in the choice window.
func preview(icons: Array[String]) -> void:
	var clean: Array[String] = []
	for icon in icons:
		clean.append(icon.to_lower())
	if clean == _preview:
		return
	_preview = clean
	refresh()
	_start_blinking()


## Back to the truth. Called as the mouse leaves.
func clear_preview() -> void:
	if _preview.is_empty():
		return
	_preview = []
	_stop_blinking()
	refresh()


## A slow pulse on the tiles the hovered card would move. Every blinking tile
## shares one tween per tile, and they are all killed the moment the preview
## ends — a tween left running on a freed node is how a UI starts flickering
## at random three screens later.
func _start_blinking() -> void:
	_stop_blinking()
	for key in _preview:
		var bits: Dictionary = _tiles.get(key, {})
		if bits.is_empty():
			continue
		var panel: PanelContainer = bits["panel"]
		if not is_instance_valid(panel):
			continue
		panel.modulate.a = 1.0
		var blink := panel.create_tween()
		blink.set_loops()
		blink.tween_property(panel, "modulate:a", 0.45, 0.32) \
			.set_trans(Tween.TRANS_SINE)
		blink.tween_property(panel, "modulate:a", 1.0, 0.32) \
			.set_trans(Tween.TRANS_SINE)
		_blinks.append(blink)


func _stop_blinking() -> void:
	for blink in _blinks:
		if blink != null and blink.is_valid():
			blink.kill()
	_blinks.clear()
	for key in _tiles.keys():
		var bits: Dictionary = _tiles[key]
		var panel: PanelContainer = bits["panel"]
		if is_instance_valid(panel):
			panel.modulate.a = 1.0


func _paint(key: String, bits: Dictionary) -> void:
	var entry: Dictionary = bits["entry"]
	var have := stack.count_of(key)
	# THE CARD YOU ARE POINTING AT IS COUNTED IN. A trait this card carries
	# is painted as though it had already been played, so the tile shows the
	# breakpoint you would GET rather than the one you have.
	var previewing := _preview.has(key)
	var shown := have + (1 if previewing else 0)
	var need := TraitDB.next_at(key, shown)
	var best := TraitDB.best(key, shown)
	var lit := not best.is_empty()

	var tint: Color = entry["colour"]
	var panel: PanelContainer = bits["panel"]

	# ============ THREE LOOKS, NOT TWO ============
	#
	#   lit         a breakpoint has been reached. Full colour
	#   previewing  the card under the mouse would move this icon. A coloured
	#               edge and a lifted background, whether or not it is lit
	#   neither     grey
	#
	# There used to be only the first and the last, and the difference showed
	# up as a bug: pointing at a TIER I card lit nothing at all. Tier I is the
	# first card of a cycle, so the count goes 0 → 1 and one is never enough
	# to reach a breakpoint. Pointing at a Tier II card lit the bar, because
	# by then the count was 1 and one more made 2.
	#
	# So the bar was answering "have you reached something" when the question
	# the mouse is asking is "does this card touch this icon". Both are worth
	# seeing, and they now look different from each other.
	var edge := Color(0.24, 0.26, 0.30)
	var fill := Color(0.10, 0.11, 0.14, 0.75)
	if lit:
		edge = tint
		fill = Color(tint.r * 0.30, tint.g * 0.30, tint.b * 0.30, 0.92)
	if previewing:
		edge = tint.lightened(0.25)
		fill = Color(tint.r * 0.42, tint.g * 0.42, tint.b * 0.42, 0.95) if lit \
			else Color(tint.r * 0.22, tint.g * 0.22, tint.b * 0.22, 0.92)
	panel.add_theme_stylebox_override("panel", MenuSupport.panel_style(fill, edge))

	# THE PICTURE CHANGES AS YOU CLIMB. The breakpoint's own Icon when it has
	# one, the trait's otherwise — so Fire at 3 can look different from Fire
	# at 2 without a line of code.
	var wanted := String(best.get("icon", "")) if lit else ""
	if wanted == "":
		wanted = String(entry["icon"])
	var picture: TextureRect = bits["picture"]
	var pip: Label = bits["pip"]
	var art := MenuSupport.icon_texture(wanted)
	picture.texture = art
	picture.visible = art != null
	pip.visible = art == null
	pip.add_theme_color_override("font_color",
		tint if lit or previewing else Color(0.40, 0.43, 0.48))

	var words: Color = MenuSupport.COLOUR_TEXT if lit or previewing \
		else Color(0.50, 0.53, 0.58)
	(bits["name"] as Label).add_theme_color_override("font_color", words)

	var score: Label = bits["score"]
	# `2 → 3` while you are pointing at a card that would move it, `2/3`
	# otherwise. The arrow is the whole message.
	score.text = "%d→%d" % [have, shown] if previewing else "%d/%d" % [shown, need]
	score.add_theme_color_override("font_color", tint if lit or previewing else words)

	var step_name: Label = bits["step_name"]
	var step_tag: Label = bits["step_tag"]
	if lit:
		step_name.text = String(best["name"])
		step_tag.text = _short(best)
		step_name.add_theme_color_override("font_color", tint.lightened(0.3))
		step_tag.add_theme_color_override("font_color", tint.lightened(0.1))
	else:
		# NOT BLANK WHEN IT IS EMPTY. An empty tile that says nothing looks
		# broken; one that says what it would take looks like a plan.
		var first := _first_step(key)
		if first.is_empty():
			step_name.text = "no combos yet"
			step_tag.text = ""
		else:
			step_name.text = "at %d:" % need
			step_tag.text = String(first.get("name", ""))
		var dim := Color(0.44, 0.47, 0.52)
		step_name.add_theme_color_override("font_color", dim)
		step_tag.add_theme_color_override("font_color", dim)

	panel.tooltip_text = _explain(key, entry, have)


## A breakpoint in three or four characters, for the tile. The sentence a
## designer wrote lives in the Description column and is shown in full in the
## tooltip; this is what fits on the bar.
func _short(step: Dictionary) -> String:
	var value := int(step["value"])
	match String(step["effect"]):
		"attack":
			return "+%d shot" % value
		"shield":
			return "-%d taken" % value
		"heal", "stamina":
			return "+%d hp" % value
		"revive":
			return "revive %d" % value
		"spawn":
			return String(step["target"]).capitalize()
		"strike":
			return "%d dmg" % value
	return ""


## The lowest breakpoint in a trait, for the "at 2: Kindling" hint.
func _first_step(key: String) -> Dictionary:
	var all: Array = TraitDB.get_db().steps.get(key, [])
	return all[0] as Dictionary if not all.is_empty() else {}


## The whole ladder for one trait, reached ones marked, for the tooltip.
func _explain(key: String, entry: Dictionary, have: int) -> String:
	var lines: Array[String] = ["%s — %d on the pile" % [entry["name"], have]]
	var all: Array = TraitDB.get_db().steps.get(key, [])
	if all.is_empty():
		lines.append("No breakpoints written for this yet. Add a row to AdventureCombos.csv.")
	for step in all:
		var row: Dictionary = step
		lines.append("%s %d  %s — %s%s" % [
			"✓" if int(row["at"]) <= have else " ",
			int(row["at"]), row["name"], row["description"],
			"   (once)" if String(row["lasts"]) == "once" else ""])
	if String(entry["notes"]).strip_edges() != "":
		lines.append("")
		lines.append(String(entry["notes"]))
	return "\n".join(lines)
