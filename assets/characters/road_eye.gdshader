shader_type spatial;

void fragment() {
	vec2 iris = (UV - vec2(0.5)) / vec2(0.056, 0.34);
	float slit = 1.0 - smoothstep(0.76, 1.04, length(iris));
	ALBEDO = mix(vec3(0.005, 0.004, 0.007), vec3(0.52, 0.004, 0.011), slit);
	ROUGHNESS = 0.43;
	SPECULAR = 0.23;
	EMISSION = vec3(0.74, 0.009, 0.018) * slit * 1.45;
}
