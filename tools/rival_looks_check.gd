extends SceneTree

# =============================================================
#  THE RIVALS' LOOKS  (Anthony, 24 Oct 2026: "Make the rivals also diverse")
#
#      godot --headless --path . --script res://tools/rival_looks_check.gd
#
#  Builds both tutorial oppositions (EnemyIntroSquad.csv, EnemyIntroSquad2.csv)
#  the way a match does, and prints each Rival's name, gender, card art and
#  the pitch sheet they wear. Fails if a Rival still wears no drawn sheet or
#  a whole side wears the same one. A tool; nothing loads it.
# =============================================================


func _initialize() -> void:
	var db := CardDatabase.get_db()
	var bad := 0
	for file in ["EnemyIntroSquad.csv", "EnemyIntroSquad2.csv"]:
		var side := SquadSheet.selection_from(file, db, null, false)
		if side == null:
			print("[rivals] %s did not build" % file)
			bad += 1
			continue
		var seen := {}
		var cards := side.all_regulars()
		for star in side.star_bundle:
			if star != null and not cards.has(star):
				cards.append(star)
		for card in cards:
			var sheet := PitchSprite.sheet_for(card, hash(card.player_name))
			var sheet_name := sheet.resource_path.get_file() if sheet != null else "(none)"
			seen[sheet_name] = true
			var art := card.artwork.resource_path.get_file() if card.artwork != null else "(none)"
			print("[rivals] %s  %-12s %-28s %s" % [file, card.player_name, art, sheet_name])
			if sheet == null or not sheet_name.begins_with("drawn_"):
				bad += 1
		print("[rivals] %s: %d different looks" % [file, seen.size()])
		if seen.size() < 4:
			bad += 1
	print("[rivals] %s" % ("ok" if bad == 0 else "%d problems" % bad))
	quit(0 if bad == 0 else 1)
