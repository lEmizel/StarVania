shader_type canvas_item;
render_mode unshaded;
// DESSIN DU TALISMAN « ESSAIM » (menu START, 1er oct. 2026) — provisoire, en
// attendant le dessin de Kaoru.
// emplacement_talisman.gd le pose dans le rond et lui fournit `opacite`,
// `eveil` et `temps`.
// TOUT LE ROND est au dessin : un disque de nuit cerné d'un trait d'encre ; au
// fond une grande LUNE DE SANG barrée de deux nuages, que traversent trois
// chauves-souris lointaines en ombres d'encre ; devant, une grande
// CHAUVE-SOURIS EN ORIGAMI qui monte en travers du rond — la même qu'en jeu
// (chauve_souris_forme.gdshaderinc : aplats rouges cernés d'encre) — et une
// petite qui la suit. Pas de blanc. Pointé ou porté (`eveil`), toutes battent
// des ailes.
// À dessiner dans un CARRÉ : le disque le remplit.

#include "res://SCRIPT/SHADER/chauve_souris_forme.gdshaderinc"

// --- fournis par emplacement_talisman.gd (les mêmes pour tout dessin de talisman) ---
uniform float opacite : hint_range(0.0, 1.0) = 1.0;
uniform float eveil : hint_range(0.0, 1.0) = 0.0;
uniform float temps = 0.0;
// ----------------------------------------------------------------------------

uniform vec4 encre_color : source_color = vec4(0.1, 0.02, 0.04, 1.0);
uniform vec4 fond_color : source_color = vec4(0.06, 0.02, 0.04, 1.0);
uniform vec4 fond_centre : source_color = vec4(0.16, 0.03, 0.05, 1.0);
uniform float trait : hint_range(0.0, 0.1) = 0.045;
uniform vec4 couleur : source_color = vec4(0.78, 0.04, 0.12, 1.0);
uniform vec4 arriere : source_color = vec4(0.46, 0.02, 0.08, 1.0);
uniform vec4 sombre : source_color = vec4(0.32, 0.01, 0.06, 1.0);
uniform vec4 clair : source_color = vec4(1.0, 0.55, 0.52, 1.0);

float disque(float d, float r, float px) {
	return smoothstep(r + px * 0.5, r - px * 0.5, d);
}

// pose une chauve-souris : centre `c` (son épaule), `s` unités du rond par
// unité de chauve-souris, tournée de `rot` (rad, négatif = elle monte),
// ailes au repos `repos` battant de `amp` à la phase `ph`
void pose(inout vec3 rgb, inout float a, vec2 p, vec2 c, float s, float rot, float repos, float ph, float amp,
		vec3 teinte, vec3 teinte_loin, float e_px, float px) {
	vec2 b = cs_tourne(p - c, -rot) / s;
	float th = repos + amp * sin(ph);
	float th_loin = repos + amp * sin(ph + 0.5);
	float squash = mix(0.78, 1.0, abs(sin(ph)));
	cs_dessiner(rgb, a, b, th, th_loin, squash, teinte, teinte_loin, encre_color.rgb, e_px, s / px);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float px = fwidth(UV.x) * 2.0;

	vec3 rgb = encre_color.rgb;
	float a = disque(r, 1.0, px);
	float champ = disque(r, 1.0 - trait, px);
	rgb = mix(rgb, mix(fond_centre.rgb, fond_color.rgb, smoothstep(0.0, 0.95, r)), champ);

	vec3 f_rgb = couleur.rgb;
	float f_a = 0.0;

	// ===================== LA LUNE DE SANG =====================
	vec2 M = vec2(0.2, -0.22);
	float RM = 0.52;
	float dm = RM - length(p - M);
	cs_par_dessus(f_rgb, f_a, mix(sombre.rgb, couleur.rgb, 0.55), smoothstep(0.0, px, dm));
	// ses cratères, en aplats plus sombres
	float cr = max(max(0.09 - length(p - M - vec2(0.17, 0.13)), 0.065 - length(p - M - vec2(-0.21, -0.12))),
		0.045 - length(p - M - vec2(0.06, -0.3)));
	cs_par_dessus(f_rgb, f_a, mix(sombre.rgb, couleur.rgb, 0.25), smoothstep(0.0, px, min(cr, dm)));
	// un fil de lumière rouge clair sur son bord haut-gauche
	float cote = dot(normalize(p - M), normalize(vec2(-1.0, -1.1)));
	cs_par_dessus(f_rgb, f_a, clair.rgb, smoothstep(0.0, px, min(dm, 0.03 - dm)) * smoothstep(0.25, 0.85, cote) * 0.75);

	// ===================== LES NUAGES QUI LA BARRENT =====================
	// deux bandes à fond plat et dos bosselé, effilées aux deux bouts
	float y1 = M.y + 0.17;
	float l1 = clamp((p.x + 0.3) / 1.2, 0.0, 1.0);
	float n1 = min(y1 + 0.012 - p.y, p.y - (y1 - 0.012 - (0.022 + 0.02 * abs(sin(p.x * 13.0 + 0.4))) * sin(3.14159 * l1)));
	n1 = min(n1, min(p.x + 0.3, 0.9 - p.x));
	float y2 = M.y + 0.3;
	float l2 = clamp((p.x - 0.05) / 0.8, 0.0, 1.0);
	float n2 = min(y2 + 0.009 - p.y, p.y - (y2 - 0.009 - (0.015 + 0.014 * abs(sin(p.x * 16.0 + 2.0))) * sin(3.14159 * l2)));
	n2 = min(n2, min(p.x - 0.05, 0.85 - p.x));
	cs_par_dessus(f_rgb, f_a, mix(fond_centre.rgb, sombre.rgb, 0.5), smoothstep(0.0, px, max(n1, n2)));

	// ===================== AU LOIN, TROIS OMBRES D'ENCRE =====================
	float bat = temps * 9.0;
	float amp = 0.85 * eveil;
	pose(f_rgb, f_a, p, vec2(0.42, -0.5), 0.0045, -0.3, 0.5, bat + 0.0, amp, encre_color.rgb, encre_color.rgb, 0.0, px);
	pose(f_rgb, f_a, p, vec2(0.0, -0.4), 0.0036, -0.5, 0.2, bat + 1.7, amp, encre_color.rgb, encre_color.rgb, 0.0, px);
	pose(f_rgb, f_a, p, vec2(0.6, -0.1), 0.003, 0.1, 0.4, bat + 3.1, amp, encre_color.rgb, encre_color.rgb, 0.0, px);

	// ===================== DEVANT, LES CHAUVES-SOURIS DE PAPIER =====================
	// la petite qui suit, en bas à droite
	pose(f_rgb, f_a, p, vec2(0.5, 0.52), 0.0085, -0.35, 0.3, bat + 2.2, amp,
		couleur.rgb, arriere.rgb, 0.012 / px, px);
	// la grande, qui monte en travers du rond
	float flotte = 0.03 * sin(temps * 4.5) * eveil;
	pose(f_rgb, f_a, p, vec2(-0.2, 0.25 + flotte), 0.0165, -0.45, 0.35, bat + 0.8, amp,
		couleur.rgb, arriere.rgb, 0.02 / px, px);

	rgb = mix(rgb, f_rgb, f_a * champ);
	COLOR = vec4(rgb, a * opacite);
}
