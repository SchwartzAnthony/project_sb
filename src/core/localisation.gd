class_name Loc
extends RefCounted

# =============================================================
#  LANGUAGES — one spreadsheet, one column per language
#
#  ============ res://data/Language.csv ============
#
#      Key,English,Deutsch,Notes
#      back,Back,Zurück,The Back button on every screen
#      play_a_match,Play a match,Spiel bestreiten,
#
#  ONE COLUMN PER LANGUAGE. Add a column headed `Français`, fill it in, and
#  French appears in Settings > Language. Delete a column and that language
#  is gone. There is no list of languages anywhere in the code — the columns
#  of that file ARE the list.
#
#  `Key` is the short word the game asks for. `Notes` is for you and is never
#  shown. Any other column is a language.
#
#  ============ HOW A SCREEN USES IT ============
#
#      Loc.text("back")                    ->  "Back"   or  "Zurück"
#      Loc.text("greeting", "Hello")       ->  the fallback if there is no row
#      Loc.fill("hurt", {"who": "Ida"})    ->  "Ida is hurt"  from  "{who} is hurt"
#
#  A KEY THAT IS NOT IN THE FILE COMES BACK AS THE FALLBACK, or as the key
#  itself. Nothing ever shows a blank, and the Output panel lists every key
#  that was asked for and missing — so translating is a matter of reading
#  that list and adding rows.
#
#  ============ WHAT ABOUT ALL THE OTHER CSVs? ============
#
#  A card's name, a building's description, a line of dialogue — those live
#  in their own spreadsheets and are far too many to copy into this one. They
#  are translated THE SAME WAY, in place:
#
#      Name,Name.Deutsch
#      Mire Grub,Sumpfmade
#
#  Add a column with the language's name after a dot and it is used when that
#  language is on. `translated()` below is what does that lookup, and the
#  loaders call it — so the rule is the same everywhere: a dotted column is
#  the same column in another language.
#
#  ============ WHY NOT GODOT'S OWN TRANSLATION SYSTEM? ============
#
#  Because Godot's .translation importer wants CSVs shaped its way, in a
#  folder set up in Project Settings, and re-imported from the editor every
#  time you add a word. Everything else in this game is "edit a spreadsheet,
#  press F5", and the language should not be the one exception. This also
#  avoids the UID warnings you saw, which were Godot trying to import your
#  DATA csvs as translation files.
# =============================================================

const PATH := "res://data/Language.csv"
const SETTING := "language"

## Column headings that are not languages.
const NOT_A_LANGUAGE: Array[String] = ["key", "notes", "note", "comment", "context"]

static var _words: Dictionary = {}          # key -> { language -> text }
static var _languages: Array[String] = []
static var _current: String = ""
static var _missing: Dictionary = {}
static var _loaded: bool = false


# =============================================================
#  LOADING
# =============================================================

## Called once per run by MenuEscape.install(), so no screen has to remember.
static func install() -> void:
	if _loaded:
		return
	_loaded = true
	load_all()
	_current = String(GameSettings.load_all().get(SETTING, ""))
	if _current == "" or not _languages.has(_current):
		_current = _languages[0] if not _languages.is_empty() else "English"
	print("[language] %d word(s) in %d language(s). Showing %s." % [
		_words.size(), _languages.size(), _current])


static func load_all() -> void:
	_words.clear()
	_languages.clear()

	var rows := MenuSupport.read_csv(PATH)
	if rows.is_empty():
		print("[language] No %s — the game shows the words written in the code." % PATH)
		return

	# THE COLUMNS ARE THE LANGUAGES. Read from the first row, because
	# read_csv() has already normalised the headings into its keys.
	for key in (rows[0] as Dictionary).keys():
		var heading := String(key)
		if NOT_A_LANGUAGE.has(heading):
			continue
		_languages.append(heading)

	for row in rows:
		var word_key := MenuSupport.field(row, "Key").strip_edges().to_lower()
		if word_key == "":
			continue
		var by_language: Dictionary = {}
		for language in _languages:
			by_language[language] = String(row.get(language, ""))
		_words[word_key] = by_language


# =============================================================
#  ASKING FOR A WORD
# =============================================================

## The word for `key` in the language that is on.
##
## `fallback` is what you get when the key has no row at all — pass the
## English so a screen reads properly before anything has been translated.
static func text(key: String, fallback: String = "") -> String:
	install()
	var word_key := key.strip_edges().to_lower()

	var by_language: Dictionary = _words.get(word_key, {})
	if not by_language.is_empty():
		var said := String(by_language.get(_current, ""))
		if said != "":
			return said
		# The row exists but this language's cell is blank. Fall back to the
		# FIRST language rather than to nothing — a half-translated file
		# should read as half-translated, not as holes.
		if not _languages.is_empty():
			var first := String(by_language.get(_languages[0], ""))
			if first != "":
				return first

	# Nothing at all. Remember it so the report below can list it.
	_missing[word_key] = fallback if fallback != "" else key
	return fallback if fallback != "" else key


## A word with things slotted into it.
##
##     Loc.fill("knocked_out", {"who": card.player_name})
##
## with a row reading  `{who} is knocked out.`  That is how a translated
## sentence keeps its own word order — German may want the name last, and a
## sentence glued together in code cannot allow that.
static func fill(key: String, parts: Dictionary, fallback: String = "") -> String:
	var said := text(key, fallback)
	for name_of in parts.keys():
		said = said.replace("{%s}" % name_of, str(parts[name_of]))
	return said


# =============================================================
#  A DOTTED COLUMN IN ANY OTHER SPREADSHEET
# =============================================================

## Read a column from any CSV row IN THE CURRENT LANGUAGE.
##
##     Loc.translated(row, "Name")
##
## looks for `Name.Deutsch` first and falls back to `Name`. So every other
## spreadsheet in the game is translated by adding dotted columns beside the
## ones that are already there, and nothing has to be moved or duplicated.
static func translated(row: Dictionary, column: String,
		fallback: String = "") -> String:
	install()
	if _current != "":
		var dotted := MenuSupport.field(row, "%s.%s" % [column, _current], "")
		if dotted != "":
			return dotted
	return MenuSupport.field(row, column, fallback)


# =============================================================
#  SWITCHING
# =============================================================

## Every language your spreadsheet offers, in column order.
static func languages() -> Array[String]:
	install()
	if _languages.is_empty():
		return ["English"]
	return _languages


static func current() -> String:
	install()
	return _current


## Change language. Saved immediately, so it survives closing the game.
##
## The screen you are on is NOT rebuilt by this — the caller reloads it,
## because only the caller knows how. The settings screen does exactly that.
static func choose(language: String) -> void:
	install()
	if not _languages.has(language):
		push_warning("[language] '%s' is not a column in %s." % [language, PATH])
		return
	_current = language
	var settings := GameSettings.load_all()
	settings[SETTING] = language
	GameSettings.save_all(settings)
	print("[language] Now showing %s." % language)


# =============================================================
#  WHAT IS STILL TO TRANSLATE
# =============================================================

## Print every key that was asked for and had no row. This is your to-do
## list: play through a screen, read the list, add those rows.
##
## Called by ContentReport at startup, and safe to call yourself at any time.
static func report() -> void:
	if _missing.is_empty():
		return
	print("[language] %d word(s) asked for that are not in %s:"
		% [_missing.size(), PATH])
	var keys: Array = _missing.keys()
	keys.sort()
	for key in keys:
		print("    %s,%s" % [key, _missing[key]])
	print("    (those lines are ready to paste into the spreadsheet)")
