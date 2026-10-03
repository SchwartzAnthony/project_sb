class_name CoinToss
extends CanvasLayer

# =============================================================
#  A COIN IN THE AIR  (round AB)
#
#  Your answer to Q034: Manfred's coin flip is SHOWN, not just announced. A
#  coin spins in the middle of the screen, lands, and says which way the foul
#  goes. Drawn, not an image, so it is never missing.
#
#      await CoinToss.show_it(self, heads, "HEADS - the foul goes to THEM")
#
#  `coin_toss_seconds` in Tuning.csv; 0 skips the animation.
# =============================================================

const SIZE := 120.0


static func show_it(on_node: Node, heads: bool, caption: String) -> void:
	var db := CardDatabase.get_db()
	var seconds := 1.6
	if db != null:
		seconds = db.tune_float("coin_toss_seconds", 1.6)
	if seconds <= 0.0:
		return
	var made := CoinToss.new()
	made.name = "CoinToss"
	made.layer = 165
	on_node.add_child(made)
	await made._run(heads, caption, seconds)
	made.queue_free()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _run(heads: bool, caption: String, seconds: float) -> void:
	var screen := get_viewport().get_visible_rect().size
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.position = Vector2(screen.x * 0.5, screen.y * 0.42)
	add_child(holder)

	var coin := Panel.new()
	var face := StyleBoxFlat.new()
	face.bg_color = Color(0.86, 0.68, 0.22)
	face.border_color = Color(0.55, 0.40, 0.10)
	face.set_border_width_all(6)
	face.set_corner_radius_all(int(SIZE * 0.5))
	coin.add_theme_stylebox_override("panel", face)
	coin.size = Vector2(SIZE, SIZE)
	coin.position = Vector2(-SIZE * 0.5, -SIZE * 0.5)
	coin.pivot_offset = Vector2(SIZE * 0.5, SIZE * 0.5)
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(coin)

	var mark := Label.new()
	mark.text = "?"
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mark.size = Vector2(SIZE, SIZE)
	mark.add_theme_font_size_override("font_size", 44)
	mark.add_theme_color_override("font_color", Color(0.30, 0.20, 0.05))
	coin.add_child(mark)

	var words := Label.new()
	words.text = "COIN FLIP"
	words.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	words.size = Vector2(700.0, 40.0)
	words.position = Vector2(-350.0, SIZE * 0.5 + 18.0)
	words.add_theme_font_size_override("font_size", 26)
	words.add_theme_color_override("font_color", Color(1, 1, 1))
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0, 0, 0, 0.6)
	back.set_corner_radius_all(6)
	words.add_theme_stylebox_override("normal", back)
	holder.add_child(words)

	# The spin: the coin is squashed flat and back, faster and faster.
	var spin := create_tween()
	spin.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	var turns := 6
	var each := seconds * 0.6 / float(turns * 2)
	for i in turns:
		spin.tween_property(coin, "scale:x", 0.05, each)
		spin.tween_property(coin, "scale:x", 1.0, each)
	await spin.finished
	mark.text = "H" if heads else "T"
	words.text = caption
	await get_tree().create_timer(seconds * 0.4, true, false, true).timeout
