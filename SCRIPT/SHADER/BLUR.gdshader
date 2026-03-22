shader_type canvas_item;

// === PARAMÈTRES ===
uniform float distortion_strength : hint_range(0.0, 0.05) = 0.012;
uniform float speed : hint_range(0.1, 5.0) = 1.0;
uniform float scale : hint_range(0.001, 0.1) = 0.02;
uniform float vertical_bias : hint_range(0.0, 1.0) = 0.7;
uniform float fade_top : hint_range(0.0, 1.0) = 0.1;
uniform float fade_bottom : hint_range(0.0, 1.0) = 0.9;
uniform bool circular_mode = false;
uniform float circular_radius : hint_range(0.0, 0.5) = 0.4;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

// Coordonnées monde passées du vertex au fragment
varying vec2 world_pos;

// === BRUIT ===
vec3 mod289_3(vec3 x) {
	return x - floor(x * (1.0 / 289.0)) * 289.0;
}

vec4 mod289_4(vec4 x) {
	return x - floor(x * (1.0 / 289.0)) * 289.0;
}

vec4 permute(vec4 x) {
	return mod289_4(((x * 34.0) + 1.0) * x);
}

float noise(vec3 p) {
	vec3 a = floor(p);
	vec3 d = p - a;
	d = d * d * (3.0 - 2.0 * d);

	a = mod289_3(a);
	vec4 b = a.xxyy + vec4(0.0, 1.0, 0.0, 1.0);
	vec4 k1 = permute(b.xyxy);
	vec4 k2 = permute(k1.xyxy + b.zzww);

	vec4 c = k2 + a.zzzz;
	vec4 k3 = permute(c);
	vec4 k4 = permute(c + 1.0);

	vec4 o1 = fract(k3 * (1.0 / 41.0));
	vec4 o2 = fract(k4 * (1.0 / 41.0));
	vec4 o3 = o2 * d.z + o1 * (1.0 - d.z);
	vec2 o4 = o3.yw * d.x + o3.xz * (1.0 - d.x);

	return o4.y * d.y + o4.x * (1.0 - d.y);
}

float fbm(vec3 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 4; i++) {
		value += amplitude * noise(p);
		p *= 2.03;
		amplitude *= 0.5;
	}
	return value;
}

// === VERTEX : calcule la position monde ===
void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

// === FRAGMENT ===
void fragment() {
	vec2 uv = SCREEN_UV;
	float t = TIME * speed;

	// Bruit ancré en espace monde -> indépendant de la caméra
	vec2 world_uv = world_pos * scale;

	float noise_x = fbm(vec3(world_uv, t * 0.8)) * 2.0 - 1.0;
	float noise_y = fbm(vec3(world_uv + 50.0, t * 1.1)) * 2.0 - 1.0;

	noise_y = mix(noise_y, abs(noise_y), vertical_bias);

	vec2 distortion = vec2(noise_x, noise_y) * distortion_strength;

	// Masque de zone d'effet
	float mask = 1.0;
	if (circular_mode) {
		float dist = length(UV - 0.5);
		mask = smoothstep(circular_radius, circular_radius * 0.3, dist);
	} else {
		mask = smoothstep(fade_top, fade_top + 0.15, UV.y);
		mask *= smoothstep(fade_bottom, fade_bottom - 0.15, UV.y);
	}

	distortion *= mask;

	vec4 scene = texture(screen_tex, uv + distortion);

	float alpha = length(distortion) > 0.0001 ? 1.0 : 0.0;

	COLOR = vec4(scene.rgb, alpha);
}
