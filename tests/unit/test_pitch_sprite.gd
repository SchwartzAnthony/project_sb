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
	for anim_name in ["idle", "run", "kick", "tackle", "fall", "cheer"]:
		assert_true(PitchSprite.has_anim(anim_name), "%s is in PitchAnims.csv" % anim_name)
		var first: int = PitchSprite.anim(anim_name)["row"]
		for d in 8:
			assert_false(used.has(first + d), "%s row %d is used once" % [anim_name, first + d])
			used[first + d] = true
