class_name DialogueChoice
extends RefCounted

# =============================================================
#  ONE CHOICE — a button under the text box.
#
#  Filled in from the "Choice 1 Text / Next / Requires / Effects" columns
#  (and 2, 3, 4) of Dialogue.csv.
# =============================================================

## What the button says.
var text: String = ""
## The Node ID this choice jumps to. Blank ends the scene.
var next_id: String = ""
## Condition for the button to appear at all — see DialogueGrammar.
## An unearned choice is not greyed out, it is simply absent.
var requires: String = ""
## Applied the moment the button is clicked, before the jump.
var effects: String = ""
## Which of the four columns this came from, for error messages.
var slot: int = 0


func is_available(state: GameState) -> bool:
	return DialogueGrammar.test(requires, state)


func take(state: GameState) -> void:
	DialogueGrammar.apply(effects, state)
