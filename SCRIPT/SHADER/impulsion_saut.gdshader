shader_type canvas_item;
render_mode unshaded;
// IMPULSION DE SAUT — l'air chassé sous les pieds quand le joueur saute. C'est
// la sœur du souffle de dash (même blanc, mêmes traits effilés, tout piloté par
// `progress`, des formes qui MAIGRISSENT au lieu de s'estomper), mais posée à
// plat : l'effet reste AU POINT D'APPEL, le joueur s'en éloigne.
//
// Repère : l'origine est le point d'appel (les pieds), l'unité la HAUTEUR du
// rectangle, y négatif = vers le haut. Agrandir le rectangle agrandit tout.
//
// DEUX FORMES :
//   • l'ANNEAU — l'impulsion : un anneau couché sur le sol (donc une ellipse
//     large et plate) qui s'élargit d'un coup, épais à ses deux pointes. Un
//     second anneau, plus petit, le suit d'un temps.
//   • les FILETS D'AIR — le sillage : des traits effilés qui montent derrière
//     le joueur, dans le sens de son saut (`direction` : droit pour un saut sur
//     place, penché pour un saut en courant), sans jamais le dépasser
//     (`parcouru`). Ils s'écartent, ondulent, et leur queue rattrape leur tête.

uniform float progress : hint_range(0.0, 1.0) = 0.0;

// --- fournis par impulsion_saut.gd à chaque image ---------------------------
// distance déjà parcourue par le joueur depuis l'appel, en hauteurs de rectangle
uniform float parcouru = 0.6;
// largeur / hauteur du rectangle, et place du point d'appel dans le rectangle
uniform float aspect = 1.53;
uniform vec2 origine = vec2(0.5, 0.8235);
// sens du saut (y négatif = vers le haut)
uniform vec2 direction = vec2(0.0, -1.0);
// ----------------------------------------------------------------------------

uniform int nb_filets : hint_range(2, 12) = 5;
// longueur des plus longs filets (1 = une hauteur de rectangle)
uniform float longueur : hint_range(0.2, 1.0) = 0.7;
// écartement des filets de part et d'autre du saut
uniform float etalement : hint_range(0.05, 0.5) = 0.22;
// épaisseur des filets (0 = cheveux, 1 = rubans)
uniform float epaisseur : hint_range(0.1, 1.0) = 0.5;
// 0 = filets droits, 1 = ça serpente franchement
uniform float ondulation : hint_range(0.0, 1.0) = 0.5;
// l'anneau au sol (0 = aucun)
uniform float anneau : hint_range(0.0, 1.0) = 0.7;
// demi-largeur de l'anneau à la fin (en hauteurs de rectangle)
uniform float largeur_anneau : hint_range(0.1, 0.7) = 0.5;
// une valeur par impulsion : deux sauts de suite ne se ressemblent pas
uniform float graine = 0.0;
uniform vec4 couleur : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// (PI et TAU sont fournis par le langage de shader de Godot)

const int MAX_FILETS = 12;

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

	// 1) L'ANNEAU AU SOL, puis son écho
	for (int k = 0; k < 2; k++) {
		float fk = float(k);
		float retard = fk * 0.16;
		float tk = clamp((t - retard) / (1.0 - retard), 0.0, 1.0);
		float pk = 1.0 - pow(1.0 - tk, 3.0);
		float a = largeur_anneau * mix(0.22, 1.0, pk) * (1.0 - 0.32 * fk);
		float b = a * 0.22 + 0.008;             // couché : large et plat
		// l'ellipse ramenée à un cercle de rayon b ; `pente` corrige l'étirement
		// pour que l'épaisseur du trait reste la même tout autour
		vec2 q = vec2(p.x * (b / a), p.y);
		float dq = max(length(q), 0.0001);
		float pente = length(vec2(q.x * (b / a), q.y)) / dq;
		float cq = q.x / dq;
		// trait de pinceau : épais aux deux pointes, plus fin du côté éloigné
		// (le haut), et un peu irrégulier
		float pinceau = (0.25 + 0.75 * cq * cq) * mix(0.55, 1.0, smoothstep(-0.3, 0.3, q.y / dq))
				* (0.8 + 0.2 * sin(atan(q.y, q.x) * 3.0 + graine * 1.7 + fk * 2.1));
		float demi = 0.036 * anneau * (1.0 - pow(tk, 1.7)) * pinceau * (1.0 - 0.35 * fk)
				* step(retard + 0.0001, t);
		sd = max(sd, demi - abs(dq - b) / pente);
	}

	// 2) LES FILETS D'AIR, dans le sens du saut
	vec2 dir = normalize(direction + vec2(0.0, -0.0001));
	float u = dot(p, dir);                      // le long du saut
	float v = p.x * dir.y - p.y * dir.x;        // en travers
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
		// une voie par filet, d'un bord à l'autre, un peu décalée dans sa voie
		float v0 = ((fi + 0.5 + (h3 - 0.5) * 0.6) / n * 2.0 - 1.0) * etalement;
		float u0 = 0.04 + 0.10 * h4;            // il naît juste au-dessus du sol
		float l = longueur * (0.45 + 0.55 * h1);
		// la tête suit le joueur sans jamais le dépasser ; la queue la rattrape
		float tete = min(parcouru - 0.05 - 0.14 * h2, u0 + l);
		float queue = mix(u0, tete, smoothstep(0.40 + 0.15 * h4, 1.0, t));
		// serrés sous le joueur au départ, ils s'écartent et ondulent
		float axe = v0 * mix(0.55, 1.0, pousse)
				+ ondulation * 0.03 * sin(u * 9.0 + h1 * TAU - t * 5.0);
		float demi = epaisseur * (0.022 + 0.024 * h2) * maigrir;
		sd = max(sd, fuseau(u, v - axe, queue, tete, demi, 0.72));
	}

	COLOR = vec4(couleur.rgb, couleur.a * smoothstep(0.0, px, sd));
}
