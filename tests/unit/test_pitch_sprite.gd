extends GutTest

# =============================================================
#  THE ISOMETRIC PITCH FIGURES  (round AN, GUT)
#
#  Which of the 8 drawings a direction on screen picks, and that every
#  animation in data/PitchAnims.csv has its 8 rows.
# =============================================================


func test_straight_screen_directions() -> void:
	assert_eq(PitchSprite.direction_of(Vector2(1, 0)), 0, "right is east")
	assert_eq(PitchSprite.direction_of(Vector2(0, 1)), 2, "down is south")
	assert_eq(PitchSprite.direction_of(Vector2(-1, 0)), 4, "left is west")
	assert_eq(PitchSprite.direction_of(Vector2(0, -1)), 6, "up is north")
	assert_eq(PitchSprite.direction_of(Vector2.ZERO), -1, "standing still has no direction")


func test_squash_turns_the_tilted_pitch_into_diagonals() -> void:
	# The tilted pitch's long side runs up-right at about 20 degrees on
	# screen (PitchView.csv corners). Unsquashed that is east; on the ground
	# it is north-east.
	var up_the_pitch := Vector2(1008, -360)
	assert_eq(PitchSprite.direction_of(up_the_pitch, 1.0), 0)
	assert_eq(PitchSprite.direction_of(up_the_pitch, 2.0), 7, "north-east")
	var across := Vector2(642, 240)
	assert_eq(PitchSprite.direction_of(across, 2.0), 1, "south-east")


func test_every_animation_has_eight_rows_without_overlap() -> void:
	PitchSprite.reload()
	var used := {}
	for anim_name in ["idle", "run", "kick", "tackle", "fall", "cheer", "drink"]:
		assert_true(PitchSprite.has_anim(anim_name), "%s is in PitchAnims.csv" % anim_name)
		var first: int = PitchSprite.anim(anim_name)["row"]
		for d in 8:
			assert_false(used.has(first + d), "%s row %d is used once" % [anim_name, first + d])
			used[first + d] = true


func test_drink_has_a_stand_in_until_it_is_drawn() -> void:
	PitchSprite.reload()
	var drink := PitchSprite.anim("drink")
	assert_false(drink.is_empty(), "drink is in PitchAnims.csv")
	assert_false(bool(drink["loop"]), "a drink plays once")
	var stand_in := String(drink["stand_in"])
	assert_true(stand_in == "" or PitchSprite.has_anim(stand_in),
		"the Stand-in '%s' is an animation too" % stand_in)


func test_drawn_sheets_have_their_own_cell_and_smooth_scaling() -> void:
	# Drawn players (18 Oct 2026): data/PitchSheets.csv drawn_* rows.
	PitchSprite.reload()
	var drawn := load("res://assets/players/pitch/drawn_thomas_light.webp") as Texture2D
	assert_not_null(drawn, "the drawn Thomas sheet is built")
	var look := PitchSprite.look_of(drawn)
	assert_eq(float(look["cell"]), 112.0, "drawn sheets use 112 pixel frames")
	assert_true(PitchSprite.is_smooth(drawn), "drawn sheets scale smoothly")
	var pixel := load("res://assets/players/pitch/club_m1.png") as Texture2D
	assert_false(PitchSprite.is_smooth(pixel), "pixel sheets keep hard pixels")
	assert_eq(float(PitchSprite.look_of(pixel)["cell"]), 72.0, "pixel sheets use Tuning pitch_sheet_cell")
	assert_eq(int(drawn.get_width() / 112.0), 9, "9 frames across, like the widest move")
