shader_type canvas_item;
render_mode unshaded;
// SLASH DU HÉROS — le croissant blanc des attaques, refait en shader d'après
// les dessins (30 sept. 2026) : même trajet, mêmes étendues, même allure, mais
// à chaque image d'écran au lieu de six dessins.
//
// Tout vient de MESURES faites sur les dessins (voir slash_heros.gd) :
//   • le TRAJET — autour d'un centre, le bord extérieur de tous les croissants
//     mis ensemble suit la courbe
//         r(θ) = a0 + a1·cos θ + b1·sin θ + a2·cos 2θ + b2·sin 2θ      (`forme`)
//   • la LAME — à un instant donné elle occupe ce trajet de l'angle `queue` à
//     l'angle `tete`. Entre les deux, douze relevés pris de la queue à la tête
//     disent de combien son bord extérieur sort du trajet (`dehors`), son
//     épaisseur vers le centre (`large`) et son opacité (`voile`) : la queue
//     est large, voilée, aux bords flous ; le corps est blanc plein, aux bords
//     nets ; la tête s'effile en pointe.
//   • les FILETS — les petits traits dessinés autour du croissant, repérés le
//     long de la lame : ils la suivent, ceux d'un dessin s'effacent pendant que
//     ceux du suivant apparaissent.
// slash_heros.gd fait glisser tout ça d'un dessin au suivant au fil du temps.
//
// FEU (`feu` > 0, 1er oct. 2026 : le slash du squelette bleu, le lanceur de
// boules de feu) : le même croissant, FAIT de feu. La famille du feu du jeu
// (boule_de_feu, jet_flamme) : bruit à gradients qui MONTE (les flammes
// s'élèvent à l'écran), aplats cartoon en bandes, même palette de quatre
// couleurs. La lame garde sa silhouette mesurée, gonflée de quelques px et
// rongée par le bruit ; la tête est la plus chaude (cœur clair), la queue
// refroidit ; derrière elle, le chemin parcouru brûle encore un moment
// (`residu_feu`) en se déchirant ; quelques braises montent.
//
// FOUDRE (`foudre` > 0) : le même croissant, mais FAIT de foudre. Sa chair
// devient un plasma bleu pâle aux bords crénelés qui garde la silhouette, et
// dedans courent des BRINS de foudre — des lignes brisées blanches qui se
// tressent d'un bord à l'autre de la queue à la pointe, et qui changent
// `cadence` fois par seconde. Rien ne dépasse de la lame : ni éclairs, ni
// poils. Un halo bleu l'entoure, quelques étincelles sautent, et là où la lame
// est passée l'électricité traîne un peu (`residu`) avant de s'éteindre. Les
// brins sont ancrés le long du trajet, pas sur la lame : la lame avance à
// travers une décharge qui, elle, reste en place.

const int N = 12;           // nombre de relevés le long de la lame
const int NB_FILETS = 8;    // quatre pour le dessin qu'on quitte, quatre pour le suivant
const float GRILLE = 22.0;  // la grille des étincelles (px)

// --- fournis par slash_heros.gd -----------------------------------------------
// taille du rectangle (px), et centre du trajet depuis le centre du rectangle
uniform vec2 taille = vec2(650.0, 650.0);
uniform vec2 centre = vec2(48.4, -36.1);
// la courbe du trajet : (a0, a1, b1, a2) et b2
uniform vec4 forme = vec4(127.59, -10.0, -2.59, 17.62);
uniform float forme_b2 = 4.23;
// où est la lame : de `queue` à `tete` (radians, tete ≥ queue)
uniform float queue = -1.64;
uniform float tete = 0.72;
// les relevés, de la queue à la tête (px, px, 0…1)
uniform float dehors[12];
uniform float large[12];
uniform float voile[12];
// les filets, six nombres chacun : début et fin le long de la lame (0 = queue,
// 1 = tête), distance au trajet à ses deux bouts (px, positif vers le centre),
// demi-épaisseur (px), opacité
uniform float filets[48];
uniform float opacite : hint_range(0.0, 1.0) = 1.0;
// pour la foudre : le temps qui passe (s), l'angle où la lame est née
// (radians), sa vie (1, puis 0 quand elle s'éteint), un nombre par instance
uniform float temps = 0.0;
uniform float origine = -2.5;
uniform float vie = 1.0;
uniform float graine = 0.0;
// -1 : le slash a été mesuré sur des dessins retournés gauche-droite (celui du
// squelette tourne dans l'autre sens) ; on le retourne au rendu
uniform float miroir = 1.0;
// ------------------------------------------------------------------------------

// --- l'allure ---
// force des filets (0 = aucun, 1 = comme sur les dessins)
uniform float traits : hint_range(0.0, 1.0) = 1.0;
// flou des bords là où la lame est voilée (part de son épaisseur)
uniform float flou_queue : hint_range(0.0, 0.5) = 0.4;
uniform vec4 couleur : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// --- la foudre (0 = le slash blanc des dessins, 1 = fait de foudre) ---
uniform float foudre : hint_range(0.0, 1.0) = 0.0;
// combien de brins de foudre courent dans la lame
uniform int brins : hint_range(1, 5) = 3;
// épaisseur du cœur blanc des brins (px)
uniform float epaisseur_brins : hint_range(0.5, 4.0) = 1.4;
// combien les brins zigzaguent dans l'épaisseur de la lame (0 = droits)
uniform float zigzag : hint_range(0.0, 0.6) = 0.4;
// combien de fois par seconde les brins changent
uniform float cadence : hint_range(2.0, 60.0) = 20.0;
// opacité de la chair de la lame (le plasma bleu pâle sous les brins)
uniform float remplissage : hint_range(0.0, 1.0) = 0.6;
// crénelage des bords de la lame (px)
uniform float dents : hint_range(0.0, 10.0) = 2.0;
// lueur autour de la lame
uniform float halo : hint_range(0.0, 1.0) = 0.4;
// sur quel angle (radians) l'électricité traîne derrière la queue de la lame,
// là où elle est passée, avant de s'éteindre
uniform float residu : hint_range(0.0, 1.5) = 0.5;
// petites braises qui sautent autour de la lame
uniform float etincelles : hint_range(0.0, 1.0) = 0.3;
// la couleur de la foudre : les brins sont blancs (`couleur`) à cœur, ceci sur
// leurs bords, dans leur lueur et dans la chair de la lame
uniform vec4 couleur_foudre : source_color = vec4(0.45, 0.72, 1.0, 1.0);
// le halo autour de la lame
uniform vec4 couleur_halo : source_color = vec4(0.30, 0.42, 1.0, 1.0);

// --- le feu (0 = le slash blanc des dessins, 1 = fait de feu) ---
uniform float feu : hint_range(0.0, 1.0) = 0.0;
// combien le bord de la lame est rongé par les flammes (0 = lisse)
uniform float flammes : hint_range(0.0, 2.0) = 1.3;
// de combien le feu déborde de la lame dessinée (px)
uniform float gonflement : hint_range(0.0, 20.0) = 5.0;
// épaisseur du feu par rapport à la lame dessinée (1 = la même)
uniform float epaisseur_feu : hint_range(0.5, 4.0) = 1.9;
// les LANGUES de flammes sur les bords : jusqu'où elles montent (px ; celles
// du dessous de la lame restent courtes, les flammes montent), et leur largeur
uniform float hauteur_flammes : hint_range(0.0, 60.0) = 28.0;
uniform float largeur_langues : hint_range(2.0, 30.0) = 10.0;
// taille des paquets de feu (px) et vitesse à laquelle ils montent (px/s)
uniform float taille_flammes : hint_range(4.0, 60.0) = 12.0;
uniform float vitesse_flammes : hint_range(0.0, 600.0) = 220.0;
// sur quel angle (radians) le chemin parcouru brûle encore derrière la queue
uniform float residu_feu : hint_range(0.0, 2.0) = 1.1;
// chaleur maximale (1 = jusqu'au cœur clair)
uniform float chaleur_max : hint_range(0.0, 1.3) = 1.0;
// braises qui montent au-dessus du feu
uniform float braises : hint_range(0.0, 1.0) = 0.5;
// lueur autour du feu
uniform float halo_feu : hint_range(0.0, 1.0) = 0.35;
// 1 = aplats dessin animé (comme la boule de feu), 0 = dégradé doux
uniform float style_cartoon_feu : hint_range(0.0, 1.0) = 1.0;
uniform int nb_bandes_feu : hint_range(2, 8) = 4;
// la palette de la boule de feu du squelette bleu, du plus froid au plus chaud
uniform vec4 feu_exterieur : source_color = vec4(0.9, 0.05, 0.005, 1.0);
uniform vec4 feu_milieu : source_color = vec4(1.0, 0.32, 0.01, 1.0);
uniform vec4 feu_interieur : source_color = vec4(1.0, 0.85, 0.15, 1.0);
uniform vec4 feu_coeur : source_color = vec4(1.0, 1.0, 0.75, 1.0);
uniform vec4 couleur_halo_feu : source_color = vec4(1.0, 0.28, 0.04, 1.0);

// (PI et TAU sont fournis par le langage de shader de Godot)

float alea(vec2 p) {
	p = fract(p * vec2(443.897, 441.423));
	p += dot(p, p.yx + 19.19);
	return fract((p.x + p.y) * p.x);
}

// une ligne brisée au hasard : entre -1 et 1, un sommet à chaque entier
float brisee(float x, float g) {
	float i = floor(x);
	float a = alea(vec2(i, g)) * 2.0 - 1.0;
	float b = alea(vec2(i + 1.0, g)) * 2.0 - 1.0;
	return mix(a, b, x - i);
}

// le zigzag d'un brin à `u` px le long du trajet : segments de ~14 px, un
// tremblement plus fin par-dessus, et une dérive lente pour que les brins se
// croisent au lieu de courir côte à côte
float zig(float u, float g) {
	return (brisee(u / 14.0, g) + 0.5 * brisee(u / 6.0 + 9.1, g + 1.7)
			+ 0.8 * brisee(u / 48.0 + 3.3, g + 4.1)) / 1.5;
}

// BRUIT À GRADIENTS du feu (repris de boule_de_feu.gdshader : hash sans sin,
// grille tournée, 3 octaves ; pas de bruit de valeurs, sa grille se voit en
// blocs quand on le seuille)
vec2 gradient_feu(vec2 q) {
	q = fract(q * vec2(123.34, 345.45));
	q += dot(q, q + 34.345);
	return fract(vec2(q.x * q.y, q.x + q.y)) * 2.0 - 1.0;
}

float bruit_feu(vec2 q) {
	vec2 i = floor(q);
	vec2 f = fract(q);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = dot(gradient_feu(i), f);
	float b = dot(gradient_feu(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
	float c = dot(gradient_feu(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
	float d = dot(gradient_feu(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 0.75 + 0.5;
}

float fbm_feu(vec2 q) {
	const mat2 ROT = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	q = ROT * q;
	float v = 0.0;
	float amp = 0.5;
	for (int k = 0; k < 3; k++) {
		v += bruit_feu(q) * amp;
		q = ROT * q * 2.03 + vec2(17.1, 9.2);
		amp *= 0.5;
	}
	return v / 0.875;
}

// la chaleur (0…1) en couleur : rouge, orange, jaune, cœur clair
vec3 rampe_feu(float h) {
	if (h < 0.30) {
		return mix(feu_exterieur.rgb, feu_milieu.rgb, h / 0.30);
	} else if (h < 0.70) {
		return mix(feu_milieu.rgb, feu_interieur.rgb, (h - 0.30) / 0.40);
	}
	return mix(feu_interieur.rgb, feu_coeur.rgb, (h - 0.70) / 0.30);
}

// `dessus` posé sur `dessous` (couleurs non prémultipliées)
vec4 par_dessus(vec4 dessous, vec4 dessus) {
	float a = dessus.a + dessous.a * (1.0 - dessus.a);
	return vec4((dessus.rgb * dessus.a + dessous.rgb * dessous.a * (1.0 - dessus.a)) / max(a, 0.0001), a);
}

void fragment() {
	vec2 p = (UV - 0.5) * taille;
	p.x *= miroir;
	p -= centre;
	float r = length(p);
	float theta = atan(p.y, p.x);
	// un pixel d'écran, en pixels du rectangle : des bords nets à toute échelle
	float px = max(fwidth(p.x), fwidth(p.y)) * 0.75;

	// où est le pixel le long de la lame : 0 à la queue, 1 à la tête
	float milieu = 0.5 * (queue + tete);
	float demi_arc = max(0.5 * (tete - queue), 0.0001);
	float ecart = theta - milieu;
	ecart -= TAU * floor((ecart + PI) / TAU);          // ramené entre -PI et PI
	float phi = milieu + ecart;                        // l'angle, continu autour de la lame
	float s = (ecart + demi_arc) / (2.0 * demi_arc);

	// les relevés à cet endroit de la lame
	float f = clamp(s, 0.0, 1.0) * float(N) - 0.5;
	int i = int(clamp(floor(f), 0.0, float(N - 1)));
	int j = min(i + 1, N - 1);
	float m = clamp(f - float(i), 0.0, 1.0);
	float sortie = mix(dehors[i], dehors[j], m);
	float epais = mix(large[i], large[j], m);
	float blanc = mix(voile[i], voile[j], m);

	// le trajet à cet angle, et la distance du pixel au trajet (positive vers
	// le centre : c'est de ce côté que la lame s'épaissit)
	float rho = forme.x + forme.y * cos(theta) + forme.z * sin(theta)
			+ forme.w * cos(2.0 * theta) + forme_b2 * sin(2.0 * theta);
	float au_trajet = rho - r;

	// --- la foudre : le temps haché, les bords crénelés ---
	float electrique = foudre * vie;
	float tic = floor(temps * cadence + graine * 7.0);   // change `cadence` fois par seconde
	float le_long = phi * forme.x;                       // ≈ px le long du trajet
	float dents_dehors = 0.0;
	float dents_dedans = 0.0;
	if (electrique > 0.001) {
		dents_dehors = dents * brisee(le_long * 0.16 + tic * 3.7, graine + 1.0);
		dents_dedans = dents * brisee(le_long * 0.16 + tic * 3.7 + 50.0, graine + 2.0);
	}

	// --- la lame ---
	float d = au_trajet + sortie + dents_dehors;   // distance à SON bord extérieur
	// la tête s'effile en pointe sur le dernier relevé
	float ep = epais * clamp((1.0 - s) * float(N), 0.0, 1.0);
	ep = max(ep + dents_dedans * clamp(ep / 6.0, 0.0, 1.0), 0.0);   // pas de dents sur la pointe
	// bords nets là où elle est blanche, flous là où elle est voilée
	float flou = mix(flou_queue * ep + px, px, smoothstep(0.55, 0.97, blanc));
	float lame = smoothstep(0.0, flou, d) * smoothstep(0.0, flou, ep - d)
			* blanc * smoothstep(0.0, 0.07, s)         // la queue naît du vide
			* step(0.0, s) * step(s, 1.0);

	// --- les filets ---
	float filet = 0.0;
	for (int k = 0; k < NB_FILETS; k++) {
		float s0 = filets[k * 6];
		float s1 = filets[k * 6 + 1];
		float force = filets[k * 6 + 5];
		if (force <= 0.001 || s1 <= s0) {
			continue;
		}
		float u = (s - s0) / (s1 - s0);
		if (u <= 0.0 || u >= 1.0) {
			continue;
		}
		// effilé à ses deux bouts
		float demi = filets[k * 6 + 4] * pow(sin(u * PI), 0.7);
		float ou = mix(filets[k * 6 + 2], filets[k * 6 + 3], u);
		filet = max(filet, force * smoothstep(0.0, px * 1.5, demi - abs(au_trajet - ou)));
	}
	filet *= traits;

	float brulant = feu * vie;
	if (brulant > 0.001) {
		// =================== LE SLASH FAIT DE FEU ===================
		// (2e version, 1er oct. 2026 : plus épais, moins linéaire, plus de
		// flammes sur les bords) — une bande de feu bien plus épaisse que la
		// lame, presque régulière (un feu ne s'effile pas en aiguille), dont les
		// BORDS sont des langues de flammes qui montent, et dont les bandes de
		// couleur suivent ces flammes au lieu de courir parallèles à la lame.
		//
		// où le feu vit : sur la lame, et derrière sa queue, là où elle est
		// passée, en s'éteignant sur `residu_feu` — jamais avant l'angle où
		// elle est née, jamais devant sa tête
		float o = origine - milieu;
		o -= TAU * floor((o + PI) / TAU);
		o += milieu;
		float derriere = queue - phi;                           // > 0 : déjà balayé
		float age = clamp(derriere / max(residu_feu, 0.001), 0.0, 1.0);
		float en_vie = (derriere <= 0.0)
				? (1.0 - smoothstep(tete, tete + 0.06, phi))
				: (1.0 - smoothstep(0.7, 1.0, age)) * (o < milieu ? smoothstep(o - 0.12, o, phi) : 1.0);
		// L'ÉPAISSEUR : la moitié de l'épaisseur locale de la lame, la moitié de
		// sa plus grande, fois `epaisseur_feu` ; arrondie sur le dernier sixième
		// vers la tête ; plus mince en vieillissant derrière la queue
		float epais_max = 0.0;
		for (int k = 0; k < N; k++) {
			epais_max = max(epais_max, large[k]);
		}
		float bout = sqrt(clamp((1.0 - s) * 6.0, 0.0, 1.0));
		float demi = (mix(epais, epais_max, 0.5) * 0.5 * epaisseur_feu + gonflement) * bout * (1.0 - 0.45 * age);
		// ... qui varie le long du coup : des renflements qui glissent
		demi *= 0.78 + 0.44 * bruit_feu(vec2(le_long / 38.0 + graine, temps * 2.5));
		// distance signée à la LIGNE MÉDIANE de la lame (> 0 vers le centre)
		float w = au_trajet + sortie - epais * 0.5;
		float hors = abs(w);
		if (en_vie <= 0.001 || hors > demi + hauteur_flammes + 30.0) {
			COLOR = vec4(0.0);
		} else {
			// LA MATIÈRE : du bruit qui MONTE à l'écran (vers le haut = -y)
			vec2 q = vec2(p.x, p.y + temps * vitesse_flammes) / taille_flammes + vec2(graine * 3.7, graine * 1.3);
			float gros = fbm_feu(q);
			float fin = fbm_feu(q * 2.4 + vec2(5.3, temps * 3.0));
			float matiere = clamp((mix(gros, fin, 0.35) - 0.28) / 0.44, 0.0, 1.0);
			// LES LANGUES : un bruit étiré en hauteur (2,6 fois plus haut que
			// large), qui monte plus vite que la matière : là où il est fort, le
			// bord du feu s'allonge en flamme
			vec2 ql = vec2(p.x / largeur_langues, (p.y + temps * vitesse_flammes * 1.5) / (largeur_langues * 2.6))
					+ vec2(graine * 1.9, graine * 0.7);
			float langue = smoothstep(0.42, 0.86, fbm_feu(ql));
			// de quel côté de la lame est le pixel, et ce côté regarde-t-il le
			// haut ? Les flammes montent : longues au-dessus, courtes dessous
			vec2 cote = (w < 0.0 ? 1.0 : -1.0) * p / max(r, 0.001);
			float vers_haut = clamp(-cote.y, 0.0, 1.0);
			float portee = hauteur_flammes * mix(0.3, 1.0, vers_haut) * (1.0 - 0.4 * age);
			// LE BORD DU FEU : la demi-épaisseur, allongée par les langues, rongée
			// par la matière ; `e` > 0 dans le feu (px)
			float e = demi + portee * langue + (matiere - 0.5) * flammes * (8.0 + 10.0 * age) - hors;
			float forme_feu = smoothstep(-px, px, e);
			// la traînée se déchire en vieillissant (le seuil monte avec l'âge)
			float seuil = age * 0.9;
			float garde = smoothstep(seuil - 0.12, seuil + 0.04, matiere);
			float corps = forme_feu * garde * en_vie;
			// LA CHALEUR : la distance au BORD DU FEU (pas à la lame) : les
			// bandes de couleur épousent les flammes ; plus chaude vers la tête,
			// refroidit derrière la queue, ce qui se dissout rougit
			float profond = clamp(e / max(demi * 0.9, 1.0), 0.0, 1.0);
			float chaleur = profond * mix(0.62, 1.0, clamp(s, 0.0, 1.0)) * (1.0 - age * 0.8)
					+ (fin - 0.5) * 0.3;
			chaleur *= 0.6 + 0.4 * smoothstep(seuil, seuil + 0.3, matiere);
			chaleur = clamp(chaleur * chaleur_max, 0.0, 1.0);
			float aplat = (floor(chaleur * float(nb_bandes_feu)) + 0.5) / float(nb_bandes_feu);
			chaleur = mix(chaleur, aplat, style_cartoon_feu);
			vec3 rgb_corps = rampe_feu(chaleur);
			float a_corps = mix(corps, smoothstep(0.35, 0.62, corps), style_cartoon_feu);
			// les filets des dessins : de minces langues jaunes
			float a_filet = filet * en_vie * 0.9;
			// LES BRAISES : une grille qui monte avec les flammes, une braise par
			// case de temps en temps, qui scintille, seulement tout près du feu
			vec2 gb = vec2(p.x, p.y + temps * vitesse_flammes * 0.8) / 16.0;
			vec2 cel = floor(gb);
			float braise = 0.0;
			float pres = 1.0 - smoothstep(4.0, 26.0, max(-e, 0.0));
			if (pres > 0.001 && e < 0.0 && alea(cel + vec2(graine, 0.0)) < braises * 0.22) {
				vec2 ou = cel + 0.2 + 0.6 * vec2(alea(cel + vec2(3.1, graine)), alea(cel + vec2(7.7, graine)));
				float db = length((gb - ou) * 16.0);
				float scint = 0.6 + 0.4 * alea(cel + vec2(floor(temps * 14.0), 5.0));
				braise = en_vie * pres * scint * (1.0 - smoothstep(0.9 - px, 1.1 + px, db));
			}
			// LA LUEUR autour du feu
			float lueur = halo_feu * en_vie * (1.0 - age) * (1.0 - smoothstep(0.0, 24.0, max(-e, 0.0)));
			// du fond vers le dessus : la lueur, le feu, les filets, les braises
			vec4 c = vec4(couleur_halo_feu.rgb, lueur * couleur_halo_feu.a);
			c = par_dessus(c, vec4(rgb_corps, a_corps));
			c = par_dessus(c, vec4(rampe_feu(0.8), a_filet));
			c = par_dessus(c, vec4(mix(feu_milieu.rgb, feu_interieur.rgb, 0.65), braise));
			// jamais coupé net par le bord du rectangle
			float bord_rect = smoothstep(0.0, 10.0, min(min(UV.x, 1.0 - UV.x) * taille.x, min(UV.y, 1.0 - UV.y) * taille.y));
			COLOR = vec4(c.rgb, c.a * opacite * bord_rect);
		}
	} else if (electrique <= 0.001) {
		// le slash des dessins, tel quel
		COLOR = vec4(couleur.rgb, couleur.a * max(lame, filet) * opacite);
	} else {
		// =================== LE SLASH FAIT DE FOUDRE ===================
		// où l'électricité vit : sur la lame (1), et derrière sa queue, là où
		// elle est passée, en s'éteignant sur `residu` — jamais avant l'angle
		// où elle est née
		float o = origine - milieu;
		o -= TAU * floor((o + PI) / TAU);
		o += milieu;
		float derriere = queue - phi;
		float activite = max(step(derriere, 0.0) * (1.0 - smoothstep(tete, tete + 0.08, phi)),
				step(0.0, derriere) * (1.0 - smoothstep(0.0, residu, derriere))
				* (o < milieu ? smoothstep(o - 0.15, o, phi) : 1.0));
		activite *= electrique;
		float scintille = 0.8 + 0.2 * alea(vec2(tic, graine + 5.0));

		// la chair de la lame : le plasma bleu pâle qui garde la silhouette du
		// croissant (derrière la queue il continue, en s'éteignant)
		float chair = smoothstep(0.0, flou, d) * smoothstep(0.0, flou, ep - d) * blanc * activite * remplissage;
		vec3 rgb_chair = mix(couleur_foudre.rgb, couleur.rgb, 0.35);
		// les filets des dessins, bleuis et plus discrets
		rgb_chair = mix(rgb_chair, mix(couleur.rgb, couleur_foudre.rgb, 0.5), clamp(filet * 0.6 - chair, 0.0, 1.0));
		chair = max(chair, filet * 0.6 * electrique);

		// le halo autour de la lame, qui traîne derrière sa queue (mesuré sur
		// les bords lisses : les dents feraient des stries dans la lueur)
		float d_lisse = au_trajet + sortie;
		float ep_lisse = epais * clamp((1.0 - s) * float(N), 0.0, 1.0);
		float hors_lame = max(max(-d_lisse, d_lisse - ep_lisse), 0.0);
		float lueur_lame = halo * activite * scintille * (0.4 + 0.6 * blanc)
				* (1.0 - smoothstep(0.0, 24.0, hors_lame));

		// LES BRINS : des lignes brisées blanches qui se tressent dans
		// l'épaisseur de la lame, de la queue à la pointe. Le premier longe le
		// bord extérieur (le tranchant), les autres se partagent l'épaisseur.
		// Ancrés le long du trajet (`le_long`), pas sur la lame.
		float coeur = 0.0;    // le trait blanc
		float lueur = 0.0;    // sa lueur bleue
		if (activite > 0.001 && d > -10.0 && d < ep + 10.0) {
			for (int k = 0; k < brins; k++) {
				float fk = float(k);
				float base = (brins == 1) ? 0.4 : mix(0.12, 0.88, fk / float(brins - 1));
				float ampl = (k == 0) ? zigzag * 0.4 : zigzag;   // le tranchant tremble moins
				// pas tous au même rythme : les impairs changent une fois sur deux
				float tic_k = floor(tic / (1.0 + float(k % 2)));
				float g = fk * 7.3 + tic_k * 3.1 + graine;
				float u = le_long + fk * 37.0;
				float z = zig(u, g);
				float ligne = ep * clamp(base + ampl * z, 0.03, 0.97);
				// distance au brin, qui tient compte de sa pente (sinon les
				// segments raides seraient plus épais)
				float pente = ep * ampl * (zig(u + 1.0, g) - zig(u - 1.0, g)) * 0.5;
				float dist = abs(d - ligne) / sqrt(1.0 + pente * pente);
				float force = activite * (0.5 + 0.5 * blanc) * (0.7 + 0.3 * alea(vec2(fk + 3.0, tic_k + graine)));
				coeur = max(coeur, force * (1.0 - smoothstep(epaisseur_brins - px, epaisseur_brins + px, dist)));
				lueur = max(lueur, force * 0.7 * (1.0 - smoothstep(0.0, epaisseur_brins + 5.0, dist)));
			}
		}

		// les étincelles : une grille autour du trajet, une braise par case de
		// temps en temps
		if (abs(au_trajet) < 70.0 && etincelles > 0.001) {
			vec2 grille = vec2(le_long, au_trajet) / GRILLE;
			vec2 cel = floor(grille);
			float ph_e = (cel.x + 0.5) * GRILLE / forme.x;
			float derr_e = queue - ph_e;
			float act_e = max(step(derr_e, 0.0) * (1.0 - smoothstep(tete, tete + 0.08, ph_e)),
					step(0.0, derr_e) * (1.0 - smoothstep(0.0, residu, derr_e))
					* (o < milieu ? smoothstep(o - 0.15, o, ph_e) : 1.0)) * electrique;
			vec2 cle_e = cel + vec2(tic * 0.37 + graine, 0.0);
			if (alea(cle_e) < etincelles * 0.45 * act_e) {
				vec2 ou = cel + vec2(0.2) + 0.6 * vec2(alea(cle_e + vec2(3.0, 0.0)), alea(cle_e + vec2(7.0, 0.0)));
				vec2 dq = (grille - ou) * GRILLE;
				dq.y *= 0.8;
				float de = length(dq);
				float fe = act_e * (0.6 + 0.4 * alea(cle_e + vec2(9.0, 0.0)));
				coeur = max(coeur, fe * (1.0 - smoothstep(1.0 - px, 1.0 + px, de)));
				lueur = max(lueur, fe * 0.5 * (1.0 - smoothstep(0.0, 3.5, de)));
			}
		}

		// du fond vers le dessus : le halo, la chair, la lueur des brins, les
		// brins eux-mêmes
		vec4 c = vec4(couleur_halo.rgb, lueur_lame * couleur_halo.a);
		c = par_dessus(c, vec4(rgb_chair, chair));
		c = par_dessus(c, vec4(couleur_foudre.rgb, lueur * couleur_foudre.a));
		c = par_dessus(c, vec4(couleur.rgb, coeur));
		COLOR = vec4(c.rgb, c.a * couleur.a * opacite);
	}
}
