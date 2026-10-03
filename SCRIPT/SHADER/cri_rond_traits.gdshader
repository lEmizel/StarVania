shader_type canvas_item;
render_mode unshaded;
// CRI EN ROND — LES RONDS (le cri continu d'un monstre : des ronds qui partent
// de sa gueule tant qu'il crie). Même famille que le souffle du dash et
// l'éclat d'impact : du blanc en aplat, des bords nets, des formes qui
// MAIGRISSENT au lieu de s'estomper.
//   • l'ÉCLAT DU DÉPART : le cri éclate — une onde plus grosse, d'un seul
//     tenant, qui file devant les autres ;
//   • les ONDES : des ronds qui sortent de la gueule l'un après l'autre tant
//     que le cri dure, une forte puis une faible (son écho). Chacune est un
//     ROND ENTIER tracé au pinceau (la pression varie le long du tour) qui
//     s'use en s'éloignant : il maigrit, ses parties fines lâchent les
//     premières, et il se défait en arcs effilés de plus en plus courts.
//     Tracées à la main : jamais tout à fait rondes, leur ligne tremble et
//     leur tracé bout.
// Essais écartés en regardant le rendu : trois coups de pinceau séparés par
// onde (on lisait un moulinet de croissants, plus des ronds) ; des traits de
// force effilés qui filaient entre les ondes (des aiguilles en travers des
// ronds : hérissé, comme des reflets).
// Le décor qui ondule est l'autre couche (cri_rond_lentille). Repère : `centre`
// = la gueule, dans le rectangle (px). Tout est posé par SCRIPT/SHADER/cri_rond.gd.

#include "res://SCRIPT/SHADER/cri_rond.gdshaderinc"

uniform float epaisseur = 16.0;                  // l'épaisseur des ronds les plus forts (px)
uniform vec4 couleur : source_color = vec4(1.0, 1.0, 1.0, 1.0);


void fragment() {
	vec2 pix = UV * taille;
	vec2 p = pix - centre;
	float r = length(p);
	float ang = atan(p.y, p.x);
	// un pixel d'écran, en px du rectangle : des bords nets à toute échelle
	float px = length(vec2(dFdx(pix.x), dFdy(pix.x))) * 1.5;
	float sd = -1.0;
	float gueule = sortie(r);

	// ===================== L'ÉCLAT DU DÉPART =====================
	float d_e;
	float avance = eclat_depart(p, d_e);
	if (avance < 1.0) {
		// tracé au pinceau : la pression varie le long du tour
		float pression = 0.74 + 0.26 * sin(ang * 3.0 + graine * 1.7);
		float demi_e = 0.5 * epaisseur * 1.5 * gueule * (1.0 - pow(avance, 3.0)) * pression;
		sd = max(sd, demi_e - abs(d_e));
	}

	// ===================== LES ONDES =====================
	float n;
	float d;
	if (onde_proche(p, n, d) > 0.5) {
		float echo = step(0.5, mod(n, 2.0));
		// tracée au pinceau, d'un seul geste : la pression varie le long du tour
		// (2 à 4 appuis par onde, jamais aux mêmes endroits)
		float appuis = 2.0 + floor(alea(n * 5.0 + 21.0 + graine) * 3.0);
		float phi_1 = alea(n * 5.0 + 22.0 + graine) * TAU;
		float phi_2 = alea(n * 5.0 + 23.0 + graine) * TAU;
		float pression = 0.74 + 0.26 * sin(ang * appuis + phi_1) + 0.08 * sin(ang * (appuis + 3.0) + phi_2);
		// elle s'USE en s'éloignant : elle maigrit, et ses parties fines lâchent
		// les premières — le rond se défait en arcs effilés, de plus en plus courts
		float loin = clamp((r - rayon * 0.25) / (rayon * 0.75), 0.0, 1.0);
		float usure = 1.12 * pow(loin, 2.4) * mix(1.0, 1.2, echo);
		float demi = 0.5 * epaisseur * poids_onde(n) * gueule * (pression - usure);
		sd = max(sd, demi - abs(d));
	}

	// rien ne touche le bord du rectangle
	float bord = min(min(pix.x, taille.x - pix.x), min(pix.y, taille.y - pix.y));
	COLOR = vec4(couleur.rgb, couleur.a * smoothstep(0.0, px, sd) * smoothstep(0.0, 6.0, bord));
}
