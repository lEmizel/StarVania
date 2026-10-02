shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;
// FAILLE ÉTOILÉE (2 oct. 2026, piège « pluie d'étoiles » choisi par Kaoru) —
// une déchirure dans le ciel, au-dessus de la zone, d'où tombent les comètes.
// Une fente en amande aux bords irréguliers, un ciel de nuit violet profond
// dedans où scintillent des étoiles, un liseré or-blanc qui vibre, une lueur
// autour. `eveil` (0 → 1) : elle s'ouvre du centre vers les bouts ; `eclat` :
// un éclair à l'endroit (`eclat_x`) d'où vient de partir une comète.
// Piloté par SCRIPT/INTERACTIBLE/pluie_etoiles.gd.

uniform vec2 taille = vec2(1100.0, 180.0);
uniform float longueur = 900.0;                 // la fente, d'un bout à l'autre (px)
uniform float eveil : hint_range(0.0, 1.0) = 1.0;
uniform float eclat : hint_range(0.0, 1.0) = 0.0;
uniform float eclat_x = 0.0;                    // depuis le milieu de la fente (px)
uniform float temps = 0.0;
uniform float graine = 0.0;
uniform float epaisseur = 16.0;                 // la demi-ouverture au milieu (px)

uniform vec4 couleur_bord : source_color = vec4(1.0, 0.9, 0.62, 1.0);
uniform vec4 couleur_nuit : source_color = vec4(0.1, 0.05, 0.22, 1.0);
uniform vec4 couleur_nebuleuse : source_color = vec4(0.45, 0.22, 0.75, 1.0);
uniform vec4 couleur_lueur : source_color = vec4(0.62, 0.48, 1.0, 1.0);


float alea(vec2 c) {
	return fract(sin(dot(c, vec2(127.1, 311.7)) + graine) * 43758.5453);
}

// un hasard ENTIER, exact : deux appels sur le même entier rendent la même
// valeur au bit près. Le hasard flottant « fract(sin(n) × 43758) » d'avant ne
// tombait pas pareil au même nœud calculé depuis sa gauche ou sa droite une
// fois compilé : l'épaisseur de la fente et sa nébuleuse SAUTAIENT d'un coup,
// une coupure verticale nette dans la faille (vue par Kaoru), de plus en plus
// probable avec le temps qui grandit. Même piège que le pilier de foudre.
float alea_u(uint n) {
	n = (n << 13u) ^ n;
	n = n * (n * n * 15731u + 789221u) + 1376312589u;
	return float(n & 2147483647u) / 2147483647.0;
}

// un bruit doux : une valeur au hasard à chaque entier, raccordées en douceur
float bruit(float x) {
	float fi = floor(x);
	uint i = uint(int(fi) + 4096);
	uint s = uint(int(graine * 97.0)) * 1013u;
	float a = alea_u(i * 7919u + s);
	float b = alea_u((i + 1u) * 7919u + s);
	float f = x - fi;
	return mix(a, b, f * f * (3.0 - 2.0 * f));
}

void fragment() {
	vec2 p = UV * taille - taille * 0.5;
	float ouvert = smoothstep(0.0, 1.0, eveil);
	float demi = max(longueur * 0.5 * ouvert, 1.0);
	float u = p.x / demi;
	// la fente : une amande, son milieu qui serpente, ses bords irréguliers
	float milieu = 4.0 * sin(p.x * 0.012 + graine) + 2.5 * sin(p.x * 0.041 + graine * 1.7);
	float ep = epaisseur * max(1.0 - u * u, 0.0) * ouvert;
	ep *= 0.7 + 0.45 * bruit(p.x * 0.05 + temps * 0.6);
	float d = abs(p.y - milieu) - ep;            // < 0 dedans
	float dans_fente = step(abs(u), 1.0);
	float px = max(fwidth(p.x), 0.001);

	// le ciel de nuit dedans, une nébuleuse qui ondule, des étoiles qui scintillent
	float a = clamp(0.5 - d / px, 0.0, 1.0) * dans_fente;
	vec3 nuit = mix(couleur_nuit.rgb, couleur_nebuleuse.rgb,
			0.35 * bruit(p.x * 0.02 + temps * 0.4) * bruit(p.y * 0.1 + p.x * 0.01 - temps * 0.3));
	vec2 cel = floor(p / 7.0);
	float h = alea(cel);
	vec2 dans_cel = fract(p / 7.0) - 0.5;
	float etoile = step(0.88, h) * exp(-dot(dans_cel, dans_cel) * 40.0)
			* (0.5 + 0.5 * sin(temps * (3.0 + 6.0 * h) + h * 30.0));
	nuit += vec3(1.0, 0.95, 0.85) * etoile * 1.4;

	// le liseré qui vibre, et la lueur autour
	vec3 lum = vec3(0.0);
	float lisere = exp(-pow(abs(d / 1.8), 2.0)) * dans_fente * (0.8 + 0.2 * sin(temps * 9.0 + p.x * 0.05));
	lum += couleur_bord.rgb * lisere * 1.3 * ouvert;
	float lueur = exp(-max(d, 0.0) / 22.0) * max(1.0 - u * u, 0.0) * 0.35 * ouvert;
	lum += couleur_lueur.rgb * lueur;
	// une comète vient de partir : un éclair à cet endroit
	float e = exp(-pow(abs((p.x - eclat_x) / 38.0), 2.0)) * exp(-pow(abs((p.y - milieu) / 26.0), 2.0)) * eclat;
	lum += couleur_bord.rgb * e * 1.6;

	// rien ne touche le bord du rectangle
	vec2 pix = UV * taille;
	float bord = min(min(pix.x, taille.x - pix.x), min(pix.y, taille.y - pix.y));
	float garde = smoothstep(0.0, 14.0, bord);
	a *= garde * 0.95;
	lum *= garde;
	COLOR = vec4(nuit * a + lum, a);
}
