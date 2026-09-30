shader_type canvas_item;
render_mode unshaded;
// TRACE DE GRIFFE — ce que la griffe du joueur laisse sur le mur pendant le
// wall run. Même famille que le souffle de dash (traits nets, sans contour,
// des formes qui MAIGRISSENT au lieu de s'estomper), mais l'effet n'a pas de
// durée propre : il vit tant que la griffe racle, et ce qu'elle a laissé finit
// de s'éteindre sur place.
//
// Repère : l'origine est le BOUT DES DOIGTS, +x le sens de la course
// (`scale.x = -1` sur le nœud pour une course vers la gauche), l'unité le pixel.
// Le rectangle suit la griffe ; tout ce qui est dessiné dedans est pourtant
// ANCRÉ AU MUR, parce que chaque point est repéré par son abscisse sur le mur
// (`parcouru` moins sa distance à la griffe) et par son âge.
//
// TROIS FORMES :
//   • les SILLONS — un trait par doigt, chaud et épais sous la griffe, qui
//     tremble un peu, refroidit (blanc → `couleur_fin`) et s'affine jusqu'à
//     disparaître au bout de `vie` secondes.
//   • les ÉTINCELLES — arrachées tout le long du chemin : elles partent vers
//     l'arrière et en travers, retombent, et s'éteignent en maigrissant.
//   • l'ÉCLAT — le point de contact : une petite lentille blanche qui vacille
//     au bout des doigts, tant que la griffe touche.

// --- fournis par trace_de_griffe.gd à chaque image --------------------------
// taille du rectangle (px) et place du bout des doigts dedans
uniform vec2 taille = vec2(480.0, 270.0);
uniform vec2 origine = vec2(0.9167, 0.4444);
// longueur déjà raclée depuis le début du trait (px) et vitesse de la course (px/s)
uniform float parcouru = 400.0;
uniform float vitesse = 700.0;
// secondes écoulées depuis que la griffe a quitté le mur (0 tant qu'elle racle)
uniform float temps_lache = 0.0;
// 1 tant que la griffe touche, 0 dès qu'elle quitte le mur
uniform float contact = 1.0;
// une valeur par trait : deux traits ne se ressemblent pas
uniform float graine = 0.0;
// ----------------------------------------------------------------------------

// nombre de doigts, et écart entre deux doigts (px)
uniform int nb_doigts : hint_range(1, 5) = 4;
uniform float ecart : hint_range(2.0, 20.0) = 7.3;
// demi-épaisseur d'un sillon tout frais (px)
uniform float epaisseur : hint_range(0.5, 6.0) = 2.0;
// 0 = sillons tirés à la règle, 1 = la main tremble franchement
uniform float tremble : hint_range(0.0, 1.0) = 0.5;
// durée de vie d'un sillon (s) : à 700 px/s, 0,42 s = 294 px de trace
uniform float vie : hint_range(0.1, 1.5) = 0.42;
// part des étincelles qui partent (0 = aucune)
uniform float etincelles : hint_range(0.0, 1.0) = 0.75;
// une étincelle possible tous les `pas` pixels de mur
uniform float pas : hint_range(8.0, 60.0) = 12.0;
// durée de vie des étincelles (s), leur taille, et ce qui les fait retomber (px/s²)
uniform float vie_etincelles : hint_range(0.1, 0.8) = 0.36;
uniform float taille_etincelles : hint_range(0.3, 3.0) = 1.25;
uniform float gravite : hint_range(0.0, 2500.0) = 900.0;
// l'éclat au point de contact (0 = aucun)
uniform float eclat : hint_range(0.0, 1.0) = 0.8;
// chaud sous la griffe, puis ça refroidit
uniform vec4 couleur : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 couleur_fin : source_color = vec4(0.8, 0.62, 1.0, 1.0);

const int MAX_DOIGTS = 5;
// plafond du nombre d'étincelles regardées par pixel (les plus vieilles, déjà
// presque éteintes, sont ignorées au-delà)
const int MAX_ETINCELLES = 48;

// hash 1D sans sin : une valeur stable par indice
float alea(float n) {
	n = fract(n * 0.1031);
	n *= n + 33.33;
	n *= n + n;
	return fract(n);
}

// bruit 1D lissé, entre 0 et 1
float bruit(float x) {
	float i = floor(x);
	float f = fract(x);
	return mix(alea(i), alea(i + 1.0), f * f * (3.0 - 2.0 * f));
}

// Un FUSEAU couché sur l'axe u, de u0 à u1, pointu aux deux bouts. `demi` est
// sa demi-largeur au ventre, placé à la fraction `ventre` de sa longueur.
// Renvoie une distance, positive dedans.
float fuseau(float u, float v, float u0, float u1, float demi, float ventre) {
	float s = (u - u0) / max(u1 - u0, 0.0001);
	if (u1 <= u0 || s <= 0.0 || s >= 1.0) {
		return -1.0;
	}
	return demi * min(s / ventre, (1.0 - s) / (1.0 - ventre)) - abs(v);
}


void fragment() {
	vec2 p = (UV - origine) * taille;           // px, depuis le bout des doigts
	float u = -p.x;                             // distance DERRIÈRE la griffe
	float v = p.y;
	float vit = max(vitesse, 1.0);
	// un pixel d'écran, en pixels du rectangle : des bords nets à toute échelle
	float px = length(vec2(dFdx(UV.y), dFdy(UV.y))) * taille.y * 1.2;
	float nd = float(nb_doigts);

	// 1) LES SILLONS
	float s = parcouru - u;                     // abscisse sur le mur depuis le début du trait
	float age = u / vit + temps_lache;          // depuis quand la griffe est passée là
	float frais = 1.0 - clamp(age / vie, 0.0, 1.0);
	float sd_s = -1.0;
	if (u >= 0.0 && s >= 0.0) {
		// chaud et gonflé sous la griffe, effilé au tout début du trait
		float gonfle = (1.0 + 1.2 * exp(-u / 14.0) * contact) * smoothstep(0.0, 26.0, s);
		for (int i = 0; i < MAX_DOIGTS; i++) {
			if (i >= nb_doigts) {
				break;
			}
			float fi = float(i);
			float y0 = (fi - (nd - 1.0) * 0.5) * ecart + (alea(fi * 2.3 + graine) - 0.5) * 2.4;
			float ondule = tremble * (1.7 * sin(s * 0.045 + fi * 1.9 + graine)
					+ 0.8 * sin(s * 0.13 + fi * 4.1 + graine * 2.0));
			float demi = epaisseur * (0.7 + 0.6 * alea(fi * 3.3 + graine * 1.7))
					* pow(frais, 0.7) * (0.65 + 0.35 * bruit(s / 14.0 + fi * 7.0 + graine)) * gonfle;
			sd_s = max(sd_s, demi - abs(v - y0 - ondule));
		}
	}

	// 2) LES ÉTINCELLES : une par case de `pas` pixels de mur. On regarde toutes
	// celles qui peuvent encore vivre derrière la griffe.
	float sd_e = -1.0;
	float age_e = 0.0;
	float k_tete = floor(parcouru / pas);
	// au-delà de cette distance derrière la griffe, plus aucune n'est en vie
	int n_vivantes = int(ceil(vit * vie_etincelles / pas)) + 1;
	for (int j = 0; j < MAX_ETINCELLES; j++) {
		float k = k_tete - float(j);
		if (k < 0.0 || j >= n_vivantes) {
			break;
		}
		float h1 = alea(k * 1.7 + graine);
		float h2 = alea(k * 3.1 + graine * 1.3 + 5.0);
		float h3 = alea(k * 5.3 + graine * 0.7 + 9.0);
		float h4 = alea(k * 7.9 + graine * 2.1 + 3.0);
		float h5 = alea(k * 9.7 + graine * 0.9 + 1.0);
		float s_k = (k + h1) * pas;             // où elle est née sur le mur
		float tau = (parcouru - s_k) / vit + temps_lache;
		float vie_k = vie_etincelles * (0.55 + 0.45 * h2);
		if (h5 > etincelles || s_k > parcouru || tau > vie_k) {
			continue;
		}
		float r = tau / vie_k;
		float y0 = (floor(h3 * nd) - (nd - 1.0) * 0.5) * ecart;
		// vitesse de départ (px/s) : vers l'arrière et en travers, un peu plus
		// souvent vers le haut ; puis la gravité
		vec2 v0 = vec2(mix(40.0, 340.0, h4), (h3 * 2.0 - 1.0) * 380.0 - 70.0);
		vec2 pos = vec2((parcouru - s_k) + v0.x * tau, y0 + v0.y * tau + 0.5 * gravite * tau * tau);
		vec2 dir = normalize(vec2(v0.x, v0.y + gravite * tau));
		float l = taille_etincelles * mix(12.0, 28.0, h2) * (1.0 - 0.5 * r);
		float demi = taille_etincelles * mix(1.6, 3.0, h4) * (1.0 - r * r);
		vec2 e = vec2(u, v) - pos;
		// la tête de l'étincelle est en `pos`, sa traîne derrière elle
		float f = fuseau(dot(e, dir), e.x * dir.y - e.y * dir.x, -l, 0.0, demi, 0.7);
		if (f > sd_e) {
			sd_e = f;
			age_e = r;
		}
	}

	// 3) L'ÉCLAT du point de contact : une lentille en travers des doigts, qui vacille
	float haut = (nd - 1.0) * 0.5 * ecart + 7.0;
	float vacille = 0.55 + 0.45 * alea(floor(parcouru / 9.0) + graine * 3.0);
	float sd_c = fuseau(v, p.x, -haut, haut, 6.5 * eclat * contact * vacille, 0.5);

	// du plus froid au plus chaud : sillons, puis étincelles, puis l'éclat par-dessus
	float a_s = smoothstep(0.0, px, sd_s);
	float a_e = smoothstep(0.0, px, sd_e);
	float a_c = smoothstep(0.0, px, sd_c);
	vec3 rgb = mix(couleur.rgb, couleur_fin.rgb, smoothstep(0.0, 0.6, 1.0 - frais));
	rgb = mix(rgb, mix(couleur.rgb, couleur_fin.rgb, smoothstep(0.2, 0.9, age_e)), a_e);
	rgb = mix(rgb, couleur.rgb, a_c);
	COLOR = vec4(rgb, couleur.a * max(max(a_s, a_e), a_c));
}
