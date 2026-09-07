class_name AnimSpec
extends RefCounted

# =============================================================
#  ONE ROW OF Animations.csv
#
#  Says where an animation lives on a spritesheet and how to play it.
#  You never write code to add an animation — you draw it on a row of
#  your sheet and describe that row here.
#
#     Animation , Unit Type , Row , First Frame , Frames , FPS , Loop
#
#  `Unit Type` blank  = the default for every class.
#  `Unit Type` filled = an override just for that class.
#
#  Sheet geometry defaults to your existing 12 x 39 layout; a sheet with
#  a different grid just sets Sheet Columns / Sheet Rows on its rows.
# =============================================================

const DEFAULT_COLUMNS := 12
const DEFAULT_ROWS := 39

var name: String = ""
var unit_type: String = ""        # "" = applies to every class
var sheet_columns: int = DEFAULT_COLUMNS
var sheet_rows: int = DEFAULT_ROWS
var row: int = 0
var first_frame: int = 0
var frames: int = 1
var fps: float = 10.0
var loop: bool = false
var notes: String = ""


func validate() -> String:
	if name == "":
		return "Animation has no name"
	if sheet_columns <= 0 or sheet_rows <= 0:
		return "Sheet Columns / Sheet Rows must be positive"
	if row < 0 or row >= sheet_rows:
		return "Row %d is outside the sheet (0 to %d)" % [row, sheet_rows - 1]
	if first_frame < 0 or first_frame >= sheet_columns:
		return "First Frame %d is outside the sheet (0 to %d)" % [first_frame, sheet_columns - 1]
	if frames <= 0:
		return "Frames must be at least 1"
	if first_frame + frames > sheet_columns:
		return "First Frame %d + Frames %d runs off the end of the row (max %d)" \
			% [first_frame, frames, sheet_columns]
	if fps <= 0.0:
		return "FPS must be greater than 0"
	return ""


func duration() -> float:
	return float(frames) / maxf(fps, 0.001)


## The cell rectangle for step `index` (0-based) within this animation.
func cell_rect(index: int, texture_size: Vector2) -> Rect2:
	var frame_w := texture_size.x / float(sheet_columns)
	var frame_h := texture_size.y / float(sheet_rows)
	var column := first_frame + clampi(index, 0, frames - 1)
	return Rect2(column * frame_w, row * frame_h, frame_w, frame_h)


func describe() -> String:
	return "%s%s: row %d, frames %d-%d @ %.0f fps%s" % [
		name,
		"" if unit_type == "" else " (" + unit_type + ")",
		row, first_frame, first_frame + frames - 1, fps,
		" looping" if loop else ""]
