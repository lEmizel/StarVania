shader_type canvas_item;

// Flash de degats : 0.0 = sprite normal, 1.0 = entierement blanc.
// Pilote par code (BASE_IA) via set_shader_parameter.
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// Teinte d'etat (1er oct. 2026), MULTIPLIEE : les traits d'encre restent
// noirs, le clair prend la couleur ; 0 = aucune. Pilotee par BASE_IA.teinter :
// le poison du talisman "Sang corrompu" fait virer le monstre au violet.
uniform vec4 teinte_couleur : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float teinte_force : hint_range(0.0, 1.0) = 0.0;
// FISSURES (1er oct. 2026, talisman "Coup de grace") : un monstre a portee
// d'execution se fissure de rouge ; 0 = aucune (BASE_IA les fait battre).
// Dessinees dans le repere LOCAL du sprite (px) : elles suivent le monstre sans
// sauter d'une image d'animation a l'autre. Seulement une partie des bords de
// cellules (un bruit les choisit) : des fissures, pas un carrelage.
uniform float fissure : hint_range(0.0, 1.0) = 0.0;
uniform vec4 fissure_couleur : source_color = vec4(0.92, 0.07, 0.1, 1.0);
uniform float fissure_taille = 20.0;
// CRISTAL (1er oct. 2026, talisman "Sang cristallise") : le monstre fige
// devient une STATUE de cristal de sang — ses tons sont remplaces par une rampe
// de rouges (l'encre reste noire), des aretes de facettes plus claires, et un
// reflet qui passe en diagonale. Sobre : rien ne deborde de sa silhouette.
// v2 : une rampe de rubis et une NUANCE PAR FACETTE (chaque cellule plus ou
// moins claire) — en v1, une seule rampe vers le rose clair : un squelette
// peint en saumon, pas du cristal.
uniform float cristal : hint_range(0.0, 1.0) = 0.0;
uniform vec4 cristal_sombre : source_color = vec4(0.3, 0.01, 0.07, 1.0);
uniform vec4 cristal_rubis : source_color = vec4(0.82, 0.07, 0.17, 1.0);
uniform vec4 cristal_clair : source_color = vec4(1.0, 0.5, 0.56, 1.0);
uniform float cristal_facettes = 14.0;

varying vec2 local;

void vertex() {
	local = VERTEX;
}

vec2 hachis2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

float bruit(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hachis2(i).x, hachis2(i + vec2(1.0, 0.0)).x, u.x),
			mix(hachis2(i + vec2(0.0, 1.0)).x, hachis2(i + vec2(1.0, 1.0)).x, u.x), u.y);
}

// la facette (cellule de Voronoi la plus proche) : un nombre au hasard par facette
float facette(vec2 x) {
	vec2 n = floor(x);
	vec2 f = fract(x);
	float md = 8.0;
	vec2 meilleure = n;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 r = g + hachis2(n + g) - f;
			float d = dot(r, r);
			if (d < md) {
				md = d;
				meilleure = n + g;
			}
		}
	}
	return hachis2(meilleure + vec2(7.3, 1.1)).x;
}

// distance au bord de cellule de Voronoi le plus proche (en cellules)
float bord_voronoi(vec2 x) {
	vec2 n = floor(x);
	vec2 f = fract(x);
	vec2 mg = vec2(0.0);
	vec2 mr = vec2(0.0);
	float md = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 r = g + hachis2(n + g) - f;
			float d = dot(r, r);
			if (d < md) {
				md = d;
				mr = r;
				mg = g;
			}
		}
	}
	md = 8.0;
	for (int j = -2; j <= 2; j++) {
		for (int i = -2; i <= 2; i++) {
			vec2 g = mg + vec2(float(i), float(j));
			vec2 r = g + hachis2(n + g) - f;
			if (dot(mr - r, mr - r) > 0.00001) {
				md = min(md, dot(0.5 * (mr + r), normalize(r - mr)));
			}
		}
	}
	return md;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec3 rgb = mix(tex.rgb, tex.rgb * teinte_couleur.rgb, teinte_force);
	if (fissure > 0.0) {
		vec2 x = local / fissure_taille;
		float b = bord_voronoi(x);
		float trait_f = 1.0 - smoothstep(0.025, 0.06, b);
		float masque = smoothstep(0.38, 0.5, bruit(x * 0.45 + vec2(5.3, 1.9)));
		rgb = mix(rgb, fissure_couleur.rgb, trait_f * masque * fissure * step(0.5, tex.a));
	}
	if (cristal > 0.0) {
		float l = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
		vec2 xf = local / cristal_facettes + vec2(11.0, 3.0);
		// la lumière du dessin, nuancée facette par facette
		float t = clamp(smoothstep(0.1, 0.95, l) * mix(0.62, 1.12, facette(xf)), 0.0, 1.0);
		vec3 c = mix(cristal_sombre.rgb, cristal_rubis.rgb, smoothstep(0.0, 0.62, t));
		c = mix(c, cristal_clair.rgb, smoothstep(0.8, 1.0, t) * 0.8);
		// les arêtes des facettes, plus claires
		float b = bord_voronoi(xf);
		c = mix(c, cristal_clair.rgb, (1.0 - smoothstep(0.02, 0.06, b)) * 0.55);
		// un reflet qui passe en diagonale
		float bande = abs(fract((local.x + local.y) / 140.0 - TIME * 0.45) - 0.5);
		c = mix(c, cristal_clair.rgb, (1.0 - smoothstep(0.04, 0.1, bande)) * 0.6);
		// l'encre reste noire
		c = mix(tex.rgb, c, smoothstep(0.05, 0.16, l));
		rgb = mix(rgb, c, cristal);
	}
	COLOR = vec4(mix(rgb, flash_color.rgb, flash_amount), tex.a);
}
