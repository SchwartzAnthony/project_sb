extends GutTest

# =============================================================
#  TOWN-MAP BUILDINGS ONLY ANSWER ON THEIR OWN PIXELS  (round AN, GUT)
#
#  Two big buildings side by side must not steal each other's clicks, so a
#  click on a see-through corner of the picture is not on the building.
# =============================================================


func _building(box: Vector2) -> MapBuilding:
	# A 4 x 2 picture: the left half drawn, the right half see-through.
	var image := Image.create(4, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for y in 2:
		for x in 2:
			image.set_pixel(x, y, Color.RED)
	var button := MapBuilding.new()
	button.size = box
	button.use_picture(ImageTexture.create_from_image(image))
	autofree(button)
	return button


func test_drawn_pixels_are_clickable() -> void:
	var button := _building(Vector2(40, 20))
	assert_true(button._has_point(Vector2(5, 10)), "the drawn half takes the click")


func test_see_through_pixels_are_not() -> void:
	var button := _building(Vector2(40, 20))
	assert_false(button._has_point(Vector2(35, 10)), "the empty half lets it through")


func test_letterboxed_space_is_not() -> void:
	# Drawn keep-aspect in a taller box: 40 x 20 picture centred in 40 x 60.
	var button := _building(Vector2(40, 60))
	assert_false(button._has_point(Vector2(5, 5)), "above the picture is nothing")
	assert_true(button._has_point(Vector2(5, 30)), "the picture itself still counts")
