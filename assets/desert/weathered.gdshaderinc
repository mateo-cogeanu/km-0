// Paint, sheet steel, block, brick and boards after years of desert sun: paint
// bleached pale and chalky where the sun hits, flaking back to primer or grey
// wood, rust bleeding down from every seam and fixing, and a skirt of sand
// blown up against the bottom of every wall. Optional procedural detail for
// the simple distant shells and the roller shutters: ribs, block courses,
// boards. `char_amount` blackens it all for the fire.

uniform vec3 base_color : source_color = vec3(0.55);
uniform float metallic_base = 0.0;
uniform float roughness_base = 0.85;
uniform float bleach = 0.35;
uniform float peel = 0.0;
uniform vec3 under_color : source_color = vec3(0.36, 0.33, 0.29);
uniform float rust = 0.0;
uniform float dust = 0.5;
uniform float streaks = 0.3;
uniform float bricks = 0.0;
uniform float blocks = 0.0;
// 0 none, 1 vertical ribs (sheet walls), 2 horizontal ribs (shutters, roofs run along x).
uniform int ribs = 0;
uniform float boards = 0.0;
uniform float wood_grain = 0.0;
uniform float char_amount = 0.0;
uniform float wet_amount = 0.0;
instance uniform vec3 tint : source_color = vec3(1.0);
// Painted surfaces take the building's colour; bare steel and wood do not.
uniform float use_tint = 0.0;

uniform sampler2D noise_tex : hint_default_black, filter_linear_mipmap, repeat_enable;

varying vec3 world;
varying vec3 local;
varying vec3 world_normal;
varying vec3 local_normal;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.27, 0.43));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise2(vec2 p) {
	return texture(noise_tex, p * 0.03125).r;
}

// Noise on the plane a surface faces, so no wall gets smeared diagonally.
float nz(vec3 an, vec3 p) {
	return noise2(an.y > 0.7 ? p.xz : (an.x > an.z ? p.zy + vec2(p.x * 0.37, 0.0) : p.xy + vec2(p.z * 0.37, 0.0)));
}

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	local = VERTEX;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	local_normal = NORMAL;
}

void fragment() {
	vec3 an = abs(world_normal);
	vec3 n = normalize(local_normal);
	// Wall coordinates: across the face and up it.
	vec2 face = abs(n.x) > abs(n.z) ? local.zy : local.xy;
	if (abs(n.y) > 0.7) {
		face = local.xz;
	}
	vec3 color = base_color * mix(vec3(1.0), tint, use_tint);
	float variation = nz(an, world * 2.3) * 0.55 + hash(floor(world * 9.0)) * 0.2 + 0.12;
	color *= 0.86 + 0.24 * variation;
	if (bricks > 0.5) {
		vec2 cell = vec2(face.x * 4.4 + floor(face.y * 13.33) * 0.5, face.y * 13.33);
		color *= 0.76 + 0.42 * hash(vec3(floor(cell), 1.0));
		vec2 f = fract(cell);
		color = mix(color, vec3(0.5, 0.47, 0.42), (1.0 - step(0.06, f.y)) * 0.8 + (1.0 - step(0.03, f.x)) * 0.8 * step(0.06, f.y));
	}
	if (blocks > 0.5 && abs(n.y) < 0.7) {
		vec2 cell = vec2(face.x / 0.4 + floor(face.y / 0.2) * 0.5, face.y / 0.2);
		vec2 f = fract(cell);
		color *= 0.9 + 0.14 * hash(vec3(floor(cell), 2.0));
		float joint = max(1.0 - smoothstep(0.0, 0.05, f.y), 1.0 - smoothstep(0.0, 0.025, f.x));
		color *= 1.0 - joint * 0.3;
	}
	if (boards > 0.5 && abs(n.y) < 0.7) {
		float row = fract(face.y / 0.2);
		color *= mix(0.62, 1.0, smoothstep(0.0, 0.12, row)) * mix(1.0, 1.06, smoothstep(0.5, 1.0, row));
	}
	if (wood_grain > 0.0) {
		float grain = nz(an, vec3(face.x * 40.0, face.y * 2.0, local.z * 40.0 + local.x * 3.0));
		color *= 1.0 - wood_grain * 0.25 * smoothstep(0.4, 0.9, grain);
	}
	// Sun-bleached: chalky and pale, most on what faces the sky and the south.
	float sun = clamp(0.55 + 0.45 * world_normal.y + 0.2 * world_normal.z, 0.0, 1.0);
	float chalk = bleach * sun * (0.6 + 0.4 * variation);
	color = mix(color, vec3(dot(color, vec3(0.3, 0.59, 0.11))) * 1.06 + vec3(0.025, 0.02, 0.01), chalk);
	// Flaking paint, showing what is under it.
	float flake = 0.0;
	if (peel > 0.0) {
		flake = smoothstep(0.66, 0.72, nz(an, world * vec3(13.0, 21.0, 13.0) + vec3(4.0)) * 0.6 + variation * 0.45);
		color = mix(color, under_color, flake * peel);
	}
	// Rust: small patches drawn out downward, worst low down and at the edges.
	float blotch = 0.0;
	if (rust > 0.0) {
		float runs = nz(an, world * vec3(7.0, 1.2, 7.0) + vec3(7.0)) * 0.55 + hash(floor(world * 24.0)) * 0.15 + 0.08;
		float low = 1.0 - smoothstep(0.0, 0.9, local.y);
		blotch = smoothstep(0.6, 0.82, runs + low * 0.22 + variation * 0.15);
		vec3 rusty = mix(vec3(0.36, 0.2, 0.11), vec3(0.24, 0.14, 0.09), hash(floor(world * 30.0)));
		color = mix(color, rusty, blotch * rust);
	}
	// Streaks running down the walls from seams and fixings.
	if (streaks > 0.0 && abs(n.y) < 0.7) {
		float streak = nz(an, vec3(face.x * 11.0, world.y * 0.6, 0.0)) * (0.4 + variation * 0.6);
		float s = smoothstep(0.3, 0.6, streak) * streaks;
		color = mix(color, color * vec3(0.72, 0.6, 0.5), s);
	}
	// Ribs drawn on: the shading of corrugation without the geometry.
	vec3 bump = vec3(0.0);
	if (ribs == 1) {
		float u = face.x / 0.076 * 6.2831;
		bump = vec3(cos(u), 0.0, 0.0);
		color *= 0.92 + 0.08 * sin(u);
	} else if (ribs == 2) {
		float u = local.y / 0.038 * 6.2831;
		bump = vec3(0.0, cos(u), 0.0);
		color *= 0.9 + 0.1 * sin(u);
	}
	// Sand blown up the bottom of the walls, and lying on ledges.
	if (dust > 0.0 && (local.y < 1.1 || world_normal.y > 0.75)) {
		float skirt = smoothstep(0.55 + variation * 0.5, 0.0, local.y) * step(abs(n.y), 0.7);
		float ledge = smoothstep(0.75, 1.0, world_normal.y) * (0.3 + 0.7 * variation);
		vec3 sand = vec3(0.6, 0.49, 0.36) * (0.9 + 0.2 * hash(floor(world * 40.0)));
		color = mix(color, sand, clamp((skirt * 0.6 + ledge * 0.4) * dust, 0.0, 1.0));
	}
	// Petrol soaking in, then fire.
	color *= 1.0 - wet_amount * 0.55;
	if (char_amount > 0.0) {
		float soot = char_amount * (0.75 + 0.25 * nz(an, world * 4.0));
		color = mix(color, vec3(0.035, 0.03, 0.028), soot);
	}
	ALBEDO = color;
	METALLIC = metallic_base * (1.0 - flake * peel) * (1.0 - blotch * rust) * (1.0 - chalk * 0.5);
	ROUGHNESS = mix(clamp(roughness_base + blotch * rust * 0.2, 0.0, 1.0), 0.15, wet_amount);
	if (ribs > 0) {
		NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4((MODEL_MATRIX * vec4(bump * 0.35, 0.0)).xyz, 0.0)).xyz);
	}
}
