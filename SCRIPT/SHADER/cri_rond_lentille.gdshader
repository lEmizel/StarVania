shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;
// CRI EN ROND — LA LENTILLE (le cri continu d'un monstre). Cette couche fait
// ONDULER LE DÉCOR au passage de chaque onde : elle lit l'écran et le tord le
// long du rayon (l'air comprimé qui passe), comme la lentille du trou noir.
// Elle se dessine au niveau du décor (z −1, juste après une copie d'écran
// fraîche — nœud « Copie ») : le monstre et le héros, devant, restent nets.
// Les ronds tracés au pinceau sont l'autre couche (cri_rond_traits).
// Tout est posé par SCRIPT/SHADER/cri_rond.gd.

#include "res://SCRIPT/SHADER/cri_rond.gdshaderinc"

uniform sampler2D ecran : hint_screen_texture, filter_linear;
uniform float deformation = 12.0;                // de combien le décor est tordu au passage d'une onde (px)

// l'épaisseur de la bande d'air tordue autour de chaque onde (px)
const float LARGEUR_ONDE = 18.0;


// le profil d'une onde : le décor s'étire de part et d'autre de sa crête
// (−1 juste derrière, +1 juste devant, 0 dessus et au loin)
float profil(float d, float largeur) {
	float x = d / largeur;
	return x * exp(-x * x) * 2.33;
}

void fragment() {
	vec2 pix = UV * taille;
	vec2 p = pix - centre;
	float r = length(p);
	vec2 dir = p / max(r, 0.001);
	// elle sort de la gueule, et s'éteint avant le bout de sa portée
	float gueule = sortie(r);
	float n;
	float d;
	float existe = onde_proche(p, n, d);
	float dev = profil(d, LARGEUR_ONDE) * existe * poids_onde(n)
			* gueule * (1.0 - smoothstep(rayon * 0.45, rayon, r));
	// l'éclat du départ tord plus fort, et plus large
	float d_e;
	float avance = eclat_depart(p, d_e);
	dev += profil(d_e, LARGEUR_ONDE * 1.5) * 1.8 * gueule * (1.0 - avance) * step(avance, 0.999);
	dev *= deformation;
	// le déplacement, du repère du nœud à celui de l'écran (le monstre peut être
	// retourné : scale.x = −1)
	vec2 dl = dir * dev;
	vec2 jx = dFdx(pix);
	vec2 jy = dFdy(pix);
	float det = jx.x * jy.y - jy.x * jx.y;
	vec2 ds = vec2(dl.x * jy.y - dl.y * jy.x, dl.y * jx.x - dl.x * jx.y) / (abs(det) > 0.000001 ? det : 1.0);
	vec3 fond = texture(ecran, SCREEN_UV - ds * SCREEN_PIXEL_SIZE).rgb;
	// on ne redessine l'écran que là où il est tordu
	float a = smoothstep(0.0, 0.6, abs(dev));
	// rien ne touche le bord du rectangle
	float bord = min(min(pix.x, taille.x - pix.x), min(pix.y, taille.y - pix.y));
	a *= smoothstep(0.0, 12.0, bord);
	COLOR = vec4(fond * a, a);
}
