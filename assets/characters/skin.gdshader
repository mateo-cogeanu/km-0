shader_type spatial;
// Skin: a little uneven in tone, flushed at cheeks, nose, ears and knuckles
// (vertex colour green), fine pores, light scattering through it, and an
// oilier sheen down the nose and forehead.

uniform vec3 base_color : source_color = vec3(0.6, 0.42, 0.33);
uniform vec3 flush_color : source_color = vec3(0.62, 0.3, 0.26);
uniform float weathered = 0.0;
uniform sampler2D noise_tex : hint_default_black, filter_linear_mipmap, repeat_enable;

float n2(vec2 p) {
	return texture(noise_tex, p * 0.03125).r;
}

void fragment() {
	vec2 p = UV;
	vec3 color = base_color * (0.92 + 0.14 * n2(p * 30.0));
	color = mix(color, flush_color, COLOR.g * (0.25 + 0.2 * weathered));
	// Sun-darkened, blotchy with age.
	float spots = smoothstep(0.62, 0.8, n2(p * 90.0)) * weathered;
	color *= 1.0 - spots * 0.18 - weathered * 0.06;
	float pores = n2(p * 900.0);
	color *= 0.97 + 0.03 * pores;
	ALBEDO = color;
	ROUGHNESS = 0.55 + 0.15 * n2(p * 50.0) + weathered * 0.1;
	SPECULAR = 0.35;
	SSS_STRENGTH = 0.18;
	BACKLIGHT = vec3(0.12, 0.03, 0.02);
	float fine = 1.0 - smoothstep(0.0003, 0.002, length(fwidth(p)));
	float e = 0.0003;
	vec2 grad = vec2(n2((p + vec2(e, 0.0)) * 900.0) - pores, n2((p + vec2(0.0, e)) * 900.0) - pores) / e;
	NORMAL_MAP = normalize(vec3(-grad * 0.0001 * fine * (1.0 + weathered), 1.0)) * 0.5 + 0.5;
}
