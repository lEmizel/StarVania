shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;
// LE REGARD (6 oct. 2026) — attaque de boss, phase 2 : ses yeux ouverts VISENT
// le héros (un fil de lumière suit son cœur), le fil SE FIGE, puis un RAYON
// part de ses yeux le long du fil, jusqu'au premier mur ou au sol.
// regard_rose.gd donne l'origine (ses yeux), la direction, la longueur et
// l'heure ; tout se dessine ici, sans particules.
//   • LA VISÉE : un fil pointillé qui court des yeux vers la cible, une lueur
//     dans les yeux ;
//   • LE FIL FIGÉ : plein, plus clair, qui bat vite — le temps de sortir de la
//     ligne ;
//   • LE RAYON : un trait de lumière, cœur presque blanc, corps rose, halo ;
//     un éclat au départ, une gerbe là où il frappe ; il s'éteint en se
//     resserrant.
// Repère : celui du nœud, l'origine sur ses yeux (px).

uniform vec2 taille = vec2(5800.0, 5800.0);
uniform vec2 origine_rect = vec2(-2900.0, -2900.0);
// la direction du fil (unitaire) et sa longueur (px) ; la cible, pour la lueur du bout
uniform vec2 direction = vec2(1.0, 0.0);
uniform float longueur = 1000.0;
// 0 : la visée ; 1 : le fil figé ; 2 : le rayon ; 3 : rien
uniform int phase = 3;
// le temps depuis le début de cette phase (s)
uniform float temps = 0.0;
// la largeur du rayon (px, tout ce qui blesse)
uniform float largeur = 56.0;
uniform float graine = 0.0;

uniform vec4 couleur_coeur : source_color = vec4(1.0, 0.94, 0.99, 1.0);
uniform vec4 couleur_corps : source_color = vec4(0.98, 0.68, 0.87, 1.0);
uniform vec4 couleur_halo : source_color = vec4(0.95, 0.3, 0.62, 1.0);

const float DUREE_TIR = 0.4;

void fragment() {
	vec2 p = UV * taille + origine_rect;
	float t = clamp(dot(p, direction), 0.0, longueur);
	vec2 sur = direction * t;
	float d = length(p - sur);
	float r0 = length(p);
	float r1 = length(p - direction * longueur);
	if (phase >= 3 || (d > largeur * 3.0 + 60.0 && r0 > 220.0 && r1 > 220.0)) {
		discard;
	}
	vec3 rgb = vec3(0.0);
	float a = 0.0;
	vec3 lueur = vec3(0.0);
	// (le fil ne part pas de l'intérieur de sa tête)
	float depuis_les_yeux = smoothstep(18.0, 40.0, t);
	if (phase == 0) {
		// LA VISÉE : un fil pointillé qui court vers la cible
		float entree = smoothstep(0.0, 0.12, temps);
		float tirets = step(0.5, fract((t - temps * 700.0) / 44.0));
		float fil = (1.0 - smoothstep(1.2, 3.2, d)) * tirets * 0.55 * entree * depuis_les_yeux;
		lueur += mix(couleur_halo.rgb, couleur_coeur.rgb, 0.5) * fil;
		lueur += couleur_halo.rgb * exp(-d / 7.0) * 0.12 * entree * depuis_les_yeux;
		// les yeux qui s'allument
		lueur += couleur_halo.rgb * exp(-r0 / 16.0) * 0.6 * entree;
	} else if (phase == 1) {
		// LE FIL FIGÉ : plein, clair, il bat vite
		float bat = 0.7 + 0.3 * sin(temps * 42.0);
		float fil = (1.0 - smoothstep(1.6, 4.4, d)) * depuis_les_yeux;
		lueur += mix(couleur_corps.rgb, couleur_coeur.rgb, 0.6) * fil * bat;
		lueur += couleur_halo.rgb * exp(-d / 11.0) * 0.3 * bat * depuis_les_yeux;
		// ses yeux brillent fort
		lueur += mix(couleur_halo.rgb, couleur_coeur.rgb, 0.4) * exp(-r0 / 22.0) * (0.9 + 0.4 * bat);
		// la cible, marquée d'une étoile qui grossit
		float k = clamp(temps / 0.5, 0.0, 1.0);
		vec2 q = abs(p - direction * longueur);
		float etoile = max(exp(-q.x / (3.0 + 20.0 * k) - q.y / 2.5), exp(-q.y / (3.0 + 20.0 * k) - q.x / 2.5));
		lueur += mix(couleur_halo.rgb, couleur_coeur.rgb, 0.6) * etoile * 0.7 * bat;
	} else {
		// LE RAYON
		float k = clamp(temps / DUREE_TIR, 0.0, 1.0);
		float flash = exp(-temps / 0.05);
		float w = largeur * 0.5 * (1.0 - 0.7 * k) * (1.0 + 1.3 * flash);
		float coeur = (1.0 - smoothstep(w * 0.35, w * 0.8, d)) * (1.0 - k * k) * depuis_les_yeux;
		float corps = (1.0 - smoothstep(w * 0.8, w, d)) * (1.0 - k) * depuis_les_yeux;
		vec3 c = mix(couleur_corps.rgb, couleur_coeur.rgb, smoothstep(w * 0.6, 0.0, d));
		rgb = c * corps;
		a = corps;
		lueur += couleur_halo.rgb * exp(-d / (w * 1.6 + 6.0)) * 0.7 * (1.0 - k) * (1.0 - corps) * depuis_les_yeux;
		lueur += couleur_coeur.rgb * coeur * 0.5 * (1.0 - corps);
		// l'éclat du départ, dans ses yeux
		lueur += mix(couleur_halo.rgb, couleur_coeur.rgb, 0.6) * exp(-r0 / (30.0 + 40.0 * flash)) * (0.6 + 1.5 * flash) * (1.0 - k);
		// la gerbe là où il frappe : des rais qui s'écartent, puis s'éteignent
		vec2 v = p - direction * longueur;
		float ang = atan(v.y, v.x);
		float rais = 0.55 + 0.45 * cos(ang * 9.0 + graine);
		float gerbe = (1.0 - smoothstep(0.0, 40.0 + 110.0 * k, r1)) * (0.4 + 0.6 * rais) * (1.0 - k) * 0.9;
		lueur += mix(couleur_halo.rgb, couleur_coeur.rgb, 0.5 + 0.5 * flash) * gerbe;
	}
	COLOR = vec4(rgb + lueur * (1.0 - a), a);
}
