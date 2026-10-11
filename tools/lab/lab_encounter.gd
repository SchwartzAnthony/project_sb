extends AdventureEncounter

# =============================================================
#  THE ADVENTURE FIGHT, WITH NO SCREEN - for Sturmball Lab
#
#  The real AdventureEncounter: every rule (focus, the draft, the icon pile
#  and its breakpoints, the hit, the layers and their soak, the enemies'
#  targeting, walkovers, the cycle) is the parent's code, untouched.
#
#  Only the four things that DRAW or WAIT are replaced:
#    _build_ui         a few invisible labels and buttons instead of windows
#    _refresh_choices  draws the card window - nothing to draw
#    _note             the log line goes to the lab instead of a Label
#    _beat             a pause for the eye - no pause
#  and _ready skips the enemy buttons and the build-up windows, which only
#  show the move going in (what an enemy gains is worked out before they
#  play). With nothing to wait for, a whole round resolves in one frame.
# =============================================================

signal noted(text: String)


static func open_bare(parent: Node, database: CardDatabase, save: GameState,
		the_run: AdventureRun, wave: Array[Dictionary]) -> AdventureEncounter:
	var fight = load("res://tools/lab/lab_encounter.gd").new()
	fight.db = database
	fight.state = save
	fight.run = the_run
	fight.adventure = AdventureDB.get_db()
	# The same scaling AdventureEncounter.open() applies.
	var hard := the_run.difficulty(save, database)
	for entry in wave:
		fight.foes.append(AdventureEncounter._fresh_foe(entry, hard))
	fight.set_meta("hard", hard)
	parent.add_child(fight)
	return fight


func _ready() -> void:
	_build_ui()
	_push_bars()
	_begin_round()


func _build_ui() -> void:
	_title = Label.new()
	_prompt = Label.new()
	_detail = Label.new()
	_item_button = Button.new()
	_flee_button = Button.new()
	_log_button = Button.new()
	for n in [_title, _prompt, _detail, _item_button, _flee_button, _log_button]:
		n.visible = false
		add_child(n)


func _refresh_choices() -> void:
	pass


func _note(text: String) -> void:
	noted.emit(text)


func _beat(_seconds: float = 0.7) -> void:
	pass
