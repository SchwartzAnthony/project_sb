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
var _bench_done := false
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
	if mine_spots.is_empty() or not open_play:
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
	if unit == null or unit.data == null or mine_spots.is_empty() or not _can_mine(unit.data):
		return Vector2.INF
	var best := Vector2.INF
	var best_d := INF
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
	for side in [false, true]:
		abilities.set_touched(side, (_touched[side] as Dictionary).keys())
		var count := 0
		for spot in mine_spots:
			if bool(spot["side"]) == side:
				count += 1
		abilities.set_mining(side, (_mined[side] as Dictionary).keys(), count)
		var worked := (_worked[side] as Dictionary).size()
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
	if _cold:
		_cold = false
		_tint_ball(false)


## What the abilities put on the pitch since the last look.
func absorb(abilities: AbilityEngine) -> void:
	if abilities == null:
		return
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
	for stone in stones:
		var q: Vector2 = stone["pos"]
		var w := 18.0
		var h := 24.0
		var tint := Color(0.62, 0.64, 0.68) if not bool(stone["side"]) else Color(0.55, 0.5, 0.55)
		draw_rect(Rect2(q - Vector2(w * 0.5, h), Vector2(w, h)), tint, true)
		draw_circle(q - Vector2(0, h), w * 0.5, tint)
		draw_line(q - Vector2(0, h + 4), q - Vector2(0, 6), Color(0.25, 0.25, 0.3), 2.5)
		draw_line(q - Vector2(5, h - 6), q - Vector2(-5, h - 6), Color(0.25, 0.25, 0.3), 2.5)
