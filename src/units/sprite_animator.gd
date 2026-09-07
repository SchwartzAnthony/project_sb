class_name SpriteAnimator
extends TextureRect

# =============================================================
#  SPRITESHEET PLAYER FOR THE CLOSE-UP VIEWS
#
#  Drives a TextureRect from an AnimSpec (one row of Animations.csv).
#
#  TWO THINGS MAKE IT LOOK RIGHT
#
#  1. CROP TO THE DRAWN CHARACTER. Your frames are 128 x 64 but the
#     footballer only fills a small part of that. Blowing up the whole
#     cell would show a tiny figure in a sea of nothing, so on the first
#     play we scan the animation's frames, find the box that actually has
#     pixels in it, and crop every frame to that shared box. The figure
#     then fills the panel and stays put between frames (a shared box, not
#     a per-frame one, is what stops it jittering).
#
#  2. NEAREST-NEIGHBOUR SCALING. texture_filter is NEAREST and the scale
#     is snapped to a whole number, so a 4x blow-up is exactly 4 hard
#     pixels per source pixel. No blur, no half-pixel shimmer.
#
#  Crop boxes are cached per texture+animation, so the scan happens once.
# =============================================================

signal animation_finished(anim_name: String)

static var _crop_cache: Dictionary = {}

var spec: AnimSpec
var sheet: Texture2D
var speed_scale: float = 1.0

var _atlas: AtlasTexture
var _crop: Rect2i = Rect2i()
var _index: int = 0
var _clock: float = 0.0
var _playing: bool = false
var _finished_sent: bool = false


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Start an animation. Passing a null spec or sheet leaves the panel blank
## rather than erroring — art can be missing while you are still drawing it.
func play(new_sheet: Texture2D, new_spec: AnimSpec) -> void:
	sheet = new_sheet
	spec = new_spec
	_index = 0
	_clock = 0.0
	_finished_sent = false
	_playing = spec != null and sheet != null

	if not _playing:
		texture = null
		return

	_crop = _crop_for(sheet, spec)
	_atlas = AtlasTexture.new()
	_atlas.atlas = sheet
	texture = _atlas
	_show_frame(0)


func stop() -> void:
	_playing = false


func is_playing() -> bool:
	return _playing


func _process(delta: float) -> void:
	if not _playing or spec == null:
		return

	_clock += delta * maxf(speed_scale, 0.01)
	var step := spec.fps * _clock

	if step < 1.0:
		return
	_clock = 0.0
	_index += 1

	if _index >= spec.frames:
		if spec.loop:
			_index = 0
		else:
			_index = spec.frames - 1
			_playing = false
			if not _finished_sent:
				_finished_sent = true
				animation_finished.emit(spec.name)
			return

	_show_frame(_index)


func _show_frame(index: int) -> void:
	if _atlas == null or spec == null or sheet == null:
		return
	var cell := spec.cell_rect(index, sheet.get_size())
	_atlas.region = Rect2(
		cell.position.x + float(_crop.position.x),
		cell.position.y + float(_crop.position.y),
		float(_crop.size.x),
		float(_crop.size.y))


## Scale the panel so the cropped figure fills it at a WHOLE-number zoom.
func fit_into(box: Vector2, max_zoom: int = 8) -> void:
	if _crop.size.x <= 0 or _crop.size.y <= 0:
		return
	var zoom := int(floor(minf(box.x / float(_crop.size.x), box.y / float(_crop.size.y))))
	zoom = clampi(zoom, 1, max_zoom)
	custom_minimum_size = Vector2(_crop.size) * zoom
	size = custom_minimum_size


func crop_size() -> Vector2i:
	return _crop.size


# =============================================================
#  CROP SCANNING
# =============================================================

static func _crop_for(sheet_texture: Texture2D, anim: AnimSpec) -> Rect2i:
	var key := "%s|%s|%d|%d|%d" % [
		sheet_texture.resource_path, anim.name, anim.row, anim.first_frame, anim.frames]
	if _crop_cache.has(key):
		return _crop_cache[key]

	var fallback := Rect2i(0, 0,
		int(sheet_texture.get_width() / anim.sheet_columns),
		int(sheet_texture.get_height() / anim.sheet_rows))

	var image := sheet_texture.get_image()
	if image == null:
		_crop_cache[key] = fallback
		return fallback
	if image.is_compressed():
		# Can't read pixels from a compressed import; use the whole cell.
		_crop_cache[key] = fallback
		return fallback

	var union := Rect2i()
	var found := false
	for i in anim.frames:
		var cell := anim.cell_rect(i, sheet_texture.get_size())
		var region := Rect2i(int(cell.position.x), int(cell.position.y),
			int(cell.size.x), int(cell.size.y))
		var used := image.get_region(region).get_used_rect()
		if used.size.x <= 0 or used.size.y <= 0:
			continue
		if not found:
			union = used
			found = true
		else:
			union = union.merge(used)

	if not found:
		_crop_cache[key] = fallback
		return fallback

	# A little breathing room, kept inside the cell.
	union = union.grow(2)
	union.position.x = maxi(0, union.position.x)
	union.position.y = maxi(0, union.position.y)
	union.size.x = mini(union.size.x, fallback.size.x - union.position.x)
	union.size.y = mini(union.size.y, fallback.size.y - union.position.y)

	_crop_cache[key] = union
	return union
