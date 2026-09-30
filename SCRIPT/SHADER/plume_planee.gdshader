shader_type canvas_item;
render_mode unshaded;
// PLUME PLANÉE (1er oct. 2026) — une plume que l'aile de PLANÉ perd en route.
// Détachée là où elle était sur l'aile, dans le même sens, elle reste en
// arrière pendant que le joueur file et descend doucement — moins vite que lui
// — en se balançant comme une feuille morte (elle penche du côté où elle
// glisse et remonte un peu au bout de chaque glissade), puis elle décolle de
// sa base et maigrit jusqu'à rien. La même plume à liseré que aile_double_saut
// et plumes_envolees ; ses couleurs sont copiées de l'aile par le script.
//
// Repère : l'origine est le point où elle s'est détachée ; l'unité est la
// HAUTEUR du rectangle, y positif = le bas ; les angles comme sur l'aile
// (0 = vers le haut, en tournant vers -x, le dos du perso).

uniform float progress : hint_range(0.0, 1.0) = 0.0;

// --- fournis par plume_planee.gd -------------------------------------------
uniform float aspect = 0.6667;
uniform vec2 origine = vec2(0.5, 0.2667);
uniform float graine = 0.0;
// l'angle qu'elle avait sur l'aile au moment de se détacher (radians)
uniform float angle_depart = 1.0;
// ----------------------------------------------------------------------------

// longueur de la plume (1 = une hauteur de rectangle)
uniform float taille_plume : hint_range(0.03, 0.4) = 0.15;
// de combien elle descend en tout (1 = une hauteur de rectangle)
uniform float chute : hint_range(0.0, 1.0) = 0.3;
// 0 = elle tombe droit, 1 = elle se balance franchement
uniform float balancement : hint_range(0.0, 1.0) = 0.6;
// liseré (0 = aucun)
uniform float contour : hint_range(0.0, 1.0) = 0.5;
uniform vec4 couleur : source_color = vec4(0.647, 0.159, 0.236, 1.0);
uniform vec4 couleur_contour : source_color = vec4(0.207, 0.072, 0.111, 1.0);

// (PI et TAU sont fournis par le langage de shader de Godot)

// part de la largeur d'une plume que son liseré peut ajouter, au plus
const float PART_CONTOUR = 0.5;

// hash 1D sans sin
float alea(float n) {
	n = fract(n * 0.1031);
	n *= n + 33.33;
	n *= n + n;
	return fract(n);
}

// La même PLUME que dans aile_double_saut : plantée à l'origine de `e`, d'angle
// `phi`, longue de `l`, large de `demi`, pliée de `cambre`, dont `depart`
// (0 → 1) est déjà parti depuis la base. Renvoie deux distances, positives
// dedans : (la plume, la plume épaissie de son liseré).
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
	float r = clamp(progress, 0.0, 1.0);
	// un pixel d'écran, en hauteurs de rectangle : des bords nets à toute échelle
	float px = length(vec2(dFdx(UV.y), dFdy(UV.y))) * 1.5;
	float c = contour * 0.011;
	float h1 = alea(graine * 1.7 + 3.0);
	float h2 = alea(graine * 3.1 + 7.0);

	// elle descend tout de suite, mais doucement, puis un peu plus vite
	vec2 pos = vec2(0.0, chute * r * (0.55 + 0.45 * r));
	// le balancement de feuille morte : une glissade d'un côté, puis de
	// l'autre, de plus en plus large ; elle penche du côté où elle glisse et
	// remonte un peu au bout de chaque glissade
	float phase = r * (6.0 + 2.0 * h1) + h2 * TAU;
	float ampl = balancement * 0.09 * smoothstep(0.0, 0.35, r);
	pos.x += ampl * sin(phase);
	pos.y -= ampl * 0.35 * abs(cos(phase));
	float phi = angle_depart + balancement * 0.9 * smoothstep(0.0, 0.3, r) * cos(phase)
			+ (h1 - 0.5) * 0.8 * r;
	// à la fin elle décolle de sa base et maigrit
	float part = smoothstep(0.62, 1.0, r);
	float l = taille_plume * (0.85 + 0.3 * h2);
	vec2 d = plume(p - pos, phi, l, l * 0.17 * (1.0 - part * part), 0.2, 0.6 * part, c);

	vec3 rgb = couleur.rgb;
	float a = 0.0;
	par_dessus(rgb, a, couleur_contour.rgb, smoothstep(0.0, px, d.y));
	par_dessus(rgb, a, couleur.rgb, smoothstep(0.0, px, d.x));
	COLOR = vec4(rgb, couleur.a * a);
}
