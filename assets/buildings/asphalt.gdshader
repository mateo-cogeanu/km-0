shader_type spatial;
// Old two-lane blacktop baked by the sun: faded to grey, aggregate showing
// through, wheel tracks polished paler, oil down the middle of each lane,
// cracks (a long one at the centre joint, a mesh of them towards the edges),
// black tar patches, and sand blown over the edges.

uniform sampler2D noise_tex : hint_default_black, filter_linear_mipmap, repeat_enable;

varying vec3 world_point;

float hash(vec2 p) {
	p = fract(p * vec2(0.3183099, 0.3678794) + vec2(0.71, 0.113));
	p *= 17.0;
	return fract(p.x * p.y * (p.x + p.y));
}

float noise(vec2 p) {
	return texture(noise_tex, p * 0.03125).r;
}

float cell_edge(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float first = 8.0;
	float second = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(hash(i + g), hash(i + g + 19.7));
			float d = length(g + o - f);
			if (d < first) { second = first; first = d; } else if (d < second) { second = d; }
		}
	}
	return second - first;
}

void vertex() {
	world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_point.xz;
	float across = (UV.x - 0.5) * 6.8;
	float along = UV.y;
	float footprint = length(fwidth(p));
	float fine = 1.0 - smoothstep(0.02, 0.12, footprint);
	float medium = 1.0 - smoothstep(0.15, 0.8, footprint);
	float lane = abs(abs(UV.x - 0.5) - 0.25) * 4.0;
	float wheel_wear = smoothstep(0.16, 0.32, lane) * (1.0 - smoothstep(0.39, 0.56, lane));
	vec3 pavement = mix(vec3(0.095, 0.091, 0.085), vec3(0.125, 0.119, 0.11), wheel_wear);
	pavement *= 0.9 + 0.2 * noise(p * vec2(0.4, 0.08));
	// Aggregate.
	float grain = hash(floor(p * 55.0));
	pavement *= 1.0 + (grain - 0.5) * 0.35 * fine;
	pavement = mix(pavement, vec3(0.24, 0.22, 0.2), step(0.93, grain) * fine * 0.6);
	// Oil down the middle of each lane.
	float lane_middle = abs(abs(across) - 1.7);
	float oil = exp(-lane_middle * lane_middle / 0.08) * (0.5 + 0.5 * noise(vec2(along * 0.3, across)));
	pavement *= 1.0 - oil * 0.3;
	// Tar patches, here and there.
	float block = floor(along / 9.0);
	float patch_on = step(0.72, hash(vec2(block, 3.0)));
	float patch_x = (hash(vec2(block, 5.0)) - 0.5) * 4.0;
	float patch_w = 0.6 + hash(vec2(block, 7.0)) * 1.4;
	float in_patch = patch_on * step(abs(across - patch_x), patch_w) * step(abs(fract(along / 9.0) - 0.5) * 9.0, 1.2 + hash(vec2(block, 9.0)) * 2.0);
	pavement = mix(pavement, vec3(0.045, 0.043, 0.04), in_patch * 0.9);
	// Cracks: the centre joint, and a mesh towards the crumbling edges.
	float joint = 1.0 - smoothstep(0.01, 0.035, abs(across + (noise(vec2(along * 0.15, 1.0)) - 0.5) * 0.3));
	float edge_zone = smoothstep(2.4, 3.3, abs(across));
	float mesh = 0.0;
	if (edge_zone > 0.001 && medium > 0.001) {
		mesh = (1.0 - smoothstep(0.02, 0.06, cell_edge(p * 1.4))) * edge_zone;
	}
	float long_crack = (1.0 - smoothstep(0.01, 0.03, abs(fract(across * 0.37 + noise(vec2(along * 0.07, 2.0)) * 1.5) - 0.5))) * step(0.6, noise(vec2(along * 0.05, across)));
	float crack = max(max(joint * 0.8, mesh), long_crack * 0.7) * medium * (1.0 - in_patch);
	pavement = mix(pavement, vec3(0.03, 0.028, 0.026), crack * 0.85);
	// Sand blown over the edges, in drifts.
	float edge_dust = smoothstep(0.38 - noise(vec2(along * 0.2, 0.0)) * 0.08, 0.51, abs(UV.x - 0.5));
	float drift = smoothstep(0.55, 0.85, noise(p * vec2(0.6, 0.15))) * 0.4;
	ALBEDO = mix(pavement, vec3(0.42, 0.33, 0.23), clamp(edge_dust * 0.75 + drift * edge_zone, 0.0, 1.0));
	ROUGHNESS = mix(0.92, 0.7, in_patch + oil * 0.3);
	SPECULAR = 0.35;
}
