extends GutTest

# =============================================================
#  SETTINGS  (round AN, GUT)
#
#  The bug: "Settings changes don't affect the game." The volume sliders
#  turned down buses that did not exist. These check the buses are made from
#  data/SoundBuses.csv, that a slider reaches its bus at once, that nothing
#  is written to settings.json until Save, and that Text size does something.
#
#  Your real user://settings.json is copied aside first and put back after.
# =============================================================

var _backup: String = ""
var _had_file: bool = false


func before_all() -> void:
	_had_file = FileAccess.file_exists(GameSettings.SAVE_PATH)
	if _had_file:
		_backup = FileAccess.get_file_as_string(GameSettings.SAVE_PATH)


func after_all() -> void:
	if _had_file:
		var file := FileAccess.open(GameSettings.SAVE_PATH, FileAccess.WRITE)
		file.store_string(_backup)
		file.close()
	elif FileAccess.file_exists(GameSettings.SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(GameSettings.SAVE_PATH))
	GameSettings._apply_sound(GameSettings.load_all())
	TextScale.apply(get_tree(), 1.0)


func test_every_bus_in_the_sheet_exists() -> void:
	GameSettings.ensure_buses()
	for row in GameSettings.bus_rows():
		assert_gt(AudioServer.get_bus_index(String(row["bus"])), -1,
			"bus %s from SoundBuses.csv" % row["bus"])


func test_every_audio_row_names_a_real_bus() -> void:
	var wrong: Array[String] = []
	for line in AudioDB.get_db().problems:
		if String(line).contains("bus '"):
			wrong.append(String(line))
	assert_eq(wrong.size(), 0, "\n".join(wrong))


func test_a_slider_reaches_its_bus_without_saving() -> void:
	var before := FileAccess.get_file_as_string(GameSettings.SAVE_PATH) \
		if FileAccess.file_exists(GameSettings.SAVE_PATH) else ""
	var settings := GameSettings.load_all()
	settings["volume_music"] = 0.25
	GameSettings.preview(get_tree(), settings, "volume_music")
	var index := AudioServer.get_bus_index("Music")
	assert_almost_eq(AudioServer.get_bus_volume_db(index), linear_to_db(0.25), 0.01)
	settings["volume_music"] = 0.0
	GameSettings.preview(get_tree(), settings, "volume_music")
	assert_true(AudioServer.is_bus_mute(index), "zero mutes the bus")
	var after := FileAccess.get_file_as_string(GameSettings.SAVE_PATH) \
		if FileAccess.file_exists(GameSettings.SAVE_PATH) else ""
	assert_eq(after, before, "preview never writes settings.json")


func test_the_screen_saves_only_on_save() -> void:
	var screen := load(ScenePaths.SETTINGS).instantiate() as SettingsScreen
	add_child_autofree(screen)
	await wait_frames(2)
	var start := float(GameSettings.load_all().get("volume_music", 0.7))
	var wanted := 0.35 if not is_equal_approx(start, 0.35) else 0.45
	screen._change("volume_music", wanted)
	assert_eq(screen.unsaved(), ["volume_music"] as Array[String])
	assert_almost_eq(float(GameSettings.load_all()["volume_music"]), start, 0.001,
		"not on disk before Save")
	screen._save()
	assert_true(screen.unsaved().is_empty())
	assert_almost_eq(float(GameSettings.load_all()["volume_music"]), wanted, 0.001,
		"on disk after Save")
	# The screen's painted layers are read straight from the PNGs
	# (ScreenLook.picture), which Godot grumbles about. Not this test's job.
	for problem in get_errors():
		if String(problem.code).contains("Loaded resource as image file"):
			problem.handled = true


func test_numbers_from_the_file_match_numbers_from_a_button() -> void:
	assert_true(SettingsScreen._same(60, 60.0))
	assert_false(SettingsScreen._same("60", 60))
	assert_true(SettingsScreen._same("windowed", "windowed"))


func test_text_size_scales_and_comes_back() -> void:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 20)
	add_child_autofree(label)
	TextScale.apply(get_tree(), 1.5)
	assert_eq(label.get_theme_font_size("font_size"), 30)
	TextScale.apply(get_tree(), 1.0)
	assert_eq(label.get_theme_font_size("font_size"), 20)


func test_rumble_picks_the_strongest_row_that_fits() -> void:
	var plain := Rumble.pick("goal_scored", {})
	var star := Rumble.pick("goal_scored", {"star": "yes"})
	assert_false(plain.is_empty(), "Rumble.csv has a goal_scored row")
	assert_gt(float(star["seconds"]), float(plain["seconds"]), "a star's goal shakes longer")
	assert_true(Rumble.pick("no_such_moment", {}).is_empty())


func test_vibration_switch_turns_rumble_off() -> void:
	var settings := GameSettings.load_all()
	settings["pad_vibration"] = false
	GameSettings.preview(get_tree(), settings, "pad_vibration")
	assert_false(Rumble.on)
	settings["pad_vibration"] = true
	GameSettings.preview(get_tree(), settings, "pad_vibration")
	assert_true(Rumble.on)
