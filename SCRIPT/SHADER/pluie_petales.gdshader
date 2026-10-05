shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;
// PLUIE DE PÉTALES (5 oct. 2026) — attaque de boss : sous ses ailes, des
// RIDEAUX serrés de pétales lumineux tombent de la hauteur du nœud jusqu'au
// sol. On ne reste pas dessous : il n'y a pas de place entre les rideaux.
// pluie_petales.gd pose les rideaux (leur abscisse, leur sol) et donne l'heure ;
// tout se dessine ici, sans particules.
//   • L'ANNONCE, sous toute l'envergure à la fois : un filet de lueur et une
//     poussière de paillettes descendent le long de chaque rideau, une étoile
//     s'allume au sol sous chacun et leurs traits couchés se rejoignent en une
//     ligne de lumière — la largeur de ce qui va tomber.
//   • LA PLUIE, du milieu vers les bords, LANCÉE : les premiers pétales
//     partent d'un trait, étirés par leur course et tout droits, comme jetés
//     par un coup d'aile ; puis la chute ralentit jusqu'à sa vitesse de
//     croisière et ils se mettent à pencher et à se balancer. Un pétale : une
//     larme effilée en haut, ventrue en bas ; cœur presque blanc, corps rose
//     strié, liseré plus sombre, et un halo ajouté à ce qu'il y a derrière
//     (mode prémultiplié).
//   • AU SOL : chaque rideau allume une petite flamme posée et sa lumière
//     couchée ; après le dernier pétale, la braise s'éteint.
// Les pétales d'un rideau sont rangés dans des cases qui tombent toutes du même
// chemin (`tombe`) : un pixel ne regarde que les trois cases autour de lui,
// dans les trois rideaux voisins.
// Tout le hasard est tiré d'un ENTIER (une case rend la même valeur d'où qu'on
// la calcule).

// --- fournis par pluie_petales.gd ---
// taille du rectangle et position de son coin dans le repère du nœud : tout est
// calculé dans ce repère (y = 0 : la ligne d'où tombent les pétales)
uniform vec2 taille = vec2(2080.0, 1000.0);
uniform vec2 origine = vec2(-1040.0, -90.0);
uniform int nb_colonnes = 0;
// l'abscisse de chaque rideau et la hauteur de son sol (au-delà de `chute` :
// pas de sol, il tombe dans le vide)
uniform float colonnes_x[32];
uniform float sols[32];
// l'abscisse du premier rideau sans son écart, et le pas des rideaux
uniform float base_x = -462.0;
uniform float espacement = 115.6;
uniform float chute = 1600.0;
uniform float envergure = 520.0;
// l'heure de la salve (s), la durée de l'annonce, celle de la pluie, le retard
// des rideaux du bord sur ceux du milieu, la vitesse de chute en croisière
// (px/s)
uniform float temps = 0.0;
uniform float delai = 0.4;
uniform float duree = 4.2;
uniform float balayage = 0.2;
uniform float vitesse = 700.0;
// l'IMPULSION du lancer : ce que les pétales font de plus que leur chute de
// croisière (px), et en combien de temps cet élan s'épuise (s)
uniform float impulsion = 600.0;
uniform float impulsion_duree = 0.25;
uniform float graine = 0.0;
// ------------------------------------

// --- l'allure ---
// demi-hauteur d'un grand pétale (px), et un pétale tous les … px dans un rideau
uniform float taille_petale : hint_range(10.0, 90.0) = 52.0;
uniform float pas_petales : hint_range(50.0, 300.0) = 118.0;
// une paillette tous les … px, et leur éclat
uniform float pas_paillettes : hint_range(10.0, 120.0) = 34.0;
uniform float paillettes : hint_range(0.0, 2.0) = 1.0;
// force du halo autour des pétales
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

// le hasard d'une case : colonne, rang dans la colonne, numéro du tirage
float alea(int colonne, int rang, int tirage) {
	uint n = uint(colonne + 64) * 7919u + uint(rang + 1048576) * 104729u + uint(tirage) * 15485863u;
	return alea_u(n);
}

// LA CHUTE : le chemin fait `tau` s après le départ d'un rideau — l'élan du
// lancer, vite épuisé, puis la vitesse de croisière (la même loi que
// pluie_petales.gd, qui s'en sert pour les dégâts)
float tombe(float tau) {
	return vitesse * tau + impulsion * (1.0 - exp(-tau / max(impulsion_duree, 0.01)));
}

// UN PÉTALE : une larme effilée en haut, ventrue en bas, dont la pointe se
// courbe d'un côté (`courbe`, en part de sa demi-largeur). `q` est le point
// dans son repère (y vers le bas), `h` sa demi-hauteur, `l` sa demi-largeur.
// Rend (profondeur à l'intérieur, distance à l'extérieur), en px.
vec2 petale(vec2 q, float h, float l, float courbe) {
	float s = clamp((q.y + h) / (2.0 * h), 0.0, 1.0);
	float w = l * sin(PI * pow(s, 1.6));
	// son axe : droit dans le ventre, il part de côté vers la pointe du haut
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
	int g = int(graine);
	// le chemin que fait un rideau pendant toute sa pluie : ses pétales partent
	// sur cette longueur-là
	float chemin_pluie = tombe(duree);
	if (nb_colonnes > 0) {
		int i0 = int(floor((pos.x - base_x) / espacement + 0.5));
		for (int di = -1; di <= 1; di++) {
			int i = i0 + di;
			if (i < 0 || i >= nb_colonnes) {
				continue;
			}
			float cx = colonnes_x[i];
			if (abs(pos.x - cx) > 120.0) {
				continue;
			}
			float sol = sols[i];
			bool a_un_sol = sol <= chute;
			// (sans sol, il se perd dans le vide : ses pétales s'éteignent de loin)
			float fond = a_un_sol ? sol : chute;
			float fondu = a_un_sol ? 30.0 : 170.0;
			// l'heure du rideau : l'annonce partout à la fois (toute la largeur se
			// lit d'un coup), la pluie d'abord au milieu, puis vers les bords
			float retard = balayage * clamp(abs(cx) / max(envergure, 1.0), 0.0, 1.0);
			float t_pluie = delai + retard;
			float t_fin = t_pluie + duree;
			// depuis le départ de ce rideau : le temps, le chemin fait, et ce qu'il
			// reste de l'élan du lancer (1 au départ, 0 en croisière)
			float tau = temps - t_pluie;
			float fait = (tau > 0.0) ? tombe(tau) : 0.0;
			float lance = (tau > 0.0) ? exp(-tau / max(impulsion_duree, 0.01)) : 0.0;

			// --- LES PÉTALES : trois cases autour du pixel, dans le repère qui tombe ---
			float u = pos.y - fait;
			int k0 = int(floor(u / pas_petales));
			for (int dk = -1; dk <= 1; dk++) {
				if (tau <= 0.0) {
					break;
				}
				int k = k0 + dk;
				float r1 = alea(i, k, 1 + g);
				float r2 = alea(i, k, 2 + g);
				float r3 = alea(i, k, 3 + g);
				float r4 = alea(i, k, 4 + g);
				float r5 = alea(i, k, 5 + g);
				float yk = (float(k) + 0.5 + (r2 - 0.5) * 0.55) * pas_petales;
				// parti pendant la pluie, ni avant le lancer ni après la fin : sinon il
				// n'existe pas
				if (yk > 0.0 || yk < -chemin_pluie) {
					continue;
				}
				float y = yk + fait;
				// il naît petit sur la ligne de départ et grandit en tombant ; LANCÉ, il
				// s'étire dans sa course et s'affine
				float hb = taille_petale * mix(0.55, 1.08, r3) * mix(0.3, 1.0, smoothstep(0.0, 110.0, y));
				float h = hb * (1.0 + 0.75 * lance);
				float l = hb * mix(0.42, 0.56, r4) * (1.0 - 0.22 * lance);
				if (y > fond + h) {
					continue;
				}
				float phase = r1 * 6.2832;
				// (lancé il file droit ; il ne penche et ne se balance qu'en ralentissant)
				float libre = 1.0 - 0.85 * lance;
				vec2 centre = vec2(cx + (r1 - 0.5) * 22.0 + 8.0 * sin(temps * 2.6 + phase) * libre, y);
				float angle = ((r5 - 0.5) * 0.7 + 0.16 * sin(temps * (3.0 + 2.0 * r4) + phase)) * libre;
				float ca = cos(angle);
				float sa = sin(angle);
				vec2 d = pos - centre;
				// (trop loin de ce pétale pour en voir même le halo)
				if (abs(d.x) > l + h * 0.6 + 45.0 || abs(d.y) > h + 50.0) {
					continue;
				}
				vec2 q = vec2(ca * d.x + sa * d.y, -sa * d.x + ca * d.y);
				vec2 pd = petale(q, h, l, (r2 - 0.5) * 2.4);
				// il s'éteint en touchant le sol
				float vis = smoothstep(0.0, 24.0, y) * (1.0 - smoothstep(fond - fondu, fond - 4.0, y + h * 0.55));
				float couv = smoothstep(-0.8, 1.2, pd.x) * vis;
				float m = clamp(pd.x / (l * 0.6), 0.0, 1.0);
				vec3 c = mix(couleur_lisere.rgb, couleur_corps.rgb, smoothstep(0.0, 0.3, m));
				c = mix(c, couleur_coeur.rgb, smoothstep(0.25, 0.7, m));
				// ses stries : deux ou trois coups de pinceau roses dans le cœur clair,
				// en éventail depuis sa pointe du bas, comme les barbes d'une plume
				float eventail = q.x / max(h * 1.2 - q.y, 1.0);
				float strie = smoothstep(0.62, 0.95, 0.5 + 0.5 * cos(eventail * 10.0 + (r2 - 0.5) * 5.0));
				c = mix(c, couleur_corps.rgb, 0.6 * strie * smoothstep(0.2, 0.6, m));
				rgb = rgb * (1.0 - couv) + c * couv;
				a = a * (1.0 - couv) + couv;
				lueur += couleur_halo.rgb * exp(-pd.y / 13.0) * halo * vis * (1.0 - couv);
				// lancé, il laisse un sillage de lumière au-dessus de lui (éteint avant
				// la limite d'où ce pétale est encore regardé : pas de bord net)
				if (lance > 0.02 && d.y < 0.0) {
					float sillage = exp(-(d.x * d.x) / (l * l * 0.45)) * exp(d.y / (h * 1.1))
							* smoothstep(-(h + 50.0), -h * 0.6, d.y) * smoothstep(0.0, 60.0, pos.y);
					lueur += mix(couleur_halo.rgb, couleur_coeur.rgb, 0.35) * sillage * lance * 0.9 * vis * (1.0 - couv);
				}
			}

			// --- LES PAILLETTES : plus fines, un peu plus lentes ; elles descendent
			// dès l'annonce, avant les pétales ---
			float v2 = vitesse * 0.82;
			float u2 = pos.y - v2 * temps;
			int j0 = int(floor(u2 / pas_paillettes));
			for (int dj = -1; dj <= 1; dj++) {
				int j = j0 + dj;
				float p1 = alea(i, j, 11 + g);
				if (p1 < 0.22) {
					continue;
				}
				float p2 = alea(i, j, 12 + g);
				float p3 = alea(i, j, 13 + g);
				float yj = (float(j) + 0.5 + (p2 - 0.5) * 0.8) * pas_paillettes;
				float t_depart = -yj / v2;
				if (t_depart < 0.0 || t_depart > t_fin + 0.15) {
					continue;
				}
				float y = yj + v2 * temps;
				if (y > fond) {
					continue;
				}
				vec2 centre = vec2(cx + (p3 - 0.5) * 58.0 + 5.0 * sin(temps * 3.3 + p2 * 6.2832), y);
				float clin = 0.55 + 0.45 * sin(temps * (7.0 + 6.0 * p3) + p1 * 6.2832);
				float e = paillette(pos - centre, mix(3.5, 8.5, p2 * p2)) * clin * smoothstep(-6.0, 30.0, y);
				lueur += mix(couleur_halo.rgb, couleur_coeur.rgb, 0.35 + 0.5 * e) * e * paillettes;
			}

			// --- LE FILET DE L'ANNONCE : une lueur très douce le long du rideau,
			// tant que les pétales ne sont pas arrivés à cette hauteur ---
			{
				float filet = smoothstep(0.0, 0.15, temps) * (1.0 - smoothstep(pos.y - 150.0, pos.y - 10.0, fait));
				if (filet > 0.001 && pos.y > 0.0 && pos.y < fond) {
					float large = exp(-(pos.x - cx) * (pos.x - cx) / (9.0 * 9.0));
					lueur += couleur_halo.rgb * large * 0.14 * filet * smoothstep(0.0, 80.0, pos.y);
				}
			}

			// --- AU SOL ---
			if (a_un_sol) {
				vec2 ds = pos - vec2(cx, sol);
				// les premiers pétales touchent-ils le sol ? et l'heure où le dernier y arrive
				float touche = smoothstep(sol - 50.0, sol + 10.0, fait);
				float t_dernier = t_fin + sol / vitesse;
				float cphase = alea(i, 7, 21 + g) * 6.2832;
				// l'annonce : une étoile qui grossit en battant, et un trait couché assez
				// long pour rejoindre ceux des voisins — une ligne de lumière sous
				// toute la pluie
				float annonce = smoothstep(0.0, 0.15, temps) * (1.0 - touche);
				if (annonce > 0.001) {
					float bat = 0.75 + 0.25 * sin(temps * 15.0 + cphase);
					float croit = clamp(temps / max(t_pluie, 0.05), 0.0, 1.0);
					float e = paillette(ds + vec2(0.0, 5.0), mix(9.0, 20.0, croit) * bat);
					float trait = exp(-(ds.x * ds.x) / (70.0 * 70.0) - (ds.y * ds.y) / (2.6 * 2.6));
					float nappe = exp(-(ds.x * ds.x) / (74.0 * 74.0) - (ds.y * ds.y) / (9.0 * 9.0));
					lueur += mix(couleur_halo.rgb, couleur_coeur.rgb, 0.7) * (e + trait * mix(0.35, 0.7, croit) * bat)  * annonce
							+ couleur_halo.rgb * nappe * 0.3 * annonce;
				}
				// la pluie : une petite flamme posée, qui vacille, et sa lumière couchée
				float feu = touche * (1.0 - smoothstep(t_dernier, t_dernier + 0.55, temps));
				if (feu > 0.001) {
					float vacille = 0.82 + 0.18 * sin(temps * 17.0 + cphase) * sin(temps * 11.3 + cphase * 1.7);
					float hf = taille_petale * 0.58 * vacille * mix(0.6, 1.0, feu);
					vec2 qf = ds + vec2(4.0 * sin(temps * 6.0 + cphase), hf * 0.92);
					vec2 pf = petale(qf, hf, hf * 0.46, 1.4 * sin(temps * 5.0 + cphase));
					float couv = smoothstep(-0.8, 1.2, pf.x) * feu;
					float m = clamp(pf.x / (hf * 0.26), 0.0, 1.0);
					vec3 c = mix(couleur_lisere.rgb, couleur_corps.rgb, smoothstep(0.0, 0.3, m));
					c = mix(c, couleur_coeur.rgb, smoothstep(0.3, 0.85, m));
					rgb = rgb * (1.0 - couv) + c * couv;
					a = a * (1.0 - couv) + couv;
					lueur += couleur_halo.rgb * exp(-pf.y / 13.0) * halo * feu * (1.0 - couv);
					float trait = exp(-(ds.x * ds.x) / (70.0 * 70.0) - (ds.y * ds.y) / (2.6 * 2.6));
					float nappe = exp(-(ds.x * ds.x) / (74.0 * 74.0) - (ds.y * ds.y) / (10.0 * 10.0));
					lueur += (couleur_coeur.rgb * trait * 0.8 + couleur_halo.rgb * nappe * 0.4) * feu * vacille;
				}
			}
		}
	}
	// jamais coupée net par le bord du rectangle
	float bord = smoothstep(0.0, 30.0, min(pos.x - origine.x, origine.x + taille.x - pos.x));
	COLOR = vec4((rgb + lueur * (1.0 - a)) * bord, a * bord);
}
