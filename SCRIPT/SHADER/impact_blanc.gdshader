shader_type canvas_item;
render_mode unshaded;
// IMPACT BLANC — l'éclat qui marque un coup d'épée qui PORTE. Même famille que
// explosion_violette (aplats nets, tout piloté par `progress`), mais sans
// matière ni palette : du blanc pur, des formes coupantes, et c'est fini en
// un sixième de seconde. À poser sur un ColorRect CARRÉ, l'éclat part du centre.
//
// Le coup vient de la GAUCHE et part vers la DROITE du rectangle (+x) ;
// `scale.x = -1` sur le nœud le retourne pour un coup porté vers la gauche.
//
// TROIS FORMES, qui ne s'estompent pas : elles MAIGRISSENT jusqu'à disparaître
// (un fondu ferait mou, un trait qui s'affine fait sec) :
//   • la LAME   — une grande estafilade en fuseau, dans l'axe du coup ;
//   • le CŒUR   — un disque plein qui claque et s'éteint avant la moitié ;
//   • les ÉCLATS — des fuseaux pointus qui jaillissent en étoile puis décollent
//                  du centre, plus longs vers l'avant que vers l'arrière.
// Le tout premier instant est GROS (l'étoile pleine) : c'est lui qui claque.
//
// Le CONTOUR d'encre détache le blanc de ce qu'il recouvre : un monstre touché
// flashe lui-même en blanc, et sans ce liseré l'éclat se fondrait dedans.
//
// Sert aussi en ROUGE SANG (impact_sang.tscn : `couleur` et `couleur_contour`),
// pour le coup que le joueur encaisse.

uniform float progress : hint_range(0.0, 1.0) = 0.0;

uniform int nb_traits : hint_range(3, 24) = 9;
// portée des plus longs éclats, en fraction du rectangle (0.5 = jusqu'au bord)
uniform float longueur : hint_range(0.1, 0.5) = 0.46;
// épaisseur des éclats (0 = cheveux, 1 = lames larges)
uniform float epaisseur : hint_range(0.05, 1.0) = 0.5;
// 0 = étoile régulière, 1 = presque tout part vers l'avant
uniform float directivite : hint_range(0.0, 1.0) = 0.55;
// la grande estafilade dans l'axe du coup (0 = aucune)
uniform float lame : hint_range(0.0, 1.0) = 1.0;
// rayon du disque central au moment de l'impact
uniform float coeur : hint_range(0.0, 0.3) = 0.075;
// liseré d'encre autour du blanc (0 = aucun)
uniform float contour : hint_range(0.0, 1.0) = 0.5;
// une valeur par éclat : deux coups de suite ne se ressemblent pas
uniform float graine = 0.0;
uniform vec4 couleur : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 couleur_contour : source_color = vec4(0.05, 0.03, 0.06, 1.0);

// (PI et TAU sont fournis par le langage de shader de Godot)

// part de l'épaisseur d'une forme que son contour peut ajouter, au plus : le
// liseré s'affine avec la forme, et une pointe finit en pointe
const float PART_CONTOUR = 0.6;

// hash 1D sans sin : une valeur stable par éclat
float alea(float n) {
	n = fract(n * 0.1031);
	n *= n + 33.33;
	n *= n + n;
	return fract(n);
}

// Un FUSEAU couché sur l'axe u, de u0 à u1, pointu aux deux bouts. `demi` est
// sa demi-largeur au ventre, placé à la fraction `ventre` de sa longueur, `c`
// la largeur du contour. Renvoie deux distances, positives dedans : (le blanc,
// le blanc épaissi de son contour).
vec2 fuseau(float u, float v, float u0, float u1, float demi, float ventre, float c) {
	float s = (u - u0) / max(u1 - u0, 0.0001);
	if (s <= 0.0) {
		return vec2(-length(vec2(u - u0, v)));
	}
	if (s >= 1.0) {
		return vec2(-length(vec2(u - u1, v)));
	}
	float large = demi * min(s / ventre, (1.0 - s) / (1.0 - ventre));
	return vec2(large, large + min(c, large * PART_CONTOUR)) - abs(v);
}


void fragment() {
	vec2 p = UV - 0.5;
	float d = length(p);
	float ang = atan(p.y, p.x);
	float t = clamp(progress, 0.0, 1.0);
	float vie = 1.0 - t;                        // tout maigrit avec le temps
	float pousse = 1.0 - pow(1.0 - t, 3.0);     // ça part très vite puis ça freine
	float flash = 1.0 - smoothstep(0.0, 0.3, t); // le premier instant, gonflé
	// un pixel d'écran, en unités du rectangle : des bords nets à toute échelle
	float px = (fwidth(UV.x) + fwidth(UV.y)) * 0.75;
	float c = contour * 0.014;

	// les formes s'additionnent par le max de leurs distances : x = le blanc,
	// y = le blanc épaissi de son contour
	vec2 sd = vec2(-1.0);

	// 1) LA LAME : bien plus longue vers l'avant, elle traverse la cible
	float demi_lame = lame * (0.042 * pow(vie, 1.4) + 0.034 * flash);
	float l_avant = longueur * (0.6 + 0.4 * pousse);
	float l_arriere = l_avant * (1.0 - 0.8 * directivite);
	sd = max(sd, fuseau(p.x, p.y, -l_arriere, l_avant, demi_lame,
			l_arriere / (l_avant + l_arriere), c));

	// 2) LE CŒUR : il claque, et il est parti avant la moitié
	float r_coeur = coeur * clamp(1.0 - t * 2.4, 0.0, 1.0);
	sd = max(sd, vec2(r_coeur, r_coeur + min(c, r_coeur * PART_CONTOUR)) - d);

	// 3) LES ÉCLATS : un par secteur angulaire. L'angle est tourné PUIS replié
	// sur un tour (la couture du cercle tombe entre deux secteurs), et chaque
	// pixel regarde aussi les deux secteurs voisins : un éclat large ou décalé
	// n'est jamais coupé par la frontière de son secteur.
	float n = float(nb_traits);
	float secteur = TAU / n;
	float tour = mod(ang + PI + graine * 2.4, TAU) / secteur;
	float idx0 = floor(tour);
	for (int k = -1; k <= 1; k++) {
		float idx = mod(idx0 + float(k), n);
		float h1 = alea(idx * 1.7 + graine);
		float h2 = alea(idx * 3.1 + graine * 1.3 + 5.0);
		float h3 = alea(idx * 5.3 + graine * 0.7 + 9.0);
		// écart d'angle entre ce pixel et l'axe de l'éclat
		float delta = (tour - (idx0 + float(k) + 0.5 + (h3 - 0.5) * 0.5)) * secteur;
		// (ang - delta = l'axe lui-même : c'est lui qui dit si l'éclat part vers l'avant)
		float avant = 1.0 - directivite * 0.5 * (1.0 - cos(ang - delta));
		float r1 = longueur * (0.45 + 0.55 * h1) * avant * (0.62 + 0.38 * pousse);
		float r0 = r1 * 0.85 * t;                // la base décolle : l'éclat s'en va
		float demi = epaisseur * (0.030 + 0.030 * h2) * (vie + 1.1 * flash);
		sd = max(sd, fuseau(d * cos(delta), d * sin(delta), r0, r1, demi, 0.22, c));
	}

	float blanc = smoothstep(0.0, px, sd.x);
	float encre = smoothstep(0.0, px, sd.y);
	// là où il n'y a pas de contour, encre == blanc : du blanc pur, sans frange
	vec3 rgb = mix(couleur_contour.rgb, couleur.rgb, blanc / max(encre, 0.0001));
	COLOR = vec4(rgb, couleur.a * encre);
}
