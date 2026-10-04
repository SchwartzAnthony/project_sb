#!/usr/bin/env python3
# =============================================================
#  THE ABILITY AUDIT  (round Y)
#
#      python3 tools/ability_audit.py
#
#  Reads EVERY ability text in the game - the four Unit_Set files (Attack and
#  Defend), Star Players.csv (Front Side and Ultimate Side) and the four
#  Emblem files (Basic Side, Condition, Ultimate Side) - and writes
#  data/AbilityAudit.csv: one row per text, broken into the same five
#  answers an Abilities.csv row gives, plus what the engine still needs.
#
#      When     the moment it can fire           on_attack, while_in_exhaust...
#      If       what must be true                defending, has_counter:burn...
#      Cost     what it spends                   ore:3
#      Do       the effect                       add_power, drain_stamina...
#      Target   who it lands on                  self, opponent, next_ally...
#      Value    how much
#      Scope    how long                         duel, round, cycle, match
#      Max      the "(Max 3)" / once per cycle
#
#  and then:
#
#      Words Needed   every word above that the engine does NOT know yet
#      Phase          which build phase brings those words (guides/COMBAT_PHASES.md)
#      Status         works today / Cn / needs your ruling
#      Question       what I could not decide from the text
#      Your Ruling    YOURS. Write the answer here. Re-running this script
#                     KEEPS what you wrote - it is matched on Card + Side.
#
#  IT IS A READING, NOT A VERDICT. The proposed words are my best reading of
#  your sentence. Where the sentence could mean two things, the row says so
#  in Question and the Status is `needs your ruling`.
# =============================================================

import csv
import glob
import io
import os
import re
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(HERE, "data")
OUT = os.path.join(DATA, "AbilityAudit.csv")

COLUMNS = ["Class", "Set", "Card", "Tier", "Power", "Side", "Text",
           "When", "If", "Cost", "Do", "Target", "Value", "Scope", "Max",
           "Words Needed", "Phase", "Status", "Question", "Your Ruling"]

# -------------------------------------------------------------
#  THE WORDS THE ENGINE ALREADY KNOWS (live today)
# -------------------------------------------------------------
LIVE = {
    # triggers
    "on_attack", "on_defend", "on_duel_start", "on_win_duel", "on_lose_duel",
    "passive", "flip", "reveal",
    # effects
    "add_power", "add_attack", "add_defense", "add_shot_power",
    "drain_stamina", "restore_stamina", "add_card_chance",
    # targets
    "self", "opponent", "all_allies", "all_enemies", "enemy_goalie", "own_goalie", "enemytier",
    # scopes
    "duel", "round", "cycle", "match",
}

# Which phase brings each word. guides/COMBAT_PHASES.md explains the phases.
PHASE = {
    # C1 - the foundation: moments, conditions, "next", zones
    "end_of_cycle": "C1", "after_tier": "C1", "contemplation": "C1", "rejuvenation": "C1", "next_self": "C1",
    "while_in_exhaust": "C1", "on_goal": "C1", "on_shot": "C1", "goalie_save": "C1",
    "defending": "C1", "attacking": "C1", "won": "C1", "lost": "C1",
    "last_ally_won": "C1", "last_ally_lost": "C1", "enemy_not_element": "C1",
    "own_goalie_lower": "C1", "enemy_below_base": "C1",
    "next_ally": "C1", "next_enemy": "C1", "next_ally_tier": "C1", "tier": "C1", "next_ally*2": "C1",
    "ally_tier": "C1", "enemy_tier": "C1", "once_per_cycle": "C1", "once_per_game": "C1",
    # round Z: "the next unit played" (ruling R03) - strict, the very next one
    "next_tier_ally": "C2", "after_combat": "C2",
    # C2 - counters, tokens, creature types
    "has_counter": "C2", "enemy_has_counter": "C2", "add_counter": "C2",
    "remove_counter": "C2", "power_counter": "C2", "has_token": "C2",
    "tokens_at_least": "C2", "is_swan": "C2", "make_swan": "C2", "swan": "C2",
    "create_token": "C2", "token": "C2",
    # C3 - the goal, the keeper and the referee
    "goalie_chance": "C3", "goalie_shield": "C3", "remove_shields": "C3",
    "foul_heat": "C3", "foul_chance": "C3", "foul_coin_flip": "C3",
    # C4 - duel-bending
    "switch_to_defender": "C4", "always_defending": "C4", "swap_power": "C4",
    "use_enemy_power": "C4", "force_ability": "C4", "negate_ability": "C4",
    "negate_buff": "C4", "change_priority": "C4", "give_priority": "C4",
    "uncounterable": "C4", "double_attack": "C5", "power_from_count": "C4", "set_power_from_token": "C4",
    "reveal_another": "C5", "remove_condition": "C4",
    # C5 - zones in action
    "send_to_exhaust": "C5", "swap_from_exhaust": "C5", "swapped_was": "C5", "revealed_was": "C5",
    "swap_from_void": "C5", "swap_in_tier": "C5", "exhaust_other_return": "C5",
    "reveal_from_exhaust": "C5", "copy_from_exhaust": "C5", "exhaust_swap": "C5",
    # C6 - the class engines
    "ore": "C2", "gain_ore": "C2", "mining": "C6", "ore_this_round": "C2",
    "mine": "C6", "fuse": "C6", "fused": "C6", "gravestone": "C6",
    "touched_ball": "C6", "touched_before_playmaker": "C6", "cold_touch": "C6",
    "weapon": "C6", "song": "C6", "victory_counter": "C6", "teufel_mask": "C6",
    # C7 / C8 - emblems and stars
    "emblem_basic": "C7", "emblem_condition": "C7", "star_ultimate": "C8",
}
PHASE_ORDER = ["C1", "C2", "C3", "C4", "C5", "C6", "C7", "C8"]


def row(**kw):
    out = {c: "" for c in COLUMNS}
    out.update({k: v for k, v in kw.items() if k in out})
    return out


# -------------------------------------------------------------
#  READING A SENTENCE
#
#  Each rule is (pattern, what it fills in). Applied to the lower-case text.
#  The first matching WHEN / IF / COST rule wins; every matching DO rule adds.
# -------------------------------------------------------------

WHEN_RULES = [
    (r"^reveal\b", {"When": "reveal"}),
    # RULING R14: "Exile" was the old name of the exhaust zone. Both read the same.
    # "While in exhaust: ... at the end of a cycle" is ONCE, at the end of the
    # cycle, if it is in the exhaust - not at every duel (round Z).
    (r"while in (exile|exhaust).*at the end of (the|a) cycle", {"When": "end_of_cycle", "If": "in_exhaust"}),
    (r"while in (exile|exhaust).*after tier (i|ii|iii|iv) combat", {"When": "after_combat", "If": "in_exhaust"}),
    # ROUND AC (C5, ruling R17): "While in Exhaust: Swap this Unit with another
    # Tier I during combat and ..." - the exhaust lights up before the duel,
    # you may swap it in, and the rest happens once it has.
    (r"while in (exile|exhaust):? ?swap this unit with another tier", {"When": "exhaust_swap"}),
    (r"while in (exile|exhaust)", {"When": "while_in_exhaust"}),
    (r"if sent to exhaust", {"When": "contemplation"}),
    (r"in exhaust & goaly successfully defends", {"When": "goalie_save", "If": "in_exhaust"}),
    (r"^if this wins", {"When": "on_win_duel"}),
    (r"^if this loses", {"When": "on_lose_duel"}),
    (r"shooting at goal", {"When": "on_shot"}),
    (r"at the end of (the|a) cycle", {"When": "end_of_cycle"}),
    (r"after tier (iv|iii|ii|i) combat", {"When": "after_tier"}),
]

IF_RULES = [
    (r"if you control 4 tokens", "tokens_at_least:4"),
    (r"if you control a token", "has_token"),
    (r"if this unit is a swan", "is_swan"),
    (r"if defending", "defending"),
    (r"if this has a burn counter", "has_counter:burn"),
    (r"if this has a counter on it", "has_counter"),
    (r"if the enemy unit has a counter on it", "enemy_has_counter"),
    (r"if another unit is mining", "mining"),
    (r"if collected ore this round", "ore_this_round"),
    (r"if this touched the ball before \"?play maker", "touched_before_playmaker"),
    (r"if this touched the ball", "touched_ball"),
    (r"if your last unit won combat", "last_ally_won"),
    (r"if your last unit lost combat", "last_ally_lost"),
    (r"if the enemy isn'?t air", "enemy_not_element:air"),
    (r"if your goalie has less stamina", "own_goalie_lower"),
    (r"if the enemy deals less damage than their base power", "enemy_below_base"),
    (r"if fused with another", "fused"),
    (r"if the revealed card was fire", "revealed_was:fire"),
    (r"if it was an air unit", "swapped_was:air"),
]

COST_RULES = [
    (r"consume (\d) ore", lambda m: "ore:%s" % m.group(1)),
]

# (pattern, Do, Target, Value, Scope, needs-word(s))
DO_RULES = [
    # ---- power in this duel ----
    (r"give this unit \+(\d) power during combat", "add_power", "self", r"\1", "duel"),
    (r"gain \+(\d) power during combat", "add_power", "self", r"\1", "duel"),
    # RULING R18 (my reading, round Z): "attack" during combat is the power the
    # card fights with in that combat, whichever side it is on.
    (r"give this unit \+(\d) attack during combat", "add_power", "self", r"\1", "duel"),
    (r"give this unit \+(\d) during combat", "add_power", "self", r"\1", "duel"),
    (r"give this \+(\d) power during combat", "add_power", "self", r"\1", "duel"),
    (r"deal \+(\d) damage during combat", "add_power", "self", r"\1", "duel"),
    # Q001 (round AB): "attack power" is now written "base power" - the power
    # the card fights with in combat.
    (r"give the enemy -(\d) (attack|base) power during combat", "add_power", "opponent", r"-\1", "duel"),
    (r"give (the )?enemy (unit )?-(\d) power during combat", "add_power", "opponent", r"-\3", "duel"),
    (r"give -(\d) to enemy during combat", "add_power", "opponent", r"-\1", "duel"),
    (r"give the enemy -(\d) during combat", "add_power", "opponent", r"-\1", "duel"),
    (r"enemy deals -(\d) power during combat", "add_power", "opponent", r"-\1", "duel"),
    (r"give enemy of same tier -(\d) power", "add_power", "next_enemy:SAMETIER", r"-\1", "duel"),
    (r"during combat remove (\d) power from a tier (i|ii|iii|iv) unit", "add_power", r"enemytier:TIER\2", r"-\1", "duel"),
    # ---- the next one ----
    # RULING R03: "the next Tier ... ally" is the VERY NEXT card played.
    (r"give (the )?next tier fire ally a burn counter", "add_counter:burn", "next_tier_ally:fire", "1", "match"),
    (r"give (the )?next fire ally a burn counter", "add_counter:burn", "next_ally:fire", "1", "match"),
    (r"give the next fire ally \+(\d) (damage )?during combat", "add_power", "next_ally:fire", r"\1", "duel"),
    (r"give the next enemy -(\d) during combat", "add_power", "next_enemy", r"-\1", "duel"),
    (r"give the next ally unit \+(\d) power during combat", "add_power", "next_ally", r"\1", "duel"),
    (r"give (your )?the next water unit \+(\d) power", "add_power", "next_ally:water", r"\2", "duel"),
    (r"next tier (i|ii|iii|iv) water unit \+(\d) power", "add_power", r"next_ally:water+TIER\1", r"\2", "duel"),
    (r"give a tier (i|ii|iii|iv) water unit \+(\d) power", "add_power", r"ally:water+TIER\1", r"\2", "duel"),
    (r"your tier iv gets \+ ?(\d) attack", "add_power", "tier:IV", r"\1", "duel"),
    (r"next (\d) swans?( units?)? deals? (\d) damage to the enemy goalie", "drain_stamina", r"next_ally*\1:swan", r"\3", "cycle"),
    (r"next swans?( units?)? deals? (\d) damage to the enemy goalie", "drain_stamina", "next_ally:swan", r"\2", "cycle"),
    (r"next swan has \+(\d) power", "add_power", "next_ally:swan", r"\1", "duel"),
    (r"next two unkengeister units get \+(\d) power", "add_power", "next_ally*2:unkengeister", r"\1", "duel"),
    (r"give a token this sequence \+(\d) attack", "add_power", "ally:token", r"\1", "duel"),
    (r"give another unit a temporary weapon", "weapon", "ally", "1", "duel"),
    # ---- the keepers ----
    (r"deal (\d) damage to (the )?enemy goalie", "drain_stamina", "enemy_goalie", r"\1", "now"),
    (r"enemy goalie takes (\d) damage", "drain_stamina", "enemy_goalie", r"\1", "now"),
    (r"give your goalie \+?(\d) stamina", "restore_stamina", "own_goalie", r"\1", "now"),
    (r"give \+(\d) stamina to goalie", "restore_stamina", "own_goalie", r"\1", "now"),
    (r"give -(\d) stamina to goalie", "drain_stamina", "enemy_goalie", r"\1", "now"),
    (r"add \+(\d) to goalie shield", "goalie_shield", "own_goalie", r"\1", "match"),
    (r"remove any shields on the enemy goalie", "remove_shields", "enemy_goalie", "1", "now"),
    (r"increase enemy goalie % (chance )?by (\d)%", "goalie_chance", "enemy_goalie", r"\2", "round"),
    # RULING R02: "enemy chance" = how likely THEIR keeper is to be beaten.
    (r"increase (\d)% on enemy chance", "goalie_chance", "enemy_goalie", r"\1", "round"),
    (r"incease the enemy goalie miss by (\d)%", "goalie_chance", "enemy_goalie", r"\1", "round"),
    (r"increase enemy goalie % of missing by (\d)%", "goalie_chance", "enemy_goalie", r"\1", "round"),
    (r"decrease goalie % of missing by -?(\d)%", "goalie_chance", "own_goalie", r"-\1", "round"),
    (r"reduce the ally goalie % chance to 0%", "goalie_chance", "own_goalie", "-100", "round"),
    (r"reduce the ally goalie % chance by (\d+)%", "goalie_chance", "own_goalie", r"-\1", "round"),
    (r"add \+(\d) power to the damage collection", "add_shot_power", "self", r"\1", "round"),
    (r"deal \+(\d) damage to goalie", "add_shot_power", "self", r"\1", "round"),
    # ---- the referee ----
    (r"add \+(\d)% to enemy yellow card chance", "add_card_chance", "all_enemies", r"\1", "match"),
    (r"\+(\d) to the enemy yellow card bar", "foul_heat", "all_enemies", r"\1", "match"),
    (r"\+(\d) yellow card progression", "foul_heat", "opponent", r"\1", "match"),
    (r"increase enemy % of committing a foul by (\d)%", "foul_chance", "all_enemies", r"\1", "round"),
    (r"give the enemy \+(\d)% foul chance for the match", "foul_chance", "all_enemies", r"\1", "match"),
    (r"if you cause a foul, instead flip a coin", "foul_coin_flip", "self", "1", "match"),
    # ---- bending the duel ----
    (r"switch to being the defender", "switch_to_defender", "self", "1", "duel"),
    (r"always counts as defending", "always_defending", "self", "1", "match"),
    (r"swap the next enemy unit power with this one", "swap_power", "next_enemy", "1", "duel"),
    (r"swap the enemy unit power with this one", "swap_power", "opponent", "1", "duel"),
    (r"swap the attack of the token with this unit power", "swap_power", "token", "1", "duel"),
    (r"use (the (attack|base) power of an enemy unit|its (attack|base) power)", "use_enemy_power", "opponent", "1", "duel"),
    # Sven (Q002, round AB): the enemy fights with the power of a token YOU own.
    (r"change the enemy'?s base power to the power of a token you own", "set_power_from_token", "opponent", "1", "duel"),
    (r"enemy (has to )?uses? (their )?attack ability", "force_ability:attack", "opponent", "1", "duel"),
    (r"(player using|enemy uses their) defen[cds]e? ability", "force_ability:defend", "opponent", "1", "duel"),
    (r"force (the|then) enemy tier (i|ii|iii|iv) to use their other ability", "force_ability:other", r"enemytier:TIER\2", "1", "duel"),
    (r"this units uses its attack ability", "force_ability:attack", "self", "1", "duel"),
    (r"negate (the )?enemy ability|negat the enemy ability", "negate_ability", "opponent", "1", "duel"),
    (r"negate power buff", "negate_buff", "opponent", "1", "duel"),
    (r"(increase|ncrease) enemy priority by \+(\d)", "change_priority", "opponent", r"\2", "duel"),
    (r"change (the )?enemy priority by -(\d)", "change_priority", "opponent", r"-\2", "duel"),
    (r"give the next ally unit -(\d) priority", "change_priority", "next_tier_ally", r"-\1", "duel"),
    (r"give a tier (i|ii|iii|iv) water unit ability priority", "give_priority", r"ally:water+TIER\1", "1", "duel"),
    (r"cannot be countered", "uncounterable", "self", "1", "duel"),
    # Lothar (C5): the token you control, in ITS next duel.
    (r"doulbe its attack|double its attack", "double_attack", "next_ally:token", "1", "duel"),
    (r"reveal another unit card", "reveal_another", "self", "1", "duel"),
    (r"remove next ally condition", "remove_condition", "next_ally", "1", "duel"),
    (r"attack equal to the victory counters", "power_from_count:victory", "self", "1", "duel"),
    (r"power is equal to each tier ii enemy in the exhaust", "power_from_count:enemy_exhaust_II", "self", "1", "duel"),
    (r"power is equal to each unique structure", "power_from_count:field_objects", "self", "3", "duel"),
    # ---- counters, tokens ----
    (r"give this unit -(\d) power counter", "add_counter:power", "self", r"-\1", "match"),
    (r"remove a counter", "remove_counter", "self", "1", "match"),
    (r"remove 1 victory counter", "remove_counter:victory", "side", "1", "match"),
    (r"send this unit to the exhaust and replace it with a rose unit token", "create_token:rose", "self", "1", "match"),
    (r"create a swan unit token", "create_token:swan", "self", "1", "match"),
    (r"send it to the exhaust", "send_to_exhaust", "self", "1", "cycle"),
    # ---- zones ----
    (r"swap this card with one of same power and tier from the exhaust", "swap_from_exhaust", "self", "1", "duel"),
    (r"swap this unit with another of same tier from the void", "swap_from_void", "self", "1", "duel"),
    (r"swap this unit with another tier i during combat", "swap_in_tier", "self", "1", "duel"),
    (r"swap a card from the exhaust of the same tier", "swap_from_exhaust", "next_ally:token", "1", "duel"),
    # Franz (C5): the second half of his sentence.
    (r"give the next air unit \+(\d) power", "add_power", "next_ally:air", r"\1", "duel"),
    # Flauros (C5): "Give this unit +1 damage during combat if ...".
    (r"give this unit \+(\d) damage during combat", "add_power", "self", r"\1", "duel"),
    (r"send a different tier iv to the exhaust zone and return this to the stack", "exhaust_other_return", "self", "1", "duel"),
    (r"reveal a unit from your exhaust zone", "reveal_from_exhaust", "self", "1", "duel"),
    # ---- the class engines ----
    (r"gain (\d) ore counters", "gain_ore", "side", r"\1", "match"),
    (r"choose 1 mine", "mine", "ally", "1", "round"),
    (r"fuses itself with a tier (i|ii|iii|iv) fire unit", "fuse", "self", "1", "match"),
    (r"can be fused", "fused", "self", "1", "match"),
    (r"summon a gravest\w+ ?on the field", "gravestone", "field", "1", "match"),
    (r"apply \"?cold touch\"? on the ball", "cold_touch", "ball", "1", "round"),
]

QUESTIONS = [
    (r"give -1 stamina to goalie", "WHICH goalie loses the stamina - the enemy's? (Read as the enemy's.)"),
    (r"on enemy chance", "\"enemy chance\": the enemy KEEPER's chance to save (so better for you), or the enemy's chance to SCORE? (Read as their keeper's.)"),
    (r"next (tier )?fire ally|next ally|next water unit|next swan|next air unit|next enemy|next tier", "\"Next\": the next card of that kind to DUEL - later this round, and into the next round if this was Tier IV? (Read that way.)"),
    (r"damage during combat", "\"+1 damage during combat\": the same as +1 power for this duel? (Read that way.)"),
    (r"\(max \d\)", "(Max N): N times per MATCH for this card? (Read that way.)"),
    (r"once per cycle", "Once per cycle per card, or once per cycle per side? (Read as per card.)"),
    (r"from the void", "\"The void\": the 18 cards NOT in the match (your bench), or the Exile zone? (Read as the bench.)"),
    (r"from outside of the game", "\"Outside of the game\": the bench (the 18 not fielded)? And does the fused card keep its own name? (Read as the bench; the fused card keeps this card's name.)"),
    (r"yellow card bar|yellow card progression", "+1 to the yellow card bar: one whole SEGMENT of the referee's bar, or one Fill Per Trigger? (Read as one segment.)"),
    (r"committing a foul$", "By how much? No number is written. (Read as +10% for the round.)"),
    (r"goalie shield", "A shield: blocks the next N stamina lost? the next goal? (Proposed: absorbs one point of stamina damage per shield.)"),
    (r"mining|mine\b|ore counters", "Ore lives where - on the CARD, or in one pool for the side? (Proposed: one pool per side, shown on the emblem bar.)"),
    (r"touched the ball", "\"Touched the ball\": held it at any point in open play since the last PLAY MAKER? (Read that way.)"),
    (r"exile|from the exhaust|to the exhaust", "Exile vs Exhaust: exhausted cards come back at the end of the cycle; exiled ones only when a rule says so. Is that right? (Read that way.)"),
    (r"switch to being the defender", "Switch to defender: the duel flips (you defend, they attack) - and does the BALL then stay with whoever wins as normal? (Read: yes, the ball follows the winner as always.)"),
    (r"intoxication|foul chance for the match", "\"Intoxication to foul\": this card's own foul chance, or a mark that raises that enemy's foul chance? (Read as a mark: that enemy is +5% to foul for the match.)"),
    (r"swap this unit with another tier i\b", "Swap with ANOTHER Tier I: one of yours from the field, from the exhaust zone, or the enemy's? (Read as one of YOUR Tier I cards still on the field.)"),
    (r"attack power during combat|\+\d attack during combat|gets \+ ?\d attack|this sequence \+\d attack", "\"Attack power during combat\": the power the card FIGHTS with in that combat, whichever side it is on - so a -1 to a DEFENDING enemy still bites? (Read that way.)"),
]

ELEMENT_OF = {"lorelei": "water", "rauhnacht-feuergeister": "fire",
              "bergmännlein": "earth", "unkengeister": "air"}


def read_text(text):
    """Text -> the proposed fields, the words needed, the questions."""
    low = " ".join(text.lower().split())
    out = {"When": "", "If": "", "Cost": "", "Do": [], "Target": [], "Value": [],
           "Scope": [], "Max": "", "Q": []}
    for pat, fill in WHEN_RULES:
        if re.search(pat, low):
            for k, v in fill.items():
                out[k] = v
            break
    ifs = []
    for pat, word in IF_RULES:
        if re.search(pat, low) and word not in ifs:
            ifs.append(word)
    if out["If"]:
        ifs.insert(0, out["If"])
    out["If"] = ";".join(ifs)
    for pat, fn in COST_RULES:
        m = re.search(pat, low)
        if m:
            out["Cost"] = fn(m)
    seen = set()
    for rule in DO_RULES:
        pat, do, target, value, scope = rule
        m = re.search(pat, low)
        if not m:
            continue
        val = m.expand(value) if "\\" in value else value
        target = re.sub(r"TIER(i+v?|iv|v)", lambda t: t.group(1).upper(), m.expand(target) if "\\" in target else target)
        key = (do, target, val)
        # ONE SENTENCE, ONE EFFECT OF EACH KIND. "Your next swan deals 1
        # damage to the enemy goalie" also matches the plain goalie rule
        # further down; the more specific reading (the swan) came first and
        # wins.
        if key in seen or do in out["Do"]:
            continue
        seen.add(key)
        out["Do"].append(do)
        out["Target"].append(target)
        out["Value"].append(val)
        out["Scope"].append(scope)
    m = re.search(r"\(max (\d)\)", low)
    if m:
        out["Max"] = m.group(1)
    elif "once per cycle" in low:
        out["Max"] = "1/cycle"
    elif "once per round" in low:
        out["Max"] = "1/round"
    elif "once per game" in low:
        out["Max"] = "1/game"
    elif "only two per cycle" in low:
        out["Max"] = "2/cycle"
    for pat, q in QUESTIONS:
        if re.search(pat, low):
            out["Q"].append(q)
    return out


FILTER_OK = {"water", "fire", "earth", "air", "lorelei", "unkengeister", "bergmännlein",
             "rauhnacht-feuergeister", "i", "ii", "iii", "iv", ""}


def words_of(r):
    """Every engine word this row uses, flattened to its first part."""
    words = []
    for t in str(r["Target"]).split("|"):
        t = t.strip().rstrip("?")
        if ":" in t:
            for f in t.split(":", 1)[1].split("+"):
                if f.lower() not in FILTER_OK and f.lower() not in words:
                    words.append(f.lower())
    for field in ("When", "If", "Cost", "Do", "Target", "Scope"):
        for piece in str(r[field]).replace("|", ";").split(";"):
            w = piece.strip().split(":")[0].rstrip("?")
            w = re.sub(r"\*\d+$", "*2", w)      # next_ally*3 is the same word as *2
            if w and w not in words:
                words.append(w)
    if r["Max"]:
        words.append("once_per_cycle" if "cycle" in r["Max"] else ("once_per_game" if "game" in r["Max"] else "max"))
    return words


RULED = {}   # question text -> your ruling, filled by main() before anything is read


def ruled(question_text):
    """True when every question in this row has a ruling from you."""
    asked = [q for _p, q in QUESTIONS if q in question_text]
    return bool(asked) and all(RULED.get(q, "").strip() for q in asked)


def finish(r, side_kind):
    """Fill Words Needed, Phase and Status from the proposed words."""
    needed = []
    for w in words_of(r):
        if w in LIVE or w in ("now", "max", "ally", "field", "ball", "in_exhaust", "side"):
            if w == "in_exhaust":
                needed.append("while_in_exhaust")
            continue
        needed.append(w)
    if side_kind == "Ultimate Side":
        needed.append("star_ultimate")
    if side_kind in ("Basic Side", "Condition"):
        needed.append("emblem_basic" if side_kind == "Basic Side" else "emblem_condition")
    needed = list(dict.fromkeys(needed))
    r["Words Needed"] = "; ".join(needed)
    phases = sorted({PHASE.get(w, "C?") for w in needed},
                    key=lambda p: PHASE_ORDER.index(p) if p in PHASE_ORDER else 99)
    r["Phase"] = phases[-1] if phases else ""
    if not r["Do"] and side_kind in ("Ultimate Side", "Basic Side"):
        # A WHOLE SYSTEM, NOT A ONE-LINE ABILITY. An Emblem's Basic Side and a
        # Star's Ultimate are small rule-sets of their own (a mine in each
        # zone, Rose tokens replacing units...). They are built as a piece in
        # their phase, from your text, and are not squeezed into one row.
        r["Do"] = "(system)"
        r["Phase"] = "C8" if side_kind == "Ultimate Side" else "C7"
        r["Words Needed"] = "star_ultimate" if side_kind == "Ultimate Side" else "emblem_basic"
        r["Status"] = r["Phase"] + " system"
        return r
    if not r["Do"]:
        r["Status"] = "needs your ruling"
        r["Question"] = ("I could not turn this into engine words - what should it DO? " + r["Question"]).strip()
    elif not needed and (not r["Question"] or ruled(r["Question"])):
        r["Status"] = "works today"
    elif r["Question"] and not ruled(r["Question"]):
        r["Status"] = "%s - needs your ruling" % r["Phase"]
    else:
        r["Status"] = r["Phase"]
    return r


def _part_rows(text, side_kind, base):
    """One sentence-part -> (when, if, cost, [do], [target], [value], [scope], max, questions)."""
    parsed = read_text(text)
    when = parsed["When"] or ("" if side_kind in ("Ultimate Side", "Basic Side", "Condition") else
                              ("on_attack" if side_kind == "Attack" else "on_defend"))
    targets = []
    for t in parsed["Target"]:
        # "enemy of same Tier" - the card's own tier, filled in here.
        targets.append(t.replace("SAMETIER", (base.get("Tier") or "").strip().upper()))
    # OUTSIDE A DUEL, "DURING COMBAT" MEANS THE NEXT ONE. A card in the
    # exhaust zone gaining "+1 power during combat" when its keeper saves has
    # no combat to be in - so it is its NEXT duel, and "the enemy" is the
    # next enemy it meets.
    if when in NOT_A_DUEL:
        targets = [{"self": "next_self", "opponent": "next_enemy"}.get(t, t)
                   if sc == "duel" else t for t, sc in zip(targets, parsed["Scope"])]
    # WHILE IN EXHAUST, "A TIER IV WATER UNIT" IS THE NEXT ONE OF THOSE TO
    # DUEL (round AB). It goes off at the start of a duel - usually the Tier I
    # duel - and a buff aimed at this round's Tier IV ran out before Tier IV
    # played. It now waits for that card.
    if when == "while_in_exhaust":
        targets = [("next_ally:" + t[5:]) if t.startswith("ally:") else
                   (("next_enemy:" + t[10:]) if t.startswith("enemytier:") else t) for t in targets]
    return when, parsed, targets


# A SENTENCE WITH TWO HALVES. "Give this unit +1 power during combat. If this
# wins: Give this unit -1 power counter." is two abilities with two different
# moments - the first when it duels, the second when it wins. Split there.
TWO_PARTS = re.compile(r"(?<=\.)\s+(?=if this (?:wins|loses))", re.IGNORECASE)


def from_text(base, text, side_kind):
    r = row(**base)
    r["Text"] = text
    whens, ifs, costs, dos, targets, values, scopes, qs = [], [], [], [], [], [], [], []
    maxes = []
    for part in TWO_PARTS.split(text):
        when, parsed, part_targets = _part_rows(part, side_kind, base)
        for i, do in enumerate(parsed["Do"]):
            whens.append(when)
            # ROUND AC (C5): the swap itself, and the reveal itself, are not
            # held back by the If that asks what they swapped / revealed -
            # "if it was an air unit" is about what comes AFTER the swap.
            if do in ("swap_in_tier", "reveal_from_exhaust") and \
                    any(w in parsed["If"] for w in ("swapped_was", "revealed_was")):
                ifs.append(";".join(t for t in parsed["If"].split(";")
                                    if not t.startswith(("swapped_was", "revealed_was"))))
            else:
                ifs.append(parsed["If"])
            costs.append(parsed["Cost"])
            dos.append(do)
            targets.append(part_targets[i])
            values.append(parsed["Value"][i])
            scopes.append(parsed["Scope"][i])
        if not parsed["Do"]:
            whens.append(when)
            ifs.append(parsed["If"])
            costs.append(parsed["Cost"])
        if parsed["Max"]:
            maxes.append(parsed["Max"])
        for q in parsed["Q"]:
            if q not in qs:
                qs.append(q)

    # ROUND AC (C5): the swap / the reveal happen FIRST, so an If that asks
    # what was swapped or revealed has an answer when its half is read.
    first = ("swap_in_tier", "reveal_from_exhaust")
    if any(d in first for d in dos) and len(dos) > 1:
        order = sorted(range(len(dos)), key=lambda i: 0 if dos[i] in first else 1)
        def re(items):
            return [items[i] for i in order] if len(items) == len(dos) else items
        whens, ifs, costs, dos, targets, values, scopes = (re(whens), re(ifs), re(costs), re(dos),
                                                           re(targets), re(values), re(scopes))

    def one_or_many(items):
        """All the same -> one value; different -> one per effect, '|' between."""
        if not items:
            return ""
        return items[0] if len(set(items)) == 1 else " | ".join(items)

    r["When"] = one_or_many(whens[:max(1, len(dos))])
    r["If"] = one_or_many(ifs[:max(1, len(dos))])
    r["Cost"] = one_or_many(costs[:max(1, len(dos))])
    r["Do"] = " | ".join(dos)
    r["Target"] = " | ".join(targets)
    r["Value"] = " | ".join(values)
    r["Scope"] = " | ".join(scopes)
    r["Max"] = maxes[0] if maxes else ""
    # "(max 3)" after "power is equal to ..." is a CAP on the number, not a
    # use limit (Glasya-Labolas) - round AB.
    if "power_from_count" in r["Do"]:
        r["Max"] = ""
    r["Question"] = " ".join(qs)
    return finish(r, side_kind)


NOT_A_DUEL = {"goalie_save", "on_goal", "on_concede", "end_of_cycle", "round_end",
              "contemplation", "rejuvenation", "while_in_exile", "on_shot", "reveal"}


def main():
    # YOUR RULINGS FIRST, so a question you have answered stops holding its
    # card back ("C2 - needs your ruling" becomes plain "C2").
    rp = os.path.join(DATA, "AbilityRulings.csv")
    if os.path.exists(rp):
        with open(rp, encoding="utf-8") as f:
            for old in csv.DictReader(f):
                if (old.get("Your Ruling") or "").strip():
                    RULED[old["Question"]] = old["Your Ruling"]
    kept = {}
    if os.path.exists(OUT):
        with open(OUT, encoding="utf-8") as f:
            for old in csv.DictReader(f):
                if (old.get("Your Ruling") or "").strip():
                    kept[(old["Card"], old["Side"])] = old["Your Ruling"]

    rows = []
    for path in sorted(glob.glob(os.path.join(DATA, "Unit_Set_*.csv"))):
        with open(path, encoding="utf-8") as f:
            for c in csv.DictReader(f):
                for side in ("Attack", "Defend"):
                    base = {"Class": c["Unit Type"], "Set": c.get("Set Name", ""), "Card": c["Name"],
                            "Tier": c["Tier"], "Power": c.get("Base Power ", c.get("Base Power", "")),
                            "Side": side}
                    rows.append(from_text(base, c[side].strip(), side))
    with open(os.path.join(DATA, "Star Players.csv"), encoding="utf-8") as f:
        for c in csv.DictReader(f):
            for side, kind in (("Front Side", "Attack"), ("Ultimate Side", "Ultimate Side")):
                base = {"Class": c["Unit Type"], "Set": c.get("Set", ""), "Card": c["Name"],
                        "Tier": c["Tier"], "Power": c.get("Base Power ", ""), "Side": "Star " + side}
                r = from_text(base, c[side].strip(), kind)
                if side == "Front Side" and r["When"] == "on_attack":
                    r["When"] = "on_duel_start"
                rows.append(r)
    for path in sorted(glob.glob(os.path.join(DATA, "* Emblems.csv"))):
        with open(path, encoding="utf-8") as f:
            for c in csv.DictReader(f):
                for side in ("Basic Side", "Condition", "Ultimate Side"):
                    text = (c.get(side) or "").strip()
                    base = {"Class": c["Unit Type"], "Set": c.get("Set", ""), "Card": c["Name"],
                            "Side": "Emblem " + side}
                    if not text:
                        r = row(**base)
                        r["Status"] = "not written yet"
                        r["Question"] = "No text yet - the Ultimate is yours to write."
                        rows.append(r)
                        continue
                    r = from_text(base, text, side)
                    if side == "Condition":
                        r["When"] = "emblem_condition"
                        r["Do"] = "turn_over"
                        r["Words Needed"] = "emblem_condition"
                        r["Phase"] = "C7"
                        r["Status"] = "C7"
                        r["Question"] = "The counter in Turns On must be fed by a real match event - see the Emblem's Turns On column."
                    rows.append(r)

    for r in rows:
        r["Your Ruling"] = kept.get((r["Card"], r["Side"]), "")

    out = io.StringIO()
    w = csv.DictWriter(out, fieldnames=COLUMNS, lineterminator="\n")
    w.writeheader()
    w.writerows(rows)
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(out.getvalue())

    # ---- THE RULINGS: each question ONCE ----
    #
    # 169 rows ask about a dozen and a half things. Answering it 169 times
    # would be absurd, so every distinct question goes into
    # data/AbilityRulings.csv once, with how many cards it touches and how I
    # have read it in the meantime. Answer THERE; your answers are kept.
    rulings_path = os.path.join(DATA, "AbilityRulings.csv")
    old_rulings = {}
    if os.path.exists(rulings_path):
        with open(rulings_path, encoding="utf-8") as f:
            for old in csv.DictReader(f):
                if (old.get("Your Ruling") or "").strip():
                    old_rulings[old["Question"]] = old["Your Ruling"]
                    old_rulings[old["ID"]] = old["Your Ruling"]
    counts = {}
    examples = {}
    for r in rows:
        for _pat, q in QUESTIONS:
            if q in r["Question"]:
                counts[q] = counts.get(q, 0) + 1
                examples.setdefault(q, "%s (%s): %s" % (r["Card"], r["Class"], r["Text"][:90]))
    # THE FOUR THAT DECIDE EVERYTHING ELSE. Not about any one sentence -
    # about how a card with TWO abilities behaves at all. Listed first.
    rulings = [
        {"ID": "F1", "Question": "In a duel a card uses ONE of its two abilities: the ATTACK side when it attacks, the DEFEND side when it defends. Right? (Today the engine fires both sides, filtered only by trigger.)",
         "Cards": len([r for r in rows if r["Side"] in ("Attack", "Defend")]), "Example": "Sallos set: Attack 'Switch to being the defender' / Defend 'If Defending: ...'",
         "My Reading": "Yes - built that way in C1, behind ability_uses_role_side in Tuning.csv.", "Your Ruling": old_rulings.get("F1", "")},
        {"ID": "F2", "Question": "OUTSIDE a duel (in the exhaust zone, in exile, at the end of the cycle) which side counts - the one it played in its LAST duel, or both?",
         "Cards": 40, "Example": "Vassago I0: Attack '...+1 power' / Defend '...+2 power', both 'While in Exhaust'",
         "My Reading": "The side it played in its last duel.", "Your Ruling": old_rulings.get("F2", "")},
        {"ID": "F3", "Question": "REVEAL happens in the draft, before anyone knows who attacks. Which side's Reveal fires - Attack, Defend, or the one you choose when you press SHOW?",
         "Cards": 13, "Example": "Zepar I0: Attack 'next 2 swans...' / Defend 'next 3 swans...'",
         "My Reading": "Proposed: you choose, with two SHOW buttons. Until you rule: the side that HAS a Reveal fires - the Attack side if both do.", "Your Ruling": old_rulings.get("F3", "")},
        {"ID": "F4", "Question": "PRIORITY: today a card's ability priority IS its power, lower goes first, the attacker first on a tie. Keep that? And 'give ability priority' = goes FIRST regardless?",
         "Cards": 6, "Example": "Sitri II2 'Give a Tier II water unit ability priority'; Vassago III4 'Change enemy priority by -1'",
         "My Reading": "Keep it. 'Ability priority' = resolves first; '+1 / -1 priority' moves its place in the queue by one.", "Your Ruling": old_rulings.get("F4", "")},
    ]
    for r in rulings:
        if not r["Your Ruling"]:
            r["Your Ruling"] = old_rulings.get(r["Question"], "")
    for n, (_pat, q) in enumerate(QUESTIONS, 1):
        if q not in counts:
            continue
        reading = ""
        m = re.search(r"\((Read[^)]*|Proposed[^)]*)\)", q)
        if m:
            reading = m.group(1)
        rulings.append({"ID": "R%02d" % n, "Question": q, "Cards": counts[q],
                        "Example": examples[q], "My Reading": reading,
                        "Your Ruling": old_rulings.get(q, "")})
    out2 = io.StringIO()
    w2 = csv.DictWriter(out2, fieldnames=["ID", "Question", "Cards", "Example", "My Reading", "Your Ruling"],
                        lineterminator="\n")
    w2.writeheader()
    w2.writerows(rulings)
    with open(rulings_path, "w", encoding="utf-8") as f:
        f.write(out2.getvalue())

    # ---- the summary, in words ----
    from collections import Counter
    by_status = Counter(r["Status"].split(" - ")[0] if r["Status"] else "?" for r in rows)
    by_class = {}
    for r in rows:
        by_class.setdefault(r["Class"], Counter())[r["Status"].split(" - ")[0]] += 1
    print("%d ability texts read. %d of your rulings kept." % (len(rows), len(kept)))
    print("")
    print("By the phase that makes them work:")
    for key in ["works today"] + PHASE_ORDER + [p + " system" for p in PHASE_ORDER] + ["needs your ruling", "not written yet"]:
        if by_status.get(key):
            print("   %-18s %3d" % (key, by_status[key]))
    print("")
    asks = sum(1 for r in rows if r["Question"])
    print("%d rows carry a question for you (the Question column)." % asks)
    print("Written to data/AbilityAudit.csv")
    print("%d distinct questions, each asked once, in data/AbilityRulings.csv." % len(rulings))
    return 0


if __name__ == "__main__":
    sys.exit(main())
