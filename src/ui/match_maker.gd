class_name MatchMaker
extends RefCounted

# =============================================================
#  THE MATCH MAKER  (round AN)
#
#  Anthony: "the base's Play Match flag opens a new Match Maker window".
#  A match is counted in Play Maker cycles (8 Oct): Normal Match = 3,
#  Test Match = 2, Quick Match = 1.
#
#  A small window over the base, in the same `window` frame as every "are you
#  sure" in the game (Theme.csv), with one button per row of
#  data/MatchMaker.csv:
#
#      ID        a name for the row
#      Words     what the button says
#      Icon      art|glyph - an icon file in assets/icons/, and the one or
#                two characters shown until that file exists
#      Mode      a MatchModes.csv ID. THAT row says how long the match is
#                (Timer, Cycles, Rounds, Star Rotation) and what it pays
#      Under     the line under the button
#      Requires  hides the button until it is true (same words as everywhere)
#
#  Adding a length is a MatchModes.csv row and a MatchMaker.csv row. No code.
#
#  Picking one hands the mode to `on_pick`; the base does the rest exactly as
#  Play a match always did (Team Build gate, save, the team shelf).
#
#  NO EXTRA ABILITIES (Anthony, 8 Oct): a switch above the buttons. On, the
#  match plays on base power only - no abilities, no Emblems, no brews, for
#  both sides. `on_pick` is called with (mode, no_abilities).
# =============================================================

const DATA_PATH := "res://data/MatchMaker.csv"


## Every option you can pick right now, in file order. Rows with no Mode,
## a Mode MatchModes.csv does not know, or a Requires that fails are left out.
static func options(state: GameState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var modes := MatchMode.get_db()
	for row in MenuSupport.read_csv(DATA_PATH):
		var mode_id := MenuSupport.field(row, "Mode")
		if mode_id == "":
			continue
		if modes.find(mode_id).is_empty():
			push_warning("[match maker] MatchMaker.csv names mode '%s', which MatchModes.csv does not have." % mode_id)
			continue
		var requires := MenuSupport.field(row, "Requires")
		if requires != "" and state != null and not DialogueGrammar.test(requires, state):
			continue
		out.append({
			"id": MenuSupport.field(row, "ID"),
			"words": MenuSupport.field(row, "Words", mode_id),
			"icon": MenuSupport.field(row, "Icon", "play|▶"),
			"mode": mode_id,
			"under": MenuSupport.field(row, "Under"),
		})
	# NEVER AN EMPTY WINDOW. No file, or every row hidden, is the old button:
	# a Normal Match.
	if out.is_empty():
		out.append({"id": "normal", "words": "Normal Match", "icon": "cycle3|3",
			"mode": "friendly", "under": ""})
	return out


## Put the window up over `on`. `on_pick` is called with the chosen
## MatchModes.csv ID and the No Extra Abilities switch after the window has
## closed itself.
static func open(on: Node, state: GameState, on_pick: Callable) -> CanvasLayer:
	var window := MenuSupport.dialog(on,
		Loc.text("match_maker", "Match Maker").to_upper(),
		Loc.text("match_maker_under", "How long a match? Nothing goes in the table."),
		480.0)
	window.name = "MatchMaker"
	var column: VBoxContainer = window.get_meta("column")

	var plain_words := Loc.text("match_no_abilities", "No Extra Abilities")
	var plain := MenuSupport.icon_button("plain|0", "%s: %s" % [plain_words,
		Loc.text("off", "Off").to_upper()], Vector2(0, 46))
	plain.name = "NoExtraAbilities"
	plain.toggle_mode = true
	plain.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	plain.tooltip_text = Loc.text("match_no_abilities_under",
		"Every player plays on base power only: no abilities, no Emblems, no brews. Both sides.")
	# The words live on a Label inside the button (icon_button), not on
	# Button.text, so the switch rewrites that Label.
	var labels := plain.find_children("*", "Label", true, false)
	var words := labels[labels.size() - 1] as Label if not labels.is_empty() else null
	plain.toggled.connect(func(on: bool) -> void:
		if words != null:
			words.text = "%s: %s" % [plain_words,
				(Loc.text("on", "On") if on else Loc.text("off", "Off")).to_upper()])
	column.add_child(plain)

	for option in options(state):
		var button := MenuSupport.icon_button(String(option["icon"]),
			String(option["words"]), Vector2(0, 56))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.tooltip_text = String(option["under"])
		var mode_id := String(option["mode"])
		button.pressed.connect(func() -> void:
			if is_instance_valid(window):
				window.queue_free()
			on_pick.call(mode_id, plain.button_pressed))
		column.add_child(button)
		if String(option["under"]) != "":
			var under := Label.new()
			under.text = String(option["under"])
			under.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			under.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			under.add_theme_font_size_override("font_size", 14)
			under.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
			column.add_child(under)

	var close := MenuSupport.icon_button("close|✕", Loc.text("close", "Close"),
		Vector2(0, 46))
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close.pressed.connect(func() -> void:
		if is_instance_valid(window):
			window.queue_free())
	column.add_child(close)

	var first := column.get_child(column.get_child_count() - 1) as Control
	for child in column.get_children():
		if child is Button and child != plain:
			first = child
			break
	first.call_deferred("grab_focus")
	return window
