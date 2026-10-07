extends SceneTree

# =============================================================
#  THE LINE-UP ON THE GRASS, FILMED  (round AN)
#
#  Starts a friendly, presses START on the VS screen and saves a frame of
#  the line-up pan every few frames, for a GIF:
#
#      godot --rendering-driver opengl3 --resolution 1920x1080 \
#          --path . --script res://tools/line_up_shot.gd
#
#      user://line_up/f_000.png ...    then tools/make_gif.py
#
#  A tool, not part of the game. Nothing loads it.
# =============================================================

## Frames per second of GAME time in the GIF. The game is slowed down while
## filming so saving a picture never makes it skip.
const GIF_FPS := 12.0
const SLOW := 0.2

func _initialize() -> void:
	seed(20260922)
	await process_frame
	_pick_a_team()
	MatchMode.choose(self, "friendly")
	change_scene_to_file("res://src/formations/main_scene.tscn")
	var sheet = null
	for i in 300:
		await create_timer(0.2, true, false, true).timeout
		if current_scene == null:
			continue
		sheet = current_scene.get("_sheet")
		if sheet != null and is_instance_valid(sheet) and bool(sheet.get("_opened")):
			break
		sheet = null
	if sheet == null:
		print("[lineup] the VS screen never opened")
		quit(1)
		return
	await create_timer(0.5, true, false, true).timeout
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://line_up"))
	var shown := 0
	_shoot(shown)
	shown += 1
	Engine.time_scale = SLOW
	sheet.call("_go")
	var frame := 0
	var since := 0.0
	for i in 20000:
		await process_frame
		frame += 1
		since += _game_delta()
		var parade := current_scene.get_node_or_null("LineUpParade")
		if parade == null and frame > 30:
			break
		if since >= 1.0 / GIF_FPS:
			since = 0.0
			_shoot(shown)
			shown += 1
	Engine.time_scale = 1.0
	print("[lineup] %d frame(s) in %s" % [shown, ProjectSettings.globalize_path("user://line_up")])
	quit(0)


var _last_ticks := 0


## Game seconds since the last call (real time x the slow-down).
func _game_delta() -> float:
	var now := Time.get_ticks_usec()
	var gone := 0.0 if _last_ticks == 0 else float(now - _last_ticks) / 1000000.0
	_last_ticks = now
	return gone * Engine.time_scale


func _shoot(index: int) -> void:
	if DisplayServer.get_name() == "headless":
		return
	root.get_texture().get_image().save_png("user://line_up/f_%03d.png" % index)


func _pick_a_team() -> void:
	var db := CardDatabase.get_db()
	# A CLASS WHOSE STARS ACTUALLY DO SOMETHING. The first class with a Star
	# is usually the journeymen, whose sheet is six lines of "None" — which
	# proves the None case and nothing else. This prefers a class with a real
	# ability on it, so the picture shows a long sentence wrapping under a tag.
	var wanted := ""
	var fallback := ""
	for card in db.players:
		if not card.is_star():
			continue
		if fallback == "":
			fallback = card.unit_type
		if String(card.active_attack_ability()).strip_edges() != "" \
				or String(card.active_defend_ability()).strip_edges() != "":
			wanted = card.unit_type
			break
	if wanted == "":
		wanted = fallback
	if wanted == "":
		return
	var roster := db.roster_for_class(wanted)
	var picked := TeamSelection.new()
	picked.unit_type = wanted
	picked.star_tier = db.star_tier_for_class(wanted)
	var stars := db.stars_for_class(wanted)
	picked.star_bundle = stars
	picked.active_star = stars[0] if not stars.is_empty() else null
	for tier in TierLadder.TIERS:
		if tier == picked.star_tier:
			continue
		picked.regulars[tier] = TierLadder.build(roster, tier, db, false)["cards"]
	TeamSelection.store(self, picked)


