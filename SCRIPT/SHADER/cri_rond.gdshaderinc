// CRI EN ROND — le calcul des ondes, commun aux deux couches du cri
// (cri_rond_traits.gdshader : les ronds tracés au pinceau ;
// cri_rond_lentille.gdshader : le décor qui ondule). Voir SCRIPT/SHADER/cri_rond.gd,
// qui donne les mêmes valeurs aux deux.
// Les ondes partent du centre à `cadence` par seconde et filent à `vitesse` :
// l'onde n° k a pour rayon  vitesse × temps + k × pas  (pas = vitesse / cadence),
// elle est donc NÉE à l'instant −k / cadence. Elle n'existe que si elle est née
// pendant le cri, entre 0 et `fin` : au départ les ondes sortent de la gueule
// une à une, à l'arrêt les dernières finissent leur course. C'est ce qui permet
// de faire DURER le cri autant qu'on veut.

uniform vec2 taille = vec2(1168.0, 1168.0);
uniform vec2 centre = vec2(584.0, 584.0);
uniform float rayon = 560.0;                     // jusqu'où portent les ondes (px)
uniform float vitesse = 640.0;                   // px/s
uniform float cadence = 8.0;                     // ondes par seconde
uniform float temps = 0.0;                       // depuis le début du cri (s)
uniform float fin = 100000.0;                    // le cri s'est tu à… (très grand : il dure encore)
uniform float graine = 0.0;                      // une valeur par cri : deux cris ne se ressemblent pas
// l'ÉCLAT DU DÉPART file devant les autres ondes, à tant de fois leur vitesse
// (posé par cri_rond.gd, qui s'en sert aussi pour dire où est le front du cri)
uniform float vitesse_eclat = 1.5;

// les ondes sont des ronds PRESQUE parfaits : leur rayon varie de ± tant (part
// du rayon, quatre ou cinq bosses par tour). Essayé plus fort (± 2 à 3 %) : les
// ronds se cabossaient, se touchaient presque, et on lisait une spirale
// gribouillée ; avec moins de bosses ils paraissaient décentrés l'un par
// rapport à l'autre…
const float IRREGULARITE = 0.011;
// … plus un tremblé fin (part du rayon), tiré à neuf à chaque tracé : la ligne vibre…
const float TREMBLE = 0.004;
// … et leur tracé est redessiné tant de fois par seconde, un peu différent
// (le « trait qui bout » des dessins animés, comme le halo des torches)
const float IMAGES_TRACE = 12.0;


// hasard ENTIER, exact (sans marches aux raccords)
float alea_u(uint n) {
	n = (n << 13u) ^ n;
	n = n * (n * n * 15731u + 789221u) + 1376312589u;
	return float(n & 2147483647u) / 2147483647.0;
}

float alea(float n) {
	return alea_u(uint(int(floor(n)) + 100000));
}

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

// le tracé à la main : de combien l'onde n° `n`, de rayon `r`, s'écarte du
// cercle parfait dans la direction `tour` (px). Ses grandes bosses changent un
// peu à chaque nouveau tracé (petits pas : ça bout, ça ne clignote pas) ; son
// tremblé fin, lui, est neuf à chaque tracé.
float bosse(vec2 tour, float n, float r) {
	float trace = floor(temps * IMAGES_TRACE);
	vec2 propre = vec2(alea(n * 2.0 + 7.0 + graine), alea(n * 2.0 + 8.0 + graine)) * 60.0;
	float large = bruit(tour * 1.5 + propre + trace * vec2(0.19, 0.13)) - 0.5;
	float fin_trait = bruit(tour * 3.4 + propre.yx + trace * vec2(1.7, 2.3)) - 0.5;
	return (large * IRREGULARITE + fin_trait * TREMBLE) * 2.0 * max(r, 100.0);
}

// tout sort de la gueule : rien au centre, les ronds naissent autour de la tête
float sortie(float r) {
	return smoothstep(26.0, 84.0, r);
}

// l'onde la plus proche du point `p` (depuis le centre) : son numéro `n` depuis
// le début du cri (0 = la première) et la distance `d` qui nous en sépare le
// long du rayon (px, > 0 : on est devant elle). Renvoie 1 si elle existe (née
// pendant le cri), 0 sinon.
float onde_proche(vec2 p, out float n, out float d) {
	float r = length(p);
	float pas = vitesse / max(cadence, 0.01);
	float f = (r - vitesse * temps) / pas;
	float k = floor(f + 0.5);
	n = -k;
	d = (f - k) * pas + bosse(p / max(r, 0.001), n, r);
	float naissance = n / max(cadence, 0.01);
	return step(-0.0001, naissance) * step(naissance, fin + 0.0001);
}

// le poids de chaque onde : une FORTE, puis une faible (son écho), et jamais
// deux tout à fait pareilles
float poids_onde(float n) {
	float echo = step(0.5, mod(n, 2.0));
	return mix(1.0, 0.62, echo) * (0.88 + 0.24 * alea(n * 3.0 + 51.0 + graine));
}

// l'ÉCLAT DU DÉPART : le cri éclate — une seule onde, plus grosse, qui file
// devant les autres. `d` : la distance qui nous en sépare (px) ; renvoie son
// avancement, 0 (elle part) → 1 (elle est au bout de la portée, éteinte).
float eclat_depart(vec2 p, out float d) {
	float r = length(p);
	d = r - vitesse * vitesse_eclat * temps + bosse(p / max(r, 0.001), -3.0, r);
	return clamp(vitesse * vitesse_eclat * temps / max(rayon, 1.0), 0.0, 1.0);
}
