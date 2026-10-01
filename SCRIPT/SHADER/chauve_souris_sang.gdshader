shader_type canvas_item;
render_mode unshaded;
// CHAUVE-SOURIS DE SANG (1er oct. 2026) — talisman « Essaim » : chaque ennemi
// tué par le joueur lâche des chauves-souris de sang qui fondent sur les
// ennemis proches et les mordent. Un ORIGAMI SIMPLE vu de côté, d'après le
// croquis de Kaoru (la silhouette : chauve_souris_forme.gdshaderinc). Sobre
// comme les autres effets de sang : des aplats rouges cernés d'encre, aucun
// blanc.
//   • elle vole vers +x : le nœud se tourne dans le sens du vol ;
//   • les ailes BATTENT autour de l'épaule, et raccourcissent au milieu de la
//     course (elles passent de biais) ;
//   • elle se DÉPLIE en sortant du cadavre (`apparition`) : à plat, ailes
//     pendantes, puis elle claque ouverte ;
//   • en mordant (`fin` avec `morsure` à 1), ses ailes se referment vers
//     l'avant sur sa proie, elle se ramasse et des gouttes en losange partent ;
//     sinon elle s'efface en s'en allant.
// Repère : l'origine est le MILIEU du rectangle, en pixels, y vers le bas ; la
// chauve-souris est dessinée en unités (l'épaule à l'origine) puis mise à
// l'échelle (`echelle` 1 = ~50 px de haut, ailes dressées).

#include "res://SCRIPT/SHADER/chauve_souris_forme.gdshaderinc"

// --- fournis par chauve_souris_sang.gd -------------------------------------
uniform vec2 taille = vec2(120.0, 110.0);
// où en est le battement (rad) : ailes en haut à π/2, en bas à 3π/2
uniform float phase = 0.0;
// angle moyen des ailes et amplitude du battement (rad ; + = levées)
uniform float repos = 0.35;
uniform float amplitude = 0.85;
// 0 → 1 : elle sort du cadavre
uniform float apparition : hint_range(0.0, 1.0) = 1.0;
// 0 → 1 : elle finit — en mordant si `morsure` vaut 1, en s'effaçant sinon
uniform float fin : hint_range(0.0, 1.0) = 0.0;
uniform float morsure : hint_range(0.0, 1.0) = 0.0;
// taille (1 = ~50 px de haut)
uniform float echelle = 1.0;
// sert à varier les gouttes d'une chauve-souris à l'autre
uniform float graine = 0.0;
// ----------------------------------------------------------------------------

// épaisseur du liseré d'encre (px, à l'échelle 1)
uniform float encre : hint_range(0.0, 4.0) = 1.5;
uniform vec4 couleur : source_color = vec4(0.78, 0.04, 0.12, 1.0);
uniform vec4 couleur_arriere : source_color = vec4(0.46, 0.02, 0.08, 1.0);
uniform vec4 couleur_encre : source_color = vec4(0.12, 0.0, 0.03, 1.0);

void fragment() {
	vec2 p = (UV - 0.5) * taille;
	float t_fin = clamp(fin, 0.0, 1.0);
	float eclate = step(0.5, morsure);
	float ap = clamp(apparition, 0.0, 1.0);

	// elle se déplie en sortant du cadavre : grandit un peu au-delà, puis se
	// pose ; en mordant elle se ramasse sur sa proie
	float ai = ap - 1.0;
	float sortie = 1.0 + 2.7 * ai * ai * ai + 1.7 * ai * ai;
	float k = echelle * mix(0.3, 1.0, sortie) * (1.0 - eclate * smoothstep(0.3, 0.9, t_fin));
	// `k` tombe à ZÉRO à la fin de la morsure : on divise ET on reconvertit en
	// pixels avec la MÊME échelle bornée. Reconvertir avec `k` (distance × 0 =
	// 0 px) mettait tout le rectangle « au bord » de la forme : un carré rouge
	// d'une image sur la cible à chaque morsure (Kaoru, 1er oct. 2026).
	float ks = max(k, 0.001);
	vec2 b = p / ks;
	// le papier est encore plié à plat à la naissance
	b.y /= mix(0.3, 1.0, smoothstep(0.0, 0.7, ap));

	// LE BATTEMENT : les deux ailes tournent autour de l'épaule, la lointaine
	// un peu en avance ; elles raccourcissent au milieu de la course
	float th = repos + amplitude * sin(phase);
	float th_loin = repos + amplitude * sin(phase + 0.5);
	float squash = mix(0.78, 1.0, abs(sin(phase)));
	// pendantes à la naissance, elles claquent ouvertes ; à la morsure elles
	// se referment vers l'avant sur la proie
	th = mix(-1.0, th, sortie);
	th_loin = mix(-1.0, th_loin, sortie);
	float serre = eclate * smoothstep(0.0, 0.45, t_fin);
	th = mix(th, 2.6, serre);
	th_loin = mix(th_loin, 2.4, serre);

	vec3 rgb = couleur.rgb;
	float a = 0.0;
	float e_px = max(encre * k, 1.0);
	cs_dessiner(rgb, a, b, th, th_loin, squash, couleur.rgb, couleur_arriere.rgb,
		couleur_encre.rgb, e_px, ks);
	// ramassée à rien, elle n'est plus là (son liseré d'un pixel resterait en
	// point au milieu des gouttes)
	a *= smoothstep(0.0, 0.12, k / max(echelle, 0.001));

	// LA MORSURE : des gouttes en losange partent du point mordu, devant elle
	if (eclate > 0.5 && t_fin > 0.0) {
		vec2 pg = (p - vec2(14.0, 0.0) * echelle) / max(echelle, 0.001);
		float ouvre = 1.0 - (1.0 - t_fin) * (1.0 - t_fin);
		float dg = -1000.0;
		for (int i = 0; i < 6; i++) {
			float fi = float(i);
			float ang = fi * 1.0472 + graine;
			float rr = mix(3.0, 30.0, ouvre) * (0.75 + 0.35 * fract(fi * 0.618 + graine));
			vec2 u = vec2(cos(ang), sin(ang));
			vec2 g = pg - u * rr;
			vec2 gl = vec2(dot(g, u), dot(g, vec2(-u.y, u.x)));
			float taille_g = max(4.5 * (1.0 - t_fin), 0.001);
			// un losange allongé dans le sens où il part
			dg = max(dg, (1.0 - (abs(gl.x) / (taille_g * 1.6) + abs(gl.y) / taille_g)) * taille_g);
		}
		float dg_px = dg * echelle;
		// réduites à rien, elles ne laissent pas un pixel derrière elles
		float reste = 1.0 - smoothstep(0.85, 1.0, t_fin);
		cs_par_dessus(rgb, a, couleur_encre.rgb, smoothstep(-0.5, 0.5, dg_px + max(encre * echelle, 1.0) * (1.0 - t_fin)) * reste);
		cs_par_dessus(rgb, a, couleur.rgb, smoothstep(-0.5, 0.5, dg_px) * reste);
	}

	// elle apparaît en un éclair, et s'efface si elle s'en va sans mordre
	a *= smoothstep(0.0, 0.3, ap);
	a *= 1.0 - (1.0 - eclate) * t_fin;
	COLOR = vec4(rgb, a);
}
