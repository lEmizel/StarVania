shader_type canvas_item;

// ============================================================================
// SLIME — le monstre est DESSINÉ ICI, pas image par image, d'après un dessin
// de référence (un slime de 38 × 30 pixels) : une goutte de sang posée, claire
// en haut et sombre en bas, la limite entre les deux qui ondule, un noyau
// sombre, trois reflets roses, un trait bordeaux tout autour. Pas d'yeux.
// Rendu en GROS PIXELS (`pixel` : le grain des autres monstres, dont les dessins
// sont affichés à 1,22) : chaque case de la grille est d'une seule couleur, sans
// dégradé, et le trait est la rangée de cases vides qui touchent une case
// pleine — un contour d'un pixel, comme sur un dessin.
// Quand sa demi-largeur vaut celle du dessin de référence (la taille 0.5 du
// monstre), sans écrasement, on retrouve ce dessin (à 4 cases près sur son
// pourtour) ; les mesures ci-dessous en viennent, en pixels de ce dessin. Aux
// autres tailles le pourtour et l'ondulation sont recalculés, le noyau et les
// reflets grossissent d'autant.
// Tout est piloté par slime_corps.gd à chaque image : l'écrasement, le penché,
// le balancement du liquide, les gouttes qui giclent, la mort.
// Ses états (éclair de coup, teinte, fissures, cristal) sont ceux de tous les
// monstres : etats_monstre.gdshaderinc.
// Les longueurs sont en CASES, le sol en y = 0, y vers le haut.
// ============================================================================
#include "res://SCRIPT/MONSTER/etats_monstre.gdshaderinc"

// le point du sol sous le slime, dans le rectangle (px d'écran)
uniform vec2 pieds = vec2(120.0, 150.0);
// le côté d'une case (px d'écran)
uniform float pixel = 1.22;

// --- le corps (sans son trait) ---
uniform float demi_largeur = 17.9;
uniform float hauteur = 28.0;
// l'écrasement : (largeur, hauteur), 1 = au repos
uniform vec2 echelle = vec2(1.0, 1.0);
// le haut part en avant (cases par case de haut)
uniform float penche = 0.0;
// 1 : posé, le ventre s'étale sur le sol ; 0 : en l'air, une goutte ronde
uniform float sol = 1.0;
// le tremblement de l'annonce (cases, en largeur)
uniform float decalage = 0.0;

// --- le dedans ---
// le liquide penche : la limite clair / sombre monte d'un côté, descend de l'autre
uniform float houle = 0.0;
// le noyau traîne un peu derrière le corps (cases)
uniform vec2 noyau_decale = vec2(0.0);

// --- ce qui gicle ---
// le temps depuis un gros atterrissage (s) ; < 0 : rien
uniform float eclabousse = -1.0;
// le temps depuis sa mort (s) ; < 0 : vivant
uniform float mort = -1.0;
uniform float graine = 1.0;

uniform vec4 couleur : source_color = vec4(0.647, 0.125, 0.204, 1.0);
uniform vec4 couleur_ombre : source_color = vec4(0.463, 0.086, 0.204, 1.0);
uniform vec4 couleur_reflet : source_color = vec4(0.973, 0.6, 0.655, 1.0);
uniform vec4 couleur_trait : source_color = vec4(0.275, 0.0, 0.0, 1.0);

const float ECLABOUSSURE = 0.45;        // durée des gouttes d'un atterrissage (s)
const float GERBE = 1.3;                // durée des gouttes de la mort (s)

// --- LE DESSIN DE RÉFÉRENCE, mesuré (en ses pixels) ---
const float REF_DEMI = 17.9;            // sa demi-largeur, sans le trait
const float REF_HAUT = 28.0;            // sa hauteur, sans le trait
// son pourtour : le plus large à 11 de haut ; au-dessus une ellipse un peu
// pointue (exposant 1,8, rayon 17,5), en dessous une ellipse carrée (exposant
// 3, rayon 14) que le sol coupe ; le sommet penche de 0,06 vers la droite
const float REF_VENTRE = 11.0;
const float REF_RAYON_HAUT = 17.5;
const float REF_RAYON_BAS = 14.0;
const float REF_PENCHE = 0.06;
// son milieu est un quart de pixel à gauche du milieu de l'image
const float REF_MILIEU = -0.25;
// la hauteur du haut de l'ombre, colonne par colonne (de la 1re à la 36e)
const float REF_OMBRE[36] = {
	12.0, 13.0, 14.0, 15.0, 15.0, 16.0, 16.0, 16.0, 16.0, 15.0, 15.0, 14.0,
	14.0, 13.0, 12.0, 11.0, 11.0, 11.0, 11.0, 11.0, 11.0, 10.0, 9.0, 8.0,
	8.0, 9.0, 10.0, 11.0, 11.0, 12.0, 12.0, 12.0, 12.0, 11.0, 11.0, 10.0
};
// son noyau : un rond de 2,5 de rayon
const vec2 REF_NOYAU = vec2(-2.25, 17.5);
const float REF_NOYAU_RAYON = 2.5;

varying vec2 local;

void vertex() {
	local = VERTEX;
}

// un hasard ENTIER (le même partout, sur toutes les cartes)
uint slime_hacher(uint x) {
	x ^= x >> 16u;
	x *= 0x7feb352du;
	x ^= x >> 15u;
	x *= 0x846ca68bu;
	x ^= x >> 16u;
	return x;
}

float slime_alea(float n) {
	uint h = slime_hacher(uint(n) * 747796405u + uint(graine) * 2891336453u + 12345u);
	return float(h & 0xffffffu) / 16777215.0;
}

// combien de fois le dessin de référence (2 pour le slime normal)
float grandeur() {
	return demi_largeur / REF_DEMI;
}

// la case `p` ramenée dans le repère du corps : sans le tremblement, sans la
// rangée du trait du bas, redressée, son milieu en x = 0
vec2 dans_le_corps(vec2 p) {
	p.x -= decalage + REF_MILIEU * grandeur();
	p.y -= 1.0;
	p.x -= penche * p.y;
	return p;
}

// LE CORPS : le pourtour du dessin, écrasé ou étiré. En l'air, le dessous se
// referme en rond.
bool dans_corps(vec2 p) {
	vec2 c = dans_le_corps(p);
	if (c.y < 0.0) {
		return false;
	}
	float a = demi_largeur * echelle.x;
	float h = hauteur * echelle.y;
	if (a < 0.5 || h < 0.5) {
		return false;
	}
	float ventre = REF_VENTRE / REF_HAUT * h;
	if (c.y > ventre) {
		float x = abs(c.x - REF_PENCHE * (c.y - ventre)) / a;
		float y = (c.y - ventre) / (REF_RAYON_HAUT / REF_HAUT * h);
		// écrasé, il s'arrondit : sans ça ses deux bouts finissent en pointe
		float pointe = mix(2.4, 1.8, clamp((echelle.y - 0.55) / 0.45, 0.0, 1.0));
		return pow(x, pointe) + pow(y, pointe) <= 1.0;
	}
	float x = abs(c.x) / a;
	float y = (ventre - c.y) / mix(ventre, REF_RAYON_BAS / REF_HAUT * h, sol);
	float n = mix(2.2, 3.0, sol);
	return pow(x, n) + pow(y, n) <= 1.0;
}

// une goutte lancée de `depart` à la vitesse `v` (cases par seconde), `t` s
// plus tard ; retombée au sol, elle n'est plus là
bool dans_goutte(vec2 p, vec2 depart, vec2 v, float t, float rayon, float pesanteur) {
	vec2 c = depart + v * t - vec2(0.0, 0.5 * pesanteur * t * t);
	if (c.y < 1.0 + rayon * 0.5) {
		return false;
	}
	vec2 d = p - (floor(c) + 0.5);
	return dot(d, d) <= rayon * rayon;
}

// un gros atterrissage : deux gouttes giclent de chaque côté de sa base
bool dans_eclaboussure(vec2 p) {
	if (eclabousse < 0.0 || eclabousse > ECLABOUSSURE) {
		return false;
	}
	float g = grandeur();
	float a = demi_largeur * echelle.x;
	float rayon = mix(1.9, 0.9, eclabousse / ECLABOUSSURE) * mix(0.7, 1.0, g * 0.5);
	for (int i = 0; i < 4; i++) {
		float cote = (i % 2 == 0) ? 1.0 : -1.0;
		vec2 v = vec2(cote * mix(35.0, 85.0, slime_alea(float(i) + 3.0)),
				mix(75.0, 130.0, slime_alea(float(i) + 9.0))) * sqrt(g);
		if (dans_goutte(p, vec2(cote * a * 0.85, 3.0), v, eclabousse, rayon * sqrt(g), 600.0)) {
			return true;
		}
	}
	return false;
}

// sa mort : il éclate en gouttes, vers le haut et les côtés
bool dans_gerbe(vec2 p) {
	if (mort < 0.0 || mort > GERBE) {
		return false;
	}
	float g = grandeur();
	float fonte = clamp(mort / GERBE, 0.0, 1.0);
	for (int i = 0; i < 9; i++) {
		float n = float(i);
		float angle = mix(0.3, 2.84, (n + slime_alea(n + 20.0)) / 9.0);
		vec2 v = vec2(cos(angle), sin(angle)) * mix(85.0, 165.0, slime_alea(n + 40.0)) * sqrt(g);
		float rayon = mix(3.0, 1.0, fonte) * mix(0.65, 1.15, slime_alea(n + 60.0)) * sqrt(g);
		if (dans_goutte(p, vec2(0.0, hauteur * 0.4), v, mort, rayon, 540.0)) {
			return true;
		}
	}
	return false;
}

bool plein(vec2 p) {
	return dans_corps(p) || dans_eclaboussure(p) || dans_gerbe(p);
}

// un point du dessin de référence (x depuis son milieu, y depuis sa base), là
// où il est dans le corps du moment, DANS LA GRILLE (le repère des cases, sans
// le tremblement ni la rangée du trait du bas) et calé dessus : au milieu d'une
// case quand un pixel du dessin en vaut un nombre impair, à un coin sinon
vec2 du_dessin(vec2 r, float cale) {
	vec2 c = vec2(r.x * demi_largeur * echelle.x / REF_DEMI + REF_MILIEU * grandeur(),
			r.y * hauteur * echelle.y / REF_HAUT);
	c.x += penche * c.y;
	return floor(c - cale + 0.5) + cale;
}

// la case `e` (dans la grille) est-elle sur le trait de reflet qui va de `r0`
// à `r1` (points du dessin de référence) ?
bool sur_reflet(vec2 e, vec2 r0, vec2 r1, float cale, float rayon) {
	vec2 a = du_dessin(r0, cale);
	vec2 b = du_dessin(r1, cale);
	vec2 ab = b - a;
	float l2 = dot(ab, ab);
	float t = l2 > 0.0 ? clamp(dot(e - a, ab) / l2, 0.0, 1.0) : 0.0;
	vec2 d = e - (a + ab * t);
	return dot(d, d) <= rayon * rayon;
}

// LES REFLETS du dessin : la petite croix en haut à droite, la virgule sur le
// flanc droit, le liseré en pointillé en bas à gauche
bool dans_reflets(vec2 e) {
	float fois = max(1.0, floor(grandeur() + 0.5));
	float cale = mod(fois, 2.0) > 0.5 ? 0.5 : 0.0;
	float rayon = 0.5 * fois - (fois > 1.5 ? 0.05 : 0.0);
	// la croix
	if (sur_reflet(e, vec2(5.75, 23.5), vec2(7.75, 23.5), cale, rayon)
			|| sur_reflet(e, vec2(6.75, 24.5), vec2(6.75, 22.5), cale, rayon)) {
		return true;
	}
	// la virgule : épaisse en haut, elle s'affine en descendant le long du flanc
	if (sur_reflet(e, vec2(10.75, 19.5), vec2(10.75, 18.5), cale, rayon)
			|| sur_reflet(e, vec2(11.75, 19.5), vec2(11.75, 17.5), cale, rayon)
			|| sur_reflet(e, vec2(11.75, 17.5), vec2(12.75, 17.5), cale, rayon)
			|| sur_reflet(e, vec2(12.75, 17.5), vec2(12.75, 16.5), cale, rayon)
			|| sur_reflet(e, vec2(12.75, 16.5), vec2(13.75, 15.5), cale, rayon)) {
		return true;
	}
	// le liseré du bas
	if (sur_reflet(e, vec2(-16.25, 9.5), vec2(-16.25, 7.5), cale, rayon)
			|| sur_reflet(e, vec2(-16.25, 7.5), vec2(-15.25, 6.5), cale, rayon)
			|| sur_reflet(e, vec2(-15.25, 6.5), vec2(-15.25, 5.5), cale, rayon)
			|| sur_reflet(e, vec2(-13.25, 3.5), vec2(-12.25, 2.5), cale, rayon)
			|| sur_reflet(e, vec2(-12.25, 2.5), vec2(-11.25, 2.5), cale, rayon)) {
		return true;
	}
	return false;
}

// la hauteur du haut de l'ombre sous la case `e` (en cases) : celle du dessin,
// lue colonne par colonne et raccordée entre deux, plus le balancement
float haut_de_l_ombre(vec2 e) {
	float a = demi_largeur * echelle.x;
	float h = hauteur * echelle.y;
	float colonne = clamp(e.x / a * REF_DEMI + REF_DEMI - 0.65, 0.0, 35.0);
	int i = int(floor(colonne));
	int j = min(i + 1, 35);
	float ombre = mix(REF_OMBRE[i], REF_OMBRE[j], colonne - float(i));
	return (ombre / REF_HAUT + houle * 0.11 * e.x / a) * h;
}

void fragment() {
	vec2 q = (local - pieds) / pixel;
	vec2 p = vec2(floor(q.x) + 0.5, -floor(q.y) - 0.5);
	float a = demi_largeur * echelle.x;
	float h = hauteur * echelle.y;

	// loin de tout : rien à calculer
	bool gouttes = (mort >= 0.0 && mort <= GERBE) || (eclabousse >= 0.0 && eclabousse <= ECLABOUSSURE);
	if (!gouttes) {
		float portee = a + (abs(penche) + REF_PENCHE) * h + abs(decalage) + 3.0;
		if (abs(p.x) > portee || p.y > h + 4.0 || p.y < 0.0) {
			discard;
		}
	}

	vec3 c = couleur.rgb;
	if (!plein(p)) {
		// LE TRAIT : une case vide qui touche une case pleine
		if (plein(p + vec2(1.0, 0.0)) || plein(p - vec2(1.0, 0.0))
				|| plein(p + vec2(0.0, 1.0)) || plein(p - vec2(0.0, 1.0))) {
			c = couleur_trait.rgb;
		} else {
			discard;
		}
	} else if (dans_corps(p)) {
		vec2 e = dans_le_corps(p);
		// sombre en bas, clair en haut
		if (e.y < haut_de_l_ombre(e)) {
			c = couleur_ombre.rgb;
		}
		if (mort < 0.0) {
			// le noyau et les reflets : placés dans la grille
			vec2 f = vec2(p.x - decalage, p.y - 1.0);
			float g = grandeur();
			float fois = max(1.0, floor(g + 0.5));
			float cale = mod(fois, 2.0) > 0.5 ? 0.5 : 0.0;
			vec2 d = f - du_dessin(REF_NOYAU, cale) - floor(noyau_decale + 0.5);
			if (dot(d, d) <= REF_NOYAU_RAYON * REF_NOYAU_RAYON * g * g) {
				c = couleur_ombre.rgb;
			}
			if (dans_reflets(f)) {
				c = couleur_reflet.rgb;
			}
		}
	}
	COLOR = vec4(etats_monstre(vec4(c, 1.0), local - pieds), 1.0);
}
