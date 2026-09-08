class_name MatchReport
extends RefCounted

# =============================================================
#  WHAT YOU GAINED — the panel after a match
#
#  Talents, brews, unlocks and achievements all used to happen in silence.
#  Something appeared at the base three screens later and nothing ever said
#  why. Someone seeing the game for the first time could play a whole match
#  and not notice they had earned anything.
#
#  HOW IT WORKS, AND WHY IT IS DONE THIS WAY
#
#  It takes a photograph of GameState when the match starts, another at the
#  final whistle, and lists the differences. That means it needs NO help
#  from anything else. A Progression row you write tomorrow, a fixture
#  reward, a stat you invent in Stats.csv — all of it shows up here on its
#  own, because all of it is a flag, a counter or an unlock, and this file
#  simply notices those changing.
#
#  There is nothing to keep in step. There is no list of "things worth
#  announcing" to forget to add to.
#
#  It rides between scenes on the SceneTree, the same way TeamSelection and
#  GameState do, so the season screen can pick it up after the match scene
#  has already gone.
# =============================================================

const META_KEY := "cw_match_report"

## Counters that are plumbing rather than progress. `tune...` is a talent
## bonus, and the two season ones are bookkeeping the screen shows properly
## in its own table.
const HIDDEN: Array[String] = ["tune", "seasonmatch", "seasonnumber"]

var _before_flags: Dictionary = {}
var _before_counters: Dictionary = {}
var _before_unlocks: Dictionary = {}

## One entry per thing gained: {"kind", "text", "detail", "weight"}.
## kind is "unlock", "flag", "counter" or "note" — the screen colours by it.
var gains: Array[Dictionary] = []
var finished: bool = false

## What the fixture did, straight from SeasonDB.record() — the score, the
## opponent, whether that was the final. Empty when no fixture was on.
## It travels with the gains because both are wanted by the same screen at
## the same moment, and one thing to hand over is simpler than two.
var summary: Dictionary = {}


# =============================================================
#  THE TWO PHOTOGRAPHS
# =============================================================

static func snapshot(state: GameState) -> MatchReport:
	var report := MatchReport.new()
	if state == null:
		return report
	report._before_flags = state.flags.duplicate(true)
	report._before_counters = state.counters.duplicate(true)
	report._before_unlocks = state.unlocks.duplicate(true)
	return report


## Add a line by hand, for something that is not a flag, counter or unlock —
## a brew wearing off, for instance.
func note(text: String, detail: String = "") -> void:
	if text.strip_edges() == "":
		return
	gains.append({"kind": "note", "text": text, "detail": detail, "weight": 5})


## Compare, and turn the difference into English. Call once, after
## everything that could change the state has run.
func finish(state: GameState) -> void:
	if finished or state == null:
		return
	finished = true

	_collect_unlocks(state)
	_collect_flags(state)
	_collect_counters(state)
	_sort_by_weight()


func is_empty() -> bool:
	return gains.is_empty()


## The first `limit` lines, plus a line saying how many were left off.
func top(limit: int) -> Array[Dictionary]:
	if limit <= 0 or gains.size() <= limit:
		return gains
	var out: Array[Dictionary] = []
	for i in limit:
		out.append(gains[i])
	var left := gains.size() - limit
	out.append({
		"kind": "note",
		"text": "...and %d more" % left,
		"detail": "Raise gains_max_rows in Tuning.csv to see them all.",
		"weight": -1,
	})
	return out


# =============================================================
#  THE THREE KINDS OF DIFFERENCE
# =============================================================

func _collect_unlocks(state: GameState) -> void:
	for key in state.unlocks.keys():
		if _before_unlocks.has(key):
			continue
		gains.append({
			"kind": "unlock",
			"text": "Unlocked  %s" % state.unlocks[key],
			"detail": "Look for it at the base.",
			"weight": 100,
		})


func _collect_flags(state: GameState) -> void:
	for key in state.flags.keys():
		var name_key := String(key)
		if _before_flags.has(name_key):
			continue
		# The "this row already fired" bookkeeping is not an achievement.
		if name_key.begins_with(CardDatabase._normalise(Progression.DONE_PREFIX)):
			continue
		if _hidden(name_key):
			continue
		gains.append({
			"kind": "flag",
			"text": state.pretty(name_key),
			"detail": "",
			"weight": 60,
		})


func _collect_counters(state: GameState) -> void:
	for key in state.counters.keys():
		var name_key := String(key)
		if _hidden(name_key):
			continue

		var now := int(state.counters[name_key])
		var before := int(_before_counters.get(name_key, 0))
		var delta := now - before
		if delta <= 0:
			continue

		gains.append({
			"kind": "counter",
			"text": "%s  +%d" % [state.pretty(name_key), delta],
			"detail": "now %d" % now,
			# Bigger jumps read as more interesting, and a brand-new counter
			# is more interesting still.
			"weight": 10 + delta + (8 if before == 0 else 0),
		})


static func _hidden(name_key: String) -> bool:
	for prefix in HIDDEN:
		if name_key.begins_with(prefix):
			return true
	return false


## Highest weight first. An explicit insertion sort: the list is a handful of
## entries long, and this keeps two equal weights in the order they were found.
func _sort_by_weight() -> void:
	var sorted: Array[Dictionary] = []
	for entry in gains:
		var at := sorted.size()
		for i in sorted.size():
			if int(sorted[i]["weight"]) < int(entry["weight"]):
				at = i
				break
		sorted.insert(at, entry)
	gains = sorted


# =============================================================
#  RIDING BETWEEN SCENES
# =============================================================

static func stash(tree: SceneTree, report: MatchReport) -> void:
	if tree != null and report != null:
		tree.set_meta(META_KEY, report)


## Take it and clear it, so re-opening the season screen later does not show
## last match's gains all over again.
static func take(tree: SceneTree) -> MatchReport:
	if tree == null or not tree.has_meta(META_KEY):
		return null
	var report := tree.get_meta(META_KEY) as MatchReport
	tree.remove_meta(META_KEY)
	return report
