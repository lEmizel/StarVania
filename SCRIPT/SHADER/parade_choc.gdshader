shader_type canvas_item;
render_mode unshaded;
// CHOC DE PARADE (1er oct. 2026) — talisman « Parade » : le « clang » de deux
// lames qui se croisent, là où l'épée du héros pare un coup. Distinct de
// l'étoile d'un coup qui porte : deux reflets de lame en X, un éclair rond au
// croisement, des étincelles qui fusent et un anneau fin qui s'élargit — en
// 0,22 s. Blanc d'acier cerné d'encre, comme l'éclat d'un coup d'épée.
// Repère : des pixels, l'origine au milieu du rectangle (le point de contact).

// --- fournis par parade_choc.gd ---------------------------------------------
uniform vec2 taille = vec2(240.0, 240.0);
// 0 → 1 : le choc
uniform float progress : hint_range(0.0, 1.0) = 0.2;
// une valeur par choc : deux chocs n'ont pas les mêmes étincelles
uniform float graine = 0.0;
// ----------------------------------------------------------------------------

// les deux reflets de lame : demi-longueur (px : au départ, à la fin), demi-
// épaisseur au milieu (px), leur angle par rapport à l'horizontale (rad)
uniform vec2 longueur_lames = vec2(62.0, 92.0);
uniform float epaisseur_lames = 7.0;
uniform float angle_lames = 0.62;
uniform int nb_etincelles : hint_range(0, 16) = 9;
// l'anneau : rayon (px : départ, fin)
uniform vec2 rayon_anneau = vec2(14.0, 96.0);
uniform float encre_px : hint_range(0.0, 4.0) = 2.0;
uniform vec4 couleur : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 encre : source_color = vec4(0.05, 0.03, 0.06, 1.0);

const int NB_MAX = 16;

void par_dessus(inout vec3 rgb, inout float a, vec3 teinte, float f) {
	float total = f + a * (1.0 - f);
	rgb = (teinte * f + rgb * a * (1.0 - f)) / max(total, 0.0001);
	a = total;
}

float alea(float n) {
	return fract(sin(n * 12.9898 + 4.1414) * 43758.5453);
}

// un reflet de lame : un fuseau le long de `u`, demi-longueur L, demi-
// épaisseur W au milieu (positif dedans, en px)
float fuseau(vec2 q, vec2 u, float L, float W) {
	float le_long = dot(q, u);
	float travers = dot(q, vec2(-u.y, u.x));
	float t = clamp(le_long / max(L, 0.001), -1.0, 1.0);
	return min(W * (1.0 - t * t) - abs(travers), L - abs(le_long));
}

// une forme cernée d'encre, posée par-dessus
void forme(inout vec3 rgb, inout float a, float d, float o) {
	par_dessus(rgb, a, encre.rgb, smoothstep(-0.5, 0.5, d + encre_px) * o);
	par_dessus(rgb, a, couleur.rgb, smoothstep(-0.5, 0.5, d) * o);
}

void fragment() {
	vec2 p = (UV - 0.5) * taille;
	float t = clamp(progress, 0.0, 1.0);
	float vite = 1.0 - (1.0 - t) * (1.0 - t);        // part vite, ralentit
	vec3 rgb = couleur.rgb;
	float a = 0.0;

	// ---- l'anneau fin qui s'élargit (derrière) ----
	float ra = mix(rayon_anneau.x, rayon_anneau.y, vite);
	float ea = 3.0 * (1.0 - t);
	forme(rgb, a, ea - abs(length(p) - ra), 1.0 - smoothstep(0.55, 1.0, t));

	// ---- les étincelles qui fusent ----
	for (int i = 0; i < NB_MAX; i++) {
		if (i >= nb_etincelles) {
			break;
		}
		float fi = float(i);
		float ang = (fi + 0.5 * alea(fi + graine)) / float(nb_etincelles) * TAU;
		vec2 u = vec2(cos(ang), sin(ang));
		float r0 = mix(16.0, 30.0, alea(fi * 3.1 + graine));
		float r1 = mix(70.0, 115.0, alea(fi * 5.3 + graine));
		float r = mix(r0, r1, vite);
		float l = mix(16.0, 6.0, t) * mix(0.7, 1.2, alea(fi * 7.7 + graine));
		float w = 2.6 * (1.0 - t);
		forme(rgb, a, fuseau(p - u * r, u, l, w), 1.0 - smoothstep(0.7, 1.0, t));
	}

	// ---- les deux reflets de lame, en X ----
	float L = mix(longueur_lames.x, longueur_lames.y, vite);
	float W = epaisseur_lames * (1.0 - smoothstep(0.25, 1.0, t));
	vec2 u1 = vec2(cos(angle_lames), sin(angle_lames));
	vec2 u2 = vec2(cos(-angle_lames), sin(-angle_lames));
	float lames = max(fuseau(p, u1, L, W), fuseau(p, u2, L, W));
	forme(rgb, a, lames, 1.0 - smoothstep(0.75, 1.0, t));

	// ---- l'éclair rond au croisement, qui s'éteint vite ----
	float rc = 20.0 * (1.0 - smoothstep(0.0, 0.35, t));
	forme(rgb, a, rc - length(p), step(0.001, rc));

	COLOR = vec4(rgb, a);
}
