class_name DialogueLine
extends RefCounted

# =============================================================
#  ONE LINE OF STORY — one row of Dialogue.csv.
#
#  Everything the screen needs to draw a moment: who is speaking, their
#  picture, the backdrop, the words, and where it goes next.
# =============================================================

## Groups rows into stories. One CSV can hold as many scenes as you like.
var scene: String = ""
## Unique within its scene. This is what Next and Choice Next point at.
var id: String = ""

# --- Presentation ---
var speaker: String = ""      # blank = narration, no name plate
var portrait: String = ""     # PNG name, found in assets/portraits/
var side: String = "left"     # left / right / centre
var animation: String = ""    # a row in Animations.csv, played on the portrait
var mood: String = ""         # happy / sad / drunk / mad ... a StoryArt.csv Mood
var view: String = ""         # front (to the player) / side (to someone else)
var leaves: String = ""       # who walks off as this line shows: names or IDs; or "all"
var background: String = ""   # PNG name, found in assets/backgrounds/
var music: String = ""        # OGG or WAV name, found in assets/music/
var sound: String = ""        # one-off sound: an Audio.csv ID, played as the line shows
var text: String = ""

# --- Flow ---
## Where to go with no choices. Blank AND no choices ends the scene.
var next_id: String = ""
## Condition for this line to be used at all. A line whose Requires fails is
## skipped over, and the one after it in the file is tried instead.
var requires: String = ""
## Applied when the line is SHOWN, before you read it.
var effects: String = ""
var choices: Array[DialogueChoice] = []

## Row number in the CSV, so a complaint can name the line to fix.
var source_row: int = 0
var source_file: String = ""


func has_choices() -> bool:
	return not choices.is_empty()


func is_available(state: GameState) -> bool:
	return DialogueGrammar.test(requires, state)


func show_effects(state: GameState) -> void:
	DialogueGrammar.apply(effects, state)


## Only the choices whose own Requires pass.
func available_choices(state: GameState) -> Array[DialogueChoice]:
	var out: Array[DialogueChoice] = []
	for choice in choices:
		if choice.is_available(state):
			out.append(choice)
	return out


func where() -> String:
	return "%s row %d ('%s')" % [source_file, source_row, id]
