class_name TutorialMorning
extends RefCounted

# =============================================================
#  THE MORNING AFTER — the Tutorial after the final whistle  (round AN)
#
#  Anthony, 8 Oct: "After the tutorial we need the sleep and rest system as
#  well as the adventure system." He picked "the morning after":
#
#    1. FULL TIME. The side that played counts its round like any match
#       would (Recovery.csv, Resting.csv) and their drunk meters drop
#       (DrunkBook.after_round). Then the scene in Tuning.csv
#       tutorial_morning_scene (the bar), and the base.
#    2. THE BASE AND THE DORMS. Guide.csv rows on the base and the Dorms
#       screen (all wait on flag:tut_morning): the Head Coach shows who is
#       in bed and why, says goodbye and leaves for the other town, and the
#       Adventure banner lights up.
#    3. THE ADVENTURE. MatchModes.csv tutorial_adventure stands in for an
#       Adventure while the morning is on: the party is
#       data/TutorialAdventureSquad.csv, and Koch stops the run at its
#       firsts (MatchTalk.csv rows with Mode tutorial_adventure, see
#       adventure_talk.gd).
#    4. HOME. However the run ends (count:adventures_played), the Dorms
#       open once more: the party in bed, the match side a fixture nearer
#       fit. The last Guide.csv row's Then is tutorial:end, which is
#       Tutorial.finish() - the base of your own save, as before.
#
#  It all happens in the tutorial's own save, so none of it is kept.
#  Tuning.csv tutorial_morning_after false ends the Tutorial at full time.
# =============================================================

const FLAG := "tut_morning"


## Is "the morning after" switched on? (Tuning.csv tutorial_morning_after.)
static func on() -> bool:
	return CardDatabase.get_db().tune_bool("tutorial_morning_after", true)


## Full time in the tutorial match: the side's round is counted in the
## tutorial save, then the full-time scene, then the base.
static func begin(tree: SceneTree, played: Array) -> void:
	var db := CardDatabase.get_db()
	var state := GameState.fetch(tree)
	MatchMode.clear(tree)
	TeamSelection.clear(tree)
	ScenePaths.clear_trail(tree)
	if state != null:
		# THE ROUND COUNTS, here only: rounds played, beds, drunk meters.
		RecoveryBook.after_match(played, state, db)
		DrunkBook.after_round(played, state, db)
		state.set_flag(FLAG)
		# What the base needs for the morning (Tuning.csv
		# tutorial_morning_effects): the Dorms and their key.
		var effects := db.tune_text("tutorial_morning_effects", "unlock:Dorms;count:dorms_key=1")
		if effects != "":
			DialogueGrammar.apply(effects, state)
		# The Head Coach shows them the Dorms himself, so the "New at the
		# base" panel does not come up under his box.
		NewUnlocksPanel.mark_all_seen(state)
		state.save_to_disk()
	var scene := db.tune_text("tutorial_morning_scene", "tut-morning-fulltime")
	print("[tutorial] Full time. The morning after: '%s', then the base." % scene)
	DialogueView.play(tree, scene, ScenePaths.BASE)
