class_name CardRunner
extends TextureRect

## One row of a pitch sheet played on a loop: the player running on his beer
## mat card (BeerMatCard). Each card keeps its own clock, started at a random
## frame, so a row of cards does not run in step.

var _atlas := AtlasTexture.new()
var _cell := 72.0
var _row := 0
var _frames := 1
var _fps := 14.0
var _time := 0.0


func setup(sheet: Texture2D, cell: float, row: int, frames: int, fps: float) -> void:
	_atlas.atlas = sheet
	_cell = cell
	_row = row
	_frames = maxi(1, frames)
	_fps = fps
	_time = randf() * float(_frames) / maxf(_fps, 0.1)
	texture = _atlas
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_show(0)


func _process(delta: float) -> void:
	if _fps <= 0.0 or _frames < 2:
		return
	_time += delta
	_show(int(_time * _fps) % _frames)


func _show(frame: int) -> void:
	_atlas.region = Rect2(frame * _cell, _row * _cell, _cell, _cell)
