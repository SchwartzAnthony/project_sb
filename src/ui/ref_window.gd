class_name RefWindow
extends CanvasLayer

# =============================================================
#  THE REFEREE, WHEN HE HAS SOMETHING TO SAY
#
#  ============ WHAT YOU ASKED FOR ============
#
#  "So I also need a ref on the side (can be a UI element where an image is
#   in) that will pop up when a foul happens."
#
#  So he slides in from the left, holds up the card, says his line, and goes
#  again. Three things in one window and all three are data:
#
#      his picture       Referee.csv `Portrait` -> assets/portraits/
#      the card          drawn, not an image. A yellow rectangle IS a yellow
#                        card and will never be missing
#      his line          Referee.csv `Says Yellow` / `Says Red` / …
#
#  ============ WHY HE SLIDES AND DOES NOT JUST APPEAR ============
#
#  Because a referee appearing instantly reads as a bug and a referee walking
#  on reads as a referee. It is about a fifth of a second of movement and it
#  is the difference between a UI element and a man. The timing is
#  `ref_window_seconds` in Tuning.csv, and 0 turns the whole window off and
#  leaves the match reporting it in the log.
#
#  ============ NO PICTURE IS NOT A GAP ============
#
#  Until `ref_default.png` is drawn he is a dark panel with a whistle glyph
#  on it. The window works from the first minute, and the drawing can come
#  whenever it comes — the art order for it is in data/ArtOrders.csv.
# =============================================================

const SLIDE := 0.18          ## seconds he takes to walk on
const BOX := Vector2(360.0, 128.0)

var _frame: PanelContainer = null


## Show him. `verdict` is "yellow", "red", "free kick" or "" (he looked away).
## Returns when the window has gone again, so a caller may await it.
static func show_it(on_node: Node, db: CardDatabase, verdict: String,
		who_fouled: String, side_is_enemy: bool) -> void:
	var seconds := 2.2
	if db != null:
		seconds = db.tune_float("ref_window_seconds", 2.2)
	if seconds <= 0.0:
		return
	# HE DOES NOT POP UP FOR A FOUL HE DID NOT SEE. That is the whole point:
	# nothing happens, and the only sign is the bar creeping up.
	# `ref_shows_uncalled` TRUE is a debugging setting — see Tuning.csv.
	if verdict == "" and (db == null or not db.tune_bool("ref_shows_uncalled", false)):
		return

	var made := RefWindow.new()
	made.name = "RefWindow"
	made.layer = 150
	on_node.add_child(made)
	await made._run(db, verdict, who_fouled, side_is_enemy, seconds)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _run(db: CardDatabase, verdict: String, who_fouled: String,
		side_is_enemy: bool, seconds: float) -> void:
	var ref := Referee.on_duty(db)

	_frame = PanelContainer.new()
	_frame.custom_minimum_size = BOX
	_frame.add_theme_stylebox_override("panel", MenuSupport.styled(
		"window", "", MenuSupport.COLOUR_BACKGROUND, _edge(verdict)))
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)

	# ---- where he stands ----
	var screen := get_viewport().get_visible_rect().size
	var home := Vector2(26.0, screen.y * 0.5 - BOX.y * 0.5)
	_frame.position = home - Vector2(BOX.x + 40.0, 0.0)   # off the left edge

	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right"]:
		pad.add_theme_constant_override(side, 12)
	for side in ["margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 10)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(pad)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(row)

	row.add_child(_portrait(String(ref["portrait"])))

	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 4)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(words)

	var heading := MenuSupport.heading(_title(verdict), 20, _edge(verdict))
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_child(heading)

	var line := Referee.says(verdict, db)
	if line != "":
		words.add_child(_quiet(line, MenuSupport.COLOUR_TEXT))
	if who_fouled != "":
		words.add_child(_quiet("%s  ·  %s" % [
			who_fouled, "them" if side_is_enemy else "you"], MenuSupport.COLOUR_TEXT_DIM))
	words.add_child(_quiet(String(ref["name"]), MenuSupport.COLOUR_TEXT_DIM))

	if verdict == "yellow" or verdict == "red":
		words.add_child(_the_card(verdict))

	# ---- on, hold, off ----
	await _slide(_frame.position, home, SLIDE)
	await get_tree().create_timer(maxf(0.2, seconds - SLIDE * 2.0),
		true, false, true).timeout
	await _slide(home, home - Vector2(BOX.x + 40.0, 0.0), SLIDE)
	queue_free()


func _slide(from: Vector2, to: Vector2, seconds: float) -> void:
	var clock := 0.0
	while clock < seconds:
		# IGNORING TIME SCALE ON PURPOSE. At 8x a referee who walks on in
		# real time would be a flicker, and the one moment the player has to
		# read is this one.
		var step := get_process_delta_time()
		clock += step
		var how_far := clampf(clock / seconds, 0.0, 1.0)
		# Ease out: quick off the mark, settling at the end. A linear slide
		# reads as a sliding panel; this reads as somebody stopping.
		_frame.position = from.lerp(to, 1.0 - pow(1.0 - how_far, 3.0))
		await get_tree().process_frame


func _title(verdict: String) -> String:
	match verdict:
		"yellow": return "YELLOW CARD"
		"red": return "RED CARD"
		"free kick": return "FREE KICK"
		_: return "PLAY ON"


func _edge(verdict: String) -> Color:
	match verdict:
		"yellow": return Color(0.95, 0.80, 0.18)
		"red": return Color(0.80, 0.16, 0.16)
		"free kick": return MenuSupport.COLOUR_ACCENT
		_: return MenuSupport.COLOUR_TEXT_DIM


## The card itself, DRAWN rather than loaded. A yellow rectangle is a yellow
## card in every country on earth and it can never be a missing file.
func _the_card(verdict: String) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0, 26.0)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var card := ColorRect.new()
	card.color = _edge(verdict)
	card.custom_minimum_size = Vector2(17.0, 24.0)
	card.size = card.custom_minimum_size
	card.position = Vector2(0.0, 1.0)
	card.rotation = deg_to_rad(-7.0)   # held up, not laid flat
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(card)
	return holder


func _portrait(file_name: String) -> Control:
	var art := MenuSupport.icon_texture(file_name)
	if art == null:
		art = _from_portraits(file_name)
	if art != null:
		var picture := TextureRect.new()
		picture.texture = art
		picture.custom_minimum_size = Vector2(96.0, 96.0)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return picture

	# NO PICTURE YET: a whistle, in a box. It reads as a referee and it is
	# never a missing file.
	var stand_in := PanelContainer.new()
	stand_in.custom_minimum_size = Vector2(96.0, 96.0)
	stand_in.add_theme_stylebox_override("panel", MenuSupport.panel_style(
		MenuSupport.COLOUR_PANEL, MenuSupport.COLOUR_TEXT_DIM))
	stand_in.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glyph := Label.new()
	glyph.text = "▰"
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.add_theme_font_size_override("font_size", 44)
	glyph.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stand_in.add_child(glyph)
	return stand_in


func _from_portraits(file_name: String) -> Texture2D:
	var clean := file_name.strip_edges()
	if clean == "":
		return null
	# ============ THE TYPED-ARRAY RULE, AGAIN ============
	#
	# `for folder in ["a", "b"]` iterates an UNTYPED array, so `folder` comes
	# out untyped, so `var path := folder + clean` cannot be inferred and the
	# file will not compile. Declaring the list as Array[String] is the whole
	# fix. This has now cost five rounds in five different files — if you ever
	# write a loop over a bare [...] literal, type it.
	var folders: Array[String] = [
		"res://assets/portraits/", "res://assets/icons/", "res://assets/"]
	var tails: Array[String] = [".png", ".webp", ".jpg"]
	for folder in folders:
		for tail in tails:
			var path := folder + clean + tail
			if ResourceLoader.exists(path):
				return load(path) as Texture2D
	return null


func _quiet(text: String, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", colour)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
