shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;
// Murky floodwater: dark and opaque a little way down, scum and foam where
// it touches walls and cars, slow ripples, and the sky in it at low angles.

uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;
uniform vec3 murk : source_color = vec3(0.035, 0.037, 0.024);
uniform vec3 shallow : source_color = vec3(0.14, 0.13, 0.09);
uniform float clarity = 0.35;

varying vec3 world;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float ripples(vec2 p) {
	float t = TIME;
	return noise(p * 0.9 + vec2(t * 0.05, t * 0.03)) * 0.5 + noise(p * 2.3 - vec2(t * 0.07, -t * 0.04)) * 0.3
		+ noise(p * 6.0 + vec2(t * 0.15, t * 0.1)) * 0.2;
}

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// How much water lies between the surface and whatever is behind it.
	float scene_depth = texture(depth_texture, SCREEN_UV).r;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, scene_depth, 1.0);
	behind.xyz /= behind.w;
	float thickness = max(VERTEX.z - behind.z, 0.0);
	float see = exp(-thickness / clarity);
	// Ripples tilt the surface.
	vec2 p = world.xz;
	float e = 0.06;
	float h = ripples(p);
	vec3 bump = normalize(vec3(h - ripples(p + vec2(e, 0.0)), 0.25, h - ripples(p + vec2(0.0, e))));
	NORMAL = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(bump, 0.0)).xyz, 0.5));
	// Scum and foam where it meets anything standing in it.
	float edge = smoothstep(0.18, 0.0, thickness) * (0.6 + 0.4 * noise(p * 8.0 + TIME * 0.2));
	float scum = smoothstep(0.6, 0.8, noise(p * 0.35 + vec2(TIME * 0.01)));
	vec3 color = mix(murk, shallow, see * 0.8);
	color = mix(color, vec3(0.2, 0.19, 0.15), scum * 0.35);
	color = mix(color, vec3(0.45, 0.43, 0.38), edge * 0.6);
	ALBEDO = color;
	ALPHA = clamp(1.0 - see * 0.85 + edge * 0.3, 0.0, 1.0);
	ROUGHNESS = mix(0.24, 0.55, scum * 0.5 + edge);
	SPECULAR = 0.32;
	METALLIC = 0.0;
}
