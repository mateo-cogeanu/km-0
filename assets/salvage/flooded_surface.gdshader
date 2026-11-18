shader_type spatial;
// Painted wood, brick and concrete after years under floodwater: a hard tide
// line where the water stood, silt and staining below it, grime streaks
// running down from every sill, and paint peeling back to grey wood. The
// band just above the water now is dark and wet.

uniform vec3 base_color : source_color = vec3(0.55);
uniform float peel = 0.0;
uniform float bricks = 0.0;
// For the simple distant houses: clapboard drawn on instead of built.
uniform float boards = 0.0;
uniform float tide_y = -4.4;
uniform float water_y = -5.2;
uniform float roughness_base = 0.85;
instance uniform vec3 tint : source_color = vec3(1.0);

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

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 color = base_color * tint;
	float variation = noise(world * 3.0) * 0.5 + noise(world * 11.0) * 0.5;
	color *= 0.9 + 0.15 * variation;
	if (bricks > 0.5) {
		// Each brick its own shade of red-brown.
		vec3 cell = floor(world * vec3(4.4, 13.3, 4.4));
		color *= 0.75 + 0.45 * hash(cell);
	}
	if (boards > 0.5 && abs(world_normal.y) < 0.5) {
		// The shadow line under each board's lower edge, every 20 cm.
		float row = fract(world.y / 0.2);
		color *= mix(0.62, 1.0, smoothstep(0.0, 0.12, row)) * mix(1.0, 1.06, smoothstep(0.5, 1.0, row));
	}
	// Peeling paint, showing weathered grey wood.
	float flake = smoothstep(0.7, 0.76, noise(world * vec3(14.0, 22.0, 14.0) + vec3(2.0)) * 0.6 + noise(world * 2.5) * 0.4);
	color = mix(color, vec3(0.32, 0.3, 0.27), flake * peel);
	// Grime running down in streaks.
	float streak = noise(vec3(world.x * 9.0 + world.z * 9.0, world.y * 0.7, 0.0));
	color *= 1.0 - smoothstep(0.55, 0.9, streak) * 0.35;
	// Below the old tide line: silt-brown, darker toward the bottom, with a
	// sharp scummy line at the top.
	float below = smoothstep(tide_y + 0.03, tide_y - 0.03, world.y + (noise(world * 2.0) - 0.5) * 0.06);
	float depth = clamp((tide_y - world.y) / 1.6, 0.0, 1.0);
	color = mix(color, mix(vec3(0.3, 0.26, 0.19), vec3(0.14, 0.12, 0.09), depth), below * 0.75);
	float line = smoothstep(0.06, 0.0, abs(world.y - tide_y)) ;
	color = mix(color, vec3(0.16, 0.14, 0.1), line * 0.7);
	// Wet and dark just above the water now.
	float wet = smoothstep(water_y + 0.35, water_y, world.y);
	color *= 1.0 - wet * 0.45;
	// Up on top, a little dust and bird lime.
	color = mix(color, vec3(0.6, 0.58, 0.54), smoothstep(0.7, 1.0, world_normal.y) * 0.15);
	ALBEDO = color;
	ROUGHNESS = mix(roughness_base, 0.25, wet);
	SPECULAR = 0.3 + wet * 0.3;
}
