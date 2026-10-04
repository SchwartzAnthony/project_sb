class_name PitchEngines
extends Node2D

# =============================================================
#  THE CLASS ENGINES ON THE PITCH  (round AD, phase C6)
#
#  The cards of three classes talk about things that happen ON THE GRASS,
#  not on the cards. This node watches the grass and tells the ability
#  engine what it saw - once at every PLAY MAKER - and draws what the
#  abilities put there.
#
#  ============ 1. WHO TOUCHED THE BALL (Unkengeister) ============
#
#  "If this touched the ball before PLAY MAKER" (ruling R13): every unit that
#  had the ball in OPEN play since the last PLAY MAKER. Its draft card says
#  TOUCHED, so you can pick it on purpose. A COLD TOUCH turns the ball icy
#  blue until the next PLAY MAKER.
#
#  ============ 2. GRAVESTONES (Unkengeister) ============
#
#  "Summon a gravestone on the field": a stone appears where that unit is
#  standing and stays for the match (your Q058 - only an Emblem's would go
#  with the Emblem). They count for Caim's Emblem and for "objects on the
#  field" (Glasya-Labolas). `gravestone_max` in Tuning.csv.
#
#  ============ 3. MINES (Bergmännlein) ============
#
#  data/Mines.csv says where the mines are (your Q091: one per zone, at the
#  side of the field). A side gets its mines if it has at least one EARTH
#  unit (`mines_need_earth`). An earth unit that comes within `mine_reach`
#  pixels of one of its side's mines during waiting play is MINING: its draft
#  card says MINING and "If another unit is mining" is true. At every PLAY
#  MAKER each mine that was worked gives its side `mine_ore_per_round` Ore
#  (your Q055: per mine, per round). Earth units with nothing to do drift to
#  their mines (`mine_pull`).
#
#  ============ 4. THE BENCH (Feuergeister fusing) ============
#
#  "Fuses itself with a Tier III fire unit from outside of the game" -
#  outside the game is the BENCH: at most `bench_size` (3) cards of your
#  class that are not in your team, and you choose them (ruling R08) at the
#  first PLAY MAKER - only if a card of yours can fuse. The AI's bench is
#  its strongest three.
# =============================================================

const MINES_FILE := "res://data/Mines.csv"

var scene: Node = null          # main_scene
var db: CardDatabase = null

## side -> {PlayerData: true}, since the last PLAY MAKER.
var _touched := {false: {}, true: {}}
var _mined := {false: {}, true: {}}
## side -> {mine index: true} - the mines worked since the last PLAY MAKER.
var _worked := {false: {}, true: {}}
## [{pos: Vector2, side: bool}]
var mine_spots: Array = []
## [{pos: Vector2, side: bool}]
var stones: Array = []
## ROUND AE (C7, Valefor): ore counters the crater dropped. [{pos, side}]
var nuggets: Array = []
var craters := {false: false, true: false}
var _bench_done := false
var _engine: AbilityEngine = null
var _terrified_once := {false: false, true: false}
var _cold := false


static func open(on: Node, database: CardDatabase) -> PitchEngines:
	var made := PitchEngines.new()
	made.name = "PitchEngines"
	made.scene = on
	made.db = database
	made.z_index = 1
	on.add_child(made)
	return made


# =============================================================
#  WATCHING THE GRASS - every physics frame, from main_scene
# =============================================================

func tick(ball: Node, units: Array, open_play: bool) -> void:
	if ball == null:
		return
	if open_play and not bool(ball.get("scripted_possession")):
		var carrier = ball.get("carrier")
		if carrier != null and is_instance_valid(carrier):
			var u := carrier as PlayerUnit
			if u != null and u.data != null:
				(_touched[u.is_enemy] as Dictionary)[u.data] = true
	if not open_play:
		return
	_pick_up_nuggets(units)
	_ball_knocks_stones(ball)
	if mine_spots.is_empty():
		return
	var reach := db.tune_float("mine_reach", 120.0)
	for thing in units:
		var unit := thing as PlayerUnit
		if unit == null or unit.data == null or not _can_mine(unit.data):
			continue
		for i in mine_spots.size():
			var spot: Dictionary = mine_spots[i]
			if bool(spot["side"]) != unit.is_enemy:
				continue
			if unit.global_position.distance_to(spot["pos"]) <= reach:
				(_mined[unit.is_enemy] as Dictionary)[unit.data] = true
				(_worked[unit.is_enemy] as Dictionary)[i] = true


func _can_mine(card: PlayerData) -> bool:
	if not db.tune_bool("mine_earth_only", true):
		return true
	return CardDatabase._normalise(card.active_element()) == "earth"


## Where an earth unit with nothing to do would like to stand: its side's
## nearest mine, or INF.
func mine_for(unit: PlayerUnit) -> Vector2:
	if unit == null or unit.data == null or not _can_mine(unit.data):
		return Vector2.INF
	var best := Vector2.INF
	var best_d := INF
	# Valefor's ore counters first - they are worth walking for.
	for n in nuggets:
		if bool(n["side"]) != unit.is_enemy:
			continue
		var dn := unit.global_position.distance_to(n["pos"]) * 0.5
		if dn < best_d:
			best_d = dn
			best = n["pos"]
	for spot in mine_spots:
		if bool(spot["side"]) != unit.is_enemy:
			continue
		var d := unit.global_position.distance_to(spot["pos"])
		if d < best_d:
			best_d = d
			best = spot["pos"]
	return best


# =============================================================
#  AT EVERY PLAY MAKER - tell the engine what happened
# =============================================================

func at_play_maker(abilities: AbilityEngine) -> void:
	if abilities == null:
		return
	_engine = abilities
	for side in [false, true]:
		if abilities.has_emblem(side, "Valefor"):
			_drop_ore(side)
	for side in [false, true]:
		abilities.set_touched(side, (_touched[side] as Dictionary).keys())
		var count := 0
		for spot in mine_spots:
			if bool(spot["side"]) == side:
				count += 1
		abilities.set_mining(side, (_mined[side] as Dictionary).keys(), count)
		var worked := (_worked[side] as Dictionary).size()
		# C8 (Glasya-Labolas's Ultimate, the OTHER side's): one of the objects
		# they used is possessed - they are terrified and get nothing from it,
		# once per PLAY MAKER.
		if worked > 0 and abilities.ultimate_up(not side, "Glasya-Labolas"):
			worked -= 1
			print("[glasya] a possessed mine terrifies the %s side - no Ore from it" % ("away" if side else "home"))
		var per := db.tune_int("mine_ore_per_round", 1)
		if worked > 0 and per > 0:
			var miner: PlayerData = null
			for c in (_mined[side] as Dictionary).keys():
				miner = c as PlayerData
				break
			abilities.mine_ore(side, worked * per, worked, miner)
	_touched = {false: {}, true: {}}
	_mined = {false: {}, true: {}}
	_worked = {false: {}, true: {}}
	_terrified_once = {false: false, true: false}
	if _cold:
		_cold = false
		_tint_ball(false)


## What the abilities put on the pitch since the last look.
func absorb(abilities: AbilityEngine) -> void:
	if abilities == null:
		return
	_engine = abilities
	if abilities.take_cold_touch():
		_cold = true
		_tint_ball(true)
	for stone in abilities.take_gravestones():
		var at := Vector2.ZERO
		var body: PlayerUnit = scene.call("unit_for_card", stone["by"], bool(stone["side"]))
		if body != null:
			at = body.global_position + Vector2(randf_range(-30, 30), randf_range(10, 40))
		else:
			at = (scene.call("get_play_rect") as Rect2).get_center()
		stones.append({"pos": at, "side": bool(stone["side"])})
		queue_redraw()


func _tint_ball(on: bool) -> void:
	var ball = scene.get("ball")
	if ball == null or not is_instance_valid(ball):
		return
	(ball as CanvasItem).modulate = Color(0.55, 0.85, 1.0) if on else Color(1, 1, 1)


# =============================================================
#  CAIM'S ULTIMATE (round AF, C8)
#
#  "Spawn gravestones onto the soccer field; when the soccer ball knocks them
#  over, spawn a ghost attaching it to the ball. The next Unkengeister gets +1
#  power for each ghost counter on the ball." When Caim's Ultimate comes up,
#  `caim_stones` gravestones appear; the ball rolling within `caim_knock_reach`
#  of one knocks it over: +1 ghost on the ball for that side.
# =============================================================

func on_ultimate(side: bool, star_name: String) -> void:
	if CardDatabase._normalise(star_name) != "caim":
		return
	var play: Rect2 = scene.call("get_play_rect")
	var keep := clampf(db.tune_float("edge_keep", 0.10), 0.0, 0.4)
	for i in db.tune_int("caim_stones", 3):
		var at := Vector2(randf_range(play.position.x + play.size.x * 0.2, play.end.x - play.size.x * 0.2),
			randf_range(play.position.y + play.size.y * (keep + 0.05), play.end.y - play.size.y * (keep + 0.05)))
		stones.append({"pos": at, "side": side, "knock": true})
	if scene.has_method("announce"):
		scene.call("announce", "%sCAIM'S GRAVESTONES RISE" % ("THEIR " if side else ""), 1.4)
	queue_redraw()


func _ball_knocks_stones(ball: Node) -> void:
	if _engine == null or stones.is_empty():
		return
	var reach := db.tune_float("caim_knock_reach", 40.0)
	var at: Vector2 = (ball as Node2D).global_position
	for i in range(stones.size() - 1, -1, -1):
		var stone: Dictionary = stones[i]
		if not bool(stone.get("knock", false)):
			continue
		if at.distance_to(stone["pos"]) <= reach:
			stones.remove_at(i)
			var side := bool(stone["side"])
			_engine.ghosts[side] = int(_engine.ghosts[side]) + 1
			print("[caim] the ball knocks a gravestone over - %d ghost(s) on the ball" % int(_engine.ghosts[side]))
			queue_redraw()


# =============================================================
#  VALEFOR'S CRATER (round AE, C7)
#
#  "A crater hits the middle of the soccer field and drops mine counters in
#  different zones. Only your earth players are able to pick them up." At
#  every PLAY MAKER while Valefor's Emblem is on your field the crater tops
#  the ore counters up to `valefor_nuggets`, one in each quarter, on your
#  side of the pitch. An earth unit of yours that runs over one picks it up:
#  +1 Ore (`nugget_reach`). They count for Valefor's Condition.
# =============================================================

func _drop_ore(side: bool) -> void:
	# YOUR Q103: once, when Valefor comes on (`valefor_refill` true tops them
	# up at every PLAY MAKER instead).
	if bool(craters[side]) and not db.tune_bool("valefor_refill", false):
		return
	var want := db.tune_int("valefor_nuggets", 4)
	var have := 0
	for n in nuggets:
		if bool(n["side"]) == side:
			have += 1
	if have >= want:
		return
	var play: Rect2 = scene.call("get_play_rect")
	if not bool(craters[side]):
		craters[side] = true
		if scene.has_method("announce"):
			scene.call("announce", "%sVALEFOR'S CRATER HITS THE PITCH" % ("THEIR " if side else ""), 1.4)
	var keep := clampf(db.tune_float("edge_keep", 0.10), 0.0, 0.4)
	for i in want - have:
		var quarter := (have + i) % 4
		var x := play.position.x + play.size.x * (0.125 + 0.25 * quarter) + randf_range(-60, 60)
		var top := play.position.y + play.size.y * (keep + 0.05)
		var bottom := play.end.y - play.size.y * (keep + 0.05)
		var y := randf_range(lerpf(top, bottom, 0.5), bottom) if not side else randf_range(top, lerpf(top, bottom, 0.5))
		nuggets.append({"pos": Vector2(x, y), "side": side})
	queue_redraw()


func _pick_up_nuggets(units: Array) -> void:
	if nuggets.is_empty() or _engine == null:
		return
	var reach := db.tune_float("nugget_reach", 55.0)
	for thing in units:
		var unit := thing as PlayerUnit
		if unit == null or unit.data == null or not _can_mine(unit.data):
			continue
		for i in range(nuggets.size() - 1, -1, -1):
			var n: Dictionary = nuggets[i]
			if bool(n["side"]) != unit.is_enemy:
				continue
			if unit.global_position.distance_to(n["pos"]) <= reach:
				nuggets.remove_at(i)
				if _engine.ultimate_up(not unit.is_enemy, "Glasya-Labolas") and not bool(_terrified_once[unit.is_enemy]):
					_terrified_once[unit.is_enemy] = true
					print("[glasya] %s is terrified by a possessed ore counter - nothing gained" % unit.data.player_name)
					queue_redraw()
					continue
				_engine.nugget_picked(unit.data, unit.is_enemy)
				print("[valefor] %s picks up an ore counter." % unit.data.player_name)
				queue_redraw()


# =============================================================
#  THE MINES - placed from data/Mines.csv
# =============================================================

func place_mines(player_cards: Array, enemy_cards: Array) -> void:
	mine_spots.clear()
	var play: Rect2 = scene.call("get_play_rect")
	var rows := MenuSupport.read_csv(MINES_FILE)
	for pair in [[player_cards, false], [enemy_cards, true]]:
		var side: bool = pair[1]
		if db.tune_bool("mines_need_earth", true) and not _has_earth(pair[0]):
			continue
		for row in rows:
			# Side: `you` rows are your mines, `them` rows theirs, `both` - each
			# side gets one there.
			var whose := MenuSupport.field(row, "Side", "both").strip_edges().to_lower()
			if (whose == "you" or whose == "home") and side:
				continue
			if (whose == "them" or whose == "away") and not side:
				continue
			var x := clampf(MenuSupport.field_float(row, "Across", 0.5), 0.0, 1.0)
			var y := clampf(MenuSupport.field_float(row, "Down", 0.5), 0.0, 1.0)
			mine_spots.append({"pos": play.position + Vector2(play.size.x * x, play.size.y * y),
				"side": side, "name": MenuSupport.field(row, "Mine")})
	print("[mines] %d mine(s) on the pitch (data/Mines.csv)." % mine_spots.size())
	queue_redraw()


func _has_earth(cards: Array) -> bool:
	for c in cards:
		var card := c as PlayerData
		if card != null and CardDatabase._normalise(card.active_element()) == "earth":
			return true
	return false


# =============================================================
#  THE BENCH - "outside of the game" (R08)
# =============================================================

## The cards of this class that are NOT in the team: who could sit on the
## bench. Fire first and the strongest first, because fusing wants fire.
func bench_candidates(unit_type: String, in_team: Array) -> Array[PlayerData]:
	var out: Array[PlayerData] = []
	for card in db.roster_for_class(unit_type):
		if card.is_star() or in_team.has(card):
			continue
		out.append(card)
	out.sort_custom(func(a: PlayerData, b: PlayerData) -> bool:
		var fa := 10 if CardDatabase._normalise(a.active_element()) == "fire" else 0
		var fb := 10 if CardDatabase._normalise(b.active_element()) == "fire" else 0
		return a.get_attack_power() + fa > b.get_attack_power() + fb)
	return out


## The bench AUTO (and the AI) would pick: first a card for each fuse the team
## can make (Jonas wants a Tier III fire unit...), then the strongest fire.
func auto_bench(unit_type: String, team: Array, size: int) -> Array[PlayerData]:
	var pool := bench_candidates(unit_type, team)
	var out: Array[PlayerData] = []
	for want in fuse_wants(team):
		if out.size() >= size:
			break
		for card in pool:
			if not out.has(card) and AbilityData.card_matches(card, want):
				out.append(card)
				break
	for card in pool:
		if out.size() >= size:
			break
		if not out.has(card):
			out.append(card)
	return out


## What the team's fuse abilities ask for ("fire+iii", ...).
func fuse_wants(cards: Array) -> Array[String]:
	var out: Array[String] = []
	for c in cards:
		var card := c as PlayerData
		if card == null:
			continue
		for cell in [card.active_attack_ability(), card.active_defend_ability()]:
			for piece in String(cell).split(";"):
				var a := db.get_ability(String(piece).strip_edges())
				if a != null and a.effect == "fuse" and not out.has(a.effect_arg):
					out.append(a.effect_arg)
	return out


func team_can_fuse(cards: Array) -> bool:
	for c in cards:
		var card := c as PlayerData
		if card == null:
			continue
		for cell in [card.active_attack_ability(), card.active_defend_ability()]:
			for piece in String(cell).split(";"):
				var a := db.get_ability(String(piece).strip_edges())
				if a != null and a.effect == "fuse":
					return true
	return false


# =============================================================
#  DRAWING
# =============================================================

func _draw() -> void:
	var mine_size := db.tune_float("mine_draw_size", 26.0) if db != null else 26.0
	for spot in mine_spots:
		var p: Vector2 = spot["pos"]
		var rim := Color(0.95, 0.75, 0.3) if not bool(spot["side"]) else Color(0.95, 0.45, 0.4)
		draw_circle(p, mine_size, Color(0.25, 0.17, 0.08, 0.85))
		draw_arc(p, mine_size, 0.0, TAU, 28, rim, 3.0)
		# a pick: two strokes
		draw_line(p + Vector2(-mine_size * 0.5, mine_size * 0.5), p + Vector2(mine_size * 0.5, -mine_size * 0.5), Color(0.85, 0.85, 0.9), 4.0)
		draw_line(p + Vector2(mine_size * 0.15, -mine_size * 0.65), p + Vector2(mine_size * 0.75, -mine_size * 0.05), Color(0.85, 0.85, 0.9), 4.0)
	for side in [false, true]:
		if bool(craters[side]):
			var play: Rect2 = scene.call("get_play_rect")
			var c := play.get_center() + Vector2(0, -40 if side else 40)
			draw_circle(c, 44.0, Color(0.2, 0.14, 0.08, 0.55))
			draw_arc(c, 44.0, 0.0, TAU, 32, Color(0.5, 0.35, 0.2, 0.8), 4.0)
	for n in nuggets:
		var q2: Vector2 = n["pos"]
		var gold := Color(1.0, 0.82, 0.3)
		draw_colored_polygon(PackedVector2Array([q2 + Vector2(0, -12), q2 + Vector2(10, 0), q2 + Vector2(0, 12), q2 + Vector2(-10, 0)]), gold)
		draw_polyline(PackedVector2Array([q2 + Vector2(0, -12), q2 + Vector2(10, 0), q2 + Vector2(0, 12), q2 + Vector2(-10, 0), q2 + Vector2(0, -12)]), Color(0.45, 0.3, 0.05), 2.0)
	for stone in stones:
		var q: Vector2 = stone["pos"]
		var w := 18.0
		var h := 24.0
		var tint := Color(0.62, 0.64, 0.68) if not bool(stone["side"]) else Color(0.55, 0.5, 0.55)
		draw_rect(Rect2(q - Vector2(w * 0.5, h), Vector2(w, h)), tint, true)
		draw_circle(q - Vector2(0, h), w * 0.5, tint)
		draw_line(q - Vector2(0, h + 4), q - Vector2(0, 6), Color(0.25, 0.25, 0.3), 2.5)
		draw_line(q - Vector2(5, h - 6), q - Vector2(-5, h - 6), Color(0.25, 0.25, 0.3), 2.5)
