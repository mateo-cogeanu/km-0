shader_type canvas_item;

// 0 by day; rises after dark and in tight, unlit places.
uniform float strength = 0.0;
uniform float pulse = 0.0;

void fragment() {
	vec2 centered = (UV - vec2(0.5)) * vec2(1.0, 0.82);
	float edge = smoothstep(0.32, 0.78, length(centered));
	float breathe = 1.0 + 0.08 * sin(TIME * 0.7) * pulse;
	COLOR = vec4(0.0, 0.0, 0.01, clamp(edge * strength * breathe, 0.0, 0.92));
}
