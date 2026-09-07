extends SceneTree

# =============================================================
#  ROW PREVIEW TOOL  —  "which row is which animation?"
#
#  Exports one labelled contact sheet per card into res://sheet_previews/.
#  Each output row shows: the row NUMBER, how many frames are drawn on it,
#  and the first / middle / last drawn frame. Open the PNG, read off the
#  row numbers, and type them into Animations.csv.
#
#  RUN IT (from a terminal, in the project folder):
#     godot --headless --script res://export_sheet_preview.gd
#
#  Or in the editor: open this file and use File > Run.
#  It only reads your art — it never changes it.
# =============================================================

const OUT_DIR := "res://sheet_previews/"
const LABEL_WIDTH := 120
const PREVIEW_FRAMES := 3      # first, middle, last drawn frame


func _initialize() -> void:
	var db := CardDatabase.get_db()
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	var done := 0
	var seen := {}
	for card in db.players:
		if card.artwork == null:
			continue
		var path: String = card.artwork.resource_path
		if seen.has(path):
			continue
		seen[path] = true
		if _export_one(card, db):
			done += 1

	print("Wrote %d preview sheet(s) to %s" % [done, OUT_DIR])
	print("Open one, read the row numbers, and fill them into Animations.csv.")
	quit()


func _export_one(card: PlayerData, db: CardDatabase) -> bool:
	var spec := db.get_anim("idle", card.unit_type)
	var columns := spec.sheet_columns if spec != null else AnimSpec.DEFAULT_COLUMNS
	var rows := spec.sheet_rows if spec != null else AnimSpec.DEFAULT_ROWS

	var source := card.artwork.get_image()
	if source == null or source.is_compressed():
		push_warning("Cannot read pixels from %s — set its import Compress Mode to Lossless."
			% card.artwork.resource_path)
		return false

	var frame_w := int(source.get_width() / columns)
	var frame_h := int(source.get_height() / rows)

	var out := Image.create(LABEL_WIDTH + frame_w * PREVIEW_FRAMES,
		frame_h * rows, false, Image.FORMAT_RGBA8)
	out.fill(Color(0.11, 0.11, 0.14, 1.0))

	for r in rows:
		# Which frames on this row actually have pixels?
		var drawn: Array[int] = []
		for c in columns:
			var cell := source.get_region(Rect2i(c * frame_w, r * frame_h, frame_w, frame_h))
			if cell.get_used_rect().size.x > 0:
				drawn.append(c)

		# "08" in blue, then "12f" in amber underneath.
		_draw_label(out, r, drawn.size(), frame_h)

		if drawn.is_empty():
			continue
		var picks: Array[int] = [drawn[0], drawn[drawn.size() / 2], drawn[drawn.size() - 1]]
		for i in picks.size():
			var cell2 := source.get_region(
				Rect2i(picks[i] * frame_w, r * frame_h, frame_w, frame_h))
			out.blit_rect(cell2, Rect2i(0, 0, frame_w, frame_h),
				Vector2i(LABEL_WIDTH + i * frame_w, r * frame_h))

		# A faint separator line under each row.
		for x in out.get_width():
			out.set_pixel(x, r * frame_h + frame_h - 1, Color(0.25, 0.25, 0.3, 1.0))

	var file_name: String = card.artwork.resource_path.get_file().get_basename()
	var save_path := OUT_DIR + file_name + "_rows.png"
	var err := out.save_png(ProjectSettings.globalize_path(save_path))
	if err != OK:
		push_warning("Could not write %s (error %d)" % [save_path, err])
		return false
	print("  %s  — %d rows of %d x %d" % [save_path, rows, frame_w, frame_h])
	return true


# A 3 x 5 bitmap font, just the digits and "f" — enough to label a row and
# its frame count without shipping a font file.
const GLYPHS := {
	"0": ["111", "101", "101", "101", "111"],
	"1": ["010", "110", "010", "010", "111"],
	"2": ["111", "001", "111", "100", "111"],
	"3": ["111", "001", "111", "001", "111"],
	"4": ["101", "101", "111", "001", "001"],
	"5": ["111", "100", "111", "001", "111"],
	"6": ["111", "100", "111", "101", "111"],
	"7": ["111", "001", "001", "001", "001"],
	"8": ["111", "101", "111", "101", "111"],
	"9": ["111", "101", "111", "001", "111"],
	"f": ["011", "100", "110", "100", "100"],
}
const GLYPH_SCALE := 4


## Row number in blue, frames-drawn count in amber underneath.
func _draw_label(out: Image, row_index: int, frame_count: int, frame_h: int) -> void:
	var top := row_index * frame_h + 6
	_draw_text(out, "%02d" % row_index, 8, top, Color(0.55, 0.78, 1.0, 1.0))
	_draw_text(out, "%df" % frame_count, 8, top + 6 * GLYPH_SCALE, Color(1.0, 0.8, 0.45, 1.0))


func _draw_text(out: Image, text: String, x: int, y: int, colour: Color) -> void:
	var cursor := x
	for i in text.length():
		var glyph: Array = GLYPHS.get(text[i], [])
		if glyph.is_empty():
			cursor += 2 * GLYPH_SCALE
			continue
		for gy in glyph.size():
			var line: String = glyph[gy]
			for gx in line.length():
				if line[gx] != "1":
					continue
				_block(out, cursor + gx * GLYPH_SCALE, y + gy * GLYPH_SCALE,
					GLYPH_SCALE, GLYPH_SCALE, colour)
		cursor += 4 * GLYPH_SCALE


func _block(out: Image, x: int, y: int, w: int, h: int, colour: Color) -> void:
	for dx in w:
		for dy in h:
			var px := x + dx
			var py := y + dy
			if px >= 0 and py >= 0 and px < out.get_width() and py < out.get_height():
				out.set_pixel(px, py, colour)
