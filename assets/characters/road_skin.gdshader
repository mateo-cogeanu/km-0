shader_type spatial;

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
	float cloud = 0.69 * skin_noise(skin_position * 7.5) + 0.31 * skin_noise(skin_position * 21.0);
	// Keep the mottling faint so the whole body reads as one even, pale skin.
	float patches = smoothstep(0.2, 0.8, cloud);
	ALBEDO = mix(vec3(0.40, 0.34, 0.31), vec3(0.50, 0.43, 0.39), patches);
	ROUGHNESS = mix(0.8, 0.72, patches);
	SPECULAR = 0.26;

	// Surface gradients add pores without relying on UVs or changing the silhouette.
	float height = skin_noise(skin_position * 70.0) * 0.00025;
	vec3 dx = dFdx(VERTEX);
	vec3 dy = dFdy(VERTEX);
	vec3 across = cross(dy, NORMAL);
	vec3 along = cross(NORMAL, dx);
	float determinant = dot(dx, across);
	vec3 gradient = (dFdx(height) * across + dFdy(height) * along);
	NORMAL = normalize(NORMAL - gradient * sign(determinant) / max(abs(determinant), 0.0000001));
}
