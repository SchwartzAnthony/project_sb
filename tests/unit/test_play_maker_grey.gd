extends GutTest

# =============================================================
#  GREY ONLY DURING A PLAY MAKER, AND NO EXTRA ABILITIES  (round AN, GUT)
#
#  Anthony, 8 Oct: players are greyed only while a Play Maker runs and they
#  are not in it; once it ends everyone is back in colour. And the Match
#  Maker's "No Extra Abilities" plays every card on its base power.
# =============================================================

const UNIT_SCENE := preload("res://src/units/player_unit.tscn")


func before_each() -> void:
	CardDatabase.get_db()
	PlayerUnit.play_maker_live = false


func after_each() -> void:
	PlayerUnit.play_maker_live = false
	MatchMode.clear(get_tree())


func _unit() -> PlayerUnit:
	var unit: PlayerUnit = UNIT_SCENE.instantiate()
	add_child_autofree(unit)
	return unit


func _greyed(unit: PlayerUnit) -> bool:
	var mat := unit.artwork.material as ShaderMaterial
	if mat != null and float(mat.get_shader_parameter("saturation")) < 1.0:
		return true
	return unit.artwork.modulate.r < 0.9


func test_nobody_is_grey_outside_a_play_maker() -> void:
	var unit := _unit()
	unit.is_exhausted = true
	unit.set_highlight(false)
	assert_false(_greyed(unit), "no Play Maker running: in colour, even when spent")


func test_only_those_outside_the_play_maker_are_grey() -> void:
	var outside := _unit()
	var inside := _unit()
	inside.is_playmaker = true
	PlayerUnit.play_maker_live = true
	outside.set_highlight(false)
	inside.set_highlight(false)
	assert_true(_greyed(outside), "not in this Play Maker: grey")
	assert_false(_greyed(inside), "in this Play Maker: colour")


func test_everyone_regains_colour_when_it_ends() -> void:
	var unit := _unit()
	PlayerUnit.play_maker_live = true
	unit.set_highlight(false)
	assert_true(_greyed(unit))
	PlayerUnit.play_maker_live = false
	unit.set_highlight(false)
	assert_false(_greyed(unit))


func test_no_extra_abilities_is_carried_by_the_match_maker_only() -> void:
	MatchMode.choose(get_tree(), "friendly", true)
	assert_true(MatchMode.no_abilities(get_tree()))
	MatchMode.choose(get_tree(), "friendly")
	assert_false(MatchMode.no_abilities(get_tree()), "any other way in leaves it off")
	MatchMode.choose(get_tree(), "friendly", true)
	MatchMode.clear(get_tree())
	assert_false(MatchMode.no_abilities(get_tree()))


func test_no_extra_abilities_fights_on_printed_power() -> void:
	var db := CardDatabase.get_db()
	var card: PlayerData = null
	for c in db.players:
		if c.get_attack_power() < 3 and c.get_defense_power() < 3:
			card = c
			break
	assert_not_null(card)
	var engine := AbilityEngine.new(db)
	engine.side_bonus = {false: 2, true: 0}
	assert_eq(engine.attack_power(card, false), card.get_attack_power() + 2)
	engine.abilities_off = true
	assert_eq(engine.attack_power(card, false), card.get_attack_power())
	assert_eq(engine.defense_power(card, false), card.get_defense_power())
	engine.side_shot_bonus = {false: 3, true: 0}
	assert_eq(engine.shot_bonus(false), 0)


func test_the_match_maker_has_the_switch() -> void:
	var holder := Node.new()
	add_child_autofree(holder)
	var window := MatchMaker.open(holder, null, func(_m: String, _p: bool) -> void: pass)
	var switch := window.find_child("NoExtraAbilities", true, false) as Button
	assert_not_null(switch)
	assert_true(switch.toggle_mode)
	assert_false(switch.button_pressed, "off unless you turn it on")
