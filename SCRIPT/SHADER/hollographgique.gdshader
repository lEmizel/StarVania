shader_type canvas_item;

// === COULEURS CIBLES (color picker hex) ===
uniform vec3 color_range_from : source_color = vec3(0.0, 0.0, 0.5);
uniform vec3 color_range_to : source_color = vec3(0.5, 0.5, 1.0);
uniform float color_tolerance : hint_range(0.0, 1.0) = 0.3;
uniform float edge_softness : hint_range(0.01, 0.5) = 0.15;

// === ÉTOILES / PAILLETTES ===
uniform float sparkle_density : hint_range(5.0, 200.0) = 60.0;
uniform float sparkle_intensity : hint_range(0.0, 2.0) = 0.8;
uniform float sparkle_speed : hint_range(0.1, 10.0) = 3.0;
uniform float sparkle_size : hint_range(0.0, 1.0) = 0.4;

// === EFFET HOLOGRAPHIQUE ===
uniform float holo_strength : hint_range(0.0, 1.0) = 0.35;
uniform float holo_speed : hint_range(0.1, 5.0) = 1.0;
uniform float holo_scale : hint_range(1.0, 20.0) = 6.0;

// === SHIMMER ===
uniform float shimmer_strength : hint_range(0.0, 1.0) = 0.3;
uniform float shimmer_speed : hint_range(0.1, 5.0) = 2.0;
uniform float shimmer_angle : hint_range(0.0, 6.28) = 0.8;

// === RGB <-> HSV ===
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

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// === TEST SI UN PIXEL EST DANS LA PLAGE DE COULEUR ===
float color_in_range(vec3 pixel, vec3 col_from, vec3 col_to, float tolerance, float softness) {
	// Centre et demi-étendue de la boîte de couleur
	vec3 center = (col_from + col_to) * 0.5;
	vec3 half_range = abs(col_to - col_from) * 0.5 + vec3(tolerance);

	// Distance normalisée du pixel au centre de la boîte
	vec3 d = abs(pixel - center) / half_range;
	float dist = max(d.x, max(d.y, d.z));

	// Smooth : 1 au centre, 0 en dehors
	return 1.0 - smoothstep(1.0 - softness, 1.0 + softness, dist);
}

// === FRAGMENT ===
void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec3 col = tex.rgb;
	vec3 hsv = rgb2hsv(col);

	// Masque de couleur
	float in_range = color_in_range(col, color_range_from, color_range_to, color_tolerance, edge_softness);

	// --- PAILLETTES ---
	vec2 sparkle_cell = floor(UV * sparkle_density);
	float sparkle_id = hash21(sparkle_cell);
	vec2 sparkle_center = (sparkle_cell + 0.5) / sparkle_density;
	float dist_to_center = length(UV - sparkle_center) * sparkle_density;

	float sparkle_phase = sparkle_id * 6.28;
	float sparkle_time = sin(TIME * sparkle_speed + sparkle_phase);
	float sparkle_thresh = smoothstep(0.3, 1.0, sparkle_time);
	float sparkle_shape = 1.0 - smoothstep(0.0, sparkle_size, dist_to_center);

	vec2 local = (UV - sparkle_center) * sparkle_density;
	float cross_x = exp(-abs(local.y) * 8.0) * exp(-abs(local.x) * 3.0);
	float cross_y = exp(-abs(local.x) * 8.0) * exp(-abs(local.y) * 3.0);
	float star_shape = max(sparkle_shape, (cross_x + cross_y) * 0.5);

	float sparkle = star_shape * sparkle_thresh * sparkle_intensity;
	vec3 sparkle_color = mix(vec3(1.0), hsv2rgb(vec3(sparkle_id, 0.2, 1.0)), 0.2);

	// --- HOLOGRAPHIQUE ---
	float holo_phase = dot(UV, vec2(cos(shimmer_angle), sin(shimmer_angle))) * holo_scale + TIME * holo_speed;
	float hue_shift = sin(holo_phase) * 0.15 + sin(holo_phase * 2.3 + 1.0) * 0.08;
	vec3 shifted_hsv = hsv;
	shifted_hsv.x = fract(shifted_hsv.x + hue_shift);
	shifted_hsv.y = max(shifted_hsv.y, 0.3);
	shifted_hsv.z = min(shifted_hsv.z * 1.15, 1.0);
	vec3 holo_col = hsv2rgb(shifted_hsv);

	// --- SHIMMER ---
	vec2 shimmer_dir = vec2(cos(shimmer_angle), sin(shimmer_angle));
	float shimmer_pos = dot(UV, shimmer_dir) * 8.0 - TIME * shimmer_speed;
	float shimmer = pow(sin(shimmer_pos) * 0.5 + 0.5, 3.0) * shimmer_strength;

	// --- COMPOSITION ---
	vec3 result = mix(col, holo_col, holo_strength);
	result += result * shimmer;
	result += sparkle_color * sparkle;
	result = min(result, vec3(1.0));

	// Mix entre original et effet selon masque couleur
	vec3 final_col = mix(col, result, in_range);

	COLOR = vec4(final_col, tex.a);
}
