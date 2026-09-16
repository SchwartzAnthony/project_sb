class_name TeamRoster
extends RefCounted

# =============================================================
#  YOUR TEAMS — saved, named, and given a badge
#
#  Until now "your team" was something you rebuilt from scratch every time
#  you pressed play. It is a THING YOU OWN now: it has a name, a badge, a
#  class and nine regulars, it lives in your save, and you pick it off a
#  shelf rather than assembling it again.
#
#  ============ WHERE IT LIVES ============
#
#  user://teams.json, beside your story save. NOT in the project folder —
#  nothing here ever writes to res://.
#
#  A team stores the NAMES of its cards, not the cards themselves. That
#  matters: edit a card's power in your unit CSV and every saved team that
#  fields it picks the change up, instead of carrying a stale copy around.
#  A card that has since been deleted is simply dropped, and the team says
#  how many it is missing rather than refusing to load.
#
#  ============ THE BADGE ============
#
#  A short name — `reeds`, `anvil`. If assets/team_icons/reeds.png exists it
#  is used; otherwise one of the built-in emblems below is drawn. So a team
#  has a badge from the first day and gets a better one when you draw it.
#  Same rule as the keeper and the unlock board.
# =============================================================

## WHERE YOUR TEAMS LIVE. A `static var` rather than a `const` because the
## save-slot screen points it at a different slot's file — see save_slots.gd,
## and the same arrangement GameState.SAVE_PATH uses.
static var SAVE_PATH := "user://teams.json"

## The drawn emblems, for a team with no artwork yet. A designer picking
## from this list is picking a SHAPE and a COLOUR, and both are visible on
## the Choose Your Team screen straight away.
const EMBLEMS: Array[String] = [
	"disc", "shield", "diamond", "chevron", "ring", "star",
	"bars", "cross", "wave", "flame", "leaf", "anvil",
]
const EMBLEM_COLOURS: Array[Color] = [
	Color(0.78, 0.42, 0.22), Color(0.34, 0.55, 0.72), Color(0.45, 0.66, 0.42),
	Color(0.70, 0.36, 0.48), Color(0.72, 0.62, 0.28), Color(0.46, 0.44, 0.68),
]

## Every team you have, newest last.
##   {"id", "name", "icon", "colour", "class", "star_tier", "cards"}
## `cards` is tier key -> Array[String] of card names.
var teams: Array[Dictionary] = []


# =============================================================
#  LOADING AND SAVING
# =============================================================

static func load_all() -> TeamRoster:
	var book := TeamRoster.new()
	if not FileAccess.file_exists(SAVE_PATH):
		return book
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return book
	var raw := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Array):
		push_warning("[teams] %s is not readable — starting with no saved teams." % SAVE_PATH)
		return book
	for entry in (parsed as Array):
		if entry is Dictionary:
			book.teams.append(_tidy(entry as Dictionary))
	return book


func save() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("[teams] Could not write %s — your teams will not be kept." % SAVE_PATH)
		return
	file.store_string(JSON.stringify(teams, "\t"))
	file.close()
	print("[teams] Saved %d team(s) to %s" % [teams.size(),
		ProjectSettings.globalize_path(SAVE_PATH)])


## Fill in anything an older save is missing, so a file written before a
## column existed still loads.
static func _tidy(entry: Dictionary) -> Dictionary:
	return {
		"id": String(entry.get("id", "")),
		"name": String(entry.get("name", "Unnamed")),
		"icon": String(entry.get("icon", "disc")),
		"colour": int(entry.get("colour", 0)),
		"class": String(entry.get("class", "")),
		"star_tier": String(entry.get("star_tier", "")),
		"cards": entry.get("cards", {}) as Dictionary,
	}


# =============================================================
#  MAKING AND CHANGING
# =============================================================

static func blank(unit_type: String, star_tier: String) -> Dictionary:
	return {
		"id": "team_%d_%d" % [Time.get_unix_time_from_system(), randi() % 1000],
		"name": "%s XI" % unit_type,
		"icon": EMBLEMS[randi() % EMBLEMS.size()],
		"colour": randi() % EMBLEM_COLOURS.size(),
		"class": unit_type,
		"star_tier": star_tier,
		"cards": {},
	}


func find(team_id: String) -> Dictionary:
	for entry in teams:
		if String(entry["id"]) == team_id:
			return entry
	return {}


## Add it, or replace the one with the same id. One call for both, so a
## screen never has to know whether it is creating or editing.
func put(entry: Dictionary) -> void:
	for i in teams.size():
		if String(teams[i]["id"]) == String(entry["id"]):
			teams[i] = entry
			return
	teams.append(entry)


func remove(team_id: String) -> void:
	for i in teams.size():
		if String(teams[i]["id"]) == team_id:
			teams.remove_at(i)
			return


# =============================================================
#  TURNING A SAVED TEAM BACK INTO CARDS
# =============================================================

## The cards a saved team fields, tier key -> Array[PlayerData].
##
## Names are matched the forgiving way the rest of the project matches
## them, so a capital letter or an underscore in your CSV does not orphan a
## saved team.
func cards_for(entry: Dictionary, db: CardDatabase) -> Dictionary:
	var out: Dictionary = {}
	if entry.is_empty() or db == null:
		return out

	var pool := db.roster_for_class(String(entry["class"]))
	var by_name: Dictionary = {}
	for card in pool:
		by_name[CardDatabase._normalise(card.player_name)] = card

	for tier in TierLadder.TIERS:
		var want: Array = (entry["cards"] as Dictionary).get(tier, [])
		var got: Array[PlayerData] = []
		for name_text in want:
			var card := by_name.get(CardDatabase._normalise(String(name_text)), null) as PlayerData
			if card != null:
				got.append(card)
		out[tier] = got
	return out


## Store the cards by NAME. See the header for why.
static func set_cards(entry: Dictionary, chosen: Dictionary) -> void:
	var names: Dictionary = {}
	for tier in chosen.keys():
		var row: Array[String] = []
		for item in (chosen[tier] as Array):
			var card := item as PlayerData
			if card != null:
				row.append(card.player_name)
		names[tier] = row
	entry["cards"] = names


## Is this team ready to take the pitch? Returns "" when it is, or a
## sentence saying what is wrong.
func trouble(entry: Dictionary, db: CardDatabase) -> String:
	if entry.is_empty():
		return "No team."
	if db == null:
		return ""
	if db.roster_for_class(String(entry["class"])).is_empty():
		return "Its class (%s) is no longer in your CSVs." % entry["class"]

	var built := cards_for(entry, db)
	var short_of: Array[String] = []
	for tier in TierLadder.TIERS:
		if tier == String(entry["star_tier"]):
			continue
		var gap := TierLadder.needs_text(built.get(tier, []), tier, db)
		if gap != "":
			short_of.append(gap)
	return "  ·  ".join(short_of)


## A one-line summary for the shelf: "Lorelei  ·  Tier IV Stars  ·  9 fielded"
func describe(entry: Dictionary, db: CardDatabase) -> String:
	var built := cards_for(entry, db)
	var n := 0
	for tier in built.keys():
		n += (built[tier] as Array).size()
	return "%s   ·   Tier %s Stars   ·   %d regular%s" % [
		entry["class"], entry["star_tier"], n, "" if n == 1 else "s"]


# =============================================================
#  THE BADGE
# =============================================================

static func colour_of(entry: Dictionary) -> Color:
	var i := int(entry.get("colour", 0))
	return EMBLEM_COLOURS[posmod(i, EMBLEM_COLOURS.size())]


## Draw one of the built-in emblems into a box. Called by the badge control
## below and by anything else that wants to draw a team without a node.
static func draw_emblem(on: CanvasItem, shape: String, tint: Color,
		box: Rect2) -> void:
	var mid := box.get_center()
	var r := minf(box.size.x, box.size.y) * 0.42
	var pale := tint.lightened(0.45)

	match shape:
		"shield":
			var pts := PackedVector2Array([
				mid + Vector2(-r, -r * 0.9), mid + Vector2(r, -r * 0.9),
				mid + Vector2(r, r * 0.25), mid + Vector2(0, r),
				mid + Vector2(-r, r * 0.25)])
			on.draw_colored_polygon(pts, tint)
		"diamond":
			on.draw_colored_polygon(PackedVector2Array([
				mid + Vector2(0, -r), mid + Vector2(r, 0),
				mid + Vector2(0, r), mid + Vector2(-r, 0)]), tint)
		"chevron":
			for k in 2:
				var y := -r * 0.5 + k * r * 0.7
				on.draw_polyline(PackedVector2Array([
					mid + Vector2(-r * 0.8, y), mid + Vector2(0, y + r * 0.55),
					mid + Vector2(r * 0.8, y)]), tint, r * 0.26)
		"ring":
			on.draw_arc(mid, r * 0.82, 0.0, TAU, 40, tint, r * 0.36, true)
		"star":
			var pts2 := PackedVector2Array()
			for i in 10:
				var rad := r if i % 2 == 0 else r * 0.45
				var a := -PI * 0.5 + float(i) * PI / 5.0
				pts2.append(mid + Vector2(cos(a), sin(a)) * rad)
			on.draw_colored_polygon(pts2, tint)
		"bars":
			for k in 3:
				on.draw_rect(Rect2(mid + Vector2(-r + k * r * 0.72, -r * 0.85),
					Vector2(r * 0.46, r * 1.7)), tint if k != 1 else pale, true)
		"cross":
			on.draw_rect(Rect2(mid + Vector2(-r * 0.24, -r), Vector2(r * 0.48, r * 2)), tint, true)
			on.draw_rect(Rect2(mid + Vector2(-r, -r * 0.24), Vector2(r * 2, r * 0.48)), tint, true)
		"wave":
			for k in 3:
				var pts3 := PackedVector2Array()
				for i in 13:
					var t := float(i) / 12.0
					pts3.append(mid + Vector2(-r + t * r * 2.0,
						-r * 0.6 + k * r * 0.62 + sin(t * TAU) * r * 0.2))
				on.draw_polyline(pts3, tint if k != 1 else pale, r * 0.16)
		"flame":
			on.draw_colored_polygon(PackedVector2Array([
				mid + Vector2(0, -r), mid + Vector2(r * 0.72, r * 0.25),
				mid + Vector2(0, r), mid + Vector2(-r * 0.72, r * 0.25)]), tint)
			on.draw_circle(mid + Vector2(0, r * 0.28), r * 0.34, pale)
		"leaf":
			on.draw_colored_polygon(PackedVector2Array([
				mid + Vector2(0, -r), mid + Vector2(r * 0.8, 0),
				mid + Vector2(0, r), mid + Vector2(-r * 0.8, 0)]), tint)
			on.draw_line(mid + Vector2(0, -r), mid + Vector2(0, r), pale, r * 0.14)
		"anvil":
			on.draw_rect(Rect2(mid + Vector2(-r, -r * 0.7), Vector2(r * 2, r * 0.6)), tint, true)
			on.draw_rect(Rect2(mid + Vector2(-r * 0.34, -r * 0.1), Vector2(r * 0.68, r * 0.7)), tint, true)
			on.draw_rect(Rect2(mid + Vector2(-r * 0.8, r * 0.6), Vector2(r * 1.6, r * 0.4)), tint, true)
		_:
			on.draw_circle(mid, r, tint)
			on.draw_arc(mid, r, 0.0, TAU, 32, pale, r * 0.18, true)


## A control that shows a team's badge — its artwork if you have drawn one,
## the built-in emblem if you have not.
static func badge(entry: Dictionary, size: float) -> Control:
	var art := MenuSupport.icon_texture(String(entry.get("icon", "")))
	if art != null:
		var rect := TextureRect.new()
		rect.texture = art
		rect.custom_minimum_size = Vector2(size, size)
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return rect

	var drawn := Control.new()
	drawn.custom_minimum_size = Vector2(size, size)
	drawn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shape := String(entry.get("icon", "disc"))
	var tint := colour_of(entry)
	drawn.draw.connect(func() -> void:
		draw_emblem(drawn, shape, tint, Rect2(Vector2.ZERO, drawn.size)))
	return drawn


# =============================================================
#  CARRYING THE CHOSEN TEAM INTO A MATCH
# =============================================================

## Turn a saved team into the TeamSelection the match already understands,
## so nothing downstream had to change.
func to_selection(entry: Dictionary, db: CardDatabase) -> TeamSelection:
	var pick := TeamSelection.new()
	if entry.is_empty() or db == null:
		return pick
	pick.unit_type = String(entry["class"])
	pick.star_tier = String(entry["star_tier"])
	pick.star_bundle = db.star_ladder_for_class(pick.unit_type)
	pick.active_star = pick.star_bundle[0] if not pick.star_bundle.is_empty() else null
	pick.regulars = cards_for(entry, db)
	pick.regulars.erase(pick.star_tier)
	return pick
