shader_type canvas_item;
render_mode unshaded;
// POISON DU SANG CORROMPU (1er oct. 2026) — talisman « Sang corrompu » : une
// fumée violette monte de l'ennemi empoisonné. Des VOLUTES naissent sur tout
// son corps, montent en ralentissant, s'élargissent et s'effacent, puis
// renaissent ailleurs. À chaque morsure du poison
// (`morsure` → 1), elles enflent un instant. Deux tons à plat (violet, cœur
// mauve), translucides, sans trait d'encre ni reflet : cernées et brillantes,
// elles faisaient des billes collées sur le squelette (v1, jugée sur
// capture). Aucun blanc.
// Repère : des pixels ; `origine` = le milieu du corps, dans le rectangle.

// --- fournis par poison_sang.gd ---------------------------------------------
uniform vec2 taille = vec2(160.0, 280.0);
uniform vec2 origine = vec2(80.0, 190.0);
// 0 → 1 : le poison apparaît ; 1 → 0 : il s'éteint
uniform float force : hint_range(0.0, 1.0) = 1.0;
// 1 au moment d'une morsure, retombe à 0
uniform float morsure : hint_range(0.0, 1.0) = 0.0;
// l'horloge des volutes (s) ; une valeur par ennemi
uniform float temps = 0.0;
uniform float graine = 0.0;
// ----------------------------------------------------------------------------

// combien de volutes ; où elles naissent (px : demi-largeur, et hauteur au-
// dessus du milieu du corps — elles partent aussi un peu en dessous) ; leur
// rayon une fois montées (px : min, max) ; la hauteur d'une montée (px) ; la
// durée d'une vie (s : min, max). Nées trop haut et montant trop, elles
// faisaient un panache sur la tête, une flamme violette plus qu'un poison.
uniform int nb_volutes : hint_range(1, 12) = 9;
uniform vec2 etendue = vec2(26.0, 60.0);
uniform vec2 grosseur = vec2(7.0, 12.0);
uniform float montee = 70.0;
uniform vec2 cycle = vec2(0.9, 1.4);
// leur opacité au plus fort (la fumée laisse voir l'ennemi)
uniform float opacite : hint_range(0.0, 1.0) = 0.5;
// étirées en hauteur : 1 = rondes
uniform float etirement : hint_range(0.3, 1.0) = 0.62;
uniform vec4 couleur : source_color = vec4(0.56, 0.13, 0.8, 1.0);
uniform vec4 clair : source_color = vec4(0.8, 0.52, 1.0, 1.0);

const int NB_MAX = 12;

void par_dessus(inout vec3 rgb, inout float a, vec3 teinte, float f) {
	float total = f + a * (1.0 - f);
	rgb = (teinte * f + rgb * a * (1.0 - f)) / max(total, 0.0001);
	a = total;
}

float alea(float n) {
	return fract(sin(n * 12.9898 + 4.1414) * 43758.5453);
}

float hachis(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float bruit(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hachis(i), hachis(i + vec2(1.0, 0.0)), u.x),
			mix(hachis(i + vec2(0.0, 1.0)), hachis(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec2 p = UV * taille - origine;
	vec3 rgb = couleur.rgb;
	float a = 0.0;
	float f = clamp(force, 0.0, 1.0);
	for (int i = 0; i < NB_MAX; i++) {
		if (i >= nb_volutes) {
			break;
		}
		float fi = float(i);
		// sa vie en cours (la k-ième) et où elle en est (0 → 1)
		float periode = mix(cycle.x, cycle.y, alea(fi * 2.9 + graine * 1.3 + 41.0));
		float u = temps / max(periode, 0.05) + alea(fi * 4.7 + graine * 0.9 + 53.0);
		float k = floor(u);
		float vie = u - k;
		// chaque vie naît ailleurs sur le haut du corps, avec une autre taille
		float s = graine + k * 3.71;
		float h1 = alea(fi * 1.7 + s);
		float h2 = alea(fi * 3.3 + s * 1.9 + 7.0);
		float h3 = alea(fi * 5.1 + s * 0.7 + 13.0);
		vec2 ou = vec2((h1 * 2.0 - 1.0) * etendue.x, mix(etendue.y * 0.35, -etendue.y, h2));
		// elle monte en ralentissant, en ondulant de plus en plus
		ou.y -= montee * (1.0 - (1.0 - vie) * (1.0 - vie));
		ou.x += sin(vie * 4.0 + h3 * 6.28) * 7.0 * vie;
		// elle s'élargit en montant (de la fumée), plus encore à la morsure
		float r = mix(grosseur.x, grosseur.y, h3) * mix(0.35, 1.0, smoothstep(0.0, 0.6, vie));
		r *= f * (1.0 + 0.3 * morsure);
		float o = opacite * f * smoothstep(0.0, 0.12, vie) * (1.0 - smoothstep(0.45, 1.0, vie));
		if (r < 0.3 || o <= 0.001) {
			continue;
		}
		vec2 q = p - ou;
		q.y *= etirement;
		// son bord rongé par un bruit qui monte avec elle
		float n = bruit(q * 0.2 + vec2(fi * 7.0 + k * 3.0, temps * 1.8)) - 0.5;
		float d = r - length(q) + n * r * 0.6;
		// deux tons à plat : le violet, et un cœur mauve
		par_dessus(rgb, a, couleur.rgb, smoothstep(-0.8, 0.8, d) * o);
		par_dessus(rgb, a, clair.rgb, smoothstep(-0.8, 0.8, d - r * 0.5) * o * 0.55);
	}
	COLOR = vec4(rgb, a);
}
