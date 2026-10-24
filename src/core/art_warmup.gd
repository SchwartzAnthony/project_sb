class_name ArtWarmup
extends Node

# =============================================================
#  THE BIG PLAYER PICTURES ARE READY BEFORE THEY ARE NEEDED  (round AN)
#
#  Anthony, 24 Oct: "The game seems to lag ... When the animation comes in
#  for the cards it stalls (like it is loading)."
#
#  It was loading. Every duel shows both players from their sharp duel
#  sheet (assets/players/duel/, 3600 x 2700 each), and the line-up and the
#  drinking window from their sharp window sheet (assets/players/window/).
#  Each one was read from disk, unpacked and measured the moment its window
#  opened: about half a second of frozen screen per duel, and again at the
#  next duel, because nothing kept the sheet once the window closed.
#
#  Now the match, once it is built, hands this node every player on the
#  pitch. It reads their sheets on other threads, all at once, measures the
#  figure in each move (the crop box SpriteAnimator would otherwise work out
#  on the spot), and keeps the sheets until the match closes. A duel, the
#  line-up or a drink then finds everything ready.
#
#  Nothing on screen changes: the same sheets, the same crops, only earlier.
#  main_scene.gd adds this node, and it goes with the match.
# =============================================================

## res:// path -> Texture2D, held for as long as the match is open.
var _held: Dictionary = {}
## res:// paths still being read on another thread.
var _reading: Array[String] = []
## The measuring jobs on WorkerThreadPool, waited for once they are done.
var _tasks: Array[int] = []


## Start reading the duel and window sheets of `cards` (PlayerData). Safe to
## call with anything; cards with no sharp sheets are skipped.
static func warm_match(host: Node, cards: Array) -> ArtWarmup:
	var db := CardDatabase.get_db()
	if host == null or db == null:
		return null
	var keeper := ArtWarmup.new()
	keeper.name = "ArtWarmup"
	host.add_child(keeper)

	# The duel sheets: every move in DuelArena.DUEL_ROWS (duel_arena.gd).
	var duel_folder := db.tune_text("duel_sheets", "res://assets/players/duel/").strip_edges()
	var duel_cell := _cell_of(db.tune_text("duel_cell", "400,540"))
	var duel_moves: Array = []
	for move in DuelArena.DUEL_ROWS:
		var row: Array = DuelArena.DUEL_ROWS[move]
		duel_moves.append([move, int(row[0]), int(row[1])])

	# The window sheets: the line-up's standing figure (line_up_parade.gd).
	var window_folder := "res://assets/players/window/"
	var window_cell := Vector2(336, 460)
	for row in MenuSupport.read_csv("res://data/DrinkWindow.csv"):
		var key := MenuSupport.field(row, "Key").strip_edges()
		if key == "window_sheets":
			window_folder = MenuSupport.field(row, "Value").strip_edges()
		elif key == "window_cell":
			window_cell = _cell_of(MenuSupport.field(row, "Value"))
	var window_moves: Array = [["idle", int(db.tune_float("line_up_sharp_row", 2.0)), 4]]

	var files: Array[String] = []
	for card in cards:
		if not (card is PlayerData):
			continue
		var pitch := PitchSprite.window_sheet(card as PlayerData)
		if pitch != null and not files.has(pitch.resource_path.get_file()):
			files.append(pitch.resource_path.get_file())
	# The line-up comes first, straight after the loading screen, so its
	# sheets are asked for first; the duels come later.
	if window_folder != "":
		for file in files:
			keeper._warm(window_folder.path_join(file), window_cell, window_moves)
	if duel_folder != "":
		for file in files:
			keeper._warm(duel_folder.path_join(file), duel_cell, duel_moves)
	return keeper


static func _cell_of(text: String) -> Vector2:
	var parts := text.split(",")
	if parts.size() != 2:
		return Vector2.ZERO
	return Vector2(float(parts[0]), float(parts[1]))


func _warm(path: String, cell: Vector2, moves: Array) -> void:
	if _held.has(path) or _reading.has(path) or not ResourceLoader.exists(path):
		return
	if ResourceLoader.load_threaded_request(path, "Texture2D") == OK:
		_reading.append(path)
	if cell.x > 0.0 and cell.y > 0.0:
		_tasks.append(WorkerThreadPool.add_task(_measure.bind(path, cell, moves)))


func _process(_delta: float) -> void:
	for task in _tasks.duplicate():
		if WorkerThreadPool.is_task_completed(task):
			WorkerThreadPool.wait_for_task_completion(task)
			_tasks.erase(task)
	for path in _reading.duplicate():
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		_reading.erase(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			_held[path] = ResourceLoader.load_threaded_get(path)
	if _reading.is_empty() and _tasks.is_empty():
		set_process(false)


func _exit_tree() -> void:
	for task in _tasks:
		WorkerThreadPool.wait_for_task_completion(task)
	_tasks.clear()
	for path in _reading:
		if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_LOADED:
			ResourceLoader.load_threaded_get(path)
	_reading.clear()
	_held.clear()


## On a worker thread: the crop box of each move ([name, row, frames]),
## exactly as SpriteAnimator would measure it. Needs the picture file
## itself, which is there whenever the game runs from the project folder;
## without it the window measures on the spot as before.
static func _measure(path: String, cell: Vector2, moves: Array) -> void:
	if not FileAccess.file_exists(path):
		return
	var image := Image.load_from_file(path)
	if image == null or image.is_empty() or image.is_compressed():
		return
	var found: Dictionary = {}
	for move in moves:
		var spec := AnimSpec.new()
		spec.name = String(move[0])
		spec.sheet_columns = maxi(1, int(image.get_width() / cell.x))
		spec.sheet_rows = maxi(1, int(image.get_height() / cell.y))
		spec.row = int(move[1])
		if spec.row >= spec.sheet_rows:
			spec.row = 0
		spec.first_frame = 0
		spec.frames = int(move[2])
		found[SpriteAnimator.crop_key(path, spec)] = SpriteAnimator.scan_crop(image, spec)
	ArtWarmup._store_crops.call_deferred(found)


static func _store_crops(found: Dictionary) -> void:
	for key in found:
		if not SpriteAnimator._crop_cache.has(key):
			SpriteAnimator._crop_cache[key] = found[key]
