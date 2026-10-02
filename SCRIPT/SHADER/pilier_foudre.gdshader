shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;
// PILIER DE FOUDRE (2 oct. 2026, piège imaginé par Kaoru) — le pilier, vu de
// côté, refait dans le style du pilon (Kaoru : « aussi beau que le pilon ») :
// un élément de DÉCOR, SANS contour — le volume vient des tons, la lumière
// vient d'en haut à gauche, la palette est celle de la pierre de ses décors.
//   • un SOCLE à deux marches, un FÛT de pierre en assises (joints d'un ton
//     plus sombre), une RUNE d'éclair gravée sur sa face ;
//   • trois anneaux de CUIVRE sous le CHAPITEAU cerclé de fer ;
//   • trois GRIFFES de fer qui tiennent un CRISTAL taillé (facettes claire et
//     sombre) ;
// piloté par SCRIPT/INTERACTIBLE/pilier_foudre.gd :
//   • `eveil` : il est à l'écran, il veille — le cristal luit doucement ;
//   • `charge` (0 → 1) : il va appeler la foudre — la rune se REMPLIT de
//     lumière de bas en haut, le cristal s'embrase, de petits arcs crépitent
//     entre les griffes et le cristal ;
//   • `appel` (1 → 0) : l'éclair d'appel part vers le ciel — tout flashe.
// La pierre est opaque ; la lumière s'AJOUTE (alpha prémultiplié) et s'éteint
// avant le bord du rectangle (aucun carré de lueur).

uniform vec2 taille = vec2(170.0, 315.0);
uniform vec2 base = vec2(85.0, 305.0);       // le pied du pilier, au ras du sol, dans le rectangle
uniform float eveil : hint_range(0.0, 1.0) = 0.0;
uniform float charge : hint_range(0.0, 1.0) = 0.0;
uniform float appel : hint_range(0.0, 1.0) = 0.0;
uniform float temps = 0.0;

uniform float hauteur_cristal = 222.0;       // le milieu du cristal, au-dessus du pied (l'arc d'appel part de là)

uniform vec4 pierre : source_color = vec4(0.46, 0.52, 0.63, 1.0);
uniform vec4 pierre_ombre : source_color = vec4(0.29, 0.34, 0.44, 1.0);
uniform vec4 pierre_lumiere : source_color = vec4(0.61, 0.66, 0.76, 1.0);
uniform vec4 fer : source_color = vec4(0.26, 0.28, 0.33, 1.0);
uniform vec4 fer_lumiere : source_color = vec4(0.5, 0.53, 0.59, 1.0);
uniform vec4 cuivre : source_color = vec4(0.55, 0.37, 0.27, 1.0);
uniform vec4 cuivre_lumiere : source_color = vec4(0.8, 0.57, 0.4, 1.0);
uniform vec4 couleur : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 couleur_foudre : source_color = vec4(0.45, 0.72, 1.0, 1.0);


float alea(vec2 c) {
	return fract(sin(dot(c, vec2(127.1, 311.7))) * 43758.5453);
}

// le hasard des nœuds du grain : ENTIER, exact. Le hasard flottant
// « fract(sin(n) × 43758) » pouvait rendre deux valeurs au même nœud selon le
// côté d'où on le calcule : des marches aux raccords (vues sur la faille de la
// pluie d'étoiles, 2 oct.)
float alea_noeud(vec2 i) {
	uint x = uint(int(i.x) + 4096);
	uint y = uint(int(i.y) + 4096);
	uint n = x * 7919u + y * 104729u;
	n = (n << 13u) ^ n;
	n = n * (n * n * 15731u + 789221u) + 1376312589u;
	return float(n & 2147483647u) / 2147483647.0;
}

float bruit(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 s = f * f * (3.0 - 2.0 * f);
	return mix(mix(alea_noeud(i), alea_noeud(i + vec2(1.0, 0.0)), s.x),
			mix(alea_noeud(i + vec2(0.0, 1.0)), alea_noeud(i + vec2(1.0, 1.0)), s.x), s.y);
}

float couvre(float d, float px) {
	return clamp(0.5 - d / px, 0.0, 1.0);
}

vec4 sur(vec4 dst, vec4 src) {
	float a = src.a + dst.a * (1.0 - src.a);
	vec3 rgb = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 0.0001);
	return vec4(rgb, a);
}

float boite(vec2 p, vec2 c, vec2 b, float r) {
	vec2 d = abs(p - c) - b + r;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - r;
}

float segment(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

// le modelé d'une pièce SANS contour (comme le pilon) : un dégradé du haut vers
// le bas, un filet de lumière sur les bords haut et gauche, une ombre sur les
// bords droit et bas, un grain de pierre
vec3 modele(vec2 p, vec2 c, vec2 b, vec3 base_c, vec3 clair, vec3 sombre, float grain) {
	vec2 q = (p - c) / b;
	vec3 col = mix(clair, base_c, smoothstep(-1.0, 0.2, q.y));
	col = mix(col, sombre, smoothstep(0.3, 1.0, q.y) * 0.55);
	col = mix(col, clair, max(smoothstep(-0.78, -1.0, q.x), smoothstep(-0.8, -1.0, q.y)) * 0.7);
	col = mix(col, sombre, max(smoothstep(0.7, 1.0, q.x), smoothstep(0.72, 1.0, q.y)) * 0.75);
	col *= 1.0 - grain * (bruit(p * 0.18) - 0.5) * 0.09;
	return col;
}

void fragment() {
	vec2 pix = UV * taille;
	float px = max(fwidth(pix.x), 0.001);
	vec2 p = pix - base;                             // y vers le bas, 0 = le sol
	vec4 c = vec4(pierre.rgb, 0.0);
	vec3 lum = vec3(0.0);
	float vif = clamp(0.25 * eveil + 0.75 * charge, 0.0, 1.0);
	float bat = 0.85 + 0.15 * sin(temps * 9.0);

	// ===================== LE SOCLE (deux marches) =====================
	vec2 c1 = vec2(0.0, -7.0);
	vec2 b1 = vec2(34.0, 7.0);
	c = sur(c, vec4(modele(p, c1, b1, pierre.rgb, pierre_lumiere.rgb, pierre_ombre.rgb, 1.0), couvre(boite(p, c1, b1, 2.0), px)));
	vec2 c2 = vec2(0.0, -19.0);
	vec2 b2 = vec2(28.0, 5.5);
	c = sur(c, vec4(modele(p, c2, b2, pierre.rgb, pierre_lumiere.rgb, pierre_ombre.rgb, 1.0), couvre(boite(p, c2, b2, 2.0), px)));

	// ===================== LE FÛT, en assises =====================
	float y0 = -24.0;
	float y1 = -176.0;
	float t_fut = clamp((p.y - y0) / (y1 - y0), 0.0, 1.0);    // 0 au pied, 1 en haut
	float demi = mix(20.0, 15.0, t_fut);
	float d_fut = max(abs(p.x) - demi, max(p.y - y0, y1 - p.y));
	vec2 cf = vec2(0.0, (y0 + y1) * 0.5);
	vec2 bf = vec2(demi, (y0 - y1) * 0.5);
	vec3 col_fut = modele(p, cf, bf, pierre.rgb, pierre_lumiere.rgb, pierre_ombre.rgb, 1.0);
	// les joints entre les assises : un ton plus sombre, pas un trait d'encre
	float assise = 38.0;
	float joint = abs(fract((p.y - y0) / assise) - 0.0) * assise;
	joint = min(joint, assise - joint);
	col_fut = mix(col_fut, pierre_ombre.rgb * 0.9, couvre(joint - 0.8, px) * 0.7);
	// chaque assise un peu différente
	float n_assise = floor((p.y - y0) / assise);
	col_fut *= 0.96 + 0.08 * alea(vec2(n_assise, 3.1));
	// la rune d'éclair gravée sur la face : un sillon en zigzag
	float d_rune = 1000.0;
	vec2 r0 = vec2(-4.0, -44.0);
	vec2 rs[5] = vec2[5](vec2(5.0, -72.0), vec2(-5.0, -100.0), vec2(6.0, -128.0), vec2(-3.0, -150.0), vec2(2.0, -162.0));
	vec2 prec = r0;
	for (int k = 0; k < 5; k++) {
		d_rune = min(d_rune, segment(p, prec, rs[k]));
		prec = rs[k];
	}
	float sillon = couvre(d_rune - 2.2, px) * step(d_fut, 0.0);
	col_fut = mix(col_fut, pierre_ombre.rgb * 0.75, sillon * 0.85);
	c = sur(c, vec4(col_fut, couvre(d_fut, px)));
	// la rune se remplit de lumière, de bas en haut, pendant la charge
	float niveau = mix(y0 - 20.0, -170.0, charge);
	float rempli = step(niveau, p.y) * step(d_fut, 0.0);
	lum += couleur_foudre.rgb * exp(-pow(abs(d_rune) / 2.0, 2.0)) * rempli * (0.6 + 0.4 * bat) * 1.4 * step(0.01, charge);
	lum += couleur.rgb * couvre(d_rune - 0.9, px) * rempli * step(0.01, charge) * 0.9;
	// une lueur douce qui sort du sillon
	lum += couleur_foudre.rgb * exp(-d_rune / 9.0) * rempli * 0.25 * step(0.01, charge);

	// ===================== LES ANNEAUX DE CUIVRE =====================
	for (int k = 0; k < 3; k++) {
		float yk = -150.0 - float(k) * 9.0;
		float dk = mix(20.0, 15.0, clamp((yk - y0) / (y1 - y0), 0.0, 1.0)) + 3.0;
		vec2 ck = vec2(0.0, yk);
		vec2 bk = vec2(dk, 3.0);
		vec3 col_k = modele(p, ck, bk, cuivre.rgb, cuivre_lumiere.rgb, cuivre.rgb * 0.6, 0.0);
		c = sur(c, vec4(col_k, couvre(boite(p, ck, bk, 1.5), px)));
		// le cuivre s'allume un peu quand il charge
		lum += couleur_foudre.rgb * couvre(boite(p, ck, bk, 1.5), px) * charge * 0.25 * bat;
	}

	// ===================== LE CHAPITEAU, cerclé de fer =====================
	vec2 cc = vec2(0.0, -184.0);
	vec2 bc = vec2(24.0, 8.0);
	c = sur(c, vec4(modele(p, cc, bc, pierre.rgb, pierre_lumiere.rgb, pierre_ombre.rgb, 1.0), couvre(boite(p, cc, bc, 2.5), px)));
	vec2 cb = vec2(0.0, -182.0);
	vec2 bb = vec2(25.0, 2.6);
	c = sur(c, vec4(modele(p, cb, bb, fer.rgb, fer_lumiere.rgb, fer.rgb * 0.7, 0.0), couvre(boite(p, cb, bb, 1.0), px)));

	// ===================== LES GRIFFES DE FER =====================
	float hc = hauteur_cristal;
	for (int k = 0; k < 3; k++) {
		float fk = float(k) - 1.0;                   // -1, 0, 1
		vec2 pied = vec2(fk * 15.0, -192.0);
		vec2 coude = vec2(fk * 19.0, -210.0);
		vec2 bout = vec2(fk * 9.0, -hc - 14.0 + abs(fk) * 4.0);
		if (k == 1) {
			// la griffe du milieu passe derrière le cristal : plus sombre, plus fine
			pied = vec2(0.0, -192.0);
			coude = vec2(0.0, -200.0);
			bout = vec2(0.0, -206.0);
		}
		float dg = min(segment(p, pied, coude) - 3.2, segment(p, coude, bout) - 2.4);
		vec3 col_g = mix(fer_lumiere.rgb, fer.rgb, smoothstep(-3.0, 3.0, p.x - mix(pied.x, bout.x, 0.5) + 1.5));
		c = sur(c, vec4(col_g, couvre(dg, px)));
	}

	// ===================== LE CRISTAL, taillé =====================
	vec2 qc = p - vec2(0.0, -hc);
	vec2 dc = vec2(9.0, 16.0);
	float d_cristal = (abs(qc.x) / dc.x + abs(qc.y) / dc.y - 1.0) * min(dc.x, dc.y) * 0.85;
	// deux facettes : claire à gauche, sombre à droite, une arête au milieu
	vec3 face = qc.x < 0.0 ? mix(couleur_foudre.rgb, couleur.rgb, 0.35) : couleur_foudre.rgb * 0.62;
	face = mix(face * 0.45, face, 0.35 + 0.65 * vif);
	face = mix(face, couleur.rgb, couvre(abs(qc.x) - 0.6, px) * 0.5 * (0.4 + 0.6 * vif));
	c = sur(c, vec4(face, couvre(d_cristal, px)));
	// sa lumière (gaussienne : elle s'éteint avant le bord)
	float r_c = length(qc);
	lum += couleur_foudre.rgb * exp(-pow(abs(r_c) / 26.0, 2.0)) * (0.25 * eveil + 0.9 * charge) * bat;
	lum += couleur.rgb * exp(-pow(abs(r_c) / 9.0, 2.0)) * charge * 0.8 * bat;

	// ===================== LES ARCS QUI CRÉPITENT (charge) =====================
	if (charge > 0.05) {
		for (int k = 0; k < 3; k++) {
			float fk = float(k);
			float graine_arc = floor(temps * 18.0 + fk * 7.0);
			if (alea(vec2(graine_arc, fk)) > charge * 0.9) {
				continue;
			}
			float cote = k == 0 ? -1.0 : 1.0;
			vec2 a = vec2(cote * 9.0, -hc - 14.0 + 4.0);
			if (k == 2) {
				a = vec2(0.0, -206.0);
			}
			vec2 b = vec2((alea(vec2(graine_arc, fk + 3.0)) - 0.5) * 8.0, -hc + (alea(vec2(graine_arc, fk + 5.0)) - 0.5) * 18.0);
			// un petit zigzag de 3 segments
			vec2 m1 = mix(a, b, 0.33) + vec2((alea(vec2(graine_arc, fk + 9.0)) - 0.5) * 8.0, 0.0);
			vec2 m2 = mix(a, b, 0.66) + vec2((alea(vec2(graine_arc, fk + 11.0)) - 0.5) * 8.0, 0.0);
			float da = min(segment(p, a, m1), min(segment(p, m1, m2), segment(p, m2, b)));
			lum += couleur.rgb * couvre(da - 0.5, px) * 0.9 + couleur_foudre.rgb * exp(-da / 3.0) * 0.6;
		}
	}

	// ===================== L'APPEL : tout flashe =====================
	if (appel > 0.0) {
		lum += couleur.rgb * exp(-pow(abs(r_c) / 14.0, 2.0)) * appel * 2.4;
		lum += couleur_foudre.rgb * exp(-pow(abs(r_c) / 40.0, 2.0)) * appel * 0.9;
		// la rune entière s'illumine
		lum += couleur_foudre.rgb * exp(-pow(abs(d_rune) / 2.5, 2.0)) * step(d_fut, 0.0) * appel * 1.2;
	}

	// la lumière s'éteint avant le bord du rectangle (aucun carré)
	float bord = min(min(pix.x, taille.x - pix.x), min(pix.y, taille.y - pix.y));
	lum *= smoothstep(0.0, 16.0, bord);
	COLOR = vec4(c.rgb * c.a + lum, c.a);
}
