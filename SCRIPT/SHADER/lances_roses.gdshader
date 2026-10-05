shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;
// LANCES ROSES (5 oct. 2026) — attaque de boss : à son claquement de doigts,
// des lances de lumière sortent du sol dans toute une zone, EN RYTHME. La zone
// est découpée en emplacements réguliers ; à chaque vague une partie d'entre
// eux, tirée au hasard, pousse une lance. On se place là où il n'y en a pas.
// lances_roses.gd tire les vagues et donne l'heure ; tout se dessine ici, dans
// le style de la pluie de pétales (pluie_petales.gdshader), sans particules.
//   • L'ANNONCE : chaque emplacement visé s'allume — une étoile au sol, un
//     trait de lumière large comme l'emplacement, et le FANTÔME de la lance,
//     sa silhouette en lueur avec un filet au milieu, là où elle va sortir.
//     Les emplacements libres restent sombres. Juste avant la sortie, le
//     fantôme s'avive.
//   • LA SORTIE : la lance jaillit d'un trait, dépasse un peu et se pose — une
//     longue lame en feuille plantée dans le sol, ventrue à hauteur d'homme
//     et effilée jusqu'à sa pointe (le pétale de la pluie, étiré et dressé) :
//     cœur presque blanc, corps rose strié, liseré plus sombre, une arête rose
//     au milieu, et un halo ajouté à ce qu'il y a derrière (mode prémultiplié).
//     Deux petits pétales s'ouvrent à son pied, un éclair court le long du sol
//     et des paillettes montent autour d'elle. (`part_fer` plus petit : le
//     fer ne prend que le haut, au bout d'une hampe.)
//   • LE RETRAIT : elle rentre dans le sol.
// Deux vagues peuvent se voir à la fois : celle dont les lances sont sorties,
// et la suivante qui s'annonce déjà.
// Tout le hasard est tiré d'un ENTIER.

// --- fournis par lances_roses.gd ---
// taille du rectangle et position de son coin dans le repère du nœud : tout est
// calculé dans ce repère
uniform vec2 taille = vec2(1880.0, 700.0);
uniform vec2 origine = vec2(-940.0, -100.0);
// les emplacements : leur nombre, l'abscisse du premier, leur écart, et la
// hauteur du sol sous chacun (au-delà de `chute` : pas de sol, pas de lance)
uniform int nb_cases = 0;
uniform float base_x = -750.0;
uniform float pas = 100.0;
uniform float sols[32];
uniform float chute = 1600.0;
// les deux vagues visibles : pour chacune, quels emplacements sont visés
// (1 ou 0), l'heure depuis son annonce (s ; négative : pas de vague), sa graine
uniform float motif_a[32];
uniform float temps_a = -1.0;
uniform float graine_a = 0.0;
uniform float motif_b[32];
uniform float temps_b = -1.0;
uniform float graine_b = 0.0;
// la vie d'une vague (s) : l'annonce, la sortie, le temps où elles restent
// sorties, le retrait ; et la hauteur des lances (px)
uniform float annonce = 0.7;
uniform float sortie = 0.08;
uniform float tenue = 0.3;
uniform float retrait = 0.16;
uniform float hauteur = 460.0;
// ------------------------------------

// --- l'allure ---
// le fer : sa demi-largeur (px), et la part de la lance qu'il occupe (1 = une
// lame entière plantée dans le sol ; 0,4 = un fer au bout d'une hampe) ; la
// demi-largeur de la hampe (px)
uniform float largeur_fer : hint_range(6.0, 40.0) = 22.0;
uniform float part_fer : hint_range(0.25, 1.0) = 1.0;
uniform float hampe : hint_range(1.0, 12.0) = 4.5;
// force du halo, et éclat des paillettes
uniform float halo : hint_range(0.0, 1.5) = 0.6;
uniform float paillettes : hint_range(0.0, 2.0) = 1.0;
uniform vec4 couleur_coeur : source_color = vec4(1.0, 0.94, 0.99, 1.0);
uniform vec4 couleur_corps : source_color = vec4(0.98, 0.68, 0.87, 1.0);
uniform vec4 couleur_lisere : source_color = vec4(0.9, 0.32, 0.64, 1.0);
uniform vec4 couleur_halo : source_color = vec4(0.95, 0.3, 0.62, 1.0);

float alea_u(uint n) {
	n = (n << 13u) ^ n;
	n = n * (n * n * 15731u + 789221u) + 1376312589u;
	return float(n & 2147483647u) / 2147483647.0;
}

// le hasard d'une lance : son emplacement, sa vague, le numéro du tirage
float alea(int emplacement, int vague, int tirage) {
	uint n = uint(emplacement + 64) * 7919u + uint(vague + 1048576) * 104729u + uint(tirage) * 15485863u;
	return alea_u(n);
}

// UNE PAILLETTE : une croix à quatre branches fines et un point au milieu
float paillette(vec2 p, float r) {
	vec2 a = abs(p);
	float croix = max(exp(-a.x / (r * 0.16) - a.y / (r * 0.7)), exp(-a.y / (r * 0.16) - a.x / (r * 0.7)));
	return max(croix * 0.85, exp(-dot(p, p) / (r * r * 0.16)));
}

// UN PÉTALE (celui de la pluie) : une larme effilée en haut, ventrue en bas.
// `q` est le point dans son repère (y vers le bas), `h` sa demi-hauteur, `l`
// sa demi-largeur. Rend (profondeur à l'intérieur, distance à l'extérieur).
vec2 petale(vec2 q, float h, float l) {
	float s = clamp((q.y + h) / (2.0 * h), 0.0, 1.0);
	float w = l * sin(PI * pow(s, 1.6));
	float cote = abs(q.x) - w;
	float bout = max(abs(q.y) - h, 0.0);
	float dehors = length(vec2(max(cote, 0.0), bout));
	return vec2((bout > 0.0) ? -dehors : -cote, dehors);
}

// LE PROFIL D'UNE LANCE haute de `l_tot` px : sa demi-largeur à `haut` px du
// sol (x), et où l'on est le long de son fer (y : 0 à son bas, 1 à sa pointe)
vec2 profil(float haut, float l_tot) {
	float fer = l_tot * part_fer;
	float u = (haut - (l_tot - fer)) / max(fer, 1.0);
	float w_fer = largeur_fer * sin(PI * pow(clamp(u, 0.0, 1.0), 0.6));
	// (la hampe, ou le pied de la lame : jamais pincée au ras du sol)
	float w_hampe = mix(hampe * 1.7, hampe, clamp(haut / max(l_tot * 0.5, 1.0), 0.0, 1.0))
			* (1.0 - smoothstep(0.05, 0.32, u));
	return vec2(max(w_fer, w_hampe), u);
}

// UNE LANCE d'une vague : son annonce, puis elle-même. `cx` est l'abscisse de
// son emplacement, `sol` la hauteur du sol sous elle, `tau` l'heure depuis
// l'annonce de sa vague.
void lance(vec2 pos, float cx, float sol, float tau, int i, int g, inout vec3 rgb, inout float a, inout vec3 lueur) {
	float dx = pos.x - cx;
	float haut = sol - pos.y;                  // px au-dessus du sol
	float t_ret = annonce + sortie + tenue;
	float vie = t_ret + retrait;
	if (tau < 0.0 || tau > vie + 0.4 || abs(dx) > pas * 1.25 + 30.0) {
		return;
	}
	float r1 = alea(i, g, 1);
	float r2 = alea(i, g, 2);
	vec3 clair = mix(couleur_halo.rgb, couleur_coeur.rgb, 0.7);

	// --- L'ANNONCE : l'emplacement s'allume, de plus en plus ---
	if (tau < annonce + 0.05) {
		float croit = clamp(tau / max(annonce, 0.01), 0.0, 1.0);
		float presse = smoothstep(annonce - 0.14, annonce, tau);       // juste avant de sortir
		float fondu = smoothstep(0.0, 0.08, tau) * (1.0 - smoothstep(annonce, annonce + 0.05, tau));
		float bat = 0.78 + 0.22 * sin(tau * 24.0 + r1 * 6.2832);
		float e = paillette(vec2(dx, 5.0 - haut), mix(9.0, 21.0, croit) * bat);
		float trait = exp(-(dx * dx) / (pas * pas * 0.14) - (haut * haut) / (2.8 * 2.8));
		float nappe = exp(-(dx * dx) / (pas * pas * 0.18) - (haut * haut) / (10.0 * 10.0));
		// le fantôme : la silhouette de la lance à venir, et un filet en son milieu
		float l_fant = hauteur * mix(0.86, 1.0, r2);
		float fantome = 0.0;
		float filet = 0.0;
		if (haut > 0.0 && haut < l_fant + 20.0 && abs(dx) < largeur_fer + 20.0) {
			float w = profil(min(haut, l_fant), l_fant).x;
			float monte = 1.0 - smoothstep(l_fant * mix(0.25, 1.0, croit), l_fant * mix(0.45, 1.05, croit), haut);
			fantome = (1.0 - smoothstep(-2.0, 3.0, abs(dx) - w)) * monte * smoothstep(0.0, 12.0, haut);
			filet = exp(-(dx * dx) / (5.0 * 5.0)) * monte * smoothstep(0.0, 30.0, haut);
		}
		lueur += clair * (e + trait * mix(0.55, 1.0, croit) * bat) * fondu
				+ couleur_halo.rgb * (nappe * 0.4 + fantome * mix(0.12, 0.34, croit) * (1.0 + 0.9 * presse)
				+ filet * mix(0.15, 0.3, croit) * (1.0 + 1.6 * presse)) * fondu;
	}

	if (tau < annonce) {
		return;
	}
	// --- LA LANCE : elle jaillit, dépasse un peu, se pose ; puis elle rentre ---
	float am = clamp((tau - annonce) / max(sortie, 0.01), 0.0, 1.0);
	float pousse = 1.0 + 2.2 * pow(am - 1.0, 3.0) + 1.2 * pow(am - 1.0, 2.0);
	float rr = clamp((tau - t_ret) / max(retrait, 0.01), 0.0, 1.0);
	float sortie_l = pousse * (1.0 - rr * rr);
	float l_tot = hauteur * mix(0.86, 1.0, r2) * sortie_l;
	float eclat = exp(-(tau - annonce) / 0.12);                      // l'éclair de la sortie
	float presente = step(tau, vie);
	if (presente > 0.5 && l_tot > 2.0 && haut > -3.0 && haut < l_tot + 60.0 && abs(dx) < largeur_fer + 60.0) {
		vec2 pr = profil(haut, l_tot);
		float w = pr.x;
		float u = pr.y;                                                // 0 au bas du fer, 1 à sa pointe
		float dedans = w - abs(dx);
		float dehors = (haut > l_tot) ? length(vec2(dx, haut - l_tot)) : max(-dedans, 0.0);
		float hors_sol = smoothstep(-2.0, 2.0, haut);                  // rien sous le sol
		float couv = smoothstep(-0.8, 1.2, (haut > l_tot) ? -dehors : dedans) * hors_sol;
		float m = clamp(dedans / max(w * 0.7, 1.0), 0.0, 1.0);
		vec3 c = mix(couleur_lisere.rgb, couleur_corps.rgb, smoothstep(0.0, 0.3, m));
		c = mix(c, couleur_coeur.rgb, smoothstep(0.25, 0.7, m));
		// ses stries : des coups de pinceau roses dans le cœur clair, en éventail
		// depuis la pointe, comme sur les pétales ; et l'arête du fer au milieu
		float eventail = dx / max(l_tot * 1.12 - haut, 1.0);
		float strie = smoothstep(0.62, 0.95, 0.5 + 0.5 * cos(eventail * 62.0 + (r1 - 0.5) * 5.0));
		c = mix(c, couleur_corps.rgb, 0.55 * strie * smoothstep(0.2, 0.6, m) * smoothstep(0.0, 0.15, u));
		float arete = (1.0 - smoothstep(0.0, 2.4, abs(dx))) * smoothstep(0.03, 0.2, u) * (1.0 - smoothstep(0.82, 1.0, u));
		c = mix(c, couleur_corps.rgb, 0.6 * arete);
		rgb = rgb * (1.0 - couv) + c * couv;
		a = a * (1.0 - couv) + couv;
		lueur += couleur_halo.rgb * exp(-dehors / 13.0) * halo * (1.0 + 1.6 * eclat) * hors_sol * (1.0 - couv);
	}
	// à son pied, deux petits pétales s'ouvrent quand elle sort et se referment
	// quand elle rentre
	if (presente > 0.5 && haut > -3.0 && haut < 80.0 && abs(dx) < 80.0) {
		float ouvre = pousse * (1.0 - rr);
		for (int cote = -1; cote <= 1; cote += 2) {
			float fc = float(cote);
			float hp = mix(20.0, 27.0, alea(i, g, 6 + cote)) * ouvre;
			if (hp < 2.0) {
				continue;
			}
			// (penché vers l'extérieur, sa pointe du bas dans le sol au pied de la lance)
			float angle = fc * 0.62;
			vec2 d = vec2(dx - fc * (7.0 + hp * 0.55), -haut + hp * 0.78);
			vec2 q = vec2(cos(angle) * d.x + sin(angle) * d.y, -sin(angle) * d.x + cos(angle) * d.y);
			q.y = -q.y;                                                // pointe en haut, ventre en bas
			vec2 pp = petale(q, hp, hp * 0.44);
			float hors_sol = smoothstep(-2.0, 2.0, haut);
			float couv = smoothstep(-0.8, 1.2, pp.x) * hors_sol;
			float m = clamp(pp.x / (hp * 0.26), 0.0, 1.0);
			vec3 c = mix(couleur_lisere.rgb, couleur_corps.rgb, smoothstep(0.0, 0.3, m));
			c = mix(c, couleur_coeur.rgb, smoothstep(0.3, 0.85, m));
			rgb = rgb * (1.0 - couv) + c * couv;
			a = a * (1.0 - couv) + couv;
			lueur += couleur_halo.rgb * exp(-pp.y / 11.0) * halo * hors_sol * (1.0 - couv);
		}
	}
	if (presente > 0.5) {
		// au pied : l'éclair de la sortie le long du sol, puis une lueur tant qu'elle est là
		float trait = exp(-(dx * dx) / (pas * pas * 0.2) - (haut * haut) / (3.0 * 3.0));
		float nappe = exp(-(dx * dx) / (pas * pas * 0.22) - (haut * haut) / (11.0 * 11.0));
		lueur += (couleur_coeur.rgb * trait * (0.5 + 1.3 * eclat) + couleur_halo.rgb * nappe * (0.35 + 0.9 * eclat)) * (1.0 - rr);
	}
	// des paillettes montent autour d'elle, de sa sortie à son retrait
	float depuis = tau - annonce;
	float vp = 430.0;
	float pp = 46.0;
	int j0 = int(floor((haut - vp * depuis) / pp));
	for (int dj = -1; dj <= 1; dj++) {
		int j = j0 + dj;
		float p1 = alea(i * 37 + j, g, 11);
		float p2 = alea(i * 37 + j, g, 12);
		float yj = (float(j) + 0.5 + (p2 - 0.5) * 0.8) * pp;
		// partie du sol après la sortie, avant le retrait
		if (yj > 0.0 || yj < -vp * (sortie + tenue)) {
			continue;
		}
		float h_p = yj + vp * depuis;
		vec2 centre = vec2((p1 - 0.5) * 64.0 + 5.0 * sin(depuis * 9.0 + p2 * 6.2832), h_p);
		float clin = 0.55 + 0.45 * sin(depuis * (9.0 + 7.0 * p1) + p2 * 6.2832);
		float fane = 1.0 - smoothstep(hauteur * 0.45, hauteur * 0.95, h_p);
		float e = paillette(vec2(dx - centre.x, h_p - haut), mix(3.5, 8.0, p2 * p2)) * clin * fane * smoothstep(0.0, 14.0, h_p);
		lueur += mix(couleur_halo.rgb, couleur_coeur.rgb, 0.35 + 0.5 * e) * e * paillettes;
	}
}

void fragment() {
	vec2 pos = UV * taille + origine;
	vec3 rgb = vec3(0.0);       // ce qui couvre (déjà multiplié par sa couverture)
	float a = 0.0;
	vec3 lueur = vec3(0.0);     // ce qui s'ajoute
	if (nb_cases > 0) {
		int i0 = int(floor((pos.x - base_x) / pas + 0.5));
		for (int di = -1; di <= 1; di++) {
			int i = i0 + di;
			if (i < 0 || i >= nb_cases) {
				continue;
			}
			float sol = sols[i];
			if (sol > chute) {
				continue;
			}
			float cx = base_x + float(i) * pas;
			if (temps_a >= 0.0 && motif_a[i] > 0.5) {
				lance(pos, cx, sol, temps_a, i, int(graine_a), rgb, a, lueur);
			}
			if (temps_b >= 0.0 && motif_b[i] > 0.5) {
				lance(pos, cx, sol, temps_b, i, int(graine_b), rgb, a, lueur);
			}
		}
	}
	// jamais coupée net par le bord du rectangle
	float bord = smoothstep(0.0, 30.0, min(pos.x - origine.x, origine.x + taille.x - pos.x));
	COLOR = vec4((rgb + lueur * (1.0 - a)) * bord, a * bord);
}
