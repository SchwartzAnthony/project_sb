// CHALK WRITING (24 Oct 2026, the Brewery's chalk board): breaks words and
// lines up into chalk grain, so they read as written on a slate.
shader_type canvas_item;

// How much of the stroke is rubbed thin, 0 = solid ink, 1 = very patchy.
uniform float grain = 0.45;

float speck(vec2 at) {
	return fract(sin(dot(at, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec4 colour = texture(TEXTURE, UV) * COLOR;
	if (speck(floor(FRAGCOORD.xy)) < grain * 0.6) {
		colour.a *= 0.35;
	}
	COLOR = colour;
}
