class_name EmblemBar
extends CanvasLayer

# =============================================================
#  THE EMBLEMS ALONG THE TOP OF THE PITCH
#
#  ============ WHAT YOU ASKED FOR ============
#
#  "Star Players have Emblems that are presented — so like an icon on the top
#   of the field. Star Units when coming into the field place their emblem,
#   which has the conditions on it."
#
#  So this is the bar. One tile per Emblem your Stars brought on, with the
#  Condition it is racing toward and how far along it is.
#
#  ============ WHAT A TILE SHOWS, AND WHY EACH PART IS THERE ============
#
#      the picture      which Emblem it is, at a glance and from a distance
#      the name         the demon
#      the pips         HOW FAR ALONG. Three of five filled is the whole
#                       point of putting it on screen — an Emblem you cannot
#                       see the progress of is a rule you have to remember
#      the words        the Condition, in the player's own prose
#
#  A tile is in one of three states and each one looks different from across
#  the room, because that is the distance a player reads a match from:
#
#      RACING     lit edge, pips filling
#      ASCENDED   accent edge, the star, and the Ultimate Side under it
#      HELD       dimmed. Somebody else got there first
#
#  ============ IT OWNS NOTHING ============
#
#  Every number on it is read from EmblemBook each time it refreshes. There is
#  no copy of the race in here to go stale, so a substitution changes the bar
#  and nothing has to be told about it.
# =============================================================

## The cards this side has on the pitch. Set it and call refresh().
var squad: Array[PlayerData] = []
## ROUND AB (your answer Q011): the OTHER side's Star(s) on the pitch, so you
## can see the Emblem you are playing against. `emblem_show_enemy` in Tuning.
var enemy_squad: Array[PlayerData] = []
var state: GameState = null

var _row: HBoxContainer = null
var _tiles: Dictionary = {}     ## emblem key -> the tile Control


## Put a bar over `on`. Returns null when emblems are switched off, so a
## caller can write one line and not think about it.
static func open(on: Node, cards: Array[PlayerData], save: GameState) -> EmblemBar:
	var db := CardDatabase.get_db()
	if db != null and not db.tune_bool("emblems_on_field", true):
		return null
	var made := EmblemBar.new()
	made.name = "EmblemBar"
	# ROUND AA: UNDER THE DUEL AND SHOT WINDOWS (layers 20 and 21), so a duel
	# is never read through the bar. `emblem_bar_layer` in Tuning.csv.
	made.layer = db.tune_int("emblem_bar_layer", 18) if db != null else 18
	made.squad = cards
	made.state = save
	on.add_child(made)
	made.refresh()
	return made


func _ready() -> void:
	var db := CardDatabase.get_db()
	# BELOW THE SCOREBOARD. See the note on `emblem_bar_top` in Tuning.csv:
	# the score box is 96 tall and starts about 20 down, so a bar any higher
	# than this sits on top of the score.
	var top := 126.0
	if db != null:
		top = db.tune_float("emblem_bar_top", 126.0)

	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.offset_top = top
	holder.offset_bottom = top + 200.0
	add_child(holder)

	_row = HBoxContainer.new()
	_row.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	# ROUND AA: TO THE RIGHT by default, under the clock - the middle of the
	# screen belongs to the ATTACKING / DEFENDING banner during the draft, and
	# the two were drawn on top of each other. `emblem_bar_align`: left,
	# centre or right.
	var align := db.tune_text("emblem_bar_align", "right").to_lower() if db != null else "right"
	_row.alignment = BoxContainer.ALIGNMENT_END if align == "right" \
		else (BoxContainer.ALIGNMENT_BEGIN if align == "left" else BoxContainer.ALIGNMENT_CENTER)
	_row.offset_right = -16.0
	_row.offset_left = 16.0
	_row.add_theme_constant_override("separation", 10)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(_row)


## Read the whole bar again. Cheap enough to call at the end of every duel,
## which is what main_scene does.
func refresh() -> void:
	if _row == null:
		return
	for child in _row.get_children():
		child.queue_free()
	_tiles = {}

	var db := CardDatabase.get_db()
	if db == null or db.tune_bool("emblem_show_enemy", true):
		for badge in EmblemBook.on_the_field(enemy_squad):
			_row.add_child(_enemy_tile(badge))
	var shown := 0
	for badge in EmblemBook.on_the_field(squad):
		var tile := _tile(badge)
		_row.add_child(tile)
		_tiles[CardDatabase._normalise(badge.id)] = tile
		shown += 1
	# Said in the Output panel, so "I do not see the Emblem" can be checked
	# against what the game thinks it is showing.
	var names: PackedStringArray = PackedStringArray()
	for card in squad:
		if card != null:
			names.append(card.player_name)
	print("[emblems] the bar shows %d Emblem(s) for %s" % [shown, ", ".join(names) if not names.is_empty() else "NO STAR"])


func _tile(badge: ClassBook.Emblem) -> Control:
	var db := CardDatabase.get_db()
	var size := 56.0
	if db != null:
		size = db.tune_float("emblem_bar_size", 56.0)

	var up := EmblemBook.is_up(badge, state)
	var held := EmblemBook.is_locked(badge, state)
	var blocked := EmblemBook.is_blocked(badge, state)
	var bits := EmblemBook.progress(badge, state)
	# ROUND AB (Q009): a held Emblem keeps its Basic side, so it is only
	# dimmed when the old rule (emblem_locked_is_inactive) is back on.
	var basic_dead := db != null and db.tune_bool("emblem_locked_is_inactive", false)

	var edge := MenuSupport.COLOUR_TEXT_DIM
	if up:
		edge = MenuSupport.COLOUR_ACCENT
	elif held:
		edge = MenuSupport.COLOUR_LOCKED
	elif int(bits["have"]) > 0:
		edge = MenuSupport.COLOUR_ATTACK

	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel",
		MenuSupport.styled("panel", "", MenuSupport.COLOUR_PANEL, edge))
	# THE BAR DOES NOT EAT CLICKS. It sits over the pitch and a player has to
	# be able to press a card that happens to be under it.
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if blocked:
		frame.modulate = Color(0.55, 0.55, 0.55, 0.9)
	elif held and basic_dead:
		frame.modulate = Color(1.0, 1.0, 1.0, 0.45)

	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right"]:
		pad.add_theme_constant_override(side, 10)
	for side in ["margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 7)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(pad)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(row)

	# ---- the picture ----
	var art := MenuSupport.icon_texture(badge.art)
	if art != null:
		var picture := TextureRect.new()
		picture.texture = art
		picture.custom_minimum_size = Vector2(size, size)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(picture)
	else:
		# NO ART IS NOT A GAP. An Emblem with no picture is a lettered square,
		# so the bar works from the first minute and the drawing can come
		# whenever it comes.
		var mark := Label.new()
		mark.text = badge.id.substr(0, 1).to_upper()
		mark.custom_minimum_size = Vector2(size, size)
		mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		mark.add_theme_font_size_override("font_size", int(size * 0.5))
		mark.add_theme_color_override("font_color", edge)
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(mark)

	# ---- the words ----
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 2)
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.custom_minimum_size = Vector2(230.0, 0)
	row.add_child(words)

	var title := badge.id.to_upper()
	if up:
		title = "★ " + title
	var heading := MenuSupport.heading(title, 16,
		MenuSupport.COLOUR_ACCENT if up else MenuSupport.COLOUR_TEXT)
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_child(heading)

	if blocked:
		var x := _small("X  ULTIMATE BLOCKED — %s already used this game's Ultimate. The Basic side still works." % EmblemBook.ascended(state), Color(0.95, 0.25, 0.22))
		x.add_theme_font_size_override("font_size", 13)
		words.add_child(x)
	elif up:
		words.add_child(_small(badge.ultimate, MenuSupport.COLOUR_ACCENT))
	elif held:
		words.add_child(_pips(int(bits["have"]), int(bits["need"]), badge))
		words.add_child(_small("Ultimate taken by %s - the Basic side still works." % EmblemBook.ascended(state)
			if not basic_dead else "HELD — %s got there first." % EmblemBook.ascended(state)))
	else:
		words.add_child(_pips(int(bits["have"]), int(bits["need"]), badge))
		words.add_child(_small(badge.condition if badge.condition != ""
			else DialogueGrammar.describe(badge.turns_on)))

	return frame


## ROUND AB: the OTHER side's Emblem - its name, THEIRS, and its Basic side.
## Their race is not kept, so there are no pips.
func _enemy_tile(badge: ClassBook.Emblem) -> Control:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel",
		MenuSupport.styled("panel", "", MenuSupport.COLOUR_PANEL, MenuSupport.COLOUR_DEFEND))
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right"]:
		pad.add_theme_constant_override(side, 10)
	for side in ["margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 7)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(pad)
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 2)
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(words)
	var heading := MenuSupport.heading("THEIRS · " + badge.id.to_upper(), 14, MenuSupport.COLOUR_DEFEND)
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_child(heading)
	words.add_child(_small(badge.basic))
	return frame


## HOW FAR ALONG, as a row of pips — "●●●○○  3 of 5".
##
## A bar would have read as a health bar, which is the one thing it is not.
## Pips count, and counting is what a Condition asks you to do.
func _pips(have: int, need: int, badge: ClassBook.Emblem) -> Control:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 4)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if need <= 0:
		# An Emblem whose Turns On is a flag test rather than a count has
		# nothing to draw pips for, and that is a fair thing to write.
		line.add_child(_small("no counter — it turns over on a condition"))
		return line

	var dots := ""
	for i in need:
		dots += "●" if i < have else "○"
	var pips := Label.new()
	pips.text = dots
	pips.add_theme_font_size_override("font_size", 13)
	pips.add_theme_color_override("font_color",
		MenuSupport.COLOUR_ATTACK if have > 0 else MenuSupport.COLOUR_TEXT_DIM)
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(pips)

	var count := Label.new()
	count.text = "%d of %d" % [have, need]
	count.add_theme_font_size_override("font_size", 12)
	count.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(count)
	return line


func _small(words_text: String, colour: Color = MenuSupport.COLOUR_TEXT_DIM) -> Label:
	var label := Label.new()
	label.text = words_text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(230.0, 0)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", colour)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
