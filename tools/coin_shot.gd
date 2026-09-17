extends SceneTree

# =============================================================
#  SCREENSHOTS OF THE NUMBER GUESS
#
#  Opens the clash screen on its own, calls a number, lets the coin land and
#  saves the screen at each step. It exists because the clash only appears
#  several minutes into a real match, after a draft and a relay — which is a
#  long way to walk to find out that a button is off the bottom of the screen.
#
#      xvfb-run godot --rendering-driver opengl3 --resolution 1920x1080 \
#          --script res://tools/coin_shot.gd
#
#  A tool, not part of the game. Nothing loads it.
# =============================================================

var _shot := 0
var _clash: CoinClash


func _initialize() -> void:
	await process_frame
	var db := CardDatabase.get_db()

	_clash = CoinClash.make(db)
	root.add_child(_clash)
	await process_frame
	await process_frame

	_snap("opened")
	_clash.start()
	await _wait(0.4)
	_snap("asking")

	# Call seven. Theirs is always drawn from the nine we did not call, so the
	# two can never be the same number.
	_clash._pick(7)
	for i in 6:
		await _wait(0.45)
		_snap("spin-%d" % i)

	# Whoever called closer now chooses. If it was not us, the screen has
	# already moved on by itself and _choose does nothing.
	_clash._choose(true)
	for i in 3:
		await _wait(0.5)
		_snap("chosen-%d" % i)

	# ============ THE EXACT CALL ============
	#
	# Naming the coin is a one-in-ten event, so waiting for one to happen by
	# itself is not a test. The celebration is played on purpose here and
	# photographed, which is the only way to know it draws.
	_clash.start()
	await _wait(0.3)
	_clash._picked = 4
	_clash._landed = 4
	_clash._coin.text = "4"
	_clash._title.text = "CALLED IT!"
	_clash._celebrate(true)
	for i in 4:
		await _wait(0.16)
		_snap("exact-%d" % i)

	print("[coin] done")
	quit(0)


func _wait(seconds: float) -> void:
	await create_timer(seconds, true, false, true).timeout


func _snap(label: String) -> void:
	var view := root.get_viewport()
	if view == null:
		return
	var picture := view.get_texture().get_image()
	if picture == null:
		return
	var path := "user://c_%02d_%s.png" % [_shot, label]
	_shot += 1
	picture.save_png(path)
	print("[coin] %s" % path.get_file())
