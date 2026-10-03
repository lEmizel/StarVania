shader_type canvas_item;
render_mode unshaded;
// MAILLON DE CHAÎNE (3 oct. 2026) — un maillon de la LAME À CHAÎNE
// (SCRIPT/INTERACTIBLE/lame_chaine.gd), en fer, style décor sans contour.
// Les maillons alternent : de FACE (un anneau ovale) et de PROFIL (une barre),
// comme une vraie chaîne. Le rectangle est allongé dans le sens de la chaîne.
// `profil` = 2 : le CAPUCHON rond de l'axe, posé sur le départ de la chaîne.
// EN APLAT, deux tons de fer, SANS OMBRAGE (Kaoru, sur une capture : « retirer
// l'ombrage de la chaîne pour retirer son côté 3D » — la v1 bombait chaque
// maillon comme un tore éclairé, avec des taches de rouille) : les maillons de
// face sont sombres, ceux de profil un ton plus clair, on lit l'emboîtement.

uniform vec2 taille = vec2(34.0, 18.0);
uniform float profil = 0.0;                      // 0 = de face (anneau), 1 = de profil (barre), 2 = capuchon de l'axe
uniform vec4 fer : source_color = vec4(0.29, 0.33, 0.36, 1.0);
uniform vec4 fer_clair : source_color = vec4(0.42, 0.46, 0.49, 1.0);


float couvre(float d, float px) {
	return clamp(0.5 - d / px, 0.0, 1.0);
}

void fragment() {
	vec2 pix = UV * taille;
	// la taille d'un pixel d'écran, quel que soit l'angle de la chaîne
	float px = max(length(vec2(dFdx(pix.x), dFdy(pix.x))), 0.001);
	vec2 p = pix - taille * 0.5;
	float a = taille.x * 0.5 - 1.5;                   // demi-longueur
	float b = taille.y * 0.5 - 1.5;                   // demi-largeur
	vec3 col = fer.rgb;
	float cov;
	if (profil < 0.5) {
		// DE FACE : un anneau ovale (ellipse extérieure moins ellipse intérieure)
		float e = 3.2;                                  // épaisseur du fer
		float d_ext = (length(p / vec2(a, b)) - 1.0) * min(a, b);
		float d_int = (1.0 - length(p / vec2(max(a - e, 1.0), max(b - e, 1.0)))) * min(a - e, b - e);
		cov = couvre(max(d_ext, d_int), px);
	} else if (profil < 1.5) {
		// DE PROFIL : une barre arrondie (le maillon vu par la tranche), un ton plus clair
		float r = 2.6;
		cov = couvre(length(p - vec2(clamp(p.x, -a + r, a - r), 0.0)) - r, px);
		col = fer_clair.rgb;
	} else {
		// LE CAPUCHON DE L'AXE : un disque, son boulon au milieu
		float r = min(a, b);
		cov = couvre(length(p) - r, px);
		col = mix(fer.rgb, fer_clair.rgb, couvre(length(p) - r * 0.42, px));
	}
	COLOR = vec4(col, cov);
}
