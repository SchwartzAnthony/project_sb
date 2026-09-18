extends SceneTree

# =============================================================
#  DOES ANYBODY END UP OFF THE GRASS?
#
#  A knocked-out player lies down, and lying down makes them a completely
#  different shape: turned a quarter-turn, a sprite that was thirty pixels
#  wide and a hundred tall is a hundred wide and thirty tall. So somebody
#  standing legally in the top row of the running shape could lie down and
#  reach ninety pixels further up — off the band and onto the black.
#
#  This puts a player in every row, knocks each one over, and checks that the
#  whole body is still inside the lane. It is the sort of thing a screenshot
#  only catches if you happen to take it at the right moment.
#
#      godot --headless --script res://tools/lane_check.gd
#
#  A tool, not part of the game. Nothing loads it.
# =============================================================


func _initialize() -> void:
	await process_frame
	var db := CardDatabase.get_db()
	if db.players.is_empty():
		print("[lane] no cards loaded")
		quit(1)
		return

	var top := db.tune_float("adventure_lane_top", 215.0)
	var height := db.tune_float("adventure_lane_height", 600.0)
	var bottom := top + height
	var rows := maxi(1, db.tune_int("adventure_party_rows", 5))
	print("[lane] band %.0f to %.0f, %d rows" % [top, bottom, rows])

	var holder := Node2D.new()
	root.add_child(holder)

	var bad := 0
	for seat in rows:
		for lying in [false, true]:
			var walker := AdventureWalker.new()
			holder.add_child(walker)
			walker.setup(db.players[seat % db.players.size()], 200.0, db)
			walker.lane_top = top
			walker.lane_bottom = bottom
			# The same y the running shape would give this seat.
			walker.position = Vector2(300.0,
				top + 52.0 + float(seat) * (height - 104.0) / float(rows))
			walker.target = walker.position
			if lying:
				walker.lie_down()
			await process_frame

			var edge: Dictionary = walker.call("_edges")
			var body_top := walker.position.y + float(edge["top"])
			var body_low := walker.position.y + float(edge["bottom"])
			var ok := body_top >= top - 1.0 and body_low <= bottom + 1.0
			if not ok:
				bad += 1
			print("[lane] row %d %-8s body %.0f to %.0f   %s" % [
				seat, "lying" if lying else "standing", body_top, body_low,
				"ok" if ok else "OFF THE GRASS"])
			walker.queue_free()

	if bad > 0:
		print("[lane] %d off the grass." % bad)
		quit(1)
		return
	print("[lane] everybody stays on the grass, standing and lying.")
	quit(0)
