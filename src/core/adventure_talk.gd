class_name AdventureTalk
extends RefCounted

# =============================================================
#  ADVENTURE TALK — somebody stops an Adventure to explain  (round AN)
#
#  The Adventure version of MatchTalk.csv, and it uses the same file: a
#  MatchTalk.csv row whose Mode is an Adventure mode (MatchModes.csv Scene
#  = adventure, e.g. tutorial_adventure) plays at one of these moments:
#
#    adv_start    the party sets off
#    adv_pickup   the first thing to pick up comes past
#    adv_wave     a wave blocks the way (adv_boss for the boss's wave)
#    adv_focus    a fight round opens: point at an enemy
#    adv_draft    a Tier's cards are up (Tier column: I, II, III, IV)
#    adv_hit      all four are in and the move is worked out
#    adv_down     one of yours has run out of stamina
#    adv_loot     a wave is cleared: the loot and Continue / Return
#
#  ROUND is the wave number (1 = the first). HIGHLIGHT is different here:
#  it is the words on a button to light up after the box, the way Guide.csv
#  does it ("Return to base"). DO is not read.
#
#  The game is paused under the box and nothing can be clicked until it
#  closes. No row for a moment = nothing happens, so an ordinary Adventure
#  never notices this file.
# =============================================================

static var _busy := false


## Stop here if MatchTalk.csv has a row for this moment of this Adventure.
## Await it to wait until the box has closed.
static func talk(host: Node, event: String, facts: Dictionary = {}) -> void:
	if _busy or host == null or not host.is_inside_tree():
		return
	var tree := host.get_tree()
	var state := GameState.fetch(tree)
	var mode_id := String(MatchMode.current(tree).get("id", ""))
	var row := MatchTalk.row_for(event, mode_id, state, facts)
	if row.is_empty():
		return
	_busy = true
	print("[adventure talk] %s (wave %s, Tier %s): '%s'." % [event,
		str(facts.get("round", "-")), String(facts.get("tier", "-")), String(row["scene"])])
	var shield := _input_shield(host)
	var box := MatchTalkBox.play(host, String(row["scene"]), state, true)
	if box != null:
		await box.finished
	if is_instance_valid(shield):
		shield.queue_free()
	_busy = false
	if is_instance_valid(host):
		Guide.highlight(host, String(row.get("highlight", "")))


## A see-through sheet that swallows clicks while the box is up.
static func _input_shield(host: Node) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.name = "AdventureTalkShield"
	layer.layer = 149
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var sheet := Control.new()
	sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(sheet)
	host.add_child(layer)
	return layer
