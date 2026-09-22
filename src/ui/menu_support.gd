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


# -------------------------------------------------------------
#  A BAG SLOT — the square button the Inventory is made of
#
#  icon_button() above puts the picture on the LEFT and the words beside it,
#  which is right for a menu of five things and wrong for a bag of forty.
#  This is the other shape: a square with the picture in the middle, how many
#  you have in the bottom corner, and NO WORDS AT ALL.
#
#  What it is is read by pointing at it. Every screen that shows one also
#  shows a description panel, and the caller wires the hover up — see
#  inventory_screen.gd, which is the one place all of this comes together.
#
#  `art` is a file name out of a CSV (Items.csv `Art`, Brews.csv `Artwork`).
#  Missing art is not an error: `glyph` is drawn instead, which is why a bag
#  full of items works long before any of them have been drawn.
# -------------------------------------------------------------

static func slot_button(art: String, glyph: String, count: int,
		size: Vector2 = Vector2(84, 84), tint: Color = COLOUR_TEXT_DIM) -> Button:
	# ============ HOW BIG AN ITEM IS, FROM A SPREADSHEET ============
	#
	# "The icons are too small to see on the screen." They were 84 pixels
	# square with ten pixels of padding a side, which leaves 64 for the
	# drawing — and a 64-pixel drawing on a 1080-line screen is a thumbnail.
	#
	# `icon_tile_size` in Tuning.csv is the number, so the answer to "is that
	# big enough" is a row you change and look at rather than a message to
	# me. Everything scales off it: the padding, the count in the corner and
	# the stand-in glyph are all fractions of the tile now, so one row moves
	# all of them together.
	size = Vector2(tuned("icon_tile_size", size.x), tuned("icon_tile_size", size.y))
	var button := Button.new()
	button.custom_minimum_size = size
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_stylebox_override("normal", panel_style(COLOUR_PANEL, tint))
	button.add_theme_stylebox_override("hover", panel_style(COLOUR_SLOT_EMPTY, COLOUR_ACCENT))
	button.add_theme_stylebox_override("pressed", panel_style(COLOUR_SLOT_EMPTY, COLOUR_ACCENT))
	button.add_theme_stylebox_override("disabled", panel_style(COLOUR_LOCKED, COLOUR_TEXT_DIM))
	button.add_theme_stylebox_override("focus", focus_style())

	# --- the picture, filling the middle ---
	var texture := icon_texture(art)
	if texture != null:
		var picture := TextureRect.new()
		picture.texture = texture
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		# A FRACTION OF THE TILE, not a fixed ten pixels — so making the tile
		# bigger makes the DRAWING bigger rather than the border round it.
		var pad := size.x * tuned("icon_tile_padding", 0.10)
		picture.offset_left = pad
		picture.offset_top = pad * 0.8
		picture.offset_right = -pad
		picture.offset_bottom = -maxf(pad * 1.8, 14.0)
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(picture)
	else:
		var mark := Label.new()
		mark.text = glyph
		mark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mark.offset_bottom = -12.0
		mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		mark.add_theme_font_size_override("font_size", int(size.y * 0.42))
		mark.add_theme_color_override("font_color", tint)
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(mark)

	# --- how many, along the bottom. Hidden at one, because "x1" is noise ---
	if count > 1:
		var many := Label.new()
		many.text = "x%d" % count
		many.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		# Inside the border on all three sides. Pinned to the edge it sat ON
		# the border, and a number cut in half by a line reads as a glitch.
		many.offset_top = -20.0
		many.offset_bottom = -5.0
		many.offset_left = 4.0
		many.offset_right = -8.0
		many.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		many.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		many.add_theme_font_size_override("font_size", 12)
		many.add_theme_color_override("font_color", COLOUR_ACCENT)
		many.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(many)

	return button


## A tab along the top of a window. A plain rectangle with a word in it —
## icon_button() would give it an empty picture half, which on a tab is a
## notch of dead space at the left of every one of them.
static func tab_button(text: String, lit: bool,
		size: Vector2 = Vector2(170, 38)) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = size
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 14)
	paint_tab(button, lit)
	button.add_theme_stylebox_override("hover",
		panel_style(COLOUR_SLOT_EMPTY, COLOUR_ACCENT))
	button.add_theme_stylebox_override("pressed",
		panel_style(COLOUR_SLOT_EMPTY, COLOUR_ACCENT))
	button.add_theme_stylebox_override("focus", focus_style())
	return button


## Light a tab, or put it out. Kept apart from tab_button() so a screen can
## change which tab is lit without rebuilding the row.
static func paint_tab(button: Button, lit: bool) -> void:
	button.add_theme_stylebox_override("normal", panel_style(
		COLOUR_SLOT_EMPTY if lit else COLOUR_PANEL,
		COLOUR_ACCENT if lit else COLOUR_TEXT_DIM))
	button.add_theme_color_override("font_color",
		COLOUR_TEXT if lit else COLOUR_TEXT_DIM)


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
	"res://assets/talents/", "res://assets/brews/",
	# Crests and banners. A team's Banner Art is looked for here first, which
	# is why assets/team/ is on the list — see team_sheet.gd.
	"res://assets/team/", "res://assets/menu/", "res://assets/",
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

## ============ THE TWO COLOURS THAT MEAN THE MOST ============
##
## ATTACK is warm, DEFENCE is cool, and they mean exactly one thing each,
## everywhere in the game: the strip above the cards that says which way
## round the round is being played, and the ATK / DEF tags on a Star's
## abilities. Learn them once in the draft and you can read a team sheet
## without reading a word of it.
##
## They are in the palette rather than in the two files that use them
## precisely so that they cannot drift apart, and so the Colour tab can
## replace both at once.
static var COLOUR_ATTACK := Color(0.95, 0.62, 0.36)
static var COLOUR_DEFEND := Color(0.44, 0.73, 0.94)

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
## ============ A WINDOW THAT SITS OVER A SCREEN ============
##
## Every "are you sure", every little settings box, every confirmation in the
## game should look the same and behave the same, and until now each one was
## built by hand where it was needed — which is how you end up with three
## different ideas of what a dialog is.
##
## Hand it a title and a line of explanation; it returns a CanvasLayer with a
## dimmed backdrop and a centred panel, and puts the VBoxContainer you should
## add your buttons to in its `column` metadata:
##
##     var window := MenuSupport.dialog(self, "SLOT 2", "14 matches")
##     var column: VBoxContainer = window.get_meta("column")
##     column.add_child(my_button)
##
## Escape closes it, clicking the dim closes it, and it frees itself. It is
## on layer 180 — above ordinary screen content, below the Escape panel
## (150 is below it, the match's pause menu is 200), so a dialog cannot trap
## you: Escape still reaches the panel behind it after this one is gone.
## ONE NUMBER OUT OF Tuning.csv, safely. The card database is not always
## loaded when a menu is being built — the title screen draws before anything
## has read a spreadsheet — so this falls back to the value in code rather
## than to zero, which would make a button no pixels wide.
static func tuned(key: String, fallback: float) -> float:
	var book := CardDatabase.get_db()
	if book == null:
		return fallback
	return book.tune_float(key, fallback)


static func dialog(on: Node, title: String, under: String = "",
		width: float = 460.0) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.name = "Dialog"
	layer.layer = 180
	on.add_child(layer)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click != null and click.pressed and is_instance_valid(layer):
			layer.queue_free())
	layer.add_child(dim)

	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(centre)

	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(width, 0)
	frame.add_theme_stylebox_override("panel",
		panel_style(COLOUR_PANEL, COLOUR_ACCENT))
	centre.add_child(frame)

	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right"]:
		pad.add_theme_constant_override(side, 26)
	for side in ["margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 22)
	frame.add_child(pad)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	pad.add_child(column)

	var head := heading(title, 26, COLOUR_ACCENT)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(head)

	if under.strip_edges() != "":
		var note := Label.new()
		note.text = under
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		note.add_theme_font_size_override("font_size", 14)
		note.add_theme_color_override("font_color", COLOUR_TEXT_DIM)
		column.add_child(note)

	layer.set_meta("column", column)
	return layer


# ============ EVERY BOX IN THE GAME IS DRAWN HERE ============
#
# A card face, a tile, a dialog, the strip above the card row, the keeper's
# number, a button, the celebration window. All of them. Which is exactly why
# `data/Theme.csv` sits in front of this one function: change the `panel` row
# and you have changed every box in the game without opening a screen.
#
# THE SHAPE COMES FROM THE SPREADSHEET, THE COLOUR FROM THE CALLER. Thirty-six
# screens already pass the colour they want and those calls are not going
# away, so a themed image is drawn MODULATED by it — one neutral grey PNG
# arrives in every screen wearing that screen's own colour. The corner radius,
# the border width and the padding come from the row.
#
# With no Theme.csv at all it draws precisely what it drew before: a flat box,
# 6px corners, a 2px border, 8 by 6 of padding.
static func panel_style(fill: Color, border: Color = Color(0, 0, 0, 0)) -> StyleBox:
	return ThemeBook.style("panel", "", fill, border)


## The same thing for a named element — a window, a slot, a tab — so a screen
## that wants the dialog look can ask for it by name instead of by colour.
static func styled(element: String, state: String = "",
		fill: Color = Color(0, 0, 0, 0), border: Color = Color(0, 0, 0, 0)) -> StyleBox:
	return ThemeBook.style(element, state, fill, border)


## A heading. The FONT comes from the `heading` row of Theme.csv; the size
## and colour are the caller's, because a screen knows how big its own title
## should be relative to its own contents and a spreadsheet does not.
static func heading(text: String, size: int = 28, colour: Color = COLOUR_TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	var face := ThemeBook.font(String(ThemeBook.row_for("heading").get("font", "")))
	if face != null:
		label.add_theme_font_override("font", face)
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
static func focus_style() -> StyleBox:
	# The `button` row's `focus` state. Its Fill is left empty on purpose —
	# the box is drawn OVER the button, so filling it paints the button out.
	return ThemeBook.style("button", "focus", Color(0, 0, 0, 0), COLOUR_ACCENT)


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
	# `.y`, NOT `-inset`. `inset` is a Vector2 here and offset_bottom is a
	# float, so the missing .y was a parse error that took this whole file
	# down — and with it every screen that calls anything in it.
	node.offset_bottom = -inset.y
