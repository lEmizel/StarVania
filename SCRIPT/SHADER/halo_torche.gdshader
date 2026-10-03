shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;
// HALO DE TORCHE (3 oct. 2026, d'après une image de référence de Kaoru) — la
// lueur ronde autour de la flamme de ses torches (SCRIPT/INTERACTIBLE/
// flamme.tscn, la flamme qu'il pose sur les torches peintes de ses décors) :
//   • un disque orange translucide, un peu plus fort près de la flamme, cerné
//     d'un fin LISERÉ plus clair et d'une lueur douce juste dehors ;
//   • un TREMBLÉ DESSINÉ À LA MAIN : le cercle est presque rond sur chaque
//     image, mais il est REDESSINÉ `images_trace` fois par seconde, un peu
//     différent à chaque fois (bord légèrement bosselé, centre qui bouge d'un
//     rien, liseré plus ou moins épais) — le « trait qui bout » des dessins
//     animés. Kaoru, sur sa référence : « dans les images c'est un rond quasi
//     parfait, en fait ça bouge, le rond n'est pas toujours super rond, ça donne
//     un côté dessiné à la main ». (1er essai : un bord qui ondulait en continu,
//     des plaques de chaleur et un liseré effacé par endroits — trop.)
//   • le LISERÉ, ce sont TROIS COUPS DE PINCEAU NETS répartis autour du
//     cercle, avec des vides entre eux : chacun part épais et franc, s'amincit
//     et s'efface. Un trait à bord FRANC (anticrénelé), pas une lueur floue.
//     Les retours de Kaoru, dans l'ordre : « plus déstructuré, comme si parfois
//     il s'effaçait — regarde mieux la référence » ; « ça clignote trop, il
//     bouge trop » (tout était retiré au hasard 12 fois par seconde : leurs
//     places et leurs longueurs dérivent maintenant LENTEMENT, au pas des
//     tracés) ; « on y est presque, faudrait mieux répartir les traits et les
//     rendre plus nets » (un seul long trait laissait un côté vide, et il
//     était flou).
//   • il respire avec le vacillement de la flamme (`vacille`, posé à chaque
//     image par flamme.gd — la même valeur fait vaciller sa lumière ; dans
//     l'éditeur il reste à mi-souffle) ;
//   • quelques BRAISES montent de la pointe, dérivent et s'éteignent.
// Elle TEINTE le décor en orange plus qu'elle ne s'y ajoute (`teinte`, alpha
// prémultiplié) : en lumière seulement ajoutée, elle virait au pêche pâle sur
// ses décors clairs (gris-bleu de sc_10, scene_7). Les braises, elles, sont
// des points de couleur pleine, et le liseré a une épaisseur FIXE à l'écran
// (un trait de crayon : il grossissait avec les grandes torches).
// Le halo reste ROND même si la flamme est étirée (échelle non uniforme) et
// grandit avec elle : les distances sont prises en repère monde (MODEL_MATRIX),
// ramenées à l'échelle moyenne du nœud. Chaque torche a ses propres braises :
// leur hasard part de sa position dans le monde.
// Repère : `centre` et `source_braises` dans le rectangle (px locaux).

uniform vec2 taille = vec2(120.0, 156.0);
uniform vec2 centre = vec2(60.0, 96.0);
uniform float rayon = 46.0;                       // px locaux, à l'échelle moyenne du nœud
uniform float vacille : hint_range(0.0, 1.0) = 0.5;
uniform float force_disque : hint_range(0.0, 1.0) = 0.26;
uniform float force_lisere : hint_range(0.0, 1.0) = 0.55;
uniform float force_lueur : hint_range(0.0, 1.0) = 0.12;
// le cercle est redessiné tant de fois par seconde (12 = un dessin animé « en deux »)
uniform float images_trace : hint_range(1.0, 30.0) = 12.0;
// à chaque nouveau tracé, le bord se bossèle de ± tant (part du rayon) ; 0 = cercle parfait
uniform float tremble : hint_range(0.0, 0.2) = 0.035;
// 1 = la lueur teinte le décor en orange (garde sa couleur sur un décor clair),
// 0 = elle s'y ajoute (plus « lumière », mais vire au blanc sur un décor clair)
uniform float teinte : hint_range(0.0, 1.0) = 0.7;
// épaisseur du liseré à l'écran (px), quelle que soit la taille de la torche
uniform float epaisseur_lisere = 2.0;
// le coup de pinceau du liseré : 0 = trait égal tout autour, 1 = il s'amincit,
// s'efface et se troue comme sur la référence
uniform float pinceau : hint_range(0.0, 1.0) = 1.0;
uniform int nb_braises : hint_range(0, 12) = 5;
uniform vec2 source_braises = vec2(60.0, 78.0);   // la pointe de la flamme
uniform float montee_braises = 55.0;              // elles montent d'autant (px locaux)
uniform vec4 couleur : source_color = vec4(1.0, 0.55, 0.16, 1.0);
uniform vec4 couleur_lisere : source_color = vec4(1.0, 0.68, 0.28, 1.0);
uniform vec4 couleur_braise : source_color = vec4(1.0, 0.74, 0.28, 1.0);

varying vec2 v_echelle;
varying float v_graine;


// hasard ENTIER, exact (le hasard flottant fait des marches et perd sa
// précision quand les nombres grandissent)
float alea_u(uint n) {
	n = (n << 13u) ^ n;
	n = n * (n * n * 15731u + 789221u) + 1376312589u;
	return float(n & 2147483647u) / 2147483647.0;
}

// le hasard des nœuds du bruit : ENTIER, exact (sans marches aux raccords)
float alea_noeud(vec2 i) {
	uint x = uint(int(i.x) + 8192);
	uint y = uint(int(i.y) + 8192);
	return alea_u(x * 7919u + y * 104729u);
}

float bruit(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(alea_noeud(i), alea_noeud(i + vec2(1.0, 0.0)), u.x),
			mix(alea_noeud(i + vec2(0.0, 1.0)), alea_noeud(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	v_echelle = vec2(length(MODEL_MATRIX[0].xy), length(MODEL_MATRIX[1].xy));
	vec2 o = MODEL_MATRIX[3].xy;
	v_graine = alea_u(uint(int(floor(o.x)) + 100000) * 7919u + uint(int(floor(o.y)) + 100000) * 104729u);
}

void fragment() {
	vec2 pix = UV * taille;
	float s = max((v_echelle.x + v_echelle.y) * 0.5, 0.0001);
	// l'écart au centre, ramené à l'échelle moyenne : rond dans le monde
	float g = v_graine * 50.0;
	// LE TRACÉ DU MOMENT : un nouveau dessin `images_trace` fois par seconde
	// (chaque torche à son propre rythme), tous un peu différents
	float trace = floor(TIME * images_trace + v_graine * 97.0);
	vec2 hasard = vec2(alea_u(uint(int(trace) + 100000) * 31u + uint(g * 1000.0)),
			alea_u(uint(int(trace) + 100000) * 57u + uint(g * 1000.0) + 7u));
	// le centre bouge d'un rien d'un tracé à l'autre, le rayon aussi
	vec2 q = (pix - centre) * v_echelle / s - (hasard - 0.5) * 0.5;
	float d = length(q);
	vec2 dir = q / max(d, 0.0001);
	// le bord, un peu bosselé : un bruit lu sur le tour du cercle (il se
	// referme tout seul). D'un tracé à l'autre, on avance d'un PETIT pas dans ce
	// bruit : chaque tracé ressemble au précédent, en un peu différent (un
	// tirage tout neuf faisait sauter le bord de plusieurs px 12 fois par seconde)
	vec2 tirage = vec2(trace * 0.22, g) + hasard * 0.12;
	float bosses = bruit(dir * 1.2 + tirage) * 0.75 + bruit(dir * 2.6 + tirage.yx * 1.3) * 0.25;
	float r = rayon * (0.965 + 0.07 * vacille) * (0.994 + 0.012 * hasard.x)
			* (1.0 + (bosses - 0.5) * 2.0 * tremble);
	float aa = max(fwidth(d), 0.0005);
	float souffle = 0.8 + 0.4 * vacille;

	// ===================== LE DISQUE, SON LISERÉ, SA LUEUR =====================
	float dedans = clamp((r - d) / aa + 0.5, 0.0, 1.0);
	float k = clamp(d / r, 0.0, 1.0);
	float disque = dedans * (0.78 + 0.22 * (1.0 - k) * (1.0 - k));
	// LE LISERÉ : TROIS COUPS DE PINCEAU répartis sur le tour (un par tiers,
	// un peu décalés), dans un sens propre à chaque torche. Chacun couvre d'un
	// cinquième à un tiers de tour : épais et franc au départ, il s'amincit et
	// s'efface ; entre eux, des vides. Leurs places et leurs longueurs suivent
	// un temps LENT, au pas des tracés : un peu différents à chaque tracé,
	// sans jamais sauter
	float lent = trace / max(images_trace, 1.0);        // les secondes, au pas des tracés
	float ang = atan(q.y, q.x);
	uint gi = uint(g * 1000.0);
	float sens_trait = alea_u(gi + 3u) < 0.5 ? -1.0 : 1.0;
	float base_ang = alea_u(gi + 9u) * TAU;
	float coup = 0.0;
	for (int c = 0; c < 3; c++) {
		float fc = float(c);
		float a0 = base_ang + fc * TAU / 3.0 + (alea_u(gi + 20u + uint(c)) - 0.5) * 0.6
				+ (bruit(vec2(lent * 0.12 + fc * 3.7, g * 2.1)) - 0.5) * 0.7;
		float lg = 0.2 + 0.13 * bruit(vec2(lent * 0.15 + fc * 5.3, g * 1.3));
		float u = fract(sens_trait * (ang - a0) / TAU) / lg;
		if (u < 1.0) {
			float e = smoothstep(0.0, 0.12, u) * (1.0 - smoothstep(0.55, 1.0, u)) * mix(1.45, 0.55, u);
			coup = max(coup, e);
		}
	}
	float profil = mix(1.0, coup, pinceau);
	// un trait NET : une bande pleine à bord franc (anticrénelé sur un pixel),
	// qui s'amincit avec le coup de pinceau — épaisseur en px d'écran, ramenée
	// à l'échelle de la torche
	float demi = epaisseur_lisere * 0.5 * profil * (0.85 + 0.3 * bruit(dir * 2.2 + vec2(lent * 0.1, g * 1.9))) / s;
	float lisere = clamp((demi - abs(d - r)) / aa + 0.5, 0.0, 1.0) * (0.85 + 0.15 * bosses) * step(0.02, profil);
	// une frange serrée juste dehors (le bord du disque reste net)
	float lueur = (1.0 - dedans) * exp(-max(d - r, 0.0) / 2.5);
	// alpha prémultiplié : chaque élément ajoute sa couleur, et COUVRE le décor
	// à hauteur de `teinte` (couvert = teinté en orange, découvert = ajouté)
	float af = disque * force_disque * souffle;
	float al = lisere * force_lisere * souffle;
	float ag = lueur * force_lueur * souffle;
	vec3 rgb = couleur.rgb * af + couleur_lisere.rgb * al + couleur.rgb * ag;
	float a = (af + al) * teinte + ag * teinte * 0.5;

	// ===================== LES BRAISES =====================
	uint graine = uint(v_graine * 1048575.0);
	for (int i = 0; i < 12; i++) {
		if (i >= nb_braises) {
			break;
		}
		uint base = uint(i) * 2654435761u + graine;
		float periode = 1.0 + 0.9 * alea_u(base + 11u);
		float ph = TIME / periode + alea_u(base + 23u);
		float t = fract(ph);
		uint h = base * 31u + uint(int(floor(ph)) + 1000000) * 7919u;
		vec2 depart = source_braises + vec2((alea_u(h + 1u) - 0.5) * 9.0, (alea_u(h + 2u) - 0.5) * 6.0);
		float derive = (alea_u(h + 3u) - 0.5) * 26.0;
		vec2 pos = depart + vec2(derive * t + sin(t * 7.0 + alea_u(h + 4u) * 6.28) * 3.5,
				-t * montee_braises * (0.7 + 0.6 * alea_u(h + 5u)));
		float vie = smoothstep(0.0, 0.1, t) * (1.0 - smoothstep(0.5, 1.0, t));
		// leur taille en px d'écran : de petits points, quelle que soit la torche
		float db = length((pix - pos) * v_echelle);
		float taille_b = 1.1 + 1.0 * alea_u(h + 6u);
		float coeur = clamp((taille_b - db) / max(fwidth(db), 0.0005) + 0.5, 0.0, 1.0);
		float halo_b = exp(-db / 2.5) * 0.3;
		float eb = clamp((coeur + halo_b) * vie, 0.0, 1.0);
		rgb = mix(rgb, couleur_braise.rgb, eb);
		a = mix(a, 1.0, eb);
	}

	// rien ne touche le bord du rectangle
	float bord = min(min(pix.x, taille.x - pix.x), min(pix.y, taille.y - pix.y));
	float fondu = smoothstep(0.0, 4.0, bord);
	COLOR = vec4(rgb, clamp(a, 0.0, 1.0)) * fondu;
}
