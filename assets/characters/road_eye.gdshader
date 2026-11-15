shader_type spatial;

// How brightly the eyes shine; raised in the dark so only they show.
uniform float glow = 1.0;
// 0 is a thin slit, 1 is wide open like an animal's eyes caught in a light.
uniform float dilate = 0.0;

void fragment() {
	vec2 iris = (UV - vec2(0.5)) / vec2(mix(0.056, 0.2, dilate), mix(0.34, 0.27, dilate));
	float slit = 1.0 - smoothstep(0.76, 1.04, length(iris));
	ALBEDO = mix(vec3(0.005, 0.004, 0.007), vec3(0.52, 0.004, 0.011), slit);
	ROUGHNESS = 0.18;
	SPECULAR = 0.5;
	EMISSION = vec3(0.74, 0.009, 0.018) * slit * 1.45 * glow;
}
