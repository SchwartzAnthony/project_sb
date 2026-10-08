class_name MatchCoach
extends Node

# =============================================================
#  THE HEAD COACH IN THE MATCH  (round AN - the tutorial, Anthony 7 Oct)
#
#  "Have the Head Coach stop the game at certain moments ... and highlight
#   (with a golden/yellow box/circle around the objects)."
#
#  Every stop is a row of data/MatchTalk.csv. This node is the part of the
#  match that listens for those moments, finds the row, points the gold at
#  what the row names, plays the lines in the coach's box while everything
#  waits, and then does what the row's Do column says - including the TIME
#  OUT to the pub, which plays a whole Dialogue.csv scene over the frozen
#  match and comes back to exactly the same moment.
#
#  It also owns the EXHAUST ZONE button (Tuning.csv exhaust_button): the
#  place on the match screen where the cards you used this cycle are kept,
#  which the coach points at in the second Play Maker.
#
#  Nothing here knows it is "the tutorial". A row with Mode = tutorial only
#  fires in the tutorial match; the same columns work in any match.
# =============================================================

const DIALOGUE_SCENE := "res://src/ui/dialogue_view.tscn"

var main: Node
var _busy := false
var _exhaust_button: Button
var _exhaust_open := false
var _tick := 0.0


static func attach(match_scene: Node) -> MatchCoach:
	var made := MatchCoach.new()
	made.name = "MatchCoach"
	made.main = match_scene
	match_scene.add_child(made)
	return made


func _ready() -> void:
	# The duel window and the shot window ask us at their gold moments.
	var arena = main.get("duel_arena")
	if arena != null:
		arena.coach = arena_moment
	var shot = main.get("shootout")
	if shot != null:
		shot.coach = shot_moment
	_build_exhaust_button()


# =============================================================
#  THE STOPS
# =============================================================

## Which PLAY MAKER of the match this is: 1 for the first, counting on
## across the cycles (the 4th is the first of cycle 2).
func play_maker_number() -> int:
	var cycle := int(main.get("current_cycle"))
	var per := int(main.get("ROUNDS_PER_CYCLE"))
	return maxi(0, cycle - 1) * per + int(main.get("rounds_this_cycle"))


## The coach stops the match here if MatchTalk.csv has a row for this moment.
## Await it to wait until he has finished (and the Do column has been done);
## call it without await and the match simply pauses underneath him.
func talk(event: String, facts: Dictionary = {}) -> void:
	if _busy:
		return
	var state: GameState = main.get("state")
	var mode: Dictionary = main.get("match_mode")
	var with_round := facts.duplicate()
	with_round["round"] = str(play_maker_number())
	var row := MatchTalk.row_for(event, String(mode.get("id", "")), state, with_round)
	if row.is_empty():
		return
	_busy = true
	print("[match talk] %s (Play Maker %s, Tier %s): '%s'." % [event,
		with_round["round"], String(facts.get("tier", "-")), String(row["scene"])])

	# ROUND AN (Anthony, 8 Oct): from this moment nothing on the screen can
	# be clicked until he has finished - not the cards he is about to point
	# at, not the next line before this one has been read.
	var shield := _input_shield()

	var groups: Array = []
	var words := String(row.get("highlight", ""))
	if words != "":
		# A moment, so a row of cards that has just been dealt has landed and
		# faded in before we measure where it is (the pause would freeze it
		# half see-through). Tuning.csv match_talk_highlight_delay.
		var wait := CardDatabase.get_db().tune_float("match_talk_highlight_delay", 0.6)
		if wait > 0.0:
			await get_tree().create_timer(wait, false).timeout
		await get_tree().process_frame
		# One group of gold per line, | between them.
		var found := 0
		for part in words.split("|"):
			var group := _spots_for(String(part))
			found += group.size()
			groups.append(group)
		if found == 0 and words.to_lower().contains("card"):
			# The cards went while we waited (picked already): nothing to say.
			shield.queue_free()
			_busy = false
			return

	var box := MatchTalkBox.play(main, String(row["scene"]), state, true, groups)
	if box != null:
		main.set("_talk_box", box)
		await box.finished
	shield.queue_free()

	await _do(String(row.get("do", "")))
	_busy = false


## A see-through sheet over everything that swallows clicks, up from the
## moment a stop is decided until the coach's box has closed.
func _input_shield() -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.name = "CoachShield"
	layer.layer = 149
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var sheet := Control.new()
	sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(sheet)
	main.add_child(layer)
	return layer


## The duel window's gold moments (duel_arena.gd calls this).
func arena_moment(event: String, tier: String) -> void:
	await talk(event, {"tier": tier})


## The shot window's moment (shootout_view.gd calls this).
func shot_moment(event: String) -> void:
	await talk(event, {})


# =============================================================
#  WHAT HE POINTS AT  (MatchTalk.csv Highlight)
# =============================================================

func _spots_for(words: String) -> Array:
	var out: Array = []
	for raw in words.split(";", false):
		var word := String(raw).strip_edges()
		if word == "" or word == "-":
			continue
		var ring := false
		if word.to_lower().begins_with("ring:"):
			ring = true
			word = word.substr(5).strip_edges()
		for control in _controls_for(word):
			if control != null and control.is_visible_in_tree():
				out.append({"rect": control.get_global_rect(), "ring": ring})
	if out.is_empty():
		print("[match talk] Highlight '%s' found nothing on screen to point at." % words)
	return out


func _controls_for(word: String) -> Array:
	var lower := word.to_lower()
	var cards: Array = []
	var row = main.get("card_container")
	if row != null:
		for child in (row as Node).get_children():
			if child is PlayerCardUI and not child.is_queued_for_deletion():
				cards.append(child)
	if lower == "cards":
		return cards
	if lower == "card:first":
		return [cards[0]] if not cards.is_empty() else []
	if lower == "card:last":
		return [cards[-1]] if not cards.is_empty() else []
	if lower.begins_with("card:"):
		var wanted := CardDatabase._normalise(word.substr(5))
		for card in cards:
			var data: PlayerData = (card as PlayerCardUI).current_data
			if data != null and CardDatabase._normalise(data.player_name) == wanted:
				return [card]
		return []
	if lower == "exhaust":
		return [_exhaust_button]
	var shot = main.get("shootout")
	if shot != null and shot.has_method("spot"):
		var found: Control = shot.spot(lower)
		if found != null:
			return [found]
	var arena = main.get("duel_arena")
	if arena != null and arena.has_method("spot"):
		var found_arena: Control = arena.spot(lower)
		if found_arena != null:
			return [found_arena]
	return []


# =============================================================
#  WHAT HAPPENS AFTER HIS LINES  (MatchTalk.csv Do)
# =============================================================

func _do(text: String) -> void:
	for raw in text.split(";", false):
		var part := String(raw).strip_edges()
		if part == "":
			continue
		var colon := part.find(":")
		var verb := part.to_lower()
		var value := ""
		if colon > 0:
			verb = part.substr(0, colon).strip_edges().to_lower()
			value = part.substr(colon + 1).strip_edges()
		match verb:
			"pub":
				await time_out(value)
			"star":
				make_star(value)
			"ability":
				var eq := value.find("=")
				if eq > 0:
					give_ability(value.substr(0, eq).strip_edges(), value.substr(eq + 1).strip_edges())
			"announce":
				await main.announce(value, 1.6)
			"keep_star":
				_keep_star = true
			"class":
				var eq := value.find("=")
				if eq > 0:
					change_class(value.substr(0, eq).strip_edges(), value.substr(eq + 1).strip_edges())
			"inspire":
				var at := value.find("=")
				if at > 0:
					inspire(value.substr(0, at).strip_edges(), float(value.substr(at + 1)))
			_:
				push_warning("[match talk] Do: '%s' is not something the coach knows how to do." % part)


## ============ TIME OUT ============
##
## The match is frozen exactly where it is and the whole screen becomes a
## Dialogue.csv scene - the bar, the Head Coach, Koch and his beer. When the
## scene ends, the layer goes and the match carries on from the same frame:
## same score, same clock, same cards in the exhaust.
func time_out(scene: String) -> void:
	var tree := get_tree()
	if not ResourceLoader.exists(DIALOGUE_SCENE):
		return
	print("[match talk] TIME OUT - '%s' plays over the match." % scene)
	var layer := CanvasLayer.new()
	layer.name = "TimeOut"
	layer.layer = 160
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	main.add_child(layer)
	# A return address left on the tree would send the story off to it.
	var parked: Variant = null
	if tree.has_meta(DialogueView.META_RETURN):
		parked = tree.get_meta(DialogueView.META_RETURN)
		tree.remove_meta(DialogueView.META_RETURN)
	var view := (load(DIALOGUE_SCENE) as PackedScene).instantiate() as DialogueView
	view.scene_name = scene
	view.return_to_menu = false
	var was_paused := tree.paused
	tree.paused = true
	layer.add_child(view)
	await view.scene_finished
	tree.paused = was_paused
	layer.queue_free()
	if parked != null:
		tree.set_meta(DialogueView.META_RETURN, parked)
	print("[match talk] Back from the TIME OUT - the match carries on.")


func _my_unit_called(name_text: String) -> PlayerUnit:
	var wanted := CardDatabase._normalise(name_text)
	for unit in main.call("_everyone_ever"):
		var u := unit as PlayerUnit
		if u != null and not u.is_enemy and u.data != null \
				and CardDatabase._normalise(u.data.player_name) == wanted:
			return u
	return null


## `star:Koch` - he is a Star from now on: the badge, never tired by a
## Play Maker, and swapped out at the next STAR PLAYER SWITCH like any Star.
func make_star(name_text: String) -> void:
	var unit := _my_unit_called(name_text)
	if unit == null:
		push_warning("[match talk] star:%s - nobody of that name is playing for you." % name_text)
		return
	unit.data.player_type = "Star"
	unit.is_star_player = true
	# Spent this cycle as a plain player; a Star is never spent by a pick.
	unit.is_exhausted = false
	unit.is_playmaker = false
	unit.set_highlight(false)
	main.set("active_player_star", unit.data)
	print("[match talk] %s is a Star now." % unit.data.player_name)


## `keep_star` - at this STAR PLAYER SWITCH your Star is not swapped: he
## plays the next cycle too. Used once, by the switch that follows.
var _keep_star := false


func take_keep_star() -> bool:
	var kept := _keep_star
	_keep_star = false
	return kept


## `class:Koch=Bergmännlein` - he turns into that class: its element, its
## sprite on the pitch and on his card (the Earth Brew in the tutorial).
func change_class(name_text: String, klass: String) -> void:
	var unit := _my_unit_called(name_text)
	if unit == null:
		push_warning("[match talk] class:%s=%s - nobody of that name is playing for you." % [name_text, klass])
		return
	var db := CardDatabase.get_db()
	var data := unit.data
	data.unit_type = klass
	data.element = SquadSheet._element_of(klass, db)
	var art := SquadSheet._art_for("", klass, "m", db)
	if art != null:
		data.artwork = art
	unit.update_unit_data(data)
	print("[match talk] %s is a %s now." % [data.player_name, klass])


## `inspire:Koch=75` - how drunk (inspired) he is, in %, on THE DRUNK METER
## (drunk_book.gd, data/DrunkLevels.csv). At the star level his star ability
## (StarAbilities.csv) wakes up.
func inspire(name_text: String, percent: float) -> void:
	var unit := _my_unit_called(name_text)
	if unit == null:
		return
	DrunkBook.set_level(unit.data, percent)
	print("[match talk] %s is %d%% inspired." % [unit.data.player_name, int(percent)])


## `ability:Koch=TUT_KOCH_BEER` - that Abilities.csv row on both his sides.
func give_ability(name_text: String, ability_id: String) -> void:
	var unit := _my_unit_called(name_text)
	var db := CardDatabase.get_db()
	if unit == null or db.get_ability(ability_id) == null:
		push_warning("[match talk] ability:%s=%s - no such player or no such Abilities.csv row." % [name_text, ability_id])
		return
	unit.data.attack_ability_id = ability_id
	unit.data.defend_ability_id = ability_id
	print("[match talk] %s now has %s." % [unit.data.player_name, ability_id])


# =============================================================
#  THE EXHAUST ZONE BUTTON
#
#  Your cards used this cycle wait in the exhaust until the STAR PLAYER
#  SWITCH. The button bottom right says how many are there; press it to see
#  them (the same strip that lights up for a swap). Tuning.csv:
#      exhaust_button   false hides it
# =============================================================

func _build_exhaust_button() -> void:
	var db := CardDatabase.get_db()
	if not db.tune_bool("exhaust_button", true):
		return
	var layer = main.get("selection_ui")
	if layer == null:
		return
	_exhaust_button = Button.new()
	_exhaust_button.name = "ExhaustButton"
	_exhaust_button.focus_mode = Control.FOCUS_NONE
	_exhaust_button.add_theme_font_size_override("font_size", db.tune_int("exhaust_button_font_size", 24))
	_exhaust_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_exhaust_button.offset_left = -300.0
	_exhaust_button.offset_top = -78.0
	_exhaust_button.offset_right = -20.0
	_exhaust_button.offset_bottom = -20.0
	_exhaust_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_exhaust_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_exhaust_button.pressed.connect(_toggle_exhaust)
	(layer as Node).add_child(_exhaust_button)
	_refresh_exhaust()


func _process(delta: float) -> void:
	_tick += delta
	if _tick >= 0.4:
		_tick = 0.0
		_refresh_exhaust()


func _exhausted_count() -> int:
	var engine = main.get("abilities")
	if engine == null:
		return 0
	return (engine as AbilityEngine).cards_in(false, "exhaust").size()


func _refresh_exhaust() -> void:
	if _exhaust_button == null:
		return
	_exhaust_button.text = Loc.text("exhaust_button", "EXHAUST ZONE") + "  (%d)" % _exhausted_count()


var _exhaust_panel: PanelContainer


func _toggle_exhaust() -> void:
	_exhaust_open = not _exhaust_open
	if _exhaust_panel != null and is_instance_valid(_exhaust_panel):
		_exhaust_panel.queue_free()
		_exhaust_panel = null
	if not _exhaust_open:
		return
	_exhaust_panel = PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.03, 0.04, 0.06, 0.85)
	box.border_color = Color(1.0, 0.8, 0.3)
	box.set_border_width_all(3)
	box.set_corner_radius_all(8)
	box.set_content_margin_all(12)
	_exhaust_panel.add_theme_stylebox_override("panel", box)
	_exhaust_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var list := VBoxContainer.new()
	_exhaust_panel.add_child(list)
	var head := Label.new()
	head.text = Loc.text("exhaust_head", "YOUR EXHAUST ZONE")
	head.add_theme_font_size_override("font_size", 24)
	head.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
	list.add_child(head)
	var engine = main.get("abilities")
	var cards: Array = []
	if engine != null:
		cards = (engine as AbilityEngine).cards_in(false, "exhaust")
	if cards.is_empty():
		var none := Label.new()
		none.text = Loc.text("exhaust_empty", "Empty. Cards you play wait here\nuntil the STAR PLAYER SWITCH.")
		none.add_theme_font_size_override("font_size", 20)
		list.add_child(none)
	for c in cards:
		var line := Label.new()
		line.text = "%s  (Tier %s, P:%d)" % [c.player_name, c.get_tier_clean(), c.get_attack_power()]
		line.add_theme_font_size_override("font_size", 20)
		list.add_child(line)
	_exhaust_button.get_parent().add_child(_exhaust_panel)
	_exhaust_panel.reset_size()
	_exhaust_panel.position = _exhaust_button.position + Vector2(
		_exhaust_button.size.x - _exhaust_panel.size.x, -_exhaust_panel.size.y - 10.0)
