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
