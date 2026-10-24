shader_type canvas_item;

// =============================================================
//  THE MATCH BALL'S FACE  (Anthony, 24 Oct 2026: "make the ball actually
//  roll on the field and have it actually look like a soccer ball")
//
//  A classic black-and-white patch ball (12 black pentagons, 20 white
//  hexagons) drawn in ink: a thick black outline, black seams, flat white
//  and one flat blue-grey shade at the bottom, like the drawn ball in the
//  village picture. The patches sit on a real sphere, so ball.gd can turn
//  it any way it rolls; the outline and the shade stay put, the way a
//  drawn ball would be lit.
//
//  Drawn on a square: UV 0..1 covers the ball edge to edge.
// =============================================================

// How the ball is turned. ball.gd rolls this every frame.
uniform mat3 spin = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0));
uniform vec4 ink : source_color = vec4(0.06, 0.05, 0.07, 1.0);
uniform vec4 paper : source_color = vec4(0.98, 0.97, 0.93, 1.0);
uniform vec4 shade : source_color = vec4(0.63, 0.72, 0.86, 1.0);
// Outline thickness, as a share of the ball's radius.
uniform float outline = 0.13;
// Seam thickness between the patches.
uniform float seam = 0.045;
// How shaky the ink is. 0 = ruler straight.
uniform float wobble = 0.35;

// The 12 corners of an icosahedron = the 12 black pentagons.
const float G = 1.61803399;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i + vec3(0, 0, 0)), hash(i + vec3(1, 0, 0)), f.x),
				   mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			   mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
				   mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

// Keep the best two scores seen so far, and whether the best is a pentagon.
void consider(float s, bool penta, inout float best, inout float second, inout bool best_penta) {
	if (s > best) {
		second = best;
		best = s;
		best_penta = penta;
	} else if (s > second) {
		second = s;
	}
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float aa = max(fwidth(r), 0.001) * 1.2;
	if (r > 1.0 + aa) {
		discard;
	}

	// The point on the sphere under this pixel, in the ball's own turned frame.
	vec3 view = vec3(p.x, -p.y, sqrt(max(0.0, 1.0 - r * r)));
	vec3 n = normalize(spin * view);

	// Which patch: the face of a truncated icosahedron the ray hits first.
	// Pentagon faces sit a little further out than hexagon faces (2.3274
	// against 2.2673 for edge 1), which is what gives them their size.
	float best = -10.0;
	float second = -10.0;
	bool best_penta = false;
	float kp = 1.0 / 2.32744;
	float kh = 1.0 / 2.26728;
	vec3 pent[6] = vec3[6](vec3(0.0, 1.0, G), vec3(0.0, 1.0, -G), vec3(1.0, G, 0.0),
		vec3(1.0, -G, 0.0), vec3(G, 0.0, 1.0), vec3(-G, 0.0, 1.0));
	for (int i = 0; i < 6; i++) {
		float d = dot(n, normalize(pent[i]));
		consider(d * kp, true, best, second, best_penta);
		consider(-d * kp, true, best, second, best_penta);
	}
	// The 20 hexagons = the corners of a dodecahedron.
	float ig = 1.0 / G;
	vec3 hex[10] = vec3[10](vec3(1.0, 1.0, 1.0), vec3(1.0, 1.0, -1.0), vec3(1.0, -1.0, 1.0),
		vec3(-1.0, 1.0, 1.0), vec3(ig, 0.0, G), vec3(-ig, 0.0, G), vec3(0.0, G, ig),
		vec3(0.0, G, -ig), vec3(G, ig, 0.0), vec3(G, -ig, 0.0));
	for (int i = 0; i < 10; i++) {
		float d = dot(n, normalize(hex[i]));
		consider(d * kh, false, best, second, best_penta);
		consider(-d * kh, false, best, second, best_penta);
	}

	// A hand-drawn seam is never ruler straight.
	float shake = (noise(n * 9.0) - 0.5) * wobble * seam;
	float gap = best - second;
	float gap_aa = max(fwidth(gap), 0.0005);
	float on_seam = 1.0 - smoothstep(seam * 0.12 + shake * 0.12 - gap_aa,
		seam * 0.12 + shake * 0.12 + gap_aa, gap);

	// Flat comic shade: lit from the top left, one hard step into blue-grey.
	vec3 light = normalize(vec3(-0.45, 0.6, 0.66));
	float lit = dot(view, light) + (noise(view * 6.0) - 0.5) * 0.12;
	float lit_aa = max(fwidth(lit), 0.002);
	vec3 body = mix(shade.rgb, paper.rgb, smoothstep(0.2 - lit_aa, 0.2 + lit_aa, lit));
	if (best_penta) {
		body = ink.rgb;
	}
	body = mix(body, ink.rgb, on_seam);

	// The thick outline, a little heavier at the bottom right like a brush.
	float edge = 1.0 - outline * (0.85 + 0.3 * clamp(dot(normalize(p + 0.0001), vec2(0.7, 0.7)) * 0.5 + 0.5, 0.0, 1.0));
	float ring = smoothstep(edge - aa, edge + aa, r);
	vec3 col = mix(body, ink.rgb, ring);
	float alpha = 1.0 - smoothstep(1.0 - aa, 1.0 + aa, r);
	COLOR = vec4(col, alpha * COLOR.a);
}
