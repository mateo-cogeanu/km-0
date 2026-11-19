shader_type spatial;
// Leaf and needle cards for the roadside trees and scrub
// (Sources/make_roadside_props.py). Each card is a quad with 0..1 UVs; the
// leaf shapes come from a small mask (Sources/make_foliage_masks.py). The cards'
// normals point out of the canopy, so a crown lights like a soft mass, and
// self-shading darkens the inside of it.

render_mode cull_disabled, depth_draw_opaque;

uniform vec4 base_color : source_color = vec4(0.36, 0.42, 0.26, 1.0);
uniform vec4 dry_color : source_color = vec4(0.55, 0.5, 0.32, 1.0);
uniform vec4 twig_color : source_color = vec4(0.24, 0.2, 0.16, 1.0);
uniform float dry = 0.12;
// The crown's middle and half-size in the model's own space, for shading.
uniform vec3 crown_center = vec3(0.0, 3.0, 0.0);
uniform vec3 crown_size = vec3(2.0, 1.2, 2.0);
uniform float sway = 0.04;
uniform sampler2D mask_tex : filter_linear_mipmap, repeat_disable;

varying float shade;
varying float tint;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	vec3 rel = (VERTEX - crown_center) / crown_size;
	float depth = clamp(length(rel), 0.0, 1.2);
	// Outer leaves catch the light; the inside and underside sit in shade.
	shade = mix(0.42, 1.0, smoothstep(0.15, 1.0, depth)) * mix(0.72, 1.0, smoothstep(-1.0, 0.6, rel.y));
	vec3 origin = MODEL_MATRIX[3].xyz;
	tint = hash(origin.xz * 0.37);
	// A slow breeze, more at the tips than near the trunk.
	float reach = clamp(length(VERTEX.xz) * 0.35 + VERTEX.y * 0.08, 0.0, 1.5);
	float t = TIME * 1.1 + origin.x * 0.13 + origin.z * 0.11;
	VERTEX.x += sin(t + VERTEX.y * 0.7) * sway * reach;
	VERTEX.z += sin(t * 0.83 + VERTEX.x * 0.6) * sway * 0.7 * reach;
	VERTEX.y += sin(t * 1.7 + VERTEX.z) * sway * 0.3 * reach;
}

void fragment() {
	// Undo the back-face flip: every card lights by its outward crown normal.
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	// Red: coverage, green: which leaf, blue: twig (Sources/make_foliage_masks.py).
	vec3 mask = texture(mask_tex, UV).rgb;
	float id = mask.g;
	float twig = mask.b;
	vec3 color = base_color.rgb * mix(0.82, 1.15, id);
	color = mix(color, dry_color.rgb, step(1.0 - dry, fract(id * 7.31)) * 0.55);
	color *= mix(0.9, 1.1, tint);
	color = mix(color, twig_color.rgb, twig);
	ALBEDO = color * shade;
	// Each leaf tilts its own way, so the crown glints and breaks up.
	NORMAL = normalize(NORMAL + vec3(id - 0.5, fract(id * 13.7) - 0.5, 0.0) * 0.7);
	ROUGHNESS = 0.8;
	SPECULAR = 0.25;
	BACKLIGHT = color * 0.45 * shade;
	// Mipmaps thin the leaves out with distance; lift coverage to keep the
	// crown's mass.
	float lod = log2(max(max(fwidth(UV).x, fwidth(UV).y) * 512.0, 1.0));
	ALPHA = mask.r * (1.0 + clamp(lod, 0.0, 5.0) * 0.4);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
