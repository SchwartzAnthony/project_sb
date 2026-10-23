class_name BeerMatCard
extends RefCounted

# =============================================================
#  THE BEER MAT CARD  (Anthony, 23 Oct 2026)
#
#  "Yes place these into the game please, remember the card frame as this
#  will come up next again." Every player card is a worn Bavarian beer mat:
#  the player runs in the window exactly as he runs on the pitch (his own
#  pitch sheet, looping), his name is in the centre panel, the number sits in
#  the bottle cap, a small window on top shows his Tier and the wooden plank
#  is the ITEMS button in the match (PlayerCardUI).
#
#  All of it is in data/CardFace.csv: the frame, where the
#  window, plank, cap and panel are (fractions of the frame), how big the
#  runner is and what the cap shows. enabled = false brings the old card back.
#  MenuSupport.card_face() asks here first, so the match, the team builder
#  and the Adventure fight all change together.
# =============================================================

const PATH := "res://data/CardFace.csv"

static var _rows: Dictionary = {}
static var _loaded := false


static func value(key: String, fallback: String = "") -> String:
	if not _loaded:
		_loaded = true
		for row in MenuSupport.read_csv(PATH):
			var key_name := MenuSupport.field(row, "Key").strip_edges()
			if key_name != "":
				_rows[key_name] = MenuSupport.field(row, "Value").strip_edges()
	return String(_rows.get(key, fallback))


static func number(key: String, fallback: float) -> float:
	var text := value(key)
	return float(text) if text.is_valid_float() else fallback


static func enabled() -> bool:
	return value("enabled", "false").to_lower() == "true" and ResourceLoader.exists(value("frame"))


## A fraction rectangle of the frame ("x,y,w,h") laid onto the frame's box.
static func _area(key: String, frame: Rect2) -> Rect2:
	var parts := value(key).split(",")
	if parts.size() != 4:
		return frame
	return Rect2(frame.position + Vector2(float(parts[0]), float(parts[1])) * frame.size,
		Vector2(float(parts[2]), float(parts[3])) * frame.size)


## Fills `button` (already `box` big) with the beer mat card for `card`.
static func dress(button: Button, card: PlayerData, db: CardDatabase, box: Vector2,
		extra: String) -> void:
	var clear := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, clear)
	var frame_tex := load(value("frame")) as Texture2D
	# The frame keeps its own shape, centred in the card's box.
	var aspect := frame_tex.get_size().x / frame_tex.get_size().y
	var size := Vector2(box.y * aspect, box.y)
	if size.x > box.x:
		size = Vector2(box.x, box.x / aspect)
	var frame := Rect2((box - size) / 2.0, size)

	var art := TextureRect.new()
	art.texture = frame_tex
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.position = frame.position
	art.size = frame.size
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(art)
	# Hover and press light the whole mat up a little, like the old card did.
	button.mouse_entered.connect(func() -> void: art.modulate = Color(1.12, 1.1, 1.0))
	button.mouse_exited.connect(func() -> void: art.modulate = Color.WHITE)

	_add_runner(button, card, db, frame)

	var ink := Color.from_string(value("ink", "#19110a"), Color(0.1, 0.07, 0.04))
	# 23 Oct (Anthony): the name sits alone in the centre panel (no
	# signature any more); the plank below is the ITEMS button (PlayerCardUI
	# puts it there, see plank_rect).
	var panel := _area("sign", frame)
	var name_area := Rect2(panel.position + panel.size * Vector2(0.08, 0.2),
		panel.size * Vector2(0.84, 0.6))
	_add_text(button, card.player_name.to_upper(), name_area, ink, 0.75)
	button.set_meta("plank_rect", _area("plank", frame))
	var shown := card.card_number if value("cap_number", "power") == "card_number" \
		else card.get_attack_power()
	_add_text(button, str(shown), _area("cap", frame), ink, 0.9)
	if value("tier_window", "true").to_lower() == "true":
		_add_tier_window(button, card, frame, frame_tex, ink)

	var window := _area("window", frame)
	if extra != "":
		_add_tag(button, extra, Vector2(window.position.x + 4, window.end.y - frame.size.y * 0.075),
			frame.size.y * 0.045)

	if card.is_star():
		var mark := clampf(frame.size.x * 0.17, 18.0, 44.0)
		var badge := StarBadge.make_marker(false, mark)
		button.add_child(badge)
		badge.size = Vector2(mark, mark)
		# A star drawn as a letter can be bigger than asked; keep it inside.
		var real := badge.get_combined_minimum_size().max(Vector2(mark, mark))
		badge.position = Vector2(window.end.x - real.x - 3.0, window.position.y + 3.0)


## The player running in the window: his own pitch sheet, the run facing
## west, looping at his pitch speed. No pitch sheet = his old portrait.
static func _add_runner(button: Button, card: PlayerData, db: CardDatabase, frame: Rect2) -> void:
	var window := _area("window", frame)
	var clip := Control.new()
	clip.clip_contents = true
	clip.position = window.position
	clip.size = window.size
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(clip)

	var tall := frame.size.y * number("runner_height", 0.4)
	var feet := frame.position.y + frame.size.y * number("runner_feet", 0.566) - window.position.y
	var sheet := PitchSprite.window_sheet(card)
	var run := PitchSprite.anim("run")
	if sheet == null or run.is_empty():
		var still := MenuSupport.portrait_rect(card, db, Vector2(tall, tall))
		still.mouse_filter = Control.MOUSE_FILTER_IGNORE
		still.position = Vector2((window.size.x - tall) / 2.0, feet - tall)
		still.size = Vector2(tall, tall)
		clip.add_child(still)
		return
	var look := PitchSprite.look_of(sheet)
	var cell := float(look.get("cell", 72.0))
	var runner := CardRunner.new()
	runner.setup(sheet, cell, int(run["row"]) + PitchSprite.DIRECTIONS.find("west"),
		int(run["frames"]), float(run["fps"]) * number("runner_speed", 1.0))
	# The figure stands on the cell's feet line (PitchSheets.csv Lift is how
	# far above the cell's bottom that is, in sheet pixels at its own scale).
	var lift := float(look.get("lift", 0.0))
	var scale := tall / cell * 1.25
	runner.size = Vector2(cell, cell) * scale
	runner.position = Vector2((window.size.x - runner.size.x) / 2.0,
		feet - runner.size.y + (lift / cell) * runner.size.y * 0.25)
	runner.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if bool(look.get("smooth", false)) \
		else CanvasItem.TEXTURE_FILTER_NEAREST
	clip.add_child(runner)


## The small window at the top centre with the Tier: a piece of the centre
## panel's own picture (cream, blue and red edge), stretched like a sign.
static func _add_tier_window(button: Button, card: PlayerData, frame: Rect2,
		frame_tex: Texture2D, ink: Color) -> void:
	var spot := _area("tier_window_spot", frame)
	var patch := NinePatchRect.new()
	patch.texture = frame_tex
	var full := frame_tex.get_size()
	var parts := value("sign").split(",")
	if parts.size() == 4:
		patch.region_rect = Rect2(Vector2(float(parts[0]), float(parts[1])) * full,
			Vector2(float(parts[2]), float(parts[3])) * full)
	var edge := int(number("tier_window_edge", 34.0))
	patch.patch_margin_left = edge
	patch.patch_margin_right = edge
	patch.patch_margin_top = edge
	patch.patch_margin_bottom = edge
	patch.position = spot.position
	patch.size = spot.size
	patch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The picture's edge is drawn at the panel's own size; shrink the whole
	# window so the edge keeps its thickness on a small card.
	var shrink := clampf(spot.size.y / (patch.region_rect.size.y * 0.5), 0.05, 1.0)
	patch.size = spot.size / shrink
	patch.scale = Vector2(shrink, shrink)
	button.add_child(patch)
	var words := value("tier_text", "TIER {tier}").replace("{tier}", card.get_tier_clean())
	_add_text(button, words, Rect2(spot.position + spot.size * Vector2(0.18, 0.2),
		spot.size * Vector2(0.64, 0.6)), ink, 0.85)


## Writes `text` in the card's ink, centred in `area` of `button`.
static func write(button: Button, text: String, area: Rect2, ink: Color) -> void:
	_add_text(button, text, area, ink)


static func _add_text(button: Button, text: String, area: Rect2, ink: Color,
		fill: float = 0.66) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", ink)
	# Plain ink on cardboard: no menu outline or shadow behind it.
	label.add_theme_constant_override("outline_size", 0)
	label.add_theme_constant_override("shadow_outline_size", 0)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	label.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Centred on the card, as big as fits: the height of the plank or cap,
	# smaller for a long name.
	var font := label.get_theme_font("font")
	var font_size := maxi(6, int(area.size.y * fill))
	if font != null:
		while font_size > 6 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > area.size.x * 0.9:
			font_size -= 1
	label.add_theme_font_size_override("font_size", font_size)
	# Centre the label on the middle of the area. A label is never shorter
	# than its font's line, so a tall font in a thin plank would otherwise
	# grow downwards and sit low. The comic font's letters also sit a hair low
	# and left in their line (measured: 4% of the font size), so nudge them.
	var line := font.get_height(font_size) if font != null else float(font_size)
	var tall := maxf(area.size.y, line)
	var nudge := Vector2(number("text_nudge_x", 0.04), number("text_nudge_y", -0.04)) * float(font_size)
	label.size = Vector2(area.size.x, tall)
	label.position = area.get_center() - label.size / 2.0 + nudge
	button.add_child(label)


static func _add_tag(button: Button, text: String, where: Vector2, height: float) -> void:
	var label := Label.new()
	label.text = " %s " % text
	label.add_theme_font_size_override("font_size", maxi(6, int(height * 0.8)))
	label.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT)
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color(0, 0, 0, 0.6)
	plate.set_corner_radius_all(3)
	label.add_theme_stylebox_override("normal", plate)
	label.position = where
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(label)
