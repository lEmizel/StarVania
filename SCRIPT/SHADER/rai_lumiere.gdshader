shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;
// RAI DE LUMIÈRE (3 oct. 2026, d'après une image de référence) — la
// lumière qui entre par un PASSAGE (SCRIPT/INTERACTIBLE/passage.tscn, nœud
// RaiDeLumiere) : l'ouverture blanche de lumière, et la nappe qui tombe en biais
// jusqu'au sol, plus forte près de l'ouverture, avec :
//   • un LISERÉ net sur son bord haut, au tracé un peu ondulé, DESSINÉ À LA
//     MAIN, qui se transforme TRÈS LENTEMENT, en continu et sur place (sans
//     glisser le long du trait) : `vitesse_ondulation`. Essais écartés :
//     redessinée 12 fois par seconde comme le halo des torches (trop agitée),
//     puis figée (trop morte) ;
//   • des POUSSIÈRES qui flottent dedans et scintillent ;
//   • une BRUME qui traîne au pied de l'ouverture ;
//   • des rayons à peine marqués qui partent du haut de l'ouverture.
// Elle éclaircit le décor (alpha prémultiplié, `teinte` : part qui couvre le
// décor ; le reste s'ajoute) : elle ressort surtout dans ses couloirs sombres.
// DEUX MODES (`mode`) :
//   • 0 = DE CÔTÉ (passage horizontal) : la nappe tombe en biais de l'ouverture
//     jusqu'au sol. Repère : `source` = le pied de l'ouverture, au sol ; la
//     salle est vers +x ;
//   • 1 = VERTICAL (pour les passages verticaux) : une colonne DROITE qui part
//     d'un trou (`hauteur` = sa LARGEUR), un liseré net de chaque côté. RIEN ne
//     déborde de sa largeur (sinon il rentre dans les murs) : les bords ne
//     tremblent que vers
//     l'intérieur, et la lueur du trou reste dedans. Repère :
//     `source` = le milieu de l'ouverture, le trajet va vers +y (vers le bas).
//     Qu'elle tombe ou qu'elle monte, elle DISPARAÎT EN DÉGRADÉ : nette au
//     trou, plus rien au bout (avant, elle finissait sur une flaque et de la
//     brume, qui passaient sous le sol quand elle était trop longue). Elle ne
//     se voit vraiment que sur la 1re moitié de sa longueur.
// rai_lumiere.gd retourne le rectangle (scale −1) pour l'autre côté, ou pour
// une lumière qui MONTE d'un trou du sol.

uniform vec2 taille = vec2(600.0, 420.0);
uniform vec2 source = vec2(60.0, 360.0);
uniform float hauteur = 300.0;                   // hauteur de l'ouverture (px)
uniform float longueur = 420.0;                  // le rai touche le sol à tant de l'ouverture (px)
uniform float intensite : hint_range(0.0, 2.0) = 1.0;
uniform float ouverture : hint_range(0.0, 1.0) = 0.8;
uniform vec4 couleur : source_color = vec4(1.0, 0.96, 0.88, 1.0);
uniform float teinte : hint_range(0.0, 1.0) = 0.45;
uniform float force_nappe : hint_range(0.0, 1.0) = 0.32;
uniform float force_lisere : hint_range(0.0, 1.0) = 0.6;
uniform int nb_poussieres : hint_range(0, 32) = 16;
uniform float brume : hint_range(0.0, 1.0) = 0.6;
uniform float tremble : hint_range(0.0, 0.1) = 0.015;   // l'ondulation des bords, en part de la taille
// l'ondulation se transforme à cette vitesse (unités de bruit par seconde) :
// 0,6 = une forme nouvelle en 2 secondes environ ; 0 = figée. (0,05 : trop
// lent, le mouvement ne se voit pas ; 0,3 : encore trop lent.)
// Réglée sur le passage (rai_vitesse_ondulation)
uniform float vitesse_ondulation = 0.6;
uniform float graine = 0.0;
uniform float mode = 0.0;                        // 0 = de côté, 1 = vertical
uniform float evasement = 0.0;                   // vertical : la colonne s'élargit d'autant au bout (0 = droite)


// hasard ENTIER, exact (sans marches aux raccords, sans perte de précision)
float alea_u(uint n) {
	n = (n << 13u) ^ n;
	n = n * (n * n * 15731u + 789221u) + 1376312589u;
	return float(n & 2147483647u) / 2147483647.0;
}

float alea_noeud(vec2 i) {
	uint x = uint(int(i.x) + 8192);
	uint y = uint(int(i.y) + 8192);
	return alea_u(x * 7919u + y * 104729u);
}

float bruit(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(alea_noeud(i), alea_noeud(i + vec2(1.0, 0.0)), u.x),
			mix(alea_noeud(i + vec2(0.0, 1.0)), alea_noeud(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += bruit(p) * a;
		p = p * 2.03 + vec2(13.7, 7.1);
		a *= 0.5;
	}
	return v / 0.9375;
}

void fragment() {
	vec2 pix = UV * taille;
	float px = max(fwidth(pix.x), 0.001);
	float t = TIME;
	float g = graine * 37.0;
	float lent = t * vitesse_ondulation;               // l'ondulation se transforme, très lentement
	uint gi = uint(g * 1000.0);
	float nappe = 0.0;
	float lisere = 0.0;
	float poussieres = 0.0;
	float nappe_brume = 0.0;
	float ouv = 0.0;
	if (mode < 0.5) {
		vec2 p = pix - source;
		float x = p.x;                                   // vers la salle
		float h = -p.y;                                  // au-dessus du sol
		float H = max(hauteur, 1.0);
		float L = max(longueur, 1.0);
		float sol = smoothstep(-1.5, 1.5, h);             // rien sous le sol

		// ===================== LE BORD HAUT, ONDULÉ =====================
		// la droite du haut de l'ouverture (0, H) au sol (L, 0), qui ondule un peu
		// (propre à chaque passage) et se transforme très lentement, sur place
		float u = clamp(x / L, 0.0, 1.0);
		float ondule = (bruit(vec2(u * 6.0, g + 3.1 + lent)) - 0.5) * 2.0 * tremble * H;
		float h_bord = H * (1.0 - x / L) + ondule;
		float k = L / sqrt(L * L + H * H);               // pour passer à la distance perpendiculaire au bord
		float dp = (h_bord - h) * k;                      // > 0 sous le bord, dans le rai
		float dans_long = step(0.0, x) * (1.0 - smoothstep(L * 0.92, L * 1.02, x));

		// ===================== LA NAPPE =====================
		float dedans = clamp(dp / 2.5 + 0.5, 0.0, 1.0) * dans_long * sol;
		float fondu = pow(1.0 - u, 0.75);                 // plus forte près de l'ouverture
		// une bande un peu plus claire juste sous le bord, comme sur la référence
		float sous_bord = exp(-max(dp, 0.0) / 26.0) * 0.45;
		// des rayons à peine marqués, partis du haut de l'ouverture
		vec2 depuis_haut = vec2(x, H - h);
		float ang = atan(depuis_haut.y, max(depuis_haut.x, 0.001));
		float rayons = 0.82 + 0.18 * bruit(vec2(ang * 22.0, g + lent * 0.7));
		nappe = dedans * fondu * (0.75 + sous_bord) * rayons;

		// ===================== LE LISERÉ DU BORD =====================
		float demi = 0.6 + 0.6 * bruit(vec2(u * 9.0, g + 7.7 + lent));
		float trait = clamp((demi - abs(dp)) / px + 0.5, 0.0, 1.0);
		float lueur_trait = exp(-dp * dp / 18.0) * 0.25;
		lisere = (trait + lueur_trait) * dans_long * sol * mix(1.0, 0.25, smoothstep(0.1, 1.0, u));

		// ===================== LES POUSSIÈRES =====================
		poussieres = 0.0;
		for (int i = 0; i < 32; i++) {
			if (i >= nb_poussieres) {
				break;
			}
			uint base = uint(i) * 2654435761u + gi;
			float periode = 4.0 + 3.0 * alea_u(base + 11u);
			float ph = t / periode + alea_u(base + 23u);
			float vie = fract(ph);
			uint hh = base * 31u + uint(int(floor(ph)) + 100000) * 7919u;
			// une place au hasard dans le rai, qui dérive doucement
			float pu = 0.04 + 0.86 * alea_u(hh + 1u) + sin(t * 0.35 + alea_u(hh + 2u) * 6.28) * 0.02;
			float pv = 0.08 + 0.8 * alea_u(hh + 3u) + sin(t * 0.5 + alea_u(hh + 4u) * 6.28) * 0.04 - vie * 0.06;
			float ex = pu * L;
			float eh = pv * H * (1.0 - pu);
			float dd = length(vec2(x - ex, h - eh));
			float r = 0.8 + 0.8 * alea_u(hh + 5u);
			float scintille = 0.55 + 0.45 * sin(t * (2.0 + 3.0 * alea_u(hh + 6u)) + alea_u(hh + 7u) * 6.28);
			float apparait = smoothstep(0.0, 0.15, vie) * (1.0 - smoothstep(0.8, 1.0, vie));
			poussieres += (clamp((r - dd) / px + 0.5, 0.0, 1.0) + exp(-dd * dd / 6.0) * 0.3) * scintille * apparait;
		}
		poussieres = min(poussieres, 1.0) * dans_long * sol;

		// ===================== LA BRUME AU PIED DE L'OUVERTURE =====================
		vec2 qb = vec2(x * 0.012 - t * 0.05, h * 0.02 - t * 0.02);
		float volute = fbm(qb + vec2(fbm(qb * 1.7 + vec2(g, t * 0.04)) * 1.2, 0.0) + vec2(g * 0.3, 0.0));
		float zone_brume = (1.0 - smoothstep(0.0, 90.0, h)) * (1.0 - smoothstep(0.0, L * 0.55, x))
				* smoothstep(-20.0, 10.0, x) * sol;
		nappe_brume = smoothstep(0.38, 0.75, volute) * zone_brume * brume;

		// ===================== L'OUVERTURE, BLANCHE DE LUMIÈRE =====================
		float larg = 22.0;
		float d_ouv = max(max(-(x + larg), x), max(-h, h - H));     // < 0 dans l'ouverture
		// un cœur blanc au bord doux, plus franc vers l'arrière (d'où vient la lumière)
		float coeur_ouv = clamp(-d_ouv / 2.0 + 0.5, 0.0, 1.0) * mix(1.0, 0.75, smoothstep(-larg, 0.0, x));
		float halo_ouv = exp(-max(d_ouv, 0.0) / 22.0) * 0.55 * (1.0 - clamp(-d_ouv / 2.0 + 0.5, 0.0, 1.0));
		ouv = (coeur_ouv * 0.95 + halo_ouv) * ouverture;
	} else {
		// ===================== VERTICAL : UNE COLONNE QUI PART D'UN TROU =====================
		vec2 p = pix - source;
		float along = p.y;                               // 0 à l'ouverture → L au bout
		float across = p.x;
		float W = max(hauteur, 1.0);                     // la largeur du trou
		float L = max(longueur, 1.0);
		float uu = clamp(along / L, 0.0, 1.0);
		float hw = W * 0.5 * (1.0 + evasement * uu);
		// ses deux bords, un peu ondulés (ils se transforment très lentement) —
		// vers l'INTÉRIEUR seulement : jamais plus large que le trou
		float bord_g = -hw + bruit(vec2(uu * 5.0, g + 1.3 + lent)) * 2.0 * tremble * W;
		float bord_d = hw - bruit(vec2(uu * 5.0, g + 9.1 + lent)) * 2.0 * tremble * W;
		float dp = min(across - bord_g, bord_d - across);           // > 0 dans la colonne
		// elle s'éteint en dégradé : plus rien au bout de sa longueur
		float dans_long = step(0.0, along) * (1.0 - smoothstep(L * 0.5, L, along));
		float degrade = pow(1.0 - uu, 2.2);

		// la nappe : plus forte près du trou, plus claire le long des bords,
		// des rayons à peine marqués dans le sens de la colonne
		float dedans = clamp(dp / 2.5 + 0.5, 0.0, 1.0) * dans_long;
		float fondu = degrade;
		float sous_bord = exp(-max(dp, 0.0) / 22.0) * 0.4;
		float rayons = 0.82 + 0.18 * bruit(vec2(across / max(hw, 1.0) * 9.0, g + lent * 0.7));
		nappe = dedans * fondu * (0.75 + sous_bord) * rayons;

		// les liserés des deux bords
		float demi = 0.6 + 0.6 * bruit(vec2(uu * 9.0, g + 7.7 + lent));
		float d_bord = min(abs(across - bord_g), abs(across - bord_d));
		float trait = clamp((demi - d_bord) / px + 0.5, 0.0, 1.0);
		float lueur_trait = exp(-d_bord * d_bord / 18.0) * 0.25;
		lisere = (trait + lueur_trait) * dans_long * (1.0 - smoothstep(0.05, 0.75, uu));

		// les poussières : elles descendent doucement (elles montent si la lumière monte)
		for (int i = 0; i < 32; i++) {
			if (i >= nb_poussieres) {
				break;
			}
			uint base = uint(i) * 2654435761u + gi;
			float periode = 4.0 + 3.0 * alea_u(base + 11u);
			float ph = t / periode + alea_u(base + 23u);
			float vie = fract(ph);
			uint hh = base * 31u + uint(int(floor(ph)) + 100000) * 7919u;
			float pu = 0.04 + 0.86 * alea_u(hh + 1u) + vie * 0.05 + sin(t * 0.35 + alea_u(hh + 2u) * 6.28) * 0.015;
			float pv = (alea_u(hh + 3u) * 2.0 - 1.0) * 0.85 + sin(t * 0.5 + alea_u(hh + 4u) * 6.28) * 0.06;
			float ey = pu * L;
			float ex = pv * W * 0.5 * (1.0 + evasement * pu);
			float dd = length(vec2(across - ex, along - ey));
			float r = 0.8 + 0.8 * alea_u(hh + 5u);
			float scintille = 0.55 + 0.45 * sin(t * (2.0 + 3.0 * alea_u(hh + 6u)) + alea_u(hh + 7u) * 6.28);
			float apparait = smoothstep(0.0, 0.15, vie) * (1.0 - smoothstep(0.8, 1.0, vie));
			poussieres += (clamp((r - dd) / px + 0.5, 0.0, 1.0) + exp(-dd * dd / 6.0) * 0.3) * scintille * apparait;
		}
		// les poussières s'éteignent avec la lumière
		poussieres = min(poussieres, 1.0) * dans_long * (0.25 + 0.75 * pow(1.0 - uu, 1.2));

		// le trou, blanc de lumière
		float larg = 22.0;
		float d_ouv = max(max(-(along + larg), along), abs(across) - W * 0.5);
		float coeur_ouv = clamp(-d_ouv / 2.0 + 0.5, 0.0, 1.0) * mix(1.0, 0.75, smoothstep(-larg, 0.0, along));
		float halo_ouv = exp(-max(d_ouv, 0.0) / 22.0) * 0.55 * (1.0 - clamp(-d_ouv / 2.0 + 0.5, 0.0, 1.0))
				* (1.0 - smoothstep(W * 0.5 - 2.0, W * 0.5 + 2.0, abs(across)));   // pas sur les murs
		ouv = (coeur_ouv * 0.95 + halo_ouv) * ouverture;
	}

	// ===================== LA LUMIÈRE, EN ALPHA PRÉMULTIPLIÉ =====================
	float an = nappe * force_nappe * intensite;
	float al = lisere * force_lisere * intensite;
	float ap = poussieres * 0.8 * intensite;
	float ab = nappe_brume * 0.6 * intensite;
	vec3 rgb = couleur.rgb * (an + al + ap + ab + ouv);
	float a = (an + ab) * teinte + (al + ap) * 0.6 + ouv * 0.9;

	// rien ne touche le bord du rectangle
	float bord = min(min(pix.x, taille.x - pix.x), min(pix.y, taille.y - pix.y));
	float fondu_bord = smoothstep(0.0, 6.0, bord);
	COLOR = vec4(rgb, clamp(a, 0.0, 1.0)) * fondu_bord;
}
