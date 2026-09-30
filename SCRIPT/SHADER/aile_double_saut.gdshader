shader_type canvas_item;
render_mode unshaded;
// AILE DE DOUBLE SAUT — une aile rouge sang qui surgit dans le dos du joueur,
// donne UN COUP vers le bas (c'est lui qui « porte » le second saut), puis se
// défait plume par plume. Même famille que les autres effets (aplats nets, tout
// piloté par `progress`, des formes qui MAIGRISSENT au lieu de s'estomper).
//
// Repère : l'origine est la RACINE de l'aile (entre les omoplates), le perso
// regarde vers +x et l'aile part derrière lui (vers -x) ; l'unité est la
// HAUTEUR du rectangle. Le nœud est enfant du POINT du joueur : il se retourne
// avec lui et le suit. Les angles se comptent depuis la verticale, en tournant
// vers le dos du perso (0° = vers le haut, 90° = vers l'arrière, 180° = le bas).
//
// L'aile est un ÉVENTAIL DE PLUMES, dessinées l'une par-dessus l'autre avec
// leur liseré (c'est lui qui fait lire des plumes, et pas un éventail uni) :
// les GRANDES PLUMES, un rang de COUVERTURES sur la racine, et une AILE ARRIÈRE
// plus petite et plus sombre, décalée derrière.
//
// QUATRE TEMPS — c'est le rythme qui fait l'impulsion :
//   1. elle SURGIT : déjà ouverte et dressée dès la première image, avec un
//      éclat clair et un léger rebond de taille ;
//   2. le COUP : toute l'aile s'abat de `battement` degrés, très vite au début ;
//      les pointes des plumes traînent derrière, et le bord de l'aile laisse
//      une TRAÎNÉE d'arcs clairs là où il vient de passer ;
//   3. la SUITE : elle finit sa course en se refermant un peu ;
//   4. elle SE DÉFAIT : chaque plume décolle de la racine et maigrit, pas
//      toutes au même instant.
//
// LE PLANÉ (1er oct. 2026, `plane` = 1) : la MÊME aile, dans une seconde
// instance que le script pilote, TENUE OUVERTE tant que le joueur plane. Pas de
// coup : elle surgit dressée et tombe aussitôt sur sa pose de plané en un seul
// rebond (c'est elle qui « accroche » l'air, dès la première image), puis elle
// houle lentement, ses plumes frémissent et leurs pointes plient vers le haut
// sous l'air qui porte le joueur. Quand il lâche le bouton, elle se replie en
// se défaisant comme après le coup. `plane` = 0 : le coup du double saut,
// exactement comme avant.

uniform float progress : hint_range(0.0, 1.0) = 0.0;

// --- fournis par aile_double_saut.gd à chaque image -------------------------
// largeur / hauteur du rectangle, et place de la racine de l'aile dedans
uniform float aspect = 0.9362;
uniform vec2 origine = vec2(0.6364, 0.5745);
// une valeur par aile : deux doubles sauts ne se défont pas pareil
uniform float graine = 0.0;
// ----------------------------------------------------------------------------

// nombre de grandes plumes
uniform int nb_plumes : hint_range(3, 10) = 7;
// longueur de la plus grande plume (1 = une hauteur de rectangle)
uniform float envergure : hint_range(0.1, 0.6) = 0.43;
// angle de l'éventail une fois ouvert (degrés)
uniform float ouverture : hint_range(20.0, 160.0) = 95.0;
// de combien l'aile s'abat pendant le coup (degrés)
uniform float battement : hint_range(0.0, 160.0) = 115.0;
// largeur des plumes
uniform float largeur : hint_range(0.3, 2.0) = 1.0;
// 0 = plumes droites, 1 = bien cambrées vers le bas
uniform float courbure : hint_range(0.0, 1.0) = 0.5;
// présence de la seconde aile, derrière (0 = une seule aile)
uniform float aile_arriere : hint_range(0.0, 1.0) = 0.8;
// l'éclat clair à l'apparition (0 = aucun)
uniform float eclat : hint_range(0.0, 1.0) = 0.8;
// la traînée d'arcs derrière le coup d'aile (0 = aucune)
uniform float trainee : hint_range(0.0, 1.0) = 0.8;
// liseré entre les plumes (0 = aucun)
uniform float contour : hint_range(0.0, 1.0) = 0.5;
uniform vec4 couleur : source_color = vec4(0.647, 0.159, 0.236, 1.0);
uniform vec4 couleur_arriere : source_color = vec4(0.414, 0.044, 0.098, 1.0);
uniform vec4 couleur_contour : source_color = vec4(0.207, 0.072, 0.111, 1.0);
// l'éclat du surgissement et la traînée du coup
uniform vec4 couleur_eclat : source_color = vec4(1.0, 0.86, 0.82, 1.0);

// --- LE PLANÉ : TOUT est fourni par aile_double_saut.gd à chaque image -------
// (les réglages de la pose sont dans le groupe « Plané » du nœud racine de la
// scène, pas ici : le script écrase ces valeurs)
// 0 = le coup du double saut ; 1 = l'aile tenue ouverte
uniform float plane : hint_range(0.0, 1.0) = 0.0;
// secondes depuis l'ouverture, et 0 → 1 à la fermeture
uniform float plane_temps = 0.0;
uniform float plane_fin : hint_range(0.0, 1.0) = 0.0;
// angle de la plume du haut une fois l'aile ouverte (degrés, 0 = vers le haut)
uniform float plane_angle : hint_range(-30.0, 90.0) = 40.0;
// écartement de l'éventail en plané (1 = celui du coup)
uniform float plane_eventail : hint_range(0.5, 1.6) = 1.0;
// taille de l'aile en plané (1 = celle du coup)
uniform float plane_taille : hint_range(0.5, 1.6) = 1.1;
// la houle lente de toute l'aile : amplitude (degrés) et vitesse
uniform float plane_houle : hint_range(0.0, 15.0) = 3.0;
uniform float plane_houle_vitesse : hint_range(0.0, 15.0) = 4.8;
// de combien l'air plie les pointes des plumes vers le haut (0 = pas du tout)
uniform float plane_portance : hint_range(0.0, 1.0) = 1.0;

// (PI est fourni par le langage de shader de Godot)

const int MAX_PLUMES = 10;
// part de la largeur d'une plume que son liseré peut ajouter, au plus
const float PART_CONTOUR = 0.5;

// hash 1D sans sin : une valeur stable par plume
float alea(float n) {
	n = fract(n * 0.1031);
	n *= n + 33.33;
	n *= n + n;
	return fract(n);
}

// Une PLUME plantée à l'origine de `e`. `phi` est son angle ; `l` sa longueur ;
// `demi` sa demi-largeur au plus large ; `cambre` la fait plier (positif = vers
// le bas de l'éventail) ; `depart` (0 → 1) est la fraction de sa longueur déjà
// partie depuis la racine, quand elle se défait. Fine à la racine, large aux
// deux tiers, bout arrondi. Renvoie deux distances, positives dedans : (la
// plume, la plume épaissie de son liseré).
vec2 plume(vec2 e, float phi, float l, float demi, float cambre, float depart, float c) {
	if (l <= 0.0001 || demi <= 0.0) {
		return vec2(-1.0);
	}
	vec2 dir = vec2(-sin(phi), -cos(phi));
	vec2 travers = vec2(-cos(phi), sin(phi));
	float s = dot(e, dir) / l;
	if (s <= depart || s >= 1.0) {
		return vec2(-1.0);
	}
	float ss = (s - depart) / (1.0 - depart);
	float large = demi * min(ss / 0.65, sqrt((1.0 - ss) / 0.35));
	float v = dot(e, travers) - cambre * l * s * s;
	return vec2(large, large + min(c, large * PART_CONTOUR)) - abs(v);
}

// pose une couleur par-dessus ce qui est déjà dessiné
void par_dessus(inout vec3 rgb, inout float a, vec3 teinte, float force) {
	float total = force + a * (1.0 - force);
	rgb = (teinte * force + rgb * a * (1.0 - force)) / max(total, 0.0001);
	a = total;
}


void fragment() {
	vec2 p = (UV - origine) * vec2(aspect, 1.0);
	float t = clamp(progress, 0.0, 1.0);
	// un pixel d'écran, en hauteurs de rectangle : des bords nets à toute échelle
	float px = length(vec2(dFdx(UV.y), dFdy(UV.y))) * 1.5;
	float c = contour * 0.014;

	// 1. elle surgit
	float surgit = smoothstep(0.0, 0.07, t);
	float rebond = 1.0 + 0.14 * sin(smoothstep(0.0, 0.22, t) * PI);
	float flash = eclat * (1.0 - smoothstep(0.04, 0.24, t));
	// 2. le coup : l'aile reste dressée le temps de deux images (il faut la
	// VOIR levée pour lire qu'elle s'abat), puis part à pleine vitesse et freine
	float s_coup = clamp((t - 0.09) / 0.26, 0.0, 1.0);
	float coup = 1.0 - pow(1.0 - s_coup, 3.0);
	float vite = (1.0 - s_coup) * (1.0 - s_coup) * step(0.09, t);   // 1 → 0 pendant le coup
	// 3. la suite, 4. elle se défait
	float suite = smoothstep(0.35, 0.82, t);
	float fin = clamp((t - 0.46) / 0.54, 0.0, 1.0);

	// LE PLANÉ : rien de ce coup n'est joué, l'aile est tenue ouverte
	bool pl = plane > 0.5;
	float pt = max(plane_temps, 0.0);
	// l'ouverture accroche l'air : l'aile surgit dressée et tombe sur sa pose
	// de plané en un seul rebond amorti (1 au départ, puis vers 0)
	float accroche = exp(-pt * 13.0) * cos(pt * 21.0);
	if (pl) {
		surgit = smoothstep(0.0, 0.05, pt);
		rebond = 1.0 + 0.08 * sin(smoothstep(0.0, 0.2, pt) * PI);
		flash = eclat * 0.6 * (1.0 - smoothstep(0.02, 0.16, pt));
		coup = 0.0;
		vite = 0.0;
		suite = 0.0;
		fin = clamp(plane_fin, 0.0, 1.0);
	}

	vec3 rgb = couleur.rgb;
	float a = 0.0;
	// 0 = l'aile arrière, dessinée d'abord ; 1 = l'aile avant
	for (int w = 0; w < 2; w++) {
		float arr = (w == 0) ? 1.0 : 0.0;
		float presence = mix(1.0, aile_arriere, arr);
		if (presence <= 0.001) {
			continue;
		}
		vec2 e = p - arr * vec2(0.045, -0.02);
		// dressée au départ, elle s'abat pendant le coup
		float phi0 = radians(-30.0 - 14.0 * arr) + radians(battement) * coup * mix(1.0, 0.9, arr)
				+ radians(10.0) * suite;
		// l'éventail s'écarte au milieu du coup, puis se referme un peu
		float eventail = mix(1.0, 0.72, suite) * (1.0 + 0.10 * sin(coup * PI));
		float taille = envergure * mix(1.0, 0.8, arr) * mix(0.75, 1.0, surgit) * rebond;
		if (pl) {
			// la pose de plané, qui houle lentement (l'aile arrière décalée :
			// les deux ne houlent pas ensemble) ; à la fermeture elle se
			// replie vers le bas en se défaisant
			float houle = sin(pt * plane_houle_vitesse + arr * 0.8);
			phi0 = radians(mix(-30.0, plane_angle, 1.0 - accroche) - 12.0 * arr
					+ plane_houle * houle + 25.0 * fin);
			eventail = (plane_eventail - 0.35 * accroche + 0.04 * sin(pt * plane_houle_vitesse + 1.3))
					* mix(1.0, 0.65, fin);
			taille *= plane_taille;
		}
		vec3 teinte = mix(mix(couleur.rgb, couleur_arriere.rgb, arr), couleur_eclat.rgb, flash);

		// la TRAÎNÉE du coup : trois arcs là où le bord de l'aile avant vient de
		// passer, épais contre l'aile, effilés derrière
		if (w == 1 && trainee > 0.001) {
			float rho = length(e);
			float recule = phi0 - atan(-e.x, -e.y);         // angle derrière le bord de l'aile
			float queue = radians(60.0) * vite;
			if (recule > 0.0 && recule < queue) {
				float le_long = recule / queue;
				for (int k = 0; k < 3; k++) {
					float f = trainee * 0.016 * vite * (1.0 - le_long)
							- abs(rho - taille * (0.97 - 0.19 * float(k)));
					par_dessus(rgb, a, couleur_eclat.rgb, smoothstep(0.0, px, f) * (0.35 + 0.65 * vite));
				}
			}
		}

		// rang 0 = les grandes plumes, rang 1 = les couvertures par-dessus
		for (int rang = 0; rang < 2; rang++) {
			float fr = float(rang);
			int n_rang = nb_plumes - rang;
			for (int i = 0; i < MAX_PLUMES; i++) {
				if (i >= n_rang) {
					break;
				}
				// du bas vers le haut : la plume du haut passe devant les autres
				float fi = float(n_rang - 1 - i);
				float place = (fi + 0.5 * fr) / float(nb_plumes - 1);   // 0 en haut, 1 en bas
				float phi = phi0 + radians(ouverture) * eventail * place;
				float l = taille * mix(1.0, 0.42, pow(place, 1.2)) * mix(1.0, 0.45, fr);
				float demi = largeur * l * mix(0.115, 0.21, fr);
				// pendant le coup, les pointes traînent derrière (elles plient vers le haut)
				float cambre = courbure * 0.22 - 0.30 * vite * mix(1.0, 0.4, fr);
				if (pl) {
					// en plané, l'air qui porte le joueur plie les pointes vers le
					// haut, et chaque plume frémit (celles du bas, plus)
					float frisson = sin(pt * 11.0 + fi * 1.9 + fr * 0.7 + arr * 2.3);
					phi += radians(2.2) * frisson * place;
					cambre = courbure * 0.22 - plane_portance * (0.16 + 0.05 * frisson) * mix(1.0, 0.5, fr);
				}
				// elle se défait : pas toutes les plumes au même instant
				float part = clamp(fin * 1.5 - 0.5 * alea(fi * 3.7 + fr * 11.0 + arr * 23.0 + graine), 0.0, 1.0);
				vec2 d = plume(e, phi, l * (1.0 + 0.25 * part), demi * (1.0 - part * part),
						cambre, 0.8 * part, c);
				par_dessus(rgb, a, couleur_contour.rgb, smoothstep(0.0, px, d.y) * presence);
				par_dessus(rgb, a, teinte, smoothstep(0.0, px, d.x) * presence);
			}
		}
	}
	COLOR = vec4(rgb, couleur.a * a);
}
