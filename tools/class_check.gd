extends SceneTree

# =============================================================
#  DO A CLASS'S SPREADSHEETS AGREE WITH EACH OTHER?
#
#  A class is spread over two files that have to line up:
#
#      Unit_Set_Lorelei.csv       the cards, grouped by `Set Name`
#      Lorelei Emblems.csv        the emblems, by `Name`
#
#  A Set Name in the first has to be an emblem Name in the second, because
#  they are the same thing: the emblem is the card, the set is the nine units
#  it unlocks. Nothing in the game could see when they did not match, and
#  the symptom of a mismatch is an emblem that unlocks nothing — which looks
#  exactly like an emblem you have not earned yet.
#
#  It also checks the ladder inside every set: three cards in each tier the
#  Stars do not hold, one of each rung.
#
#      godot --headless --script res://tools/class_check.gd
#
#  A tool, not part of the game. Nothing loads it.
# =============================================================

func _initialize() -> void:
	await process_frame

	var book := ClassBook.classes()
	print("")
	print("[class] ==== WHAT THE SPREADSHEETS DESCRIBE ====")
	for key in book:
		var entry: ClassBook.ClassEntry = book[key]
		# A class with neither Stars nor sets is somebody else's file — the
		# basic team, a scratch side — and is not worth a paragraph.
		if entry.stars.is_empty() and entry.sets.is_empty() and entry.emblems.is_empty():
			continue
		print("")
		print("[class] %s" % entry.unit_type.to_upper())
		print("[class]   Stars: %d%s" % [entry.stars.size(),
			"  (Tier %s)" % entry.star_tier if entry.star_tier != "" else ""])
		for star in entry.stars:
			print("[class]     %s  P%d" % [star.player_name, star.get_attack_power()])
		if entry.sets.is_empty():
			print("[class]   no emblem sets")
		for set_key in entry.sets:
			var kit: ClassBook.EmblemSet = entry.sets[set_key]
			var spread: Array[String] = []
			for tier in PlayerData.TIER_ORDER:
				var many := int(kit.by_tier.get(tier, 0))
				if many > 0:
					spread.append("%s x%d" % [tier, many])
			var badge: ClassBook.Emblem = entry.emblems.get(set_key)
			print("[class]   set '%s': %d cards  (%s)   emblem: %s" % [
				kit.id, kit.cards.size(), ", ".join(spread),
				badge.id if badge != null else "NONE OF THAT NAME"])
		for badge_key in entry.emblems:
			if not entry.sets.has(badge_key):
				var lone: ClassBook.Emblem = entry.emblems[badge_key]
				print("[class]   emblem '%s': no unit set of that name" % lone.id)

	# ---- and everything wrong ----
	print("")
	print("[class] ==== WHAT DOES NOT AGREE ====")
	var problems := ClassBook.trouble()
	if problems.is_empty():
		print("[class] nothing. Every class's files line up.")
	else:
		for line in problems:
			print("[class] %s" % line)
		print("")
		print("[class] %d problem(s). None of them stops the game running —" % problems.size())
		print("[class] they are the things that will not work the day the talent")
		print("[class] tree tries to use them.")

	# ============ AND, SEPARATELY, WHAT IS SIMPLY NOT WRITTEN YET ============
	#
	# A class with no emblem file is work you have not started, not work you
	# have got wrong. It used to be four complaints per class in the list
	# above, which is how one real finding ended up in a list of six.
	var waiting := ClassBook.waiting()
	if not waiting.is_empty():
		print("")
		print("[class] ==== NOT WRONG, JUST NOT WRITTEN YET ====")
		for line in waiting:
			print("[class] %s" % line)
	quit(0)
