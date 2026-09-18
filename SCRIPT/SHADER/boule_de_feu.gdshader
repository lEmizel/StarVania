shader_type canvas_item;
render_mode unshaded;
// BOULE DE FEU — visuel de projectile. Même famille que jet_flamme et
// flamme_cartoon : bruit à gradients (hash sans sin), aplats cartoon, même
// palette de quatre couleurs.
//
// À poser sur un ColorRect LARGE (≈ 3:1) : la BOULE occupe l'avant, la traînée
// s'étire derrière elle. Le projectile vole vers la DROITE de son repère —
// `scale.x = -1` le fait voler vers la gauche (convention de bloodball.tscn),
// et on tourne le nœud pour un tir en diagonale.
//
// PRINCIPE (repris du jet de flammes) : la traînée n'a AUCUN contour fixe. Sa
// matière EST le bruit, qui file vers l'arrière, et un seuil de dissolution
// grandit à mesure qu'on s'éloigne de la boule : chaque paquet de feu lâché
// rétrécit, se détache, puis s'éteint. La boule, elle, est un disque dense au
// bord rongé : c'est la tête du projectile, elle doit rester lisible.
//
// UN RÉGLAGE principal : `puissance`
//   0    → rien n'est dessiné (projectile éteint / pas encore né)
//   ~0.3 → petite braise à courte traînée
//   1    → pleine boule, longue traînée, cœur blanc

uniform float puissance : hint_range(0.0, 1.0) = 1.0;

// rayon de la boule, en HAUTEURS de rectangle (0.3 = 60 % de la hauteur en diamètre)
uniform float rayon : hint_range(0.05, 0.5) = 0.38;
// longueur de la traînée derrière la boule, même unité
uniform float longueur_trainee : hint_range(0.0, 3.0) = 1.7;
// vitesse à laquelle le feu part vers l'arrière
uniform float vitesse : hint_range(0.0, 8.0) = 3.0;
// la queue part PLUS ÉTROITE que la boule (col de la comète) puis s'évase :
// c'est ce qui fait lire la tête comme une boule et pas comme une dalle
uniform float col : hint_range(0.1, 1.0) = 0.45;
uniform float evasement : hint_range(0.0, 2.0) = 0.85;
// ondulation de la queue (0 = queue droite)
uniform float turbulence : hint_range(0.0, 1.0) = 0.45;
// à quel point la traînée se déchire tôt : 0 = compacte jusqu'au bout,
// 2 = elle part en lambeaux dès la sortie de la boule
uniform float dispersion : hint_range(0.0, 2.0) = 1.0;
// taille des paquets de feu (plus grand = plus fin)
uniform float detail : hint_range(1.0, 10.0) = 5.0;
// LARGEUR / hauteur du ColorRect : renseigné par boule_de_feu.gd, pour calculer
// le bruit dans un espace aux VRAIES proportions (sinon il est étiré par la
// forme du rectangle et le seuil y découpe des bandes verticales)
uniform float ratio = 3.0;
// position de la boule dans le rectangle (0 = tout à l'arrière, 1 = tout à l'avant)
uniform float tete_x : hint_range(0.3, 0.95) = 0.79;
// décale le bruit : renseigné par boule_de_feu.gd (une valeur par boule). Sans
// ça, deux boules tirées en même temps sont IDENTIQUES
uniform float graine = 0.0;
// 1 = aplats dessin animé, 0 = dégradé doux
uniform float style_cartoon : hint_range(0.0, 1.0) = 1.0;
uniform int nb_bandes : hint_range(2, 8) = 4;
uniform float saturation : hint_range(0.0, 2.0) = 1.0;

uniform vec4 outer_color : source_color = vec4(0.9, 0.05, 0.005, 1.0);
uniform vec4 middle_color : source_color = vec4(1.0, 0.32, 0.01, 1.0);
uniform vec4 inner_color : source_color = vec4(1.0, 0.85, 0.15, 1.0);
uniform vec4 core_color : source_color = vec4(1.0, 1.0, 0.75, 1.0);


// BRUIT À GRADIENTS (type Perlin), hash SANS sin (le hash sin perd sa précision
// GPU quand le temps défile). Surtout PAS de bruit de valeurs ici : quand la
// silhouette ET les couleurs sortent d'un seuil, sa structure en grille se voit
// en blocs rectangulaires (vécu sur le jet de flammes).
vec2 gradient(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(vec2(p.x * p.y, p.x + p.y)) * 2.0 - 1.0;
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = dot(gradient(i), f);
	float b = dot(gradient(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
	float c = dot(gradient(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
	float d = dot(gradient(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 0.75 + 0.5;
}

// 3 octaves : un projectile est petit à l'écran, la 4e ne se verrait pas et
// plusieurs boules peuvent voler en même temps. Grille tournée dès la première
// octave : aucune arête alignée sur l'écran.
float fbm(vec2 p) {
	const mat2 ROT = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	p = ROT * p;
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 3; i++) {
		value += noise(p) * amplitude;
		p = ROT * p * 2.03 + vec2(17.1, 9.2);
		amplitude *= 0.5;
	}
	return value / 0.875;      // ramené autour de 0..1
}


void fragment() {
	float p = clamp(puissance, 0.0, 1.0);
	if (p <= 0.002) {
		COLOR = vec4(0.0);      // éteint : rien à calculer, rien à dessiner
	} else {
		// repère centré sur la BOULE, en hauteurs de rectangle, x vers l'avant
		vec2 pos = (UV - vec2(tete_x, 0.5)) * vec2(ratio, 1.0);
		float d = length(pos);
		float derriere = -pos.x;                    // > 0 derrière la boule

		// --- LA MATIÈRE : du bruit qui file vers l'ARRIÈRE --------------------
		float flux = vitesse * (0.6 + 0.4 * p);
		vec2 q = vec2(pos.x + TIME * flux + graine * 7.13, pos.y + graine * 3.71);
		float gros = fbm(q * detail);
		// le détail fin recule 35 % plus vite que les gros paquets. Le temps va en X :
		// ajouté en Y, il faisait DÉRIVER le détail vers le bas au lieu de reculer.
		float fin = fbm(vec2(q.x + TIME * flux * 0.35, q.y) * detail * 2.4 + vec2(5.3, 0.0));
		float matiere = clamp((mix(gros, fin, 0.35) - 0.28) / 0.44, 0.0, 1.0);

		// --- LA BOULE : un disque dense, bord rongé par le bruit --------------
		float r = rayon * (0.45 + 0.55 * p);
		// distance BRUITÉE : elle sert à la fois au contour et aux couches de
		// chaleur. Avec la distance exacte, les aplats cartoon dessinaient des
		// anneaux parfaits, façon cible.
		float dn = d + (matiere - 0.5) * 0.36 * r;
		float tete = 1.0 - smoothstep(r * 0.72, r * 1.14, dn);

		// --- LA TRAÎNÉE : de la matière qui se dissout en s'éloignant ---------
		float lon = longueur_trainee * (0.3 + 0.7 * p);
		float t = derriere / max(lon, 0.001);       // 0 à la boule → 1 au bout ; peut dépasser
		float tc = clamp(t, 0.0, 1.0);
		float demi = r * (col + evasement * tc);
		// la queue serpente de plus en plus loin de la boule
		float yy = pos.y + (gros - 0.5) * turbulence * r * tc;
		float bord = abs(yy) / max(demi, 0.0001);
		// le seuil monte en s'éloignant de la boule (front ondulé par le bruit)…
		float debut = mix(0.85, 0.15, clamp(dispersion * 0.5, 0.0, 1.0));
		float seuil_bout = smoothstep(debut, 1.2, t + (gros - 0.5) * 0.3);
		// …et vers les bords de la traînée
		float seuil = max(seuil_bout, smoothstep(0.55, 1.15, bord));
		// masque « derrière la boule » : la queue naît dans le dos de la tête
		float masque_queue = smoothstep(-r * 0.05, r * 0.55, derriere);
		float trainee = smoothstep(seuil - 0.12, seuil + 0.02, matiere + 0.02) * masque_queue;
		trainee *= 1.0 - smoothstep(1.1, 1.35, bord);         // rien loin de l'axe
		trainee *= 1.0 - smoothstep(1.15, 1.35, t);           // rien au-delà de la traînée

		float corps = max(tete, trainee);

		// --- CHALEUR → COULEUR ------------------------------------------------
		// le cœur de la boule est le plus chaud ; la traînée refroidit en
		// s'éloignant, et un paquet qui se dissout rougit avant de s'éteindre
		// la QUEUE plafonne à 0,62 de chaleur : elle reste orange puis rouge, et
		// c'est ce qui fait ressortir la tête. Sans ce plafond, son axe était aussi
		// clair que le noyau et les deux se fondaient en une seule masse.
		// `centre` passe par le MÊME masque que la queue. Sans lui, la chaleur de la
		// queue s'appliquait aussi DEVANT la boule : elle y réchauffait une bande
		// centrée sur l'axe, qui ressortait en pointe jaune traversant les anneaux
		// orange et rouge du bord avant (vu par Kaoru le 18 sept. 2026).
		float centre = (1.0 - clamp(bord, 0.0, 1.0)) * masque_queue;
		float chaleur = centre * (1.0 - tc * 0.8) * 0.62 * (0.6 + 0.4 * p) + (fin - 0.5) * 0.2;
		chaleur *= 0.55 + 0.45 * smoothstep(seuil, seuil + 0.35, matiere);
		// la BOULE, elle, va jusqu'au blanc : noyau clair, couche jaune, bord orange
		chaleur = max(chaleur, (1.0 - smoothstep(r * 0.25, r * 1.15, dn)) * (0.85 + 0.15 * p));
		chaleur = clamp(chaleur, 0.0, 1.0);

		float aplat = (floor(chaleur * float(nb_bandes)) + 0.5) / float(nb_bandes);
		chaleur = mix(chaleur, aplat, style_cartoon);

		vec3 color;
		if (chaleur < 0.30) {
			color = mix(outer_color.rgb, middle_color.rgb, chaleur / 0.30);
		} else if (chaleur < 0.70) {
			color = mix(middle_color.rgb, inner_color.rgb, (chaleur - 0.30) / 0.40);
		} else {
			color = mix(inner_color.rgb, core_color.rgb, (chaleur - 0.70) / 0.30);
		}

		float gris = dot(color, vec3(0.299, 0.587, 0.114));
		color = clamp(mix(vec3(gris), color, saturation), 0.0, 1.0);

		// contour net en cartoon, fondu en dégradé
		float alpha = mix(corps, smoothstep(0.35, 0.62, corps), style_cartoon);
		COLOR = vec4(color, alpha);
	}
}
