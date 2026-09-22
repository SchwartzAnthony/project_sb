class_name ShootoutView
extends CanvasLayer

# =============================================================
#  THE SHOOTOUT CUT-AWAY
#
#  Opens just before the shot. The keeper faces you (first person, as if
#  you were standing on the penalty spot) and the striker is seen FROM
#  BEHIND at the bottom of the frame, so the camera sits over their
#  shoulder. Shot power and keeper stamina are on show, the striker
#  plays their `kick`, then the window closes and the real ball flight
#  you already have takes over on the pitch.
#
#  ART, ALL OPTIONAL — it works with nothing drawn yet:
#    Keeper front view : "Shootout Artwork" column in Goalies.csv,
#                        animations `keeper_ready` / `keeper_dive`
#    Striker from behind: the card's own sheet, animation `kick_back`,
#                        falling back to `kick`, then `idle`
#  Anything missing draws a clean placeholder instead of breaking, so you
#  can play the whole sequence today and swap art in one piece at a time.
# =============================================================

signal shot_taken          # the striker's foot has hit the ball
signal view_closed

const BASE := "Dim/Center/Frame/Margin/VBox"

var db: CardDatabase

var open_seconds: float = 0.7
var read_seconds: float = 0.9
var windup_seconds: float = 0.8
var close_seconds: float = 0.4
var speed: float = 1.0
var skip_speed: float = 6.0

var _running := false
var _skipping := false

var _dim: ColorRect
var _title: Label
var _caption: Label
var _shot_value: Label
var _stamina_value: Label
var _stamina_bar: ProgressBar
var _chance_value: Label
var _chance_note: Label
var _keeper_stage: Control
var _striker_stage: Control
var _keeper_anim: SpriteAnimator
var _striker_anim: SpriteAnimator
var _keeper_placeholder: ColorRect
var _striker_placeholder: ColorRect


func _ready() -> void:
	_wire()
	if _dim:
		_dim.visible = false


func _wire() -> void:
	if _dim != null:
		return
	_dim = get_node_or_null("Dim") as ColorRect
	if _dim == null:
		push_error("shootout_view.tscn is missing its Dim node.")
		return

	_title = get_node_or_null(BASE + "/Title") as Label
	_caption = get_node_or_null(BASE + "/Caption") as Label
	_shot_value = get_node_or_null(BASE + "/Readouts/ShotBox/ShotValue") as Label
	_stamina_value = get_node_or_null(BASE + "/Readouts/StaminaBox/StaminaValue") as Label
	_stamina_bar = get_node_or_null(BASE + "/Readouts/StaminaBox/StaminaBar") as ProgressBar
	_chance_value = get_node_or_null(BASE + "/Readouts/ChanceBox/ChanceValue") as Label
	_chance_note = get_node_or_null(BASE + "/Readouts/ChanceBox/ChanceNote") as Label
	_keeper_stage = get_node_or_null(BASE + "/Stage/KeeperStage") as Control
	_striker_stage = get_node_or_null(BASE + "/Stage/StrikerStage") as Control

	_keeper_anim = SpriteAnimator.new()
	_striker_anim = SpriteAnimator.new()
	_keeper_placeholder = _make_placeholder(Color(0.30, 0.40, 0.55, 0.85), Vector2(320, 300))
	_striker_placeholder = _make_placeholder(Color(0.45, 0.30, 0.30, 0.85), Vector2(180, 210))

	if _keeper_stage:
		_keeper_stage.add_child(_keeper_placeholder)
		_keeper_stage.add_child(_keeper_anim)
	if _striker_stage:
		_striker_stage.add_child(_striker_placeholder)
		_striker_stage.add_child(_striker_anim)


func _make_placeholder(colour: Color, box: Vector2) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = colour
	rect.custom_minimum_size = box
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func apply_tuning(database: CardDatabase) -> void:
	db = database
	speed = db.tune_float("arena_speed", speed)
	skip_speed = db.tune_float("arena_skip_speed", skip_speed)
	open_seconds = db.tune_float("shootout_open_seconds", open_seconds)
	read_seconds = db.tune_float("shootout_read_seconds", read_seconds)
	windup_seconds = db.tune_float("shootout_windup_seconds", windup_seconds)
	close_seconds = db.tune_float("shootout_close_seconds", close_seconds)


func is_running() -> bool:
	return _running


func skip() -> void:
	_skipping = true


# =============================================================
#  SEQUENCE
#
#  `info` keys:
#    shooter_card, shooter_is_player, shot_power,
#    keeper_data (GoalieData|null), keeper_stamina, keeper_max
# =============================================================

func play_shot(info: Dictionary) -> void:
	_wire()
	if _dim == null:
		view_closed.emit()
		return

	_running = true
	_skipping = false
	_dim.visible = true

	var card = info.get("shooter_card")
	var is_player := bool(info.get("shooter_is_player", true))
	var power := int(info.get("shot_power", 0))
	var stamina := int(info.get("keeper_stamina", 0))
	var stamina_max := maxi(1, int(info.get("keeper_max", 1)))
	var keeper_data = info.get("keeper_data")

	if _title:
		# "YOU SHOOTS" was on this screen for eleven rounds. One verb per
		# side, and both are rows of Language.csv so they translate.
		_title.text = Loc.text("you_shoot", "YOU SHOOT") if is_player \
			else Loc.text("they_shoot", "THEY SHOOT")
	if _caption:
		_caption.text = card.player_name if card != null else "—"
	if _shot_value:
		_shot_value.text = str(power)
	if _stamina_value:
		_stamina_value.text = "%d / %d" % [stamina, stamina_max]
	if _stamina_bar:
		_stamina_bar.max_value = stamina_max
		_stamina_bar.value = stamina

	# ============ THE NUMBER THE WHOLE ROUND WAS FOR ============
	#
	# Shot power and keeper stamina were already on this screen, and between
	# them they are the two halves of a sum the player was being asked to do
	# in their head with no idea what the formula was. So the game does the
	# sum: this is the chance, out of ShotOdds.csv, and IT IS THE NUMBER THAT
	# IS ABOUT TO BE ROLLED — see take_shot() in goalie_unit.gd for why the
	# order of operations there matters.
	if _chance_value:
		var percent := ShotOdds.chance(stamina, stamina_max, power)
		_chance_value.text = "%d%%" % int(round(percent))
		_chance_value.add_theme_color_override("font_color", ShotOdds.colour_for(percent))
		if _chance_note:
			# An empty keeper is not a probability any more, it is a fact, and
			# it should read like one.
			if stamina <= 0:
				_chance_note.text = Loc.text("goal_is_open", "the goal is open")
			elif percent >= 99.5:
				_chance_note.text = "he cannot stop this"
			else:
				_chance_note.text = "%d of %d stamina left" % [stamina, stamina_max]

	_dress_keeper(keeper_data)
	_dress_striker(card, "idle")

	await _beat(open_seconds)
	await _beat(read_seconds)

	# The strike.
	_dress_striker(card, "kick_back")
	if _keeper_anim.is_playing() or _keeper_placeholder.visible:
		_play_keeper(keeper_data, "keeper_dive")
	await _beat(windup_seconds)
	shot_taken.emit()

	await _beat(close_seconds)
	_dim.visible = false
	_running = false
	view_closed.emit()


func _dress_keeper(keeper_data) -> void:
	_play_keeper(keeper_data, "keeper_ready")


func _play_keeper(keeper_data, anim_name: String) -> void:
	var sheet: Texture2D = null
	if keeper_data != null and keeper_data.shootout_artwork != null:
		sheet = keeper_data.shootout_artwork

	var spec: AnimSpec = null
	if db != null:
		spec = db.get_anim(anim_name)

	var have_art := sheet != null and spec != null
	if _keeper_placeholder:
		_keeper_placeholder.visible = not have_art
	if _keeper_anim:
		_keeper_anim.visible = have_art
		if have_art:
			_keeper_anim.speed_scale = _rate()
			_keeper_anim.play(sheet, spec)
			_keeper_anim.fit_into(Vector2(520.0, 340.0))


func _dress_striker(card, anim_name: String) -> void:
	var spec: AnimSpec = null
	if db != null and card != null:
		# A dedicated from-behind animation if you have drawn one, else the
		# normal kick, else idle.
		for candidate in [anim_name, "kick", "idle"]:
			spec = db.get_anim(candidate, card.unit_type)
			if spec != null:
				break

	var have_art := card != null and card.artwork != null and spec != null
	if _striker_placeholder:
		_striker_placeholder.visible = not have_art
	if _striker_anim:
		_striker_anim.visible = have_art
		if have_art:
			_striker_anim.speed_scale = _rate()
			_striker_anim.play(card.artwork, spec)
			_striker_anim.fit_into(Vector2(300.0, 220.0))


func _rate() -> float:
	return maxf(0.05, skip_speed if _skipping else speed)


func _beat(seconds: float) -> void:
	var wait := seconds / _rate()
	if wait <= 0.001:
		await get_tree().process_frame
		return
	await get_tree().create_timer(wait).timeout


func _unhandled_input(event: InputEvent) -> void:
	if not _running:
		return
	if event is InputEventMouseButton and event.pressed:
		skip()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		skip()
