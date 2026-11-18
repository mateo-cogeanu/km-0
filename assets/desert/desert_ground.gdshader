shader_type spatial;
// The desert floor: the biome colour from the vertices (or a flat colour),
// broken up by big soft mottling, darker grit, wind ripples, scattered
// pebbles and, here and there, a pan of cracked hardpan. Fine detail fades
// out with distance so it never shimmers.

uniform vec3 flat_color : source_color = vec3(0.67, 0.55, 0.39);
uniform float use_vertex_color = 1.0;
uniform float pebbles = 1.0;
uniform float ripples = 1.0;
uniform float cracks = 1.0;

uniform sampler2D noise_tex : hint_default_black, filter_linear_mipmap, repeat_enable;

varying vec3 world;

float hash(vec2 p) {
	p = fract(p * vec2(0.3183099, 0.3678794) + vec2(0.71, 0.113));
	p *= 17.0;
	return fract(p.x * p.y * (p.x + p.y));
}

float noise(vec2 p) {
	return texture(noise_tex, p * 0.03125).r;
}

float fbm(vec2 p) {
	return noise(p) * 0.5 + noise(p * 2.03 + 7.1) * 0.3 + noise(p * 4.1 + 3.3) * 0.2;
}

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

// Distance to the nearest edge between irregular cells: the crack network.
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
			if (d < first) {
				second = first;
				first = d;
			} else if (d < second) {
				second = d;
			}
		}
	}
	return second - first;
}

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world.xz;
	vec3 color = mix(flat_color, to_linear(COLOR.rgb), use_vertex_color);
	float footprint = length(fwidth(p));
	float fine = 1.0 - smoothstep(0.03, 0.2, footprint);
	float medium = 1.0 - smoothstep(0.3, 1.5, footprint);
	// Big soft mottling and darker grit.
	color *= 0.84 + 0.3 * fbm(p * 0.035);
	float grit = smoothstep(0.5, 0.78, noise(p * 0.22 + 4.0) * 0.7 + noise(p * 0.9) * 0.3);
	color = mix(color, color * vec3(0.8, 0.76, 0.72), grit * 0.7);
	// Pale wash where water once stood, with a crack network across it.
	float pan = smoothstep(0.66, 0.74, noise(p * 0.018 + 11.0) * 0.8 + noise(p * 0.07) * 0.2) * cracks;
	color = mix(color, color * 1.06 + vec3(0.015, 0.015, 0.012), pan * 0.5);
	if (pan > 0.001 && medium > 0.001) {
		vec2 q = p * 2.3 + vec2(noise(p * 1.7), noise(p * 1.7 + 5.0)) * 0.6;
		float edge = cell_edge(q);
		float crack = 1.0 - smoothstep(0.015, 0.05, edge);
		color *= 1.0 - crack * pan * medium * 0.22;
	}
	// Wind ripples, wavering across the sand.
	float phase = dot(p, vec2(0.55, 0.83)) * 7.0 + noise(p * 0.4) * 9.0;
	float ripple = sin(phase) * fine * ripples * (1.0 - pan) * (1.0 - grit * 0.6);
	color *= 1.0 + ripple * 0.045;
	// Pebbles and grains.
	vec2 cell = floor(p * 5.0);
	vec2 inside = fract(p * 5.0) - 0.5 - (vec2(hash(cell), hash(cell + 3.1)) - 0.5) * 0.6;
	float stone = (1.0 - smoothstep(0.04, 0.08, length(inside))) * step(0.72, hash(cell + 9.4)) * fine * pebbles;
	color = mix(color, color * (0.72 + 0.45 * hash(cell + 5.5)), stone * 0.8);
	color *= 0.94 + 0.12 * hash(floor(p * 40.0)) * fine;
	ALBEDO = color;
	ROUGHNESS = 0.97;
	SPECULAR = 0.25;
	// Ripples catch low sun.
	float slope = cos(phase) * fine * ripples * (1.0 - pan) * 0.12;
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(vec3(0.55, 0.0, 0.83) * slope, 0.0)).xyz);
}
