shader_type canvas_item;
render_mode unshaded;
// CÂBLE DE SANG — le câble du grappin. Même famille que jet_flamme et
// boule_de_feu : bruit à gradients (hash sans sin), aplats cartoon, palette de
// quatre couleurs.
//
// POSÉ SUR LA Line2D de accroche_grappin.tscn, qui n'est qu'un RUBAN de support :
// UV.x court de la MAIN (0) jusqu'à l'accroche (1), UV.y traverse le ruban. Le
// ruban est volontairement bien plus large que le câble visible — toute cette
// marge sert aux grumeaux, aux gouttes et à la lueur.
//
// TROIS UNIFORMES SONT RENSEIGNÉS PAR LE SCRIPT à chaque image (`longueur`,
// `largeur`, `bas_local`). Sans eux tout serait étiré par la longueur du câble,
// qui change à chaque frame pendant le lancer, et les gouttes tomberaient de
// travers dès que le câble n'est pas vertical.
//
// PRINCIPE : le câble n'a AUCUNE silhouette. Ce n'est pas un tuyau dont le bord
// s'effiloche, c'est une traînée de BRUME : une décroissance douce depuis l'axe,
// multipliée par une matière bruitée qui dérive. Ce qui est dense se voit, le
// reste s'évapore — et comme la matière bouge, tout se dissout en permanence,
// y compris au milieu. Un bord franc ne peut pas réapparaître : il n'existe pas.
//
// Son axe serpente quand même (mais revient exactement sur ses deux ancrages)
// et des caillots plus denses remontent vers la main : c'est ce qui empêche la
// brume de n'être qu'un flou et lui donne un sens de circulation.
//
// Le trait d'encre et les gouttes existent toujours dans le code, mais sont
// ÉTEINTS par défaut (`contour` et `gouttes` à 0) : ils racontent un liquide
// solide, l'inverse d'une brume.

// --- renseignés par accroche_grappin.gd ---
uniform float longueur = 300.0;    // longueur du câble, en pixels
uniform float largeur = 44.0;      // largeur du ruban (width de la Line2D), en pixels
uniform vec2 bas_local = vec2(0.0, 1.0);   // "vers le bas" du monde, dans le repère du ruban

// --- réglages ---
// épaisseur du câble au repos, en pixels
uniform float epaisseur : hint_range(1.0, 40.0) = 13.0;
// grumeaux : 0 = tuyau régulier, 1 = boyau noueux
uniform float renflement : hint_range(0.0, 1.0) = 0.45;
// ondulation de l'axe, en pixels (0 = câble tendu au cordeau)
uniform float serpentement : hint_range(0.0, 10.0) = 2.5;
// caillots qui remontent vers la main, par seconde (négatif = ils descendent)
uniform float vitesse_pulse : hint_range(-6.0, 6.0) = 2.2;
// distance entre deux caillots, en pixels
uniform float pas_pulse : hint_range(20.0, 400.0) = 90.0;
// suintement : 0 = aucune goutte (défaut : une goutte, c'est du liquide qui
// tient, ça contredit la brume). Laissé pour une variante future
uniform float gouttes : hint_range(0.0, 1.0) = 0.0;
// halo autour du câble
uniform float lueur : hint_range(0.0, 1.0) = 0.5;

// --- BRUME ---
// part de la matière laissée au bruit. 0 = traînée pleine et régulière,
// 1 = le bruit décide de tout, y compris au centre
uniform float dissolution : hint_range(0.0, 1.0) = 0.80;
// étalement de la brume autour de l'axe (1 = la largeur d'`epaisseur`)
uniform float etalement : hint_range(0.5, 3.0) = 1.35;
// douceur du fondu : petit = volutes encore marquées, grand = vapeur
uniform float douceur : hint_range(0.05, 1.2) = 0.45;
// opacité d'ensemble
uniform float densite : hint_range(0.2, 2.0) = 1.0;
// seuil d'existence : ce qui est en dessous n'est PAS dessiné. C'est lui qui
// creuse les trous et détache les volutes. Trop bas, la brume redevient un
// tuyau plein ; trop haut, le câble se coupe en morceaux
uniform float seuil : hint_range(0.0, 0.7) = 0.30;
// taille des volutes (petit = grosses masses, grand = fine poussière)
uniform float brume_grain : hint_range(0.01, 0.40) = 0.09;
// vitesse à laquelle la brume file le long du câble
uniform float brume_vitesse : hint_range(0.0, 10.0) = 2.5;
// grosse tête à la pointe : le crochet qui mord l'accroche
uniform float pointe : hint_range(0.0, 1.5) = 0.7;
// décale le bruit : une valeur par accroche, sinon deux câbles sont identiques
uniform float graine = 0.0;
// 1 = aplats dessin animé, 0 = dégradé doux
uniform float style_cartoon : hint_range(0.0, 1.0) = 1.0;
uniform int nb_bandes : hint_range(2, 8) = 4;

// épaisseur du trait d'encre au bord, en PIXELS (0 = pas de contour). Le jeu
// est dessiné au trait : sans lui le câble ne ressemble à rien de la scène
uniform float contour : hint_range(0.0, 5.0) = 0.0;
uniform vec4 contour_color : source_color = vec4(0.07, 0.0, 0.02, 1.0);
uniform vec4 outer_color : source_color = vec4(0.33, 0.0, 0.05, 1.0);
uniform vec4 middle_color : source_color = vec4(0.62, 0.04, 0.08, 1.0);
uniform vec4 inner_color : source_color = vec4(0.86, 0.08, 0.09, 1.0);
uniform vec4 core_color : source_color = vec4(1.00, 0.66, 0.56, 1.0);


// BRUIT À GRADIENTS, hash SANS sin (le hash sin perd sa précision GPU quand le
// temps défile) — identique à jet_flamme / boule_de_feu.
vec2 gradient(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(vec2(p.x * p.y, p.x + p.y)) * 2.0 - 1.0;
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = dot(gradient(i), f);
	float b = dot(gradient(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
	float c = dot(gradient(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
	float d = dot(gradient(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 0.75 + 0.5;
}

// 2 octaves suffisent : le câble est fin à l'écran
float fbm(vec2 p) {
	const mat2 ROT = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	p = ROT * p;
	return noise(p) * 0.65 + noise(ROT * p * 2.03 + vec2(17.1, 9.2)) * 0.35;
}

// hash 1D sans sin (Hoskins) : une valeur stable par goutte
float hash11(float n) {
	n = fract(n * 0.1031);
	n *= n + 33.33;
	n *= n + n;
	return fract(n);
}

float segment(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.0001), 0.0, 1.0);
	return length(pa - ba * h);
}


// Gouttes : une cellule tous les PAS pixels le long du câble. Chacune perle sur
// le flanc BAS (au sens du monde, d'où `bas_local`), s'étire en goutte reliée au
// câble, se détache, puis s'efface avant de sortir du ruban.
// Renvoie (distance signée en pixels, rayon de la goutte la plus proche) : le
// rayon sert d'ÉCHELLE LOCALE au reste du shader. Sans lui, une goutte de 3 px
// est peinte avec les seuils du câble, qui en fait 10 : elle sortait presque
// entièrement en couleur de bord, donc noire.
vec2 champ_gouttes(vec2 p, float axe, float demi, float t) {
	const float PAS = 34.0;
	float meilleur = 1e9;
	float rayon_proche = 1.0;
	float cellule = floor(p.x / PAS);
	for (int k = -1; k <= 1; k++) {
		float idx = cellule + float(k);
		float alea = hash11(idx * 1.7 + graine * 3.1);
		if (alea > 0.25 + 0.75 * gouttes) {
			continue;   // cette cellule reste sèche
		}
		float xc = (idx + 0.35 + 0.3 * hash11(idx * 5.3 + 11.0)) * PAS;
		float phase = fract(t * (0.45 + 0.35 * alea) + alea * 7.0);
		float enfle = sin(phase * PI);              // naît, gonfle, s'efface
		float chute = phase * phase * 11.0;         // accélère en tombant
		// La goutte perle sur le FLANC du câble, puis tombe vers le bas du MONDE.
		// Accrochée à l'axe, elle resterait noyée dans le câble dès qu'il est
		// vertical (le "bas" est alors dans l'axe) : on ne voyait rien.
		float flanc = bas_local.y >= 0.0 ? 1.0 : -1.0;
		if (abs(bas_local.y) < 0.30) {
			// câble presque vertical : le bas ne désigne plus de flanc,
			// on répartit les gouttes des deux côtés
			flanc = hash11(idx * 3.7 + graine * 2.3) < 0.5 ? -1.0 : 1.0;
		}
		vec2 a = vec2(xc, axe + flanc * demi * 0.75);
		vec2 b = a + bas_local * chute;
		// UNE TÊTE RONDE ET UN COL QUI S'ÉTIRE. Une simple capsule entre les deux
		// points donnait un bâtonnet d'épaisseur constante : ça ressemblait à des
		// antennes, pas à du sang qui perle.
		float taille = (0.75 + 0.55 * hash11(idx * 9.1 + 3.0)) * (1.1 + 3.0 * gouttes);
		float rayon = taille * pow(enfle, 0.45);
		float tete = length(p - b) - rayon;
		// le col s'amincit à mesure que la goutte descend, puis se rompt
		float col = rayon * 0.42 * (1.0 - clamp(chute / 8.0, 0.0, 1.0));
		float cou = segment(p, a, b) - col;
		float dg = min(tete, cou);
		if (dg < meilleur) {
			meilleur = dg;
			rayon_proche = max(rayon, 1.0);
		}
	}
	return vec2(meilleur, rayon_proche);
}


void fragment() {
	float le_long = UV.x * longueur;
	float travers = (UV.y - 0.5) * largeur;
	vec2 p = vec2(le_long, travers);
	float t = TIME;

	// L'axe serpente, mais la fenêtre en sinus le ramène EXACTEMENT sur ses deux
	// points : sinon le câble décolle de la main et rate l'anneau.
	float fenetre = sin(UV.x * PI);
	float axe = serpentement * (fbm(vec2(le_long * 0.010, t * 0.5 + graine)) - 0.5) * 2.0 * fenetre;

	// caillots qui remontent le câble
	float pulse = 0.5 + 0.5 * sin((le_long / pas_pulse + t * vitesse_pulse) * TAU);

	// demi-épaisseur : repos + grumeaux + gonflement des caillots
	float grain = fbm(vec2(le_long * 0.030 - t * 0.9, graine * 2.0 + 4.0));
	float demi = epaisseur * 0.5;
	demi *= 1.0 + renflement * ((grain - 0.5) * 1.5 + 0.5 * pulse);
	demi *= 1.0 + pointe * smoothstep(0.84, 1.0, UV.x);
	demi = max(demi, 0.6);

	// ===================== LA BRUME =====================
	// distance à l'axe, en "épaisseurs" : aucune frontière, juste un éloignement
	float r = abs(travers - axe) / (max(demi, 0.6) * etalement);
	// noyau : décroissance douce, jamais de bord
	float noyau = exp(-r * r * 0.9);

	// LA MATIÈRE EST LE BRUIT, et elle dérive le long du câble. Deux échelles :
	// les grosses volutes portent la forme, les fines la déchirent.
	float m1 = fbm(vec2(le_long * brume_grain - t * brume_vitesse,
		travers * brume_grain * 1.4 + t * 0.8 + graine * 3.0));
	float m2 = fbm(vec2(le_long * brume_grain * 2.6 - t * brume_vitesse * 1.7,
		travers * brume_grain * 3.0 + t * 1.4 + graine));
	float matiere = m1 * 0.65 + m2 * 0.35;

	// Densité : le noyau donne l'allure générale, la matière la ronge PARTOUT.
	// Le bruit doit faire passer la masse AU-DESSUS ET EN DESSOUS du seuil,
	// sinon l'alpha sature et on retrouve un tuyau plein à bord franc.
	float force = noyau * (1.0 - dissolution * 0.5 + dissolution * (matiere - 0.5) * 2.2);
	float masse = force - seuil;

	// les gouttes et l'encre ne servent qu'à la variante "liquide" (éteintes)
	float d = abs(travers - axe) - demi;
	float echelle = demi;
	if (gouttes > 0.001) {
		vec2 dg = champ_gouttes(p, axe, demi, t);
		if (dg.x < d) {
			d = dg.x;
			echelle = dg.y;
		}
		masse = max(masse, (-dg.x / max(dg.y, 1.0)) * 0.9);
	}
	echelle = max(echelle, 1.0);

	float alpha = clamp(masse / douceur, 0.0, 1.0) * densite;
	alpha = clamp(alpha, 0.0, 1.0);

	// CHALEUR : c'est la densité qui décide de la couleur, plus aucune distance.
	// Les caillots l'éclaircissent au passage : l'éclat REMONTE le câble.
	float chaleur = clamp(masse * 1.9, 0.0, 1.0) * (0.66 + 0.50 * pulse * (0.55 + 0.45 * grain));
	chaleur = clamp(chaleur, 0.0, 1.0);
	if (style_cartoon > 0.5) {
		float n = float(nb_bandes);
		chaleur = floor(chaleur * n) / max(n - 1.0, 1.0);
		chaleur = clamp(chaleur, 0.0, 1.0);
	}

	vec3 col = mix(outer_color.rgb, middle_color.rgb, smoothstep(0.0, 0.45, chaleur));
	col = mix(col, inner_color.rgb, smoothstep(0.42, 0.75, chaleur));
	// le cœur clair reste RARE : dans une brume, un gros aplat crème fait de la
	// chair, pas de la vapeur
	col = mix(col, core_color.rgb, smoothstep(0.93, 1.0, chaleur));

	// trait d'encre : éteint par défaut, il raconte un corps solide
	if (contour > 0.01) {
		float trait = min(contour, echelle * 0.5);
		col = mix(col, contour_color.rgb, smoothstep(-trait, -trait * 0.25, d)
			* (1.0 - smoothstep(0.0, 4.0, d)));
	}

	// halo : un reste de lueur sous la brume
	alpha = clamp(alpha + lueur * 0.30 * noyau * noyau, 0.0, 1.0);

	COLOR = vec4(col, alpha);
}
