class_name GoalieData
extends Resource

# Built at runtime by CardDatabase from Goalies.csv.
# Columns: Team, Name, Max Stamina, Passive / Ability, Artwork, [Ability ID]

@export var team: String = ""
@export var goalie_name: String = ""
@export var max_stamina: int = 25
@export_multiline var ability_text: String = ""
## Optional — an "Ability ID" column pointing at a row in Abilities.csv.
@export var ability_id: String = ""
@export var artwork: Texture2D
