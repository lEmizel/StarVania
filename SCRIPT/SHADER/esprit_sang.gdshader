shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;
// ESPRIT DE SANG (1er oct. 2026) — les âmes perdues à la mort, laissées sur place
// comme dans les Souls (Kaoru : « un petit esprit rouge, wisp of blood, qu'on
// doit ramasser pour les récupérer »).
// Un FEU FOLLET de sang qui flotte : un corps de FLAMME — rond et chaud en bas,
// effilé en haut, sa pointe qui ondule et vacille —, deux petites LANGUES de feu
// qui s'en détachent et montent en s'éteignant, une vapeur qui s'en défait (des
// bruits empilés et tordus, comme l'œil du Canon de verre), quelques
// gouttelettes qui montent autour, et une LUEUR qui le signale de loin (ajoutée
// à ce qu'il y a derrière : mode prémultiplié). Il respire. (Une 1re version,
// un cœur rond et de petites flammes, se lisait comme une boule rouge.)
// Quand on le touche (`absorbe` 0 → 1), il s'embrase, se resserre et file vers
// le héros (le script le déplace).
// Repère : des pixels, l'origine au milieu du cœur.

// --- fournis par esprit_sang.gd ---------------------------------------------
uniform vec2 taille = vec2(110.0, 150.0);
// le milieu du cœur, depuis le haut-gauche du rectangle (px)
uniform vec2 ancre = vec2(55.0, 92.0);
uniform float temps = 0.0;
// 0 : il attend ; 1 : repris (il s'est fondu dans le héros)
uniform float absorbe : hint_range(0.0, 1.0) = 0.0;
// sa direction de vol quand il file vers le héros (sa traîne la suit)
uniform vec2 vol = vec2(0.0, 0.0);
uniform float apparition : hint_range(0.0, 1.0) = 1.0;
// ----------------------------------------------------------------------------

uniform float rayon_coeur = 10.0;
uniform float hauteur_flammes = 44.0;
uniform float halo : hint_range(0.0, 1.0) = 0.45;
uniform vec4 couleur_coeur : source_color = vec4(1.0, 0.36, 0.3, 1.0);
uniform vec4 couleur : source_color = vec4(0.86, 0.06, 0.1, 1.0);
uniform vec4 couleur_vapeur : source_color = vec4(0.5, 0.02, 0.06, 1.0);
uniform vec4 couleur_lueur : source_color = vec4(0.9, 0.08, 0.1, 1.0);

float hachis(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float bruit(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	return mix(mix(hachis(i), hachis(i + vec2(1.0, 0.0)), u.x),
			mix(hachis(i + vec2(0.0, 1.0)), hachis(i + vec2(1.0, 1.0)), u.x), u.y);
}

// trois bruits empilés, chacun tourné (pas de carreaux)
float bruits(vec2 p) {
	float s = bruit(p) * 0.55;
	p = vec2(0.8 * p.x - 0.6 * p.y, 0.6 * p.x + 0.8 * p.y) * 2.03 + vec2(17.0, 5.0);
	s += bruit(p) * 0.3;
	p = vec2(0.8 * p.x - 0.6 * p.y, 0.6 * p.x + 0.8 * p.y) * 2.02 + vec2(3.0, 29.0);
	s += bruit(p) * 0.15;
	return s;
}

// une larme : tête ronde de rayon r1 en `a`, pointe de rayon r2 en `b` (px,
// négative dedans)
float larme(vec2 p, vec2 a, vec2 b, float r1, float r2) {
	vec2 ab = b - a;
	float h = max(length(ab), (r1 - r2) * 1.01 + 0.01);
	vec2 y = ab / max(length(ab), 0.0001);
	vec2 q = vec2(abs(dot(p - a, vec2(-y.y, y.x))), dot(p - a, y));
	float bb = (r1 - r2) / h;
	float aa = sqrt(1.0 - bb * bb);
	float k = dot(q, vec2(-bb, aa));
	if (k < 0.0) {
		return length(q) - r1;
	}
	if (k > aa * h) {
		return length(q - vec2(0.0, h)) - r2;
	}
	return dot(q, vec2(aa, bb)) - r1;
}

void fragment() {
	vec2 p = UV * taille - ancre;
	float vie = apparition * (1.0 - smoothstep(0.55, 1.0, absorbe));
	// il respire
	float souffle = 1.0 + 0.07 * sin(temps * 3.1);
	// absorbé : il se resserre
	float e = souffle * mix(1.0, 0.45, smoothstep(0.0, 0.8, absorbe));
	vec2 q = p / e;

	// le bruit qui fait vaciller la flamme et monter sa vapeur
	vec2 g = q * 0.07;
	vec2 tord = vec2(bruits(g * 1.1 + vec2(3.1, temps * 0.6)), bruits(g * 1.1 + vec2(8.4, temps * 0.7 + 2.0)));
	float n = bruits(g * vec2(1.6, 0.8) + (tord - 0.5) * 1.3 + vec2(0.0, temps * 1.4));

	// ===================== LE CORPS DE FLAMME =====================
	// sa pointe va vers le haut — vers l'arrière quand il file vers le héros —
	// et ondule
	vec2 haut = length(vol) > 0.01 ? -normalize(vol) : vec2(0.0, -1.0);
	vec2 cote_h = vec2(-haut.y, haut.x);
	float vacille = sin(temps * 3.7) * 4.0 + sin(temps * 6.3 + 1.0) * 1.6;
	vec2 pointe = haut * hauteur_flammes * (1.0 + 0.08 * sin(temps * 5.1)) + cote_h * vacille;
	float h = clamp(dot(q, haut) / hauteur_flammes, 0.0, 1.0);        // 0 au cœur → 1 à la pointe
	float d_corps = larme(q, vec2(0.0), pointe, rayon_coeur * 1.15, 1.2);
	d_corps += (n - 0.5) * 4.0 * h;
	float corps = smoothstep(1.0, -1.0, d_corps);

	// ===================== SES DEUX LANGUES =====================
	float langues = 0.0;
	for (int k = 0; k < 2; k++) {
		float fk = float(k);
		float c = fract(temps * 0.85 + fk * 0.5);
		float flanc = fk * 2.0 - 1.0;
		vec2 depart = cote_h * flanc * rayon_coeur * 0.8 + haut * hauteur_flammes * 0.25;
		vec2 lc = depart + haut * c * hauteur_flammes * 0.95 + cote_h * flanc * sin(c * 3.0) * 5.0;
		float lr = 4.2 * (1.0 - c);
		float dl = larme(q, lc, lc + haut * lr * 2.6, lr, 0.6);
		langues = max(langues, smoothstep(0.8, -0.8, dl) * step(0.3, lr));
	}

	// ===================== LA VAPEUR (au-dessus de la pointe) =====================
	float hv = clamp(dot(q, haut) / (hauteur_flammes * 1.5), 0.0, 1.0);
	float largeur_v = rayon_coeur * 1.1 * (1.0 - hv);
	float vapeur = smoothstep(0.0, 0.9, (largeur_v - abs(dot(q, cote_h) - vacille * hv)) / rayon_coeur
			+ (n - 0.5) * 1.4 - hv * 0.5) * step(0.0, dot(q, haut)) * 0.45;

	// ===================== LE CŒUR (le bas de la flamme, brûlant) =====================
	float chaud = smoothstep(rayon_coeur * 1.0, 0.0, length(q - vec2(-1.5, -1.0)));

	// ===================== LES GOUTTELETTES QUI MONTENT =====================
	float gout = 0.0;
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		float cycle = fract(temps * 0.45 + fi * 0.27);
		float ang = fi * 1.7 + temps * 0.8;
		vec2 c = vec2(cos(ang) * (rayon_coeur + 7.0) * (1.0 - cycle * 0.4), -cycle * hauteur_flammes * 1.1);
		float r = 2.0 * (1.0 - cycle) * (0.7 + 0.3 * sin(fi * 2.3));
		gout = max(gout, smoothstep(0.8, -0.8, length(q - c) - r));
	}

	// ===================== LE TOUT (couleurs prémultipliées) =====================
	vec3 rgb = couleur_vapeur.rgb * vapeur;
	float a = vapeur;
	// la flamme : brûlante en bas, rouge au milieu, sombre à la pointe
	vec3 teinte = mix(couleur.rgb, couleur_vapeur.rgb, smoothstep(0.45, 1.0, h));
	teinte = mix(teinte, couleur_coeur.rgb, chaud);
	// absorbé, il s'embrase
	teinte = mix(teinte, couleur_coeur.rgb, smoothstep(0.0, 0.5, absorbe) * 0.6);
	rgb = teinte * corps + rgb * (1.0 - corps);
	a = corps + a * (1.0 - corps);
	rgb = couleur.rgb * langues + rgb * (1.0 - langues);
	a = langues + a * (1.0 - langues);
	rgb = couleur.rgb * gout + rgb * (1.0 - gout);
	a = gout + a * (1.0 - gout);
	// la lueur : à support borné (elle s'éteint avant le bord du rectangle)
	float lueur_r = rayon_coeur * 4.2;
	float l = clamp(1.0 - length(q * vec2(1.0, 0.8)) / lueur_r, 0.0, 1.0);
	rgb += couleur_lueur.rgb * l * l * halo * (0.8 + 0.2 * sin(temps * 3.1)) * (1.0 + absorbe);
	// rien ne touche le bord
	vec2 bord = min(UV, 1.0 - UV) * taille;
	float garde = smoothstep(0.0, 6.0, min(bord.x, bord.y));
	COLOR = vec4(rgb * garde * vie, a * garde * vie);
}
