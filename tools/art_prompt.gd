extends SceneTree

# =============================================================
#  THE PROMPT BUILDER  (round AN)
#
#      godot --headless --path . --script res://tools/art_prompt.gd -- pixellab "Lorelei siren"
#      godot --headless --path . --script res://tools/art_prompt.gd -- openai "the beer tent at night"
#
#  Builds the full art prompt from data/ArtStyle.csv, so the style words are
#  the SAME every time: the recipe_<tool> row says how, {subject} is what you
#  typed, and every other {name} is the Text of that row (art_bible,
#  stammtisch_prompt ...). Prints the prompt and saves it in
#  art_source/prompts/last_<tool>.txt to copy from.
#  Nothing is sent anywhere: the API keys stay in the Deck's Claude config.
# =============================================================

const STYLE_CSV := "res://data/ArtStyle.csv"
const OUT_DIR := "res://art_source/prompts"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("[art_prompt] Give the tool and what to draw, e.g.  -- pixellab \"Lorelei siren\"")
		quit(1)
		return
	var tool_name := String(args[0]).to_lower()
	var subject := " ".join(args.slice(1)).strip_edges()
	var words := _read_style()
	if words.is_empty():
		quit(1)
		return
	var recipe_key := "recipe_" + tool_name
	if not words.has(recipe_key):
		push_error("[art_prompt] ArtStyle.csv has no row '%s'. Tools with a recipe: %s" % [recipe_key, ", ".join(_recipes(words))])
		quit(1)
		return
	var prompt := _fill(String(words[recipe_key]), subject, words)
	if prompt.is_empty():
		quit(1)
		return
	print(prompt)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path := "%s/last_%s.txt" % [OUT_DIR, tool_name]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("[art_prompt] Could not write %s" % path)
		quit(1)
		return
	file.store_string(prompt + "\n")
	file.close()
	print("[art_prompt] saved in %s" % path)
	quit(0)


# Key -> Text of every row in ArtStyle.csv.
func _read_style() -> Dictionary:
	var words := {}
	var file := FileAccess.open(STYLE_CSV, FileAccess.READ)
	if file == null:
		push_error("[art_prompt] Could not open %s" % STYLE_CSV)
		return words
	var header := file.get_csv_line()
	var key_col := header.find("Key")
	var text_col := header.find("Text")
	if key_col < 0 or text_col < 0:
		push_error("[art_prompt] %s needs the columns Key and Text" % STYLE_CSV)
		return words
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() > maxi(key_col, text_col) and String(row[key_col]) != "":
			words[String(row[key_col])] = String(row[text_col])
	return words


# Replaces {subject} and every {row_key}; an unknown name is reported by name.
func _fill(recipe: String, subject: String, words: Dictionary) -> String:
	var out := recipe.replace("{subject}", subject)
	var names := RegEx.new()
	names.compile("\\{([A-Za-z0-9_]+)\\}")
	for found in names.search_all(out):
		var name := found.get_string(1)
		if not words.has(name):
			push_error("[art_prompt] The recipe asks for {%s}, but ArtStyle.csv has no row with that Key" % name)
			return ""
		out = out.replace("{%s}" % name, String(words[name]))
	return out


func _recipes(words: Dictionary) -> Array:
	var found := []
	for key in words:
		if String(key).begins_with("recipe_"):
			found.append(String(key).trim_prefix("recipe_"))
	return found
