shader_type canvas_item;

// Boule de feu rouge sang, entierement procedurale.
// Le quad est large (3:1) : la boule occupe l'avant (droite),
// la trainee de flammes s'etire derriere et defile avec le temps.

uniform vec4 core_color : source_color = vec4(1.0, 0.9, 0.65, 1.0);
uniform vec4 blood_color : source_color = vec4(0.85, 0.08, 0.08, 1.0);
uniform vec4 outer_color : source_color = vec4(0.35, 0.0, 0.06, 1.0);
uniform float ball_radius : hint_range(0.1, 0.5) = 0.3;
uniform float trail_strength : hint_range(0.0, 2.0) = 1.3;

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
	// Tete de la boule vers l'avant du quad (x ~ 0.78)
	vec2 head = vec2(0.78, 0.5);
	// Correction d'aspect (quad 3:1) pour une boule ronde
	vec2 p = (UV - head) * vec2(3.0, 1.0);
	float d = length(p);

	// Bruit anime qui defile vers l'arriere (donne vie a la trainee)
	float n = noise(vec2(UV.x * 8.0 + TIME * 6.0, UV.y * 6.0)) * 0.5
			+ noise(vec2(UV.x * 16.0 + TIME * 10.0, UV.y * 12.0 + TIME * 2.0)) * 0.25;

	// Trainee : resserree verticalement, s'estompe vers la queue (x -> 0)
	float trail = smoothstep(0.42, 0.0, abs(UV.y - 0.5))
			* smoothstep(0.0, 0.85, UV.x)
			* step(UV.x, head.x);
	trail *= n * trail_strength;

	// Boule : coeur dense + halo, bord ronge par le bruit
	float ball = smoothstep(ball_radius, ball_radius * 0.3, d + n * 0.16);
	float halo = smoothstep(ball_radius * 2.0, ball_radius * 0.5, d) * 0.5;

	float intensity = max(ball * 1.25, max(trail, halo));

	// Palette : sombre -> rouge sang -> coeur clair
	vec3 col = mix(outer_color.rgb, blood_color.rgb, smoothstep(0.12, 0.55, intensity));
	col = mix(col, core_color.rgb, smoothstep(0.78, 1.05, intensity));

	float alpha = smoothstep(0.10, 0.32, intensity);
	COLOR = vec4(col, alpha);
}
