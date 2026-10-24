class_name MatchCoach
extends Node

## Loaded by path, not by its class name: a Godot editor that has not
## re-scanned since a pull would not know the name yet, and the whole match
## would fail to load (the Deck, 8 Oct).
const DRINK_WINDOW := preload("res://src/ui/drink_window.gd")
const PLAYER_CARD: PackedScene = preload("res://src/ui/player_card_ui.tscn")

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
const BREWERY_SCENE := "res://src/ui/brewery_screen.tscn"

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


## True when this Play Maker has a drinking lesson in it (a MatchTalk.csv row
## for this mode and Round whose Do says drink_lesson), so every bag but the
## one being taught is greyed. Tuning.csv tutorial_bags_shut_in_lessons.
func lesson_this_play_maker() -> bool:
	if not CardDatabase.get_db().tune_bool("tutorial_bags_shut_in_lessons", true):
		return false
	var mode: Dictionary = main.get("match_mode")
	return MatchTalk.has_lesson(String(mode.get("id", "")), str(play_maker_number()))


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

	# A drinking lesson's card has its bag lit while he talks about it.
	_open_lesson_bag(String(row.get("do", "")))
	var box := MatchTalkBox.play(main, String(row["scene"]), state, true, groups)
	if box != null:
		main.set("_talk_box", box)
		await box.finished
	shield.queue_free()
	# The click that closed his last line must not also take the card under it.
	main.call("hold_picks")

	await _do(String(row.get("do", "")))
	_busy = false


func _open_lesson_bag(do_text: String) -> void:
	var at := do_text.find("drink_lesson:")
	if at < 0:
		return
	var head := do_text.substr(at + 13).get_slice("=", 0).strip_edges()
	var found := _controls_for("card:" + head)
	if found.is_empty():
		return
	var target := found[0] as PlayerCardUI
	main.set("bag_open_for", target.current_data)
	target.set_bag_shut(false)


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
		# ROUND AN (Anthony, 24 Oct): the coach's box goes above the referee's
		# bar while he talks about it (MatchTalkBox reads "above").
		var above := word.to_lower().begins_with("referee")
		for control in _controls_for(word):
			if control != null and control.is_visible_in_tree():
				out.append({"rect": control.get_global_rect(), "ring": ring, "control": control, "above": above})
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
	# referee / referee:you / referee:them - the referee's bar (round AN).
	if lower == "referee" or lower.begins_with("referee:"):
		var bar = main.get("ref_bar")
		if bar == null or not is_instance_valid(bar):
			return []
		return (bar as RefBar).spots(lower.substr(8) if lower.contains(":") else "")
	# flask:first / flask:<name> - the bag button on that card (round AN).
	if lower.begins_with("flask:"):
		var on := _controls_for("card:" + word.substr(6))
		if not on.is_empty():
			var flask = (on[0] as Node).get("_flask")
			return [flask] if flask != null else on
		return []
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
			"brewery":
				await brewery_time_out(value)
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
			"show_card":
				var at_card := value.find("=")
				if at_card > 0:
					var scene_words := value.substr(at_card + 1).strip_edges()
					var gold := ""
					if scene_words.contains("@"):
						gold = scene_words.get_slice("@", 1).strip_edges()
						scene_words = scene_words.get_slice("@", 0).strip_edges()
					await show_card(value.substr(0, at_card).strip_edges(), scene_words, gold)
			"drink_lesson":
				await drink_lesson(value)
			"give":
				give_items(value)
			"say":
				await say(value)
			"empty_bag":
				await empty_bag(value)
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
	# PUB MUSIC (Anthony, 23 Oct): the time out is in the bar, so it gets the
	# bar's music - Audio.csv rows pub_time_out_music / match_music_back_pub.
	AudioDirector.fire(tree, "time_out_started", {"where": "pub"})
	await view.scene_finished
	AudioDirector.fire(tree, "time_out_ended", {"where": "pub"})
	tree.paused = was_paused
	layer.queue_free()
	if parked != null:
		tree.set_meta(DialogueView.META_RETURN, parked)
	print("[match talk] Back from the TIME OUT - the match carries on.")


## ============ TIME OUT AT THE BREWERY (round AN) =====##
## `brewery:tut-brewery` - the match freezes and the whole screen becomes
## the Brewery, with the flag in the value set so Guide.csv rows (Screen
## brewery, Requires flag:tut-brewery) lead the way: the Brewer, the
## machines, the mini-games. A Guide.csv row whose Then says goto:back ends
## it; the flag is cleared and the match carries on from the same frame.
func brewery_time_out(flag: String) -> void:
	var tree := get_tree()
	if not ResourceLoader.exists(BREWERY_SCENE):
		return
	var state := GameState.fetch(tree)
	# tut-brewery and tut_brewery are the same flag.
	flag = flag.strip_edges().replace("-", "_")
	if state != null and flag != "":
		state.set_flag(flag, true)
	print("[match talk] TIME OUT at the Brewery - '%s'." % flag)
	var layer := CanvasLayer.new()
	layer.name = "BreweryTimeOut"
	layer.layer = 140
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	main.add_child(layer)
	var was_paused := tree.paused
	tree.paused = true
	var screen := (load(BREWERY_SCENE) as PackedScene).instantiate() as BreweryScreen
	screen.in_match = true
	layer.add_child(screen)
	# BREWERY MUSIC (Anthony, 23 Oct): the Brewery gets its own music here too
	# - Audio.csv rows brewery_time_out_music / match_music_back_brewery.
	AudioDirector.fire(tree, "time_out_started", {"where": "brewery"})
	await screen.left
	AudioDirector.fire(tree, "time_out_ended", {"where": "brewery"})
	if state != null and flag != "":
		state.set_flag(flag, false)
	tree.paused = was_paused
	layer.queue_free()
	print("[match talk] Back from the Brewery - the match carries on.")


## `say:tut-after-brewery@flask:first|-` - more of his lines in the middle
## of a Do (after the Brewery, say), with the gold per line after @ as in
## the Highlight column. Nothing can be clicked while he talks.
func say(value: String) -> void:
	var scene := value.get_slice("@", 0).strip_edges()
	var gold := value.get_slice("@", 1).strip_edges() if value.contains("@") else ""
	var shield := _input_shield()
	await get_tree().process_frame
	var groups: Array = []
	if gold != "":
		for part in gold.split("|"):
			groups.append(_spots_for(String(part)))
	var box := MatchTalkBox.play(main, scene, main.get("state"), true, groups)
	if box != null:
		main.set("_talk_box", box)
		await box.finished
	shield.queue_free()
	main.call("hold_picks")


## ============ THE BAG OPENS BY ITSELF, EMPTY ============
##
## `empty_bag:first` (Anthony, 24 Oct). After "Now open the bag on the
## Tier I, Power 1, and..." the bag on that card opens on its own and shows
## nothing in it, then shuts, and the next say: plays ("Where is the rest
## of the beer?!"). The word is a Highlight word without "card:" - first,
## last or a name. Tuning.csv tutorial_empty_bag_seconds = how long it
## stays open. Nothing can be clicked meanwhile.
func empty_bag(who: String) -> void:
	var found := _controls_for("card:" + who.strip_edges())
	if found.is_empty():
		push_warning("[match talk] empty_bag: no card '%s' on the table." % who)
		return
	var target := found[0] as PlayerCardUI
	var shield := _input_shield()
	var tree := get_tree()
	# A beat of gold on his bag button, as if somebody pressed it.
	var gold_layer := CanvasLayer.new()
	gold_layer.name = "EmptyBagGold"
	gold_layer.layer = 151
	gold_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	main.add_child(gold_layer)
	var flask := target.get("_flask") as Control
	_gold_on(gold_layer, [flask] if flask != null else [target])
	# Real seconds, so a match on fast speed does not rush it.
	await tree.create_timer(0.5, true, false, true).timeout
	gold_layer.queue_free()
	# No item id is called "-", so the bag shows its empty line.
	var bag := InventoryScreen.open(main, main.get("state"), InventoryScreen.Use.ON_CARD,
		"Using something on %s." % target.current_data.player_name, ["-"])
	bag.name = "EmptyBag"
	bag.process_mode = Node.PROCESS_MODE_ALWAYS
	print("[match talk] the bag on %s opens by itself - empty." % target.current_data.player_name)
	var hold := CardDatabase.get_db().tune_float("tutorial_empty_bag_seconds", 2.2)
	await tree.create_timer(maxf(0.3, hold), true, false, true).timeout
	if is_instance_valid(bag):
		bag.close()
	await tree.process_frame
	shield.queue_free()


## ============ THE DRINKING LESSON ============
##
## `drink_lesson:first=keg@barrel@tut-fass-after@card` (Anthony,
## 8 Oct). The cards are on the table and the Head Coach has asked for it:
##   1. the item goes in the bag (if it is not there), and the bag on that
##      card shows ONLY it. Gold on the card's bag button, then on the item;
##      nothing else can be clicked.
##   2. the player uses it -> the drinking window (barrel or bottle) with his
##      own sprite -> the scene after @, gold per line after the next @.
##   3. only that card can be picked.
## Parts: <card>=<item>@<barrel|bottle>@<scene>@<gold>. <card> is a word of
## the Highlight column without "card:" - first, last or a name. The scene
## plays over his card shown big (show_card), so the gold words are
## card / abilities / attack / defend / -.
## Several items with + between them (the combo lesson): the bag shows those
## of them that are in it, gold on each, and any one will do. Nothing is
## added for a list - give: puts them in the bag first.
func drink_lesson(spec: String) -> void:
	var parts := spec.split("@")
	var head := String(parts[0])
	var eq := head.find("=")
	if eq <= 0:
		push_warning("[match talk] drink_lesson:%s - write it card=item@barrel@scene@gold." % spec)
		return
	var who := head.substr(0, eq).strip_edges()
	var item_id := head.substr(eq + 1).strip_edges()
	# Several items with + between them: the player picks any one of them.
	var items: Array = []
	for part in item_id.split("+", false):
		items.append(String(part).strip_edges())
	var vessel := String(parts[1]).strip_edges() if parts.size() > 1 else "barrel"
	var after := String(parts[2]).strip_edges() if parts.size() > 2 else ""
	var gold := String(parts[3]).strip_edges() if parts.size() > 3 else "abilities"
	var state: GameState = main.get("state")
	if state == null:
		return
	if items.size() == 1 and state.count(item_id) <= 0:
		state.add_count(item_id, 1)
	main.set("bag_only", items)
	main.call("_redraw_offered_cards")
	await get_tree().process_frame

	var found := _controls_for("card:" + who)
	if found.is_empty():
		push_warning("[match talk] drink_lesson: no card '%s' on the table." % who)
		main.set("bag_only", [])
		return
	var target := found[0] as PlayerCardUI
	var drinker := target.current_data

	# Only his bag button works.
	main.set("bag_open_for", drinker)
	target.set_bag_shut(false)
	_lock_all_but_flask(target)
	var gold_layer := CanvasLayer.new()
	gold_layer.name = "DrinkLessonGold"
	gold_layer.layer = 151
	gold_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	main.add_child(gold_layer)
	var flask := target.get("_flask") as Control
	_gold_on(gold_layer, [flask] if flask != null else [target])

	var used := [false]
	var on_open := func(bag: InventoryScreen) -> void:
		await get_tree().process_frame
		await get_tree().process_frame
		var tiles: Array = []
		for one in items:
			var tile := bag.tile_for(one)
			if tile != null:
				tiles.append(tile)
		print("[match talk] drink lesson: the bag is open, gold on %d of %s." % [tiles.size(), item_id])
		var layer_now := main.get_node_or_null("DrinkLessonGold") as CanvasLayer
		if layer_now != null:
			_gold_on(layer_now, tiles)
		bag.tree_exited.connect(func() -> void:
			# Closed without using it: back to his bag button.
			var still := main.get_node_or_null("DrinkLessonGold") as CanvasLayer
			if not used[0] and still != null and is_instance_valid(target):
				_lock_all_but_flask(target)
				var again := target.get("_flask") as Control
				_gold_on(still, [again] if again != null else [target]))
	main.connect("bag_opened", on_open)
	print("[match talk] drink lesson: waiting for %s on %s." % [item_id, drinker.player_name])
	while true:
		var got: Array = await _next_item_used()
		if got[0] == drinker and items.has(String((got[1] as Dictionary).get("id", ""))):
			break
	used[0] = true
	main.disconnect("bag_opened", on_open)
	gold_layer.queue_free()
	main.set("bag_only", [])
	# He has had his; his bag shuts with the rest.
	main.set("bag_open_for", null)
	if bool(main.get("bags_shut")) and is_instance_valid(target):
		target.set_bag_shut(true)

	# The drinking window, the match still frozen.
	var tree := get_tree()
	var was_paused := tree.paused
	tree.paused = true
	var window = DRINK_WINDOW.play(main, drinker, vessel)
	await window.finished
	tree.paused = was_paused

	# Only he can be picked now. His new card comes up big, the way
	# Bergmännlein Koch's does, and the scene after @ plays over it.
	_lock_all_but(target)
	if after != "":
		await show_card(drinker.player_name, after, gold)
	_lock_all_but(target)
	main.call("hold_picks")


## `give:anstoss_helles+doppelpass_weisse` - one of each into the bag
## (`item=3` for more than one).
func give_items(value: String) -> void:
	var state: GameState = main.get("state")
	if state == null:
		return
	for part in value.split("+", false):
		var one := String(part).strip_edges()
		var how_many := 1
		if one.contains("="):
			how_many = maxi(1, int(one.get_slice("=", 1)))
			one = one.get_slice("=", 0).strip_edges()
		if AdventureDB.get_db().item(one).is_empty():
			push_warning("[match talk] give:%s - Items.csv has no such item." % one)
			continue
		state.add_count(one, how_many)
	main.call("_redraw_offered_cards")


func _next_item_used() -> Array:
	var got: Array = await main.item_used_on_card
	return got


func _table_cards() -> Array:
	var out: Array = []
	var row = main.get("card_container")
	if row != null:
		for child in (row as Node).get_children():
			if child is PlayerCardUI and not child.is_queued_for_deletion():
				out.append(child)
	return out


func _lock_all_but_flask(target: PlayerCardUI) -> void:
	for card in _table_cards():
		var c := card as PlayerCardUI
		if c != target:
			c.set_locked(true)
			continue
		c.set_locked(false)
		var face = c.get("_face")
		if face != null:
			(face as Button).disabled = true
			(face as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE


func _lock_all_but(target: PlayerCardUI) -> void:
	for card in _table_cards():
		(card as PlayerCardUI).set_locked(card != target)


func _gold_on(layer: CanvasLayer, controls: Array) -> void:
	for child in layer.get_children():
		child.queue_free()
	var spots: Array = []
	for control in controls:
		if control != null and is_instance_valid(control) and (control as Control).is_visible_in_tree():
			spots.append({"rect": (control as Control).get_global_rect(), "ring": false})
	if not spots.is_empty():
		layer.add_child(MatchTalkBox.CoachSpots.make(spots))


## The bottom of the screen the coach's box (and his face) takes, and the
## gap kept around the big card.
const SHOW_CARD_BOX_ROOM := 260.0
const SHOW_CARD_MARGIN := 24.0

## ============ HIS NEW CARD ============
##
## `show_card:Koch=tut-koch-new-card` (Anthony, 8 Oct) - the match stays
## frozen and his card, the same one you pick on the field, comes up big
## over the pub, with his attack and defend abilities spelled out beside it.
## Then the scene's lines play. After an @ comes the gold, one group per
## line with | between them, the way MatchTalk.csv Highlight works:
## card, abilities, attack, defend, or - for nothing.
##   show_card:Koch=tut-koch-new-card@abilities|-|-
func show_card(name_text: String, scene: String, gold: String = "card") -> void:
	var unit := _my_unit_called(name_text)
	if unit == null or unit.data == null:
		push_warning("[match talk] show_card:%s - nobody of that name is playing for you." % name_text)
		return
	var tree := get_tree()
	var db := CardDatabase.get_db()
	var data := unit.data
	var layer := CanvasLayer.new()
	layer.name = "NewCard"
	layer.layer = 145
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	main.add_child(layer)
	var was_paused := tree.paused
	tree.paused = true

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(root)
	if not StoryArt.add_backdrop(root, db.tune_text("show_card_backdrop", "bar"), 0.6):
		var black := ColorRect.new()
		black.color = Color(0, 0, 0, 0.8)
		black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root.add_child(black)

	var screen := root.get_viewport_rect().size
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 70)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(row)

	# The field card, bigger - but never so big that it runs into the
	# coach's box along the bottom or off the screen (Anthony, 24 Oct).
	var grow := db.tune_float("show_card_scale", 1.8)
	var base := PlayerCardUI.card_size()
	var room := Vector2(screen.x - 80.0 - 70.0 - 520.0, screen.y - SHOW_CARD_BOX_ROOM - 2.0 * SHOW_CARD_MARGIN)
	grow = minf(grow, minf(room.x / base.x, room.y / base.y))
	var holder := Control.new()
	holder.custom_minimum_size = PlayerCardUI.card_size() * grow
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(holder)
	var card := PLAYER_CARD.instantiate() as PlayerCardUI
	holder.add_child(card)
	card.setup_card(data)
	card.scale = Vector2(grow, grow)

	# Beside it, the two abilities.
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 18)
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	side.custom_minimum_size = Vector2(520, 0)
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(side)
	side.add_child(MenuSupport.heading("%s %s" % [data.unit_type.to_upper(), data.player_name.to_upper()], 30, MenuSupport.COLOUR_ACCENT))
	var attack_box := _ability_box(side, "ON ATTACK", data.active_attack_ability(), data)
	var defend_box := _ability_box(side, "ON DEFEND", data.active_defend_ability(), data)

	# Middle of the screen, above the coach's box along the bottom.
	await tree.process_frame
	var used := row.get_combined_minimum_size()
	row.position = Vector2((screen.x - used.x) * 0.5,
		maxf(SHOW_CARD_MARGIN, (screen.y - SHOW_CARD_BOX_ROOM - used.y) * 0.5))
	await tree.process_frame

	var groups: Array = []
	for part in gold.split("|"):
		var group: Array = []
		for word in String(part).split(";", false):
			var spots: Array = []
			match String(word).strip_edges().to_lower():
				"card": spots = [holder]
				"abilities": spots = [attack_box, defend_box]
				"attack": spots = [attack_box]
				"defend": spots = [defend_box]
			for control in spots:
				group.append({"rect": (control as Control).get_global_rect(), "ring": false})
		groups.append(group)
	print("[match talk] %s's new card is up: '%s'." % [data.player_name, scene])
	var box := MatchTalkBox.play(main, scene, main.get("state"), true, groups)
	if box != null:
		main.set("_talk_box", box)
		await box.finished
	tree.paused = was_paused
	layer.queue_free()


func _ability_box(host: Control, title: String, ability_id: String, card: PlayerData = null) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",
		MenuSupport.panel_style(MenuSupport.COLOUR_PANEL, MenuSupport.COLOUR_ACCENT))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(panel)
	var inner := VBoxContainer.new()
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(inner)
	inner.add_child(MenuSupport.heading(title, 16, MenuSupport.COLOUR_TEXT_DIM))
	var db := CardDatabase.get_db()
	var ability := db.get_ability(ability_id) if ability_id.strip_edges() != "" else null
	if ability == null:
		inner.add_child(MenuSupport.heading("No ability", 22))
		return panel
	inner.add_child(MenuSupport.heading(ability.display_name, 24, MenuSupport.COLOUR_ACCENT))
	var line := Label.new()
	line.text = _ability_words(ability, db, card)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.custom_minimum_size = Vector2(480, 0)
	line.add_theme_font_size_override("font_size", 20)
	inner.add_child(line)
	return panel


## His ability in a sentence for the new card. The keeper ones read the way
## the Head Coach says them; anything else falls back to the card popup's words.
func _ability_words(ability: AbilityData, db: CardDatabase, card: PlayerData = null) -> String:
	match CardDatabase._normalise(ability.effect):
		"addpowerpertiermate":
			# Anthony's words for the Kleiner Faß, 8 Oct.
			var who := ("Tier %s player" % card.get_tier_clean()) if card != null else "player of the same Tier"
			return "For each other %s not in the Exhaust Zone, give this %+d Power during combat." % [who, ability.value]
		"addpowerperplayed":
			return ability.plain()
		"drainstamina":
			return "Their keeper loses %d stamina." % ability.value
		"restorestamina":
			return "Your keeper gets %d stamina back." % ability.value
	var words := CardPopup.new()
	words.db = db
	var text := words._plain_english(ability)
	words.free()
	return text


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
## `ability:Koch=TUT_KOCH_EARTH/TUT_KOCH_EARTH_DEF` - attack side / defend side.
func give_ability(name_text: String, ability_id: String) -> void:
	var unit := _my_unit_called(name_text)
	var db := CardDatabase.get_db()
	var sides := ability_id.split("/")
	var attack_id := sides[0].strip_edges()
	var defend_id := sides[1].strip_edges() if sides.size() > 1 else attack_id
	if unit == null or db.get_ability(attack_id) == null or db.get_ability(defend_id) == null:
		push_warning("[match talk] ability:%s=%s - no such player or no such Abilities.csv row." % [name_text, ability_id])
		return
	unit.data.attack_ability_id = attack_id
	unit.data.defend_ability_id = defend_id
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
	# 24 Oct 2026 (Anthony): while the coach talks about it, it comes in
	# front of the dark sheet (MatchTalkBox), then goes back.
	_exhaust_button.set_meta("lift_in_talk", true)
	ScreenLook.plank(_exhaust_button)
	(layer as Node).add_child(_exhaust_button)
	_draw_exhaust_icon(db.tune_text("exhaust_icon", "coaster").strip_edges().to_lower(),
		db.tune_float("exhaust_icon_scale", 1.0))
	_refresh_exhaust()


# -------------------------------------------------------------
#  THE DRAWN EXHAUST MARKER (Anthony 23 Oct 2026: "cannot see it, it blends
#  in too much"). Tuning.csv exhaust_icon picks the look:
#      plank    the blue wooden plank, the empty Maß on its end
#      coaster  a blue-white beer mat with the empty Maß on it
#      mug      a big empty Maß, the words on a plank under it
#      plain    the old grey button
#  Each has a dark aura so it stands off the grass, and a red disc with the
#  count. Pieces: assets/ui/exhaust (tools/make_exhaust_icon.py).
# -------------------------------------------------------------

const EXHAUST_ART := "res://assets/ui/exhaust/"
var _exhaust_count_label: Label = null
var _exhaust_words: Control = null


func _draw_exhaust_icon(look: String, scale: float) -> void:
	if look == "plain" or ScreenLook.picture(EXHAUST_ART + "mug.png") == null:
		return
	var b := _exhaust_button
	var plank_row := {MenuSupport.normalise("Image"): "res://assets/menu/button_plank_drawn.png",
		MenuSupport.normalise("Scale"): "1", MenuSupport.normalise("Colour"): "#ffffff"}
	var words := Loc.text("exhaust_button", "EXHAUST ZONE")
	var mug_at := Rect2()
	var badge_at := Vector2()
	match look:
		"coaster", "mug":
			var box := Vector2(190, 190) if look == "coaster" else Vector2(150, 230)
			box *= scale
			b.offset_left = -20.0 - box.x - 30.0 * scale
			b.offset_right = -20.0 - 30.0 * scale
			b.offset_top = -74.0 - box.y
			b.offset_bottom = -74.0
			b.flat = true
			for state in ["normal", "hover", "pressed", "focus", "disabled"]:
				b.add_theme_stylebox_override(state, StyleBoxEmpty.new())
			if look == "coaster":
				_exhaust_piece("coaster", Rect2(Vector2.ZERO, box))
				var mh := box.y * 0.62
				mug_at = Rect2(Vector2(box.x * 0.5 - mh * 0.27, box.y * 0.17), Vector2(mh * 0.54, mh))
				badge_at = Vector2(box.x * 0.80, box.y * 0.14)
			else:
				var mh := box.y * 0.86
				mug_at = Rect2(Vector2(box.x * 0.5 - mh * 0.27, 0), Vector2(mh * 0.54, mh))
				badge_at = Vector2(box.x * 0.30, box.y * 0.56)
			_exhaust_piece("mug", mug_at)
			# The words on a small plank across the foot.
			var sign_board := Button.new()
			sign_board.text = words
			sign_board.focus_mode = Control.FOCUS_NONE
			sign_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
			sign_board.add_theme_font_size_override("font_size", int(20 * scale))
			sign_board.size = Vector2(box.x + 60.0 * scale, 46.0 * scale)
			sign_board.position = Vector2(-30.0 * scale, box.y - 18.0 * scale)
			b.add_child(sign_board)
			ScreenLook._dress(sign_board, plank_row)
			_exhaust_words = sign_board
		_:
			# plank: the button itself is the plank, the Maß stands on its end.
			b.offset_left = -20.0 - 330.0 * scale
			b.offset_top = -44.0 - 64.0 * scale
			b.offset_right = -20.0
			b.offset_bottom = -44.0
			ScreenLook._dress(b, plank_row)
			b.alignment = HORIZONTAL_ALIGNMENT_RIGHT
			var mh := 150.0 * scale
			mug_at = Rect2(Vector2(-34.0 * scale, 64.0 * scale - mh + 8.0 * scale), Vector2(mh * 0.54, mh))
			badge_at = Vector2(322.0 * scale, 4.0 * scale)
			var glow := Panel.new()
			var shade := StyleBoxFlat.new()
			shade.bg_color = Color(0, 0, 0, 0)
			shade.shadow_color = Color(0.04, 0.02, 0.0, 0.8)
			shade.shadow_size = int(16 * scale)
			shade.set_corner_radius_all(int(12 * scale))
			glow.add_theme_stylebox_override("panel", shade)
			glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
			glow.show_behind_parent = true
			glow.position = Vector2(4, 4) * scale
			glow.size = Vector2(330, 56) * scale
			b.add_child(glow)
			_exhaust_piece("mug", mug_at)
	# The count on a red disc.
	var d := 58.0 * scale
	var badge_rect := Rect2(badge_at - Vector2(d, d) * 0.5, Vector2(d, d))
	_exhaust_piece("badge", badge_rect)
	_exhaust_count_label = Label.new()
	_exhaust_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_exhaust_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_exhaust_count_label.position = badge_rect.position
	_exhaust_count_label.size = badge_rect.size
	_exhaust_count_label.add_theme_font_size_override("font_size", int(28 * scale))
	_exhaust_count_label.add_theme_color_override("font_color", Color("fff6e0"))
	_exhaust_count_label.add_theme_color_override("font_outline_color", Color("19110a"))
	_exhaust_count_label.add_theme_constant_override("outline_size", 6)
	_exhaust_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(_exhaust_count_label)
	if look == "plank":
		b.text = words
	else:
		b.text = ""
	b.mouse_entered.connect(func() -> void: b.modulate = Color(1.15, 1.1, 1.0))
	b.mouse_exited.connect(func() -> void: b.modulate = Color.WHITE)


## One drawn piece and its dark aura, laid on the button (clicks pass through).
func _exhaust_piece(piece: String, at: Rect2) -> void:
	var art := ScreenLook.picture(EXHAUST_ART + piece + ".png")
	var glow := ScreenLook.picture(EXHAUST_ART + piece + "_aura.png")
	if art == null:
		return
	if glow != null:
		var pad := at.size * (Vector2(glow.get_size()) / Vector2(art.get_size()) - Vector2.ONE) * 0.5
		var aura := _exhaust_rect(glow, Rect2(at.position - pad, at.size + pad * 2.0))
		aura.self_modulate = Color(0.04, 0.02, 0.0, 0.85)
	_exhaust_rect(art, at)


func _exhaust_rect(texture: Texture2D, at: Rect2) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.position = at.position
	rect.size = at.size
	_exhaust_button.add_child(rect)
	return rect


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
	if _exhaust_count_label != null:
		_exhaust_count_label.text = str(_exhausted_count())
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
