class_name MapBuilding
extends Button

# =============================================================
#  A BUILDING ON THE TOWN MAP THAT ONLY ANSWERS ON ITS OWN PIXELS
#
#  ROUND AN (Anthony): two big buildings next to each other must not steal
#  each other's clicks. A building's picture has empty, see-through corners
#  round the house, and a plain Button would answer a click there too - so
#  a click on the Pub's roof could open the Training Ground below it.
#
#  This Button only counts a point as "on it" when the picture is drawn
#  there (alpha above ALPHA_HIT). The picture is shown keep-aspect, centred,
#  exactly as base_screen.gd draws it, and the point is mapped the same way.
# =============================================================

const ALPHA_HIT := 0.1

var _mask: Image


## The picture whose pixels decide what is clickable.
func use_picture(texture: Texture2D) -> void:
	_mask = texture.get_image() if texture != null else null
	if _mask != null and _mask.is_compressed():
		_mask.decompress()


func _has_point(point: Vector2) -> bool:
	if not Rect2(Vector2.ZERO, size).has_point(point):
		return false
	if _mask == null:
		return true
	var picture := Vector2(_mask.get_size())
	var scale := minf(size.x / picture.x, size.y / picture.y)
	var offset := (size - picture * scale) * 0.5
	var at := (point - offset) / scale
	if at.x < 0.0 or at.y < 0.0 or at.x >= picture.x or at.y >= picture.y:
		return false
	return _mask.get_pixel(int(at.x), int(at.y)).a > ALPHA_HIT
