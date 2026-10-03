shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;
// PILIER DE FOUDRE (2 oct. 2026) — le pilier, UN DESSIN
// (MEDIA/INTERACTIBLE/pillier_de_foudre.png) : une colonne de pierre bleue à
// volutes, une bande claire le long de son axe, trois anneaux, une COUPE à
// deux cornes. Le shader pose le dessin tel quel (1 pixel du dessin = 1 pixel
// du jeu, avec le filtre du nœud, celui des autres décors) et ajoute ce qui
// n'est pas dessiné :
//   • le JOYAU : un cristal taillé (quatre facettes en aplat) qui repose dans le
//     creux de la coupe, entre les cornes ;
//   • la lumière, pilotée par SCRIPT/INTERACTIBLE/pilier_foudre.gd :
//     `eveil` : il est à l'écran, il veille — le joyau luit doucement ;
//     `charge` (0 → 1) : il va appeler la foudre — la lumière MONTE du pied à la
//     coupe le long de la bande claire de son axe (seulement là où cette
//     bande se voit sur son dessin : ses anneaux, qui passent devant, restent
//     sombres), le joyau s'embrase et éclaire la coupe, de petits arcs
//     crépitent entre les cornes et le joyau ;
//     `appel` (1 → 0) : l'éclair d'appel part vers le ciel — tout flashe.
// La pierre est opaque ; la lumière s'AJOUTE (alpha prémultiplié) et s'éteint
// avant le bord du rectangle (aucun carré de lueur).
// (Avant ce dessin, le pilier était tracé ici : socle, fût en assises, rune
// d'éclair, anneaux de cuivre, griffes de fer.)
// Repère : `base` = le pied du pilier, au ras du sol, dans le rectangle ; le bas
// de son dessin y est posé, son axe au milieu.

uniform vec2 taille = vec2(260.0, 510.0);
uniform vec2 base = vec2(130.0, 500.0);
uniform sampler2D dessin : repeat_disable;
uniform float eveil : hint_range(0.0, 1.0) = 0.0;
uniform float charge : hint_range(0.0, 1.0) = 0.0;
uniform float appel : hint_range(0.0, 1.0) = 0.0;
uniform float temps = 0.0;

uniform float hauteur_cristal = 372.0;           // le milieu du joyau, au-dessus du pied (l'arc d'appel part de là)
uniform vec2 demi_cristal = vec2(15.0, 26.0);    // sa demi-largeur, sa demi-hauteur
uniform vec2 corne = vec2(53.5, 362.0);          // le bout d'une corne de la coupe : de part et d'autre de l'axe, au-dessus du pied
uniform float creux = 342.0;                     // le fond de la coupe, au-dessus du pied
uniform float demi_bande = 4.0;                  // la bande claire de son axe (demi-largeur)

uniform vec4 couleur : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 couleur_foudre : source_color = vec4(0.45, 0.72, 1.0, 1.0);


float alea(vec2 c) {
	return fract(sin(dot(c, vec2(127.1, 311.7))) * 43758.5453);
}

float couvre(float d, float px) {
	return clamp(0.5 - d / px, 0.0, 1.0);
}

vec4 sur(vec4 dst, vec4 src) {
	float a = src.a + dst.a * (1.0 - src.a);
	vec3 rgb = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 0.0001);
	return vec4(rgb, a);
}

float clarte(vec4 t) {
	return dot(t.rgb, vec3(0.299, 0.587, 0.114));
}

float segment(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

void fragment() {
	vec2 pix = UV * taille;
	float px = max(fwidth(pix.x), 0.001);
	vec2 p = pix - base;                             // y vers le bas, 0 = le sol
	vec3 lum = vec3(0.0);
	float vif = clamp(0.25 * eveil + 0.75 * charge, 0.0, 1.0);
	float bat = 0.85 + 0.15 * sin(temps * 9.0);
	float hc = hauteur_cristal;

	// ===================== SON DESSIN : le bas posé au sol, l'axe au milieu =====================
	vec2 sz = vec2(textureSize(dessin, 0));
	vec2 uv = (p + vec2(sz.x * 0.5, sz.y)) / sz;
	vec4 pierre = texture(dessin, uv);
	if (uv.x <= 0.0 || uv.y <= 0.0 || uv.x >= 1.0 || uv.y >= 1.0) {
		pierre = vec4(0.0);
	}
	vec4 c = pierre;

	// ===================== LA LUMIÈRE QUI MONTE le long de la bande de son axe (charge) =====================
	float haut_bande = creux - 2.0;
	float niveau = mix(20.0, -haut_bande, charge);          // elle part de sous le pied
	// la bande ne s'allume que là où elle se voit : plus claire que la pierre de
	// part et d'autre (ses anneaux, qui passent devant, la cachent). Lu sur
	// sept rangées : une fissure fine l'atténue à peine, en douceur (lue sur une
	// seule rangée, elle coupait le faisceau d'un trait net ; sur trois rangées
	// espacées, elle faisait trois rayures)
	float bande_visible = 0.0;
	if (abs(p.x) < 40.0 && (charge > 0.005 || appel > 0.0)) {
		vec2 a_cote = vec2(11.0 / sz.x, 0.0);
		for (int k = -3; k <= 3; k++) {
			vec2 uv_axe = vec2(0.5, uv.y + float(k) / sz.y);
			bande_visible += smoothstep(0.004, 0.03, clarte(textureLod(dessin, uv_axe, 0.0))
					- 0.5 * (clarte(textureLod(dessin, uv_axe - a_cote, 0.0)) + clarte(textureLod(dessin, uv_axe + a_cote, 0.0)))) / 7.0;
		}
	}
	float dans_bande = step(-haut_bande, p.y) * step(p.y, 0.0) * pierre.a * bande_visible;
	float rempli = step(niveau, p.y) * dans_bande * step(0.01, charge);
	float d_bande = max(abs(p.x) - demi_bande * 0.45, 0.0);
	lum += couleur_foudre.rgb * exp(-pow(d_bande / (demi_bande * 0.9), 2.0)) * rempli * (0.6 + 0.4 * bat) * 1.1;
	lum += couleur.rgb * exp(-pow(abs(p.x) / (demi_bande * 0.4), 2.0)) * rempli * 0.75;
	// sa tête, plus vive, là où elle en est
	lum += couleur.rgb * exp(-pow((p.y - niveau) / 7.0, 2.0)) * exp(-pow(abs(p.x) / (demi_bande * 1.6), 2.0)) * dans_bande
			* step(0.01, charge) * (1.0 - smoothstep(0.9, 1.0, charge)) * 0.9;
	// une lueur douce qui déborde sur la pierre
	lum += couleur_foudre.rgb * exp(-abs(p.x) / 12.0) * rempli * 0.16;

	// ===================== LE JOYAU, taillé : quatre facettes en aplat =====================
	vec2 qc = p - vec2(0.0, -hc);
	float d_cristal = (abs(qc.x) / demi_cristal.x + abs(qc.y) / demi_cristal.y - 1.0) * min(demi_cristal.x, demi_cristal.y) * 0.85;
	// claire à gauche, sombre à droite ; le haut plus clair que le bas
	float ton = (qc.x < 0.0 ? 1.0 : 0.56) * (qc.y < 0.0 ? 1.0 : 0.8);
	vec3 face = mix(couleur_foudre.rgb, couleur.rgb, qc.x < 0.0 && qc.y < 0.0 ? 0.45 : 0.12) * ton;
	face = mix(face * 0.45, face, 0.35 + 0.65 * vif);
	// ses arêtes : celle du milieu, et la ceinture
	float arete = max(couvre(abs(qc.x) - 0.6, px), couvre(abs(qc.y) - 0.6, px) * 0.6);
	face = mix(face, couleur.rgb, arete * 0.5 * (0.4 + 0.6 * vif));
	c = sur(c, vec4(face, couvre(d_cristal, px)));
	// sa lumière (gaussienne : elle s'éteint avant le bord)
	float r_c = length(qc);
	lum += couleur_foudre.rgb * exp(-pow(r_c / 34.0, 2.0)) * (0.25 * eveil + 0.9 * charge) * bat;
	lum += couleur.rgb * exp(-pow(r_c / 13.0, 2.0)) * charge * 0.8 * bat;
	// … qui éclaire la coupe et les anneaux, sur la pierre seulement
	lum += couleur_foudre.rgb * exp(-pow(r_c / 80.0, 2.0)) * pierre.a * (0.06 * eveil + 0.3 * charge) * bat;

	// ===================== LES ARCS QUI CRÉPITENT (charge) : des cornes au joyau =====================
	if (charge > 0.05) {
		for (int k = 0; k < 3; k++) {
			float fk = float(k);
			float graine_arc = floor(temps * 18.0 + fk * 7.0);
			if (alea(vec2(graine_arc, fk)) > charge * 0.9) {
				continue;
			}
			float cote = k == 0 ? -1.0 : 1.0;
			vec2 a = vec2(cote * corne.x, -corne.y);
			if (k == 2) {
				a = vec2(0.0, -creux);
			}
			vec2 b = vec2((alea(vec2(graine_arc, fk + 3.0)) - 0.5) * demi_cristal.x, -hc + (alea(vec2(graine_arc, fk + 5.0)) - 0.5) * demi_cristal.y);
			// un petit zigzag de 3 segments
			vec2 m1 = mix(a, b, 0.33) + vec2(0.0, (alea(vec2(graine_arc, fk + 9.0)) - 0.5) * 14.0);
			vec2 m2 = mix(a, b, 0.66) + vec2(0.0, (alea(vec2(graine_arc, fk + 11.0)) - 0.5) * 14.0);
			float da = min(segment(p, a, m1), min(segment(p, m1, m2), segment(p, m2, b)));
			lum += couleur.rgb * couvre(da - 0.6, px) * 0.9 + couleur_foudre.rgb * exp(-da / 3.5) * 0.6;
		}
	}

	// ===================== L'APPEL : tout flashe =====================
	if (appel > 0.0) {
		lum += couleur.rgb * exp(-pow(r_c / 20.0, 2.0)) * appel * 2.4;
		lum += couleur_foudre.rgb * exp(-pow(r_c / 52.0, 2.0)) * appel * 0.9;
		// la bande entière s'illumine
		lum += couleur_foudre.rgb * exp(-pow(d_bande / (demi_bande * 1.1), 2.0)) * dans_bande * appel * 1.2;
	}

	// la lumière s'éteint avant le bord du rectangle (aucun carré)
	float bord = min(min(pix.x, taille.x - pix.x), min(pix.y, taille.y - pix.y));
	lum *= smoothstep(0.0, 16.0, bord);
	COLOR = vec4(c.rgb * c.a + lum, c.a);
}
