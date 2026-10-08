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
#  The barrel and the bottle are drawn in code for now (placeholders until
#  PixelLab art exists); the player is his own card sprite.
#  Sound: Audio.csv drink_big while he drinks, drink_burp on the burp.
#  Tuning.csv drink_window_seconds stretches or shrinks the whole thing.
# =============================================================

signal finished

const BOX := Vector2(460, 320)
const BEER := Color(0.95, 0.72, 0.18)
const FOAM := Color(0.98, 0.96, 0.88)
const WOOD := Color(0.55, 0.33, 0.16)
const HOOP := Color(0.25, 0.22, 0.2)
const GLASS := Color(0.32, 0.55, 0.25, 0.95)

var card: PlayerData
var kind := "barrel"

var _panel: Panel
var _hero: TextureRect
var _vessel: Control
var _burp: Label
var _speed := 1.0


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

	_vessel = _make_barrel() if kind != "bottle" else _make_bottle()
	_panel.add_child(_vessel)

	_burp = MenuSupport.heading("*BURP!*", 40, MenuSupport.COLOUR_ACCENT)
	_burp.position = Vector2(BOX.x * 0.5 + 20, 40)
	_burp.pivot_offset = Vector2(70, 25)
	_burp.scale = Vector2.ZERO
	_panel.add_child(_burp)

	_run()


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


func _run() -> void:
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
