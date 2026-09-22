extends SceneTree

# =============================================================
#  EVERY CSV NEEDS A .csv.import NEXT TO IT — THIS MAKES THE MISSING ONES
#
#  ============ THE TRAP ============
#
#  Godot treats a .csv as a TRANSLATION FILE unless something tells it not
#  to. Drop a new spreadsheet into data/, open the project, and Godot quietly
#  writes one .translation file per COLUMN beside it:
#
#      Unit_Set_Lorelei.Artwork.translation
#      Unit_Set_Lorelei.Attack.translation
#      Unit_Set_Lorelei.Base Power .translation
#      ... and nine more, for one file
#
#  Four new spreadsheets made thirty-two of them. They do nothing, they are
#  committed to the repository along with everything else, and they come back
#  every time the project is imported.
#
#  What stops it is a three-line file beside the CSV, named after it:
#
#      data/Unit_Set_Lorelei.csv.import
#
#          [remap]
#
#          importer="keep"
#
#  ============ WHAT THIS DOES ============
#
#  Walks data/ (and any folder you name), writes the missing .csv.import
#  files, and deletes the .translation files that were made because they were
#  missing. Run it after adding a spreadsheet and before opening the project:
#
#      godot --headless --script res://tools/csv_import_fix.gd
#
#  It NEVER touches a .csv.import that already exists and it never touches a
#  .csv. It prints every file it writes and every one it removes.
#
#  A tool, not part of the game. Nothing loads it.
# =============================================================

const FOLDERS := ["res://data", "res://data/tutorial"]
const KEEP := "[remap]\n\nimporter=\"keep\"\n"


func _initialize() -> void:
	var written := 0
	var removed := 0
	var already := 0

	for folder in FOLDERS:
		var dir := DirAccess.open(folder)
		if dir == null:
			continue
		dir.list_dir_begin()
		var names: Array[String] = []
		var name_text := dir.get_next()
		while name_text != "":
			if not dir.current_is_dir():
				names.append(name_text)
			name_text = dir.get_next()
		dir.list_dir_end()

		for file_name in names:
			# ---- a CSV with no .csv.import ----
			if file_name.to_lower().ends_with(".csv"):
				var want := "%s/%s.import" % [folder, file_name]
				# ============ IT IS NOT ENOUGH FOR THE FILE TO EXIST ============
				#
				# When Godot imports a CSV as a translation it WRITES ONE
				# ITSELF, saying importer="csv_translation". So "is there a
				# .csv.import beside it" is the wrong question and answering
				# it cost me a run: every file had one, and every file was
				# still being turned into translations. The question is
				# whether it says `keep`.
				if FileAccess.file_exists(want):
					var have := FileAccess.open(want, FileAccess.READ)
					var body := have.get_as_text() if have != null else ""
					if have != null:
						have.close()
					if body.contains("importer=\"keep\""):
						already += 1
						continue
					print("[csv] %s says %s — rewriting it" % [want,
						"importer=\"csv_translation\"" if body.contains("csv_translation")
						else "something else"])
				var out := FileAccess.open(want, FileAccess.WRITE)
				if out == null:
					print("[csv] could NOT write %s — is the folder read-only?" % want)
					continue
				out.store_string(KEEP)
				out.close()
				written += 1
				print("[csv] wrote %s" % want)

			# ---- a .translation that only exists because one was missing ----
			if file_name.to_lower().ends_with(".translation") \
					or file_name.contains(".translation-"):
				var stray := "%s/%s" % [folder, file_name]
				if DirAccess.remove_absolute(ProjectSettings.globalize_path(stray)) == OK:
					removed += 1
					print("[csv] removed %s" % stray)

	print("")
	print("[csv] %d .csv.import file(s) written, %d already there, %d stray .translation file(s) removed."
		% [written, already, removed])
	if written > 0 or removed > 0:
		print("[csv] DELETE THE .godot FOLDER and let the project reimport, or the")
		print("[csv] old translations stay in the import cache.")
	quit(0)
