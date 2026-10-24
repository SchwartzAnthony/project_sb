extends GutTest

# =============================================================
#  THE ITEMS PLANK ON A MATCH CARD  (24 Oct)
#
#  Anthony: after a beer in the tutorial a click on the card did nothing,
#  Koch needed a second click. The greyed ITEMS plank (bag shut) was a
#  disabled button on top of the card, and a disabled button still eats
#  the click. Greyed, it must let the click through to the card.
# =============================================================

const CARD_SCENE := preload("res://src/ui/player_card_ui.tscn")


func _card() -> PlayerCardUI:
	var data := PlayerData.new()
	data.unit_type = "Normal"
	data.player_name = "Koch"
	data.tier = "IV"
	data.base_power_left = 4
	data.base_power_right = 4
	data.element = "None"
	var card := CARD_SCENE.instantiate() as PlayerCardUI
	add_child_autofree(card)
	card.setup_card(data)
	return card


func test_greyed_plank_lets_the_click_through() -> void:
	var card := _card()
	var plank := card.get("_flask") as Button
	if plank == null:
		pass_test("draft_brew_button is off: no plank on the card")
		return
	card.set_bag_shut(true)
	assert_true(plank.disabled, "a shut bag greys the plank")
	assert_eq(plank.mouse_filter, Control.MOUSE_FILTER_IGNORE,
		"the greyed plank does not swallow the click meant for the card")
	var face := card.get("_face") as Control
	assert_eq(face.mouse_filter, Control.MOUSE_FILTER_STOP, "the card under it still takes the click")


func test_open_plank_still_opens_the_bag() -> void:
	var card := _card()
	var plank := card.get("_flask") as Button
	if plank == null:
		pass_test("draft_brew_button is off: no plank on the card")
		return
	card.set_bag_shut(true)
	card.set_bag_shut(false)
	assert_false(plank.disabled, "an open bag lights the plank again")
	assert_eq(plank.mouse_filter, Control.MOUSE_FILTER_STOP, "and it takes its own click")
