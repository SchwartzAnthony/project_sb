shader_type canvas_item;
// THE ENEMY EMBLEM (Anthony, 23 Oct 2026: "Have the enemy emblem be red").
// Turns the blue of the beer mat panel red and leaves the cream alone.
uniform vec3 red = vec3(0.72, 0.12, 0.10);

void fragment() {
	vec4 c = COLOR;
	float blue = clamp((c.b - max(c.r, c.g)) * 4.0, 0.0, 1.0);
	float dark = 1.0 - c.b;
	vec3 swapped = red * (0.55 + 0.45 * (1.0 - dark)) * 1.15;
	COLOR = vec4(mix(c.rgb, swapped, blue), c.a);
}
