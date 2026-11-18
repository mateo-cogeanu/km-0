shader_type spatial;
render_mode cull_disabled;
// The ear membranes: thin, veined skin you can almost see light through.

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
	float vein = smoothstep(0.9, 0.98, 1.0 - abs(skin_noise(skin_position * 18.0) * 2.0 - 1.0));
	float mottle = skin_noise(skin_position * 7.0);
	ALBEDO = mix(vec3(0.36, 0.25, 0.24), vec3(0.18, 0.08, 0.1), vein * 0.8) * (0.85 + 0.3 * mottle);
	ROUGHNESS = 0.3;
	SPECULAR = 0.5;
	BACKLIGHT = vec3(0.45, 0.16, 0.12);
	ALPHA = 0.9 - 0.15 * mottle;
}
