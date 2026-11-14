shader_type spatial;

varying vec3 world_point;

void vertex() {
	world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 world_xz = world_point.xz;
	float lane = abs(abs(UV.x - 0.5) - 0.25) * 4.0;
	float wheel_wear = smoothstep(0.16, 0.32, lane) * (1.0 - smoothstep(0.39, 0.56, lane));
	float stains = sin(world_xz.y * 0.34 + cos(world_xz.x * 1.7)) * cos(world_xz.y * 0.81);
	float edge_dust = smoothstep(0.42, 0.51, abs(UV.x - 0.5));
	vec3 pavement = mix(vec3(0.079, 0.076, 0.071), vec3(0.112, 0.106, 0.097), wheel_wear);
	pavement += stains * 0.008;
	ALBEDO = mix(pavement, vec3(0.205, 0.158, 0.105), edge_dust * 0.60);
	ROUGHNESS = 0.94;
}
