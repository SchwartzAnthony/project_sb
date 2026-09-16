class_name InstallCheck
extends RefCounted

# =============================================================
#  IS EVERYTHING WHERE IT SHOULD BE?
#
#  ============ WHY THIS EXISTS ============
#
#  Godot finds a script by its `class_name`, not by its path. So when a file
#  ends up in the wrong folder — or does not get copied at all — Godot does
#  not say "SaveSlots.gd is missing". It says
#
#      Identifier "SaveSlots" not declared in the current scope
#
#  in every file that mentions it. One missing file becomes twenty errors,
#  none of which name the file.
#
#  This reads res://data/FileManifest.csv — a plain list of every file and
#  the folder it belongs in — and prints, in words, exactly what is missing
#  and exactly where to put it. It runs once when the title screen opens.
#
#  ============ THE MANIFEST ============
#
#      File     the file name
#      Folder   where it goes, under res://
#      What it is / Notes    for you
#
#  Add a file to your project, add a row. The check then guards it too.
#
#  ============ IT NEVER STOPS THE GAME ============
#
#  Everything here prints and returns. A missing file is reported and the
#  game carries on as far as it can — which is what you want, because the
#  report is more useful than a crash.
# =============================================================

const MANIFEST := "res://data/FileManifest.csv"
const DONE_KEY := "cw_install_checked"


## Called once by the title screen. Safe to call again from anywhere.
static func run(tree: SceneTree, force: bool = false) -> void:
	if tree != null and tree.has_meta(DONE_KEY) and not force:
		return
	if tree != null:
		tree.set_meta(DONE_KEY, true)

	var rows := MenuSupport.read_csv(MANIFEST)
	if rows.is_empty():
		print("[install] No %s, so nothing was checked. That file is a plain list of every file and its folder — see install_check.gd." % MANIFEST)
		return

	var missing: Array[String] = []
	var misplaced: Array[String] = []
	var checked := 0

	for row in rows:
		var file_name := MenuSupport.field(row, "File")
		var folder := MenuSupport.field(row, "Folder")
		if file_name == "" or folder == "":
			continue
		checked += 1

		var should_be := "res://" + folder.strip_edges().trim_suffix("/") + "/" + file_name
		if FileAccess.file_exists(should_be):
			continue

		# Not where it should be. Is it anywhere at all? If it is, the fix is
		# to move it, and saying WHERE it is now is most of the answer.
		var found := _find(file_name)
		if found == "":
			missing.append("%s        should be in  %s" % [file_name, folder])
		else:
			misplaced.append("%s\n        is in    %s\n        move to  %s"
				% [file_name, found.get_base_dir() + "/", folder])

	if missing.is_empty() and misplaced.is_empty():
		print("[install] All %d files are where they should be." % checked)
		return

	print("")
	print("=============================================================")
	print(" SOMETHING IS IN THE WRONG PLACE")
	print("")
	print(" Godot finds a script by its class_name, not its path — so one")
	print(" file in the wrong folder shows up as a dozen 'not declared in")
	print(" the current scope' errors that never name the file. This is the")
	print(" list of what is actually wrong.")
	print("=============================================================")

	if not misplaced.is_empty():
		print("")
		print(" IN THE WRONG FOLDER  (%d)" % misplaced.size())
		for note in misplaced:
			print("   " + note)

	if not missing.is_empty():
		print("")
		print(" NOT IN THE PROJECT AT ALL  (%d)" % missing.size())
		for note in missing:
			print("   " + note)
		print("")
		print("   These are in the zip, in folders of the same names. Copy the")
		print("   folder over the top of res:// and they land in the right places.")

	print("")
	print(" Fix those and the errors above this go away together.")
	print("=============================================================")
	print("")


## Look for a file anywhere under res://, so a misplaced one can be named.
static func _find(file_name: String) -> String:
	var queue: Array[String] = ["res://"]
	while not queue.is_empty():
		var here: String = queue.pop_front()
		var dir := DirAccess.open(here)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if entry.begins_with("."):
				entry = dir.get_next()
				continue
			var full := here.path_join(entry)
			if dir.current_is_dir():
				if not ScenePaths.SKIP_DIRS.has(entry):
					queue.append(full)
			elif entry == file_name:
				dir.list_dir_end()
				return full
			entry = dir.get_next()
		dir.list_dir_end()
	return ""
