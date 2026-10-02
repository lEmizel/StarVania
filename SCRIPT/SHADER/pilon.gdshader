shader_type canvas_item;
render_mode unshaded;
// PILON (2 oct. 2026, piège imaginé par Kaoru) — le DÉCOR du concasseur, SANS
// contour (il fait partie du décor : le volume vient des tons, pas de l'encre).
// Deux montants de pierre sur leurs socles, un linteau, la tige de fer du piston
// qui coulisse dans le linteau, et la tête : un bloc de pierre cerclé de deux
// bandes de fer rivetées, semelle de fer. La lumière vient d'en haut à gauche.
//   • `levee` (px) : le bloc monte (la tige dépasse d'autant du linteau) ;
//   • `tremble` : il tremble en haut, avant de tomber ;
//   • `poussiere` : du gravier tombe de lui pendant qu'il monte ;
//   • `impact` (1 → 0 après le coup) : deux nuages de poussière au ras du sol ;
//   • son ombre sur le sol se resserre et fonce à mesure qu'il descend.
// Repère : `sol` = le sol sous le pilon, dans le rectangle (px). Piloté par
// SCRIPT/INTERACTIBLE/pilon.gd.

uniform vec2 taille = vec2(220.0, 400.0);
uniform vec2 sol = vec2(110.0, 380.0);
uniform float levee = 0.0;
uniform float levee_max = 120.0;
uniform float tremble : hint_range(0.0, 1.0) = 0.0;
uniform float poussiere : hint_range(0.0, 1.0) = 0.0;
uniform float impact : hint_range(0.0, 1.0) = 0.0;
uniform float temps = 0.0;

uniform float largeur_bloc = 84.0;
uniform float hauteur_bloc = 62.0;

uniform vec4 pierre : source_color = vec4(0.46, 0.52, 0.63, 1.0);
uniform vec4 pierre_ombre : source_color = vec4(0.29, 0.34, 0.44, 1.0);
uniform vec4 pierre_lumiere : source_color = vec4(0.61, 0.66, 0.76, 1.0);
uniform vec4 fer : source_color = vec4(0.26, 0.28, 0.33, 1.0);
uniform vec4 fer_lumiere : source_color = vec4(0.5, 0.53, 0.59, 1.0);
uniform vec4 couleur_poussiere : source_color = vec4(0.78, 0.8, 0.84, 1.0);


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

// un rectangle arrondi (centre c, demi-tailles b, rayon r) ; négatif dedans
float boite(vec2 p, vec2 c, vec2 b, float r) {
	vec2 d = abs(p - c) - b + r;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - r;
}

// le modelé d'une pièce SANS contour : un dégradé du haut vers le bas, un filet
// de lumière sur les bords haut et gauche, une ombre sur les bords droit et bas
vec3 modele(vec2 p, vec2 c, vec2 b, vec3 base, vec3 clair, vec3 sombre, float grain) {
	vec2 q = (p - c) / b;                            // -1..1 dans la pièce
	vec3 col = mix(clair, base, smoothstep(-1.0, 0.2, q.y));
	col = mix(col, sombre, smoothstep(0.3, 1.0, q.y) * 0.55);
	float bord_g = smoothstep(-0.78, -1.0, q.x);
	float bord_h = smoothstep(-0.8, -1.0, q.y);
	float bord_d = smoothstep(0.7, 1.0, q.x);
	float bord_b = smoothstep(0.72, 1.0, q.y);
	col = mix(col, clair, max(bord_g, bord_h) * 0.7);
	col = mix(col, sombre, max(bord_d, bord_b) * 0.75);
	col *= 1.0 - grain * (bruit(p * 0.18) - 0.5) * 0.09;
	return col;
}

void fragment() {
	vec2 pix = UV * taille;
	float px = max(fwidth(pix.x), 0.001);
	vec2 p = pix - sol;                              // y vers le bas, 0 = le sol
	vec4 c = vec4(pierre.rgb, 0.0);

	float lb = largeur_bloc * 0.5;
	float hb = hauteur_bloc;
	float x_montant = lb + 12.0;                     // l'axe des montants
	float h_cadre = levee_max + hb + 14.0;           // le bas du linteau
	float secoue = sin(temps * 63.0) * 2.0 * tremble;

	// ===================== L'OMBRE AU SOL =====================
	float k_ombre = 1.0 - clamp(levee / max(levee_max, 1.0), 0.0, 1.0);
	float l_ombre = lb * mix(1.5, 1.05, k_ombre);
	float ombre = exp(-pow(abs(p.x / l_ombre), 6.0)) * exp(-pow(abs(p.y / 4.0), 2.0)) * mix(0.18, 0.5, k_ombre);
	c = sur(c, vec4(vec3(0.08, 0.1, 0.16), ombre));

	// ===================== LES MONTANTS ET LEURS SOCLES =====================
	for (int cote = 0; cote < 2; cote++) {
		float s = cote == 0 ? -1.0 : 1.0;
		vec2 cm = vec2(s * x_montant, -h_cadre * 0.5);
		vec2 bm = vec2(7.0, h_cadre * 0.5);
		float dm = boite(p, cm, bm, 1.5);
		vec3 cm_col = modele(p, cm, bm, pierre_ombre.rgb, pierre.rgb, pierre_ombre.rgb * 0.72, 1.0);
		c = sur(c, vec4(cm_col, couvre(dm, px)));
		// le socle
		vec2 cs = vec2(s * x_montant, -9.0);
		vec2 bs = vec2(13.0, 9.0);
		float ds = boite(p, cs, bs, 2.0);
		c = sur(c, vec4(modele(p, cs, bs, pierre.rgb, pierre_lumiere.rgb, pierre_ombre.rgb, 1.0), couvre(ds, px)));
		// un collier de fer à mi-hauteur
		vec2 cc = vec2(s * x_montant, -h_cadre * 0.55);
		vec2 bc = vec2(9.0, 5.0);
		c = sur(c, vec4(modele(p, cc, bc, fer.rgb, fer_lumiere.rgb, fer.rgb * 0.7, 0.0), couvre(boite(p, cc, bc, 1.5), px)));
	}

	// ===================== LA TIGE (elle coulisse dans le linteau) =====================
	float y_bloc_haut = -levee - hb;
	float y_tige_haut = -h_cadre - 34.0 - levee;
	vec2 ct = vec2(secoue, (y_bloc_haut + y_tige_haut) * 0.5);
	vec2 bt = vec2(6.0, (y_bloc_haut - y_tige_haut) * 0.5);
	float dt = boite(p, ct, bt, 2.0);
	c = sur(c, vec4(modele(p, ct, bt, fer.rgb, fer_lumiere.rgb, fer.rgb * 0.65, 0.0), couvre(dt, px)));
	// son chapeau, en haut
	vec2 cch = vec2(secoue, y_tige_haut);
	vec2 bch = vec2(10.0, 5.0);
	c = sur(c, vec4(modele(p, cch, bch, fer.rgb, fer_lumiere.rgb, fer.rgb * 0.7, 0.0), couvre(boite(p, cch, bch, 2.0), px)));

	// ===================== LE LINTEAU =====================
	vec2 cl = vec2(0.0, -h_cadre - 11.0);
	vec2 bl = vec2(x_montant + 14.0, 11.0);
	float dl = boite(p, cl, bl, 2.5);
	c = sur(c, vec4(modele(p, cl, bl, pierre.rgb, pierre_lumiere.rgb, pierre_ombre.rgb, 1.0), couvre(dl, px)));
	// la bague de fer où passe la tige
	vec2 cb = vec2(0.0, -h_cadre - 11.0);
	vec2 bb = vec2(11.0, 12.5);
	c = sur(c, vec4(modele(p, cb, bb, fer.rgb, fer_lumiere.rgb, fer.rgb * 0.7, 0.0), couvre(boite(p, cb, bb, 2.0), px)));
	// la tige repasse devant la bague (on voit qu'elle la traverse)
	c = sur(c, vec4(modele(p, ct, bt, fer.rgb, fer_lumiere.rgb, fer.rgb * 0.65, 0.0), couvre(max(dt, abs(p.y - cb.y) - 9.0), px)));

	// ===================== LA TÊTE : le bloc cerclé de fer =====================
	vec2 cbk = vec2(secoue, -levee - hb * 0.5);
	vec2 bbk = vec2(lb, hb * 0.5);
	float dbk = boite(p, cbk, bbk, 4.0);
	vec3 col_bloc = modele(p, cbk, bbk, pierre.rgb, pierre_lumiere.rgb, pierre_ombre.rgb, 1.0);
	// une fêlure discrète dans la pierre (un ton plus sombre, pas un trait d'encre)
	vec2 qb = p - cbk;
	float felure = abs(qb.x - 6.0 - 5.0 * sin(qb.y * 0.25)) - 0.6;
	col_bloc = mix(col_bloc, pierre_ombre.rgb * 0.85, couvre(felure, px) * step(-hb * 0.3, qb.y) * step(qb.y, hb * 0.05) * 0.8);
	c = sur(c, vec4(col_bloc, couvre(dbk, px)));
	// deux bandes de fer rivetées
	for (int k = 0; k < 2; k++) {
		float yk = cbk.y + (k == 0 ? -hb * 0.3 : hb * 0.18);
		vec2 cf = vec2(cbk.x, yk);
		vec2 bf = vec2(lb + 2.0, 5.5);
		c = sur(c, vec4(modele(p, cf, bf, fer.rgb, fer_lumiere.rgb, fer.rgb * 0.68, 0.0), couvre(boite(p, cf, bf, 1.5), px)));
		for (int r = 0; r < 4; r++) {
			vec2 cr = vec2(cbk.x + (float(r) / 3.0 - 0.5) * lb * 1.5, yk);
			float dr = length(p - cr) - 2.2;
			vec3 riv = mix(fer_lumiere.rgb * 1.15, fer.rgb, smoothstep(-2.2, 1.5, p.x - cr.x + p.y - cr.y));
			c = sur(c, vec4(riv, couvre(dr, px)));
		}
	}
	// la semelle de fer
	vec2 csm = vec2(cbk.x, -levee - 4.0);
	vec2 bsm = vec2(lb + 3.0, 4.5);
	c = sur(c, vec4(modele(p, csm, bsm, fer.rgb, fer_lumiere.rgb, fer.rgb * 0.6, 0.0), couvre(boite(p, csm, bsm, 1.0), px)));

	// ===================== LE GRAVIER QUI TOMBE (il monte) =====================
	if (poussiere > 0.01) {
		for (int k = 0; k < 6; k++) {
			float fk = float(k);
			float periode = 0.5 + 0.3 * alea(vec2(fk, 1.3));
			float ph = temps / periode + alea(vec2(fk, 7.7));
			float t = fract(ph);
			float n = floor(ph);
			float x0 = (alea(vec2(fk, n)) - 0.5) * lb * 1.8;
			vec2 pos = vec2(x0, -levee + 0.5 * 1400.0 * t * t * periode * periode);
			if (pos.y > 0.0) {
				continue;
			}
			float dg = length(p - pos) - (1.2 + 1.0 * alea(vec2(fk, n + 3.0)));
			c = sur(c, vec4(pierre_ombre.rgb, couvre(dg, px) * poussiere));
		}
	}

	// ===================== LA POUSSIÈRE DU COUP =====================
	if (impact > 0.01) {
		float t = 1.0 - impact;
		float nuage = 0.0;
		for (int k = 0; k < 2; k++) {
			float s = k == 0 ? -1.0 : 1.0;
			for (int b = 0; b < 3; b++) {
				float fb = float(b);
				vec2 cn = vec2(s * (lb + 10.0 + t * (40.0 + 22.0 * fb)), -8.0 - fb * 5.0 - t * 14.0);
				float rn = (9.0 + 6.0 * fb) * (0.6 + 0.8 * t);
				nuage = max(nuage, couvre(length(p - cn) - rn, px * 3.0));
			}
		}
		c = sur(c, vec4(couleur_poussiere.rgb, nuage * impact * 0.7 * step(p.y, 1.0)));
	}

	COLOR = c;
}
