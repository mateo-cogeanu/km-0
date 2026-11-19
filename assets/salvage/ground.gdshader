shader_type spatial;
// The ground of Marrow, by kind: 0 asphalt (cracked, silted, patched),
// 1 pavement (concrete slabs with joints), 2 mud (the banks), 3 grass and
// scrub (the ridge and the hills round the valley, with rock where it is
// steep). Everything in world space, so it needs no UVs.

uniform int kind = 0;
uniform float water_y = -5.2;

varying vec3 world;
varying vec3 world_normal;

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

float cracks(vec2 p) {
	float n = noise(vec3(p * 1.7, 0.0));
	return smoothstep(0.03, 0.0, abs(n - 0.5)) * smoothstep(0.3, 0.7, noise(vec3(p * 0.3, 4.0)));
}

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 p = world.xz;
	vec3 color;
	float rough = 0.9;
	if (kind == 0) {
		color = mix(vec3(0.07, 0.068, 0.064), vec3(0.11, 0.105, 0.098), noise(vec3(p * 0.8, 0.0)));
		color += (hash(floor(vec3(p * 40.0, 0.0))) - 0.5) * 0.02;
		color = mix(color, vec3(0.03), cracks(p));
		float patch = step(0.78, noise(vec3(p * 0.15, 9.0)));
		color = mix(color, vec3(0.05, 0.05, 0.048), patch * 0.6);
		float silt = smoothstep(0.45, 0.7, noise(vec3(p * 0.4, 2.0)));
		color = mix(color, vec3(0.22, 0.18, 0.13), silt * 0.5);
	} else if (kind == 1) {
		vec2 slab = fract(p / 1.5);
		float joint = 1.0 - smoothstep(0.0, 0.025, min(min(slab.x, 1.0 - slab.x), min(slab.y, 1.0 - slab.y)));
		color = vec3(0.42, 0.41, 0.38) * (0.85 + 0.25 * hash(vec3(floor(p / 1.5), 0.0)));
		color *= 0.9 + 0.15 * noise(vec3(p * 3.0, 1.0));
		color = mix(color, vec3(0.12), joint * 0.7 + cracks(p * 1.5) * 0.6);
		color = mix(color, vec3(0.28, 0.24, 0.17), smoothstep(0.5, 0.8, noise(vec3(p * 0.5, 7.0))) * 0.5);
	} else if (kind == 2) {
		color = mix(vec3(0.17, 0.14, 0.1), vec3(0.27, 0.22, 0.15), noise(vec3(p * 0.6, 3.0)));
		color = mix(color, vec3(0.1, 0.085, 0.06), smoothstep(0.6, 0.8, noise(vec3(p * 2.5, 5.0))));
		rough = 0.75;
	} else {
		// Fine clumps fade out with distance so the far hills do not shimmer.
		float far = smoothstep(50.0, 220.0, distance(world, CAMERA_POSITION_WORLD));
		float fine = mix(noise(vec3(p * 4.0, 8.0)), 0.5, far);
		float clump = noise(vec3(p * 0.7, 6.0)) * 0.6 + fine * 0.4;
		color = mix(vec3(0.1, 0.11, 0.06), vec3(0.2, 0.2, 0.1), clump);
		color = mix(color, vec3(0.18, 0.14, 0.09), smoothstep(0.62, 0.8, noise(vec3(p * 0.3, 11.0))) * 0.7);
		// Big patches of bracken and bare earth on the hillsides.
		color = mix(color, vec3(0.2, 0.13, 0.07), smoothstep(0.55, 0.75, noise(vec3(p * 0.04, 13.0))) * 0.6);
		// Rock where the ground is steep, in layers.
		float steep = smoothstep(0.86, 0.7, world_normal.y + (noise(vec3(p * 0.2, 15.0)) - 0.5) * 0.12);
		float strata = 0.8 + 0.2 * noise(vec3(p.x * 0.05, world.y * 1.6, p.y * 0.05));
		color = mix(color, vec3(0.3, 0.29, 0.27) * strata, steep);
		rough = 0.97;
	}
	// Anything near the water's edge is wet.
	float wet = smoothstep(water_y + 0.4, water_y, world.y);
	color *= 1.0 - wet * 0.4;
	ALBEDO = color;
	ROUGHNESS = mix(rough, 0.3, wet);
}
