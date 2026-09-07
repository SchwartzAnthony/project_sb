class_name TeamSelection
extends RefCounted

# =============================================================
#  TEAM SELECTION — what you picked, carried into the match
#
#  The class-select and team-builder screens fill this in, then hand it to
#  the match. It is stored on the SceneTree, which survives
#  change_scene_to_file(), so NOTHING has to be set up in Project Settings —
#  no autoload, no singleton to register.
#
#  If a match starts with no selection stored (you ran main_scene.tscn
#  directly, or came from the old menu), main_scene falls back to its
#  original random kickoff draft. Both paths keep working.
# =============================================================

const META_KEY := "cw_team_selection"

## The class / race you locked in, e.g. "Brandteufel".
var unit_type: String = ""

## Which Tier your Star Players occupy — that tier is locked in the builder.
var star_tier: String = ""

## All three Stars of the class. The match rotates through these at HOLD UP!.
var star_bundle: Array[PlayerData] = []

## The Star that starts the match.
var active_star: PlayerData = null

## Tier key ("I".."IV") -> the three regulars you chose for it.
## The Star's own tier is absent — the Stars fill it.
var regulars: Dictionary = {}


# -------------------------------------------------------------
#  HAND-OFF
# -------------------------------------------------------------

## Park this selection where the next scene can find it.
static func store(tree: SceneTree, selection: TeamSelection) -> void:
	if tree == null or selection == null:
		return
	tree.set_meta(META_KEY, selection)


## Pick up a selection stored by an earlier scene, or null if there is none.
static func fetch(tree: SceneTree) -> TeamSelection:
	if tree == null or not tree.has_meta(META_KEY):
		return null
	return tree.get_meta(META_KEY) as TeamSelection


## Forget the stored selection, so the next match falls back to a random draft.
static func clear(tree: SceneTree) -> void:
	if tree != null and tree.has_meta(META_KEY):
		tree.remove_meta(META_KEY)


# -------------------------------------------------------------
#  QUERIES
# -------------------------------------------------------------

## Which tiers still need filling in? Empty array means the team is legal.
func missing_tiers(all_tiers: Array[String], per_tier: int = 3) -> Array[String]:
	var missing: Array[String] = []
	for tier in all_tiers:
		if tier == star_tier:
			continue
		var picked: Array = regulars.get(tier, [])
		if picked.size() < per_tier:
			missing.append(tier)
	return missing


func is_complete(all_tiers: Array[String], per_tier: int = 3) -> bool:
	return unit_type != "" and active_star != null \
		and missing_tiers(all_tiers, per_tier).is_empty()


## Every regular you chose, flattened — handy for spawning.
func all_regulars() -> Array[PlayerData]:
	var out: Array[PlayerData] = []
	for tier in regulars.keys():
		for card in (regulars[tier] as Array):
			if card != null:
				out.append(card)
	return out


func describe() -> String:
	var parts: Array[String] = []
	for tier in ["I", "II", "III", "IV"]:
		if tier == star_tier:
			parts.append("Tier %s: %s (Stars)" % [tier, unit_type])
			continue
		var names: Array[String] = []
		for card in (regulars.get(tier, []) as Array):
			if card != null:
				names.append(card.player_name)
		parts.append("Tier %s: %s" % [tier, ", ".join(names)])
	return "\n".join(parts)
