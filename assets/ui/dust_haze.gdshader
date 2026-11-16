shader_type spatial;
render_mode unshaded, depth_draw_never, depth_test_disabled, cull_disabled, blend_mix, fog_disabled, shadows_disabled;

// A full-screen layer of airborne dust that gets thicker with distance.
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform float density = 0.085;
uniform float strength = 0.0;
uniform vec3 tint : source_color = vec3(0.6, 0.47, 0.33);

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	float depth = texture(depth_tex, SCREEN_UV).x;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float distance_to = length(view.xyz / view.w);
	float swirl = 0.95 + 0.05 * sin(SCREEN_UV.x * 9.0 + TIME * 1.7) * sin(SCREEN_UV.y * 7.0 - TIME * 1.1);
	ALBEDO = tint;
	ALPHA = clamp((1.0 - exp(-distance_to * density)) * strength * swirl * 1.08, 0.0, 0.995);
}
