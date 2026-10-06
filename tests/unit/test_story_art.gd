extends GutTest

# =============================================================
#  THE CONVERSATION PICTURES  (round AN, GUT)
#
#  data/StoryArt.csv: every face and room the intro names exists, a
#  Speaker finds its face without a Portrait cell, and the bar is layered.
# =============================================================

var art: StoryArt
var story: DialogueDB


func before_each() -> void:
	StoryArt.reload_files()
	art = StoryArt.get_db()
	story = DialogueDB.get_db()


func test_every_image_in_the_file_exists() -> void:
	for id in art.portraits.keys():
		var path: String = art.portraits[id]["image"]
		assert_true(ResourceLoader.exists(path), "portrait %s: %s" % [id, path])
	for id in art.backgrounds.keys():
		for layer in art.backgrounds[id]:
			assert_true(ResourceLoader.exists(String(layer["image"])), "background %s: %s" % [id, layer["image"]])


func test_speaker_finds_a_face_without_a_portrait_cell() -> void:
	var row := art.portrait_for("", "Heatwave Brandteufel")
	assert_eq(row.get("image", ""), "res://assets/story/portraits/heatwave.png")
	assert_eq(art.portrait_for("", "Nobody At All"), {})


func test_the_bar_has_layers() -> void:
	assert_gte(art.background_layers("bar").size(), 2, "the bar is a room plus the regulars")


func test_every_intro_line_has_a_face_or_is_narration() -> void:
	for scene in ["prologue", "first_team"]:
		for line in story.scenes.get(scene, []):
			if line.speaker == "":
				continue
			var row := art.portrait_for(line.portrait, line.speaker)
			assert_false(row.is_empty(), "%s/%s (%s) has no face in StoryArt.csv" % [scene, line.id, line.speaker])
