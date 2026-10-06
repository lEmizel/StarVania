shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;
// RAFALE DE PÉTALES (6 oct. 2026) — attaque de boss : d'un battement d'ailes,
// elle envoie des pétales à l'HORIZONTALE, des deux côtés à la fois, à travers
// toute l'arène. Chaque rafale passe à l'une de deux hauteurs : BASSE (au ras
// du sol : on la saute) ou HAUTE (au-dessus de la tête : on reste au sol).
// rafale_petales.gd donne l'heure et les rafales en route ; tout se dessine ici,
// sans particules, avec les pétales de la pluie (pluie_petales.gdshader).
//   • L'ANNONCE : la bande où la rafale va passer s'allume d'un bout à l'autre
//     de l'arène — ses bords en traits de lumière, et dedans des chevrons qui
//     glissent d'elle vers les murs (sa hauteur et son sens, d'un coup d'œil).
//   • LA RAFALE : un souffle de lumière qui remplit la bande, et dedans un train
//     serré de pétales, leur ventre en avant, chacun avec son sillage ; le front
//     est une barre de lumière.
//   • APRÈS : des traînées de lumière s'éteignent là où elle est passée.
// Le repère est celui du nœud : x = 0 là d'où partent les rafales, y vers le
// bas, le sol en y = `sol`. Tout le hasard est tiré d'un ENTIER.

// --- fournis par rafale_petales.gd ---
uniform vec2 taille = vec2(4000.0, 600.0);
uniform vec2 origine = vec2(-2000.0, -200.0);
uniform float sol = 300.0;
// jusqu'où vont les rafales, à gauche et à droite (px) : le premier mur
uniform float portee_g = 1900.0;
uniform float portee_d = 1900.0;
uniform float temps = 0.0;
uniform float annonce = 0.35;
uniform float vitesse = 2200.0;
uniform float longueur = 280.0;
// les deux hauteurs, en px au-dessus du sol : la basse va du sol à
// `basse_haut`, la haute de `haute_bas` à `haute_haut`
uniform float basse_haut = 90.0;
uniform float haute_bas = 170.0;
uniform float haute_haut = 430.0;
// les rafales en route (les `nb` premières cases) : l'heure de leur départ,
// haute (1) ou basse (0), leur tirage
uniform int nb = 0;
uniform float depart[4];
uniform float haute[4];
uniform float graines[4];
// ------------------------------------

// --- l'allure ---
// demi-longueur d'un grand pétale (px), un pétale tous les … px le long de la
// rafale, un rang tous les … px en hauteur
uniform float taille_petale : hint_range(10.0, 70.0) = 33.0;
uniform float pas_petales : hint_range(40.0, 200.0) = 62.0;
uniform float pas_rangs : hint_range(30.0, 120.0) = 46.0;
uniform float paillettes : hint_range(0.0, 2.0) = 1.0;
uniform float halo : hint_range(0.0, 1.5) = 0.6;
uniform vec4 couleur_coeur : source_color = vec4(1.0, 0.94, 0.99, 1.0);
uniform vec4 couleur_corps : source_color = vec4(0.98, 0.68, 0.87, 1.0);
uniform vec4 couleur_lisere : source_color = vec4(0.9, 0.32, 0.64, 1.0);
uniform vec4 couleur_halo : source_color = vec4(0.95, 0.3, 0.62, 1.0);

float alea_u(uint n) {
	n = (n << 13u) ^ n;
	n = n * (n * n * 15731u + 789221u) + 1376312589u;
	return float(n & 2147483647u) / 2147483647.0;
}

// le hasard d'une case : sa place le long de la rafale, son rang, le numéro du tirage
float alea(int le_long, int rang, int tirage) {
	uint n = uint(le_long + 4096) * 7919u + uint(rang + 64) * 104729u + uint(tirage) * 15485863u;
	return alea_u(n);
}

// UN PÉTALE (celui de la pluie) : une larme effilée d'un bout, ventrue de
// l'autre. `q` est le point dans son repère (y : vers son ventre), `h` sa
// demi-longueur, `l` sa demi-largeur. Rend (profondeur à l'intérieur, distance
// à l'extérieur), en px.
vec2 petale(vec2 q, float h, float l, float courbe) {
	float s = clamp((q.y + h) / (2.0 * h), 0.0, 1.0);
	float w = l * sin(PI * pow(s, 1.6));
	q.x -= courbe * l * (1.0 - s) * (1.0 - s);
	float cote = abs(q.x) - w;
	float bout = max(abs(q.y) - h, 0.0);
	float dehors = length(vec2(max(cote, 0.0), bout));
	return vec2((bout > 0.0) ? -dehors : -cote, dehors);
}

// UNE PAILLETTE : une croix à quatre branches fines et un point au milieu
float paillette(vec2 p, float r) {
	vec2 a = abs(p);
	float croix = max(exp(-a.x / (r * 0.16) - a.y / (r * 0.7)), exp(-a.y / (r * 0.16) - a.x / (r * 0.7)));
	return max(croix * 0.85, exp(-dot(p, p) / (r * r * 0.16)));
}

void fragment() {
	vec2 pos = UV * taille + origine;
	vec3 rgb = vec3(0.0);       // ce qui couvre (déjà multiplié par sa couverture)
	float a = 0.0;
	vec3 lueur = vec3(0.0);     // ce qui s'ajoute
	float d = abs(pos.x);
	float portee = (pos.x < 0.0) ? portee_g : portee_d;
	if (d <= portee + 20.0) {
		// le mur l'arrête : elle s'éteint en y arrivant
		float mur = 1.0 - smoothstep(portee - 70.0, portee, d);
		for (int k = 0; k < nb; k++) {
			bool est_haute = haute[k] > 0.5;
			float y_haut = sol - (est_haute ? haute_haut : basse_haut);
			float y_bas = sol - (est_haute ? haute_bas : 0.0);
			if (pos.y < y_haut - 60.0 || pos.y > y_bas + 45.0) {
				continue;
			}
			int g = int(graines[k]);
			float tau = temps - depart[k];
			float front = max(tau, 0.0) * vitesse;
			// 1 dans la bande, 0 dehors
			float dans = smoothstep(y_haut - 8.0, y_haut + 10.0, pos.y) * (1.0 - smoothstep(y_bas - 10.0, y_bas + 8.0, pos.y));

			// --- L'ANNONCE : devant la rafale, tant qu'elle n'est pas passée ---
			float monte = clamp((tau + annonce) / max(annonce, 0.05), 0.0, 1.0);
			float ann = monte * smoothstep(front - 30.0, front + 70.0, d) * mur;
			if (ann > 0.001) {
				float bat = 0.8 + 0.2 * sin(temps * 15.0 + float(k) * 2.1);
				float milieu_b = (y_haut + y_bas) * 0.5;
				// des chevrons glissent dans la bande, la pointe vers les murs
				float glisse = d - vitesse * 0.45 * temps + abs(pos.y - milieu_b) * 0.9;
				float c = fract(glisse / 170.0);
				float chevron = smoothstep(0.0, 0.07, c) * (1.0 - smoothstep(0.13, 0.3, c));
				lueur += mix(couleur_halo.rgb, couleur_coeur.rgb, 0.25) * (0.1 + 0.32 * chevron) * dans * ann * bat;
				// ses bords : deux traits de lumière épais, et leur halo
				float e = (pos.y - y_haut) / 3.6;
				float trait = exp(-e * e) + 0.35 * exp(-abs(pos.y - y_haut) / 14.0);
				if (est_haute) {
					e = (pos.y - y_bas) / 3.6;
					trait += exp(-e * e) + 0.35 * exp(-abs(pos.y - y_bas) / 14.0);
				}
				lueur += mix(couleur_halo.rgb, couleur_coeur.rgb, 0.65) * trait * 0.95 * bat * ann;
				// des paillettes filent dans la bande, d'elle vers les murs
				float milieu = (y_haut + y_bas) * 0.5;
				float demi = (y_bas - y_haut) * 0.5;
				float v = d - vitesse * 0.45 * (temps + 10.0);
				int j0 = int(floor(v / 64.0));
				for (int dj = -1; dj <= 1; dj++) {
					int j = j0 + dj;
					float p1 = alea(j, 9, 31 + g);
					if (p1 < 0.3) {
						continue;
					}
					float p2 = alea(j, 9, 32 + g);
					vec2 centre = vec2((float(j) + 0.5) * 64.0 + vitesse * 0.45 * (temps + 10.0), milieu + (p2 - 0.5) * 1.5 * demi);
					float clin = 0.55 + 0.45 * sin(temps * (7.0 + 6.0 * p2) + p1 * 6.2832);
					float s = paillette(vec2(d, pos.y) - centre, mix(4.0, 8.0, p2 * p2)) * clin;
					lueur += mix(couleur_halo.rgb, couleur_coeur.rgb, 0.4 + 0.5 * s) * s * paillettes * ann;
				}
			}
			if (tau <= 0.0) {
				continue;
			}

			// --- LA RAFALE : dans le repère qui file avec elle (0 : le front) ---
			float u = d - front;
			// le souffle : la bande s'emplit de lumière du front à la queue
			lueur += mix(couleur_halo.rgb, couleur_coeur.rgb, 0.2) * 0.3 * dans * mur
					* smoothstep(-longueur * 1.05, -longueur * 0.55, u) * (1.0 - smoothstep(-12.0, 26.0, u));
			if (u < 60.0 && u > -longueur - 70.0) {
				float haut_bande = y_bas - y_haut;
				int rangs = max(int(floor(haut_bande / pas_rangs + 0.5)), 1);
				float haut_rang = haut_bande / float(rangs);
				int iv0 = int(floor((pos.y - y_haut) / haut_rang));
				for (int dv = -1; dv <= 1; dv++) {
					int iv = iv0 + dv;
					if (iv < 0 || iv >= rangs) {
						continue;
					}
					// (un rang sur deux est décalé d'une demi-case)
					float decale = 0.5 * float(iv - 2 * (iv / 2));
					int iu0 = int(floor(u / pas_petales - decale));
					for (int du = -1; du <= 1; du++) {
						int iu = iu0 + du;
						float r1 = alea(iu, iv, 1 + g);
						float r2 = alea(iu, iv, 2 + g);
						float r3 = alea(iu, iv, 3 + g);
						float r4 = alea(iu, iv, 4 + g);
						float r5 = alea(iu, iv, 5 + g);
						float uc = (float(iu) + decale + 0.5 + (r2 - 0.5) * 0.6) * pas_petales;
						if (uc > 0.0 || uc < -longueur) {
							continue;
						}
						// serrés au front, plus rares et plus petits vers la queue
						float place = -uc / longueur;
						if (r1 > mix(0.98, 0.66, place)) {
							continue;
						}
						float yc = y_haut + (float(iv) + 0.5 + (r3 - 0.5) * 0.5) * haut_rang;
						float h = taille_petale * mix(0.62, 1.0, r4) * mix(1.25, 0.7, place);
						float l = h * mix(0.38, 0.5, r5) / mix(1.25, 1.0, place);
						vec2 dd = vec2(u - uc, pos.y - yc);      // (le long, en travers)
						if (abs(dd.x) > h + 70.0 || abs(dd.y) > l + 34.0) {
							continue;
						}
						float phase = r1 * 6.2832;
						float angle = (r5 - 0.5) * 0.45 + 0.2 * sin(temps * (5.0 + 3.0 * r4) + phase);
						float ca = cos(angle);
						float sa = sin(angle);
						// son repère : le ventre vers l'avant
						vec2 q = vec2(ca * dd.y - sa * dd.x, sa * dd.y + ca * dd.x);
						vec2 pd = petale(q, h, l, (r2 - 0.5) * 2.0);
						float vis = smoothstep(-longueur, -longueur * 0.78, uc) * mur * smoothstep(0.0, 36.0, d);
						float couv = smoothstep(-0.8, 1.2, pd.x) * vis;
						float m = clamp(pd.x / (l * 0.6), 0.0, 1.0);
						vec3 c = mix(couleur_lisere.rgb, couleur_corps.rgb, smoothstep(0.0, 0.3, m));
						c = mix(c, couleur_coeur.rgb, smoothstep(0.25, 0.7, m));
						rgb = rgb * (1.0 - couv) + c * couv;
						a = a * (1.0 - couv) + couv;
						lueur += couleur_halo.rgb * exp(-pd.y / 11.0) * halo * vis * (1.0 - couv);
						// son sillage : un trait de lumière derrière lui
						if (dd.x < 0.0) {
							float sillage = exp(-(dd.y * dd.y) / (l * l * 0.5)) * exp(dd.x / (h * 1.5))
									* smoothstep(-(h + 70.0), -h * 0.5, dd.x);
							lueur += mix(couleur_halo.rgb, couleur_coeur.rgb, 0.35) * sillage * 0.75 * vis * (1.0 - couv);
						}
					}
				}
				// le front : une barre de lumière
				float f = u / 30.0;
				lueur += mix(couleur_halo.rgb, couleur_coeur.rgb, 0.6) * exp(-f * f) * dans * 0.85 * mur * smoothstep(0.0, 36.0, d);
			}

			// --- APRÈS SON PASSAGE : des traînées qui s'éteignent ---
			float passe = (-longueur * 0.6 - u) / vitesse;
			if (passe > 0.0) {
				// quelques filets de lumière, à des hauteurs tirées au hasard, chacun
				// de sa longueur
				float rang = (pos.y - y_haut) / 9.0;
				int ir = int(floor(rang));
				float tire = alea(ir, 7, 41 + g);
				float filet = step(0.66, tire) * (1.0 - abs(fract(rang) - 0.5) * 2.0);
				float dure = mix(0.1, 0.3, alea(ir, 7, 42 + g));
				lueur += couleur_halo.rgb * 0.5 * filet * smoothstep(0.0, 0.04, passe) * exp(-passe / dure)
						* dans * mur;
			}
		}
	}
	// jamais coupée net par le bord du rectangle
	float bord = smoothstep(0.0, 30.0, min(pos.x - origine.x, origine.x + taille.x - pos.x));
	COLOR = vec4((rgb + lueur * (1.0 - a)) * bord, a * bord);
}
