shader_type canvas_item;

// ============================================================================
// PREMIER BOSS — FIGURE PROVISOIRE, dessinée ici en attendant ses vraies
// images, d'après son dessin de référence (couleurs et proportions mesurées
// dessus) : une grande créature-phalène, ici vue de face et en vol. Ailes
// ouvertes (lilas, taches mauves, le bas en lambeaux roses et troués), longs
// cheveux violets, deux grandes oreilles roses dedans dont une qui tombe, corps
// clair, bandages gris, pagne de fourrure indigo, jambières lilas, mains carmin
// et pieds roses griffus, une cloche crème et or serrée contre elle, courte
// queue pâle tachetée au bout rose.
// Rendu en GROS PIXELS (`pixel`) : chaque case de la grille est d'une seule
// couleur, sans dégradé. Le trait d'encre : les cases vides qui touchent une
// case pleine, et les cases d'une pièce qui touchent une pièce posée devant
// elle.
// Tout est piloté par premier_boss_corps.gd à chaque image : le battement des
// ailes, leur repli, le bras qui se lève, l'éclat du claquement de doigts, la
// tête, les oreilles, la queue, la cloche qui sonne, l'affaissement de la mort.
// Ses états (éclair de coup, teinte, fissures, cristal) sont ceux de tous les
// monstres : etats_monstre.gdshaderinc.
// Les longueurs sont en UNITÉS DU DESSIN (`unite` cases chacune), l'origine au
// milieu de la poitrine, y vers le haut ; son point le plus bas (ses pieds) est
// BAS unités plus bas, et le bout de ses ailes ouvertes à 96 unités de son milieu.
// ============================================================================
#include "res://SCRIPT/MONSTER/etats_monstre.gdshaderinc"

// son point le plus bas, dans le rectangle (px d'écran)
uniform vec2 pieds = vec2(644.0, 693.0);
// le côté d'une case (px d'écran)
uniform float pixel = 1.75;
// le nombre de cases d'une unité du dessin
uniform float unite = 3.54;

// --- ce qui bouge ---
// les ailes du haut et du bas : de combien elles sont levées (degrés ; négatif :
// baissées)
uniform float aile_haut = 0.0;
uniform float aile_bas = 0.0;
// 0 : ailes ouvertes ; 1 : repliées le long du corps
uniform float repli = 0.0;
// 0 : la main libre sur la cloche ; 1 : le bras levé, la main au-dessus de l'épaule
uniform float bras = 0.0;
// l'éclat du claquement de doigts (0 : aucun ; 1 : au plus grand)
uniform float claque = 0.0;
// la tête : de combien elle monte (unités ; négatif : elle se baisse)
uniform float tete = 0.0;
// les oreilles : de combien elles se lèvent (degrés ; négatif : elles tombent)
uniform float oreilles = 0.0;
// le balancement de la queue (radians)
uniform float queue = 0.0;
// la cloche : de combien elle penche autour de son anneau (degrés)
uniform float cloche = 0.0;
// 0 : les yeux fermés ; 1 : ouverts (la phase 2)
uniform float yeux = 0.0;
// 0 : en vol ; 1 : affaissée, le bas de son corps sous la ligne du sol
uniform float affaisse = 0.0;

// de la poitrine à son point le plus bas, ses pieds (unités)
const float BAS = 42.0;
// affaissée, elle descend d'autant (unités)
const float AFFAISSEMENT = 25.0;
// la hauteur du milieu de sa tête, au-dessus de la poitrine (unités)
const float TETE = 14.5;
// l'attache du bras libre, et la longueur de son avant-bras
const vec2 EPAULE = vec2(-4.4, 2.2);
const float AVANT_BRAS = 8.0;

const vec3 C_TRAIT = vec3(0.03, 0.0, 0.03);

// le rayon de l'aile du haut selon l'angle autour de son attache, de -40° à
// 80° par pas de 5° (0° : à l'horizontale vers l'extérieur ; le bout vers 10°)
const float AILE_HAUTE[25] = {
	0.0, 30.0, 36.0, 43.0, 46.0, 48.0, 50.0, 53.0, 57.0, 66.0, 89.0, 85.0, 75.0,
	56.0, 43.0, 37.0, 33.0, 30.0, 28.0, 25.0, 23.0, 20.0, 17.0, 9.0, 0.0
};
// celui de l'aile du bas, de -75° à -5° par pas de 5° (le bout vers -35°)
const float AILE_BASSE[15] = {
	0.0, 12.0, 18.0, 22.0, 26.0, 33.0, 41.0, 52.0, 57.0, 50.0, 43.0, 38.0, 30.0,
	18.0, 0.0
};
// la queue, de son attache à sa pointe : courte, elle s'arrête à hauteur de
// genou (mesurée sur le dessin de référence : 19 unités de long)
const vec2 QUEUE_PTS[9] = {
	vec2(-0.8, -14.5), vec2(-1.6, -17.0), vec2(-2.6, -19.4), vec2(-3.8, -21.6),
	vec2(-5.3, -23.5), vec2(-7.2, -25.0), vec2(-9.3, -26.0), vec2(-11.5, -26.5),
	vec2(-13.6, -26.3)
};

varying vec2 local;

void vertex() {
	local = VERTEX;
}

// les couleurs du dessin de référence
vec3 pb_couleur(int c) {
	if (c == 1) { return vec3(0.863, 0.82, 0.933); }     // l'aile, lilas
	if (c == 2) { return vec3(0.906, 0.537, 0.659); }    // ses lambeaux roses
	if (c == 3) { return vec3(0.769, 0.463, 0.647); }    // leur bord, plus sombre
	if (c == 4) { return vec3(0.71, 0.45, 0.66); }       // ses taches mauves
	if (c == 5) { return vec3(0.545, 0.498, 0.773); }    // les cheveux
	if (c == 6) { return vec3(0.443, 0.357, 0.651); }    // leur ombre
	if (c == 7) { return vec3(0.996, 0.957, 0.925); }    // la peau
	if (c == 8) { return vec3(0.635, 0.514, 0.612); }    // les plis des bandages
	if (c == 9) { return vec3(0.733, 0.282, 0.498); }    // les mains
	if (c == 10) { return vec3(0.925, 0.553, 0.659); }   // le dedans des oreilles
	if (c == 11) { return vec3(0.996, 0.925, 0.925); }   // la queue, pâle
	if (c == 12) { return vec3(0.933, 0.353, 0.533); }   // ses taches, son bout, le pied de devant
	if (c == 13) { return vec3(0.988, 0.918, 0.796); }   // la cloche
	if (c == 14) { return vec3(0.969, 0.733, 0.447); }   // son or
	if (c == 15) { return vec3(0.816, 0.686, 0.784); }   // les jambières
	if (c == 16) { return vec3(0.365, 0.357, 0.616); }   // le pagne de fourrure
	if (c == 17) { return vec3(1.0, 0.93, 0.98); }       // l'éclat du claquement
	if (c == 18) { return vec3(0.93, 0.8, 0.75); }       // les griffes
	if (c == 20) { return vec3(0.714, 0.592, 0.784); }   // l'aile, près du corps
	if (c == 21) { return vec3(0.776, 0.718, 0.733); }   // les bandages
	if (c == 23) { return vec3(0.769, 0.251, 0.455); }   // le pied de derrière
	if (c == 24) { return vec3(0.761, 0.396, 0.557); }   // le dedans des oreilles, à l'ombre
	if (c == 25) { return vec3(0.25, 0.6, 0.6); }        // les gemmes de la cloche
	if (c == 26) { return vec3(0.302, 0.259, 0.522); }   // le pagne, à l'ombre
	if (c == 27) { return vec3(0.93, 0.88, 0.97); }      // les touffes de fourrure
	if (c == 28) { return vec3(0.8, 0.14, 0.4); }        // ses yeux ouverts
	if (c == 29) { return vec3(1.0, 0.96, 0.98); }       // leur reflet
	return C_TRAIT;                                       // 19 : les traits du visage
}

// un hasard ENTIER (le même partout, sur toutes les cartes)
uint pb_hacher(uint x) {
	x ^= x >> 16u;
	x *= 0x7feb352du;
	x ^= x >> 15u;
	x *= 0x846ca68bu;
	x ^= x >> 16u;
	return x;
}

float pb_alea(int n, int canal) {
	uint h = pb_hacher(uint(n + 8192) * 747796405u + uint(canal) * 2891336453u + 12345u);
	return float(h & 0xffffffu) / 16777215.0;
}

// des dents : 0 aux nombres entiers, 1 à mi-chemin
float pb_tri(float x) {
	return 1.0 - abs(fract(x) - 0.5) * 2.0;
}

vec2 pb_dir(float deg) {
	return vec2(cos(radians(deg)), sin(radians(deg)));
}

// la distance au segment a→b ; `t` : où sur le segment (0 en a, 1 en b)
float pb_segment(vec2 p, vec2 a, vec2 b, out float t) {
	vec2 ab = b - a;
	t = clamp(dot(p - a, ab) / max(dot(ab, ab), 0.0001), 0.0, 1.0);
	return length(p - a - ab * t);
}

// LAMBEAUX : des encoches en V le long d'un bord, une tous les `pas` degrés, de
// profondeur au hasard (de 0 à 1)
float pb_lambeaux(float deg, float pas, int canal) {
	float f = deg / pas;
	float i = floor(f + 0.5);
	float prof = 0.25 + 0.75 * pb_alea(int(i), canal);
	return prof * max(0.0, 1.0 - abs(f - i) * 2.7);
}

// une tache ovale, couchée dans le sens de l'aile
bool pb_tache(vec2 w, vec2 centre, float longueur, float largeur) {
	vec2 d = (w - centre) / vec2(longueur, largeur);
	return dot(d, d) < 1.0;
}

// L'AILE DU HAUT (`m` : le point, replié du côté droit ; `cote` : le hasard de
// ce côté-là). Lilas, plus sombre près du corps, des taches mauves ; son bord
// bas en lambeaux roses, troués.
int pb_aile_haute(vec2 m, int cote) {
	vec2 v = m - vec2(6.0, 4.0);
	float r = length(v) / (1.0 - 0.45 * repli);
	if (r > 92.0 || r < 0.01) {
		return 0;
	}
	float deg = degrees(atan(v.y, v.x)) - aile_haut + 80.0 * repli;
	float f = (deg + 40.0) / 5.0;
	if (f <= 0.0 || f >= 24.0) {
		return 0;
	}
	int i = int(floor(f));
	float rayon = mix(AILE_HAUTE[i], AILE_HAUTE[i + 1], f - float(i));
	float ampleur = 0.42 * (1.0 - smoothstep(1.0, 9.0, deg));
	if (r > rayon * (1.0 - ampleur * pb_lambeaux(deg, 4.3, cote))) {
		return 0;
	}
	vec2 w = r * pb_dir(deg);
	// les trous des lambeaux
	if (pb_tache(w, 32.9 * pb_dir(-24.0), 3.2, 1.9) || pb_tache(w, 40.5 * pb_dir(-9.0), 3.6, 2.3)
			|| pb_tache(w, 48.0 * pb_dir(2.5), 2.6, 1.8) || pb_tache(w, 28.0 * pb_dir(-12.0), 1.5, 1.1)) {
		return 0;
	}
	float rho = r / max(rayon, 0.01);
	// près du corps, le lilas fonce
	if (rho < 0.25 + 0.03 * pb_tri(deg / 3.1)) {
		return 20;
	}
	// les taches mauves du lilas
	if (pb_tache(w, vec2(38.0, 7.0), 3.6, 1.9) || pb_tache(w, vec2(57.0, 15.0), 2.9, 1.6)
			|| pb_tache(w, vec2(30.0, 17.0), 2.2, 1.4) || pb_tache(w, vec2(70.0, 12.5), 2.4, 1.3)
			|| pb_tache(w, vec2(47.0, 22.0), 1.6, 1.1)) {
		return 4;
	}
	// les lambeaux, en flammes
	float seuil = 0.6 + 0.5 * smoothstep(0.0, 14.0, deg) - 0.07 * pb_tri(deg / 2.3);
	if (rho > seuil + 0.2) {
		return 3;
	}
	if (rho > seuil) {
		return 2;
	}
	return 1;
}

// L'AILE DU BAS : plus étroite, presque toute en lambeaux
int pb_aile_basse(vec2 m, int cote) {
	vec2 v = m - vec2(5.0, -9.0);
	float r = length(v) / (1.0 - 0.4 * repli);
	if (r > 60.0 || r < 0.01) {
		return 0;
	}
	float deg = degrees(atan(v.y, v.x)) - aile_bas + 30.0 * repli;
	float f = (deg + 75.0) / 5.0;
	if (f <= 0.0 || f >= 14.0) {
		return 0;
	}
	int i = int(floor(f));
	float rayon = mix(AILE_BASSE[i], AILE_BASSE[i + 1], f - float(i));
	float ampleur = 0.12 + 0.3 * (1.0 - smoothstep(-42.0, -30.0, deg));
	if (r > rayon * (1.0 - ampleur * pb_lambeaux(deg + 1.7, 4.6, cote + 7))) {
		return 0;
	}
	vec2 w = r * pb_dir(deg);
	if (pb_tache(w, vec2(31.0, -24.0), 2.4, 1.5) || pb_tache(w, vec2(36.0, -17.0), 1.7, 1.1)) {
		return 0;
	}
	float rho = r / max(rayon, 0.01);
	if (rho < 0.3) {
		return 20;
	}
	float seuil = 0.44 - 0.08 * pb_tri(deg / 2.6);
	if (rho > seuil + 0.26) {
		return 3;
	}
	if (rho > seuil) {
		return 2;
	}
	return 1;
}

// LES CHEVEUX DE DEVANT : une calotte hérissée de mèches, qui laisse une
// fenêtre au visage sous une frange en dents
int pb_cheveux(vec2 q) {
	vec2 h = q - vec2(0.0, TETE + tete);
	float r = length(h);
	if (r > 15.5) {
		return 0;
	}
	float a = atan(h.x, h.y);                      // 0 : vers le haut
	if (r > 11.6 + 3.2 * pow(pb_tri(a * 1.75 + 0.5), 1.4)) {
		return 0;
	}
	// de chaque côté du visage, elle finit en mèches
	if (h.y < -8.5 + 2.6 * pb_tri(h.x / 2.7)) {
		return 0;
	}
	if (abs(h.x) < 5.7 && h.y < 1.4 - 2.3 * pb_tri(h.x / 3.1 + 0.5)) {
		return 0;
	}
	if (r > 5.0 && pb_tri(a * 2.6 + 0.2) < 0.13) {
		return 6;
	}
	return 5;
}

// LE VISAGE, tête baissée : les yeux fermés sous un trait violet, la bouche
int pb_visage(vec2 q) {
	vec2 h = q - vec2(0.0, TETE + tete);
	vec2 e = h + vec2(0.0, 2.2);
	if (e.x * e.x / 40.0 + e.y * e.y / 56.0 > 1.0) {
		return 0;
	}
	float ax = abs(h.x);
	float oeil = -2.3 - 0.28 * (ax - 3.0) * (ax - 3.0);
	if (yeux > 0.5) {
		// ouverts : un iris carmin sous la paupière, un reflet
		vec2 d = (vec2(ax, h.y) - vec2(3.0, -2.9)) / vec2(0.95, 1.25);
		if (dot(d, d) < 1.0) {
			vec2 r = vec2(ax, h.y) - vec2(2.65, -2.45);
			return (dot(r, r) < 0.14) ? 29 : 28;
		}
		if (ax > 1.5 && ax < 4.6 && abs(h.y - oeil + 0.3) < 0.3 && h.y > oeil - 0.9) {
			return 19;
		}
	} else if (ax > 1.5 && ax < 4.6 && abs(h.y - oeil) < 0.34) {
		return 19;
	}
	if (ax > 2.0 && ax < 4.3 && abs(h.y - oeil - 1.5) < 0.3) {
		return 6;
	}
	if (ax < 0.75 && abs(h.y + 6.4) < 0.28) {
		return 19;
	}
	return 7;
}

// LES OREILLES : deux longues feuilles pointues, roses dedans ; l'une est
// couchée, presque à l'horizontale, l'autre tombe
int pb_oreilles(vec2 q) {
	vec2 h = vec2(abs(q.x), q.y) - vec2(5.5, TETE + 2.0 + tete);
	if (h.x < -1.0 || h.x > 27.0 || h.y > 12.0 || h.y < -24.0) {
		return 0;
	}
	vec2 axe = pb_dir(((q.x < 0.0) ? 7.0 : -40.0) + oreilles);
	float s = dot(h, axe) / 24.0;
	if (s < 0.0 || s > 1.0) {
		return 0;
	}
	float n = dot(h, vec2(-axe.y, axe.x));
	float w = 4.7 * pow(sin(3.14159 * pow(s, 0.8)), 0.8) * (1.0 - 0.45 * s);
	if (abs(n) > w) {
		return 0;
	}
	if (s > 0.1 && s < 0.9 && n > -0.78 * w && n < 0.3 * w) {
		return (n < -0.36 * w) ? 24 : 10;
	}
	return 7;
}

// LES TOUFFES de fourrure de ses épaules
int pb_touffes(vec2 q) {
	vec2 e = vec2(abs(q.x), q.y) - vec2(5.1, 3.5);
	if (length(e) < 1.7 + 0.7 * pb_tri(atan(e.y, e.x) * 1.4)) {
		return 27;
	}
	return 0;
}

// un bras : le haut bandé, l'avant-bras nu, une touffe au poignet, la main carmin
int pb_bras(vec2 q, vec2 epaule, vec2 coude, vec2 main) {
	if (length(q - main) <= 2.0) {
		return 9;
	}
	float t;
	float d = pb_segment(q, coude, main, t);
	if (t > 0.6 && t < 0.86 && d <= 2.1) {
		return 27;
	}
	if (d <= mix(1.65, 1.4, t)) {
		return 7;
	}
	d = pb_segment(q, epaule, coude, t);
	if (d <= 1.8) {
		return (fract(t * 4.0 + 0.1) < 0.22) ? 8 : 21;
	}
	return 0;
}

// la main du bras libre, et vers où pointe son avant-bras : posée sur la
// cloche (0), ou levée (1) — le bras s'écarte du corps pour monter
vec2 pb_main_libre(out vec2 vers) {
	vec2 coude = EPAULE + 9.0 * pb_dir(mix(-118.0, -212.0, bras));
	vers = pb_dir(mix(-15.0, -262.0, bras));
	return coude + AVANT_BRAS * vers;
}

// LE BRAS LIBRE : la main sur la cloche, ou levé pour claquer des doigts
int pb_bras_libre(vec2 q) {
	vec2 vers;
	vec2 main = pb_main_libre(vers);
	return pb_bras(q, EPAULE, main - AVANT_BRAS * vers, main);
}

// L'ÉCLAT du claquement de doigts : une étoile à quatre branches, au bout de la main
int pb_eclat(vec2 q) {
	if (claque < 0.03) {
		return 0;
	}
	vec2 vers;
	vec2 main = pb_main_libre(vers);
	vec2 e = abs(q - main - 3.2 * vers) / (8.5 * claque);
	if (pow(e.x, 0.6) + pow(e.y, 0.6) < 1.0) {
		return 17;
	}
	return 0;
}

// LA CLOCHE, tenue à deux mains contre elle : l'anneau d'or, le dôme, la
// ceinture, la robe évasée à festons ; des gemmes sur le dôme et sur la robe
int pb_cloche(vec2 q) {
	vec2 axe = normalize(vec2(0.14, -1.0));
	vec2 r = q - vec2(2.4, -2.6);                  // le haut du dôme
	// elle se balance autour de son anneau
	vec2 pivot = -1.6 * axe;
	vec2 tourne = pb_dir(-cloche);
	r -= pivot;
	r = vec2(tourne.x * r.x - tourne.y * r.y, tourne.y * r.x + tourne.x * r.y) + pivot;
	float da = length(r + 1.6 * axe);
	if (da < 1.65) {
		return (da > 0.8) ? 14 : 0;
	}
	float u = dot(r, axe) / 14.0;                  // 0 : le haut ; 1 : le bas des festons
	float v = dot(r, vec2(-axe.y, axe.x));
	if (u < 0.0 || u > 0.93 + 0.07 * abs(sin(3.14159 * (v / 2.5 + 0.5)))) {
		return 0;
	}
	float demi = 4.1;
	if (u < 0.56) {
		demi = 4.7 * sqrt(min(u / 0.2, 1.0));
	} else if (u >= 0.64) {
		demi = mix(4.6, 7.6, pow((u - 0.64) / 0.36, 0.75));
	}
	if (abs(v) > demi) {
		return 0;
	}
	if (length(vec2(abs(v) - 2.3, (u - 0.36) * 14.0)) < 0.8
			|| length(vec2(v - 2.5 * floor(v / 2.5 + 0.5), (u - 0.79) * 14.0)) < 0.72) {
		return 25;
	}
	if ((u >= 0.56 && u < 0.64) || u > 0.88 || abs(u - 0.13) < 0.022) {
		return 14;
	}
	return 13;
}

// LE TORSE : le cou, la poitrine serrée d'une bande, une sangle en travers
int pb_torse(vec2 q) {
	if (abs(q.x) < 1.7 && q.y >= 4.0 && q.y < 7.5) {
		return 7;
	}
	if (q.y > 4.2 || q.y < -16.5) {
		return 0;
	}
	float k = (4.2 - q.y) / 20.7;
	float demi = (4.9 - 1.1 * sin(3.14159 * k)) * sqrt(max(1.0 - pow(abs(2.0 * k - 1.0), 6.0), 0.0));
	if (abs(q.x) > demi) {
		return 0;
	}
	if (abs(dot(q - vec2(-4.2, 4.0), vec2(0.816, 0.578))) < 0.85) {
		return 21;
	}
	if (q.y > -3.8 && q.y < 1.0) {
		return (fract((q.y + 0.25 * q.x) / 1.6) < 0.24) ? 8 : 21;
	}
	return 7;
}

// LE PAGNE de fourrure, au bord déchiqueté
int pb_pagne(vec2 q) {
	if (q.y > -11.8 || q.y < -21.5) {
		return 0;
	}
	float bord = -17.2 - 3.4 * pb_tri(q.x / 2.1 + 0.2);
	if (q.y < bord || abs(q.x) > mix(5.0, 6.4, clamp((-11.8 - q.y) / 6.0, 0.0, 1.0))) {
		return 0;
	}
	return (q.y < bord + 1.6) ? 26 : 16;
}

// une jambe : la cuisse nue, le genou bandé, la jambière, le pied griffu
int pb_jambe(vec2 q, vec2 hanche, vec2 genou, vec2 cheville, vec2 pied, int couleur_pied) {
	vec2 vers = normalize(pied - cheville);
	vec2 travers = vec2(-vers.y, vers.x);
	for (int i = -1; i <= 1; i++) {
		vec2 g = pied + vers * (1.5 - 0.3 * abs(float(i))) + travers * (float(i) * 0.95);
		if (length(q - g) < 0.52) {
			return 18;
		}
	}
	float t;
	float d = pb_segment(q, cheville, pied, t);
	if (d <= mix(2.0, 1.3, t)) {
		return couleur_pied;
	}
	d = pb_segment(q, genou, cheville, t);
	if (d <= mix(2.1, 1.6, t)) {
		return (fract(t * 3.0 + 0.55) < 0.1) ? 8 : 15;
	}
	d = pb_segment(q, hanche, genou, t);
	if (d <= mix(2.5, 2.0, t)) {
		if (t > 0.52) {
			return (fract(t * 7.0) < 0.22) ? 8 : 21;
		}
		return 7;
	}
	return 0;
}

// LA QUEUE : courte et fine, elle descend et part de côté, en pointe ; pâle et
// tachetée, le bout rose ; il se balance à peine
int pb_queue(vec2 q) {
	if (q.x > 3.0 || q.x < -18.0 || q.y > -12.0 || q.y < -30.0) {
		return 0;
	}
	for (int i = 0; i < 8; i++) {
		float ta = float(i) / 8.0;
		float tb = float(i + 1) / 8.0;
		vec2 a = QUEUE_PTS[i] + vec2(0.0, ta * ta * 1.1 * sin(queue + ta * 2.2));
		vec2 b = QUEUE_PTS[i + 1] + vec2(0.0, tb * tb * 1.1 * sin(queue + tb * 2.2));
		float t;
		float d = pb_segment(q, a, b, t);
		float ou = mix(ta, tb, t);
		if (d <= mix(1.3, 0.3, pow(ou, 1.3))) {
			if (ou > 0.55) {
				return 12;
			}
			// ses taches, placées le long d'elle : elles la suivent quand elle bouge
			vec2 ab = b - a;
			float cote = sign(ab.x * (q.y - a.y) - ab.y * (q.x - a.x));
			vec2 lieu = vec2(ou * 19.0, cote * d + 8.0);
			vec2 g = floor(lieu / 1.1);
			if (ou > 0.12 && pb_alea(int(g.x) * 57 + int(g.y) * 131, 5) < 0.42
					&& length(lieu - (g + 0.5) * 1.1) < 0.42) {
				return 12;
			}
			return 11;
		}
	}
	return 0;
}

// LES CHEVEUX DU DOS : la masse sombre qui tombe derrière elle, en mèches
int pb_cheveux_dos(vec2 q) {
	if (q.y > TETE + tete || q.y < -14.5 + 3.2 * pb_tri(q.x / 3.3 + 0.3)) {
		return 0;
	}
	if (abs(q.x) > mix(8.6, 12.6, smoothstep(-14.0, 0.0, q.y))) {
		return 0;
	}
	return 6;
}

// CE QU'IL Y A DANS LA CASE `p` (cases depuis son point le plus bas, y vers le
// haut) : 0 si elle est vide, sinon 32 × le rang de la pièce (plus grand :
// plus devant) + sa couleur
int pb_matiere(vec2 p) {
	if (p.y < 0.0) {
		return 0;
	}
	vec2 q = vec2(p.x / unite, p.y / unite - BAS + AFFAISSEMENT * affaisse);
	int c;
	if (abs(q.x) < 34.0 && q.y < 34.0) {
		c = pb_eclat(q);
		if (c != 0) { return 544 + c; }
		c = pb_bras_libre(q);
		if (c != 0) { return 512 + c; }
		c = pb_bras(q, vec2(4.4, 2.2), vec2(9.6, -3.6), vec2(7.3, -7.0));
		if (c != 0) { return 480 + c; }
		c = pb_touffes(q);
		if (c != 0) { return 448 + c; }
		c = pb_cheveux(q);
		if (c != 0) { return 416 + c; }
		c = pb_visage(q);
		if (c != 0) { return 384 + c; }
		c = pb_oreilles(q);
		if (c != 0) { return 352 + c; }
		c = pb_cloche(q);
		if (c != 0) { return 320 + c; }
		c = pb_pagne(q);
		if (c != 0) { return 288 + c; }
		c = pb_torse(q);
		if (c != 0) { return 224 + c; }
		c = pb_jambe(q, vec2(2.0, -14.5), vec2(5.4, -22.5), vec2(1.4, -29.5), vec2(0.2, -35.0), 12);
		if (c != 0) { return 192 + c; }
		c = pb_jambe(q, vec2(-2.2, -14.5), vec2(-3.8, -24.5), vec2(-2.6, -34.0), vec2(-3.4, -39.8), 23);
		if (c != 0) { return 160 + c; }
		c = pb_queue(q);
		if (c != 0) { return 128 + c; }
		c = pb_cheveux_dos(q);
		if (c != 0) { return 96 + c; }
	}
	vec2 m = vec2(abs(q.x), q.y);
	int cote = (q.x < 0.0) ? 31 : 37;
	c = pb_aile_haute(m, cote);
	if (c != 0) { return 64 + c; }
	c = pb_aile_basse(m, cote);
	if (c != 0) { return 32 + c; }
	return 0;
}

void fragment() {
	vec2 g = (local - pieds) / pixel;
	vec2 p = vec2(floor(g.x) + 0.5, -floor(g.y) - 0.5);
	int ici = pb_matiere(p);
	int voisine = max(max(pb_matiere(p + vec2(1.0, 0.0)), pb_matiere(p - vec2(1.0, 0.0))),
			max(pb_matiere(p + vec2(0.0, 1.0)), pb_matiere(p - vec2(0.0, 1.0))));
	vec3 rgb = C_TRAIT;
	if (ici == 0) {
		// LE TRAIT du pourtour : une case vide qui touche une case pleine
		if (voisine == 0) {
			discard;
		}
	} else if (voisine / 32 <= ici / 32) {
		// (sinon : le trait d'une pièce posée devant celle-ci)
		rgb = pb_couleur(ici % 32);
	}
	COLOR = vec4(etats_monstre(vec4(rgb, 1.0), local - pieds), 1.0);
}
