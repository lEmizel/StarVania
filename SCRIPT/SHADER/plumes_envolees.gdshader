shader_type canvas_item;
render_mode unshaded;
// PLUMES ENVOLÉES — ce que le coup d'aile du double saut laisse DERRIÈRE lui,
// là où il a été donné (le joueur, lui, est déjà parti vers le haut) :
//   • le SOUFFLE — l'air chassé vers le bas : deux arcs clairs en forme de
//     creux, qui descendent en s'élargissant et s'éteignent vite. C'est
//     l'impulsion du double saut ;
//   • les PLUMES — quelques plumes arrachées par le coup, chassées vers le bas
//     puis qui planent en se balançant, avant de maigrir et de disparaître.
// Même famille que aile_double_saut (mêmes plumes à liseré, peintes l'une
// par-dessus l'autre).
//
// Repère : l'origine est la racine de l'aile AU MOMENT DU COUP, le perso
// regardait vers +x ; l'unité est la HAUTEUR du rectangle, y positif = le bas.

uniform float progress : hint_range(0.0, 1.0) = 0.0;

// --- fournis par aile_double_saut.gd à chaque image -------------------------
uniform float aspect = 0.8421;
uniform vec2 origine = vec2(0.625, 0.2895);
uniform float graine = 0.0;
// ----------------------------------------------------------------------------

// nombre de plumes arrachées (0 = aucune)
uniform int nb_plumes : hint_range(0, 10) = 5;
// longueur d'une plume (1 = une hauteur de rectangle)
uniform float taille_plume : hint_range(0.03, 0.3) = 0.11;
// de combien elles descendent en tout
uniform float chute : hint_range(0.0, 1.0) = 0.5;
// 0 = elles tombent droit, 1 = elles se balancent franchement
uniform float balancement : hint_range(0.0, 1.0) = 0.5;
// le souffle d'air sous l'aile (0 = aucun)
uniform float souffle : hint_range(0.0, 1.0) = 0.8;
// liseré des plumes (0 = aucun)
uniform float contour : hint_range(0.0, 1.0) = 0.5;
uniform vec4 couleur : source_color = vec4(0.647, 0.159, 0.236, 1.0);
uniform vec4 couleur_contour : source_color = vec4(0.207, 0.072, 0.111, 1.0);
uniform vec4 couleur_souffle : source_color = vec4(1.0, 0.9, 0.88, 1.0);

// (PI et TAU sont fournis par le langage de shader de Godot)

const int MAX_PLUMES = 10;
const float PART_CONTOUR = 0.5;

// hash 1D sans sin : une valeur stable par plume
float alea(float n) {
	n = fract(n * 0.1031);
	n *= n + 33.33;
	n *= n + n;
	return fract(n);
}

// La même PLUME que dans aile_double_saut : plantée à l'origine de `e`, d'angle
// `phi` (0 = vers le haut, en tournant vers -x), longue de `l`, large de `demi`,
// dont `depart` (0 → 1) est déjà parti depuis la racine. Renvoie deux
// distances, positives dedans : (la plume, la plume épaissie de son liseré).
vec2 plume(vec2 e, float phi, float l, float demi, float depart, float c) {
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
	return vec2(large, large + min(c, large * PART_CONTOUR)) - abs(dot(e, travers) - 0.18 * l * s * s);
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
	float c = contour * 0.009;

	vec3 rgb = couleur_souffle.rgb;
	float a = 0.0;

	// 1) LE SOUFFLE : deux creux d'air sous l'aile, l'un après l'autre. Chacun
	// descend vite puis freine, s'élargit, et son trait s'affine jusqu'à rien.
	for (int k = 0; k < 2; k++) {
		float fk = float(k);
		float retard = 0.03 + 0.07 * fk;
		float tk = clamp((t - retard) / 0.34, 0.0, 1.0);
		float pk = 1.0 - (1.0 - tk) * (1.0 - tk);
		float demi_l = mix(0.11, 0.27, pk) * (1.0 - 0.25 * fk);     // demi-largeur du creux
		float dx = (p.x + 0.10) / demi_l;                          // centré sous l'aile, derrière le perso
		// le milieu du creux est le plus bas ; ses bords remontent
		float y_arc = 0.07 + 0.40 * pk - 0.10 * fk - 0.38 * demi_l * dx * dx;
		float demi = souffle * 0.016 * (1.0 - dx * dx) * (1.0 - tk * tk) * (1.0 - 0.3 * fk)
				* step(retard + 0.0001, t) * step(abs(dx), 1.0);
		par_dessus(rgb, a, couleur_souffle.rgb, smoothstep(0.0, px, demi - abs(p.y - y_arc)));
	}

	// 2) LES PLUMES
	for (int i = 0; i < MAX_PLUMES; i++) {
		if (i >= nb_plumes) {
			break;
		}
		float fi = float(i);
		float h1 = alea(fi * 1.7 + graine);
		float h2 = alea(fi * 3.1 + graine * 1.3 + 5.0);
		float h3 = alea(fi * 5.3 + graine * 0.7 + 9.0);
		float h4 = alea(fi * 7.9 + graine * 2.1 + 3.0);
		float h5 = alea(fi * 9.7 + graine * 0.9 + 1.0);
		// chacune part à son instant et vit sa durée
		float depart_t = 0.04 + 0.22 * h3;
		float vie = 0.55 + 0.38 * h4;
		float r = clamp((t - depart_t) / vie, 0.0, 1.0);
		if (t < depart_t || r >= 1.0) {
			continue;
		}
		// arrachée dans la zone que l'aile vient de balayer
		vec2 pos = vec2(mix(-0.30, 0.0, h1), mix(-0.20, 0.10, h2));
		// chassée vers le bas par le coup, puis elle plane : vite d'abord, lente ensuite
		pos.y += chute * (0.45 + 0.55 * h5) * (1.0 - (1.0 - r) * (1.0 - r));
		float phase = r * (5.0 + 3.0 * h5) + h2 * TAU;
		pos.x += balancement * 0.07 * sin(phase) * sqrt(r);
		float phi = h1 * TAU + balancement * 1.1 * sin(phase + 1.2);
		// à la fin elle décolle de sa base et maigrit
		float part = smoothstep(0.6, 1.0, r);
		float l = taille_plume * (0.7 + 0.5 * h5);
		vec2 d = plume(p - pos, phi, l, l * 0.17 * (1.0 - part * part), 0.6 * part, c);
		par_dessus(rgb, a, couleur_contour.rgb, smoothstep(0.0, px, d.y));
		par_dessus(rgb, a, couleur.rgb, smoothstep(0.0, px, d.x));
	}
	COLOR = vec4(rgb, couleur.a * a);
}
