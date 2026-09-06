@tool
extends EditorScript

const CSV_DIR = "res://data/"
const ASSETS_DIR = "res://assets/players/"
const NORMAL_DIR = "res://data/players/normal/"
const STAR_DIR = "res://data/players/star_player/"
const FORMATION_DIR = "res://src/formations/"
const GOALIES_CSV = "res://data/Goalies.csv"
const GOALIES_SAVE_DIR = "res://data/goalies/"

# Add this call inside your _run() function:
# import_goalies()

func import_goalies() -> void:
	if not FileAccess.file_exists(GOALIES_CSV):
		return

	DirAccess.make_dir_recursive_absolute(GOALIES_SAVE_DIR)

	var file = FileAccess.open(GOALIES_CSV, FileAccess.READ)
	var rows = parse_csv(file.get_as_text())
	file.close()

	for i in range(1, rows.size()):
		var row = rows[i]
		if row.size() < 3 or row[1].strip_edges() == "":
			continue

		var goalie = GoalieData.new()
		goalie.team = row[0].strip_edges()
		goalie.goalie_name = row[1].strip_edges()
		goalie.max_stamina = int(row[2])
		goalie.ability_text = row[3].strip_edges() if row.size() > 3 else ""

		if row.size() >= 5 and row[4].strip_edges() != "":
			var art_path = ASSETS_DIR + row[4].strip_edges()
			if ResourceLoader.exists(art_path):
				goalie.artwork = load(art_path)

		var clean_name = goalie.team.to_lower() + "_goalie.tres"
		ResourceSaver.save(goalie, GOALIES_SAVE_DIR + clean_name)

	print("Goalie resources generated successfully.")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(NORMAL_DIR)
	DirAccess.make_dir_recursive_absolute(STAR_DIR)

	var dir = DirAccess.open(CSV_DIR)
	if not dir:
		printerr("Failed to open directory: ", CSV_DIR)
		return

	var csv_files: Array[String] = []
	for file_name in dir.get_files():
		if file_name.ends_with(".csv"):
			csv_files.append(CSV_DIR + file_name)

	if csv_files.is_empty():
		print("No CSV files found in: ", CSV_DIR)
		return

	var total_imported = 0
	for csv_path in csv_files:
		print("Processing: ", csv_path)
		total_imported += process_csv(csv_path)

	EditorInterface.get_resource_filesystem().scan()
	print("Done! Scanned %d CSV(s) and saved %d total player resources." % [csv_files.size(), total_imported])


func process_csv(csv_path: String) -> int:
	var file = FileAccess.open(csv_path, FileAccess.READ)
	if not file:
		printerr("Failed to open: ", csv_path)
		return 0

	var raw_text = file.get_as_text()
	file.close()

	var rows = parse_csv(raw_text)
	if rows.is_empty():
		return 0

	var count = 0
	for i in range(1, rows.size()):
		var row = rows[i]
		if row.size() < 14 or row[1].strip_edges() == "":
			continue

		var player = PlayerData.new()
		player.unit_type = row[0].strip_edges()
		player.player_name = row[1].strip_edges()
		player.attack_text = row[2].strip_edges()
		player.defend_text = row[3].strip_edges()
		player.element = row[4].strip_edges()
		player.base_power_left = int(row[5])
		player.base_power_right = int(row[6])
		player.tier = row[7].strip_edges()
		player.stufe = row[8].strip_edges()
		player.tool = row[9].strip_edges()
		player.card_number = int(row[10])
		player.card_date = int(row[11])
		player.card_set = row[12].strip_edges()
		player.created_by = row[13].strip_edges()

# Column 15 (Index 14): Artwork
		if row.size() >= 15:
			var image_name = row[14].strip_edges()
			if image_name != "":
				var full_art_path = ASSETS_DIR + image_name
				if ResourceLoader.exists(full_art_path):
					player.artwork = load(full_art_path)
				else:
					printerr("Image not found: ", full_art_path)

		# Column 16 (Index 15): Player Type ("Normal" or "Star")
		var is_star = false
		if row.size() >= 16 and row[15].strip_edges() != "":
			player.player_type = row[15].strip_edges()
			if player.player_type.to_lower().contains("star"):
				is_star = true

		# Formation auto-assignment for Star Players
		if is_star:
			var formation_file = ""
			# Optional Column 17 (Index 16): Custom formation override
			if row.size() >= 17 and row[16].strip_edges() != "":
				formation_file = row[16].strip_edges()
			else:
				# Default naming rule: res://scenes/[unit_type]_formation.tscn
				formation_file = player.unit_type.to_lower().replace(" ", "_") + "_formation.tscn"

			var formation_path = FORMATION_DIR + formation_file
			if ResourceLoader.exists(formation_path):
				player.formation_scene = load(formation_path)
			else:
				print("Note: No formation scene found yet at: ", formation_path)

		# Save to sorted directory
		var clean_name = player.player_name.to_lower().replace(" ", "_").replace("-", "_")
		var target_folder = STAR_DIR if is_star else NORMAL_DIR
		var save_path = target_folder + clean_name + ".tres"

		ResourceSaver.save(player, save_path)
		count += 1

	return count


func parse_csv(content: String) -> Array:
	var rows = []
	var current_row: PackedStringArray = []
	var current_field = ""
	var in_quotes = false
	var i = 0

	while i < content.length():
		var c = content[i]
		if in_quotes:
			if c == '"':
				if i + 1 < content.length() and content[i + 1] == '"':
					current_field += '"'
					i += 1
				else:
					in_quotes = false
			else:
				current_field += c
		else:
			if c == '"':
				in_quotes = true
			elif c == ",":
				current_row.append(current_field)
				current_field = ""
			elif c == "\r":
				pass
			elif c == "\n":
				current_row.append(current_field)
				current_field = ""
				rows.append(current_row)
				current_row = []
			else:
				current_field += c
		i += 1

	if not current_field.is_empty() or not current_row.is_empty():
		current_row.append(current_field)
		rows.append(current_row)

	return rows
