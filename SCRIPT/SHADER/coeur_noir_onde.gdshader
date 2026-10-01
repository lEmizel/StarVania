shader_type canvas_item;
render_mode unshaded;
// L'ONDE DU CŒUR NOIR (1er oct. 2026) — talisman « Cœur noir » (idée de
// Kaoru) : quand le cœur noir se brise, il ÉCLATE dans la poitrine du héros —
// une tache noire qui claque, des ÉCLATS de cœur noir (cernés d'un fil rouge)
// qui volent — et une ONDE noire, liserée de sang, part de lui et court jusqu'au
// bord de l'écran : chaque monstre qu'elle atteint est frappé (le script fait
// les dégâts au passage de l'onde).
// Sobre : du noir, un rouge sang, aucun blanc ; l'onde s'amincit et s'efface en
// s'éloignant.
// Repère : des pixels, l'origine au point d'éclatement (le milieu du rectangle).

// --- fournis par coeur_noir_onde.gd ------------------------------------------
uniform vec2 taille = vec2(1200.0, 1200.0);
// 0 → 1 : la course de l'onde (son rayon : `rayon_max` × une course qui ralentit)
uniform float progres : hint_range(0.0, 1.0) = 0.0;
uniform float rayon_max = 560.0;
// le temps depuis l'éclatement (s) : les éclats, la tache
uniform float temps = 0.0;
// ----------------------------------------------------------------------------

uniform float epaisseur = 22.0;
uniform float lisere = 3.0;
uniform vec4 couleur_noire : source_color = vec4(0.06, 0.01, 0.03, 1.0);
uniform vec4 couleur_sang : source_color = vec4(0.82, 0.05, 0.12, 1.0);

void par_dessus(inout vec3 rgb, inout float a, vec3 teinte, float f) {
	float total = f + a * (1.0 - f);
	rgb = (teinte * f + rgb * a * (1.0 - f)) / max(total, 0.0001);
	a = total;
}

float alea(float n) {
	return fract(sin(n * 12.9898 + 4.1414) * 43758.5453);
}

// un éclat : un triangle pointu (sommet vers l'extérieur), négatif dedans
float eclat(vec2 p, float l, float w) {
	p.x = abs(p.x);
	return max(p.x * l / w + p.y - l * 0.5, -p.y - l * 0.5) / sqrt(1.0 + (l / w) * (l / w));
}

void fragment() {
	vec2 p = (UV - 0.5) * taille;
	float r = length(p);
	vec3 rgb = couleur_noire.rgb;
	float a = 0.0;

	// ===================== L'ONDE =====================
	float pr = clamp(progres, 0.0, 1.0);
	float rayon = rayon_max * (1.0 - pow(1.0 - pr, 2.2));
	float ep = epaisseur * (1.0 - 0.6 * pr);
	float d = abs(r - rayon) - ep * 0.5;
	float vie = 1.0 - smoothstep(0.55, 1.0, pr);
	if (d < 6.0 && pr < 1.0) {
		// un anneau noir, plus dense sur son front, liseré de sang devant et derrière
		float m = smoothstep(1.0, -1.0, d);
		float front = smoothstep(rayon - ep * 0.5, rayon + ep * 0.5, r);
		par_dessus(rgb, a, couleur_noire.rgb, m * mix(0.45, 0.9, front) * vie);
		float fil = smoothstep(1.0, -0.5, abs(r - (rayon + ep * 0.5)) - lisere * 0.5);
		par_dessus(rgb, a, couleur_sang.rgb, fil * vie);
		float fil2 = smoothstep(1.0, -0.5, abs(r - (rayon - ep * 0.5)) - lisere * 0.3);
		par_dessus(rgb, a, couleur_sang.rgb, fil2 * 0.5 * vie);
	}

	// ===================== LA TACHE (le cœur qui claque) =====================
	// (petite et brève : plus grosse, elle restait collée au torse du héros)
	float tache_r = 18.0 * (0.4 + 1.2 * smoothstep(0.0, 0.08, temps)) * (1.0 - smoothstep(0.05, 0.18, temps));
	if (tache_r > 0.5) {
		par_dessus(rgb, a, couleur_noire.rgb, smoothstep(1.0, -1.0, r - tache_r));
		par_dessus(rgb, a, couleur_sang.rgb, smoothstep(1.0, -0.5, abs(r - tache_r) - 1.5));
	}

	// ===================== LES ÉCLATS =====================
	float te = clamp(temps / 0.55, 0.0, 1.0);
	if (te < 1.0) {
		for (int i = 0; i < 9; i++) {
			float fi = float(i);
			float ang = (fi + alea(fi) * 0.7) / 9.0 * TAU;
			vec2 dir = vec2(cos(ang), sin(ang));
			float loin = mix(70.0, 150.0, alea(fi * 3.1)) * (1.0 - pow(1.0 - te, 2.0)) + 60.0 * te * te * dir.y;
			vec2 c = dir * loin + vec2(0.0, 80.0 * te * te);
			// il tourne en volant
			float rot = ang + te * mix(-6.0, 6.0, alea(fi * 5.7));
			vec2 q = p - c;
			q = vec2(cos(rot) * q.x + sin(rot) * q.y, -sin(rot) * q.x + cos(rot) * q.y);
			float taille_e = mix(9.0, 16.0, alea(fi * 7.3)) * (1.0 - te * 0.6);
			float de = eclat(q, taille_e * 1.5, taille_e * 0.55);
			float vis = 1.0 - smoothstep(0.6, 1.0, te);
			par_dessus(rgb, a, couleur_sang.rgb, smoothstep(1.0, -1.0, de - 1.4) * vis);
			par_dessus(rgb, a, couleur_noire.rgb, smoothstep(1.0, -1.0, de) * vis);
		}
	}
	COLOR = vec4(rgb, a);
}
