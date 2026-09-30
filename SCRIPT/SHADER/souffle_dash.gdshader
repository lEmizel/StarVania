shader_type canvas_item;
render_mode unshaded;
// SOUFFLE DE DASH — l'air que le joueur chasse en partant en dash. L'effet reste
// AU POINT DE DÉPART : le joueur s'en éloigne, le souffle ne le suit pas. Même
// famille que impact_blanc (aplats nets, tout piloté par `progress`, des formes
// qui MAIGRISSENT au lieu de s'estomper).
//
// Repère : l'origine est le point de départ du dash, +x le sens du dash,
// l'unité la HAUTEUR du rectangle. `scale.x = -1` sur le nœud pour un dash vers
// la gauche. Agrandir le rectangle agrandit tout l'effet.
//
// DEUX FORMES :
//   • l'ANNEAU D'AIR — l'impulsion : un anneau vu de profil (donc une ellipse
//     haute et étroite) qui enfle et recule, tracé comme au pinceau, épais à
//     l'arrière, ouvert à l'avant là où le joueur est passé. Un second anneau,
//     plus petit, le suit d'un temps.
//   • les FILETS D'AIR — le sillage : des traits effilés qui s'étirent derrière
//     le joueur sans jamais le dépasser (`parcouru`), s'écartent à mesure que
//     l'anneau enfle, et ondulent ; leur queue finit par rattraper leur tête.

uniform float progress : hint_range(0.0, 1.0) = 0.0;

// --- fournis par souffle_dash.gd à chaque image -----------------------------
// distance déjà parcourue par le joueur depuis le départ, en hauteurs de rectangle
uniform float parcouru = 1.2;
// largeur / hauteur du rectangle, et place du point de départ dans le rectangle
uniform float aspect = 1.55;
uniform vec2 origine = vec2(0.29, 0.5);
// ----------------------------------------------------------------------------

uniform int nb_filets : hint_range(2, 14) = 6;
// longueur des plus longs filets (1 = une hauteur de rectangle)
uniform float longueur : hint_range(0.2, 1.2) = 1.0;
// écartement vertical des filets au départ
uniform float etalement : hint_range(0.05, 0.45) = 0.3;
// épaisseur des filets (0 = cheveux, 1 = rubans)
uniform float epaisseur : hint_range(0.1, 1.0) = 0.5;
// 0 = filets droits, 1 = ça serpente franchement
uniform float ondulation : hint_range(0.0, 1.0) = 0.5;
// l'anneau d'air du départ (0 = aucun)
uniform float anneau : hint_range(0.0, 1.0) = 0.7;
// une valeur par souffle : deux dashs de suite ne se ressemblent pas
uniform float graine = 0.0;
uniform vec4 couleur : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// (PI et TAU sont fournis par le langage de shader de Godot)

const int MAX_FILETS = 14;

// hash 1D sans sin : une valeur stable par filet
float alea(float n) {
	n = fract(n * 0.1031);
	n *= n + 33.33;
	n *= n + n;
	return fract(n);
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
	vec2 p = (UV - origine) * vec2(aspect, 1.0);
	float t = clamp(progress, 0.0, 1.0);
	float maigrir = 1.0 - t * t;                // tout maigrit, surtout vers la fin
	float pousse = 1.0 - pow(1.0 - t, 3.0);     // ça part très vite puis ça freine
	// un pixel d'écran, en hauteurs de rectangle : des bords nets à toute échelle
	float px = length(vec2(dFdx(UV.y), dFdy(UV.y))) * 1.5;
	float sd = -1.0;

	// 1) L'ANNEAU D'AIR, puis son écho
	for (int k = 0; k < 2; k++) {
		float fk = float(k);
		float retard = fk * 0.14;
		float tk = clamp((t - retard) / (1.0 - retard), 0.0, 1.0);
		float pk = 1.0 - pow(1.0 - tk, 3.0);    // il part très vite puis il freine
		float ry = mix(0.14, 0.46, pk) * (1.0 - 0.30 * fk);
		float rx = ry * 0.30;
		float cx = -0.04 - 0.10 * pk;           // il recule : c'est l'air chassé
		// l'ellipse ramenée à un cercle de rayon ry ; `pente` corrige l'étirement
		// pour que l'épaisseur du trait reste la même tout autour
		vec2 q = vec2((p.x - cx) * (ry / rx), p.y);
		float dq = length(q);
		float pente = length(vec2(q.x * (ry / rx), q.y)) / max(dq, 0.0001);
		float a_q = atan(q.y, q.x);
		float arriere = 0.5 - 0.5 * cos(a_q);   // 0 devant, 1 derrière
		float pinceau = smoothstep(0.08, 0.75, arriere)
				* (0.72 + 0.28 * sin(a_q * 3.0 + graine * 1.7 + fk * 2.1));
		float demi = 0.040 * anneau * (1.0 - pow(tk, 1.7)) * pinceau * (1.0 - 0.35 * fk)
				* step(retard + 0.0001, t);
		sd = max(sd, demi - abs(dq - ry) / pente);
	}

	// 2) LES FILETS D'AIR
	float n = float(nb_filets);
	for (int i = 0; i < MAX_FILETS; i++) {
		if (i >= nb_filets) {
			break;
		}
		float fi = float(i);
		float h1 = alea(fi * 1.7 + graine);
		float h2 = alea(fi * 3.1 + graine * 1.3 + 5.0);
		float h3 = alea(fi * 5.3 + graine * 0.7 + 9.0);
		float h4 = alea(fi * 7.9 + graine * 2.1 + 3.0);
		// une voie par filet, du haut vers le bas, un peu décalée dans sa voie
		float y0 = ((fi + 0.5 + (h3 - 0.5) * 0.6) / n * 2.0 - 1.0) * etalement;
		float x0 = -0.02 - 0.16 * h4;           // il naît un peu derrière le départ
		float l = longueur * (0.40 + 0.60 * h1);
		// la tête suit le joueur sans jamais le dépasser ; la queue la rattrape
		float tete = min(parcouru - 0.06 - 0.16 * h2, x0 + l);
		float rattrape = smoothstep(0.45 + 0.15 * h4, 1.0, t);
		float queue = mix(x0, tete, rattrape);
		// serrés derrière le joueur au départ, les filets s'écartent en même
		// temps que l'anneau enfle (un sillage qui se disperse), et ondulent
		float axe = y0 * mix(0.45, 1.0, pousse)
				+ ondulation * 0.035 * sin(p.x * 8.0 + h1 * TAU - t * 5.0);
		float demi = epaisseur * (0.020 + 0.022 * h2) * maigrir;
		sd = max(sd, fuseau(p.x, p.y - axe, queue, tete, demi, 0.72));
	}

	COLOR = vec4(couleur.rgb, couleur.a * smoothstep(0.0, px, sd));
}
