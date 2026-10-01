shader_type canvas_item;
render_mode unshaded;
// COUP DE GRÂCE (1er oct. 2026) — talisman « Coup de grâce » : l'ennemi
// fissuré qu'on achève VOLE EN ÉCLATS. Un éclat rouge bref au centre, un
// anneau fin qui s'élargit, et des ÉCLATS anguleux qui jaillissent en tournant,
// retombent un peu et s'effacent — en 0,45 s. Aplats rouges (deux tons) cernés
// d'encre, aucun blanc (les effets de sang du jeu sont sobres).
// Repère : des pixels, l'origine au milieu du rectangle (le milieu de l'ennemi).

// --- fournis par grace_eclats.gd ---------------------------------------------
uniform vec2 taille = vec2(320.0, 320.0);
uniform float progress : hint_range(0.0, 1.0) = 0.3;
uniform float graine = 0.0;
// ----------------------------------------------------------------------------

uniform int nb_eclats : hint_range(3, 20) = 13;
// jusqu'où ils filent (px : min, max) ; leur taille (px : min, max)
uniform vec2 portee = vec2(70.0, 140.0);
uniform vec2 grosseur = vec2(10.0, 22.0);
// la retombée (px à la fin)
uniform float chute = 50.0;
uniform float encre_px : hint_range(0.0, 4.0) = 2.0;
uniform vec4 couleur : source_color = vec4(0.86, 0.06, 0.12, 1.0);
uniform vec4 sombre : source_color = vec4(0.4, 0.01, 0.07, 1.0);
uniform vec4 vive : source_color = vec4(1.0, 0.25, 0.25, 1.0);
uniform vec4 encre : source_color = vec4(0.08, 0.02, 0.04, 1.0);

const int NB_MAX = 20;

void par_dessus(inout vec3 rgb, inout float a, vec3 teinte, float f) {
	float total = f + a * (1.0 - f);
	rgb = (teinte * f + rgb * a * (1.0 - f)) / max(total, 0.0001);
	a = total;
}

float alea(float n) {
	return fract(sin(n * 12.9898 + 4.1414) * 43758.5453);
}

// distance signée à un triangle (négative dedans) — Inigo Quilez
float sd_triangle(vec2 p, vec2 p0, vec2 p1, vec2 p2) {
	vec2 e0 = p1 - p0, e1 = p2 - p1, e2 = p0 - p2;
	vec2 v0 = p - p0, v1 = p - p1, v2 = p - p2;
	vec2 pq0 = v0 - e0 * clamp(dot(v0, e0) / dot(e0, e0), 0.0, 1.0);
	vec2 pq1 = v1 - e1 * clamp(dot(v1, e1) / dot(e1, e1), 0.0, 1.0);
	vec2 pq2 = v2 - e2 * clamp(dot(v2, e2) / dot(e2, e2), 0.0, 1.0);
	float s = sign(e0.x * e2.y - e0.y * e2.x);
	vec2 d = min(min(vec2(dot(pq0, pq0), s * (v0.x * e0.y - v0.y * e0.x)),
			vec2(dot(pq1, pq1), s * (v1.x * e1.y - v1.y * e1.x))),
			vec2(dot(pq2, pq2), s * (v2.x * e2.y - v2.y * e2.x)));
	return -sqrt(d.x) * sign(d.y);
}

// une forme (positive dedans) cernée d'encre
void forme(inout vec3 rgb, inout float a, float d, vec3 teinte, float o) {
	par_dessus(rgb, a, encre.rgb, smoothstep(-0.5, 0.5, d + encre_px) * o);
	par_dessus(rgb, a, teinte, smoothstep(-0.5, 0.5, d) * o);
}

void fragment() {
	vec2 p = (UV - 0.5) * taille;
	float t = clamp(progress, 0.0, 1.0);
	float vite = 1.0 - (1.0 - t) * (1.0 - t);
	vec3 rgb = couleur.rgb;
	float a = 0.0;

	// ---- l'anneau fin qui s'élargit (derrière) ----
	float ra = mix(16.0, 130.0, vite);
	forme(rgb, a, 3.5 * (1.0 - t) - abs(length(p) - ra), couleur.rgb, 1.0 - smoothstep(0.5, 0.9, t));

	// ---- l'éclat rouge au centre, bref ----
	float rc = 38.0 * (1.0 - smoothstep(0.0, 0.3, t));
	forme(rgb, a, rc - length(p), vive.rgb, step(0.001, rc));

	// ---- les éclats ----
	for (int i = 0; i < NB_MAX; i++) {
		if (i >= nb_eclats) {
			break;
		}
		float fi = float(i);
		float h1 = alea(fi * 1.7 + graine);
		float h2 = alea(fi * 3.3 + graine * 1.9 + 7.0);
		float h3 = alea(fi * 5.1 + graine * 0.7 + 13.0);
		float ang = (fi + 0.6 * h1) / float(nb_eclats) * TAU;
		vec2 dir = vec2(cos(ang), sin(ang));
		vec2 c = dir * mix(8.0, mix(portee.x, portee.y, h2), vite) + vec2(0.0, chute * t * t);
		float s = mix(grosseur.x, grosseur.y, h3) * (1.0 - smoothstep(0.6, 1.0, t));
		if (s < 0.5) {
			continue;
		}
		// il tourne sur lui-même en volant
		float rot = ang + (h1 - 0.5) * 9.0 * t;
		vec2 q = p - c;
		q = vec2(cos(rot) * q.x + sin(rot) * q.y, -sin(rot) * q.x + cos(rot) * q.y);
		// un triangle effilé, pointe vers l'extérieur
		float d = -sd_triangle(q, vec2(s, 0.0), vec2(-s * 0.55, s * 0.42), vec2(-s * 0.4, -s * 0.5));
		vec3 teinte = mix(sombre.rgb, couleur.rgb, step(0.0, q.y));
		forme(rgb, a, d, teinte, 1.0);
	}
	COLOR = vec4(rgb, a);
}
