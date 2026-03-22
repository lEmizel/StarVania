shader_type canvas_item;

// === Couleur Range 1 (from/to) ===
uniform vec4 color1_from : source_color = vec4(0.73, 0.19, 0.30, 1.0);
uniform vec4 color1_to : source_color = vec4(0.44, 0.19, 0.30, 1.0);
uniform float hue_shift_1 : hint_range(0.0, 1.0) = 0.0;
uniform float saturation_1 : hint_range(0.0, 2.0) = 1.0;
uniform float brightness_1 : hint_range(0.5, 1.5) = 1.0;
uniform float hue_tolerance_1 : hint_range(0.01, 0.3) = 0.06;

// === Couleur Range 2 (from/to) ===
uniform vec4 color2_from : source_color = vec4(0.2, 0.4, 0.8, 1.0);
uniform vec4 color2_to : source_color = vec4(0.2, 0.3, 0.6, 1.0);
uniform float hue_shift_2 : hint_range(0.0, 1.0) = 0.0;
uniform float saturation_2 : hint_range(0.0, 2.0) = 1.0;
uniform float brightness_2 : hint_range(0.5, 1.5) = 1.0;
uniform float hue_tolerance_2 : hint_range(0.01, 0.3) = 0.06;

// === Couleur Range 3 (from/to) ===
uniform vec4 color3_from : source_color = vec4(0.8, 0.7, 0.2, 1.0);
uniform vec4 color3_to : source_color = vec4(0.6, 0.5, 0.1, 1.0);
uniform float hue_shift_3 : hint_range(0.0, 1.0) = 0.0;
uniform float saturation_3 : hint_range(0.0, 2.0) = 1.0;
uniform float brightness_3 : hint_range(0.5, 1.5) = 1.0;
uniform float hue_tolerance_3 : hint_range(0.01, 0.3) = 0.06;

// === Couleur Simple A (une seule cible) ===
uniform vec4 color_a : source_color = vec4(1.0, 0.0, 0.0, 1.0);
uniform float hue_shift_a : hint_range(0.0, 1.0) = 0.0;
uniform float saturation_a : hint_range(0.0, 2.0) = 1.0;
uniform float brightness_a : hint_range(0.5, 1.5) = 1.0;
uniform float hue_tolerance_a : hint_range(0.01, 0.3) = 0.06;

// === Couleur Simple B ===
uniform vec4 color_b : source_color = vec4(0.0, 1.0, 0.0, 1.0);
uniform float hue_shift_b : hint_range(0.0, 1.0) = 0.0;
uniform float saturation_b : hint_range(0.0, 2.0) = 1.0;
uniform float brightness_b : hint_range(0.5, 1.5) = 1.0;
uniform float hue_tolerance_b : hint_range(0.01, 0.3) = 0.06;

// === Couleur Simple C ===
uniform vec4 color_c : source_color = vec4(0.0, 0.0, 1.0, 1.0);
uniform float hue_shift_c : hint_range(0.0, 1.0) = 0.0;
uniform float saturation_c : hint_range(0.0, 2.0) = 1.0;
uniform float brightness_c : hint_range(0.5, 1.5) = 1.0;
uniform float hue_tolerance_c : hint_range(0.01, 0.3) = 0.06;

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0/3.0, 2.0/3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0/3.0, 1.0/3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

// Recolor par range (midpoint de from/to)
bool try_recolor_range(inout vec3 hsv, vec4 from_col, vec4 to_col, float h_shift, float sat, float bright, float tolerance) {
	float hue_from = rgb2hsv(from_col.rgb).x;
	float hue_to = rgb2hsv(to_col.rgb).x;
	float target_hue = (hue_from + hue_to) * 0.5;
	float dist = abs(hsv.x - target_hue);
	dist = min(dist, 1.0 - dist);
	if (dist < tolerance && hsv.y > 0.1) {
		hsv.x = fract(hsv.x + h_shift);
		hsv.y *= sat;
		hsv.z *= bright;
		return true;
	}
	return false;
}

// Recolor par couleur simple (hue directe)
bool try_recolor_single(inout vec3 hsv, vec4 target_col, float h_shift, float sat, float bright, float tolerance) {
	float target_hue = rgb2hsv(target_col.rgb).x;
	float dist = abs(hsv.x - target_hue);
	dist = min(dist, 1.0 - dist);
	if (dist < tolerance && hsv.y > 0.1) {
		hsv.x = fract(hsv.x + h_shift);
		hsv.y *= sat;
		hsv.z *= bright;
		return true;
	}
	return false;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec3 hsv = rgb2hsv(tex.rgb);

	// D'abord les ranges (prioritaires)
	if (!try_recolor_range(hsv, color1_from, color1_to, hue_shift_1, saturation_1, brightness_1, hue_tolerance_1)) {
	if (!try_recolor_range(hsv, color2_from, color2_to, hue_shift_2, saturation_2, brightness_2, hue_tolerance_2)) {
	if (!try_recolor_range(hsv, color3_from, color3_to, hue_shift_3, saturation_3, brightness_3, hue_tolerance_3)) {
	// Ensuite les simples
	if (!try_recolor_single(hsv, color_a, hue_shift_a, saturation_a, brightness_a, hue_tolerance_a)) {
	if (!try_recolor_single(hsv, color_b, hue_shift_b, saturation_b, brightness_b, hue_tolerance_b)) {
		try_recolor_single(hsv, color_c, hue_shift_c, saturation_c, brightness_c, hue_tolerance_c);
	}}}}}

	COLOR = vec4(hsv2rgb(hsv), tex.a);
}