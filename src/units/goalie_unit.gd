class_name GoalieUnit
extends Area2D

# =============================================================
#  GOALIE
#
#  Stamina is a WALL, and the wall gets weaker as you knock it down. How much
#  weaker is a curve you draw in `data/ShotOdds.csv`, and the number it
#  produces is PRINTED ON THE SCREEN before the shot is taken — in the
#  shootout cut-away, and beside the keeper on the pitch.
#
#  AT 0 STAMINA THE GOAL IS OPEN AND THE SHOT GOES IN. That is the 0 row of
#  ShotOdds.csv saying 100, not a rule in here, so you can change your mind
#  about it in a spreadsheet.
#
#  Conceding a goal fully restores THIS goalie's stamina only.
#
#  NOTE: goalie_unit.tscn's ROOT NODE must be an Area2D. If it is a
#  Node2D, instantiate() silently returns null and no goals can ever be
#  scored. Use the corrected goalie_unit.tscn shipped alongside this file.
# =============================================================

signal goal_conceded
signal stamina_depleted
signal shot_saved(remaining_stamina: int)

@export var max_stamina: int = 40

# ============ THE TWO OLD NUMBERS, KEPT AND NO LONGER USED ============
#
# `break_through_chance` was a FLAT 5% while the keeper had any stamina at
# all, and `open_goal_chance` was 90% once he had none. Between them they
# said that a keeper on 1 stamina is exactly as hard to beat as a keeper on
# 30, and that an empty net still saves one shot in ten.
#
# ShotOdds.csv replaces both with a curve. They are kept here because
# Tuning.csv still has rows pointing at them and an older save or an older
# spreadsheet should not break — see `_tune_goalie()` in main_scene.gd — and
# because `shot_odds` false in Tuning.csv puts the old behaviour back.
@export_range(0.0, 1.0, 0.01) var break_through_chance: float = 0.05
@export_range(0.0, 1.0, 0.01) var open_goal_chance: float = 0.90

## false goes back to the two flat numbers above. Set from Tuning.csv.
var use_shot_odds: bool = true

var current_stamina: int
var is_enemy: bool = false
var data: GoalieData

# Typed as Range, not ProgressBar — TextureProgressBar and ProgressBar are
# siblings, both extending Range. Typing this as ProgressBar breaks any
# scene that uses a TextureProgressBar.
@onready var artwork: Sprite2D = get_node_or_null("Artwork")
@onready var stamina_bar: Range = get_node_or_null("StaminaBar")
@onready var name_label: Label = get_node_or_null("NameLabel")


# =============================================================
#  SEEING THE KEEPER
#
#  The Artwork sprite has no texture until Goalies.csv gives it one. With a
#  blank Artwork column, or a PNG that is not there, the keeper was drawn as
#  nothing at all — which is why you could not see a goalkeeper for a whole
#  match.
#
#  So when there is no texture, one is drawn here instead: a coloured post
#  with a G on it. The same "playable before you have art" rule the base
#  screen uses for buildings and visitors.
#
#  Draw the art and this disappears on its own. Nothing to switch off.
# =============================================================

const FALLBACK_SIZE := Vector2(30.0, 54.0)
const FALLBACK_HOME := Color(0.36, 0.72, 0.95)
const FALLBACK_AWAY := Color(0.95, 0.45, 0.42)


func _draw() -> void:
	if artwork != null and artwork.texture != null:
		return   # you have drawn one; nothing to stand in for

	var box := Rect2(-FALLBACK_SIZE * 0.5, FALLBACK_SIZE)
	var body := FALLBACK_AWAY if is_enemy else FALLBACK_HOME

	draw_rect(box.grow(2.0), Color(0, 0, 0, 0.55), true)
	draw_rect(box, body, true)
	draw_rect(box, body.lightened(0.35), false, 2.0)

	# Gloves, so it reads as a keeper rather than an outfield player.
	var glove := Vector2(7.0, 7.0)
	draw_rect(Rect2(box.position - Vector2(glove.x, -6.0), glove),
		Color(0.98, 0.86, 0.4), true)
	draw_rect(Rect2(Vector2(box.end.x, box.position.y + 6.0), glove),
		Color(0.98, 0.86, 0.4), true)

	var font := ThemeDB.fallback_font
	if font != null:
		draw_string(font, Vector2(-5.0, 6.0), "G",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.08, 0.09, 0.12))


func _ready() -> void:
	_refill()


func setup(goalie_data: GoalieData) -> void:
	data = goalie_data
	if data == null:
		return
	max_stamina = data.max_stamina
	if data.artwork != null and artwork != null:
		artwork.texture = data.artwork
	if name_label != null:
		name_label.text = data.goalie_name
	if is_node_ready():
		_refill()


func _refill() -> void:
	current_stamina = max_stamina
	if stamina_bar != null:
		stamina_bar.max_value = max_stamina
		stamina_bar.value = current_stamina
	if artwork != null:
		artwork.modulate = Color.WHITE
	_refresh_plate()


# =============================================================
#  SHOT RESOLUTION — returns true if the shot was a GOAL
# =============================================================

func take_shot(shot_power: int) -> bool:
	if not use_shot_odds:
		return _take_shot_the_old_way(shot_power)

	# ============ ROLL FIRST, THEN TAKE THE STAMINA OFF ============
	#
	# THE ORDER IS THE WHOLE POINT. The player was shown a percentage a
	# second ago, worked out from the stamina the keeper had then. Chipping
	# the stamina before rolling would roll against a DIFFERENT number to the
	# one on the screen — the cut-away would say 52% and the game would
	# quietly roll 61%, and nobody could ever tell.
	#
	# So: roll against what was shown, then knock the wall down for next time.
	# A shot that empties a keeper does not get the empty keeper's odds. The
	# next one does, and it is a certainty.
	var went_in := randf() < ShotOdds.odds(current_stamina, max_stamina, shot_power)

	current_stamina = maxi(0, current_stamina - shot_power)
	if stamina_bar != null:
		stamina_bar.value = current_stamina
	if current_stamina == 0:
		stamina_depleted.emit()
		play_exhausted_feedback()
	_refresh_plate()

	if went_in:
		_concede()
		return true

	play_save_feedback()
	shot_saved.emit(current_stamina)
	return false


## What it did before ShotOdds.csv: a flat 5% while he had anything left and
## 90% once he did not. `shot_odds` false in Tuning.csv brings it back.
func _take_shot_the_old_way(shot_power: int) -> bool:
	if current_stamina <= 0:
		if randf() < open_goal_chance:
			_concede()
			return true
		play_save_feedback()
		return false

	current_stamina = maxi(0, current_stamina - shot_power)
	if stamina_bar != null:
		stamina_bar.value = current_stamina
	_refresh_plate()

	if current_stamina == 0:
		stamina_depleted.emit()
		play_exhausted_feedback()
	else:
		play_save_feedback()

	if randf() < break_through_chance:
		_concede()
		return true

	shot_saved.emit(current_stamina)
	return false


# =============================================================
#  WHAT THE PLAYER IS TOLD
# =============================================================

## The chance a shot of this power scores, 0 to 100. What the cut-away shows.
func chance_of_goal(shot_power: int) -> float:
	if not use_shot_odds:
		return 100.0 * (open_goal_chance if current_stamina <= 0 else break_through_chance)
	return ShotOdds.chance(current_stamina, max_stamina, shot_power)


## "8 – 18%", or a flat "100%" when the keeper is empty. What the pitch shows,
## where nobody knows yet how hard the shot will be.
func chance_band() -> String:
	var top := 5
	var db := CardDatabase.get_db()
	if db != null:
		top = int(db.tune_float("shot_power_shown", 5.0))
	if not use_shot_odds:
		return "%d%%" % int(round(chance_of_goal(0)))
	return ShotOdds.band_text(current_stamina, max_stamina, top)


func _concede() -> void:
	goal_conceded.emit()
	print("%s conceded a goal — stamina reset to %d" % [
		"Enemy goalie" if is_enemy else "Player goalie", max_stamina
	])
	# A conceded goal resets ONLY this goalie. The other keeper is untouched.
	_refill()
	play_concede_feedback()


## Used by abilities (drain_stamina / restore_stamina from Abilities.csv).
func adjust_stamina(delta: int) -> void:
	current_stamina = clampi(current_stamina + delta, 0, max_stamina)
	if stamina_bar != null:
		stamina_bar.value = current_stamina
	if current_stamina == 0:
		stamina_depleted.emit()
		play_exhausted_feedback()
	_refresh_plate()


## Backwards-compatible alias for older call sites.
func absorb_shot(shot_power: int) -> void:
	take_shot(shot_power)


# =============================================================
#  FEEDBACK
# =============================================================

## Lunge toward the incoming ball and come back to the line. Called as the
## shot is struck, so the keeper is visibly trying for it either way.
func dive_at(target: Vector2, seconds: float = 0.42) -> void:
	var line := global_position
	var direction := (target - line)
	if direction.length() < 1.0:
		return
	var lunge := line + direction.normalized() * 28.0

	var tween := create_tween()
	tween.tween_property(self, "global_position", lunge, seconds * 0.4) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", line, seconds * 0.6) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func play_save_feedback() -> void:
	if artwork == null:
		return
	var tween := create_tween()
	tween.tween_property(artwork, "modulate", Color.CYAN, 0.1)
	tween.tween_property(artwork, "modulate", _resting_colour(), 0.1)


func play_exhausted_feedback() -> void:
	if artwork == null:
		return
	artwork.modulate = Color(0.6, 0.6, 0.6, 0.8)


func play_concede_feedback() -> void:
	if artwork == null:
		return
	var tween := create_tween()
	tween.tween_property(artwork, "modulate", Color.RED, 0.15)
	tween.tween_property(artwork, "modulate", Color.WHITE, 0.35)


func _resting_colour() -> Color:
	return Color(0.6, 0.6, 0.6, 0.8) if current_stamina == 0 else Color.WHITE


# =============================================================
#  THE PLATE ON THE PITCH
#
#  ============ WHY THE KEEPER SAYS A NUMBER NOW ============
#
#  The whole draft is a bet on one shot, and until now the only thing on
#  screen about the keeper was a small bar going down. A bar tells you that
#  something is happening; it does not tell you whether the next shot is
#  worth taking. So the keeper says it out loud:
#
#      Undine Aegis
#      8 – 18%
#
#  Two numbers, because on the pitch NOBODY KNOWS YET how hard the shot will
#  be — the low end is a shot of no power at all and the high end is a shot
#  of `shot_power_shown`. They collapse to one number when they agree, which
#  is exactly what happens at 0 stamina: a flat, unambiguous 100%.
#
#  Coloured cool when the keeper is winning and warm when he is losing, on
#  the same two colours as ATTACKING and DEFENDING everywhere else — because
#  a low number and a high number here mean precisely those two things.
#
#  `keeper_chance_on_pitch` in Tuning.csv takes it off again.
# =============================================================

var _chance_label: Label


func _refresh_plate() -> void:
	if not is_node_ready():
		return
	var db := CardDatabase.get_db()
	var wanted := db == null or db.tune_bool("keeper_chance_on_pitch", true)

	if not wanted:
		if _chance_label != null and is_instance_valid(_chance_label):
			_chance_label.visible = false
		return

	if _chance_label == null or not is_instance_valid(_chance_label):
		_chance_label = Label.new()
		_chance_label.name = "ChanceLabel"
		_chance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_chance_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Under the stamina bar, which sits at +26 to +38.
		_chance_label.offset_left = -46.0
		_chance_label.offset_right = 46.0
		_chance_label.offset_top = 40.0
		_chance_label.offset_bottom = 60.0
		add_child(_chance_label)

	var size := 12
	if db != null:
		size = int(db.tune_float("keeper_chance_size", 12.0))
	_chance_label.visible = true
	_chance_label.text = chance_band()
	_chance_label.add_theme_font_size_override("font_size", size)
	_chance_label.add_theme_color_override("font_color",
		ShotOdds.colour_for(chance_of_goal(0)))
	# A dark plate behind it, because white text on grass is white text on
	# grass and this one is meant to be readable at a glance.
	_chance_label.add_theme_stylebox_override("normal",
		MenuSupport.panel_style(Color(0.05, 0.06, 0.09, 0.78)))
