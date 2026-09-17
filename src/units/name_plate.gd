class_name NamePlate
extends RefCounted

# =============================================================
#  THE NAMEPLATE — one player, labelled the same way everywhere
#
#  A player is drawn in two completely different scenes: the league pitch
#  and the Adventure scroll. They were labelled differently in each, which
#  meant the same card read as two different things depending on which mode
#  you were in. This is the one description of how a player is labelled, and
#  both modes now ask it.
#
#  ============ THE SHAPE ============
#
#            Silver-Rhine Lorelei        <- the NAME, over the head, centred
#                  ,---.
#                 ( o o )                <- the artwork
#                  `-^-'
#            Tier I         P: 2         <- at the feet. Tier left, power right
#            [============    ]          <- the stamina bar, hugging them
#
#  THE BAR IS ADVENTURE ONLY. A league player has no stamina — only the
#  keeper does — so there is nothing to draw one from, and a bar under every
#  player on the pitch would be twenty-two bars saying the same thing.
#
#  ============ WHY IT MEASURES THE ARTWORK ============
#
#  A card's spritesheet frame is mostly empty. The drawn character sits
#  somewhere in the middle of it with a lot of transparent padding, and how
#  much padding differs from sheet to sheet.
#
#  Placing a label from the FRAME meant placing it from the padding — which
#  is why the stamina bar floated a long way under a player's feet and the
#  cross over a fallen one sat well above their head. Neither was wrong
#  arithmetic; both were measuring the wrong thing.
#
#  box_of() reads the frame ONCE and finds the rectangle the character
#  actually occupies. Everything is placed from that, so a label hugs the
#  drawn body whatever the padding is, and it keeps working when you replace
#  the art.
#
#  ============ TUNING ============
#
#      plate_name_size      the name over the head
#      plate_stat_size      the Tier and the Power at the feet
#      plate_gap            pixels between the body and the first label
#      plate_names          false hides every name in both modes
#      adventure_bar_gap    the stamina bar's gap under the stats
# =============================================================


## Where the drawn character actually sits inside a texture, as a fraction of
## that texture — {0,0,1,1} for art that fills its frame, something smaller
## for art with padding around it.
##
## MEASURED ONCE AND REMEMBERED on the texture itself, because reading an
## image back off the GPU is not something to do every frame.
static func box_of(texture: Texture2D) -> Rect2:
	if texture == null:
		return Rect2(0, 0, 1, 1)
	if texture.has_meta("opaque_box"):
		return texture.get_meta("opaque_box")

	var found := Rect2(0, 0, 1, 1)
	var image := texture.get_image()
	if image != null:
		if image.is_compressed():
			image.decompress()
		var used := image.get_used_rect()
		var whole := Vector2(maxf(1.0, float(image.get_width())),
			maxf(1.0, float(image.get_height())))
		if used.size.x > 0 and used.size.y > 0:
			found = Rect2(float(used.position.x) / whole.x,
				float(used.position.y) / whole.y,
				float(used.size.x) / whole.x,
				float(used.size.y) / whole.y)
	texture.set_meta("opaque_box", found)
	return found


## The four numbers a caller needs, in the caller's own coordinates.
##
##   `top`     the top of the drawn character
##   `bottom`  the bottom of it — their feet
##   `left`    / `right`  the sides of it
##
## `box` is what box_of() returned; `at` and `size` are where the artwork is
## being drawn and how big it is.
static func edges(box: Rect2, at: Vector2, size: Vector2) -> Dictionary:
	return {
		"top": at.y + box.position.y * size.y,
		"bottom": at.y + (box.position.y + box.size.y) * size.y,
		"left": at.x + box.position.x * size.x,
		"right": at.x + (box.position.x + box.size.x) * size.x,
		"middle": at.x + (box.position.x + box.size.x * 0.5) * size.x,
	}


# =============================================================
#  DRAWING IT
# =============================================================

## Draw the whole plate onto a CanvasItem, in its own coordinates.
##
##   edges     what edges() gave back
##   card      who this is
##   fraction  0 to 1 of stamina, or -1 for "this mode has no stamina"
##   down      true for a player who is out — the name greys and a cross goes
##             over the middle of them rather than over their head
##
## Called from _draw(). Nothing here decides anything; it only writes down
## what the caller already knows.
static func draw_plate(on: CanvasItem, edge: Dictionary, card: PlayerData,
		fraction: float = -1.0, down: bool = false) -> void:
	if on == null or card == null:
		return
	var db := CardDatabase.get_db()
	if db != null and not db.tune_bool("plate_names", true):
		return

	var font := ThemeDB.fallback_font
	var name_size := 13
	var stat_size := 11
	var gap := 5.0
	var widest := 150.0
	if db != null:
		name_size = db.tune_int("plate_name_size", 13)
		stat_size = db.tune_int("plate_stat_size", 11)
		gap = db.tune_float("plate_gap", 5.0)
		widest = db.tune_float("plate_width_max", 150.0)

	var top: float = edge["top"]
	var bottom: float = edge["bottom"]
	var middle: float = edge["middle"]

	var tint := MenuSupport.colour_for_tier(card.get_tier_clean())
	var ink := MenuSupport.COLOUR_TEXT if not down else Color(0.66, 0.58, 0.58)

	# ============ HOW WIDE THE PLATE IS ============
	#
	# NOT the width of the player. A drawn character is about thirty pixels
	# across and "Tier I" and "P: 2" together are ninety, so hanging one off
	# the left edge of the body and the other off the right edge put them on
	# top of each other — which is how "P: 2 III" happened.
	#
	# The plate is as wide as its CONTENTS need, centred on the body, and
	# never wider than plate_width_max. So it is the same size for every
	# player whatever their artwork, and the two stats always have room.
	var tier_text := "Tier %s%s" % [card.get_tier_clean(), " ★" if card.is_star() else ""]
	var power_text := "P: %d" % card.get_attack_power()
	var tier_wide := font.get_string_size(tier_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, stat_size).x
	var power_wide := font.get_string_size(power_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, stat_size).x
	var pad := 6.0
	var plate_wide := clampf(tier_wide + power_wide + pad * 3.0, 54.0, widest)
	var left := middle - plate_wide * 0.5
	var right := middle + plate_wide * 0.5

	# ============ THE NAME ============
	#
	# A SHORT NAME. Your cards are called "Songbound Shore Lorelei" — the
	# class is on the end of every one of them, and it is already obvious
	# from the player standing there. Dropping it turns twenty-three
	# characters into fifteen, which is the difference between eleven names
	# over eleven players being readable and being a smear.
	#
	# The full name is still on the card, in the log and in the team builder.
	# AND NO WIDER THAN THE WINDOW UNDER IT. A name allowed to run to
	# plate_width_max is half as wide again as the Tier/Power window, so in a
	# crowd the names collide while the windows underneath them sit neatly
	# side by side — which is how "Twilight Lorelei of the Deep River" ended up
	# written across the player next to them.
	#
	# Tying the name to the window makes every player's label exactly one
	# width, which is the whole point of having a plate at all.
	var name_room := plate_wide
	if db != null:
		name_room = plate_wide * maxf(0.5, db.tune_float("plate_name_width", 1.0))
	var label := short_name(card)
	var name_wide := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, name_size).x
	while name_wide > name_room and label.length() > 4:
		label = label.substr(0, label.length() - 2) + "…"
		name_wide = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, name_size).x
	_shadowed(on, font, Vector2(middle - name_wide * 0.5, top - gap), label,
		name_size, ink)

	# ============ THE LITTLE WINDOW AT THEIR FEET ============
	#
	# Tier on the left, Power on the right, and in Adventure the stamina bar
	# underneath them — all on one dark panel so it reads as a label rather
	# than as text floating on the grass.
	var line_high := float(stat_size) + 4.0
	var bar_high := 0.0
	var bar_gap := 3.0
	if fraction >= 0.0:
		bar_high = maxf(4.0, float(stat_size) * 0.42)
		if db != null:
			bar_gap = db.tune_float("adventure_bar_gap", 3.0)

	var panel_top := bottom + gap
	var panel_high := line_high + (bar_high + bar_gap if fraction >= 0.0 else 0.0) + 4.0
	var panel := Rect2(Vector2(left, panel_top), Vector2(plate_wide, panel_high))
	on.draw_rect(panel, Color(0.06, 0.07, 0.10, 0.78), true)
	on.draw_rect(panel, Color(tint.r, tint.g, tint.b, 0.55 if not down else 0.25), false, 1.0)

	var text_y := panel_top + float(stat_size) + 1.0
	_shadowed(on, font, Vector2(left + pad, text_y), tier_text, stat_size,
		tint.lightened(0.35) if not down else ink)
	_shadowed(on, font, Vector2(right - pad - power_wide, text_y), power_text,
		stat_size, MenuSupport.COLOUR_ACCENT if not down else ink)

	# --- the stamina bar, hugging the stats from below ---
	if fraction < 0.0:
		return
	var bar := Rect2(Vector2(left + pad, text_y + bar_gap),
		Vector2(plate_wide - pad * 2.0, bar_high))
	on.draw_rect(bar, Color(0.10, 0.11, 0.14, 0.95), true)
	if not down and fraction > 0.0:
		var filled := bar
		filled.size.x = bar.size.x * clampf(fraction, 0.0, 1.0)
		# Green, amber, red. Read at a glance, no numbers.
		var colour := Color(0.45, 0.78, 0.45)
		if fraction < 0.34:
			colour = Color(0.85, 0.35, 0.32)
		elif fraction < 0.67:
			colour = Color(0.88, 0.68, 0.32)
		on.draw_rect(filled, colour, true)


## A card's name with the class taken off the end of it.
##
## "Songbound Shore Lorelei" -> "Songbound Shore". The class is on the end of
## every card in a set and it is already obvious from who is standing there,
## so on the pitch it is eight wasted characters per player.
##
## A name that IS just the class is left alone, and so is one that does not
## end in it — nothing is ever reduced to nothing.
static func short_name(card: PlayerData) -> String:
	if card == null:
		return ""
	var full := card.player_name.strip_edges()
	var klass := card.unit_type.strip_edges()
	if klass == "" or full.to_lower() == klass.to_lower():
		return full
	if full.to_lower().ends_with(" " + klass.to_lower()):
		var cut := full.substr(0, full.length() - klass.length() - 1).strip_edges()
		if cut != "":
			return cut
	return full


## A cross over a fallen player, centred on the middle of their body.
##
## Separate from draw_plate() because a player who is lying down has a
## different middle from one who is standing, and only the caller knows
## which they are.
static func draw_down_mark(on: CanvasItem, middle: Vector2, span: float) -> void:
	var dead := Color(0.90, 0.38, 0.36)
	on.draw_line(middle + Vector2(-span, -span), middle + Vector2(span, span), dead, 3.0)
	on.draw_line(middle + Vector2(-span, span), middle + Vector2(span, -span), dead, 3.0)


## Text with a dark edge behind it, so a name stays readable over grass,
## over a white shirt, and over a background you have not drawn yet.
static func _shadowed(on: CanvasItem, font: Font, at: Vector2, text: String,
		size: int, colour: Color) -> void:
	var shade := Color(0, 0, 0, 0.55)
	for step in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		on.draw_string(font, at + step, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
			size, shade)
	on.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, colour)
