class_name TraitStack
extends RefCounted

# =============================================================
#  THE RUNNING STACK
#
#  What is on the pile right now, and what that is currently worth. The
#  spreadsheets are trait_db.gd; this is the one object that remembers.
#
#  ============ WHEN IT EMPTIES ============
#
#  NOT AT THE END OF A ROUND. When the CYCLE comes round — when every tier
#  has fielded everybody it has and they all become available again, which is
#  the same rotation your Stars use in a league match. So a fight is one long
#  build with a reset in the middle of it, and "do I spend my last Fire now
#  or hold the tier open" is a real question.
#
#  adventure_encounter.gd calls clear() when adventure_run.gd tells it the
#  cycle closed. Nothing else empties it.
#
#  ============ HELD AND ONCE ============
#
#  A `held` breakpoint is worth something for as long as the count stays at
#  or above its At. Only the HIGHEST one in a trait counts, so Blaze replaces
#  Kindling rather than stacking with it.
#
#  A `once` breakpoint fires the moment you first reach it and is then marked
#  paid for the rest of the cycle. Reaching it again after a reset fires it
#  again, which is the reward for going round twice.
# =============================================================

## trait id -> how many are on the pile.
var counts: Dictionary = {}

## The ids of `once` breakpoints that have already gone off this cycle.
var paid: Dictionary = {}

## How many players have been added since the last reset. Only for the log.
var added: int = 0


func clear() -> void:
	counts.clear()
	paid.clear()
	added = 0


func count_of(trait_id: String) -> int:
	return int(counts.get(trait_id.to_lower(), 0))


## Put one player's icons on the pile.
##
## Returns the `once` breakpoints this crossed, in the order they should
## fire — lowest first, so a trait that jumps two steps at once pays out in
## the order a player would read them.
func add(card: PlayerData) -> Array[Dictionary]:
	return add_icons(TraitDB.icons_of(card))


## The same, for anything that is not a card. Kept separate so a stand-in
## brought on by a spawn can carry icons too.
func add_icons(icons: Array[String]) -> Array[Dictionary]:
	var fired: Array[Dictionary] = []
	for icon in icons:
		var key := icon.to_lower()
		counts[key] = int(counts.get(key, 0)) + 1
		for step in TraitDB.reached(key, int(counts[key])):
			var row: Dictionary = step
			if String(row["lasts"]) != "once":
				continue
			var step_id := String(row["id"])
			if paid.has(step_id):
				continue
			paid[step_id] = true
			fired.append(row)
	added += 1
	return fired


# =============================================================
#  WHAT THE PILE IS WORTH RIGHT NOW
# =============================================================

## Every `held` breakpoint currently active — at most one per trait, the
## highest reached. This is what the shot and the shield are worked out from,
## and what the bar across the top shows as lit.
func active() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in TraitDB.get_db().traits:
		var key := String(entry["id"]).to_lower()
		var have := int(counts.get(key, 0))
		if have <= 0:
			continue
		var best := TraitDB.best(key, have)
		if best.is_empty() or String(best["lasts"]) != "held":
			continue
		out.append(best)
	return out


## What the stack adds to the shot. Added to the SHOT and never to a card —
## a card's power is the tier ladder, and nothing is allowed to move it.
func attack_bonus() -> int:
	var total := 0
	for step in active():
		if String((step as Dictionary)["effect"]) == "attack":
			total += int((step as Dictionary)["value"])
	return total


## What the stack takes off each hit against you.
func shield() -> int:
	var total := 0
	for step in active():
		if String((step as Dictionary)["effect"]) == "shield":
			total += int((step as Dictionary)["value"])
	return total


## One line for the log: "Fire 3/4 — Blaze +4   ·   Lorelei 2/4 — Same Song".
func describe() -> String:
	var bits: Array[String] = []
	for entry in TraitDB.get_db().traits:
		var key := String(entry["id"]).to_lower()
		var have := int(counts.get(key, 0))
		if have <= 0:
			continue
		var best := TraitDB.best(key, have)
		var word := String(best["name"]) if not best.is_empty() else "—"
		bits.append("%s %d/%d %s" % [entry["name"], have,
			TraitDB.next_at(key, have), word])
	return "   ·   ".join(bits) if not bits.is_empty() else "nothing on the pile yet"
