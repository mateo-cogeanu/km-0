shader_type spatial;
render_mode cull_disabled;
// The ear membranes: thin, dark, veined skin. Lit from in front they are
// almost black; with light behind them they glow the red of blood.

varying vec3 skin_position;

float hash_point(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.27, 0.43));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float skin_noise(vec3 p) {
	vec3 cell = floor(p);
	vec3 t = fract(p);
	t = t * t * (3.0 - 2.0 * t);
	return mix(
		mix(mix(hash_point(cell), hash_point(cell + vec3(1,0,0)), t.x),
			mix(hash_point(cell + vec3(0,1,0)), hash_point(cell + vec3(1,1,0)), t.x), t.y),
		mix(mix(hash_point(cell + vec3(0,0,1)), hash_point(cell + vec3(1,0,1)), t.x),
			mix(hash_point(cell + vec3(0,1,1)), hash_point(cell + vec3(1,1,1)), t.x), t.y), t.z);
}

void vertex() {
	skin_position = VERTEX;
}

void fragment() {
	// Fine branching veins: two scales of thin ridges in the noise.
	float big = 1.0 - abs(skin_noise(skin_position * vec3(9.0, 30.0, 9.0)) * 2.0 - 1.0);
	float fine = 1.0 - abs(skin_noise(skin_position * 55.0 + vec3(2.3)) * 2.0 - 1.0);
	float vein = max(smoothstep(0.955, 0.99, big), smoothstep(0.97, 0.995, fine) * 0.6);
	float mottle = skin_noise(skin_position * 11.0);
	ALBEDO = mix(vec3(0.075, 0.04, 0.035), vec3(0.025, 0.008, 0.01), vein * 0.85) * (0.8 + 0.4 * mottle);
	ROUGHNESS = 0.38;
	SPECULAR = 0.35;
	BACKLIGHT = mix(vec3(0.3, 0.06, 0.035), vec3(0.05, 0.0, 0.0), vein) * (0.7 + 0.5 * mottle);
	ALPHA = 0.9 - 0.15 * mottle;
}
