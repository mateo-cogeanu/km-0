shader_type spatial;
// The Listener's skin: pale, wet and drowned-looking. Grey-green mottling,
// darker along the back where algae and silt have settled, a paler belly,
// scars, and a wet sheen. Detail comes from noise in model space, so it
// needs no UVs.

varying vec3 skin_position;
varying vec3 skin_normal;

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
	skin_normal = NORMAL;
}

void fragment() {
	vec3 p = skin_position;
	float cloud = 0.6 * skin_noise(p * 4.0) + 0.4 * skin_noise(p * 13.0);
	float patches = smoothstep(0.25, 0.75, cloud);
	vec3 pale = mix(vec3(0.34, 0.35, 0.31), vec3(0.45, 0.45, 0.4), patches);
	// The back: darker, greener, where it lies just under the water.
	float back = smoothstep(-0.1, 0.6, skin_normal.y);
	float algae = smoothstep(0.45, 0.7, skin_noise(p * 6.0 + vec3(4.0))) * back;
	vec3 skin = mix(pale, vec3(0.3, 0.33, 0.26), back * 0.55);
	skin = mix(skin, vec3(0.2, 0.26, 0.15), algae * 0.6);
	// The belly: paler, almost white.
	float belly = smoothstep(-0.2, -0.75, skin_normal.y);
	skin = mix(skin, vec3(0.58, 0.56, 0.5), belly * 0.6);
	// Old scars: thin pale streaks.
	float scar = smoothstep(0.965, 0.99, 1.0 - abs(skin_noise(p * vec3(2.0, 9.0, 2.0) + vec3(1.7)) * 2.0 - 1.0));
	skin = mix(skin, vec3(0.75, 0.66, 0.62), scar * 0.5);
	// Dark veins under the thin skin.
	float vein = smoothstep(0.94, 0.985, 1.0 - abs(skin_noise(p * 14.0 + vec3(3.1)) * 2.0 - 1.0));
	skin = mix(skin, vec3(0.22, 0.24, 0.3), vein * 0.45 * (1.0 - back * 0.5));
	ALBEDO = skin;
	// Wet: glossy, glossier still in the hollows where water sits.
	float wet = 0.65 + 0.35 * skin_noise(p * 9.0);
	ROUGHNESS = mix(0.55, 0.28, wet) + algae * 0.25;
	SPECULAR = 0.42;
	// Pitted, wrinkled surface.
	float height = skin_noise(p * 55.0) * 0.0006 + skin_noise(p * vec3(160.0, 40.0, 160.0)) * 0.00025;
	vec3 dx = dFdx(VERTEX);
	vec3 dy = dFdy(VERTEX);
	vec3 across = cross(dy, NORMAL);
	vec3 along = cross(NORMAL, dx);
	float determinant = dot(dx, across);
	vec3 gradient = (dFdx(height) * across + dFdy(height) * along);
	NORMAL = normalize(NORMAL - gradient * sign(determinant) / max(abs(determinant), 0.0000001));
}
