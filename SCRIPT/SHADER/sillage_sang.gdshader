shader_type canvas_item;
render_mode unshaded;
// SILLAGE DE SANG — la brume laissée par la roulade et le dash (talisman
// « Sillage de sang », 1er oct. 2026). sillage_sang.gd lui passe les points du
// trajet (dans le repère du rectangle) avec l'heure où le perso y est passé.
//
// 4e version (retour de Kaoru, image de référence à l'appui : « très
// déstructuré, grâce à des bruits empilés ; là on est sur des bulles de savon
// de sang ») : une FUMÉE, pas des bouffées. Le principe est le « domain
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
//   • TOON (`toon`, 1er oct. 2026 : « un peu trop réaliste, faudrait la rendre
//     plus toon ») : la même forme, mais la densité en APLATS nets (bord
//     sombre, corps, cœur clair), un fin LISERÉ d'encre autour, des filaments
//     en traits clairs nets, et moins de micro-détails (formes plus
//     graphiques). `toon` = 0 : le rendu fumée d'avant.

const int MAX_POINTS = 24;

// --- fournis par sillage_sang.gd ---
// taille du rectangle, et position de son coin dans le repère du NŒUD (fixe) :
// tout est calculé dans ce repère fixe. Avant (1er oct. 2026), tout l'était
// dans le repère du rectangle, qui s'agrandit vers la gauche quand on roule
// vers la gauche : son coin bougeait à chaque point ajouté et toute la fumée
// sautait (« elle tremble »)
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
		for (int i = 0; i < MAX_POINTS - 1; i++) {
			if (i >= nb_points - 1) {
				break;
			}
			vec2 a = points[i];
			vec2 ab = points[i + 1] - a;
			float t = clamp(dot(pos - a, ab) / max(dot(ab, ab), 0.0001), 0.0, 1.0);
			vec2 c = a + ab * t;
			float d = length(pos - c);
			if (d < dmin) {
				dmin = d;
				proche = c;
				naissance = mix(naissances[i], naissances[i + 1], t);
			}
		}
		float age = temps - naissance;
		float vie = clamp(age / max(duree, 0.001), 0.0, 1.0);
		float rayon_max = epaisseur * 1.4 + montee * 1.4 + 20.0;
		if (age < 0.0 || vie >= 1.0 || dmin > rayon_max) {
			COLOR = vec4(0.0);
		} else {
			// --- LA MATIÈRE : trois bruits empilés, chacun déforme le suivant ;
			// l'espace est étiré en hauteur (la fumée monte en volutes hautes)
			// et défile vers le haut ---
			float tt = temps * vitesse;
			vec2 q = vec2(pos.x, pos.y * 0.75) / echelle + vec2(graine * 3.1, graine * 1.7) + vec2(0.0, tt * 0.8);
			vec2 w1 = vec2(fbm(q + vec2(0.0, tt * 0.5)), fbm(q + vec2(5.2, 1.3) - vec2(tt * 0.3, 0.0)));
			vec2 w2 = vec2(fbm(q + 3.2 * tourbillon * w1 + vec2(1.7, 9.2) + vec2(tt * 0.2, 0.0)),
					fbm(q + 3.2 * tourbillon * w1 + vec2(8.3, 2.8)));
			vec2 r = q + 3.6 * tourbillon * w2;
			// (en toon, sans sa dernière octave : des formes plus graphiques)
			float fumee = mix(fbm(r), fbm3(r), toon);
			// les filaments : un bruit « en crête » dans le même espace enroulé
			float crete = 1.0 - abs(2.0 * fbm(r * 1.7 + vec2(3.3, 7.1)) - 1.0);
			float filament = pow(crete, 5.0);

			// --- L'ENVELOPPE, ANCRÉE COMME UNE FLAMME (Kaoru : « elle devrait
			// être bien ancrée là où elle est plutôt que s'envoler ; une flamme
			// reste stable sur sa base même si elle monte ») : sa BASE reste
			// posée sur le trajet ; seul son HAUT grandit avec l'âge, d'une
			// hauteur qui varie le long du trajet (des colonnes, pas une barre),
			// et c'est la matière qui monte à travers elle. La torsion par les
			// bruits est faible à la base (stable) et forte au sommet (volutes
			// et rubans) ---
			float ouverture = smoothstep(0.0, 0.2, age);
			float renfle = 0.7 + 0.6 * bruit(vec2(proche.x / 90.0 + graine, graine * 0.37));
			float R = epaisseur * renfle * mix(0.5, 1.0, ouverture);
			float colonne = mix(0.45, 1.35, bruit(vec2(proche.x / 55.0 + graine * 2.0, temps * 0.25)));
			float h_haut = R + montee * (1.0 - (1.0 - vie) * (1.0 - vie)) * colonne;
			float h_bas = R * 0.55;
			// hauteur du pixel au-dessus du trajet : 0 à la base, 1 au sommet
			float hauteur = clamp((proche.y - pos.y) / max(h_haut, 1.0), 0.0, 1.0);
			vec2 tordu = pos + (w2 - 0.5) * R * mix(0.5, 3.2, hauteur) * tourbillon
					- vec2(0.0, (w1.y - 0.3) * R * 0.9 * hauteur);
			vec2 rel = tordu - proche;
			rel.y *= (rel.y < 0.0) ? R / h_haut : R / h_bas;
			float d_env = length(rel);
			float env = 1.0 - smoothstep(R * 0.15, R * 1.05, d_env);

			// --- LA DENSITÉ : l'enveloppe découpée en voiles par la fumée ; elle
			// se déchire en vieillissant (le seuil monte), puis s'éteint ---
			// (le haut se déchire et s'éteint le premier ; la base tient jusqu'au bout)
			// (elle reste bien visible tant qu'elle mord : jusqu'à 80 % de sa vie ;
			// avant le 1er oct. elle s'effaçait dès 70 % et mordait encore invisible)
			float seuil = mix(0.28, 0.58, smoothstep(0.5, 1.0, vie)) + 0.18 * hauteur * smoothstep(0.3, 1.0, vie);
			float voile = smoothstep(seuil, seuil + 0.45, fumee);
			float densite = pow(env * voile, 1.2) * (1.0 - smoothstep(0.82, 1.0, vie));

			// --- LES COULEURS, RÉALISTES : fumée, profondeurs sombres, filaments clairs ---
			vec3 rgb_r = couleur_fumee.rgb * mix(0.75, 1.15, fumee);
			rgb_r = mix(rgb_r, couleur_sombre.rgb, profondeur * smoothstep(0.55, 1.0, densite * voile));
			float lumiere = filament * filaments * env * (1.0 - vie * 0.7);
			rgb_r = mix(rgb_r, couleur_filament.rgb, clamp(lumiere * 1.4, 0.0, 1.0));
			float a_r = clamp(densite * 1.15 + lumiere * 0.5 * (1.0 - smoothstep(0.75, 1.0, vie)), 0.0, 1.0) * opacite;

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
				float b = (float(k) - 0.55) / n_ap;
				palier += smoothstep(b - w, b + w, dens);
			}
			palier /= n_ap;
			float b1 = 0.45 / n_ap;                      // le bord du premier aplat
			float encre = smoothstep(b1 - lisere - w, b1 - lisere + w, dens) * (1.0 - smoothstep(b1 - w, b1 + w, dens));
			vec3 clair = mix(couleur_fumee.rgb, couleur_filament.rgb, 0.45);
			vec3 rgb_t = mix(couleur_sombre.rgb * 2.2, couleur_fumee.rgb, smoothstep(0.2, 0.55, palier));
			rgb_t = mix(rgb_t, clair, smoothstep(0.75, 0.95, palier));
			float trait = smoothstep(0.84 - 0.02, 0.84 + 0.02, crete) * step(0.5, palier) * filaments * (1.0 - vie * 0.6);
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
