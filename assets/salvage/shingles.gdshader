shader_type spatial;
// Asphalt shingles, faded and patched with moss and lichen.

varying vec3 world;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.27, 0.43));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x), mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x), mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float tab = hash(floor(world * vec3(3.0, 5.5, 3.0)));
	vec3 color = mix(vec3(0.11, 0.105, 0.1), vec3(0.2, 0.19, 0.18), tab);
	float moss = smoothstep(0.55, 0.75, noise(world * 1.3) * 0.7 + noise(world * 6.0) * 0.3);
	color = mix(color, vec3(0.2, 0.25, 0.12), moss * 0.8);
	float lichen = smoothstep(0.82, 0.9, noise(world * 9.0 + vec3(5.0)));
	color = mix(color, vec3(0.55, 0.55, 0.45), lichen * 0.5);
	ALBEDO = color;
	ROUGHNESS = 0.92;
}
