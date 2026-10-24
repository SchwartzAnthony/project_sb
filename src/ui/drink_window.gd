class_name DrinkWindow
extends CanvasLayer

# =============================================================
#  THE DRINKING WINDOW  (round AN - the tutorial, Anthony 8 Oct)
#
#  "We get an animation window (small like the pre-Play Maker animation
#   window) of them taking a barrel (and their specific player sprite that
#   is tied to their name, so no random sprite) and drinking it as much as
#   possible (but also spilling some on the ground) and then wiping their
#   arm across their face and burping."
#
#  DrinkWindow.play(host, card, "barrel") - or "bottle". Await `finished`.
#  The match stays frozen underneath. Nothing to click; it plays itself.
#  PIXELLAB DRINK (Anthony, 11 Oct): when his pitch sheet has the `drink`
#  rows (PitchAnims.csv, the stein drink drawn in PixelLab on 10 Oct) the
#  window plays THAT - the very same figure and drink as on the pitch,
#  facing south-east - and then burps. Only a look without a pitch drink
#  still gets the barrel/bottle: the drawn bag pictures (assets/icons/
#  kleiner_fass.png, small_bottle.png, 24 Oct), or the old code-drawn
#  placeholder if a picture is missing.
#  Sound: Audio.csv drink_big while he drinks, drink_burp on the burp.
#  Tuning.csv drink_window_seconds stretches or shrinks the whole thing.
#
#  THE NEW LOOK (Anthony, 23 Oct 2026: "the window needs to be in our new
#  art style, the background has a bunch of text that shouldnt be there").
#  data/DrinkWindow.csv style mat: the cream beer mat panel of the inventory,
#  his name on the wooden sign board, the drawn village pitch behind him,
#  his own drawn match figure (facing right) and a drawn keg or bottle that
#  he lifts, gulps, flings over his shoulder, then cheers and burps. The
#  screen behind goes dark enough that the Play Maker's words don't show.
#  A sheet that has its own drink rows (the PixelLab looks) still plays them.
#  style old brings back the dark box and the code-drawn barrel.
# =============================================================

signal finished

const BOX := Vector2(460, 320)
const BEER := Color(0.95, 0.72, 0.18)
const FOAM := Color(0.98, 0.96, 0.88)
const WOOD := Color(0.55, 0.33, 0.16)
const HOOP := Color(0.25, 0.22, 0.2)
const GLASS := Color(0.32, 0.55, 0.25, 0.95)
## The drawn bag pictures the window uses (MenuSupport.icon_texture names).
const VESSEL_ART := {"barrel": "kleiner_fass", "bottle": "small_bottle"}
const VESSEL_SIDE := 120.0

var card: PlayerData
var kind := "barrel"

var _panel: Panel
var _hero: TextureRect
var _vessel: Control
var _burp: Label
var _speed := 1.0
var _pitch: Texture2D       # his pitch sheet, when it has the drink drawn
var _drink := {}            # PitchAnims.csv drink row
var _cell := 72.0
var _box := BOX             # the window's size (DrinkWindow.csv window)
var _sheet: Texture2D       # his drawn match sheet (new look)
var _prop: TextureRect      # the drawn keg or bottle (new look)
var _feet := Vector2.ZERO   # where his feet stand in the window (new look)

const SETTINGS := "res://data/DrinkWindow.csv"
static var _rows := {}


static func play(host: Node, who: PlayerData, what: String = "barrel") -> DrinkWindow:
	var made := DrinkWindow.new()
	made.card = who
	made.kind = what
	host.add_child(made)
	return made


func _ready() -> void:
	layer = 146
	process_mode = Node.PROCESS_MODE_ALWAYS
	var db := CardDatabase.get_db()
	_speed = maxf(0.2, db.tune_float("drink_window_seconds", 4.0) / 4.0) if db != null else 1.0

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	# The match's big announcement ("Theo drinks Kleiner Faß. ATTACK: ...")
	# would sit behind the window in raw rule words (Anthony, 23 Oct: "the
	# background has a bunch of text that shouldnt be there"): off while he
	# drinks. The cards show what the beer did right after.
	var host := get_parent()
	if host != null and "event_announcement" in host:
		var words = host.get("event_announcement")
		if words is CanvasItem:
			(words as CanvasItem).hide()
	if setting("style", "mat").to_lower() == "mat" and ResourceLoader.exists(BeerMatCard.value("frame")):
		_build_mat(root, db)
	else:
		_build_old(root, db)
	_run()


## The old dark box (8 Oct), for DrinkWindow.csv style old.
func _build_old(root: Control, db: CardDatabase) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	_panel = Panel.new()
	_panel.add_theme_stylebox_override("panel",
		MenuSupport.panel_style(MenuSupport.COLOUR_PANEL, MenuSupport.COLOUR_ACCENT))
	_panel.size = BOX
	_panel.clip_contents = true
	var screen := root.get_viewport_rect().size
	_panel.position = (screen - BOX) * 0.5 - Vector2(0, 60)
	root.add_child(_panel)

	# The grass he stands on.
	var ground := ColorRect.new()
	ground.color = Color(0.25, 0.45, 0.2)
	ground.position = Vector2(4, BOX.y - 70)
	ground.size = Vector2(BOX.x - 8, 66)
	_panel.add_child(ground)

	# HIM - his own sprite, the one on his card.
	_hero = TextureRect.new()
	_hero.texture = _body_of(MenuSupport.portrait_for(card, db) if card != null else null)
	_hero.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_hero.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hero.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_hero.size = Vector2(190, 190)
	_hero.position = Vector2(BOX.x * 0.5 - 130, BOX.y - 230)
	_hero.pivot_offset = Vector2(95, 190)
	_panel.add_child(_hero)

	var name_label := MenuSupport.heading(card.player_name if card != null else "", 18)
	name_label.position = Vector2(14, 10)
	_panel.add_child(name_label)

	# The PixelLab drink, when his sheet has it.
	_pitch = PitchSprite.window_sheet(card) if card != null else null
	_drink = PitchSprite.anim("drink")
	_cell = float(PitchSprite.look_of(_pitch)["cell"])
	if _pitch != null and not _drink.is_empty() \
			and _pitch.get_height() >= (int(_drink["row"]) + 8) * _cell:
		_hero.size = Vector2(240, 240)
		_hero.position = Vector2(BOX.x * 0.5 - 120, BOX.y - 270)
		_hero.pivot_offset = Vector2(120, 240)
		_show_drink_frame(0)
	else:
		_pitch = null
		_vessel = _make_drawn(VESSEL_ART.get(kind, VESSEL_ART["barrel"]))
		if _vessel == null:
			_vessel = _make_barrel() if kind != "bottle" else _make_bottle()
		_panel.add_child(_vessel)

	_burp = MenuSupport.heading("*BURP!*", 40, MenuSupport.COLOUR_ACCENT)
	_burp.position = Vector2(BOX.x * 0.5 + 20, 40)
	_burp.pivot_offset = Vector2(70, 25)
	_burp.scale = Vector2.ZERO
	_panel.add_child(_burp)



## A row of data/DrinkWindow.csv.
static func setting(key: String, fallback: String = "") -> String:
	if _rows.is_empty():
		for row in MenuSupport.read_csv(SETTINGS):
			var key_name := MenuSupport.field(row, "Key").strip_edges()
			if key_name != "":
				_rows[key_name] = MenuSupport.field(row, "Value").strip_edges()
	var got := String(_rows.get(key, ""))
	return got if got != "" else fallback


static func _setting_number(key: String, fallback: float) -> float:
	var text := setting(key)
	return float(text) if text.is_valid_float() else fallback


static func _setting_floats(key: String, fallback: Array) -> Array:
	var parts := setting(key).split(",")
	if parts.size() != fallback.size():
		return fallback
	var out: Array = []
	for part in parts:
		out.append(float(part))
	return out


# =============================================================
#  THE NEW LOOK  (DrinkWindow.csv style mat, 23 Oct 2026)
# =============================================================

## The beer mat window: cream panel, the village pitch inside, his name on
## the sign board, him and the keg or bottle.
func _build_mat(root: Control, db: CardDatabase) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, clampf(_setting_number("dim", 0.8), 0.0, 1.0))
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	var wh := _setting_floats("window", [660.0, 500.0])
	_box = Vector2(wh[0], wh[1])
	var edge := int(_setting_number("edge", 60.0))
	var inset := _setting_number("inset", 40.0)
	var window := Control.new()
	window.size = _box
	window.position = (root.get_viewport_rect().size - _box) * 0.5 + Vector2(0, 30)
	window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(window)
	window.add_child(InventoryScreen._mat(_box, edge, 0.9))

	# The picture: a piece of the match's own drawn village, ink round it.
	_panel = Panel.new()
	_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var inset_top := _setting_number("inset_top", inset)
	_panel.position = Vector2(inset, inset_top)
	_panel.size = _box - Vector2(inset * 2.0, inset + inset_top)
	_panel.clip_contents = true
	window.add_child(_panel)
	var view := _panel.size
	var back_path := setting("backdrop")
	var back: TextureRect = null
	if ResourceLoader.exists(back_path):
		var cut := AtlasTexture.new()
		cut.atlas = load(back_path) as Texture2D
		var r := _setting_floats("backdrop_region", [0.0, 0.0, 0.0, 0.0])
		if r[2] > 0.0 and r[3] > 0.0:
			cut.region = Rect2(r[0], r[1], r[2], r[3])
		back = TextureRect.new()
		back.texture = cut
		back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		back.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		back.size = view
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_panel.add_child(back)
	var ink := Color.from_string(BeerMatCard.value("ink", "#19110a"), Color(0.1, 0.07, 0.04))
	var frame := Panel.new()
	var line := StyleBoxFlat.new()
	line.draw_center = false
	line.border_color = ink
	line.set_border_width_all(5)
	frame.add_theme_stylebox_override("panel", line)
	frame.position = _panel.position - Vector2(2, 2)
	frame.size = view + Vector2(4, 4)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	window.add_child(frame)

	# HIM - his own drawn match figure, facing right.
	var tall := _setting_number("hero_height", 330.0)
	_feet = Vector2(view.x * _setting_number("hero_x", 0.36), view.y - _setting_number("feet_from_bottom", 26.0))
	_hero = TextureRect.new()
	_hero.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hero.stretch_mode = TextureRect.STRETCH_SCALE
	_hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_hero)
	_sheet = PitchSprite.window_sheet(card) if card != null else null
	_drink = PitchSprite.anim("drink")
	if _sheet != null:
		var look := PitchSprite.look_of(_sheet)
		_cell = float(look["cell"])
		_hero.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if bool(look["smooth"]) \
			else CanvasItem.TEXTURE_FILTER_NEAREST
		# The drawn figure's feet sit at the bottom of his frame.
		_hero.size = Vector2(tall, tall)
		_hero.position = _feet - Vector2(tall * 0.5, tall)
		if not _drink.is_empty() and _sheet.get_height() >= (int(_drink["row"]) + 8) * _cell:
			# His look has its own drink drawn: play that, as before.
			_pitch = _sheet
			_sheet = null
			_show_drink_frame(0)
		else:
			_show_sheet_frame("idle", 0)
	else:
		_hero.texture = _body_of(MenuSupport.portrait_for(card, db) if card != null else null)
		_hero.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_hero.size = Vector2(tall, tall) * 0.7
		_hero.position = _feet - Vector2(_hero.size.x * 0.5, _hero.size.y)
	_hero.pivot_offset = Vector2(_hero.size.x * 0.5, _hero.size.y)

	# The keg or the bottle, standing on the grass in front of him.
	if _pitch == null:
		_prop = TextureRect.new()
		var bottle := kind == "bottle"
		var prop_tex := load(setting("bottle" if bottle else "keg")) as Texture2D \
			if ResourceLoader.exists(setting("bottle" if bottle else "keg")) else null
		# Trim the empty air round a bag picture so its size is the drawing's.
		if prop_tex != null:
			var used := prop_tex.get_image().get_used_rect()
			if used.has_area() and used.size != Vector2i(prop_tex.get_size()):
				var trimmed := AtlasTexture.new()
				trimmed.atlas = prop_tex
				trimmed.region = Rect2(used)
				prop_tex = trimmed
		_prop.texture = prop_tex
		_prop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_prop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_prop.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		_prop.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var aspect := prop_tex.get_size().aspect() if prop_tex != null else 1.0
		if bottle:
			var h := _setting_number("bottle_height", 150.0)
			_prop.size = Vector2(h * aspect, h)
		else:
			var w := _setting_number("keg_width", 150.0)
			_prop.size = Vector2(w, w / aspect)
		_prop.pivot_offset = _prop.size * 0.5
		# The keg's open end (its drawn face) towards him.
		_prop.flip_h = not bottle
		_prop.position = Vector2(_feet.x + tall * 0.42, _feet.y - _prop.size.y)
		_panel.add_child(_prop)

	_burp = MenuSupport.heading("*BURP!*", int(_setting_number("burp_size", 64.0)), Color("f6ead0"))
	_burp.add_theme_color_override("font_outline_color", ink)
	_burp.add_theme_constant_override("outline_size", 14)
	_burp.position = Vector2(view.x * 0.52, view.y * 0.12)
	_burp.pivot_offset = Vector2(110, 40)
	_burp.scale = Vector2.ZERO
	_burp.rotation = deg_to_rad(-8.0)
	_panel.add_child(_burp)

	# The grass in front of him: the bottom strip of the same picture laid
	# over his feet, so he stands in it up to the ankles (Anthony, 24 Oct).
	var grass := _setting_number("grass_front", 0.0)
	if back != null and grass > 0.0:
		var strip := Control.new()
		strip.clip_contents = true
		strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		strip.position = Vector2(0, view.y - grass)
		strip.size = Vector2(view.x, grass)
		_panel.add_child(strip)
		var front := back.duplicate() as TextureRect
		front.position = Vector2(0, -(view.y - grass))
		strip.add_child(front)
	_panel.move_child(_burp, -1)

	# His name: in ink on the cream panel above the picture (24 Oct: "Don't
	# have the wooden plank be for their names"); `name sign` brings back the
	# wooden board, `name none` leaves it off.
	var who := (card.player_name if card != null else "").to_upper()
	match setting("name", "panel").to_lower():
		"sign":
			var sign := SignHeader.make(who, "res://data/MenuHeaderBoard.csv")
			window.add_child(sign)
			var header_lift := _setting_number("header_lift", 82.0)
			var centre_sign := func() -> void:
				sign.position = Vector2((_box.x - sign.size.x) / 2.0, -header_lift)
			sign.resized.connect(centre_sign)
			centre_sign.call()
		"panel":
			var label := MenuSupport.heading(who, int(_setting_number("name_size", 34.0)), ink)
			label.add_theme_constant_override("outline_size", 0)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.position = Vector2(inset, 6)
			label.size = Vector2(_box.x - inset * 2.0, inset_top - 8)
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			window.add_child(label)


## One frame of his drawn match sheet, facing east (right).
func _show_sheet_frame(anim_name: String, step: int) -> void:
	var row := PitchSprite.anim(anim_name)
	if row.is_empty() or _sheet == null:
		return
	var cut := AtlasTexture.new()
	cut.atlas = _sheet
	cut.region = Rect2((step % maxi(1, int(row["frames"]))) * _cell, int(row["row"]) * _cell, _cell, _cell)
	_hero.texture = cut


## Lift, gulp, fling the empty over his shoulder, cheer and BURP.
func _run_mat() -> void:
	var tall := _hero.size.y
	var m := _setting_floats("mouth", [0.6, 0.27])
	var mouth := _hero.position + Vector2(m[0], m[1]) * tall
	var bottle := kind == "bottle"
	var idle := PitchSprite.anim("idle")
	var idle_frames := maxi(1, int(idle.get("frames", 1)))
	# 1. Up to his mouth, tipped so its open end is at his lips.
	# The bottle tipped neck-first into his mouth; the keg held up in front
	# of his face, the low rim of its open end at his lips.
	var tilt := deg_to_rad(-115.0 if bottle else -30.0)
	var lips := Vector2(0, -_prop.size.y * 0.5) if bottle \
		else Vector2(-_prop.size.x * 0.5, _prop.size.y * 0.25)
	var hold := mouth - lips.rotated(tilt) - _prop.size * 0.5
	var up := create_tween()
	up.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	up.tween_property(_prop, "position", hold, _t(0.45))
	up.parallel().tween_property(_prop, "rotation", tilt, _t(0.45))
	await up.finished
	AudioDirector.fire(get_tree(), "drink_big", {"kind": kind})

	# 2. Head back, gulp gulp gulp, beer down his front and on the grass.
	for gulp in 3:
		_show_sheet_frame("idle", gulp % idle_frames)
		var bob := create_tween()
		bob.tween_property(_hero, "scale", Vector2(1.05, 0.95), _t(0.17))
		bob.parallel().tween_property(_hero, "rotation", deg_to_rad(-5.0), _t(0.17))
		bob.parallel().tween_property(_prop, "rotation", _prop.rotation - deg_to_rad(10.0), _t(0.17))
		bob.tween_property(_hero, "scale", Vector2.ONE, _t(0.17))
		bob.parallel().tween_property(_hero, "rotation", 0.0, _t(0.17))
		bob.parallel().tween_property(_prop, "rotation", _prop.rotation, _t(0.17))
		for drop in 4:
			_spill_mat(mouth + Vector2(randf_range(-4, 18), randf_range(0, 14)))
		await bob.finished

	# 3. The empty goes over his shoulder, spinning, out of the picture.
	var toss := create_tween()
	toss.tween_property(_prop, "position", Vector2(-_prop.size.x * 1.2, -_prop.size.y), _t(0.5)) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	toss.parallel().tween_property(_prop, "rotation", _prop.rotation - TAU, _t(0.5))
	toss.parallel().tween_property(_hero, "rotation", deg_to_rad(-4.0), _t(0.2))
	toss.tween_property(_hero, "rotation", 0.0, _t(0.15))
	await toss.finished

	# 4. He cheers and BURPS.
	AudioDirector.fire(get_tree(), "drink_burp", {"kind": kind})
	var cheer := PitchSprite.anim("cheer")
	var cheer_frames := maxi(1, int(cheer.get("frames", 1)))
	var burp := create_tween()
	burp.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	burp.tween_property(_burp, "scale", Vector2.ONE, _t(0.5))
	burp.parallel().tween_property(_hero, "scale", Vector2(0.95, 1.06), _t(0.15))
	burp.tween_property(_hero, "scale", Vector2.ONE, _t(0.2))
	var wait := _t(1.0 / maxf(1.0, float(cheer.get("fps", 10))))
	var steps := int(ceil(_t(1.4) / wait))
	for step in steps:
		_show_sheet_frame("cheer" if not cheer.is_empty() else "idle", step % cheer_frames)
		await get_tree().create_timer(wait, true, false, true).timeout
	finished.emit()
	queue_free()


## A drop of beer with an ink edge: it falls and leaves a little puddle.
func _spill_mat(from: Vector2) -> void:
	var drop := Drop.new()
	drop.colour = BEER if randf() < 0.7 else FOAM
	drop.size = Vector2(9, 9)
	drop.position = from
	drop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(drop)
	var floor_y := _feet.y - 6.0 + randf_range(0, 14)
	var fall := create_tween()
	fall.tween_property(drop, "position", Vector2(from.x + randf_range(-10, 40), floor_y), _t(randf_range(0.3, 0.5))) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fall.tween_property(drop, "size", Vector2(18, 6), _t(0.1))
	fall.tween_property(drop, "modulate:a", 0.0, _t(0.8))
	fall.tween_callback(drop.queue_free)


class Drop:
	extends Control
	var colour := Color.WHITE

	func _draw() -> void:
		var r := size * 0.5
		var points := PackedVector2Array()
		for k in 16:
			var a := TAU * float(k) / 16.0
			points.append(r + Vector2(cos(a) * r.x, sin(a) * r.y))
		draw_colored_polygon(points, colour)
		points.append(points[0])
		draw_polyline(points, Color(0.1, 0.07, 0.04), 1.5, true)


## His card frame, cut down to the drawn body (the frame is mostly air), so
## he fills the window instead of standing in it like a speck.
func _body_of(face: AtlasTexture) -> Texture2D:
	if face == null:
		return null
	var box := NamePlate.box_of(face)
	var cell := face.region
	var cut := Rect2(cell.position + box.position * cell.size, box.size * cell.size).grow(2.0)
	var out := AtlasTexture.new()
	out.atlas = face.atlas
	out.region = cut.intersection(cell)
	return out


## The drawn barrel or bottle, the same picture as in the bag.
func _make_drawn(art_name: String) -> Control:
	var picture := MenuSupport.icon_texture(art_name)
	if picture == null:
		return null
	var holder := Control.new()
	holder.size = Vector2(VESSEL_SIDE, VESSEL_SIDE)
	holder.pivot_offset = holder.size * 0.5
	var art := TextureRect.new()
	art.texture = picture
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	art.size = holder.size
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(art)
	holder.position = Vector2(BOX.x - VESSEL_SIDE - 40, BOX.y - VESSEL_SIDE - 60)
	return holder


func _make_barrel() -> Control:
	var barrel := Control.new()
	barrel.size = Vector2(70, 84)
	barrel.pivot_offset = Vector2(35, 42)
	var body := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = WOOD
	style.set_corner_radius_all(18)
	style.border_color = HOOP
	style.set_border_width_all(3)
	body.add_theme_stylebox_override("panel", style)
	body.size = barrel.size
	barrel.add_child(body)
	for y in [18.0, 62.0]:
		var hoop := ColorRect.new()
		hoop.color = HOOP
		hoop.position = Vector2(2, y)
		hoop.size = Vector2(66, 5)
		barrel.add_child(hoop)
	var tap := ColorRect.new()
	tap.color = Color(0.75, 0.7, 0.55)
	tap.position = Vector2(-8, 38)
	tap.size = Vector2(10, 8)
	barrel.add_child(tap)
	barrel.position = Vector2(BOX.x - 120, BOX.y - 150)
	return barrel


func _make_bottle() -> Control:
	var bottle := Control.new()
	bottle.size = Vector2(30, 90)
	bottle.pivot_offset = Vector2(15, 45)
	var body := ColorRect.new()
	body.color = GLASS
	body.position = Vector2(0, 30)
	body.size = Vector2(30, 60)
	bottle.add_child(body)
	var neck := ColorRect.new()
	neck.color = GLASS
	neck.position = Vector2(9, 4)
	neck.size = Vector2(12, 28)
	bottle.add_child(neck)
	var label := ColorRect.new()
	label.color = FOAM
	label.position = Vector2(3, 50)
	label.size = Vector2(24, 18)
	bottle.add_child(label)
	bottle.position = Vector2(BOX.x - 110, BOX.y - 160)
	return bottle


func _t(seconds: float) -> float:
	return seconds * _speed


## One frame of the pitch drink, facing south-east (PitchSprite.DIRECTIONS 1).
func _show_drink_frame(step: int) -> void:
	var cut := AtlasTexture.new()
	cut.atlas = _pitch
	var row := int(_drink["row"]) + 1
	cut.region = Rect2(step * _cell, row * _cell, _cell, _cell)
	_hero.texture = cut


func _run() -> void:
	if _pitch != null:
		await _run_pitch()
		return
	if _prop != null:
		await _run_mat()
		return
	var mouth := _hero.position + Vector2(118, 50)
	# 1. He grabs it: the barrel flies up to his mouth and tips.
	var up := create_tween()
	up.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	up.tween_property(_vessel, "position", mouth - Vector2(10, 30), _t(0.45))
	up.parallel().tween_property(_vessel, "rotation", deg_to_rad(-110.0), _t(0.45))
	await up.finished
	AudioDirector.fire(get_tree(), "drink_big", {"kind": kind})

	# 2. He drinks as much as he can - head back, three gulps, beer everywhere.
	for gulp in 3:
		var bob := create_tween()
		bob.tween_property(_hero, "scale", Vector2(1.06, 0.94), _t(0.16))
		bob.parallel().tween_property(_hero, "rotation", deg_to_rad(-6.0), _t(0.16))
		bob.tween_property(_hero, "scale", Vector2.ONE, _t(0.16))
		bob.parallel().tween_property(_hero, "rotation", 0.0, _t(0.16))
		for drop in 4:
			_spill(mouth + Vector2(randf_range(-6, 14), randf_range(0, 10)))
		await bob.finished

	# 3. Down goes the empty.
	var down := create_tween()
	down.tween_property(_vessel, "position", Vector2(_vessel.position.x + 60, BOX.y - 40), _t(0.35))
	down.parallel().tween_property(_vessel, "rotation", deg_to_rad(-200.0), _t(0.35))
	down.tween_property(_vessel, "modulate:a", 0.0, _t(0.2))
	await down.finished

	# 4. The arm across the face.
	var arm := ColorRect.new()
	arm.color = Color(0.85, 0.65, 0.5)
	arm.size = Vector2(60, 12)
	arm.position = mouth + Vector2(30, 0)
	arm.pivot_offset = Vector2(0, 6)
	_panel.add_child(arm)
	var wipe := create_tween()
	wipe.tween_property(arm, "position", mouth - Vector2(70, 4), _t(0.3))
	wipe.parallel().tween_property(_hero, "rotation", deg_to_rad(4.0), _t(0.3))
	wipe.tween_property(arm, "modulate:a", 0.0, _t(0.12))
	wipe.parallel().tween_property(_hero, "rotation", 0.0, _t(0.12))
	await wipe.finished
	arm.queue_free()

	# 5. BURP.
	AudioDirector.fire(get_tree(), "drink_burp", {"kind": kind})
	var burp := create_tween()
	burp.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	burp.tween_property(_burp, "scale", Vector2.ONE, _t(0.5))
	burp.parallel().tween_property(_hero, "scale", Vector2(0.92, 1.1), _t(0.15))
	burp.tween_property(_hero, "scale", Vector2.ONE, _t(0.2))
	await burp.finished
	await get_tree().create_timer(_t(0.7), true, false, true).timeout
	finished.emit()
	queue_free()


## The PixelLab drink: lift, gulp, wipe, toss - frame by frame at the
## PitchAnims.csv FPS (drink_window_seconds stretches it) - then the BURP.
func _run_pitch() -> void:
	AudioDirector.fire(get_tree(), "drink_big", {"kind": kind})
	var frames := int(_drink["frames"])
	var wait := _t(1.0 / maxf(1.0, float(_drink["fps"])))
	for step in frames:
		_show_drink_frame(step)
		await get_tree().create_timer(wait, true, false, true).timeout
	# The last frame has the stein in the air; he burps standing, hands empty
	# (frame 0 is his plain standing drawing).
	_show_drink_frame(0)
	AudioDirector.fire(get_tree(), "drink_burp", {"kind": kind})
	var burp := create_tween()
	burp.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	burp.tween_property(_burp, "scale", Vector2.ONE, _t(0.5))
	burp.parallel().tween_property(_hero, "scale", Vector2(0.95, 1.06), _t(0.15))
	burp.tween_property(_hero, "scale", Vector2.ONE, _t(0.2))
	await burp.finished
	await get_tree().create_timer(_t(0.7), true, false, true).timeout
	finished.emit()
	queue_free()


## A drop of beer: it leaves the barrel, falls, and makes a little puddle.
func _spill(from: Vector2) -> void:
	var drop := ColorRect.new()
	drop.color = BEER if randf() < 0.7 else FOAM
	drop.size = Vector2(6, 6)
	drop.position = from
	_panel.add_child(drop)
	var floor_y := BOX.y - 66 + randf_range(0, 20)
	var fall := create_tween()
	fall.tween_property(drop, "position", Vector2(from.x + randf_range(-20, 30), floor_y), _t(randf_range(0.3, 0.5))) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fall.tween_property(drop, "size", Vector2(12, 3), _t(0.1))
	fall.tween_property(drop, "modulate:a", 0.4, _t(0.6))
