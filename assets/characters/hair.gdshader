shader_type spatial;
// Hair strands (alpha-free ribbons): each strand its own shade, darker at
// the root and lighter at the tip, with a highlight that runs across the
// strands rather than along them. Vertex colour holds the strand direction
// (rgb) and a random shade (alpha); UV.y runs root to tip.
render_mode cull_disabled;

uniform vec3 base_color : source_color = vec3(0.06, 0.045, 0.032);
uniform vec3 tip_color : source_color = vec3(0.12, 0.09, 0.065);
uniform float roughness_base = 0.45;

varying vec3 strand;

void vertex() {
	strand = normalize(COLOR.rgb * 2.0 - 1.0);
	vec3 t = normalize(strand - NORMAL * dot(strand, NORMAL));
	TANGENT = t;
	BINORMAL = cross(NORMAL, t);
}

void fragment() {
	float shade = COLOR.a;
	vec3 color = mix(base_color, tip_color, UV.y * 0.8) * (0.75 + 0.5 * shade);
	// Darker towards the edges of each ribbon, so strands read separately.
	color *= 0.7 + 0.3 * sin(UV.x * 3.14159);
	ALBEDO = color;
	ROUGHNESS = roughness_base + shade * 0.15;
	SPECULAR = 0.5;
	ANISOTROPY = 0.8;
	ANISOTROPY_FLOW = vec2(1.0, 0.0);
}
