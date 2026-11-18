shader_type spatial;
// Cloth and leather for the people, all from runtime noise: canvas weave,
// denim twill with fading, knit rib, wool, scuffed leather, cotton and
// flannel check, rubber. UV is in metres round and along the limbs
// (Sources/make_player.py); vertex colour red is how worn a spot is.

uniform int kind = 0; // 0 canvas, 1 denim, 2 knit, 3 wool, 4 leather, 5 cotton, 6 flannel, 7 rubber
uniform vec3 base_color : source_color = vec3(0.4);
uniform vec3 wear_color : source_color = vec3(0.6);
uniform vec3 check_color : source_color = vec3(0.1);
uniform float roughness_base = 0.9;
uniform float sheen = 0.0;
uniform sampler2D noise_tex : hint_default_black, filter_linear_mipmap, repeat_enable;

float n2(vec2 p) {
	return texture(noise_tex, p * 0.03125).r;
}

// The height of the cloth surface at p (metres), for the bump.
float height(vec2 p) {
	if (kind == 0) {
		vec2 w = sin(p * 6.2831 / 0.0024);
		return (w.x * w.y) * 0.5 + 0.5;
	} else if (kind == 1) {
		return fract((p.x + p.y) / 0.0028) < 0.62 ? 1.0 : 0.0;
	} else if (kind == 2) {
		return 0.5 + 0.5 * sin(p.x * 6.2831 / 0.006);
	} else if (kind == 3) {
		return n2(p * 260.0) * 0.6 + n2(p * 70.0) * 0.4;
	} else if (kind == 4) {
		return n2(p * 140.0) * 0.5 + n2(p * 35.0) * 0.5;
	} else if (kind == 5 || kind == 6) {
		vec2 w = sin(p * 6.2831 / 0.0016);
		return w.x * w.y * 0.5 + 0.5;
	}
	return n2(p * 300.0);
}

void fragment() {
	vec2 p = UV;
	float wear = COLOR.r;
	float fine = 1.0 - smoothstep(0.0008, 0.004, length(fwidth(p)));
	vec3 color = base_color;
	float mottle = n2(p * 6.0) * 0.6 + n2(p * 25.0) * 0.4;
	color *= 0.86 + 0.28 * mottle;
	float rough = roughness_base;
	if (kind == 1) {
		// Indigo warp over white weft, faded where it rubs, with whiskers.
		float twill = fract((p.x + p.y) / 0.0028);
		// Where the weave is too fine to draw, its average shade instead.
		color = mix(color, color * 1.35 + vec3(0.06), mix(0.62, 1.0 - step(0.62, twill), fine) * 0.35);
		float fade = wear * (0.7 + 0.3 * n2(p * 4.0));
		float whisker = smoothstep(0.7, 0.95, n2(vec2(p.x * 3.0, p.y * 40.0))) * wear;
		color = mix(color, wear_color, clamp(fade * 0.45 + whisker * 0.3, 0.0, 1.0));
	} else if (kind == 0) {
		color = mix(color, wear_color, wear * (0.4 + 0.6 * n2(p * 15.0)) * 0.6);
		color *= 0.94 + 0.06 * mix(0.5, height(p), fine);
	} else if (kind == 2) {
		color *= 0.85 + 0.15 * height(p);
		float stitch = abs(fract(p.y / 0.004) - 0.5) * 2.0;
		color *= 0.92 + 0.08 * stitch;
	} else if (kind == 3) {
		color *= 0.85 + 0.25 * n2(p * 260.0);
		color = mix(color, wear_color, wear * 0.4);
	} else if (kind == 4) {
		float scuff = smoothstep(0.55, 0.8, n2(p * 30.0)) * (0.4 + 0.6 * wear);
		color = mix(color, wear_color, scuff * 0.7);
		float crease = smoothstep(0.7, 0.9, n2(vec2(p.x * 200.0, p.y * 20.0)));
		color *= 1.0 - crease * 0.25;
		rough = mix(0.45, 0.85, scuff);
	} else if (kind == 6) {
		// Flannel check: broad bands both ways, a thin line between.
		vec2 c = fract(p / 0.045);
		float bands = step(0.5, c.x) + step(0.5, c.y);
		color = mix(color, check_color, bands * 0.45);
		float line = (1.0 - step(0.06, abs(c.x - 0.25))) + (1.0 - step(0.06, abs(c.y - 0.25)));
		color = mix(color, vec3(0.45, 0.42, 0.36), clamp(line, 0.0, 1.0) * 0.5);
		color *= 0.9 + 0.1 * n2(p * 300.0);
	}
	ALBEDO = color;
	ROUGHNESS = rough;
	SPECULAR = 0.3;
	// Sheen at grazing angles: cloth catches the light at its edges.
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO += color * rim * sheen;
	// Bump from the pattern, fading out where it would shimmer.
	float e = 0.0004;
	float h = height(p);
	vec2 grad = vec2(height(p + vec2(e, 0.0)) - h, height(p + vec2(0.0, e)) - h) / e;
	float strength = (kind == 4 ? 0.0012 : (kind == 3 ? 0.0006 : 0.00025)) * fine;
	NORMAL_MAP = normalize(vec3(-grad * strength, 1.0)) * 0.5 + 0.5;
}
