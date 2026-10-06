shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;
// CHUTE D'EAU (6 oct. 2026) — décor : une nappe d'eau qui tombe, dessinée à
// plat comme un dessin animé (d'après des images de référence). chute_eau.gd
// fabrique le rectangle et donne les réglages ; l'animation suit TIME, elle
// tourne donc aussi dans l'éditeur. Sans particules, sans lecture de l'écran.
// CE QUI RESTE EN PLACE :
//   • LA NAPPE : un voile translucide de la couleur de l'eau, qui éclaire un
//     peu ce qu'il y a derrière (`lueur`). Elle est faite de `nappes` pans
//     séparés par des COUTURES droites.
//   • LES LISERÉS : un trait clair et net le long des deux bords de la nappe et
//     de chaque couture.
//   • LA BRILLANCE : des bandes plus claires en travers de la nappe, par deux
//     (une fine, une épaisse dessous), penchées, décalées d'un pan à l'autre.
//     Elles ne descendent pas : seul leur tracé frémit sur place.
//   • LES ÉCLATS : des aiguilles claires pendues au sommet, dont la longueur
//     varie lentement.
// CE QUI TOMBE, VITE (`vitesse`) :
//   • LES TROUS : de très longues fentes en aiguille par où l'on voit le
//     décor (souvent plus longues que la chute), bordées d'un trait clair ;
//     une place tous les 21 px en travers de la nappe, plus les coutures, qui
//     s'ouvrent plus large ; et de courtes fentes plus rapides. `taille_trous`
//     les grossit toutes.
//   • LES PLIS : de larges coulées verticales un peu plus claires, et de fins
//     traits clairs en longues boucles (les lignes de niveau d'un bruit étiré
//     en hauteur), qui s'effilent et s'interrompent comme un coup de pinceau.
// AU PIED :
//   • L'ÉCUME : des LANGUES d'eau, fines et pointues comme des flammes, qui
//     jaillissent et retombent chacune à son rythme, penchées vers
//     l'extérieur ; un bourrelet bas qui les relie, des trous qui montent
//     dedans, des gouttes lancées en cloche, une flaque à sa base. Elle bouge
//     par à-coups (`cadence` images par seconde), comme un dessin image par
//     image.
// Le repère : x = 0 sur l'axe de la chute, y = 0 à son sommet, y vers le bas.
// Tout le hasard est tiré d'un ENTIER (un nœud de bruit rend la même valeur
// d'où qu'on le calcule : pas de marche au bord des cases). Ce qui tombe fait
// défiler la GRILLE du bruit d'un nombre entier de cases, à part de la
// coordonnée fine : la précision reste entière même quand TIME est grand.

// --- fournis par chute_eau.gd ---
// taille du rectangle et position de son coin dans le repère du nœud
uniform vec2 taille = vec2(520.0, 620.0);
uniform vec2 origine = vec2(-260.0, -2.0);
uniform float largeur = 140.0;
uniform float hauteur = 600.0;
uniform vec4 couleur : source_color = vec4(0.42, 0.72, 1.0, 1.0);
uniform vec4 couleur_ecume : source_color = vec4(0.88, 0.96, 1.0, 1.0);
// ce que la nappe cache du décor (0 → 1), et ce qu'elle lui ajoute de lumière
uniform float opacite = 0.5;
uniform float lueur = 0.5;
// vitesse de chute (px/s), nombre de pans, abondance des trous (0 → 1) et
// leur grosseur (1 = celle du dessin)
uniform float vitesse = 4000.0;
uniform int nappes = 3;
uniform float dechirure = 0.5;
uniform float taille_trous = 1.0;
// taille du dessin (bandes, plis, liserés) : 1 = d'après les images de référence
uniform float echelle = 1.0;
// un filet : de combien son axe ondule (px)
uniform float ondulation = 0.0;
// hauteur de l'écume au pied (px ; 0 : aucune) et ses images par seconde
uniform float ecume = 120.0;
uniform float cadence = 12.0;
// fondus du sommet et du pied (px ; 0 : coupe nette)
uniform float fondu_haut = 0.0;
uniform float fondu_bas = 0.0;
uniform float graine = 0.0;
// ------------------------------------

float alea_u(uint n) {
	n = (n << 13u) ^ n;
	n = n * (n * n * 15731u + 789221u) + 1376312589u;
	return float(n & 2147483647u) / 2147483647.0;
}

float alea(int a, int b) {
	return alea_u(uint(a + 65536) * 7919u + uint(b + 65536) * 104729u);
}

// bruit à une dimension : un hasard à chaque entier, raccordés en douceur ;
// `decal` fait défiler sa grille d'un nombre entier de cases
float bruit1(float x, int canal, int decal) {
	float fi = floor(x);
	float f = x - fi;
	int i = int(fi) + decal;
	float u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	return mix(alea(i, canal), alea(i + 1, canal), u);
}

vec2 gradient_e(int ix, int iy) {
	uint n = uint(ix + 65536) * 7919u + uint(iy + 65536) * 104729u;
	return vec2(alea_u(n), alea_u(n + 40503u)) * 2.0 - 1.0;
}

// bruit à gradients à deux dimensions, entre 0 et 1 environ ; `decal` fait
// défiler sa grille d'un nombre entier de cases vers le bas
float bruit2(vec2 p, int decal) {
	vec2 fl = floor(p);
	vec2 f = p - fl;
	int ix = int(fl.x);
	int iy = int(fl.y) + decal;
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = dot(gradient_e(ix, iy), f);
	float b = dot(gradient_e(ix + 1, iy), f - vec2(1.0, 0.0));
	float c = dot(gradient_e(ix, iy + 1), f - vec2(0.0, 1.0));
	float d = dot(gradient_e(ix + 1, iy + 1), f - vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 0.75 + 0.5;
}

// CE QUI TOMBE : à `y` px sous le sommet, à `v` px/s, mesuré en cases de `l`
// px. Rend la coordonnée fine (x) et le décalage entier de la grille (y).
vec2 qui_tombe(float y, float v, float l) {
	float s = v * TIME / l;
	float si = floor(s);
	return vec2(y / l - (s - si), -si);
}

// une couleur plus claire, sans perdre sa teinte : ce qui dépasse du blanc
// sur une composante est rendu aux deux autres
vec3 eclaircir(vec3 c, float k) {
	vec3 v = c * k;
	vec3 trop = max(v - vec3(1.0), vec3(0.0));
	return clamp(min(v, vec3(1.0)) + (trop.r + trop.g + trop.b) / 3.0, 0.0, 1.0);
}

void fragment() {
	vec2 pos = UV * taille + origine;
	float e = max(echelle, 0.05);
	float demi = largeur * 0.5;
	int gi = int(graine);
	float gf = graine * 0.731;
	vec3 c_eau = couleur.rgb;
	vec3 c_ecume = couleur_ecume.rgb;
	vec3 c_bande = mix(c_eau, c_ecume, 0.5);
	vec3 c_vif = mix(eclaircir(c_eau, 1.55), c_ecume, 0.25);       // liserés, éclats, traits

	// (un filet : son axe ondule et sa largeur respire, de plus en plus loin du sommet)
	float libre = smoothstep(0.0, 160.0 * e, pos.y);
	vec2 t_axe = qui_tombe(pos.y, 0.5 * vitesse, 150.0 * e);
	vec2 t_gros = qui_tombe(pos.y, 0.5 * vitesse, 85.0 * e);
	float axe = ondulation * (bruit1(t_axe.x + gf, 3, int(t_axe.y)) - 0.5) * 2.0 * libre;
	float demi_l = demi * (1.0 + 0.5 * (bruit1(t_gros.x + gf + 7.0, 4, int(t_gros.y)) - 0.5) * min(ondulation / max(demi, 1.0) * 3.0, 1.0) * libre);
	float x = pos.x - axe;
	float ax = abs(x);

	// ===== LES PLIS (ils tombent) =====
	// les traits fins : les lignes de niveau d'un bruit étiré en hauteur (de
	// longues boucles), à épaisseur constante à l'écran ; un second bruit les
	// effile et les interrompt
	vec2 t_plis = qui_tombe(pos.y, vitesse, 640.0 * e);
	float plis = bruit2(vec2(x / (40.0 * e) + gf, t_plis.x + gf * 1.7), int(t_plis.y)) * 5.0;
	float d_plis = abs(fract(plis) - 0.5) / clamp(fwidth(plis), 0.0002, 4.0);
	vec2 t_trace = qui_tombe(pos.y, vitesse, 900.0 * e);
	float trace = bruit2(vec2(x / (90.0 * e) + gf + 31.0, t_trace.x), int(t_trace.y));
	float ep_plis = 1.1 * e * smoothstep(0.42, 0.62, trace);
	float trait = smoothstep(ep_plis + 0.6, ep_plis - 0.6, d_plis) * smoothstep(0.0, 0.4 * e, ep_plis);
	// les coulées : de larges traînées verticales un peu plus claires
	vec2 t_coul = qui_tombe(pos.y, vitesse, 760.0 * e);
	float coulees = smoothstep(0.5, 0.78, bruit2(vec2(x / (13.0 * e) + gf * 2.3, t_coul.x + 5.0), int(t_coul.y)));

	// ===== LES COUTURES : leurs liserés, et les larges fentes qui y tombent =====
	int n = clamp(nappes, 1, 8);
	float larg_pan = largeur / float(n);
	int pan = 0;
	float fente = 0.0;
	float lisere = 0.0;
	float pres_du_bord = 0.0;        // le dégradé clair qui double chaque liseré
	// (un filet est trop étroit pour se trouer : il se couperait en deux)
	float a_des_trous = step(0.001, dechirure) * smoothstep(24.0, 48.0, largeur / e);
	float seuil = mix(0.78, 0.34, dechirure);
	float ouverture_max = a_des_trous * (3.0 * e + dechirure * dechirure * larg_pan * 1.1) * taille_trous;
	float ep_l = 1.25 * e;
	vec2 t_fente = qui_tombe(pos.y, 0.9 * vitesse, 1400.0 * e);
	vec2 t_ampl = qui_tombe(pos.y, 0.9 * vitesse, 2600.0 * e);
	for (int i = 1; i < 8; i++) {
		if (i >= n) {
			break;
		}
		float xi = (float(i) / float(n) + (alea(i, 11 + gi) - 0.5) * 0.5 / float(n)) * largeur - demi;
		if (x > xi) {
			pan = i;
		}
		float dx = abs(x - xi);
		// elle s'ouvre vite jusqu'à sa largeur du moment, puis ses bords restent
		// droits : une aiguille aux deux bouts pointus
		float ouvre = bruit1(t_fente.x + alea(i, 12 + gi) * 40.0, 20 + i + gi, int(t_fente.y));
		float ampleur = mix(0.35, 1.0, bruit1(t_ampl.x + alea(i, 23 + gi) * 40.0, 60 + i + gi, int(t_ampl.y)));
		float demi_fente = clamp((ouvre - seuil) / (1.0 - seuil) * 2.5, 0.0, 1.0) * ouverture_max * ampleur;
		fente = max(fente, smoothstep(0.6, -0.6, dx - demi_fente) * step(0.3, demi_fente));
		lisere = max(lisere, smoothstep(ep_l + 0.6, ep_l - 0.6, abs(dx - demi_fente)));
		pres_du_bord = max(pres_du_bord, 0.7 * exp(-max(dx - demi_fente, 0.0) / (6.0 * e)));
	}
	// le liseré des deux bords de la nappe
	lisere = max(lisere, smoothstep(ep_l + 0.6, ep_l - 0.6, abs(ax - (demi_l - ep_l))));
	pres_du_bord = max(pres_du_bord, exp(-max(demi_l - ax, 0.0) / (9.0 * e)));

	// ===== LES TROUS : de longues fentes, une place tous les 21 px =====
	// (chacune à sa vitesse ; son trait clair ne paraît qu'avec elle ; une fente
	// peut déborder sur la place voisine : on regarde les trois places autour)
	float pas_t = 21.0 * e;
	float jf0 = floor((x + demi) / pas_t);
	float seuil_trou = mix(0.85, 0.3, dechirure);
	float ep_t = 0.9 * e;
	for (int dj = -1; dj <= 1; dj++) {
		float jf = jf0 + float(dj);
		int j = int(jf);
		float xt = (jf + 0.28 + 0.44 * alea(j, 30 + gi)) * pas_t - demi;
		vec2 t_trou = qui_tombe(pos.y, vitesse * (0.85 + 0.4 * alea(j, 31 + gi)), 1100.0 * e);
		float ouvre_t = bruit1(t_trou.x + alea(j, 32 + gi) * 40.0, 80 + j * 3 + gi, int(t_trou.y));
		float demi_t = clamp((ouvre_t - seuil_trou) / (1.0 - seuil_trou) * 2.5, 0.0, 1.0) * mix(2.0, 6.8, alea(j, 33 + gi)) * e * taille_trous * a_des_trous;
		float dxt = abs(x - xt);
		fente = max(fente, smoothstep(0.6, -0.6, dxt - demi_t) * step(0.3, demi_t));
		lisere = max(lisere, smoothstep(ep_t + 0.6, ep_t - 0.6, abs(dxt - demi_t)) * smoothstep(0.2, 0.9, demi_t));
	}
	// de courtes fentes en plus, plus rapides que la nappe
	vec2 t_court = qui_tombe(pos.y, 1.2 * vitesse, 420.0 * e);
	vec2 cg = vec2(x / (26.0 * e) + gf, t_court.x);
	vec2 ig = floor(cg);
	int igx = int(ig.x);
	int igy = int(ig.y) + int(t_court.y);
	if (alea(igx, igy * 7 + 50 + gi) < 0.3 * dechirure * a_des_trous) {
		vec2 centre = vec2(0.3 + 0.4 * alea(igx + 9, igy + 51 + gi), 0.3 + 0.4 * alea(igx + 5, igy + 52 + gi));
		vec2 dg = (cg - ig - centre) * vec2(26.0, 420.0);          // px (à l'échelle 1)
		fente = max(fente, 1.0 - smoothstep(0.75, 1.15, length(dg / vec2(3.0 * min(taille_trous, 2.5), 110.0))));
	}

	// ===== LES ÉCLATS : des aiguilles claires pendues au sommet, une par pan =====
	float eclat = 0.0;
	for (int i = 0; i < 8; i++) {
		if (i >= n) {
			break;
		}
		float xe = ((float(i) + 0.2 + 0.6 * alea(i, 13 + gi)) / float(n)) * largeur - demi;
		// (sa longueur varie lentement ; souvent elle n'y est pas)
		float longueur_e = max(bruit1(TIME * 0.3 + alea(i, 14 + gi) * 40.0, 40 + i + gi, 0) - 0.45, 0.0) / 0.55 * 190.0 * e;
		float demi_e = 3.0 * e * pow(max(1.0 - pos.y / max(longueur_e, 1.0), 0.0), 0.8);
		eclat = max(eclat, smoothstep(0.6, -0.6, abs(x - xe) - demi_e) * step(0.3, demi_e));
	}

	// ===== LA BRILLANCE : des bandes plus claires, par deux, qui restent EN PLACE =====
	float s0 = pos.y + (alea(pan, 15 + gi) - 0.5) * 18.0 * e;        // décalées d'un pan à l'autre
	float periode = 330.0 * e;
	float kf = floor(s0 / periode);
	int k = int(kf);
	float pente = (alea(k, 17 + gi) - 0.5) * 0.7;
	// (leur tracé frémit sur place, lentement)
	float onde = (bruit2(vec2(x / (75.0 * e) + float(k) * 3.7, TIME * 0.35), 0) - 0.5) * 20.0 * e;
	float d = s0 - (kf + mix(0.35, 0.65, alea(k, 24 + gi))) * periode - pente * x - onde;      // px sous l'axe du groupe
	float ep1 = mix(7.0, 11.0, alea(k, 19 + gi)) * e;
	float ep2 = mix(18.0, 27.0, alea(k, 20 + gi)) * e;
	float bord_a = (bruit2(vec2(x / (34.0 * e) + float(k) * 1.3, TIME * 0.6 + 3.0), 0) - 0.5) * 9.0 * e;
	float bord_b = (bruit2(vec2(x / (41.0 * e) + float(k) * 2.1, TIME * 0.5 + 7.0), 0) - 0.5) * 11.0 * e;
	float bande = max(smoothstep(0.7, -0.7, abs(d + ep2 + 14.0 * e + ep1 + bord_a) - ep1),
			smoothstep(0.7, -0.7, abs(d - 6.0 * e + bord_b) - ep2)) * step(alea(k, 16 + gi), 0.85);

	// ===== LA NAPPE : ses tons, puis ce qu'elle cache et ce qu'elle ajoute =====
	float pied = (ecume > 0.5) ? smoothstep(hauteur - 1.3 * ecume, hauteur, pos.y) : 0.0;     // elle blanchit en arrivant
	vec3 c = c_eau * (0.9 + 0.3 * coulees);
	float al = min(opacite * (0.92 + 0.3 * coulees), 1.0);
	c = mix(c, c_bande, max(bande * 0.9, 0.45 * pres_du_bord));
	al = mix(al, min(al + 0.3, 1.0), bande);
	c = mix(c, c_vif, trait * 0.75);
	al = mix(al, min(al + 0.3, 1.0), trait * 0.75);
	c = mix(c, c_ecume, 0.3 * pied);
	al = mix(al, min(al + 0.2, 1.0), pied);
	c = mix(c, c_vif, eclat);
	al = mix(al, 0.95, eclat);
	c = mix(c, c_vif, lisere);
	al = mix(al, 0.97, lisere);
	float dans = smoothstep(demi_l + 0.7, demi_l - 0.7, ax) * smoothstep(-0.7, 0.7, pos.y) * smoothstep(hauteur + 0.7, hauteur - 0.7, pos.y);
	if (fondu_haut > 0.5) {
		dans *= smoothstep(0.0, fondu_haut, pos.y);
	}
	if (fondu_bas > 0.5) {
		dans *= smoothstep(hauteur, hauteur - fondu_bas, pos.y);
	}
	float presence = dans * (1.0 - fente * (1.0 - lisere));
	vec3 rgb = c * (al + (1.0 - al) * lueur) * presence;       // prémultiplié
	float a = al * presence;

	// ===== L'ÉCUME AU PIED =====
	if (ecume > 0.5) {
		float h = hauteur - pos.y;                 // hauteur au-dessus du pied (px)
		float large = 0.55 * ecume + 0.12 * largeur;
		float axp = abs(pos.x);
		if (h > -(0.1 * ecume + 6.0) && h < 2.7 * ecume && axp < demi + 2.6 * large) {
			float ts = (cadence > 0.5) ? floor(TIME * cadence) / cadence : TIME;
			float dehors = max(axp - demi, 0.0);
			float cf = 0.0;
			// tout son tracé ONDULE, de plus en plus avec la hauteur, et l'onde monte :
			// des contours de flamme, qui bouillent d'une image à l'autre
			float ondule = (bruit2(vec2(pos.x / (0.22 * ecume) + gf, h / (0.26 * ecume) - ts * 3.0), 0) - 0.5) * 2.0;
			float px = pos.x + ondule * 0.075 * ecume * smoothstep(0.0, 0.35 * ecume, h);
			// SES LANGUES : des flammes d'eau qui jaillissent et retombent, chacune à
			// son rythme ; à chaque jaillissement une langue change de place, de
			// taille et de pente
			float etendue = demi + 0.9 * large;
			int nb = int(clamp(floor(2.0 * etendue / (0.2 * ecume) + 0.5), 5.0, 16.0));
			for (int q = 0; q < 16; q++) {
				if (q >= nb) {
					break;
				}
				float duree_q = 0.5 + 0.45 * alea(q, 70 + gi);
				float tour = ts / duree_q + alea(q, 71 + gi);
				int cycle = int(floor(tour));
				float age = tour - floor(tour);
				float r1 = alea(q * 16 + cycle, 72 + gi);
				float r2 = alea(q * 16 + cycle, 73 + gi);
				float r3 = alea(q * 16 + cycle, 74 + gi);
				float xq = ((float(q) + 0.15 + 0.7 * r1) / float(nb) * 2.0 - 1.0) * etendue;
				// haute là où tombe la nappe, plus encore à ses deux bords, basse au loin
				float axq = abs(xq);
				float env = exp(-pow(max(axq - demi, 0.0) / large, 1.5)) * mix(0.7, 1.0, smoothstep(demi * 0.2, demi, axq))
						+ 0.4 * exp(-pow((axq - demi) / (0.3 * ecume), 2.0));
				// elle monte vite et retombe plus lentement
				float haut_q = ecume * env * mix(0.45, 1.25, r2) * sin(PI * pow(age, 0.6));
				if (haut_q < 2.0 || h > haut_q || h < 0.0) {
					continue;
				}
				float u = h / haut_q;                  // 0 à sa racine, 1 à sa pointe
				float penche = (xq / etendue) * 0.45 + (r3 - 0.5) * 0.3;
				float xc = xq + penche * h + sin(u * 4.0 + r3 * 6.2832) * 0.06 * ecume * u;
				// (large à sa racine, renflée par endroits, effilée jusqu'à sa pointe)
				float w = ecume * mix(0.07, 0.2, r3 * r3) * pow(1.0 - u, 0.7) * (0.8 + 0.3 * sin(u * 8.0 + r1 * 6.2832));
				cf = max(cf, smoothstep(-0.7, 0.7, w - abs(px - xc)));
			}
			// le bourrelet bas qui les relie, et sa flaque en lentille dessous
			float bosse = ecume * (0.14 + 0.22 * bruit2(vec2(px / (0.3 * ecume) + gf, ts * 2.4), 0)) * exp(-pow(dehors / (0.7 * large), 2.0));
			cf = max(cf, smoothstep(-0.7, 0.7, bosse - h));
			float demi_flaque = demi + 1.3 * large;
			float creux = (0.03 * ecume + 2.0) * sqrt(max(1.0 - (axp / demi_flaque) * (axp / demi_flaque), 0.0));
			cf *= smoothstep(-0.7, 0.7, h + creux);
			// ses trous : des bulles ovales qui montent, plus nombreuses vers le haut
			float rel = clamp(h / (1.1 * ecume), 0.0, 1.0);
			float trou = bruit2(vec2(pos.x / (0.2 * ecume) + gf * 1.3, (h - 1.3 * ecume * ts) / (0.36 * ecume)), 0);
			float seuil_e = mix(0.68, 0.55, rel) + (1.0 - smoothstep(0.1 * ecume, 0.22 * ecume, h));
			cf *= 1.0 - smoothstep(-0.5, 0.5, (trou - seuil_e) / clamp(fwidth(trou), 0.0005, 0.2));
			// ses gouttes : lancées en cloche vers l'extérieur, étirées par leur course
			for (int q = 0; q < 14; q++) {
				float duree_q = 0.9 + 0.5 * alea(q, 60 + gi);
				float tour = ts / duree_q + alea(q, 61 + gi);
				int cycle = int(floor(tour));
				float age = (tour - floor(tour)) * duree_q;
				float r1 = alea(q * 16 + cycle, 62 + gi);
				float r2 = alea(q * 16 + cycle, 63 + gi);
				float r3 = alea(q * 16 + cycle, 64 + gi);
				float sens = (r3 < 0.5) ? -1.0 : 1.0;
				vec2 v0 = vec2(sens * ecume * mix(0.25, 1.0, r1), ecume * mix(2.6, 4.6, r2));       // px/s, y vers le haut
				float grav = 9.0 * ecume;
				vec2 p = vec2(sens * demi * (0.2 + fract(r3 * 7.3)) + v0.x * age, 0.15 * ecume + v0.y * age - 0.5 * grav * age * age);
				if (p.y < 0.0) {
					continue;
				}
				vec2 sa = normalize(vec2(v0.x, v0.y - grav * age));
				vec2 dq = vec2(pos.x - p.x, h - p.y);
				float rayon = (1.4 + 2.0 * r3) * ecume / 110.0 * (1.0 - 0.5 * age / duree_q);
				cf = max(cf, smoothstep(0.8, -0.8, length(vec2(dot(dq, sa) / 2.2, dot(dq, vec2(-sa.y, sa.x)))) - rayon));
			}
			cf *= 0.93;
			rgb = rgb * (1.0 - cf) + c_ecume * cf;
			a = a * (1.0 - cf) + cf;
		}
	}
	COLOR = vec4(rgb, a);
}
