shader_type canvas_item;
render_mode unshaded;
// VENT (2 oct. 2026, piège de Kaoru) — le courant d'air qui sort d'une bouche
// et file le long de son axe (vers −y dans le rectangle ; le nœud tourné, le
// vent tourne avec). Même famille que le souffle du dash : des aplats blancs
// nets, des formes qui MAIGRISSENT au lieu de s'estomper.
//   • les FILETS : des fuseaux blancs qui filent dans le courant, gros de la
//     tête, effilés de la queue ; ils ondulent, plus fort en haut, et le
//     courant s'évase en montant. Peu nombreux, lents et fins pendant la brise
//     (`puissance` basse), serrés, longs et rapides en pleine rafale ;
//   • les ANNEAUX D'AIR : au départ de la rafale (`rafale`, secondes), deux
//     anneaux vus de profil sortent de la bouche, montent et s'ouvrent, tracés
//     comme au pinceau.
// Piloté par SCRIPT/INTERACTIBLE/piege_de_vent.gd (`defilement` : la distance
// parcourue par l'air, cumulée par le script pour que les filets ne sautent
// pas quand la puissance change).

uniform vec2 taille = vec2(340.0, 580.0);
uniform vec2 bouche = vec2(170.0, 560.0);       // le milieu de la bouche, dans le rectangle (px)
uniform float largeur = 200.0;                  // le courant à la bouche (px)
uniform float portee = 480.0;                   // jusqu'où il porte (px)
uniform float puissance : hint_range(0.0, 1.0) = 1.0;
uniform float defilement = 0.0;
uniform float rafale = 10.0;
uniform float temps = 0.0;
uniform float graine = 0.0;
uniform float evasement = 0.55;                 // le courant s'élargit d'autant au bout

uniform int nb_filets : hint_range(4, 24) = 20;
uniform float longueur_filets = 200.0;          // px
uniform float epaisseur = 2.6;                  // demi-épaisseur au ventre (px)
uniform float ondulation = 9.0;                 // px
uniform float anneaux : hint_range(0.0, 2.0) = 1.0;
uniform int nb_rubans : hint_range(0, 6) = 3;   // les grands rubans d'air, derrière les filets
uniform float opacite_rubans : hint_range(0.0, 1.0) = 0.45;
uniform int nb_volutes : hint_range(0, 6) = 2;   // les volutes qui s'enroulent vers l'extérieur, en haut
uniform vec4 couleur : source_color = vec4(1.0, 1.0, 1.0, 0.9);

const int MAX_FILETS = 24;


float alea(float n) {
	n = fract(n * 0.1031);
	n *= n + 33.33;
	n *= n + n;
	return fract(n);
}

// un FUSEAU couché sur l'axe u, de u0 à u1, pointu aux deux bouts, ventre à la
// fraction `ventre` ; positif dedans, −1 hors de sa portée
float fuseau(float u, float v, float u0, float u1, float demi, float ventre) {
	float s = (u - u0) / max(u1 - u0, 0.0001);
	if (u1 <= u0 || s <= 0.0 || s >= 1.0) {
		return -1.0;
	}
	return demi * min(s / ventre, (1.0 - s) / (1.0 - ventre)) - abs(v);
}

// une VOLUTE : un trait qui part du bas, monte, passe par-dessus et s'enroule
// vers l'extérieur (`sens` : +1 à droite, −1 à gauche). `q` : le point par
// rapport au centre de l'enroulement, en (x, hauteur). Positif dedans.
float volute(vec2 q, float r0, float sens, float demi) {
	q.x *= sens;
	float r = length(q);
	// l'angle compté dans le sens des aiguilles, depuis le point de départ (à gauche)
	float th = mod(PI - atan(q.y, q.x), TAU);
	float t_max = 1.55 * PI;
	float meilleur = 1e5;
	float s_m = 0.0;
	for (int k = 0; k < 2; k++) {
		float t = th + TAU * float(k);
		if (t > t_max) {
			continue;
		}
		float d = abs(r - r0 * exp(-0.2 * t));
		if (d < meilleur) {
			meilleur = d;
			s_m = t / t_max;
		}
	}
	if (meilleur > 1e4) {
		return -1.0;
	}
	// effilée au départ, pointue au bout de l'enroulement
	return demi * smoothstep(0.0, 0.14, s_m) * pow(1.0 - s_m, 0.6) - meilleur;
}

void fragment() {
	vec2 pix = UV * taille;
	float px = max(fwidth(pix.x), 0.001);
	vec2 p = pix - bouche;
	float h = -p.y;                                  // hauteur au-dessus de la bouche
	float hn = clamp(h / max(portee, 1.0), 0.0, 1.0);
	float demi_l = largeur * 0.5;
	float w = demi_l * (1.0 + evasement * pow(hn, 1.5));
	float sd = -1.0;

	// ===================== LES RUBANS =====================
	// de grandes bandes d'air qui serpentent, plus lentes que les filets : la
	// masse du courant (en aplat plus pâle, derrière)
	float sd_r = -1.0;
	for (int i = 0; i < 6; i++) {
		if (i >= nb_rubans) {
			break;
		}
		float fi = float(i) + 40.0;
		float h2 = alea(fi * 3.1 + graine * 1.3 + 5.0);
		float h3 = alea(fi * 5.3 + graine * 0.7 + 9.0);
		float h4 = alea(fi * 7.9 + graine * 2.1 + 3.0);
		float u = ((float(i) + 0.5) / float(nb_rubans) * 2.0 - 1.0) * 0.55 + (h2 - 0.5) * 0.2;
		float axe = u * w + (16.0 + 10.0 * h3) * (0.4 + 0.6 * hn)
				* sin(h * (0.011 + 0.006 * h4) + h3 * TAU - temps * (1.5 + h2));
		float periode = portee * (0.9 + 0.4 * h4);
		float s = h - defilement * (0.55 + 0.15 * h2) - h3 * periode;
		float le_long = s - floor(s / periode) * periode;
		float l = portee * (0.5 + 0.2 * h2) * mix(0.4, 1.0, puissance);
		float maigrir = smoothstep(0.0, 30.0, h) * (1.0 - smoothstep(0.55, 1.0, hn));
		float demi = (6.0 + 3.0 * h4) * maigrir * puissance;
		sd_r = max(sd_r, fuseau(le_long, p.x - axe, 0.0, l, demi, 0.6));
	}

	// ===================== LES FILETS =====================
	float nf = float(nb_filets);
	for (int i = 0; i < MAX_FILETS; i++) {
		if (i >= nb_filets) {
			break;
		}
		float fi = float(i);
		float h1 = alea(fi * 1.7 + graine);
		float h2 = alea(fi * 3.1 + graine * 1.3 + 5.0);
		float h3 = alea(fi * 5.3 + graine * 0.7 + 9.0);
		float h4 = alea(fi * 7.9 + graine * 2.1 + 3.0);
		float h5 = alea(fi * 11.3 + graine * 0.3 + 1.0);
		// pendant la brise, seuls quelques filets
		if (h1 > mix(0.3, 1.0, puissance)) {
			continue;
		}
		// sa voie, d'un bord à l'autre du courant, et son ondulation
		float u = (((fi + 0.5 + (h2 - 0.5) * 0.7) / nf) * 2.0 - 1.0) * 0.9;
		float axe = u * w + ondulation * (0.35 + 0.65 * hn)
				* sin(h * (0.018 + 0.012 * h3) + h4 * TAU + temps * (2.0 + 2.0 * h5));
		// il file : des passages à la suite dans sa voie, chacun sa longueur
		float vit = 0.75 + 0.5 * h3;
		float periode = longueur_filets * (1.6 + 1.2 * h4);
		float s = h - defilement * vit - h5 * periode;
		float k = floor(s / periode);
		float le_long = s - k * periode;
		float hk = alea(fi * 13.1 + k * 7.7 + graine);
		if (hk < 0.18) {
			continue;                                // des trous dans la file
		}
		float l = longueur_filets * (0.35 + 0.85 * hk) * mix(0.5, 1.0, puissance);
		// il maigrit à la sortie de la bouche et en arrivant au bout du courant
		float maigrir = smoothstep(0.0, 18.0, h) * (1.0 - smoothstep(0.62, 1.0, hn));
		float demi = epaisseur * (0.65 + 0.7 * h2) * maigrir * mix(0.55, 1.0, puissance);
		sd = max(sd, fuseau(le_long, p.x - axe, 0.0, l, demi, 0.45));
	}

	// ===================== LES VOLUTES =====================
	// elles montent avec le courant, grossissent, et s'enroulent vers l'extérieur
	for (int i = 0; i < 6; i++) {
		if (i >= nb_volutes) {
			break;
		}
		float fi = float(i);
		float hv = alea(fi * 17.3 + graine + 2.0);
		float phase = fract(defilement * 0.00042 + (fi + 0.37 * hv) / float(nb_volutes));
		float hc = mix(0.4, 0.9, phase) * portee;
		float sens = mod(fi, 2.0) < 1.0 ? 1.0 : -1.0;
		float wc = demi_l * (1.0 + evasement * pow(hc / max(portee, 1.0), 1.5));
		float xc = sens * wc * (0.45 + 0.2 * hv);
		float r0 = mix(22.0, 52.0, phase) * mix(0.6, 1.0, puissance);
		float demi = 3.4 * smoothstep(0.0, 0.15, phase) * (1.0 - phase * phase) * smoothstep(0.3, 0.8, puissance);
		sd = max(sd, volute(vec2(p.x - xc, h - hc), r0, sens, demi));
	}

	// ===================== LES ANNEAUX D'AIR =====================
	// au départ de la rafale : ils sortent de la bouche, montent, s'ouvrent
	for (int k = 0; k < 2; k++) {
		float fk = float(k);
		float t = (rafale - fk * 0.12) / 0.55;
		if (t <= 0.0 || t >= 1.0) {
			continue;
		}
		float pk = 1.0 - pow(1.0 - t, 3.0);          // il part vite, puis il freine
		float cy = mix(8.0, portee * 0.42, pk) * (1.0 - 0.25 * fk);
		float rx = demi_l * mix(0.55, 1.3, pk) * (1.0 - 0.2 * fk);
		float ry = rx * 0.22;                         // une ellipse plate : vue de profil
		float ki = rx / ry;
		// l'ellipse ramenée à un cercle de rayon rx ; `pente` garde le trait égal
		vec2 q = vec2(p.x, (h - cy) * ki);
		float d = length(q);
		float pente = length(vec2(q.x, q.y * ki)) / max(d, 0.0001);
		float angle = atan(q.y, q.x);
		float pinceau = 0.62 + 0.38 * sin(angle * 2.0 + fk * 1.7 + graine);
		float demi_r = 3.4 * anneaux * (1.0 - pow(t, 1.6)) * pinceau * (1.0 - 0.3 * fk);
		sd = max(sd, demi_r - abs(d - rx) / pente);
	}

	float a_filets = couleur.a * smoothstep(0.0, px, sd);
	float a_rubans = couleur.a * opacite_rubans * smoothstep(0.0, px, sd_r);
	COLOR = vec4(couleur.rgb, a_filets + a_rubans * (1.0 - a_filets));
}
