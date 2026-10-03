extends SceneTree

# =============================================================
#  THE DUEL WINDOW, ON ITS OWN, PHOTOGRAPHED
#
#  The duel cut-away turns up several minutes into a real match, after a
#  draft, a relay and a clash. That is a very long walk to find out whether
#  the card back reads properly — so this opens the window by itself, hands
#  it a made-up duel, and saves a picture every tenth of a second through the
#  whole thing.
#
#  WHAT TO LOOK FOR, in order:
#
#      d_00..  the card BACK: "TIER x" with a crest each side
#      d_0x..  the window squashed to nothing — the turn
#      d_0x..  the duel itself: two players, then their numbers
#      d_1x..  the WON / LOST stamps
#
#  Run it with a window, because a screenshot needs something to photograph:
#
#      xvfb-run godot --rendering-driver opengl3 --resolution 1920x1080 \
#          --script res://tools/duel_shot.gd
#
#  Pictures land beside your save, in user://. The path is printed at the end.
#
#  A tool, not part of the game. Nothing loads it.
# =============================================================

const STEP := 0.1
const SHOTS := 46

var _n := 0


func _initialize() -> void:
	await process_frame
	var db := CardDatabase.get_db()

	# ---- two real cards out of your own spreadsheets ----
	var cards := _two_of_a_tier(db, "III")
	if cards.is_empty():
		print("[duel] no tier III cards found — check your unit CSVs")
		quit(1)
		return

	var arena = load("res://src/ui/duel_arena.tscn").instantiate()
	root.add_child(arena)
	arena.db = db
	arena.apply_tuning(db)
	# The two crests on the back of the card. Banner Art out of ClassInfo.csv,
	# exactly as the team sheet uses it.
	arena.left_team = "THE CLUB"
	arena.right_team = "THE RIVALS"
	arena.left_crest = _crest(db, cards[0])
	arena.right_crest = _crest(db, cards[1])
	await process_frame

	var left := {
		"card": cards[0], "is_attacker": true, "priority": 0,
		"power_before": cards[0].get_attack_power(),
		"power_after": cards[0].get_attack_power() + 1,
		"printed": cards[0].get_attack_power(),
		"ability": _first(db, cards[0].active_attack_ability()),
		"wins": true,
	}
	var right := {
		"card": cards[1], "is_attacker": false,
		# Round Z, ruling F4: a priority that is not its power is shown.
		"priority": cards[1].get_defense_power() - 1,
		"power_before": cards[1].get_defense_power(),
		"power_after": cards[1].get_defense_power(),
		"printed": cards[1].get_defense_power(),
		"ability": _first(db, cards[1].active_defend_ability()),
		"wins": false,
	}

	arena.play_duel({"tier": "III", "left": left, "right": right})

	for i in SHOTS:
		await create_timer(STEP, true, false, true).timeout
		_shoot("d_%02d" % _n)
		_n += 1
		if not arena.is_running():
			break

	print("[duel] %d pictures in %s" % [_n, ProjectSettings.globalize_path("user://")])
	quit(0)


## The first row a cell names (a cell may name several since round Y).
func _first(db: CardDatabase, cell: String) -> AbilityData:
	for piece in cell.split(";"):
		var a := db.get_ability(String(piece).strip_edges())
		if a != null:
			return a
	return null


## Two cards of one tier, from different classes when the data allows it, so
## the two crests on the back are not the same picture twice.
func _two_of_a_tier(db: CardDatabase, tier: String) -> Array:
	var found: Array = []
	var classes: Array = []
	for card in db.players:
		if card.get_tier_clean() != tier:
			continue
		if classes.has(card.unit_type):
			continue
		classes.append(card.unit_type)
		found.append(card)
		if found.size() == 2:
			return found
	# Only one class in the project: take any two of the tier.
	for card in db.players:
		if card.get_tier_clean() == tier and not found.has(card):
			found.append(card)
		if found.size() == 2:
			break
	return found if found.size() == 2 else []


## The same lookup the team sheet does: Banner Art out of ClassInfo.csv, then
## banner_<class>, then whatever team_crest_fallback says.
func _crest(db: CardDatabase, card: PlayerData) -> String:
	var wanted := CardDatabase._normalise(String(card.unit_type))
	var row := {}
	for line in MenuSupport.read_csv("res://data/ClassInfo.csv"):
		if CardDatabase._normalise(MenuSupport.field(line, "Class")) == wanted:
			row = line
			break
	var crest := MenuSupport.field(row, "Banner Art").strip_edges()
	if crest == "" or MenuSupport.icon_texture(crest) == null:
		crest = "banner_%s" % wanted
	if MenuSupport.icon_texture(crest) == null:
		crest = db.tune_text("team_crest_fallback", "banner_normal_team")
	return crest


func _shoot(name: String) -> void:
	var image := root.get_texture().get_image()
	image.save_png("user://%s.png" % name)
	print("[duel] %s.png" % name)
