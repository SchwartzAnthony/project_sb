extends SceneTree

# =============================================================
#  IS THE CLOCK STILL STRAIGHT?
#
#  The slow-motion dips in Juice.csv used to leave Engine.time_scale
#  permanently low when two of them overlapped, and it compounded every hit
#  until the game was a slideshow. This fires every slow-motion moment the
#  spreadsheet has, in overlapping bursts, and checks that the clock always
#  comes back to 1.0.
#
#      godot --headless --script res://tools/clock_check.gd
#
#  If it ever prints STUCK, that bug is back. It is a tool, not part of the
#  game, and nothing loads it.
# =============================================================

const BURSTS := 40


func _initialize() -> void:
	await process_frame
	var db := CardDatabase.get_db()
	JuiceDB.get_db()

	var holder := Node2D.new()
	root.add_child(holder)
	await process_frame

	var moments: Array[String] = []
	for name in JuiceDB.MOMENTS:
		for row in JuiceDB.rows_for(name):
			if float((row as Dictionary)["slowmo"]) > 0.0:
				moments.append(name)
				break
	print("moments that dip the clock: %s" % ", ".join(moments))
	if moments.is_empty():
		print("nothing dips — nothing to check.")
		quit(0)
		return

	var worst := 1.0
	var stuck := 0

	for i in BURSTS:
		# OVERLAPPING ON PURPOSE. Three dips started a frame apart is exactly
		# the shape that used to break it: the first to finish put back 1.0
		# and the last put back the slowed value it had found.
		for m in moments:
			Juice.fire(holder, m, {"node": holder, "amount": 6, "average": 6.0})
			await process_frame
		worst = minf(worst, Engine.time_scale)

		# Wait for the longest dip to be well and truly over.
		await create_timer(1.0, true, false, true).timeout
		if not is_equal_approx(Engine.time_scale, 1.0):
			stuck += 1
			print("  burst %d left the clock at %.4f" % [i, Engine.time_scale])

	print("")
	print("slowest the clock got mid-dip: %.3f  (that part is meant to happen)" % worst)
	if stuck == 0:
		print("CLOCK IS STRAIGHT after all %d bursts." % BURSTS)
	else:
		print("STUCK after %d of %d bursts — the dip bug is back." % [stuck, BURSTS])

	# And the belt-and-braces path.
	Engine.time_scale = 0.05
	Juice.release()
	print("release() from 0.05 -> %.3f" % Engine.time_scale)
	GameSpeed.set_speed(4.0)
	print("GameSpeed 4x -> %.3f" % Engine.time_scale)
	GameSpeed.reset()
	print("GameSpeed reset -> %.3f  (db had %d tuning rows)"
		% [Engine.time_scale, db.tuning.size()])
	quit(0)
