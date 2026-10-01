shader_type canvas_item;
render_mode unshaded;
// ÉTOURDI (1er oct. 2026) — talisman « Parade » : trois petites étoiles
// tournent au-dessus de la tête d'un monstre sonné (BASE_IA.etourdir), sur une
// ellipse vue de 3/4 : celles qui passent DERRIÈRE la tête sont plus petites et
// plus sombres, et dessinées avant celles de devant. Étoiles blanches cernées
// d'encre, comme l'éclat d'un coup d'épée.
// Repère : des pixels, l'origine au milieu du rectangle (le centre de l'orbite).

// --- fournis par etourdi.gd --------------------------------------------------
uniform vec2 taille = vec2(150.0, 80.0);
uniform float temps = 0.0;
// 0 → 1 : elles apparaissent ; 1 → 0 : elles s'en vont
uniform float force : hint_range(0.0, 1.0) = 1.0;
// ----------------------------------------------------------------------------

uniform int nb_etoiles : hint_range(1, 5) = 3;
// l'orbite (px : demi-largeur, demi-hauteur) ; tours par seconde
uniform vec2 orbite = vec2(44.0, 11.0);
uniform float vitesse = 1.3;
// rayon d'une étoile (px : pointes, creux) — à 8,5 px elles ne se voyaient
// presque pas en jeu
uniform vec2 rayon = vec2(14.0, 5.5);
uniform float encre_px : hint_range(0.0, 4.0) = 2.2;
uniform vec4 couleur : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 couleur_derriere : source_color = vec4(0.62, 0.6, 0.66, 1.0);
uniform vec4 encre : source_color = vec4(0.05, 0.03, 0.06, 1.0);

const int NB_MAX = 5;

void par_dessus(inout vec3 rgb, inout float a, vec3 teinte, float f) {
	float total = f + a * (1.0 - f);
	rgb = (teinte * f + rgb * a * (1.0 - f)) / max(total, 0.0001);
	a = total;
}

// une étoile à 4 branches (positive dedans, en px) ; `tourne` : son angle
float etoile(vec2 q, float re, float ri, float tourne) {
	float ang = atan(q.y, q.x) + tourne;
	float secteur = TAU / 4.0;
	float x = abs(mod(ang, secteur) / secteur - 0.5) * 2.0;   // 1 sur une pointe, 0 entre deux
	float r = mix(ri, re, pow(x, 2.2));
	return r - length(q);
}

void fragment() {
	vec2 p = (UV - 0.5) * taille;
	vec3 rgb = couleur.rgb;
	float a = 0.0;
	float f = clamp(force, 0.0, 1.0);
	// deux passes : d'abord les étoiles de derrière, puis celles de devant
	for (int passe = 0; passe < 2; passe++) {
		for (int i = 0; i < NB_MAX; i++) {
			if (i >= nb_etoiles) {
				break;
			}
			float ang = temps * vitesse * TAU + float(i) * TAU / float(nb_etoiles);
			float devant = sin(ang);                   // > 0 : devant la tête
			if ((passe == 0) == (devant > 0.0)) {
				continue;
			}
			vec2 c = vec2(cos(ang) * orbite.x, devant * orbite.y);
			float s = mix(0.72, 1.0, smoothstep(-1.0, 1.0, devant)) * f;
			vec2 q = p - c;
			float d = etoile(q, rayon.x * s, rayon.y * s, temps * 3.0 + float(i));
			vec3 teinte = mix(couleur_derriere.rgb, couleur.rgb, smoothstep(-0.6, 0.6, devant));
			par_dessus(rgb, a, encre.rgb, smoothstep(-0.5, 0.5, d + encre_px * s) * f);
			par_dessus(rgb, a, teinte, smoothstep(-0.5, 0.5, d) * f);
		}
	}
	COLOR = vec4(rgb, a);
}
