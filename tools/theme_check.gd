extends SceneTree

# =============================================================
#  THE SKIN, READ BACK TO YOU
#
#  `data/Theme.csv` is the one file that can change every screen in the game
#  at once, which also makes it the one file where a typo is hardest to find:
#  an image name that is nearly right draws nothing, and nothing looks a lot
#  like "I have not drawn it yet".
#
#  So this says, in order:
#
#      every element, what it is drawn from, and whether that file exists
#      every palette colour, and whether the game reads that name
#      which elements are IMAGES and which are still flat colours
#      what is in assets/ui/ that no row is using
#
#      godot --headless --script res://tools/theme_check.gd
#
#  A tool, not part of the game. Nothing loads it.
# =============================================================

## The palette names apply_palette() knows what to do with. A row naming
## anything else is a typo, and a silent one.
const PALETTE_KEYS: Array[String] = [
	"accent", "background", "panel", "slot_empty", "locked", "text",
	"text_dim", "attack", "defend", "tier_1", "tier_2", "tier_3", "tier_4",
]

## The elements the game actually asks for by name. A row for anything else
## is harmless but does nothing, which is worth knowing before you spend an
## evening drawing art for it.
const KNOWN_ELEMENTS: Array[String] = [
	"panel", "window", "button", "button_primary", "slot", "tab",
	"bar_back", "bar_fill", "tooltip", "divider", "heading", "body", "small", "fallback",
]


func _initialize() -> void:
	var problems := 0

	print("")
	print("=== Theme.csv ===")
	for problem in ThemeBook.problems():
		print("  ! %s" % problem)
		problems += 1

	var elements := ThemeBook.elements()
	if elements.is_empty():
		print("  No element rows. The game draws itself the way it always did.")
		quit(0)
		return

	# ---- the elements ----
	print("")
	print("  %-16s %-9s %-14s %s" % ["element", "state", "drawn from", "shape"])
	var with_images := 0
	var used_images: Array[String] = []
	for element in elements:
		var states: Dictionary = elements[element]
		for state in states:
			var row: Dictionary = states[state]
			var art := String(row["image"])
			var drawn := "a flat colour"
			if art != "":
				used_images.append(art)
				if ThemeBook.image(art) != null:
					drawn = art
					if String(row.get("tint", "yes")) == "no":
						drawn += " (untinted)"
					with_images += 1
				else:
					drawn = art + "  MISSING"
			var shape := "corner %d, border %d, pad %d x %d" % [
				int(row["corner"]), int(row["border_width"]),
				int(row["pad_x"]), int(row["pad_y"])]
			print("  %-16s %-9s %-14s %s" % [element, state if state != "" else "-", drawn, shape])

		if not KNOWN_ELEMENTS.has(element):
			print("  ! '%s' is not an element the game asks for. The list is: %s"
				% [element, ", ".join(KNOWN_ELEMENTS)])
			problems += 1

	# ---- the palette ----
	print("")
	print("  --- the palette ---")
	var palette := ThemeBook.palette()
	for key in palette:
		var tint: Color = palette[key]
		var known := PALETTE_KEYS.has(String(key))
		print("  colour %-12s %s%s" % [key, tint.to_html(false),
			"" if known else "     <- NOT A NAME THE GAME READS"])
		if not known:
			problems += 1

	for wanted in PALETTE_KEYS:
		if not palette.has(wanted):
			print("  colour %-12s (not set — the game keeps its built-in colour)" % wanted)

	# ---- images on disk that nothing is using ----
	print("")
	print("  --- assets/ui/ ---")
	var folder := DirAccess.open("res://assets/ui")
	var on_disk: Array[String] = []
	if folder != null:
		folder.list_dir_begin()
		var file_name := folder.get_next()
		while file_name != "":
			if not folder.current_is_dir() and not file_name.ends_with(".import"):
				on_disk.append(file_name)
			file_name = folder.get_next()
		folder.list_dir_end()
	if on_disk.is_empty():
		print("  empty. Everything is drawn as a flat colour.")
	for file_name in on_disk:
		var stem := file_name.get_basename()
		var used := used_images.has(stem) or used_images.has(file_name)
		print("  %-22s %s" % [file_name, "in use" if used else "not named by any row"])

	# ---- the headline ----
	print("")
	print("  %d of the element rows are drawn from an image; the rest are flat colours."
		% with_images)
	if with_images == 0:
		print("  Put a file name in the Image column of the `panel` row and every box")
		print("  in the game changes at once. There are three to try in assets/ui/.")

	print("")
	print("=== %s ===" % ("ALL GOOD" if problems == 0 else "%d thing(s) to look at" % problems))
	print("")
	quit(0)
