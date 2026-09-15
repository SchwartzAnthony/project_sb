class_name TeamBuilderHandoff
extends RefCounted

# =============================================================
#  WHICH TEAM THE BUILDER IS WORKING ON
#
#  The builder is opened from two places and has to behave differently:
#
#    CREATE TEAM   no id stashed   -> start from scratch, save a new team
#    EDIT TEAM     an id stashed   -> load that team, save over it
#
#  One value on the SceneTree says which. Same trick as TeamSelection and
#  GameState — no autoload to register, and it survives the scene change.
#
#  It also carries WHERE TO GO when the builder is finished, so the builder
#  does not need to know whether it was reached from the team shelf, the
#  base, or anywhere you add later.
# =============================================================

const KEY := "cw_builder_team"
const BACK_KEY := "cw_builder_back"


## Edit an existing team.
static func edit(tree: SceneTree, team_id: String, back: String = "") -> void:
	if tree == null:
		return
	tree.set_meta(KEY, team_id)
	if back != "":
		tree.set_meta(BACK_KEY, back)


## Start a new one.
static func clear(tree: SceneTree) -> void:
	if tree != null and tree.has_meta(KEY):
		tree.remove_meta(KEY)


## The team being edited, or "" for a new one.
static func current(tree: SceneTree) -> String:
	if tree == null or not tree.has_meta(KEY):
		return ""
	return String(tree.get_meta(KEY))


## Where to go when the builder is done. The team shelf unless something
## said otherwise.
static func back_to(tree: SceneTree) -> String:
	if tree != null and tree.has_meta(BACK_KEY):
		return String(tree.get_meta(BACK_KEY))
	return ScenePaths.TEAM_SELECT
