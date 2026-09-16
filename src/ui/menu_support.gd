class_name MenuSupport
extends RefCounted

# =============================================================
#  MENU SUPPORT — shared helpers for every menu screen
#
#  Two jobs:
#    1. Read a menu CSV (MenuConfig.csv, ClassInfo.csv, Collection.csv)
#       with the SAME forgiving rules as the game's data CSVs: column order
#       does not matter, capitals/spaces/underscores are ignored, extra
#       columns are skipped, a missing file is not an error.
#    2. Turn a 12 x 39 spritesheet into a single portrait frame, so cards
#       and slots can show a face instead of the whole sheet.
#
#  Nothing in here ever crashes on missing data — it returns empty and the
#  screen falls back to text or a coloured block.
# =============================================================


# -------------------------------------------------------------
#  CSV READING
# -------------------------------------------------------------

## Read a CSV into an Array of Dictionaries, keyed by NORMALISED header
## ("Display Name", "display_name" and "DISPLAYNAME" all become "displayname").
## Use `field()` below to read a value so you never have to normalise by hand.
## Returns an empty array if the file is missing — callers fall back to defaults.
##
## The return type is spelled Array[Dictionary] rather than plain Array so that
## every `for row in read_csv(...)` loop gets a properly typed row. Without it
## each row is a Variant and Godot warns on every line that touches one.
static func read_csv(path: String) -> Array[Dictionary]:
	if not FileAccess.file_exists(path):
		return []

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("[menu] Could not open %s" % path)
		return []

	var content := file.get_as_text()
	file.close()

	var rows := CardDatabase.parse_csv(content)
	if rows.size() < 2:
		return []

	# First non-empty line is the header.
	var header: PackedStringArray = rows[0]
	var keys: Array[String] = []
	for h in header:
		keys.append(normalise(String(h)))

	var out: Array[Dictionary] = []
	for i in range(1, rows.size()):
		var row: PackedStringArray = rows[i]
		if row.is_empty():
			continue
		# Skip blank lines and #comment lines.
		var first := String(row[0]).strip_edges()
		if first == "" and row.size() <= 1:
			continue
		if first.begins_with("#"):
			continue

		var entry: Dictionary = {}
		for c in range(keys.size()):
			var value := ""
			if c < row.size():
				value = String(row[c]).strip_edges()
			entry[keys[c]] = value
		out.append(entry)

	return out


## Read one column out of a row returned by read_csv(). Column name is given
## the way a human would write it — "Display Name" — and matched loosely.
static func field(row: Dictionary, column: String, fallback: String = "") -> String:
	var key := normalise(column)
	if row.has(key):
		var value := String(row[key])
		if value != "":
			return value
	return fallback


static func field_float(row: Dictionary, column: String, fallback: float) -> float:
	var text := field(row, column, "")
	if text.is_valid_float():
		return text.to_float()
	return fallback


static func normalise(text: String) -> String:
	return text.strip_edges().to_lower().replace(" ", "").replace("_", "").replace("-", "")


# -------------------------------------------------------------
#  PORTRAITS
# -------------------------------------------------------------

## Cut a single frame out of a card's spritesheet so it can be shown as a
## portrait. Uses the sheet grid from Animations.csv when there is one, and
## the 12 x 39 default otherwise. Returns null when the card has no art —
## callers draw a coloured block instead.
static func portrait_for(card: PlayerData, db: CardDatabase, frame_column: int = 0, frame_row: int = 0) -> AtlasTexture:
	if card == null or card.artwork == null:
		return null

	var columns := AnimSpec.DEFAULT_COLUMNS
	var rows := AnimSpec.DEFAULT_ROWS

	# An `idle` row in Animations.csv tells us the real grid and which frame
	# is the resting pose, so portraits follow the artist's own sheet.
	var spec: AnimSpec = null
	if db != null:
		spec = db.get_anim("idle", card.unit_type)
	if spec != null:
		columns = spec.sheet_columns
		rows = spec.sheet_rows
		if frame_column == 0 and frame_row == 0:
			frame_column = spec.first_frame
			frame_row = spec.row

	if columns < 1 or rows < 1:
		return null

	var sheet_size := card.artwork.get_size()
	var cell := Vector2(sheet_size.x / float(columns), sheet_size.y / float(rows))
	if cell.x < 1.0 or cell.y < 1.0:
		return null

	var atlas := AtlasTexture.new()
	atlas.atlas = card.artwork
	atlas.region = Rect2(
		clampf(frame_column, 0, columns - 1) * cell.x,
		clampf(frame_row, 0, rows - 1) * cell.y,
		cell.x, cell.y)
	atlas.filter_clip = true
	return atlas


## A TextureRect showing the card's portrait, sized to `box` and kept crisp
## (nearest-neighbour, aspect preserved). Falls back to a tinted block that
## still reads as "a card is here" when the art is missing.
static func portrait_rect(card: PlayerData, db: CardDatabase, box: Vector2) -> Control:
	var art := portrait_for(card, db)
	if art == null:
		var block := ColorRect.new()
		block.custom_minimum_size = box
		block.color = colour_for_tier(card.get_tier_clean() if card != null else "")
		return block

	var rect := TextureRect.new()
	rect.texture = art
	rect.custom_minimum_size = box
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return rect


# -------------------------------------------------------------
#  A BUTTON IN TWO PARTS: AN ICON AND A LABEL
#
#  One button, one click, but the icon sits in its own square on the left
#  with a hairline between it and the words. That is what makes a row of
#  them read as a toolbar rather than a row of text.
#
#  The icon is either:
#    * an image name  — `unlocks`, found in assets/icons/ the usual way
#    * or a short bit of text — "★", "+", "ESC". Anything one or two
#      characters wide works, and it costs nothing to change later.
#
#  Give it art and the text is replaced. Nothing else changes, which is the
#  same deal the keeper and the team badge offer.
# -------------------------------------------------------------

static func icon_button(icon: String, label: String,
		size: Vector2 = Vector2(180, 48)) -> Button:
	var button := Button.new()
	button.custom_minimum_size = size
	# FOCUS_ALL, NOT FOCUS_NONE. A button that cannot take focus cannot be
	# reached with a stick or the arrow keys, and that is the whole of
	# controller navigation — see controller_focus.gd. The focus box below is
	# drawn in the accent colour so it reads as "you are here" rather than as
	# Godot's default dotted rectangle.
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_stylebox_override("normal", panel_style(COLOUR_PANEL, COLOUR_TEXT_DIM))
	button.add_theme_stylebox_override("hover", panel_style(COLOUR_SLOT_EMPTY, COLOUR_ACCENT))
	button.add_theme_stylebox_override("pressed", panel_style(COLOUR_SLOT_EMPTY, COLOUR_ACCENT))
	button.add_theme_stylebox_override("disabled", panel_style(COLOUR_LOCKED, COLOUR_TEXT_DIM))
	button.add_theme_stylebox_override("focus", focus_style())

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(row)

	# --- the icon half ---
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(size.y - 6.0, 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_stylebox_override("panel", _half_style())
	row.add_child(box)

	# `icon` may be written as   art_name|glyph
	#
	# The art is used the moment you have drawn it, and the glyph stands in
	# until you do. So
	#     MenuSupport.icon_button("play|▶", "Play a match")
	# shows res://assets/icons/play.png once that file exists and a ▶ before
	# then — and nothing in the project changes on the day you draw it.
	var art_name := icon
	var glyph_text := icon
	var bar := icon.find("|")
	if bar >= 0:
		art_name = icon.substr(0, bar).strip_edges()
		glyph_text = icon.substr(bar + 1).strip_edges()

	var art := icon_texture(art_name)
	if art != null:
		var rect := TextureRect.new()
		rect.texture = art
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(rect)
	else:
		var glyph := Label.new()
		glyph.text = glyph_text
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		glyph.add_theme_font_size_override("font_size", int(size.y * 0.42))
		glyph.add_theme_color_override("font_color", COLOUR_ACCENT)
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(glyph)

	# --- the words half ---
	var text := Label.new()
	text.text = label
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.clip_text = true
	text.add_theme_font_size_override("font_size", 15)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)

	return button


## The faint panel behind an icon half, with a hairline on its right edge.
static func _half_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOUR_SLOT_EMPTY
	style.border_width_right = 1
	style.border_color = COLOUR_TEXT_DIM
	style.corner_radius_top_left = 5
	style.corner_radius_bottom_left = 5
	return style


# -------------------------------------------------------------
#  ONE CARD FACE, USED ON EVERY SCREEN
#
#  The team builder, the match draft and the Adventure fight were each
#  drawing their own version of a player, so the same card looked like
#  three different things depending on where you met it.
#
#  This is the one face. Portrait on top, name under it, tier and power at
#  the bottom, tinted by tier. Change it here and all three change together.
#
#  `extra` is a second line at the bottom — Adventure puts stamina there.
#  Everything else passes "".
# -------------------------------------------------------------

static func card_face(card: PlayerData, db: CardDatabase, box: Vector2,
		extra: String = "") -> Button:
	var button := Button.new()
	button.custom_minimum_size = box
	button.focus_mode = Control.FOCUS_NONE
	button.clip_contents = true

	var tint := colour_for_tier(card.get_tier_clean() if card != null else "")
	button.add_theme_stylebox_override("normal", panel_style(COLOUR_PANEL, tint))
	button.add_theme_stylebox_override("hover", panel_style(COLOUR_SLOT_EMPTY, tint))
	button.add_theme_stylebox_override("pressed",
		panel_style(COLOUR_SLOT_EMPTY, COLOUR_ACCENT))
	button.add_theme_stylebox_override("disabled",
		panel_style(COLOUR_LOCKED, COLOUR_TEXT_DIM))
	if card == null:
		return button

	var box_in := VBoxContainer.new()
	box_in.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box_in.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box_in.add_theme_constant_override("separation", 2)
	button.add_child(box_in)

	var portrait := portrait_rect(card, db, Vector2(box.x - 16.0, box.y * 0.55))
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box_in.add_child(portrait)

	# THE WRITING GROWS WITH THE CARD. The card is a different size on the
	# builder, the pitch and the Adventure fight, and 11-point text on a
	# 220-wide card looks like a mistake. These two lines are why making a
	# card bigger anywhere makes it READ bigger rather than just wider.
	var name_size := int(clampf(box.x * 0.088, 11.0, 22.0))
	var stat_size := int(clampf(box.x * 0.095, 12.0, 24.0))

	var name_label := Label.new()
	name_label.text = card.player_name
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", name_size)
	name_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box_in.add_child(name_label)

	var footer := Label.new()
	var star_mark := "★ " if card.is_star() else ""
	footer.text = "%sT%s   %d/%d" % [star_mark, card.get_tier_clean(),
		card.get_attack_power(), card.get_defense_power()]
	if extra != "":
		footer.text += "\n" + extra
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_font_size_override("font_size", stat_size)
	footer.add_theme_color_override("font_color", tint.lightened(0.35))
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box_in.add_child(footer)

	if card.is_star():
		var mark := clampf(box.x * 0.19, 22.0, 44.0)
		var badge := StarBadge.make_marker(false, mark)
		button.add_child(badge)
		badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		badge.offset_left = -(mark + 4.0)
		badge.offset_top = 3.0
		badge.offset_right = -4.0
		badge.offset_bottom = 3.0 + mark

	return button


# -------------------------------------------------------------
#  FINDING AN ICON BY NAME
#
#  The Art / Artwork column of Buildings.csv, Talents.csv and Brews.csv
#  holds a FILE NAME, not a path — `mill`, or `mill.png`. This looks for
#  that file in the usual asset folders and returns null when it is not
#  there yet, which is NOT an error: whatever asked for it draws a
#  placeholder instead, the same way the keeper does.
#
#  Add a folder to ICON_DIRS and every screen finds art there. Extensions
#  are tried in order, so a column reading `mill` finds `mill.png`.
# -------------------------------------------------------------

const ICON_DIRS: Array[String] = [
	"res://assets/icons/", "res://assets/base/", "res://assets/buildings/",
	"res://assets/talents/", "res://assets/brews/", "res://assets/",
]
const ICON_EXTENSIONS: Array[String] = [".png", ".webp", ".jpg", ".svg"]


static func icon_texture(file_name: String) -> Texture2D:
	var clean := file_name.strip_edges()
	if clean == "":
		return null

	# A full path in the column is used exactly as written.
	if clean.begins_with("res://"):
		return load(clean) as Texture2D if ResourceLoader.exists(clean) else null

	var names: Array[String] = [clean]
	if not clean.contains("."):
		for extension in ICON_EXTENSIONS:
			names.append(clean + extension)

	for folder in ICON_DIRS:
		for candidate in names:
			var path: String = folder + candidate
			if ResourceLoader.exists(path):
				return load(path) as Texture2D
	return null


# -------------------------------------------------------------
#  SHARED LOOK
#  One place to change the menu palette. Every screen reads from here.
#
#  THESE ARE `static var`, NOT `const`, ON PURPOSE. The Colour tab of the
#  settings screen writes to them — see game_settings.gd — which is how a
#  colour-blind palette or a high-contrast one changes the entire game
#  without a single screen knowing it happened. The values below are the
#  default palette, and Settings > Colour > Reset puts them back.
# -------------------------------------------------------------

static var COLOUR_BACKGROUND := Color(0.09, 0.10, 0.13)
static var COLOUR_PANEL := Color(0.14, 0.15, 0.19)
static var COLOUR_SLOT_EMPTY := Color(0.18, 0.19, 0.24)
static var COLOUR_LOCKED := Color(0.24, 0.20, 0.12)
static var COLOUR_ACCENT := Color(0.98, 0.76, 0.33)
static var COLOUR_TEXT := Color(0.92, 0.93, 0.96)
static var COLOUR_TEXT_DIM := Color(0.60, 0.63, 0.70)

## The four tier colours, in ladder order. Also a `static var`, for the same
## reason: red-green colour blindness makes the default Tier II green and
## Tier III amber hard to tell apart, and the Colour tab swaps the set.
static var TIER_COLOURS: Array[Color] = [
	Color(0.30, 0.45, 0.62),   # I
	Color(0.30, 0.56, 0.45),   # II
	Color(0.62, 0.46, 0.26),   # III
	Color(0.55, 0.32, 0.48),   # IV
]


static func colour_for_tier(tier: String) -> Color:
	match tier.to_upper():
		"I":   return TIER_COLOURS[0]
		"II":  return TIER_COLOURS[1]
		"III": return TIER_COLOURS[2]
		"IV":  return TIER_COLOURS[3]
	return Color(0.30, 0.32, 0.38)


## A filled, rounded panel background — used for every card and slot so the
## whole menu shares one look.
static func panel_style(fill: Color, border: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	if border.a > 0.0:
		style.border_width_left = 2
		style.border_width_right = 2
		style.border_width_top = 2
		style.border_width_bottom = 2
		style.border_color = border
	return style


static func heading(text: String, size: int = 28, colour: Color = COLOUR_TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	return label


# -------------------------------------------------------------
#  THE STANDARD FOOTER
#
#  ============ ONE SHAPE FOR EVERY SCREEN ============
#
#  Every screen used to build its own row of buttons, so Back was a different
#  size, colour and wording depending on where you were standing. They all
#  call footer_bar() now and get the same thing:
#
#      BACK on the bottom left, always, in the icon-and-label style
#      whatever else the screen needs, to the right of it
#      the screen's own message filling the gap between them
#
#  The style is the one from the team shelf and the base — a small picture on
#  the left of the button, the words on the right. Drop a PNG into
#  res://assets/icons/ named after the word before the `|` and that button
#  wears it; until then it draws the symbol after the `|`.
#
#  THE BASE IS THE ONE EXCEPTION. Its buttons are laid across the top rather
#  than in a footer, on purpose — it is a hub, not a page you came to and
#  will leave. It uses icon_button() directly.
# -------------------------------------------------------------

## The size every footer button is, everywhere. One number to change if you
## decide they should be bigger.
const FOOTER_BUTTON := Vector2(170.0, 54.0)
const FOOTER_TALL_BUTTON := Vector2(230.0, 54.0)


## Build the bottom row of a screen. Add it to your page's VBoxContainer and
## put your own buttons in with footer_button() below.
##
## Returns the HBoxContainer, with Back already in it on the left.
static func footer_bar(on: Node, back_pressed: Callable,
		back_label: String = "Back") -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.name = "Footer"
	bar.add_theme_constant_override("separation", 12)
	bar.custom_minimum_size = Vector2(0, FOOTER_BUTTON.y)

	var back := icon_button("back|←", back_label, FOOTER_BUTTON)
	back.name = "BackButton"
	back.tooltip_text = "Back to where you came from."
	if back_pressed.is_valid():
		back.pressed.connect(back_pressed)
	bar.add_child(back)

	if on != null:
		# Nothing to do with the look — this is so ControllerFocus can find
		# the footer and put Back last in the walking order.
		bar.add_to_group("screen_footer")
	return bar


## A gap that pushes everything after it to the right-hand end of the footer.
## Put your screen's message in it, or leave it empty for a plain spacer.
static func footer_gap(message: Label = null) -> Control:
	if message != null:
		message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		message.add_theme_font_size_override("font_size", 14)
		message.add_theme_color_override("font_color", COLOUR_TEXT_DIM)
		return message
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer


## Any other button in a footer. Same style as Back, so a row of them reads
## as one set rather than as four different buttons.
static func footer_button(icon: String, label: String,
		wide: bool = false) -> Button:
	return icon_button(icon, label, FOOTER_TALL_BUTTON if wide else FOOTER_BUTTON)


## THE ONE THAT MATTERS ON THIS SCREEN — the Play, the Lock In, the Continue.
## Same shape as the others, lit in the accent colour so the eye finds it.
static func footer_primary(icon: String, label: String) -> Button:
	var button := icon_button(icon, label, FOOTER_TALL_BUTTON)
	button.add_theme_stylebox_override("normal",
		panel_style(COLOUR_SLOT_EMPTY, COLOUR_ACCENT))
	button.add_theme_stylebox_override("hover",
		panel_style(COLOUR_LOCKED, COLOUR_ACCENT))
	return button


## THE "YOU ARE HERE" BOX, for a controller or the arrow keys. A thick accent
## border and nothing else, so it sits on top of whatever the button already
## looks like instead of replacing it.
static func focus_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_width_left = 3
	style.border_width_right = 3
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.border_color = COLOUR_ACCENT
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.expand_margin_left = 2
	style.expand_margin_right = 2
	style.expand_margin_top = 2
	style.expand_margin_bottom = 2
	return style


# -------------------------------------------------------------
#  MAKING A BUTTON FROM A .tscn LOOK LIKE THE REST
#
#  Some screens — the season table, the full-time report — have their buttons
#  laid out inside their scene file rather than built in code. Those cannot
#  be replaced with icon_button(), but they CAN be given the same face.
#
#  restyle() turns any plain Button into the two-part icon-and-label button
#  the rest of the game uses. One call per button and the screen matches.
#
#  pin_bottom_left() and friends then put it where every other screen puts
#  it, without anybody opening the scene file in the editor.
# -------------------------------------------------------------

## Give an existing Button the standard face. Its old text is thrown away —
## pass the label you want.
static func restyle(button: Button, icon: String, label: String,
		primary: bool = false) -> void:
	if button == null:
		return

	button.text = ""
	button.icon = null
	button.focus_mode = Control.FOCUS_ALL
	button.custom_minimum_size = FOOTER_TALL_BUTTON if primary else FOOTER_BUTTON

	var fill := COLOUR_SLOT_EMPTY if primary else COLOUR_PANEL
	var edge := COLOUR_ACCENT if primary else COLOUR_TEXT_DIM
	button.add_theme_stylebox_override("normal", panel_style(fill, edge))
	button.add_theme_stylebox_override("hover", panel_style(COLOUR_SLOT_EMPTY, COLOUR_ACCENT))
	button.add_theme_stylebox_override("pressed", panel_style(COLOUR_SLOT_EMPTY, COLOUR_ACCENT))
	button.add_theme_stylebox_override("disabled", panel_style(COLOUR_LOCKED, COLOUR_TEXT_DIM))
	button.add_theme_stylebox_override("focus", focus_style())

	# Out with whatever face it had, in with ours.
	for child in button.get_children():
		if child.name == "IconFace":
			child.queue_free()

	var face := icon_button(icon, label, button.custom_minimum_size)
	var row := face.get_child(0)
	face.remove_child(row)
	face.queue_free()
	row.name = "IconFace"
	button.add_child(row)


## ============ A BUTTON THAT IS IN A CONTAINER CANNOT BE PINNED ============
##
## A Control inside an HBoxContainer or a VBoxContainer has its position
## rewritten by that container every frame, so setting anchors on it does
## nothing at all. The buttons being pinned come out of .tscn files and are
## usually in exactly such a row.
##
## So they are lifted out of it first, onto the screen itself, where anchors
## mean something. This is the single line that makes pin_bottom_left() work
## on a scene somebody laid out in the editor.
static func _lift_out_of_container(node: Control) -> void:
	var parent := node.get_parent()
	if parent == null or not (parent is Container):
		return
	var screen := node.owner as Node
	if screen == null:
		# No owner means it was built in code. Walk up to the top Control.
		screen = parent
		while screen.get_parent() != null and screen.get_parent() is Container:
			screen = screen.get_parent()
		screen = screen.get_parent() if screen.get_parent() != null else parent
	parent.remove_child(node)
	screen.add_child(node)


## Put a Control in the bottom-left corner of the screen, where Back lives on
## every screen in the game.
static func pin_bottom_left(node: Control, inset: Vector2 = Vector2(32, 22)) -> void:
	if node == null:
		return
	_lift_out_of_container(node)
	var box := node.custom_minimum_size
	if box == Vector2.ZERO:
		box = FOOTER_BUTTON
	node.set_anchors_preset(Control.PRESET_BOTTOM_LEFT, true)
	node.offset_left = inset.x
	node.offset_right = inset.x + box.x
	node.offset_top = -(inset.y + box.y)
	node.offset_bottom = -inset.y


## The middle of the bottom edge — for the one button a screen is really
## about, when there is only one.
static func pin_bottom_centre(node: Control, inset: float = 22.0) -> void:
	if node == null:
		return
	_lift_out_of_container(node)
	var box := node.custom_minimum_size
	if box == Vector2.ZERO:
		box = FOOTER_TALL_BUTTON
	node.set_anchors_preset(Control.PRESET_CENTER_BOTTOM, true)
	node.offset_left = -box.x * 0.5
	node.offset_right = box.x * 0.5
	node.offset_top = -(inset + box.y)
	node.offset_bottom = -inset


static func pin_bottom_right(node: Control, inset: Vector2 = Vector2(32, 22)) -> void:
	if node == null:
		return
	_lift_out_of_container(node)
	var box := node.custom_minimum_size
	if box == Vector2.ZERO:
		box = FOOTER_BUTTON
	node.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT, true)
	node.offset_left = -(inset.x + box.x)
	node.offset_right = -inset.x
	node.offset_top = -(inset.y + box.y)
	node.offset_bottom = -inset
