shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;
// GRIFFES ROSES (5 oct. 2026) — attaque de boss : elle lève la main, de
// grandes griffes de lumière s'y forment, puis elle les LANCE en slash : trois
// CROISSANTS emboîtés, un par griffe, filent en DIAGONALE jusqu'au premier mur
// ou au sol. On sort de la diagonale avant qu'ils partent. griffes_roses.gd
// choisit la diagonale et donne l'heure ; tout se dessine ici, dans le style
// de la pluie de pétales et des lances (cœur presque blanc, corps rose, liseré
// plus sombre, halo ajouté à ce qu'il y a derrière : mode prémultiplié), sans
// particules.
//   • LA CHARGE : trois griffes poussent à la main, dressées et recourbées
//     vers la cible (`griffes_main` à 0 : l'animation du boss les montre
//     déjà) ; le PASSAGE s'annonce — un voile de lueur large comme les
//     croissants, bordé de deux filets, qui descend de la main jusqu'à la
//     surface visée, où un trait s'allume. Juste avant le lancer, tout s'avive.
//   • LE LANCER : un éclair à la main, et le slash part — trois croissants de
//     même centre, le plus grand devant, bord d'attaque vers l'avant, pointes
//     en arrière, épais au milieu et effilés aux pointes. Il grandit en
//     quittant la main ; chaque pointe tire un filet de lueur derrière elle,
//     et des paillettes se détachent de son passage.
//   • L'IMPACT : il s'enfonce dans la surface (rien ne se dessine derrière
//     elle), un éclat part du point touché, un trait de lumière court le long
//     de la surface et des paillettes rejaillissent.
// Le repère : la main est à l'origine du nœud ; `u` court le long de la
// diagonale, `v` en travers. Tout le hasard est tiré d'un ENTIER.

// --- fournis par griffes_roses.gd (à chaque image : les valeurs enregistrées
// dans une scène ne comptent pas) ---
// taille du rectangle et position de son coin dans le repère du nœud
uniform vec2 taille = vec2(1500.0, 1300.0);
uniform vec2 origine = vec2(-300.0, -300.0);
// la diagonale (vecteur unité, y vers le bas), sa longueur de la main à la
// surface touchée (px), la normale de cette surface, le côté visé (-1 / 1)
uniform vec2 dir = vec2(0.7071, 0.7071);
uniform float longueur = 900.0;
uniform vec2 normale = vec2(0.0, -1.0);
uniform float cote = 1.0;
// l'heure depuis le début (s), la durée de la charge, la vitesse du slash (px/s)
uniform float temps = 0.0;
uniform float charge = 0.8;
uniform float vitesse = 3000.0;
uniform float graine = 0.0;
// 1 : les griffes sont dessinées à la main pendant la charge
uniform float griffes_main = 1.0;
// le slash : rayon du plus grand croissant (px), demi-ouverture (rad),
// demi-épaisseur au milieu (px), écart entre deux croissants (px)
uniform float rayon = 170.0;
uniform float ouverture = 0.9;
uniform float epaisseur = 20.0;
uniform float ecart = 46.0;
// les griffes à la main : leur longueur et leur demi-épaisseur (px)
uniform float taille_main = 340.0;
uniform float epaisseur_main = 22.0;
// ------------------------------------

// --- l'allure ---
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

float alea(int a, int b, int tirage) {
	uint n = uint(a + 4096) * 7919u + uint(b + 1048576) * 104729u + uint(tirage) * 15485863u;
	return alea_u(n);
}

// UNE PAILLETTE : une croix à quatre branches fines et un point au milieu
float paillette(vec2 p, float r) {
	vec2 a = abs(p);
	float croix = max(exp(-a.x / (r * 0.16) - a.y / (r * 0.7)), exp(-a.y / (r * 0.16) - a.x / (r * 0.7)));
	return max(croix * 0.85, exp(-dot(p, p) / (r * r * 0.16)));
}

// la teinte d'une lame, du bord (0) au cœur (1)
vec3 teinte(float m) {
	vec3 c = mix(couleur_lisere.rgb, couleur_corps.rgb, smoothstep(0.0, 0.3, m));
	return mix(c, couleur_coeur.rgb, smoothstep(0.25, 0.7, m));
}

void fragment() {
	vec2 pos = UV * taille + origine;          // la main est en (0, 0)
	vec2 travers = vec2(-dir.y, dir.x);
	float u = dot(pos, dir);
	float v = dot(pos, travers);
	float tau = temps - charge;                // l'heure depuis le lancer
	int g = int(graine);
	vec3 rgb = vec3(0.0);       // ce qui couvre (déjà multiplié par sa couverture)
	float a = 0.0;
	vec3 lueur = vec3(0.0);     // ce qui s'ajoute
	vec3 clair = mix(couleur_halo.rgb, couleur_coeur.rgb, 0.7);
	vec2 bout = dir * longueur;                // le point touché
	// devant la surface touchée : rien ne se dessine derrière elle
	float devant = smoothstep(-3.0, 3.0, dot(pos - bout, normale));
	vec2 le_long_surface = vec2(-normale.y, normale.x);
	float demi_bande = rayon * sin(ouverture);  // la demi-largeur de ce qui passe

	// ===== LA CHARGE =====
	if (tau < 0.12) {
		float croit = clamp(temps / max(charge, 0.01), 0.0, 1.0);
		float presse = smoothstep(charge - 0.14, charge, temps);
		float fondu = smoothstep(0.0, 0.1, temps) * (1.0 - smoothstep(0.0, 0.1, tau));
		// le passage annoncé : un voile large comme les croissants, bordé de deux
		// filets, qui descend de la main
		if (u > 0.0 && abs(v) < demi_bande + 30.0) {
			float porte = longueur + demi_bande * 1.2;
			float descend = smoothstep(0.0, 80.0, u)
					* (1.0 - smoothstep(porte * mix(0.2, 1.0, croit), porte * mix(0.4, 1.03, croit), u));
			// (étroit à la main, il s'ouvre comme le slash grandira)
			float large = demi_bande * mix(0.3, 1.0, smoothstep(0.0, rayon * 1.2, u));
			float voile = 1.0 - smoothstep(large - 14.0, large + 6.0, abs(v));
			float bords = exp(-(abs(v) - large) * (abs(v) - large) / (4.0 * 4.0));
			lueur += couleur_halo.rgb * (voile * mix(0.02, 0.06, croit) * (1.0 + 0.8 * presse)
					+ bords * mix(0.1, 0.26, croit) * (1.0 + 1.5 * presse)) * descend * fondu * devant;
		}
		// sur la surface visée : un trait de lumière là où il va frapper
		vec2 ds = pos - bout;
		float trait = exp(-pow(dot(ds, normale) / 2.8, 2.0)) * exp(-pow(dot(ds, le_long_surface) / (demi_bande * 1.1), 2.0));
		float e = paillette(ds, mix(10.0, 24.0, croit) * (0.8 + 0.2 * sin(temps * 22.0)));
		lueur += clair * (e + trait * mix(0.3, 0.8, croit)) * croit * fondu;

		// les griffes à la main : dressées, en éventail, recourbées vers la cible
		if (griffes_main > 0.5 && length(pos) < taille_main * 1.3 + 70.0) {
			float am = clamp(temps / max(charge * 0.75, 0.01), 0.0, 1.0);
			float pousse = 1.0 + 2.2 * pow(am - 1.0, 3.0) + 1.2 * pow(am - 1.0, 2.0);
			vec2 base = normalize(vec2(-cote * 0.38, -1.0));       // vers le haut, penchées en arrière
			vec2 base_n = vec2(-base.y, base.x);
			for (int k = -1; k <= 1; k++) {
				float fk = float(k);
				float ang = fk * 0.33;
				vec2 axe = vec2(cos(ang) * base.x - sin(ang) * base.y, sin(ang) * base.x + cos(ang) * base.y);
				vec2 axe_n = vec2(-axe.y, axe.x);
				float lg = taille_main * ((k == 0) ? 1.0 : 0.82) * pousse;
				if (lg < 4.0) {
					continue;
				}
				vec2 d = pos - base_n * (fk * 17.0);
				float le_long = dot(d, axe);
				float s = le_long / lg;
				// (le crochet : la pointe part du côté de la cible)
				float en_travers = dot(d, axe_n) - cote * 0.26 * lg * clamp(s, 0.0, 1.0) * clamp(s, 0.0, 1.0);
				float ep = epaisseur_main * ((k == 0) ? 1.0 : 0.84) * min(pousse, 1.0);
				float w = max(ep * sin(PI * pow(clamp(s, 0.0, 1.0), 0.6)), 5.0 * (1.0 - clamp(s, 0.0, 1.0)));
				float dedans = w - abs(en_travers);
				float dehors = (s > 1.0) ? length(vec2(le_long - lg, en_travers))
						: ((s < 0.0) ? length(vec2(le_long, en_travers)) : max(-dedans, 0.0));
				float couv = smoothstep(-0.8, 1.2, (s < 0.0 || s > 1.0) ? -dehors : dedans) * fondu;
				vec3 c = teinte(clamp(dedans / max(w * 0.7, 1.0), 0.0, 1.0));
				rgb = rgb * (1.0 - couv) + c * couv;
				a = a * (1.0 - couv) + couv;
				lueur += couleur_halo.rgb * exp(-dehors / 13.0) * halo * (1.0 + 1.4 * presse) * fondu * (1.0 - couv);
			}
			// la lueur de la main
			lueur += couleur_halo.rgb * exp(-dot(pos, pos) / (60.0 * 60.0)) * 0.55 * croit * fondu;
		}
	}

	// ===== LE LANCER =====
	if (tau >= 0.0) {
		float tete = vitesse * tau;                // le chemin fait par le bord d'attaque
		float t_impact = longueur / max(vitesse, 1.0);
		// l'éclair du départ, à la main
		lueur += clair * exp(-dot(pos, pos) / (80.0 * 80.0)) * exp(-tau / 0.1) * 1.2;

		// LE SLASH : trois croissants de même centre, le plus grand devant
		float nait = smoothstep(0.0, 0.09, tau);       // il grandit en quittant la main
		float ech = mix(0.3, 1.0, nait);
		float r0 = rayon * ech;
		if (abs(v) < demi_bande + 70.0) {
			// le centre des croissants est derrière leur bord d'attaque
			vec2 rel = vec2(u - (tete - r0), v);
			float dist = length(rel);
			float ang = atan(rel.y, rel.x);                // 0 : droit devant
			// épais au milieu, effilé aux deux pointes
			float na = ang / max(ouverture, 0.01);
			float profil = pow(max(1.0 - na * na, 0.0), 0.75);
			for (int k = 0; k < 3; k++) {
				float rk = r0 - float(k) * ecart * ech;
				float ep = epaisseur * ech * ((k == 0) ? 1.0 : ((k == 1) ? 0.86 : 0.72));
				float w = ep * profil;
				if (w > 0.5 && abs(ang) < ouverture * 1.2 && abs(dist - rk) < ep + 70.0) {
					// (son bord d'attaque est net, son bord de fuite s'étire un peu)
					float ecart_r = dist - rk;
					float dedans = w - ((ecart_r > 0.0) ? ecart_r * 1.25 : -ecart_r * 0.85);
					float dehors = max(-dedans, 0.0);
					float couv = smoothstep(-0.8, 1.2, dedans) * devant;
					vec3 c = teinte(clamp(dedans / max(w * 0.7, 1.0), 0.0, 1.0));
					rgb = rgb * (1.0 - couv) + c * couv;
					a = a * (1.0 - couv) + couv;
					lueur += couleur_halo.rgb * exp(-dehors / 14.0) * halo * 1.4 * profil * devant * (1.0 - couv);
				}
				// ses deux pointes tirent chacune un filet derrière elles
				float u_pointe = (tete - r0) + rk * cos(ouverture);
				float derriere = u_pointe - u;
				if (derriere > 0.0 && derriere < 230.0 * ech) {
					float dv = abs(v) - rk * sin(ouverture);
					float filet = exp(-(dv * dv) / (2.6 * 2.6)) * pow(1.0 - derriere / (230.0 * ech), 1.5) * smoothstep(0.0, 30.0, u);
					lueur += mix(couleur_halo.rgb, couleur_coeur.rgb, 0.4) * filet * 0.85 * devant;
				}
			}
			// la lueur qu'il traîne
			float sillage = (tete - r0 * 0.5) - u;
			if (sillage > 0.0 && sillage < 260.0) {
				float large = demi_bande * 0.8;
				lueur += couleur_halo.rgb * exp(-(v * v) / (large * large)) * pow(1.0 - sillage / 260.0, 2.0) * 0.16 * nait * devant;
			}
		}

		// des paillettes se détachent de son passage et tombent
		float pp = 58.0;
		int j0 = int(floor(u / pp));
		for (int dj = -1; dj <= 1; dj++) {
			int j = j0 + dj;
			float p1 = alea(j, g, 11);
			float p2 = alea(j, g, 12);
			float p3 = alea(j, g, 13);
			float uj = (float(j) + 0.5 + (p1 - 0.5) * 0.8) * pp;
			float vj = (p2 - 0.5) * 2.0 * demi_bande;
			// (le croissant passe plus tard sur ses bords qu'en son milieu)
			float age = tau - (uj + rayon * (1.0 - cos(asin(clamp(vj / max(rayon, 1.0), -1.0, 1.0))))) / max(vitesse, 1.0);
			if (uj < 40.0 || age < 0.0 || age > 0.75) {
				continue;
			}
			vec2 centre = dir * uj + travers * (vj + (p3 - 0.5) * 50.0 * age) + vec2(0.0, 90.0 * age * age);
			float clin = 0.55 + 0.45 * sin(age * (16.0 + 10.0 * p3) + p2 * 6.2832);
			float e = paillette(pos - centre, mix(4.0, 9.0, p2 * p2)) * clin * (1.0 - smoothstep(0.35, 0.75, age))
					* smoothstep(-3.0, 3.0, dot(centre - bout, normale));
			lueur += mix(couleur_halo.rgb, couleur_coeur.rgb, 0.35 + 0.5 * e) * e * paillettes;
		}

		// L'IMPACT : un éclat au point touché, un trait de lumière le long de la
		// surface, et des paillettes qui rejaillissent
		float depuis = tau - t_impact;
		vec2 db = pos - bout;
		if (depuis > 0.0 && depuis < 0.75 && dot(db, db) < 420.0 * 420.0) {
			lueur += clair * exp(-dot(db, db) / (60.0 * 60.0)) * exp(-depuis / 0.12) * 1.4;
			lueur += couleur_halo.rgb * exp(-dot(db, db) / (130.0 * 130.0)) * exp(-depuis / 0.2) * 0.5;
			// (le trait s'étend du point touché vers les deux pointes du slash)
			float etend = demi_bande * 1.3 * (1.0 - exp(-depuis * 14.0)) + 20.0;
			float trait = exp(-pow(dot(db, normale) / 3.0, 2.0)) * (1.0 - smoothstep(etend * 0.7, etend, abs(dot(db, le_long_surface))));
			lueur += mix(couleur_halo.rgb, couleur_coeur.rgb, 0.7 * exp(-depuis / 0.15)) * trait * exp(-depuis / 0.25) * 1.2;
			for (int q = 0; q < 9; q++) {
				float q1 = alea(q, g, 21);
				float q2 = alea(q, g, 22);
				// (elles repartent en gerbe, du côté de la normale)
				float ang = (q1 - 0.5) * 2.4;
				vec2 vers = vec2(cos(ang) * normale.x - sin(ang) * normale.y, sin(ang) * normale.x + cos(ang) * normale.y);
				vec2 centre = le_long_surface * ((q2 - 0.5) * demi_bande) + vers * mix(60.0, 200.0, q2) * (1.0 - exp(-depuis * 5.0))
						+ vec2(0.0, 160.0 * depuis * depuis);
				float clin = 0.6 + 0.4 * sin(depuis * (18.0 + 9.0 * q2) + q1 * 6.2832);
				float e = paillette(db - centre, mix(5.0, 11.0, q2)) * clin * (1.0 - smoothstep(0.3, 0.7, depuis));
				lueur += mix(couleur_halo.rgb, couleur_coeur.rgb, 0.35 + 0.5 * e) * e * paillettes;
			}
		}
	}

	// jamais coupé net par le bord du rectangle
	float bord = smoothstep(0.0, 24.0, min(min(pos.x - origine.x, origine.x + taille.x - pos.x),
			min(pos.y - origine.y, origine.y + taille.y - pos.y)));
	COLOR = vec4((rgb + lueur * (1.0 - a)) * bord, a * bord);
}
