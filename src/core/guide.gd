class_name Guide
extends RefCounted

# =============================================================
#  THE GUIDE — the Head Coach explains a screen  (round AN)
#
#  data/Guide.csv, one row per explanation:
#
#    ID         a name for the row, unique. Also how Once is remembered:
#               a row that has played sets flag:guide_done_<ID>, which the
#               next row can wait on.
#    Screen     where it plays: base, brewery, shop, bounty (the Adventure
#               board). The screen asks when it opens, and again whenever it
#               redraws (the base after a window closes, the Brewery after
#               WORK IT).
#    Requires   the condition language. Blank = always.
#    Scene      a Dialogue.csv scene, shown in a box over the screen (the
#               same box as MatchTalk.csv). Blank or missing = no box.
#    Highlight  the words on a button to light up after the box - "WORK IT",
#               "Adventure". The first button showing those words pulses until
#               it is pressed. Nothing is forced: every other button works.
#    Then       what happens after the box, in the Progression.csv Do
#               language: flag:x ; count:x+1 ; unlock:Name ; and goto:base,
#               which on a screen opened over the base just closes it.
#    Once       true = only ever once (the usual for a tutorial).
#    Only       true = nothing but the lit button can be used until it has
#               been (round AN, so the tutorial cannot be clicked through).
#               The Brewery reads it: only the lit machine works, and its
#               mini-game cannot be lost.
#
#  The Then column runs BEFORE the button lights up (round AN), so a Then
#  that hands over stock or a key lights a machine that is ready to work.
#  goto:back closes the screen: a window over the base, or the Brewery over
#  a match TIME OUT.
#
#  The first row that fits plays; one box at a time.
# =============================================================

const FILE := "res://data/Guide.csv"
const DONE_PREFIX := "guide_done_"
## Set on the screen while an Only row's button is waiting to be pressed:
## the words of that button.
const ONLY_META := "guide_only"

static var _rows: Array[Dictionary] = []
static var _loaded := false
## The box on screen now, so a screen that redraws twice does not stack two.
static var _open_box: MatchTalkBox = null


static func reload() -> void:
	_loaded = false
	_load()


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_rows = []
	for row in MenuSupport.read_csv(FILE):
		var id_text := MenuSupport.field(row, "ID").strip_edges()
		if id_text == "":
			continue
		_rows.append({
			"id": id_text,
			"screen": CardDatabase._normalise(MenuSupport.field(row, "Screen")),
			"requires": MenuSupport.field(row, "Requires").strip_edges(),
			"scene": MenuSupport.field(row, "Scene").strip_edges(),
			"highlight": MenuSupport.field(row, "Highlight").strip_edges(),
			"then": MenuSupport.field(row, "Then").strip_edges(),
			"once": ["true", "yes", "1"].has(MenuSupport.field(row, "Once").strip_edges().to_lower()),
			"only": ["true", "yes", "1"].has(MenuSupport.field(row, "Only").strip_edges().to_lower()),
		})


## Called by a screen when it opens or redraws. `host` is the screen itself.
static func check(host: Control, screen: String, state: GameState) -> void:
	if host == null or state == null or not host.is_inside_tree():
		return
	if _open_box != null and is_instance_valid(_open_box):
		return
	# Something else is talking first (the "New at the base" list): wait. The
	# screen asks again when it closes.
	if _find_kind(host, "NewUnlocksPanel"):
		return
	_load()
	var key := CardDatabase._normalise(screen)
	for row in _rows:
		if String(row["screen"]) != key:
			continue
		if bool(row["once"]) and state.has_flag(DONE_PREFIX + String(row["id"])):
			continue
		if not DialogueGrammar.test(String(row["requires"]), state):
			continue
		_play(host, row, state)
		return


static func _play(host: Control, row: Dictionary, state: GameState) -> void:
	state.set_flag(DONE_PREFIX + String(row["id"]), true)
	state.save_to_disk()
	print("[guide] %s on %s." % [row["id"], row["screen"]])
	var scene := String(row["scene"])
	if scene != "" and DialogueDB.get_db().scene_names().has(scene):
		_open_box = MatchTalkBox.play(host, scene, state, false)
	elif scene != "":
		print("[guide] %s: Dialogue.csv has no scene called '%s' - skipped." % [row["id"], scene])
	if _open_box != null and is_instance_valid(_open_box):
		await _open_box.finished
	_open_box = null
	if not is_instance_valid(host):
		return
	# THEN FIRST (round AN): stock or a key handed over here makes the
	# machine that lights up next ready to work.
	if _then(host, String(row["then"]), state):
		return
	if host.has_method("refresh"):
		host.call("refresh")
	var words := String(row["highlight"])
	if bool(row["only"]) and words.strip_edges() != "":
		host.set_meta(ONLY_META, words.strip_edges())
	# Lit after the redraw has built the new buttons.
	await host.get_tree().process_frame
	if is_instance_valid(host):
		highlight(host, words)


## Do the Then column. goto:base over the base closes the window instead.
## True = the screen was left (goto), so there is nothing left to light.
static func _then(host: Control, actions: String, state: GameState) -> bool:
	if actions == "":
		return false
	var rest: Array[String] = []
	var go_to := ""
	for part in actions.split(";", false):
		var term := String(part).strip_edges()
		if term.to_lower().begins_with("goto:"):
			go_to = term.substr(5).strip_edges()
		else:
			rest.append(term)
	if not rest.is_empty():
		Progression.run_actions(";".join(rest), state)
		state.save_to_disk()
	if go_to == "":
		return false
	var tree := host.get_tree()
	# ROUND AN: goto:back - the screen closes itself (the Brewery over a
	# match TIME OUT), or its window over the base closes.
	if CardDatabase._normalise(go_to) == "back":
		var walk: Node = host
		while walk != null:
			if walk.has_method("leave"):
				walk.call("leave")
				return true
			if walk is BaseWindow:
				(walk as BaseWindow).close()
				return true
			walk = walk.get_parent()
		return true
	if CardDatabase._normalise(go_to) == "base":
		# A screen opened over the base: close its window and you are there.
		var node: Node = host
		while node != null:
			if node is BaseWindow:
				(node as BaseWindow).close()
				return true
			node = node.get_parent()
	ScenePaths.go_to(tree, ScenePaths.for_name(go_to))
	return true


# =============================================================
#  LIGHTING UP A BUTTON
# =============================================================

## Make the first button under `host` that shows `words` pulse until pressed.
static func highlight(host: Node, words: String) -> Control:
	if words.strip_edges() == "" or host == null:
		return null
	var target := _find_button(host, words.strip_edges().to_lower())
	if target == null:
		print("[guide] No button saying '%s' on this screen to light up." % words)
		return null
	var ring := Panel.new()
	ring.name = "GuideHighlight"
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0)
	style.border_color = MenuSupport.COLOUR_ACCENT
	style.set_border_width_all(4)
	style.set_corner_radius_all(6)
	style.expand_margin_left = 6
	style.expand_margin_right = 6
	style.expand_margin_top = 6
	style.expand_margin_bottom = 6
	ring.add_theme_stylebox_override("panel", style)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	target.add_child(ring)
	var pulse := ring.create_tween().set_loops()
	pulse.tween_property(ring, "modulate:a", 0.25, 0.5)
	pulse.tween_property(ring, "modulate:a", 1.0, 0.5)
	if target is BaseButton:
		(target as BaseButton).pressed.connect(func() -> void:
			if is_instance_valid(ring):
				ring.queue_free(), CONNECT_ONE_SHOT)
	return target


static func _find_kind(node: Node, kind_name: String) -> bool:
	for child in node.get_children():
		var script: Script = child.get_script()
		if script != null and script.get_global_name() == kind_name:
			return true
		if _find_kind(child, kind_name):
			return true
	return false


static func _find_button(node: Node, words: String) -> Control:
	if node is BaseButton and _says(node, words):
		return node as Control
	for child in node.get_children():
		var hit := _find_button(child, words)
		if hit != null:
			return hit
	return null


## A button "says" the words when its own text, its tooltip or any label
## inside it does (the base's banners carry their words on a label).
static func _says(node: Node, words: String) -> bool:
	if node is Button and (node as Button).text.to_lower().contains(words):
		return true
	if node is Control and (node as Control).tooltip_text.to_lower().begins_with(words):
		return true
	for child in node.get_children():
		if child is Label and (child as Label).text.to_lower().contains(words):
			return true
		if not (child is BaseButton) and _says_inside(child, words):
			return true
	return false


static func _says_inside(node: Node, words: String) -> bool:
	for child in node.get_children():
		if child is Label and (child as Label).text.to_lower().contains(words):
			return true
		if _says_inside(child, words):
			return true
	return false
