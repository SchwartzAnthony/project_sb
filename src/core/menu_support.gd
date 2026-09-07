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
#  SHARED LOOK
#  One place to change the menu palette. Every screen reads from here.
# -------------------------------------------------------------

const COLOUR_BACKGROUND := Color(0.09, 0.10, 0.13)
const COLOUR_PANEL := Color(0.14, 0.15, 0.19)
const COLOUR_SLOT_EMPTY := Color(0.18, 0.19, 0.24)
const COLOUR_LOCKED := Color(0.24, 0.20, 0.12)
const COLOUR_ACCENT := Color(0.98, 0.76, 0.33)
const COLOUR_TEXT := Color(0.92, 0.93, 0.96)
const COLOUR_TEXT_DIM := Color(0.60, 0.63, 0.70)


static func colour_for_tier(tier: String) -> Color:
	match tier.to_upper():
		"I":   return Color(0.30, 0.45, 0.62)
		"II":  return Color(0.30, 0.56, 0.45)
		"III": return Color(0.62, 0.46, 0.26)
		"IV":  return Color(0.55, 0.32, 0.48)
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
