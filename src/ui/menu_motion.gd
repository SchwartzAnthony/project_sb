class_name MenuMotion
extends Node

# =============================================================
#  THINGS THAT MOVE ON THE TITLE SCREEN  (round AN)
#
#  data/MainMenu.csv, column Motion, with its numbers in Motion Settings
#  written as  name=value; name=value  (anything left out keeps its default).
#
#    drift   a layer slides sideways for ever and wraps round seamlessly
#            (the clouds).   speed = pixels a second (of the picture)
#    sway    a layer waves like cloth hanging from one edge (the maypole
#            ribbons). The free end moves most, the tied end not at all.
#            amount = pixels at the free end   speed = waves a second
#            from = top / bottom (the tied edge)   reach = how many pixels
#            from that edge the ribbons hang   wave = how stretched the
#            ripple is (bigger = calmer; minus = it runs the other way)
#            phase = start the wave later   curve = 1 = straight, more =
#            only the very end moves
#    swing   a picture swings round the top-middle of itself (the sign on
#            its ropes).   amount = degrees each way   speed = swings a second
#    bird    a picture strip of 3 poses (wings up | wings down | sitting)
#            flies in, sits at X / Y, then flies off, once.
#            delay = seconds before it comes   fly = seconds to land
#            stay = seconds it sits   leave = seconds to fly off
#            from = x,y where it starts   to = x,y where it flies off to
#            flap = wing beats a second   arc = how high it swoops
#            sync = music: ROUND AN (Anthony) - no timer. The bird follows
#            the menu song instead, and comes back every time the song
#            loops, landing at `land` = seconds into the song, at the same
#            beat each time. Delay is ignored then. With the sound off (or
#            no song playing) it falls back to the timer and flies once.
#    follow  (title row only) the title is written on the picture just
#            above it in the list and moves with it.
# =============================================================

const DRIFT := """
shader_type canvas_item;
uniform float speed = 30.0;
void fragment() {
	vec2 uv = UV;
	uv.x += TIME * speed * TEXTURE_PIXEL_SIZE.x;
	COLOR = texture(TEXTURE, uv);
}
"""

const SWAY := """
shader_type canvas_item;
uniform float amount = 10.0;
uniform float speed = 0.5;
uniform float reach = 260.0;
uniform float wave = -170.0;
uniform float phase = 0.0;
uniform float curve = 1.3;
uniform bool from_bottom = false;
void fragment() {
	float h = 1.0 / TEXTURE_PIXEL_SIZE.y;
	float d = from_bottom ? (1.0 - UV.y) * h : UV.y * h;
	float k = d <= reach ? pow(d / reach, curve) : 0.0;
	float dx = floor(amount * k * sin(6.2831853 * speed * TIME + phase + d / wave) + 0.5);
	COLOR = texture(TEXTURE, UV - vec2(dx * TEXTURE_PIXEL_SIZE.x, 0.0));
}
"""

var kind := ""
var settings: Dictionary = {}
var art: Control
var atlas: AtlasTexture
var sheet: Texture2D
var frame_w := 0.0
var home := Vector2.ZERO
var t := 0.0


## "speed=30; from=top" -> {"speed": "30", "from": "top"}
static func parse_settings(text: String) -> Dictionary:
	var out := {}
	for part in text.split(";", false):
		var eq := part.find("=")
		if eq > 0:
			out[part.substr(0, eq).strip_edges().to_lower()] = part.substr(eq + 1).strip_edges()
	return out


static func number(values: Dictionary, key: String, fallback: float) -> float:
	var text := String(values.get(key, ""))
	return float(text) if text.is_valid_float() else fallback


static func point(values: Dictionary, key: String, fallback: Vector2) -> Vector2:
	var parts := String(values.get(key, "")).split(",")
	if parts.size() != 2 or not parts[0].strip_edges().is_valid_float() or not parts[1].strip_edges().is_valid_float():
		return fallback
	return Vector2(float(parts[0]), float(parts[1]))


## Layers (whole-screen pictures): drift and sway are shaders, so they cost
## nothing per frame.
static func apply_to_layer(layer: TextureRect, motion: String, values: Dictionary) -> void:
	match motion:
		"":
			return
		"drift":
			var mat := ShaderMaterial.new()
			mat.shader = Shader.new()
			mat.shader.code = DRIFT
			mat.set_shader_parameter("speed", number(values, "speed", 30.0))
			layer.material = mat
			layer.texture_repeat = CanvasItem.TEXTURE_REPEAT_MIRROR
		"sway":
			var mat := ShaderMaterial.new()
			mat.shader = Shader.new()
			mat.shader.code = SWAY
			var bottom := String(values.get("from", "top")).to_lower() == "bottom"
			mat.set_shader_parameter("amount", number(values, "amount", 10.0))
			mat.set_shader_parameter("speed", number(values, "speed", 0.5))
			mat.set_shader_parameter("reach", number(values, "reach", 260.0))
			mat.set_shader_parameter("wave", number(values, "wave", 200.0 if bottom else -170.0))
			mat.set_shader_parameter("phase", number(values, "phase", 0.0))
			mat.set_shader_parameter("curve", number(values, "curve", 1.0 if bottom else 1.3))
			mat.set_shader_parameter("from_bottom", bottom)
			layer.material = mat
		_:
			print("[menu] MainMenu.csv: a layer cannot '%s' - use drift or sway." % motion)


## Pictures: swing and bird move the picture itself every frame.
static func apply_to_picture(picture: TextureRect, frames_atlas: AtlasTexture, strip: Texture2D,
		frames: int, motion: String, values: Dictionary) -> void:
	if motion != "swing" and motion != "bird":
		print("[menu] MainMenu.csv: a picture cannot '%s' - use swing or bird." % motion)
		return
	var mover := MenuMotion.new()
	mover.kind = motion
	mover.settings = values
	mover.art = picture
	mover.atlas = frames_atlas
	mover.sheet = strip
	mover.frame_w = float(strip.get_width()) / float(maxi(1, frames))
	mover.home = picture.position
	picture.add_child(mover)
	if motion == "swing":
		picture.pivot_offset = Vector2(picture.size.x * 0.5, 0.0)
	else:
		picture.visible = false


func _process(delta: float) -> void:
	t += delta
	if kind == "swing":
		var amount := deg_to_rad(number(settings, "amount", 2.5))
		art.rotation = amount * sin(TAU * number(settings, "speed", 0.5) * t)
	elif kind == "bird":
		_bird()


func _pose(i: int) -> void:
	atlas.region = Rect2(frame_w * i, 0, frame_w, sheet.get_height())


func _bird() -> void:
	var delay := number(settings, "delay", 3.0)
	var fly := maxf(0.1, number(settings, "fly", 2.0))
	var stay := number(settings, "stay", 5.0)
	var leave := maxf(0.1, number(settings, "leave", 2.0))
	var flap := number(settings, "flap", 10.0)
	var arc := number(settings, "arc", 55.0)
	var start := point(settings, "from", Vector2(-160, 260))
	var finish := point(settings, "to", Vector2(2100, 80))
	var half := art.size * 0.5
	var beat := int(t * flap) % 2
	# THE SONG IS THE CLOCK (sync=music). The bird's own clock is worked out
	# from where the song is, so it takes off `fly` seconds before `land`
	# and the whole visit repeats with every loop of the song. Coming back
	# from Settings mid-song, it is simply wherever the song says it is.
	var clock := t
	var synced := String(settings.get("sync", "")).to_lower() == "music"
	if synced:
		var song := AudioDirector.song_time(get_tree())
		if song.y > 0.0:
			var land := number(settings, "land", delay + fly)
			clock = fposmod(song.x - (land - fly), song.y)
			delay = 0.0
	if clock < delay:
		art.visible = false
	elif clock < delay + fly:
		var u := (clock - delay) / fly
		u = 1.0 - (1.0 - u) * (1.0 - u)
		var at := (start + half).lerp(home + half, u) - Vector2(0, arc * sin(PI * u))
		art.visible = true
		art.position = at - half
		_pose(2 if u > 0.92 else beat)
	elif clock < delay + fly + stay:
		art.visible = true
		art.position = home
		_pose(2)
	elif clock < delay + fly + stay + leave:
		var u := pow((clock - delay - fly - stay) / leave, 1.4)
		art.visible = true
		art.position = (home + half).lerp(finish + half, u) - half
		_pose(beat)
	else:
		art.visible = false
		# A synced bird waits for the song to come round again.
		if not synced:
			set_process(false)
