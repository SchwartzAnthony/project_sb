class_name AdventureRun
extends RefCounted

# =============================================================
#  ONE RUN — the bounty you took, and everything you have not banked yet
#
#  ============ WHY THIS EXISTS AT ALL ============
#
#  Stamina and loot cannot live on a card, and they cannot live in your save.
#
#  NOT ON THE CARD, because PlayerData is shared. Damage written onto Müller
#  in the Marshlands would still be on Müller in Saturday's league match.
#  Nothing in this project ever writes to a card, and this is the reason.
#
#  NOT IN THE SAVE, because a run's haul is not yours until you carry it
#  home. That is the whole tension of Adventure: everything in here is lost
#  if the party falls, and only banked at the base.
#
#  So it lives here, on the SceneTree, for exactly as long as the run does.
#  Same trick as TeamSelection, GameState and MatchReport.
#
#  ============ WHAT IS FILLED IN WHEN ============
#
#  PHASE 1 (now)   the bounty, the biome, the wave counter, the haul
#  PHASE 4         stamina per card, and knockouts
#  PHASE 5         banking the haul, and the flee penalty
#
#  The stamina and haul parts are already written, because the rules for
#  them are already decided and it is easier to read them all in one place
#  than to find them scattered across three later files.
# =============================================================

const META_KEY := "cw_adventure_run"

## The Bounties.csv row being attempted, and the Biomes.csv row it is in.
var bounty: Dictionary = {}
var biome: Dictionary = {}

## Which wave you are on, 1-based. The last one is the boss.
var wave: int = 1

## Item id -> how many, picked up but NOT yet carried home.
var haul: Dictionary = {}

## Card -> stamina left. A card missing from here has not taken a hit yet.
var stamina: Dictionary = {}

## Cards that have reached 0 and are out for the rest of the run.
var knocked_out: Array[PlayerData] = []

## ============ WHO HAS ALREADY HAD A GO ============
##
## THE SAME RULE AS A LEAGUE MATCH. A player who takes a turn is spent, and
## stays spent until everyone else in their tier has taken one too — then the
## whole tier comes back and the cycle starts again. It is the substitution
## rhythm of the real sport, and it is what stops one 5-power card carrying
## every round of an Adventure.
##
## Kept per tier, cleared per tier, so Tier I refreshing has nothing to do
## with Tier IV.
##
## A KNOCKED-OUT PLAYER COUNTS AS SPENT. They never come back this run, so
## the tier they were in is permanently one short — which is exactly the
## "you start the next fight a tier down" cost you asked for, and it falls
## out of this rule rather than needing one of its own.
var spent: Dictionary = {}

## The squad you set off with, tier key -> Array[PlayerData].
var squad: Dictionary = {}


# =============================================================
#  STARTING AND CARRYING
# =============================================================

static func begin(tree: SceneTree, bounty_row: Dictionary,
		biome_row: Dictionary) -> AdventureRun:
	var run := AdventureRun.new()
	run.bounty = bounty_row
	run.biome = biome_row
	run.wave = 1
	if tree != null:
		tree.set_meta(META_KEY, run)
	return run


static func current(tree: SceneTree) -> AdventureRun:
	if tree == null or not tree.has_meta(META_KEY):
		return null
	return tree.get_meta(META_KEY) as AdventureRun


static func clear(tree: SceneTree) -> void:
	if tree != null and tree.has_meta(META_KEY):
		tree.remove_meta(META_KEY)


## HOW LONG THIS RUN IS. The bounty may set its own Waves; blank falls back
## to the biome's. One place answers it so the HUD, the wave counter and the
## boss check can never disagree.
func waves() -> int:
	var own := int(bounty.get("waves", 0))
	if own > 0:
		return own
	return maxi(1, int(biome.get("waves", 1)))


func is_boss_wave() -> bool:
	return wave >= waves()


## ============ HOW HARD THIS RUN IS ============
##
## Two things multiply together:
##
##   the biome's own Difficulty column   (1 in the marsh, 4 in the Frostreach)
##   how many times you have CLEARED it  (its boss, at least once)
##
## So a biome you have beaten is worth going back into: the enemies come
## back stronger and their drops are worth the same, which is the endless
## half of "endless". The step per clear is `adventure_repeat_step` in
## Tuning.csv — 0.35 means +35% of the base each time round.
##
## The count is a plain counter in your save, so a talent or a building can
## test it: `count:cleared_marshlands>=3`.
func clears_counter() -> String:
	return "cleared_" + CardDatabase._normalise(String(biome.get("id", "biome")))


func difficulty(state: GameState, db: CardDatabase) -> float:
	# A FIRST VISIT IS ALWAYS x1.
	#
	# The biome's Difficulty column does NOT multiply the first run — that
	# would count it twice, because the Hollowdeep's enemies are already
	# written tougher than the marsh's in AdventureEnemies.csv. Multiplying
	# those by 3 as well made the later biomes unplayable rather than hard.
	#
	# Difficulty instead decides HOW FAST a biome ramps when you go back:
	# the marsh (1) climbs gently, the Frostreach (4) climbs steeply.
	var clears := 0
	if state != null:
		clears = maxi(0, state.count(clears_counter()))
	if clears <= 0:
		return 1.0

	var pace := maxf(1.0, float(biome.get("difficulty", 1)))
	var step := db.tune_float("adventure_repeat_step", 0.35) if db != null else 0.35
	return 1.0 + float(clears) * step * pace


## Say this biome has been beaten. Called when a boss goes down.
func record_clear(state: GameState) -> void:
	if state != null:
		state.add_count(clears_counter(), 1)


func biome_name() -> String:
	return String(biome.get("name", "Somewhere"))


func bounty_name() -> String:
	return String(bounty.get("name", "A bounty"))


# =============================================================
#  THE HAUL
# =============================================================

func collect(item_id: String, amount: int) -> void:
	if item_id.strip_edges() == "" or amount <= 0:
		return
	haul[item_id] = int(haul.get(item_id, 0)) + amount


func collect_all(rolled: Dictionary) -> void:
	for key in rolled.keys():
		collect(String(key), int(rolled[key]))


func haul_size() -> int:
	var total := 0
	for key in haul.keys():
		total += int(haul[key])
	return total


## CARRY IT HOME. Everything in the haul becomes a counter in your save,
## which is what makes items work with buildings, talents and conditions
## without a single line of new code.
##
## `keep` is the fraction you actually get: 1.0 walking home, 0.8 fleeing,
## 0.0 if the party fell. Rounded DOWN, so fleeing with 1 reed leaves you
## with nothing rather than rounding up into a free item.
func bank(state: GameState, keep: float = 1.0) -> Dictionary:
	var taken: Dictionary = {}
	if state == null:
		return taken

	for key in haul.keys():
		var amount := int(floor(float(haul[key]) * clampf(keep, 0.0, 1.0)))
		if amount <= 0:
			continue
		state.add_count(String(key), amount)
		taken[key] = amount

	haul.clear()
	return taken


## What fleeing right now would cost, for the warning box. Returns
## item id -> how many you would LOSE.
func flee_loss(keep: float) -> Dictionary:
	var lost: Dictionary = {}
	for key in haul.keys():
		var total := int(haul[key])
		var kept := int(floor(float(total) * clampf(keep, 0.0, 1.0)))
		if total - kept > 0:
			lost[key] = total - kept
	return lost


# =============================================================
#  STAMINA
#
#  ADVENTURE ONLY. In a league match the only thing with stamina is the
#  keeper, and that is unchanged.
#
#  A card's stamina comes from its power, so a Tier I 0-power is fragile and
#  a Tier IV 5-power lasts. That is the trade you wanted: the low tiers are
#  weak in stamina and strong in abilities early on.
#
#      stamina = adventure_stamina_base + power * adventure_stamina_per_power
#
#  Both are rows in Tuning.csv. A unit CSV may also carry its own `Stamina`
#  column, and that wins for that one card — see PlayerData.adventure_stamina.
# =============================================================

static func stamina_for(card: PlayerData, db: CardDatabase) -> int:
	if card == null:
		return 0
	if card.adventure_stamina > 0:
		return card.adventure_stamina        # the card's own column wins
	var base := db.tune_int("adventure_stamina_base", 6)
	var per := db.tune_int("adventure_stamina_per_power", 3)
	return maxi(1, base + card.get_attack_power() * per)


func stamina_of(card: PlayerData, db: CardDatabase) -> int:
	if card == null:
		return 0
	if not stamina.has(card):
		stamina[card] = stamina_for(card, db)
	return int(stamina[card])


func is_out(card: PlayerData) -> bool:
	return card != null and knocked_out.has(card)


## Take a hit. Returns true if this knocked the card out.
func hurt(card: PlayerData, amount: int, db: CardDatabase) -> bool:
	if card == null or amount <= 0 or is_out(card):
		return false
	var left := stamina_of(card, db) - amount
	stamina[card] = maxi(0, left)
	if left <= 0 and not knocked_out.has(card):
		knocked_out.append(card)
		# OUT OF THE ROTATION TOO, permanently. See `spent` at the top: this
		# is what makes losing somebody cost you a tier slot next fight
		# rather than only costing you this round.
		retire(card)
		return true
	return false


# =============================================================
#  THE ROTATION
# =============================================================

## Has this player already had their turn this cycle?
func is_spent(card: PlayerData) -> bool:
	if card == null:
		return false
	var tier := card.get_tier_clean()
	return (spent.get(tier, []) as Array).has(card)


## Mark a player as having taken their turn, and refresh the tier if that was
## the last of them.
##
## Returns true when the tier came back round, so the fight can say so.
func use_up(card: PlayerData, db: CardDatabase) -> bool:
	if card == null:
		return false
	var tier := card.get_tier_clean()
	var used: Array = spent.get(tier, [])
	if not used.has(card):
		used.append(card)
	spent[tier] = used

	# EVERYONE WHO COULD GO HAS GONE. Wipe the tier and they are all
	# available again — which is the cycle closing.
	if available_in(tier, db).is_empty():
		spent[tier] = [] as Array
		return true
	return false


## A knocked-out player is spent for good. Called the moment they go down so
## the rotation never waits for somebody who is not getting up.
func retire(card: PlayerData) -> void:
	if card == null:
		return
	var tier := card.get_tier_clean()
	var used: Array = spent.get(tier, [])
	if not used.has(card):
		used.append(card)
	spent[tier] = used


## Who a tier can actually field RIGHT NOW: standing, and not yet used this
## cycle. This is what the draft offers you.
func available_in(tier: String, db: CardDatabase) -> Array[PlayerData]:
	var out: Array[PlayerData] = []
	for card in standing_in(tier, db):
		if not is_spent(card):
			out.append(card)
	return out


## Everyone in a tier who is spent but still on their feet — for the card
## window, which shows them greyed out with "next cycle" on them rather than
## hiding them. Seeing who is resting is half of knowing what you have.
func resting_in(tier: String, db: CardDatabase) -> Array[PlayerData]:
	var out: Array[PlayerData] = []
	for card in standing_in(tier, db):
		if is_spent(card):
			out.append(card)
	return out


## Who is still standing in a tier, weakest first — the order enemies pick
## their target in, and the order the draft offers them.
func standing_in(tier: String, db: CardDatabase) -> Array[PlayerData]:
	var out: Array[PlayerData] = []
	for entry in (squad.get(tier, []) as Array):
		var card := entry as PlayerData
		if card != null and not is_out(card):
			out.append(card)

	# Insertion sort by power: the lists are three long and this keeps two
	# equal powers in the order they were chosen.
	var sorted: Array[PlayerData] = []
	for card in out:
		var at := sorted.size()
		for i in sorted.size():
			if sorted[i].get_attack_power() > card.get_attack_power():
				at = i
				break
		sorted.insert(at, card)
	return sorted


## True when nobody is left anywhere. The run is over and the haul is gone.
func party_is_down() -> bool:
	for tier in squad.keys():
		for entry in (squad[tier] as Array):
			var card := entry as PlayerData
			if card != null and not is_out(card):
				return false
	return true
