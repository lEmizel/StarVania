shader_type canvas_item;
render_mode unshaded;
// PLUME ACÉRÉE (1er oct. 2026) — talisman « Plumes acérées » : une plume de
// l'aile du double saut, devenue lame, qui fond vers le sol. La même plume à
// liseré que l'aile (aile_double_saut, plume_planee), plus effilée et plus
// pointue, pointe vers +x — le nœud la tourne dans le sens de sa course — avec
// un trait de vitesse derrière elle. Ses couleurs sont celles de l'aile
// (copiées par plume_aceree.gd).
// Repère : des pixels, l'origine au milieu du rectangle (le milieu de la plume).

// --- fournis par plume_aceree.gd ---------------------------------------------
uniform vec2 taille = vec2(150.0, 44.0);
// 1 = en vol ; descend vers 0 quand elle s'efface
uniform float opacite : hint_range(0.0, 1.0) = 1.0;
// 1 = le trait de vitesse au complet ; 0 = aucun (plantée)
uniform float trainee : hint_range(0.0, 1.0) = 1.0;
// ----------------------------------------------------------------------------

// longueur de la plume, sa demi-largeur au plus large (px), sa courbure — à
// 38 × 5,5 elles se perdaient en jeu
uniform float longueur = 46.0;
uniform float largeur = 6.5;
uniform float cambre = 0.06;
uniform float contour_px : hint_range(0.0, 4.0) = 1.6;
uniform vec4 couleur : source_color = vec4(0.647, 0.159, 0.236, 1.0);
uniform vec4 couleur_contour : source_color = vec4(0.207, 0.072, 0.111, 1.0);

void par_dessus(inout vec3 rgb, inout float a, vec3 teinte, float f) {
	float total = f + a * (1.0 - f);
	rgb = (teinte * f + rgb * a * (1.0 - f)) / max(total, 0.0001);
	a = total;
}

void fragment() {
	vec2 p = (UV - 0.5) * taille;
	vec3 rgb = couleur.rgb;
	float a = 0.0;

	// ---- le trait de vitesse, derrière la base (vers -x) ----
	float base = -longueur * 0.5;
	float fin = -taille.x * 0.5;
	float t = clamp((base - p.x) / max(base - fin, 1.0), 0.0, 1.0);   // 0 à la base → 1 au bout
	float epais = 1.4 * (1.0 - t);
	float trait_v = step(p.x, base) * smoothstep(-0.5, 0.5, epais - abs(p.y));
	par_dessus(rgb, a, couleur.rgb, trait_v * (1.0 - t) * 0.55 * trainee * opacite);

	// ---- la plume : de la base (s = 0) à la pointe (s = 1) ----
	float s = (p.x - base) / longueur;
	float large = largeur * min(s / 0.55, sqrt(max(1.0 - s, 0.0) / 0.45));
	float v = p.y - cambre * longueur * s * s;
	float d = min(large - abs(v), min(s, 1.0 - s) * longueur);
	par_dessus(rgb, a, couleur_contour.rgb, smoothstep(-0.5, 0.5, d + contour_px) * opacite);
	par_dessus(rgb, a, couleur.rgb, smoothstep(-0.5, 0.5, d) * opacite);
	// le rachis : un fil sombre au milieu, de la base aux deux tiers
	float rachis = min(0.6 - abs(v), min(s, 0.66 - s) * longueur);
	par_dessus(rgb, a, couleur_contour.rgb, smoothstep(-0.5, 0.5, rachis) * 0.7 * opacite);

	COLOR = vec4(rgb, a);
}
