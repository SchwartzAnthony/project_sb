class_name SeasonBook
extends RefCounted

# =============================================================
#  THE COMPETITIONS — every season you can enter
#
#  THE SEASON used to be one fixture list and nothing else. Now it is a
#  SHELF of competitions — a picture each, most of them locked — and the
#  table you already had is what opens when you click one.
#
#  ============ res://data/Seasons.csv ============
#
#      ID           the short word. Season.csv fixtures name it in their
#                   own Season column, which is what says which fixtures
#                   belong to which competition
#      Name         what it is called on the shelf
#      Art          a picture, from assets/seasons/ — a drawn crest is used
#                   until you have one
#      Colour       #rrggbb, for the crest and the tile's edge
#      Requires     the usual condition language. unlocked:X, flag:y,
#                   count:z>=3. Blank = always open
#      Row, Column  where its tile sits on the shelf. THIS IS THE TALENT
#                   TREE PART — put two seasons on the same row and they sit
#                   side by side; put one on row 2 under another and a line
#                   is drawn between them
#      After        the ID of the season this one follows. Draws the joining
#                   line, and is only decoration — Requires is what actually
#                   locks it
#      Matches      how many fixtures it has, for the tile. Leave blank and
#                   it is counted from Season.csv
#      Description  yours, shown under the name
#
#  ADD A ROW, GET A SEASON. Add ten rows and you have ten, laid out however
#  your Row and Column columns say. There is no limit and no code to touch.
#
#  ============ WHICH ONE IS BEING PLAYED ============
#
#  One value in your save. Picking a season sets it; the fixture loader
#  reads it and keeps only that season's fixtures. So the table, the league
#  position and the final all work exactly as they did — they simply have
#  fewer fixtures in front of them.
# =============================================================

const PATH := "res://data/Seasons.csv"
const CHOSEN := "chosen_season"

static var _instance: SeasonBook

## Each: id, name, art, colour, requires, row, column, after, matches,
##       description
var seasons: Array[Dictionary] = []
var problems: Array[String] = []


static func get_db() -> SeasonBook:
	if _instance == null:
		_instance = SeasonBook.new()
		_instance.load_all()
	return _instance


## Not called reload() — see the note on any of the other loaders for why.
static func reload_files() -> void:
	_instance = null
	get_db()


func load_all() -> void:
	seasons.clear()
	problems.clear()

	var rows := MenuSupport.read_csv(PATH)
	if rows.is_empty():
		# NO FILE IS NOT AN ERROR. A project that has never heard of multiple
		# seasons gets one called "The Season" holding every fixture, which
		# is exactly how the game behaved before this file existed.
		seasons.append({
			"id": "season_one", "name": "The Season", "art": "",
			"colour": Color(0.45, 0.62, 0.78), "requires": "",
			"row": 0, "column": 0, "after": "", "matches": 0,
			"description": "Every fixture in Season.csv.",
		})
		return

	for row in rows:
		var id_text := MenuSupport.field(row, "ID")
		if id_text == "":
			continue
		seasons.append({
			"id": id_text,
			"name": Loc.translated(row, "Name", id_text),
			"art": MenuSupport.field(row, "Art"),
			"colour": _colour(MenuSupport.field(row, "Colour"),
				Color(0.45, 0.62, 0.78)),
			"requires": MenuSupport.field(row, "Requires"),
			"row": int(MenuSupport.field_float(row, "Row", 0.0)),
			"column": int(MenuSupport.field_float(row, "Column", 0.0)),
			"after": MenuSupport.field(row, "After"),
			"matches": int(MenuSupport.field_float(row, "Matches", 0.0)),
			"description": Loc.translated(row, "Description"),
		})

	_validate()
	print("[seasons] %d competition(s) loaded." % seasons.size())


func _validate() -> void:
	var seen: Dictionary = {}
	for entry in seasons:
		var key := CardDatabase._normalise(String(entry["id"]))
		if seen.has(key):
			problems.append("Seasons.csv has two seasons called '%s'." % entry["id"])
		seen[key] = true

	for entry in seasons:
		var after := String(entry["after"]).strip_edges()
		if after != "" and not seen.has(CardDatabase._normalise(after)):
			problems.append("Seasons.csv: '%s' says it comes After '%s', which is not a season."
				% [entry["id"], after])

	for note in problems:
		push_warning("[seasons] " + note)


# =============================================================
#  WHICH ONE IS ON
# =============================================================

## The season being played. Empty only when there are none at all.
static func chosen_id() -> String:
	var state := GameState.fetch(Engine.get_main_loop() as SceneTree)
	if state == null:
		return first_id()
	var picked := state.text(CHOSEN, "")
	if picked != "" and get_db().find(picked).has("id"):
		return picked
	return first_id()


static func first_id() -> String:
	var book := get_db()
	if book.seasons.is_empty():
		return ""
	return String(book.seasons[0]["id"])


## Start playing a competition. The fixture list is re-read, because it only
## holds the chosen season's fixtures.
static func choose(state: GameState, season_id: String) -> void:
	if state == null:
		return
	state.set_text(CHOSEN, season_id)
	state.save_to_disk()
	SeasonDB.reload_files()
	print("[seasons] Now playing '%s'." % season_id)


func find(season_id: String) -> Dictionary:
	var key := CardDatabase._normalise(season_id)
	for entry in seasons:
		if CardDatabase._normalise(String(entry["id"])) == key:
			return entry
	return {}


# =============================================================
#  LOCKED OR OPEN
# =============================================================

## "" when it can be played, or a sentence saying what is missing.
static func locked_reason(entry: Dictionary, state: GameState) -> String:
	var needs := String(entry.get("requires", "")).strip_edges()
	if needs == "":
		return ""
	if DialogueGrammar.test(needs, state):
		return ""
	return DialogueGrammar.describe(needs)


## How many fixtures a season has. The Matches column if it has one,
## otherwise counted out of Season.csv — so the tile is right without you
## having to keep two numbers in step.
static func match_count(entry: Dictionary) -> int:
	var said := int(entry.get("matches", 0))
	if said > 0:
		return said

	var want := CardDatabase._normalise(String(entry.get("id", "")))
	var first := CardDatabase._normalise(first_id())
	var n := 0
	for row in MenuSupport.read_csv("res://data/Season.csv"):
		if MenuSupport.field(row, "Opponent") == "":
			continue
		var belongs := CardDatabase._normalise(MenuSupport.field(row, "Season"))
		if belongs == "":
			belongs = first
		if belongs == want:
			n += 1
	return n


# =============================================================
#  THE CREST
#
#  Drawn in code until you have art, the same deal the team badges and the
#  keeper get. A season is a shield with its initial in it, in its own
#  colour, so a shelf of eight is readable on the first day.
# =============================================================

static func draw_crest(on: CanvasItem, entry: Dictionary, box: Rect2,
		lit: bool) -> void:
	var tint: Color = entry.get("colour", Color(0.45, 0.62, 0.78))
	if not lit:
		tint = tint.darkened(0.55)
	var mid := box.get_center()
	var r := minf(box.size.x, box.size.y) * 0.40

	var points := PackedVector2Array([
		mid + Vector2(-r, -r * 0.95), mid + Vector2(r, -r * 0.95),
		mid + Vector2(r, r * 0.20), mid + Vector2(0, r),
		mid + Vector2(-r, r * 0.20)])
	on.draw_colored_polygon(points, tint)
	on.draw_polyline(points + PackedVector2Array([points[0]]),
		tint.lightened(0.4), 2.5)

	var letter := String(entry.get("name", "?")).strip_edges().substr(0, 1).to_upper()
	var font := ThemeDB.fallback_font
	var size := int(r * 1.1)
	var width := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
	on.draw_string(font, mid + Vector2(-width * 0.5, size * 0.34), letter,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, size,
		Color(0.06, 0.06, 0.09) if lit else Color(0.2, 0.2, 0.24))


static func _colour(text: String, fallback: Color) -> Color:
	var clean := text.strip_edges()
	if clean == "":
		return fallback
	if not clean.begins_with("#"):
		clean = "#" + clean
	if not Color.html_is_valid(clean):
		push_warning("[seasons] '%s' is not a colour. Write it as #rrggbb." % text)
		return fallback
	return Color.html(clean)
