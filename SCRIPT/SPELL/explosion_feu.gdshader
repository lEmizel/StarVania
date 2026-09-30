shader_type canvas_item;
render_mode unshaded;
// EXPLOSION DE FEU — l'impact de la boule de feu du squelette bleu (1er oct.
// 2026). Elle remplace l'éclaboussure de la bloodball recolorée en orange
// qu'utilisait la boule : une éclaboussure de SANG n'avait plus de sens pour
// une boule de FEU (Kaoru). explosion_feu.gd anime `progress` de 0 à 1.
//
// Même famille que boule_de_feu / jet_flamme / le slash de feu : bruit à
// gradients (hash sans sin), aplats cartoon en bandes, même palette de quatre
// couleurs.
//
// DÉROULÉ (progress 0 → 1) :
//   • ÉCLAIR : un cœur clair qui naît au point d'impact (le premier cinquième)
//   • NUAGE DE FEU : bord rongé par le bruit et gonflé en lobes (une silhouette
//     de nuage qui bouillonne), il gonfle vite puis ralentit, en
//     montant un peu (le feu monte) ; il refroidit du jaune vers le rouge et se
//     creuse PAR LE CENTRE (le cœur brûle en premier) : il finit en couronne
//     de lambeaux rouges qui s'éteignent
//   • LANGUES : au début, des jets de flammes rayonnent autour du nuage
//   • LIGNES DE FORCE : au moment de l'impact, des traits fins jaillissent du
//     centre dans toutes les directions (cœur clair, bord orange), filent vers
//     l'extérieur en s'effilant et s'éteignent pendant que le nuage gonfle
//   • BRAISES : des étincelles projetées tout autour, qui ralentissent
// Tout reste dans le rectangle (fondu sur ses bords) : `rayon` laisse la place
// aux langues et aux braises.

// --- fournis par explosion_feu.gd ---
uniform float progress : hint_range(0.0, 1.0) = 0.3;
// 1 = un vrai impact ; moins = plus petit, moins chaud
uniform float puissance : hint_range(0.0, 1.0) = 1.0;
uniform float graine = 0.0;

// --- la forme ---
// rayon maximal du nuage, en part du demi-côté du rectangle
uniform float rayon : hint_range(0.2, 0.9) = 0.6;
// de combien le nuage monte en brûlant (part du demi-côté)
uniform float montee : hint_range(0.0, 0.5) = 0.16;
// taille des paquets de feu (plus grand = plus fin)
uniform float detail : hint_range(1.0, 12.0) = 4.5;
// longueur des langues de flammes du début (part du rayon)
uniform float langues : hint_range(0.0, 1.0) = 0.5;
// lueur autour du feu
uniform float lueur : hint_range(0.0, 1.0) = 0.35;
uniform int nb_braises : hint_range(0, 24) = 12;
// les LIGNES DE FORCE : combien, leur force (0 = aucune), leur longueur et
// leur épaisseur (parts du demi-côté)
uniform int nb_lignes : hint_range(0, 24) = 13;
uniform float lignes : hint_range(0.0, 1.0) = 1.0;
uniform float longueur_lignes : hint_range(0.05, 0.8) = 0.44;
uniform float epaisseur_lignes : hint_range(0.005, 0.06) = 0.015;

// --- les couleurs (celles de la boule de feu) ---
// 1 = aplats dessin animé, 0 = dégradé doux
uniform float style_cartoon : hint_range(0.0, 1.0) = 1.0;
uniform int nb_bandes : hint_range(2, 8) = 4;
uniform vec4 outer_color : source_color = vec4(0.9, 0.05, 0.005, 1.0);
uniform vec4 middle_color : source_color = vec4(1.0, 0.32, 0.01, 1.0);
uniform vec4 inner_color : source_color = vec4(1.0, 0.85, 0.15, 1.0);
uniform vec4 core_color : source_color = vec4(1.0, 1.0, 0.75, 1.0);

// (PI et TAU sont fournis par le langage de shader de Godot)

float alea(vec2 p) {
	p = fract(p * vec2(443.897, 441.423));
	p += dot(p, p.yx + 19.19);
	return fract((p.x + p.y) * p.x);
}

// BRUIT À GRADIENTS (repris de boule_de_feu.gdshader)
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

float fbm(vec2 p) {
	const mat2 ROT = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	p = ROT * p;
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 3; i++) {
		v += bruit(p) * amp;
		p = ROT * p * 2.03 + vec2(17.1, 9.2);
		amp *= 0.5;
	}
	return v / 0.875;
}

// la chaleur (0…1) en couleur : rouge, orange, jaune, cœur clair
vec3 rampe(float h) {
	if (h < 0.30) {
		return mix(outer_color.rgb, middle_color.rgb, h / 0.30);
	} else if (h < 0.70) {
		return mix(middle_color.rgb, inner_color.rgb, (h - 0.30) / 0.40);
	}
	return mix(inner_color.rgb, core_color.rgb, (h - 0.70) / 0.30);
}

// `dessus` posé sur `dessous` (couleurs non prémultipliées)
vec4 par_dessus(vec4 dessous, vec4 dessus) {
	float a = dessus.a + dessous.a * (1.0 - dessus.a);
	return vec4((dessus.rgb * dessus.a + dessous.rgb * dessous.a * (1.0 - dessus.a)) / max(a, 0.0001), a);
}

void fragment() {
	float t = clamp(progress, 0.0, 1.0);
	float pw = clamp(puissance, 0.0, 1.0);
	if (t >= 0.999 || pw <= 0.002) {
		COLOR = vec4(0.0);
	} else {
		vec2 p = (UV - 0.5) * 2.0;                     // -1 … 1 : le demi-côté vaut 1
		float px = max(fwidth(p.x), fwidth(p.y)) * 0.75;

		// LE NUAGE : il gonfle vite puis ralentit, et monte en brûlant
		float gonfle = 1.0 - pow(1.0 - t, 3.0);
		float R = rayon * mix(0.3, 1.0, gonfle) * (0.55 + 0.45 * pw);
		vec2 q = p - vec2(0.0, -montee * t * t);
		float d = length(q);
		// sa matière : du bruit qui monte
		vec2 nq = q * detail + vec2(graine * 3.1, graine * 1.7 + t * 2.2);
		float gros = fbm(nq);
		float fin = fbm(nq * 2.3 + vec2(5.3, 1.1));
		float matiere = clamp((mix(gros, fin, 0.35) - 0.28) / 0.44, 0.0, 1.0);
		// LES LANGUES : des jets de flammes autour, au début seulement (le
		// bruit est lu sur la DIRECTION : pas de couture à ±180°)
		vec2 dir = q / max(d, 0.0001);
		float jets = smoothstep(0.45, 0.85, fbm(dir * 2.2 + vec2(graine, graine * 0.7)));
		// des LOBES qui durent : une silhouette de nuage qui bouillonne, pas un disque
		float lobes = fbm(dir * 1.4 + vec2(graine * 2.3, t * 0.8));
		float bord = R * (0.82 + 0.36 * lobes) * (1.0 + langues * jets * (1.0 - smoothstep(0.12, 0.55, t)));
		// distance BRUITÉE : le bord est rongé, et les bandes de couleur
		// épousent les paquets de feu (pas d'anneaux de cible)
		float dn = d + (matiere - 0.5) * 0.5 * R;
		float nuage = 1.0 - smoothstep(bord * 0.9, bord * 1.04, dn);
		// le cœur brûle en premier : le nuage se creuse par le centre
		// (pas avant la moitié de l'explosion ; sans ce garde-fou, un trou d'un
		// pixel s'ouvrait au centre dès la 1re image, là où le bruit rend `dn` < 0)
		float creux = smoothstep(0.45, 1.0, t) * R * 0.95;
		float couronne = creux < 0.002 ? 1.0 : smoothstep(creux * 0.75, creux * 1.1, dn);
		// et tout se dissout en fin de course (le seuil monte)
		float seuil = smoothstep(0.45, 1.0, t) * 0.85;
		float garde = smoothstep(seuil - 0.1, seuil + 0.05, matiere);
		float corps = nuage * couronne * garde;

		// LA CHALEUR : au centre, au début ; ce qui se dissout rougit
		float chaleur = (1.0 - clamp(dn / max(bord, 0.0001), 0.0, 1.0)) * (1.0 - t * 0.85) * (0.7 + 0.3 * pw)
				+ (fin - 0.5) * 0.25;
		// l'éclair du début : un cœur clair au point d'impact
		float eclair = (1.0 - smoothstep(0.0, 0.2, t)) * (1.0 - smoothstep(0.0, max(R, 0.3) * 0.8, d));
		chaleur = max(chaleur, eclair);
		chaleur *= 0.55 + 0.45 * smoothstep(seuil, seuil + 0.3, matiere);
		chaleur = clamp(chaleur, 0.0, 1.0);
		float aplat = (floor(chaleur * float(nb_bandes)) + 0.5) / float(nb_bandes);
		chaleur = mix(chaleur, aplat, style_cartoon);
		vec3 rgb = rampe(chaleur);
		float a = mix(corps, smoothstep(0.35, 0.62, corps), style_cartoon);

		// LA LUEUR autour du nuage, qui s'éteint avec lui
		float halo = lueur * (1.0 - smoothstep(0.0, 0.6, t)) * (1.0 - smoothstep(0.0, 0.3, max(dn - bord, 0.0))) * step(creux * 0.9, dn);

		// LES BRAISES : projetées tout autour, elles ralentissent, montent un
		// peu et s'éteignent chacune à son heure
		float braise = 0.0;
		for (int k = 0; k < nb_braises; k++) {
			float fk = float(k);
			float a0 = (fk + alea(vec2(fk, graine))) / float(nb_braises) * TAU;
			float v = mix(0.5, 0.82, alea(vec2(fk, graine + 3.0)));
			float course = (1.0 - pow(1.0 - t, 2.5)) * v * (0.6 + 0.4 * pw);
			vec2 pos = vec2(cos(a0), sin(a0)) * course + vec2(0.0, -0.1 * t * t);
			float r_b = mix(0.03, 0.012, t);
			float vie_b = 1.0 - smoothstep(0.5 + 0.35 * alea(vec2(fk, graine + 7.0)), 1.0, t);
			braise = max(braise, vie_b * (1.0 - smoothstep(r_b - px, r_b + px, length(p - pos))));
		}

		// LES LIGNES DE FORCE : chacune a son angle, sa vitesse, sa longueur et
		// un petit retard ; elle part près du centre, file vers l'extérieur
		// (vite puis moins vite), raccourcit et s'éteint. Profil en fuseau :
		// fine aux deux bouts, pleine au milieu ; un cœur clair dans un bord
		// orange
		float ligne_bord = 0.0;
		float ligne_coeur = 0.0;
		for (int k = 0; k < nb_lignes; k++) {
			float fk = float(k);
			float ang = (fk + 0.8 * alea(vec2(fk, graine + 11.0))) / float(nb_lignes) * TAU;
			vec2 dl = vec2(cos(ang), sin(ang));
			float retard = 0.07 * alea(vec2(fk, graine + 13.0));
			float tau = clamp((t - retard) / 0.5, 0.0, 1.0);
			if (tau <= 0.0 || tau >= 1.0) {
				continue;
			}
			float vit = mix(0.75, 1.15, alea(vec2(fk, graine + 17.0)));
			float lon = longueur_lignes * mix(0.55, 1.2, alea(vec2(fk, graine + 19.0))) * (1.0 - 0.55 * tau);
			float r1 = min(0.18 + 0.72 * vit * (1.0 - pow(1.0 - tau, 2.2)), 0.93);
			float r0 = max(r1 - lon, 0.05);
			float u = dot(p, dl);
			if (u <= r0 || u >= r1) {
				continue;
			}
			float travers = abs(p.x * dl.y - p.y * dl.x);
			float fuseau = pow(sin(clamp((u - r0) / (r1 - r0), 0.0, 1.0) * PI), 0.85);
			float demi_l = epaisseur_lignes * mix(0.7, 1.3, alea(vec2(fk, graine + 23.0))) * fuseau * (1.0 - 0.4 * tau);
			float vis = smoothstep(0.0, 0.08, tau) * (1.0 - smoothstep(0.45, 0.85, tau)) * lignes * (0.5 + 0.5 * pw);
			ligne_bord = max(ligne_bord, vis * (1.0 - smoothstep(demi_l * 1.8 - px, demi_l * 1.8 + px, travers)));
			ligne_coeur = max(ligne_coeur, vis * (1.0 - smoothstep(demi_l * 0.8 - px, demi_l * 0.8 + px, travers)));
		}

		// du fond vers le dessus : la lueur, le feu, les lignes de force, les braises
		vec4 c = vec4(middle_color.rgb, halo);
		c = par_dessus(c, vec4(rgb, a));
		c = par_dessus(c, vec4(mix(middle_color.rgb, inner_color.rgb, 0.35), ligne_bord));
		c = par_dessus(c, vec4(core_color.rgb, ligne_coeur));
		c = par_dessus(c, vec4(mix(middle_color.rgb, inner_color.rgb, 0.6), braise));
		// jamais coupé net par le bord du rectangle
		float bord_rect = 1.0 - smoothstep(0.9, 1.0, max(abs(p.x), abs(p.y)));
		COLOR = vec4(c.rgb, c.a * bord_rect);
	}
}
