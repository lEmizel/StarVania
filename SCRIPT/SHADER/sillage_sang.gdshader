shader_type canvas_item;
render_mode unshaded;
// SILLAGE DE SANG — la brume laissée par la roulade et le dash (talisman
// « Sillage de sang », 1er oct. 2026). sillage_sang.gd lui passe les points du
// trajet (dans le repère du rectangle) avec l'heure où le perso y est passé.
//
// 4e version, d'après une image de référence (très déstructurée, faite de
// bruits empilés ; la 3e ressemblait à des bulles de savon) : une FUMÉE, pas
// des bouffées. Le principe est le « domain
// warping » : un bruit déforme les coordonnées d'un autre bruit, qui déforme
// celles d'un troisième — ce qui enroule la matière en volutes et en rubans.
//   • L'ENVELOPPE suit le trajet : autour de chaque endroit, la fumée naît
//     juste derrière le perso, s'étale et MONTE en vieillissant, puis s'éteint
//     (le début du sillage meurt le premier). Son bord est lui-même déformé
//     par le bruit : jamais une bande régulière.
//   • La MATIÈRE : la fumée déformée découpe l'enveloppe en voiles, avec des
//     creux sombres et des zones denses ; elle tourne et monte lentement.
//   • Les FILAMENTS : des lignes claires et fines (un bruit « en crête » dans le
//     même espace déformé) — les voiles de fumée vus par la tranche.
//   • Les PROFONDEURS : là où la fumée est la plus dense, elle s'assombrit vers
//     le noir-rouge.
//   • EFFILÉE AUX DEUX BOUTS (1er oct. 2026, pour éviter le côté
//     rectangulaire) : à moins
//     d'`effilage` px d'un bout du trajet, l'épaisseur ET la montée
//     rapetissent jusqu'à `bout_min` ; un sillage court devient une lentille.
//     Le bout qui se trace suit le perso en continu (`longueur` compte le bout
//     vivant), sinon il sauterait à chaque point posé.
//   • TOON (`toon`, 1er oct. 2026 : la fumée était trop réaliste) : la même
//     forme, mais la densité en APLATS nets (bord
//     sombre, corps, cœur clair), un fin LISERÉ d'encre autour, des filaments
//     en traits clairs nets, et moins de micro-détails (formes plus
//     graphiques). `toon` = 0 : le rendu fumée d'avant.
//   • FUMÉE DOUCE (`douceur`, 5 oct. 2026) : le rendu marbré, très enroulé et
//     très contrasté avec ses veines claires, se lisait comme un liquide (de
//     l'essence) plus que comme une fumée. À 1, un autre rendu, fait comme un
//     NUAGE : un bruit presque pas déformé DÉPLACE LE BORD de l'enveloppe
//     (bosses sur des bosses, sommet qui s'effiloche) au lieu de la trouer ; le
//     cœur reste plein et tout fond en douceur ; plus de veines, mais un relief
//     doux (les masses éclairées d'en haut à gauche) et une seconde nappe qui
//     laisse voir plus ou moins à travers. À 0 : le rendu marbré, inchangé.
//     Entre les deux, les deux rendus se fondent l'un dans l'autre. Sans effet
//     en toon.

const int MAX_POINTS = 24;

// --- fournis par sillage_sang.gd ---
// taille du rectangle, et position de son coin dans le repère du NŒUD (fixe) :
// tout est calculé dans ce repère fixe. Avant (1er oct. 2026), tout l'était
// dans le repère du rectangle, qui s'agrandit vers la gauche quand on roule
// vers la gauche : son coin bougeait à chaque point ajouté et toute la fumée
// sautait (elle tremblait)
uniform vec2 taille = vec2(400.0, 200.0);
uniform vec2 origine_rect = vec2(0.0, 0.0);
// les points du trajet, dans le repère du nœud
uniform vec2 points[24];
uniform float naissances[24];
uniform int nb_points = 0;
// le temps du sillage (s), et combien de temps vit la brume en chaque endroit
uniform float temps = 0.0;
uniform float duree = 3.0;
uniform float graine = 0.0;
// la longueur du trajet (px), bout vivant compris, et son effilage aux deux
// bouts (réglés sur le nœud SillageSang : le script les donne à chaque image)
uniform float longueur = 0.0;
uniform float effilage = 110.0;
uniform float bout_min = 0.3;
// 0 = le rendu marbré d'avant ; 1 = une fumée douce (réglé sur le nœud)
uniform float douceur = 0.0;
// ------------------------------------

// --- l'allure ---
// demi-hauteur de la fumée à sa naissance (px) ; elle s'étale en vieillissant
uniform float epaisseur : hint_range(10.0, 120.0) = 56.0;
// de combien elle monte sur sa vie (px)
uniform float montee : hint_range(0.0, 200.0) = 120.0;
// taille des volutes (px) : plus grand = de plus larges enroulements
uniform float echelle : hint_range(10.0, 300.0) = 120.0;
// force de la déformation : 0 = un bruit sage, 1 = très enroulé
uniform float tourbillon : hint_range(0.0, 2.0) = 1.0;
// vitesse de la fumée qui tourne et monte
uniform float vitesse : hint_range(0.0, 2.0) = 0.35;
// opacité de la fumée la plus dense, force des filaments clairs, et combien
// les profondeurs s'assombrissent
uniform float opacite : hint_range(0.0, 1.0) = 0.85;
uniform float filaments : hint_range(0.0, 1.0) = 0.9;
uniform float profondeur : hint_range(0.0, 1.0) = 0.45;
// 1 = dessin animé (aplats, liseré d'encre, traits nets) ; 0 = fumée réaliste
uniform float toon : hint_range(0.0, 1.0) = 1.0;
// nombre d'aplats de la fumée toon, et épaisseur du liseré d'encre (0 = aucun)
uniform int nb_aplats : hint_range(2, 5) = 3;
uniform float lisere : hint_range(0.0, 0.2) = 0.07;
// les couleurs : les profondeurs (et l'encre du liseré), la fumée, les filaments
uniform vec4 couleur_sombre : source_color = vec4(0.12, 0.0, 0.02, 1.0);
uniform vec4 couleur_fumee : source_color = vec4(0.78, 0.07, 0.1, 1.0);
uniform vec4 couleur_filament : source_color = vec4(1.0, 0.42, 0.4, 1.0);

// BRUIT À GRADIENTS (le même que la boule de feu : hash sans sin, grille
// tournée)
vec2 gradient(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(vec2(p.x * p.y, p.x + p.y)) * 2.0 - 1.0;
}

float bruit(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = dot(gradient(i), f);
	float b = dot(gradient(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
	float c = dot(gradient(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
	float d = dot(gradient(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 0.75 + 0.5;
}

// 4 octaves : la fumée a besoin de ses détails fins
float fbm(vec2 p) {
	const mat2 ROT = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += bruit(p) * amp;
		p = ROT * p * 2.02 + vec2(17.1, 9.2);
		amp *= 0.5;
	}
	return v / 0.9375;
}

// 3 octaves : la matière du rendu toon, sans ses plus fins détails
float fbm3(vec2 p) {
	const mat2 ROT = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 3; i++) {
		v += bruit(p) * amp;
		p = ROT * p * 2.02 + vec2(17.1, 9.2);
		amp *= 0.5;
	}
	return v / 0.875;
}

// LE BRUIT DE LA FUMÉE DOUCE : le même bruit à gradients, mais dont le hasard
// de chaque nœud de la grille est tiré d'un ENTIER (celui de la foudre et de la
// faille étoilée). Le hasard flottant de `gradient` ne rend pas exactement la
// même valeur pour un même nœud selon la case d'où on le calcule : de petites
// marches au bord des cases, noyées dans le rendu marbré, mais qui taillent une
// fumée lisse en FACETTES dès qu'on en éclaire le relief.
float alea_u(uint n) {
	n = (n << 13u) ^ n;
	n = n * (n * n * 15731u + 789221u) + 1376312589u;
	return float(n & 2147483647u) / 2147483647.0;
}

vec2 gradient_e(vec2 i) {
	uint n = uint(int(i.x) + 65536) * 7919u + uint(int(i.y) + 65536) * 104729u;
	return vec2(alea_u(n), alea_u(n + 40503u)) * 2.0 - 1.0;
}

float bruit_e(vec2 p) {
	vec2 i = floor(p);
	vec2 f = p - i;
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = dot(gradient_e(i), f);
	float b = dot(gradient_e(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
	float c = dot(gradient_e(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
	float d = dot(gradient_e(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 0.75 + 0.5;
}

// LE NUAGE de la fumée douce : ce bruit lu à 3 octaves (x : ses masses, pour
// la lumière) et à 5 (y : avec le duvet de son bord). Chaque octave pèse un peu
// plus de la moitié de la précédente (0,53) : des bosses sur les bosses.
vec2 nuage(vec2 p) {
	const mat2 ROT = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	float v = 0.0;
	float v3 = 0.0;
	float amp = 0.5;
	float somme = 0.0;
	for (int i = 0; i < 5; i++) {
		v += bruit_e(p) * amp;
		somme += amp;
		if (i == 2) {
			v3 = v / somme;
		}
		p = ROT * p * 2.02 + vec2(17.1, 9.2);
		amp *= 0.53;
	}
	return vec2(v3, v / somme);
}

// ses masses seules (3 octaves) : la même valeur que nuage(p).x
float masses(vec2 p) {
	const mat2 ROT = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	float v = 0.0;
	float amp = 0.5;
	float somme = 0.0;
	for (int i = 0; i < 3; i++) {
		v += bruit_e(p) * amp;
		somme += amp;
		p = ROT * p * 2.02 + vec2(17.1, 9.2);
		amp *= 0.53;
	}
	return v / somme;
}

void fragment() {
	if (nb_points <= 0) {
		COLOR = vec4(0.0);
	} else {
		vec2 local = UV * taille;                  // dans le rectangle (pour son bord seulement)
		vec2 pos = local + origine_rect;           // dans le repère fixe du nœud
		// le point du trajet le plus proche, et quand le perso y est passé
		vec2 proche = points[0];
		float dmin = length(pos - points[0]);
		float naissance = naissances[0];
		// (et à combien de px du début du trajet il se trouve : pour l'effilage)
		float cumul = 0.0;
		float s_proche = 0.0;
		for (int i = 0; i < MAX_POINTS - 1; i++) {
			if (i >= nb_points - 1) {
				break;
			}
			vec2 a = points[i];
			vec2 ab = points[i + 1] - a;
			float lab = length(ab);
			float t = clamp(dot(pos - a, ab) / max(dot(ab, ab), 0.0001), 0.0, 1.0);
			vec2 c = a + ab * t;
			float d = length(pos - c);
			if (d < dmin) {
				dmin = d;
				proche = c;
				naissance = mix(naissances[i], naissances[i + 1], t);
				s_proche = cumul + lab * t;
			}
			cumul += lab;
		}
		// L'EFFILAGE : 1 au milieu du trajet, `bout_min` à ses deux bouts
		float l_trajet = max(longueur, cumul);
		float lt = max(min(effilage, l_trajet * 0.5), 1.0);
		float milieu = smoothstep(0.0, lt, min(s_proche, l_trajet - s_proche));
		float effile = mix(bout_min, 1.0, milieu);
		float age = temps - naissance;
		float vie = clamp(age / max(duree, 0.001), 0.0, 1.0);
		// (la fumée douce : seulement hors toon ; ses mèches montent un peu plus haut)
		float doux = douceur * (1.0 - toon);
		float rayon_max = epaisseur * 1.4 + montee * 1.4 + 20.0 + 40.0 * doux;
		if (age < 0.0 || vie >= 1.0 || dmin > rayon_max) {
			COLOR = vec4(0.0);
		} else {
			float tt = temps * vitesse;

			// --- L'ENVELOPPE, ANCRÉE COMME UNE FLAMME (stable sur sa base même
			// si elle monte, au lieu de s'envoler) : sa BASE reste
			// posée sur le trajet ; seul son HAUT grandit avec l'âge, d'une
			// hauteur qui varie le long du trajet (des colonnes, pas une barre),
			// et c'est la matière qui monte à travers elle. Chacun des deux rendus
			// la mesure à sa façon, plus bas ---
			// elle s'ouvre en naissant
			float ouverture = smoothstep(0.0, 0.2, age);
			// elle s'éteint à la fin de sa vie
			// (elle reste bien visible tant qu'elle mord : jusqu'à 80 % de sa vie ;
			// avant le 1er oct. elle s'effaçait dès 70 % et mordait encore invisible)
			float fin = 1.0 - smoothstep(0.82, 1.0, vie);

			// ===== LE RENDU MARBRÉ (et la matière du toon) =====
			vec3 rgb_m = vec3(0.0);
			float a_m = 0.0;
			float densite_marbre = 0.0;
			float crete = 0.0;
			if (doux < 0.999) {
				// LA MATIÈRE : trois bruits empilés, chacun déforme le suivant ; leur
				// espace est étiré en hauteur (la fumée monte en volutes hautes) et
				// défile vers le haut
				vec2 q = vec2(pos.x, pos.y * 0.75) / echelle + vec2(graine * 3.1, graine * 1.7) + vec2(0.0, tt * 0.8);
				vec2 w1 = vec2(fbm(q + vec2(0.0, tt * 0.5)), fbm(q + vec2(5.2, 1.3) - vec2(tt * 0.3, 0.0)));
				vec2 w2 = vec2(fbm(q + 3.2 * tourbillon * w1 + vec2(1.7, 9.2) + vec2(tt * 0.2, 0.0)),
						fbm(q + 3.2 * tourbillon * w1 + vec2(8.3, 2.8)));
				vec2 r = q + 3.6 * tourbillon * w2;
				// (en toon, sans sa dernière octave : des formes plus graphiques)
				float fumee = mix(fbm(r), fbm3(r), toon);
				// les filaments : un bruit « en crête » dans le même espace enroulé
				crete = 1.0 - abs(2.0 * fbm(r * 1.7 + vec2(3.3, 7.1)) - 1.0);
				float filament = pow(crete, 5.0);
				// l'enveloppe : son rayon, qui varie le long du trajet, sa hauteur, et
				// celle du pixel au-dessus du trajet (0 à la base, 1 au sommet)
				float renfle = 0.7 + 0.6 * bruit(vec2(proche.x / 90.0 + graine, graine * 0.37));
				float R = epaisseur * renfle * mix(0.5, 1.0, ouverture) * effile;
				float h_bas = R * 0.55;
				float colonne = mix(0.45, 1.35, bruit(vec2(proche.x / 55.0 + graine * 2.0, temps * 0.25)));
				float h_haut = R + montee * (1.0 - (1.0 - vie) * (1.0 - vie)) * colonne * effile;
				float hauteur = clamp((proche.y - pos.y) / max(h_haut, 1.0), 0.0, 1.0);
				// l'enveloppe est mesurée dans l'espace tordu par les bruits : la
				// torsion est faible à la base (stable) et forte au sommet (volutes
				// et rubans)
				vec2 tordu = pos + (w2 - 0.5) * R * mix(0.5, 3.2, hauteur) * tourbillon
						- vec2(0.0, (w1.y - 0.3) * R * 0.9 * hauteur);
				vec2 rel = tordu - proche;
				rel.y *= (rel.y < 0.0) ? R / h_haut : R / h_bas;
				float env = 1.0 - smoothstep(R * 0.15, R * 1.05, length(rel));
				// la densité : l'enveloppe découpée en voiles par la fumée ; elle se
				// déchire en vieillissant (le seuil monte) — le haut le premier, la
				// base tient jusqu'au bout
				float seuil = mix(0.28, 0.58, smoothstep(0.5, 1.0, vie)) + 0.18 * hauteur * smoothstep(0.3, 1.0, vie);
				float voile = smoothstep(seuil, seuil + 0.45, fumee);
				densite_marbre = pow(env * voile, 1.2) * fin;
				// les couleurs : fumée, profondeurs sombres, filaments clairs
				rgb_m = couleur_fumee.rgb * mix(0.75, 1.15, fumee);
				rgb_m = mix(rgb_m, couleur_sombre.rgb, profondeur * smoothstep(0.55, 1.0, densite_marbre * voile));
				float lumiere = filament * filaments * env * (1.0 - vie * 0.7);
				rgb_m = mix(rgb_m, couleur_filament.rgb, clamp(lumiere * 1.4, 0.0, 1.0));
				a_m = clamp(densite_marbre * 1.15 + lumiere * 0.5 * (1.0 - smoothstep(0.75, 1.0, vie)), 0.0, 1.0);
			}

			// ===== LA FUMÉE DOUCE =====
			vec3 rgb_d = vec3(0.0);
			float a_d = 0.0;
			float densite_douce = 0.0;
			if (doux > 0.001) {
				// l'espace de ses bruits défile vers le haut lui aussi, mais il n'est
				// PAS étiré en hauteur : des bosses rondes, pas des mèches verticales
				vec2 qd = pos / echelle + vec2(graine * 3.1, graine * 1.7) + vec2(0.0, tt);
				// un BALANCEMENT lisse (une seule octave de bruit) : il fait pencher un
				// peu les colonnes avec la hauteur et onduler leur sommet. Rien ne
				// déplace l'enveloppe de côté : dans le rendu marbré c'est ce
				// déplacement, par des bruits fins, qui plie le bord en arêtes et en
				// langues nettes
				vec2 balance = vec2(bruit_e(qd * 0.9 + vec2(3.1, -tt * 0.3)), bruit_e(qd * 0.9 + vec2(11.7, 5.3 - tt * 0.3))) - 0.5;
				vec2 ecart = pos - proche;
				float haut_px = max(-ecart.y, 0.0);
				// l'enveloppe : son rayon, qui varie le long du trajet, et sa hauteur.
				// Un peu plus grande que celle du rendu marbré, vers le bas (elle se
				// pose) comme vers le haut : son bord fond sur une large distance, et
				// c'est là où elle se voit encore qu'elle doit couvrir la zone de dégâts
				// (sillage_sang.gd, `dans_la_brume`)
				float renfle = 0.7 + 0.6 * bruit_e(vec2(proche.x / 90.0 + graine, graine * 0.37));
				float R = epaisseur * renfle * mix(0.5, 1.0, ouverture) * effile;
				float h_bas = R * 0.8;
				float x_col = proche.x + balance.x * haut_px * 0.3 * tourbillon;
				float colonne = mix(0.65, 1.25, bruit_e(vec2(x_col / 100.0 + graine * 2.0, temps * 0.25)));
				float h_haut = (R + montee * (1.0 - (1.0 - vie) * (1.0 - vie)) * colonne * effile) * 1.08;
				float hauteur = clamp(haut_px / max(h_haut, 1.0), 0.0, 1.0);
				// son PROFIL : plein sur le trajet, il s'arrondit jusqu'au bord (une
				// parabole : pas de pli le long du trajet)
				vec2 e = vec2(ecart.x / max(R, 1.0), (ecart.y < 0.0) ? haut_px / max(h_haut, 1.0) : ecart.y / max(h_bas, 1.0));
				e.y += balance.y * 0.5 * hauteur * tourbillon;
				float profil = 1.0 - dot(e, e);
				// LE NUAGE : un bruit à peine déformé, qui ne troue pas l'enveloppe mais
				// en DÉPLACE LE BORD — le cœur reste plein, le bord part en bosses sur
				// des bosses et fond sur une large distance. Aux deux bouts effilés la
				// fumée est mince et ses bosses un peu moins fortes : une trop grosse
				// bouffée ne s'y détache pas. En vieillissant le bord est de plus en
				// plus rongé, le haut le premier : elle se disperse
				vec2 pm = (qd + balance * 0.12 * tourbillon) * 1.5;
				vec2 n = nuage(pm);
				float r_plein = max(epaisseur * mix(0.5, 1.0, ouverture), 1.0);
				float champ = profil * R / r_plein + (n.y - 0.5) * mix(1.6, 2.4, smoothstep(0.2, 1.0, vie)) * (0.7 + hauteur) * mix(0.75, 1.0, milieu);
				float ronge = 0.5 * smoothstep(0.5, 1.0, vie) + 0.1 * hauteur * smoothstep(0.3, 1.0, vie);
				// (sa base fond plus largement que son sommet)
				float fondu = 0.5 * mix(1.0, 1.8, smoothstep(0.0, 1.0, ecart.y / max(h_bas, 1.0)));
				float corps = smoothstep(ronge, ronge + fondu, champ);
				// une seconde nappe, plus large, qui monte moins vite : on voit plus
				// ou moins à travers la fumée
				float nappe = masses(pm * 0.6 + vec2(7.3, 2.1 - tt * 0.35));
				densite_douce = corps * mix(1.0, smoothstep(0.3, 0.7, nappe), 0.45) * fin;
				// son RELIEF : ses masses lues un peu plus haut à gauche, d'où vient
				// la lumière — là où il y a moins de fumée de ce côté, la masse est
				// éclairée ; à l'opposé, elle est dans l'ombre
				float relief = n.x - masses(pm + vec2(-0.13, -0.22));
				float lum = clamp(0.58 + relief * 1.3 + (hauteur - 0.4) * 0.35 * milieu + (1.0 - corps) * 0.15, 0.0, 1.0);
				// les couleurs : plus de veines claires. Un dégradé doux, des
				// profondeurs à la fumée puis à la couleur des filaments, selon la
				// lumière reçue
				vec3 c_ombre = mix(couleur_fumee.rgb, couleur_sombre.rgb, min(profondeur * 1.3, 1.0));
				vec3 c_clair = mix(couleur_fumee.rgb, couleur_filament.rgb, filaments * 0.8);
				rgb_d = mix(c_ombre, couleur_fumee.rgb, smoothstep(0.0, 0.5, lum));
				rgb_d = mix(rgb_d, c_clair, smoothstep(0.5, 1.0, lum));
				// elle s'épaissit en douceur (plus on en traverse, moins on voit à travers)
				a_d = 1.0 - exp(-densite_douce * 1.7);
			}

			float densite = mix(densite_marbre, densite_douce, doux);
			vec3 rgb_r = mix(rgb_m, rgb_d, doux);
			float a_r = mix(a_m, a_d, doux) * opacite;

			// --- LES COULEURS, TOON : la densité en aplats nets (bord sombre,
			// corps, cœur clair), un liseré d'encre juste à l'extérieur du premier
			// aplat, les filaments en traits clairs nets, seulement dans le corps ---
			float dens = clamp(densite * 1.25, 0.0, 1.0);
			float w = max(fwidth(dens), 0.002);
			float n_ap = float(nb_aplats);
			float palier = 0.0;                          // 0 = dehors … 1 = cœur
			for (int k = 1; k <= 5; k++) {
				if (k > nb_aplats) {
					break;
				}
				float b = (float(k) - 0.75) / n_ap;
				palier += smoothstep(b - w, b + w, dens);
			}
			palier /= n_ap;
			float b1 = 0.25 / n_ap;                      // le bord du premier aplat
			float encre = smoothstep(b1 - lisere - w, b1 - lisere + w, dens) * (1.0 - smoothstep(b1 - w, b1 + w, dens));
			vec3 clair = mix(couleur_fumee.rgb, couleur_filament.rgb, 0.45);
			vec3 rgb_t = mix(couleur_sombre.rgb * 2.2, couleur_fumee.rgb, smoothstep(0.2, 0.55, palier));
			rgb_t = mix(rgb_t, clair, smoothstep(0.7, 0.9, palier));
			float trait = smoothstep(0.8 - 0.02, 0.8 + 0.02, crete) * step(0.4, palier) * filaments * (1.0 - vie * 0.6);
			rgb_t = mix(rgb_t, couleur_filament.rgb, trait);
			rgb_t = mix(rgb_t, couleur_sombre.rgb, encre);
			float a_t = max(mix(0.0, 0.92, smoothstep(0.0, 0.34, palier)) * mix(0.62, 1.0, palier), encre * 0.85) * opacite;

			vec3 rgb = mix(rgb_r, rgb_t, toon);
			float a = mix(a_r, a_t, toon);
			// jamais coupée net par le bord du rectangle
			float bord_rect = smoothstep(0.0, 12.0, min(min(local.x, taille.x - local.x), min(local.y, taille.y - local.y)));
			COLOR = vec4(rgb, a * bord_rect);
		}
	}
}
