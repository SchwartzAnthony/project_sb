extends SceneTree

# =============================================================
#  THE MOVEMENT PROBE  (round AN, 8 Oct - "players facing, walking, running")
#
#  Plays a friendly on AUTO and, every physics frame of open play, writes
#  down for every player: where they look, how fast they move, what job the
#  match gave them and how far the ball is. Then prints, per Tier and side:
#
#    facing away    % of the time a player NOT going for the ball has the
#                   ball behind him (90 degrees or more off where he looks)
#    far sprint    % of the time a player moves faster than 1.35x his walk
#                   while the ball is outside his range
#    turns/s        how often his facing changes (flicker = glitching)
#    stood          % of the time he stands dead still
#
#      godot --headless --path . --script res://tools/movement_probe.gd
#
#  PROBE_SECONDS (default 40) is how much open play to measure.
#  PROBE_FILM=1 (with a real window, e.g. xvfb-run and --rendering-driver
#  opengl3) also saves a frame every 0.2 s to user://movement_film/ for a GIF,
#  and PROBE_OVERLAY=1 turns the Z zone map on while it films.
#
#  It also prints who ran AWAY from the ball, by job; PROBE_WHY=1 splits
#  that by cause (the target was further away / a push / a fresh spot).
#
#  A tool, not part of the game. Nothing loads it.
# =============================================================

var _stats := {}
## Crowding: per frame, how many stand near the ball and how many go for it.
var _crowd := {"frames": 0, "near_sum": 0, "near_max": 0, "chasers_sum": 0,
	"chasers_max": 0, "piles": 0}
const NEAR := 140.0
## Running AWAY from the ball, by job: seconds a player moved faster than a
## stroll with the ball behind his direction of travel. And how much of that
## was toward a touchline or an end line.
var _away_by_role := {}
## Who is within 240 px of the ball, by job, summed over frames.
var _near_role := {}
var _traced := 0
var _away_to_edge := {}
const ROLE_WORDS := ["HOLD", "MARK", "OPEN", "PRESS", "BALL", "RECEIVE", "DRIBBLE", "SURGE", "RECOVER"]
var _film := false
var _dir := "user://movement_film"


func _initialize() -> void:
	seed(20261008)
	await process_frame
	var db := CardDatabase.get_db()
	db.tuning[CardDatabase._normalise("choice_window_seconds")] = "1"
	var seconds := float(OS.get_environment("PROBE_SECONDS")) \
		if OS.get_environment("PROBE_SECONDS") != "" else 40.0
	_film = OS.get_environment("PROBE_FILM") == "1"
	_pick_a_team()
	MatchMode.choose(self, "friendly", false)
	if _film:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))
		for f in DirAccess.get_files_at(_dir):
			DirAccess.remove_absolute(_dir + "/" + f)
	change_scene_to_file("res://src/formations/main_scene.tscn")

	var scene: Node = null
	var pressed := false
	for i in 400:
		await create_timer(0.2, true, false, true).timeout
		scene = current_scene
		if scene == null:
			continue
		var sheet = scene.get("_sheet")
		if not pressed:
			if sheet != null and is_instance_valid(sheet) and bool(sheet.get("_opened")):
				sheet.call("_go")
				pressed = true
			continue
		var parade := scene.find_child("LineUpParade", true, false)
		if parade != null:
			parade.call("skip")
			continue
		if int(scene.get("current_state")) == 1:   # PLAYING
			break
	if scene == null or not pressed:
		print("[probe] the match never opened")
		quit(1)
		return

	MatchHUD.set_auto_pick(scene.get("state"), true)
	if scene.has_method("_on_auto_pick_changed"):
		scene.call("_on_auto_pick_changed", true)
	GameSpeed.set_speed(1.0)
	if OS.get_environment("PROBE_OVERLAY") == "1":
		var overlay = scene.get("zone_overlay")
		if overlay != null:
			overlay.detail = true
			overlay.visible = true

	var measured := 0.0
	var since_shot := 0.0
	var shot := 0
	var last_dir := {}
	while measured < seconds and is_instance_valid(scene):
		await physics_frame
		var dt := 1.0 / float(Engine.physics_ticks_per_second)
		# Only open play: not the draft, not a Play Maker, not a talk box.
		if int(scene.get("current_state")) != 1 or PlayerUnit.play_maker_live:
			continue
		measured += dt
		var ball = scene.get("ball")
		var zones = scene.get("zones")
		var reach: float = zones.play.size.y * float(scene.get("press_radius_fraction")) \
			if zones != null else 300.0
		for unit in scene.call("_all_units"):
			_sample(unit, ball, reach, dt, last_dir)
		_count_crowd(scene.call("_all_units"), ball)
		if ball != null and is_instance_valid(ball):
			if ball.has_meta("probe_at"):
				ball.set_meta("probe_step", ball.global_position - ball.get_meta("probe_at"))
			ball.set_meta("probe_at", ball.global_position)
		if _film:
			since_shot += dt
			if since_shot >= 0.2:
				since_shot = 0.0
				root.get_texture().get_image().save_png("%s/f_%03d.png" % [_dir, shot])
				shot += 1
	_report(measured)
	quit(0)


func _sample(unit: PlayerUnit, ball, reach: float, dt: float, last_dir: Dictionary) -> void:
	var tier := unit.data.get_tier_clean() if unit.data != null else "?"
	var key := "%s %s" % ["THEM" if unit.is_enemy else "YOU ", tier]
	if not _stats.has(key):
		_stats[key] = {"t": 0.0, "free": 0.0, "away": 0.0, "far_sprint": 0.0,
			"turns": 0, "stood": 0.0, "out": 0.0, "spot": 0.0, "grouped": 0.0, "n": {}}
	var s: Dictionary = _stats[key]
	s["n"][unit.get_instance_id()] = true
	s["t"] += dt
	var id := unit.get_instance_id()
	var facing := int(unit.get("_dir"))
	if last_dir.has(id) and last_dir[id] != facing:
		s["turns"] += 1
	last_dir[id] = facing
	var speed := 0.0
	if unit.has_meta("probe_prev"):
		speed = (unit.global_position - unit.get_meta("probe_prev")).length() / dt
		unit.set_meta("probe_step", unit.global_position - unit.get_meta("probe_prev"))
	unit.set_meta("probe_prev", unit.global_position)
	if speed < 2.0:
		s["stood"] += dt
	# RUNNING ON THE SPOT: legs going (over 15 px/s) but under 25 px of real
	# ground made over the last second - leaning into an invisible wall.
	var hist: Array = unit.get_meta("probe_hist") if unit.has_meta("probe_hist") else []
	hist.append(unit.global_position)
	if hist.size() > int(1.0 / dt):
		hist.pop_front()
	unit.set_meta("probe_hist", hist)
	if speed > 15.0 and hist.size() >= int(1.0 / dt) \
			and (hist[0] as Vector2).distance_to(unit.global_position) < 25.0:
		s["spot"] += dt
		if OS.get_environment("PROBE_WHY") == "1":
			var word: String = ROLE_WORDS[clampi(unit.role, 0, ROLE_WORDS.size() - 1)]
			var tgt: float = unit.role_target.distance_to(unit.global_position)
			var zf: Vector2 = unit.call("_zone_force") * unit.zone_pull
			var sep: Vector2 = unit.call("_separation") * unit.separation_strength
			var back := unit.home_position - unit.global_position
			var slot := back.length() > unit.leash
			var cause := "zone" if zf.length() > 0.3 else ("crowd" if sep.length() > 0.3 else ("slot" if slot else ("resting" if float(unit.get("_rest_left")) > 0.0 else "?")))
			var k := "ON SPOT %s target %s %s" % [word, "far" if tgt > 40.0 else "near", cause]
			if _traced < 3 and word == "OPEN" and tgt > 40.0 and not unit.has_meta("traced"):
				unit.set_meta("traced", true)
				_traced += 1
				var pts := []
				for i in range(0, hist.size(), 6):
					pts.append("(%d,%d)" % [int(hist[i].x), int(hist[i].y)])
				print("[trace] %s at %s target %s rest %.2f roam %s spd %.0f path %s" % [unit.data.player_name,
					unit.global_position, unit.role_target, float(unit.get("_rest_left")),
					unit.is_roaming, speed, " ".join(pts)])
			_away_by_role[k] = _away_by_role.get(k, 0.0) + dt
			_away_to_edge[k] = 0.0
	# GROUPED: a team-mate within 70 px while the ball is far away.
	if ball != null and is_instance_valid(ball) \
			and unit.global_position.distance_to(ball.global_position) > 300.0:
		for other in unit.get_parent().get_children():
			var mate := other as PlayerUnit
			if mate != null and mate != unit and mate.is_enemy == unit.is_enemy \
					and mate.global_position.distance_to(unit.global_position) < 70.0:
				s["grouped"] += dt
				break
	if ball != null and is_instance_valid(ball) and speed > 25.0 and unit.has_meta("probe_step"):
		var step: Vector2 = unit.get_meta("probe_step")
		var to_ball: Vector2 = ball.global_position - unit.global_position
		if to_ball.length() > 60.0 and step.normalized().dot(to_ball.normalized()) < -0.5:
			var word: String = ROLE_WORDS[clampi(unit.role, 0, ROLE_WORDS.size() - 1)]
			_away_by_role[word] = _away_by_role.get(word, 0.0) + dt
			var bounds: Rect2 = unit.play_bounds
			var edge := 0.0
			if bounds.size.x > 1.0:
				var to_side := minf(unit.global_position.y - bounds.position.y, bounds.end.y - unit.global_position.y)
				var to_end := minf(unit.global_position.x - bounds.position.x, bounds.end.x - unit.global_position.x)
				if to_side < bounds.size.y * 0.25 or to_end < bounds.size.x * 0.12:
					edge = dt
			_away_to_edge[word] = _away_to_edge.get(word, 0.0) + edge
			if OS.get_environment("PROBE_WHY") == "1":
				var why := "fresh" if unit.fresh_left > 0.0 else "target"
				var tgt_far: bool = unit.role_target.distance_to(ball.global_position) \
					> unit.global_position.distance_to(ball.global_position) + 20.0
				if not tgt_far:
					why = "push"   # the target is not further away: separation / zone / slot pulls
				var bm: Vector2 = ball.get_meta("probe_step") if ball.has_meta("probe_step") else Vector2.ZERO
				if bm.length() / dt > 150.0:
					why += "+ball_flying"
				var k := word + " " + why
				_away_by_role[k] = _away_by_role.get(k, 0.0) + dt
				_away_to_edge[k] = _away_to_edge.get(k, 0.0)
	if unit.tier_zone.size.x > 1.0 and (unit.global_position.x < unit.tier_zone.position.x \
			or unit.global_position.x > unit.tier_zone.end.x):
		s["out"] += dt
	if ball == null or not is_instance_valid(ball):
		return
	var gap: Vector2 = ball.global_position - unit.global_position
	var chasing: bool = bool(unit.call("_is_chasing"))
	if not chasing:
		s["free"] += dt
		var want: int = PitchSprite.direction_of(
			unit.get_canvas_transform().basis_xform(gap), unit.call("_squash"))
		if want >= 0 and gap.length() > unit.face_deadzone:
			var off := absi(posmod(facing - want + 4, 8) - 4)
			if off >= 2:
				s["away"] += dt
	if gap.length() > reach and speed > unit.walk_speed * 1.35:
		s["far_sprint"] += dt


func _count_crowd(units: Array, ball) -> void:
	if ball == null or not is_instance_valid(ball):
		return
	var near := 0
	var chasers := 0
	var wide := 0
	for unit in units:
		if unit.global_position.distance_to(ball.global_position) < 240.0:
			wide += 1
			var word: String = ROLE_WORDS[clampi(unit.role, 0, ROLE_WORDS.size() - 1)]
			_near_role[word] = _near_role.get(word, 0) + 1
		if unit.global_position.distance_to(ball.global_position) < NEAR:
			near += 1
		if unit.role == PlayerUnit.Role.BALL or unit.role == PlayerUnit.Role.PRESS:
			chasers += 1
	_crowd["frames"] += 1
	_crowd["near_sum"] += near
	_crowd["near_max"] = maxi(_crowd["near_max"], near)
	_crowd["chasers_sum"] += chasers
	_crowd["chasers_max"] = maxi(_crowd["chasers_max"], chasers)
	if near >= 6:
		_crowd["piles"] += 1
	_crowd["wide_sum"] = _crowd.get("wide_sum", 0) + wide


func _report(measured: float) -> void:
	var total := 0.0
	for word in _away_by_role:
		total += _away_by_role[word]
	print("[probe] running away from the ball: %.1f player-seconds in all" % total)
	for word in _away_by_role:
		print("[probe]   %-8s %5.1f s  (%.0f%% of it near a touchline or end line)" % [word,
			_away_by_role[word], 100.0 * _away_to_edge[word] / maxf(_away_by_role[word], 0.001)])
	var f: float = maxf(1.0, float(_crowd["frames"]))
	print("[probe] near the ball (%d px): %.1f on average, %d at worst, 6+ for %.0f%% of the time" % [
		int(NEAR), _crowd["near_sum"] / f, _crowd["near_max"], 100.0 * _crowd["piles"] / f])
	print("[probe] within 240 px of the ball: %.1f on average (of the whole pitch)" % [
		_crowd.get("wide_sum", 0) / f])
	var who := []
	for word in _near_role:
		who.append("%s %.1f" % [word, _near_role[word] / f])
	print("[probe]   of them: %s" % ", ".join(who))
	print("[probe] going for it (BALL/PRESS): %.1f on average, %d at worst" % [
		_crowd["chasers_sum"] / f, _crowd["chasers_max"]])
	print("[probe] %.1f s of open play measured" % measured)
	print("[probe] %-9s %3s  %12s  %10s  %8s  %6s  %9s  %8s  %8s" % ["who", "n", "facing away", "far sprint", "turns/s", "stood", "off zone", "on spot", "grouped"])
	var keys := _stats.keys()
	keys.sort()
	var worst_away := 0.0
	for key in keys:
		var s: Dictionary = _stats[key]
		var t: float = maxf(s["t"], 0.001)
		var n: int = s["n"].size()
		var away: float = 100.0 * s["away"] / maxf(s["free"], 0.001)
		worst_away = maxf(worst_away, away)
		print("[probe] %-9s %3d  %11.0f%%  %9.0f%%  %8.2f  %5.0f%%  %8.0f%%  %7.0f%%  %7.0f%%" % [key, n, away,
			100.0 * s["far_sprint"] / t, float(s["turns"]) / t / maxf(n, 1), 100.0 * s["stood"] / t,
			100.0 * s["out"] / t, 100.0 * s["spot"] / t, 100.0 * s["grouped"] / t])
	print("[probe] worst facing-away: %.0f%%" % worst_away)


func _pick_a_team() -> void:
	var db := CardDatabase.get_db()
	var wanted := ""
	for card in db.players:
		if card.is_star():
			wanted = card.unit_type
			break
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
