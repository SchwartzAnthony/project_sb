// ROUND AN: the isometric players on the pitch. `saturation` 1 = full
// colour, 0 = grey. Players outside the Play Maker session are drawn grey
// (Tuning.csv pitch_sprite_rest_saturation), so the eye follows the play.
shader_type canvas_item;

uniform float saturation : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float grey = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(mix(vec3(grey), c.rgb, saturation), c.a);
}
