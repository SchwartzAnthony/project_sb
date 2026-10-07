class_name ShopScreen
extends Control

# =============================================================
#  THE TRAVELING BREWER
#
#  A cart, a purse, and a short list of things that are dearer than they
#  ought to be. See shop_book.gd for the files and the reasoning.
#
#  Reached from the Traveling Brewer on the base, or with  goto:brewer .
#
#  ============ WHAT IS ON SCREEN ============
#
#      THE PURSE   one tile per currency in Currencies.csv, with what each
#                  one is paid FOR, because "40 a win in a season match" is
#                  the only thing that makes a price mean anything
#      THE CART    one row per Shop.csv line whose Requires passes. What it
#                  is, what it gives, what it costs, and how many he has
#
#  A sold-out row stays on the list and says SOLD OUT. A thing that vanishes
#  is a thing you think you imagined.
# =============================================================

var db: CardDatabase
var state: GameState

var _purse: HBoxContainer
var _cart: VBoxContainer
var _status: Label
## ROUND AN: true when his picture is behind the shop - the panels then go
## see-through, and the cart leaves room on the right for him.
var _scenery := false
var _keeper_shown := false


func _ready() -> void:
	# THE WINDOW DOES ALL THREE when this screen is opened over the base:
	# the background, the Back button and Escape. See base_window.gd.
	var windowed := MenuSupport.in_a_window(self)
	if not windowed:
		MenuEscape.install(self)
		# A WINDOW SIZES THIS SCREEN ITSELF. Pinning it to the whole viewport
		# from in here would fight the container it has been put in.
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	db = CardDatabase.get_db()
	state = GameState.fetch(get_tree())
	# ROUND AN: his shop behind it and him in it - StoryArt.csv IDs named in
	# Tuning.csv shop_background / shop_keeper. Nothing there yet = as before.
	_scenery = StoryArt.add_backdrop(self, db.tune_text("shop_background", "merchant_shop"),
		db.tune_float("shop_background_shade", 0.45))
	_keeper_shown = _keeper_path() != ""
	_build_chrome()
	_add_keeper()
	_rebuild()
	(func() -> void: Guide.check(self, "shop", state)).call_deferred()


## The Traveling Merchant behind his counter, bottom right: his StoryArt.csv
## face (the Portrait ID in Tuning.csv shop_keeper).
func _keeper_path() -> String:
	var face_id := db.tune_text("shop_keeper", "merchant").strip_edges()
	if face_id == "":
		return ""
	var row := StoryArt.get_db().portrait_for(face_id, "", "", "front")
	var path := String(row.get("image", ""))
	return path if path != "" and ResourceLoader.exists(path) else ""


## How wide a strip on the right the merchant stands in (Tuning.csv).
func _keeper_room() -> float:
	return db.tune_float("shop_keeper_width", 300.0) if _keeper_shown else 0.0


## A panel over his picture: see-through black with a coloured edge, so the
## shop shows through. Without the picture, the usual skin.
func _panel(fill: Color, border: Color) -> StyleBox:
	if not _scenery:
		return MenuSupport.panel_style(fill, border)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, maxf(TextBackdrop.alpha(), 0.55))
	box.border_color = border if border.a > 0.0 else MenuSupport.COLOUR_SLOT_EMPTY
	box.set_border_width_all(2)
	box.set_corner_radius_all(4)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	return box


func _add_keeper() -> void:
	var path := _keeper_path()
	if path == "":
		return
	var face := TextureRect.new()
	face.texture = load(path) as Texture2D
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	face.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.anchor_left = 1.0
	face.anchor_right = 1.0
	face.anchor_top = 1.0
	face.anchor_bottom = 1.0
	# In the strip on the right, standing ABOVE the Back button.
	face.offset_left = -_keeper_room()
	face.offset_right = -20
	face.offset_top = -80 - _keeper_room() * 1.1
	face.offset_bottom = -80
	add_child(face)


func _build_chrome() -> void:
	# NO BACKGROUND OF ITS OWN IN A WINDOW — the window has one, and a second
	# opaque rectangle would paint over the dimmed base behind it.
	# ...and none over his picture either, which is already behind it.
	if not MenuSupport.in_a_window(self) and not _scenery:
		var fill := ColorRect.new()
		fill.color = MenuSupport.COLOUR_BACKGROUND
		fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(fill)

	var title := MenuSupport.heading(
		Loc.text("brewer_title", "THE TRAVELING BREWER"), 32, MenuSupport.COLOUR_ACCENT)
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_left = 36.0
	title.offset_top = 18.0
	title.offset_bottom = 58.0
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# THE WINDOW'S TITLE BAR ALREADY SAYS THIS. Hidden rather than removed,
	# so the layout below keeps the breathing room it was drawn with.
	title.visible = not MenuSupport.in_a_window(self)
	add_child(title)

	var purse_frame := PanelContainer.new()
	purse_frame.set_anchors_preset(Control.PRESET_TOP_WIDE)
	purse_frame.offset_left = 36.0
	purse_frame.offset_right = -36.0
	purse_frame.offset_top = 62.0
	# TALL ENOUGH FOR THE THIRD LINE. At 158 the "40 a win, in a season
	# match" line under each number was clipped off the bottom of the frame —
	# which is the one line that makes a price mean anything, and I only saw
	# it was gone in a screenshot.
	purse_frame.offset_bottom = 182.0
	purse_frame.add_theme_stylebox_override("panel", _panel(
		MenuSupport.COLOUR_PANEL, MenuSupport.COLOUR_ACCENT) if _scenery else MenuSupport.styled(
		"window", "", MenuSupport.COLOUR_PANEL, MenuSupport.COLOUR_ACCENT))
	add_child(purse_frame)

	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right"]:
		pad.add_theme_constant_override(side, 16)
	for side in ["margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 10)
	purse_frame.add_child(pad)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	pad.add_child(column)
	column.add_child(MenuSupport.heading(
		Loc.text("your_purse", "YOUR PURSE"), 16, MenuSupport.COLOUR_ACCENT))

	_purse = HBoxContainer.new()
	_purse.add_theme_constant_override("separation", 34)
	column.add_child(_purse)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 36.0
	scroll.offset_right = -36.0 - _keeper_room()
	scroll.offset_top = 196.0
	scroll.offset_bottom = -74.0
	add_child(scroll)

	_cart = VBoxContainer.new()
	_cart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cart.add_theme_constant_override("separation", 8)
	scroll.add_child(_cart)

	_status = Label.new()
	_status.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_status.offset_left = 36.0
	_status.offset_right = -260.0
	_status.offset_top = -64.0
	_status.offset_bottom = -18.0
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 16)
	_status.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_status)

	var back := MenuSupport.icon_button("◇", Loc.text("back_to_base", "Back to the base"),
		Vector2(200, 44))
	back.add_theme_font_size_override("font_size", 16)
	back.add_theme_stylebox_override("normal",
		MenuSupport.panel_style(MenuSupport.COLOUR_PANEL, MenuSupport.COLOUR_ACCENT))
	back.add_theme_stylebox_override("hover",
		MenuSupport.panel_style(MenuSupport.COLOUR_SLOT_EMPTY, MenuSupport.COLOUR_ACCENT))
	back.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	back.offset_left = -230.0
	back.offset_top = -66.0
	back.offset_right = -30.0
	back.offset_bottom = -22.0
	# THE WINDOW HAS A ✕. Two ways out of one screen is one too many.
	back.visible = not MenuSupport.in_a_window(self)
	# THE WINDOW HAS A ✕. Two ways out of one screen is one too many.
	back.visible = not MenuSupport.in_a_window(self)
	back.pressed.connect(func() -> void:
		state.save_to_disk()
		ScenePaths.go_back(get_tree(), ScenePaths.BASE))
	add_child(back)


func _rebuild() -> void:
	for child in _purse.get_children():
		child.queue_free()
	for child in _cart.get_children():
		child.queue_free()

	for money in ShopBook.currencies():
		_purse.add_child(_purse_tile(money))

	var offered := ShopBook.on_offer(state)
	if offered.is_empty():
		var nothing := Label.new()
		nothing.text = "His cart is empty. Every row of Shop.csv is still locked — check the Requires column."
		nothing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nothing.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
		_cart.add_child(nothing)
		return
	for entry in offered:
		_cart.add_child(_cart_row(entry))


func _purse_tile(money: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)

	var name_label := Label.new()
	name_label.text = String(money["name"])
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	box.add_child(name_label)

	var amount := MenuSupport.heading(
		str(ShopBook.purse(String(money["id"]), state)), 24, MenuSupport.COLOUR_TEXT)
	box.add_child(amount)

	# WHERE IT COMES FROM, under the number. A price means nothing without it.
	var where := "every match" if String(money["mode"]) == "" \
		else "a %s match" % money["mode"]
	var earn := Label.new()
	earn.text = "%d a win · %d a draw · %d a loss, in %s" % [
		int(money["win"]), int(money["draw"]), int(money["loss"]), where]
	earn.add_theme_font_size_override("font_size", 11)
	earn.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	box.add_child(earn)
	return box


func _cart_row(entry: Dictionary) -> Control:
	var money := ShopBook.currency(String(entry["currency"]))
	var left := ShopBook.left_on_the_cart(entry, state)
	var price := int(entry["price"])
	var have := ShopBook.purse(String(entry["currency"]), state)
	var can_pay := have >= price

	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _panel(
		MenuSupport.COLOUR_PANEL,
		MenuSupport.COLOUR_SLOT_EMPTY if left == 0 or not can_pay
		else MenuSupport.COLOUR_ATTACK))

	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right"]:
		pad.add_theme_constant_override(side, 14)
	for side in ["margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 10)
	frame.add_child(pad)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	pad.add_child(row)

	# A PICTURE IF YOU DREW ONE, and nothing at all if you did not. The row
	# reads perfectly without it, which is the rule for every piece of art in
	# this project.
	var art := _find_texture(String(entry["art"]))
	if art != null:
		var picture := TextureRect.new()
		picture.texture = art
		picture.custom_minimum_size = Vector2(64, 64)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(picture)

	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", 2)
	row.add_child(words)

	var name_label := MenuSupport.heading(String(entry["name"]), 18,
		MenuSupport.COLOUR_TEXT if left != 0 else MenuSupport.COLOUR_TEXT_DIM)
	words.add_child(name_label)

	var gives := Label.new()
	gives.text = _what_it_gives(entry)
	gives.add_theme_font_size_override("font_size", 13)
	gives.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	words.add_child(gives)

	var stock_label := Label.new()
	stock_label.text = "SOLD OUT" if left == 0 \
		else ("%d left on the cart" % left if left > 0 else "he has plenty")
	stock_label.add_theme_font_size_override("font_size", 11)
	stock_label.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	words.add_child(stock_label)

	var button := Button.new()
	button.custom_minimum_size = Vector2(230.0, 44.0)
	button.text = "%d %s" % [price, money["name"] if not money.is_empty() else entry["currency"]]
	button.disabled = left == 0 or not can_pay
	var tint := MenuSupport.COLOUR_ATTACK if not button.disabled else MenuSupport.COLOUR_TEXT_DIM
	button.add_theme_stylebox_override("normal",
		MenuSupport.panel_style(MenuSupport.COLOUR_PANEL, tint))
	button.add_theme_stylebox_override("hover",
		MenuSupport.panel_style(MenuSupport.COLOUR_SLOT_EMPTY, tint))
	button.add_theme_stylebox_override("disabled",
		MenuSupport.panel_style(MenuSupport.COLOUR_BACKGROUND, tint))
	button.add_theme_stylebox_override("focus", MenuSupport.focus_style())
	button.add_theme_color_override("font_color", tint)
	button.add_theme_color_override("font_disabled_color", tint)
	button.pressed.connect(_buy.bind(String(entry["id"])))
	row.add_child(button)
	return frame


## "6 Hops" or "The Fire Brew recipe", in the words the player knows.
func _what_it_gives(entry: Dictionary) -> String:
	var sells := String(entry["sells"])
	var many := int(entry["how_many"])
	var colon := sells.find(":")
	var kind := sells.substr(0, colon).strip_edges().to_lower() if colon > 0 else ""
	var rest := sells.substr(colon + 1).strip_edges() if colon > 0 else sells
	match kind:
		"res", "resource", "material":
			var res := BreweryBook.resource(rest)
			var name_text := String(res["name"]) if not res.is_empty() else rest
			return "%d %s" % [many, name_text]
		"brew", "recipe":
			var brews := BrewDB.get_db()
			var found := brews.find(rest) if brews != null else {}
			return "The %s recipe — the Pub can pour it from then on" % (
				String(found["name"]) if not found.is_empty() else rest)
		_:
			return sells


func _buy(row_id: String) -> void:
	var result := ShopBook.buy(row_id, state)
	_status.text = String(result["why"])
	_status.add_theme_color_override("font_color",
		MenuSupport.COLOUR_TEXT if bool(result["ok"]) else Color(1.0, 0.72, 0.4))
	if bool(result["ok"]):
		state.save_to_disk()
	_rebuild()


func _find_texture(file_name: String) -> Texture2D:
	if file_name.strip_edges() == "":
		return null
	# TYPED, because a bare Array literal is an Array[Variant] and `folder`
	# comes out untyped — which makes `folder + file_name` untyped too, and
	# the compiler refuses to infer `path` from it.
	var folders: Array[String] = ["res://assets/shop/", "res://assets/icons/", "res://assets/"]
	for folder in folders:
		var path := folder + file_name
		if ResourceLoader.exists(path):
			return load(path) as Texture2D
	return null
