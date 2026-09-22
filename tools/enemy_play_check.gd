extends SceneTree

# =============================================================
#  DO THE OPPOSITION'S RULES DO WHAT THE SPREADSHEET SAYS?
#
#  EnemyPlay.csv is the other side's whole brain: a list of rules read top to
#  bottom, first match wins. A rule that never fires is invisible in a match —
#  you simply never see the behaviour and have no way of knowing whether the
#  row is wrong, the condition is wrong, or a row above it is eating it.
#
#  So this puts the same four cards in front of the rules over and over, in
#  every situation the columns can describe, and prints which rule answered
#  and what it chose. Every row of your file should appear somewhere in the
#  list; a row that never appears is a row that can never happen.
#
#      godot --headless --script res://tools/enemy_play_check.gd
#
#  A tool, not part of the game. Nothing loads it.
# =============================================================

func _initialize() -> void:
	await process_frame
	var db := CardDatabase.get_db()

	var rules := EnemyPlay.rules()
	print("[enemy] %d rule(s), in the order they are read:" % rules.size())
	for rule in rules:
		print("[enemy]   %3d  %-22s when %-14s pick %-14s reveal %s%s" % [
			rule.order, rule.id, rule.when_text, rule.pick, rule.reveal,
			"   (style: %s)" % rule.style if rule.style != "" else ""])

	# ---- four cards of one tier, out of your own spreadsheets ----
	var choices: Array = []
	for tier in ["III", "II", "IV", "I"]:
		choices = []
		for card in db.players:
			if card.get_tier_clean() == tier:
				choices.append(card)
			if choices.size() >= 4:
				break
		if choices.size() >= 2:
			break
	if choices.size() < 2:
		print("[enemy] not enough cards in one tier to test with")
		quit(1)
		return

	print("")
	print("[enemy] testing with: %s" % ", ".join(choices.map(
		func(c) -> String: return "%s (P%d/D%d)" % [
			c.player_name, c.get_attack_power(), c.get_defense_power()])))
	print("")

	# ============ FLAGS, so a scripted rule gets a turn too ============
	#
	# A rule whose When is `flag:something` can only fire while that flag is
	# set in a real save, so without this every scripted row would be reported
	# as "never fires" — which is the opposite of the truth.
	# Left CLEAR for the main run, so the ordinary rules are the ones being
	# reported. Each flag rule then gets a pass of its own below.
	var pretend := GameState.new()
	var scripted: Array = []
	for rule in rules:
		if rule.when_text.begins_with("flag"):
			scripted.append(rule)

	var fired := {}
	var situations := [
		{"what": "you hid, level, they attack", "you_revealed": null,
			"attacking": true, "their_goals": 0, "your_goals": 0, "round": 1},
		{"what": "you SHOWED one", "you_revealed": choices[0],
			"attacking": false, "their_goals": 0, "your_goals": 0, "round": 1},
		{"what": "they are winning", "you_revealed": null,
			"attacking": false, "their_goals": 2, "your_goals": 0, "round": 2},
		{"what": "they are losing", "you_revealed": null,
			"attacking": true, "their_goals": 0, "your_goals": 3, "round": 3},
	]

	for tier in ["I", "II", "III", "IV"]:
		for case in situations:
			var facts := (case as Dictionary).duplicate()
			facts["tier"] = tier
			facts["choices"] = choices
			facts["style"] = ""
			facts["state"] = pretend
			var verdict := EnemyPlay.decide(facts)
			var card = verdict.get("card", null)
			var rule_id := String(verdict.get("rule", ""))
			fired[rule_id] = true
			print("[enemy] Tier %-3s %-28s -> %-28s %s   (rule: %s)" % [
				tier, case["what"],
				card.player_name if card != null else "NOTHING",
				"FACE UP" if bool(verdict.get("face_up", false)) else "face down",
				rule_id if rule_id != "" else "none matched"])

	# ---- and one pass per scripted rule, with its flag set ----
	for rule in scripted:
		var one := GameState.new()
		var flag_name: String = rule.when_text.substr(4)
		one.set_flag(flag_name)
		var facts2 := {
			"tier": "III", "choices": choices, "style": "", "state": one,
			"you_revealed": null, "attacking": true,
			"their_goals": 0, "your_goals": 0, "round": 1,
		}
		var verdict2 := EnemyPlay.decide(facts2)
		fired[String(verdict2.get("rule", ""))] = true
		print("")
		print("[enemy] with the flag behind '%s' set:" % rule.id)
		print("[enemy]   -> %s %s   (rule: %s)   Do: %s" % [
			verdict2["card"].player_name if verdict2.get("card", null) != null else "NOTHING",
			"FACE UP" if bool(verdict2.get("face_up", false)) else "face down",
			verdict2.get("rule", ""),
			verdict2.get("do", "") if String(verdict2.get("do", "")) != "" else "nothing"])

	print("")
	var never := 0
	for rule in rules:
		if not fired.has(rule.id):
			print("[enemy] NEVER FIRED: '%s'. Either its When cannot happen, or a rule above it with a lower Order is claiming the same situations." % rule.id)
			never += 1
	if never == 0:
		print("[enemy] every rule in the file fired at least once.")
	quit(0)
