shader_type canvas_item;

// Explosion de sang : flash central, anneau de choc qui s'etend,
// eclaboussures bruitees. Pilotee par le script via 'progress' (0 -> 1).

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 core_color : source_color = vec4(1.0, 0.88, 0.6, 1.0);
uniform vec4 blood_color : source_color = vec4(0.8, 0.05, 0.05, 1.0);
uniform vec4 dark_color : source_color = vec4(0.28, 0.0, 0.05, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec2 p = UV - 0.5;
	float d = length(p) * 2.0;
	float ang = atan(p.y, p.x);

	// Eclaboussures : bruit angulaire, les bords de l'explosion sont dechires
	float n = noise(vec2(ang * 3.0, d * 4.0 - progress * 3.0)) * 0.35;

	// Flash central, tres bref
	float flash = smoothstep(0.4, 0.0, d) * (1.0 - smoothstep(0.0, 0.3, progress)) * 1.4;

	// Anneau de choc qui s'etend et s'affine
	float radius = progress * 0.95;
	float ring = smoothstep(0.18 - progress * 0.1, 0.0, abs(d - radius)) * (1.0 - progress * 0.6);

	// Boule de feu interieure qui gonfle puis se dissipe
	float fire = smoothstep(radius + 0.1, radius * 0.3, d + n) * (1.0 - progress);

	float intensity = max(flash, max(ring, fire));

	vec3 col = mix(dark_color.rgb, blood_color.rgb, smoothstep(0.1, 0.5, intensity));
	col = mix(col, core_color.rgb, smoothstep(0.72, 1.05, intensity));

	// Fondu global en fin de vie
	float alpha = smoothstep(0.08, 0.3, intensity) * (1.0 - progress * progress);
	COLOR = vec4(col, alpha);
}
