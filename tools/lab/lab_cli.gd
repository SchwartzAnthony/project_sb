extends SceneTree

# Runs Sturmball Lab commands on the command line, one JSON per argument:
#   godot --headless --path . --script res://tools/lab/lab_cli.gd -- '{"cmd":"meta"}' '{"cmd":"match_new"}'
# Each answer is printed on its own line, after "LAB>". One command runs per
# frame, and {"wait": 120} lets 120 frames pass (an Adventure fight needs them).

var lab: Node
var queue: Array = []
var waiting := 0


func _initialize() -> void:
	lab = load("res://tools/lab/lab.gd").new()
	root.add_child(lab)
	queue = Array(OS.get_cmdline_user_args())


func _process(_delta: float) -> bool:
	if waiting > 0:
		waiting -= 1
		return false
	if queue.is_empty():
		return true
	var arg := String(queue.pop_front())
	var req = JSON.parse_string(arg)
	if typeof(req) == TYPE_DICTIONARY and req.has("wait"):
		waiting = int(req["wait"])
		return false
	print("LAB> " + lab.handle_text(arg))
	return false
