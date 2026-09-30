shader_type canvas_item;
render_mode unshaded;
// GRIFFURE DU XENO — le coup de griffes du xeno, taillé sur son animation : une
// griffure par griffe, qui file le long de l'arc que sa main décrit. Même
// famille que impact_blanc (aplats nets, liseré d'encre, tout piloté par
// `progress`, des formes qui MAIGRISSENT au lieu de s'estomper) ; le liseré est
// du bleu nuit de sa peau.
//
// Repère : l'origine est le nœud (les pieds du xeno, qui regarde vers +x),
// l'unité le pixel. L'ARC du coup est donné par son centre, son rayon et ses
// deux angles ; les angles se lisent comme sur l'écran : 0° = droit devant,
// -90° = au-dessus, 90° = dessous, 180° = derrière. Chaque coup a son arc
// (le script en garde deux, un pour chaque temps du double coup).
//
// DEUX FORMES :
//   • les GRIFFURES — une par griffe, sur des arcs concentriques. Leur tête
//     file jusqu'au bout de l'arc en un instant, pointue ; leur queue suit plus
//     lentement et finit par la rattraper. Les griffes intérieures ont un rien
//     de retard : la main ne frappe pas à plat.
//   • le VOILE — le flou du geste : une bande translucide sous les griffures.

uniform float progress : hint_range(0.0, 1.0) = 0.0;

// --- fournis par griffure_xeno.gd à chaque image ----------------------------
// taille du rectangle (px) et place de l'origine du nœud dedans
uniform vec2 taille = vec2(360.0, 340.0);
uniform vec2 origine = vec2(0.3611, 0.9118);
// l'arc du coup : centre (px depuis le nœud), rayon de la griffe extérieure (px),
// angle de départ et angle d'arrivée (degrés)
uniform vec2 centre = vec2(30.0, -146.0);
uniform float rayon = 136.0;
uniform float angle_debut = -95.0;
uniform float angle_fin = 120.0;
// une valeur par coup : deux griffures ne se ressemblent pas tout à fait
uniform float graine = 0.0;
// ----------------------------------------------------------------------------

// nombre de griffes, et écart entre deux griffures (px)
uniform int nb_griffes : hint_range(1, 6) = 4;
uniform float ecart : hint_range(3.0, 30.0) = 13.0;
// demi-épaisseur d'une griffure à son plus large (px)
uniform float epaisseur : hint_range(1.0, 12.0) = 5.2;
// le flou du geste sous les griffures (0 = aucun)
uniform float voile : hint_range(0.0, 1.0) = 0.22;
// liseré autour du blanc (0 = aucun)
uniform float contour : hint_range(0.0, 1.0) = 0.5;
uniform vec4 couleur : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 couleur_contour : source_color = vec4(0.09, 0.11, 0.2, 1.0);

// (TAU est fourni par le langage de shader de Godot)

const int MAX_GRIFFES = 6;
// part de l'épaisseur d'une griffure que son liseré peut ajouter, au plus
const float PART_CONTOUR = 0.6;

// hash 1D sans sin : une valeur stable par griffe
float alea(float n) {
	n = fract(n * 0.1031);
	n *= n + 33.33;
	n *= n + n;
	return fract(n);
}


void fragment() {
	vec2 p = (UV - origine) * taille - centre;  // px, depuis le centre de l'arc
	float rho = length(p);
	float t = clamp(progress, 0.0, 1.0);
	// un pixel d'écran, en pixels du rectangle : des bords nets à toute échelle
	float px = length(vec2(dFdx(UV.y), dFdy(UV.y))) * taille.y * 1.5;
	float c = contour * 3.0;

	// où ce pixel se trouve le long du coup : 0 au départ, 1 à l'arrivée
	float balayage = radians(angle_fin - angle_debut);
	float sens = balayage < 0.0 ? -1.0 : 1.0;
	float s = mod(sens * (atan(p.y, p.x) - radians(angle_debut)), TAU) / max(abs(balayage), 0.001);

	// la tête file jusqu'au bout en un tiers du temps ; la queue la rattrape
	float tete = 1.0 - pow(1.0 - clamp(t / 0.34, 0.0, 1.0), 3.0);
	float queue = smoothstep(0.12, 0.85, t);
	float maigrir = 1.0 - t * t;                // tout maigrit, surtout vers la fin

	vec2 sd = vec2(-1.0e4);                     // x = le blanc, y = le blanc et son liseré
	float n = float(nb_griffes);
	for (int k = 0; k < MAX_GRIFFES; k++) {
		if (k >= nb_griffes) {
			break;
		}
		float fk = float(k);
		// les griffes intérieures partent un rien plus tard et vont un rien moins loin
		float retard = 0.04 * fk + 0.03 * alea(fk * 3.1 + graine);
		float tete_k = clamp(tete - retard, 0.0, 1.0) * (1.0 - 0.04 * fk);
		float queue_k = min(queue * (1.0 - 0.04 * fk), tete_k);
		float u = (s - queue_k) / max(tete_k - queue_k, 0.0001);
		if (u <= 0.0 || u >= 1.0) {
			continue;
		}
		// large aux trois quarts, pointue à la tête, effilée à la queue
		float demi = epaisseur * (1.0 - 0.12 * fk) * (0.85 + 0.3 * alea(fk * 5.7 + graine))
				* min(u / 0.74, (1.0 - u) / 0.26) * maigrir;
		float f = demi - abs(rho - (rayon - fk * ecart));
		sd = max(sd, vec2(f, f + min(c, demi * PART_CONTOUR)));
	}

	// le voile : toute la bande des griffes, entre la queue et la tête
	float u_v = (s - queue) / max(tete - queue, 0.0001);
	float milieu = rayon - (n - 1.0) * ecart * 0.5;
	float demi_v = ((n - 1.0) * ecart * 0.5 + epaisseur * 1.6) * min(u_v / 0.6, (1.0 - u_v) / 0.4);
	float a_v = (u_v > 0.0 && u_v < 1.0) ? smoothstep(0.0, px * 2.0, demi_v - abs(rho - milieu)) : 0.0;
	a_v *= voile * maigrir;

	float blanc = smoothstep(0.0, px, sd.x);
	float encre = smoothstep(0.0, px, sd.y);
	// le voile dessous, puis le liseré, puis le blanc des griffures
	vec3 rgb = mix(couleur_contour.rgb, couleur.rgb, blanc / max(encre, 0.0001));
	float a = encre + a_v * (1.0 - encre);
	rgb = (rgb * encre + couleur.rgb * a_v * (1.0 - encre)) / max(a, 0.0001);
	COLOR = vec4(rgb, couleur.a * a);
}
