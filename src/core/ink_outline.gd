class_name InkOutline
extends RefCounted

# =============================================================
#  A BLACK INK BORDER ROUND EVERY LETTER  (round AN)
#
#  Anthony, 24 Oct: "The words on the buttons need to have a black border,
#  so all the font that we have, give it a black border please that fits to
#  our game art style" - "So all font not just buttons".
#
#  ============ WHY IT IS DRAWN INTO THE FONT ============
#
#  The game font (SturmballComicHD) is a picture font, and Godot cannot put
#  an outline round a picture font: outline_size does nothing to it. So the
#  border is drawn INTO a copy of the font's letter sheet when the game
#  starts: every white letter gets a thick black ring, like an inked comic
#  balloon. The letters are still white underneath, so every screen's own
#  word colour still lands on them - only the ring stays black.
#
#  ThemeBook.font() hands out this inked copy, so every word in the game
#  wears it: buttons, labels, the match, Adventure, words painted with
#  draw_string. Nothing on any screen had to change.
#
#  ============ WHERE IT IS LEFT OFF ============
#
#  Dark ink words on cream or wood (beer mats, the emblem text, the tavern
#  signs, the ink notes in the team sheet) are printed, not inked: a black
#  ring round a dark letter only makes it blurry. watch() swaps those back
#  to the plain font: any word whose colour is darker than
#  text_outline_dark_limit, or whose screen switched outlines off itself.
#
#  Tuning.csv:  text_outline             how thick (0 = no border)
#               text_outline_dark_limit  how dark a word must be to go plain
# =============================================================

const DEFAULT_THICKNESS := 6
const DEFAULT_DARK_LIMIT := 0.3
## On the inked copy: the plain font it was made from.
const PLAIN_META := "ink_outline_plain"
## On a word that was swapped to the plain font, so it is not looked at twice.
const DONE_META := "ink_outline_checked"


static func thickness() -> int:
	var db := CardDatabase.get_db()
	if db == null:
		return DEFAULT_THICKNESS
	return clampi(int(db.tune_float("text_outline", DEFAULT_THICKNESS)), 0, 16)


static func dark_limit() -> float:
	var db := CardDatabase.get_db()
	if db == null:
		return DEFAULT_DARK_LIMIT
	return db.tune_float("text_outline_dark_limit", DEFAULT_DARK_LIMIT)


## The plain font an inked copy was made from (or the font itself).
static func plain_of(face: Font) -> Font:
	if face != null and face.has_meta(PLAIN_META):
		return face.get_meta(PLAIN_META) as Font
	return face


## An inked copy of a picture font. A font Godot CAN outline (.ttf, .otf)
## and a thickness of 0 come back unchanged.
static func inked(face: Font) -> Font:
	var ring := thickness()
	if ring <= 0 or not (face is FontFile):
		return face
	var plain := face as FontFile
	if plain.get_cache_count() == 0 or plain.get_size_cache_list(0).is_empty():
		return face   # a .ttf/.otf: drawn from curves, no letter sheet to ink
	var copy := plain.duplicate(true) as FontFile
	for cache in copy.get_cache_count():
		for at_size in copy.get_size_cache_list(cache):
			_ink_size(copy, cache, at_size, ring)
	copy.set_meta(PLAIN_META, plain)
	return copy


static func _ink_size(copy: FontFile, cache: int, at_size: Vector2i, ring: int) -> void:
	# The letters sit close together on the font's sheet, so a ring round
	# one would bleed into the box of the letter above it. So every letter
	# is first copied onto a new sheet with room round it...
	var sheets: Array[Image] = []
	for page in copy.get_texture_count(cache, at_size):
		var sheet := copy.get_texture_image(cache, at_size, page)
		if sheet != null:
			sheet = sheet.duplicate() as Image
			if sheet.is_compressed():
				sheet.decompress()
			sheet.clear_mipmaps()
			sheet.convert(Image.FORMAT_RGBA8)
		sheets.append(sheet)
	var letters: Array = []
	var cell := Vector2i.ZERO
	for glyph in copy.get_glyph_list(cache, at_size):
		var box := Rect2i(copy.get_glyph_uv_rect(cache, at_size, glyph))
		var page := copy.get_glyph_texture_idx(cache, at_size, glyph)
		if box.size.x <= 0 or box.size.y <= 0 or page < 0 or page >= sheets.size() \
				or sheets[page] == null:
			continue
		letters.append([glyph, box, page])
		cell = cell.max(box.size)
	if letters.is_empty():
		return
	cell += Vector2i(ring, ring) * 2 + Vector2i(2, 2)
	var columns := 16
	var rows := ceili(letters.size() / float(columns))
	var fresh := Image.create_empty(cell.x * columns, cell.y * rows, false, Image.FORMAT_RGBA8)
	for i in letters.size():
		var corner := Vector2i(i % columns, i / columns) * cell + Vector2i(ring + 1, ring + 1)
		fresh.blit_rect(sheets[letters[i][2]], letters[i][1], corner)
	# ...then the black shape of every letter is stamped in a round ring...
	var shadow := fresh.duplicate() as Image
	shadow.adjust_bcs(0.0, 1.0, 1.0)
	var inked_sheet := Image.create_empty(fresh.get_width(), fresh.get_height(), false,
		Image.FORMAT_RGBA8)
	var whole := Rect2i(Vector2i.ZERO, fresh.get_size())
	for dy in range(-ring, ring + 1):
		for dx in range(-ring, ring + 1):
			if dx * dx + dy * dy <= ring * ring + ring:
				inked_sheet.blend_rect(shadow, whole, Vector2i(dx, dy))
	# ...and the white letters go back on top.
	inked_sheet.blend_rect(fresh, whole, Vector2i.ZERO)
	for page in range(copy.get_texture_count(cache, at_size) - 1, 0, -1):
		copy.remove_texture(cache, at_size, page)
	copy.set_texture_image(cache, at_size, 0, inked_sheet)
	# Every letter's box grows by the ring, so the ring is not cut off. How
	# far the pen moves on stays the same: the rings overlap like real ink.
	var grow := Vector2(ring, ring)
	for i in letters.size():
		var glyph: int = letters[i][0]
		var box: Rect2i = letters[i][1]
		var corner := Vector2(Vector2i(i % columns, i / columns) * cell) + Vector2(1, 1)
		copy.set_glyph_texture_idx(cache, at_size, glyph, 0)
		copy.set_glyph_uv_rect(cache, at_size, glyph, Rect2(corner, Vector2(box.size) + grow * 2.0))
		copy.set_glyph_offset(cache, at_size, glyph, copy.get_glyph_offset(cache, at_size, glyph) - grow)
		copy.set_glyph_size(cache, at_size, glyph, copy.get_glyph_size(cache, at_size, glyph) + grow * 2.0)


# =============================================================
#  DARK INK WORDS GO PLAIN
# =============================================================

## Look at every word now and whenever one is added. Called by
## ThemeBook.dress(); safe to call again.
static func watch(tree: SceneTree) -> void:
	if tree == null or tree.root == null or thickness() <= 0:
		return
	if tree.has_meta("ink_outline_watching"):
		return
	tree.set_meta("ink_outline_watching", true)
	for node in tree.root.find_children("*", "", true, false):
		check(node)
	# Deferred: a screen sets a word's colour just after adding it.
	tree.node_added.connect(func(node: Node) -> void: check.call_deferred(node))


## One word. Takes a Variant: it is called a frame late, and a node freed in
## between must be skipped, not crash the call.
static func check(node: Variant) -> void:
	if node == null or not is_instance_valid(node):
		return
	if not (node is Label or node is Button or node is RichTextLabel or node is LineEdit):
		return
	var control := node as Control
	if control.has_meta(DONE_META):
		return
	var colour_name := "default_color" if control is RichTextLabel else "font_color"
	var dark := control.get_theme_color(colour_name).get_luminance() < dark_limit()
	var switched_off := control.has_theme_constant_override("outline_size") \
		and control.get_theme_constant("outline_size") == 0
	if not (dark or switched_off):
		return
	control.set_meta(DONE_META, true)
	var font_name := "normal_font" if control is RichTextLabel else "font"
	var plain := plain_of(control.get_theme_font(font_name))
	if plain != null and plain != control.get_theme_font(font_name):
		control.add_theme_font_override(font_name, plain)
