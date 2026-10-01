shader_type canvas_item;
render_mode unshaded;
// GARDIENNES DE SANG (1er oct. 2026) — talisman « Gardiennes » : des gouttes
// de sang qui tournent autour du héros, sur une RONDE vue en perspective (une
// ellipse un peu inclinée : elles passent derrière lui, plus petites et plus
// sombres, puis devant).
// Deux rectangles de la scène portent ce shader : `Derriere` (sous le sprite
// du héros) dessine ce qui est de l'autre côté de lui, `Devant` (par-dessus)
// ce qui est de notre côté — chaque goutte, chaque bout de sillage est dessiné
// par l'un OU l'autre, selon sa profondeur. Le passage d'un côté à l'autre se
// fait aux deux bouts de la ronde, loin de la silhouette du héros : on ne le
// voit pas.
// Chaque goutte : une LARME — tête ronde devant, queue effilée derrière, dans
// le sens de sa course — en aplat cerné d'encre (sobre : pas de blanc, pas
// d'ombrage) ; derrière elle, un SILLAGE translucide qui épouse la ronde et
// s'effile. Quand elle touche un ennemi, elle s'écrase un instant (`choc`) ;
// quand elle éclate sur un tir, une flaque claque et des gouttelettes partent
// en étoile puis retombent.
// Repère : des pixels, l'origine au centre de la ronde (le milieu du rectangle).

// --- fournis par gardiennes_sang.gd ----------------------------------------
uniform vec2 taille = vec2(560.0, 400.0);
// 1 : ce rectangle dessine ce qui est devant le héros ; 0 : derrière
uniform float devant : hint_range(0.0, 1.0) = 1.0;
uniform float temps = 0.0;
uniform int nombre = 2;
// par goutte — xy : sa position (px) ; z : sa profondeur (-1 au fond de la
// ronde, +1 devant) ; w : sa taille (0 = absente, 1 = pleine)
uniform vec4 g_pos[4];
// xy : le sens de sa course (normé) ; z : son étirement (1 en ronde, plus quand
// elle fond sur un tir) ; w : son sillage (0 → 1)
uniform vec4 g_mouv[4];
// xy : où elle a éclaté ; z : où en est l'éclatement (0 → 1 ; hors de [0, 1[,
// rien) ; w : son angle sur la ronde (son sillage le suit)
uniform vec4 g_eclat[4];
// x : son opacité (pâle pendant qu'elle se reforme) ; y : le choc (1 = elle
// vient de toucher, elle s'écrase)
uniform vec4 g_etat[4];
// la ronde : ses demi-axes (px) et son inclinaison (rad) — ceux du script
uniform vec2 rayons = vec2(115.0, 28.0);
uniform float inclinaison = -0.14;
// ----------------------------------------------------------------------------

// la tête de la goutte (rayon, px, devant le héros) ; sa queue (× ce rayon)
uniform float rayon_goutte = 9.0;
uniform float longueur_queue = 2.2;
// le fond de la ronde rétrécit la goutte de tant, le devant la grandit de tant
uniform float profondeur_taille = 0.17;
// le sillage : sa longueur sur la ronde (rad), sa demi-largeur à la goutte (× le
// rayon), son opacité
uniform float longueur_sillage = 1.15;
uniform float largeur_sillage = 0.8;
uniform float opacite_sillage : hint_range(0.0, 1.0) = 0.8;
uniform float encre_px : hint_range(0.0, 4.0) = 1.6;
uniform vec4 couleur : source_color = vec4(0.74, 0.04, 0.1, 1.0);
// la couleur d'une goutte au fond de la ronde (dans l'ombre du héros)
uniform vec4 couleur_fond : source_color = vec4(0.4, 0.02, 0.06, 1.0);
uniform vec4 couleur_encre : source_color = vec4(0.1, 0.01, 0.03, 1.0);

void par_dessus(inout vec3 rgb, inout float a, vec3 teinte, float f) {
	float total = f + a * (1.0 - f);
	rgb = (teinte * f + rgb * a * (1.0 - f)) / max(total, 0.0001);
	a = total;
}

float echelle(float z) {
	return 1.0 + profondeur_taille * z;
}

vec3 teinte(float z) {
	return mix(couleur_fond.rgb, couleur.rgb, smoothstep(-1.0, 0.7, z));
}

// une larme le long de +y : tête de rayon r1 en (0, 0), bout de rayon r2 en
// (0, h) — la « capsule inégale », négative dedans (px)
float larme(vec2 p, float r1, float r2, float h) {
	h = max(h, (r1 - r2) * 1.01 + 0.01);
	p.x = abs(p.x);
	float b = (r1 - r2) / h;
	float a = sqrt(1.0 - b * b);
	float k = dot(p, vec2(-b, a));
	if (k < 0.0) {
		return length(p) - r1;
	}
	if (k > a * h) {
		return length(p - vec2(0.0, h)) - r2;
	}
	return dot(p, vec2(a, b)) - r1;
}

// une larme qui file dans le sens `sens`, tête en `c` (dans le repère de p)
float larme_en(vec2 p, vec2 c, vec2 sens, float r1, float r2, float h) {
	vec2 d = p - c;
	return larme(vec2(dot(d, vec2(-sens.y, sens.x)), -dot(d, sens)), r1, r2, h);
}

float hachis(float n) {
	return fract(sin(n * 127.1 + 31.7) * 43758.5453);
}

void fragment() {
	vec2 p = (UV - 0.5) * taille;
	float cote = step(0.5, devant);
	vec3 rgb = couleur.rgb;
	float a = 0.0;

	// la ronde dans ses propres axes ; la distance (px) de ce point à elle, au
	// premier ordre ; et l'angle de la ronde le plus proche (sa profondeur : le
	// sinus)
	float ci = cos(-inclinaison);
	float si = sin(-inclinaison);
	vec2 pe = vec2(ci * p.x - si * p.y, si * p.x + ci * p.y);
	vec2 qe = pe / rayons;
	float lq = length(qe);
	float d_ronde = (lq - 1.0) * lq / max(length(pe / (rayons * rayons)), 1e-5);
	float phi = atan(qe.y, qe.x);
	float z_phi = sin(phi);

	for (int k = 0; k < 4; k++) {
		if (k >= nombre) {
			break;
		}
		vec4 gp = g_pos[k];
		vec4 gm = g_mouv[k];
		vec4 ge = g_eclat[k];
		vec4 gs = g_etat[k];

		// ===================== SON SILLAGE (sur la ronde, derrière elle) ==========
		if (gm.w > 0.001 && gp.w > 0.001 && step(0.0, z_phi) == cote) {
			float w_max = rayon_goutte * largeur_sillage * echelle(1.0) * gp.w + 1.5;
			if (abs(d_ronde) < w_max) {
				float u = mod(ge.w - phi, TAU) / longueur_sillage;
				if (u < 1.0) {
					float w = rayon_goutte * largeur_sillage * echelle(z_phi) * gp.w * pow(1.0 - u, 0.8);
					float m = smoothstep(-0.6, 0.6, w - abs(d_ronde)) * pow(1.0 - u, 1.4)
							* opacite_sillage * gm.w * gs.x;
					par_dessus(rgb, a, teinte(z_phi), m);
				}
			}
		}

		// ===================== LA GOUTTE =====================
		if (gp.w > 0.001 && step(0.0, gp.z) == cote) {
			float s = echelle(gp.z) * gp.w;
			// elle frémit (une goutte, pas une bille)
			float r1 = rayon_goutte * s * (1.0 + 0.05 * sin(temps * 13.0 + float(k) * 2.1));
			float h = r1 * longueur_queue * max(gm.z, 0.3);
			vec2 d = p - gp.xy;
			if (length(d) < h + r1 + encre_px + 3.0) {
				vec2 l = vec2(dot(d, vec2(-gm.y, gm.x)), -dot(d, gm.xy));
				// le choc : elle s'écrase contre ce qu'elle touche (plus large, plus courte)
				l.x /= 1.0 + 0.35 * gs.y;
				l.y /= 1.0 - 0.35 * gs.y;
				float sd = larme(l, r1, r1 * 0.14, h);
				par_dessus(rgb, a, couleur_encre.rgb, smoothstep(0.6, -0.6, sd - encre_px * s) * gs.x);
				par_dessus(rgb, a, teinte(gp.z), smoothstep(0.6, -0.6, sd) * gs.x);
			}
		}

		// ===================== SON ÉCLATEMENT (devant) =====================
		if (cote > 0.5 && ge.z >= 0.0 && ge.z < 1.0) {
			float t = ge.z;
			vec2 d0 = p - ge.xy;
			if (length(d0) < 96.0) {
				// la flaque qui claque, le temps d'un battement
				float flaque = rayon_goutte * 1.5 * (1.0 - smoothstep(0.0, 0.3, t));
				float sf = length(d0 * vec2(1.0, 1.35)) - flaque;
				par_dessus(rgb, a, couleur_encre.rgb, smoothstep(0.6, -0.6, sf - encre_px) * step(0.01, flaque));
				par_dessus(rgb, a, couleur.rgb, smoothstep(0.6, -0.6, sf) * step(0.01, flaque));
				// les gouttelettes : en étoile, freinées, puis elles retombent — elles
				// filent plus loin que l'explosion de la boule de feu, qui couvre le reste
				for (int i = 0; i < 7; i++) {
					float fi = float(i) + float(k) * 7.0;
					float ang = (float(i) + hachis(fi) * 0.6) / 7.0 * TAU;
					vec2 dv = vec2(cos(ang), sin(ang));
					float loin = mix(40.0, 66.0, hachis(fi * 3.1));
					vec2 c = dv * loin * (1.0 - (1.0 - t) * (1.0 - t)) + vec2(0.0, 26.0 * t * t);
					float rr = rayon_goutte * mix(0.36, 0.56, hachis(fi * 5.7)) * (1.0 - t * t);
					// tournée dans le sens de son vol (qui plonge en retombant)
					vec2 vol = normalize(dv * (1.0 - t) * 2.0 + vec2(0.0, 1.6 * t) + vec2(0.0001));
					float sd = larme_en(d0, c, vol, rr, rr * 0.2, rr * 1.8);
					par_dessus(rgb, a, couleur_encre.rgb, smoothstep(0.6, -0.6, sd - encre_px * 0.7) * step(0.01, rr));
					par_dessus(rgb, a, couleur.rgb, smoothstep(0.6, -0.6, sd) * step(0.01, rr));
				}
			}
		}
	}
	COLOR = vec4(rgb, a);
}
