shader_type canvas_item;
render_mode unshaded;
// DESSIN DU TALISMAN « PLUMES ACÉRÉES » (menu START, 1er oct. 2026) —
// provisoire, en attendant le dessin de Kaoru.
// emplacement_talisman.gd le pose dans le rond et lui fournit `opacite`,
// `eveil` et `temps`.
// TOUT LE ROND est au dessin : un disque de nuit cerné d'un trait d'encre ; en
// haut à gauche, l'AILE rouge du double saut (cinq plumes en éventail) ; trois
// PLUMES ACÉRÉES en fondent vers le bas à droite, chacune suivie de son trait
// de vitesse. Les couleurs de l'aile. Pointé ou porté (`eveil`), les plumes
// filent et reviennent.
// À dessiner dans un CARRÉ : le disque le remplit.

// --- fournis par emplacement_talisman.gd (les mêmes pour tout dessin de talisman) ---
uniform float opacite : hint_range(0.0, 1.0) = 1.0;
uniform float eveil : hint_range(0.0, 1.0) = 0.0;
uniform float temps = 0.0;
// ----------------------------------------------------------------------------

uniform vec4 encre_color : source_color = vec4(0.1, 0.02, 0.04, 1.0);
uniform vec4 fond_color : source_color = vec4(0.06, 0.02, 0.04, 1.0);
uniform vec4 fond_centre : source_color = vec4(0.17, 0.03, 0.05, 1.0);
uniform float trait : hint_range(0.0, 0.1) = 0.045;
uniform vec4 couleur : source_color = vec4(0.647, 0.159, 0.236, 1.0);
uniform vec4 couleur_arriere : source_color = vec4(0.414, 0.044, 0.098, 1.0);
uniform vec4 couleur_contour : source_color = vec4(0.207, 0.072, 0.111, 1.0);

float disque(float d, float r, float px) {
	return smoothstep(r + px * 0.5, r - px * 0.5, d);
}

// une plume de la base `b`, dans la direction `u` (unitaire), longue de `l`,
// demi-large de `w` ; positive dedans
float plume(vec2 p, vec2 b, vec2 u, float l, float w) {
	vec2 q = p - b;
	float s = dot(q, u) / l;
	float v = dot(q, vec2(-u.y, u.x));
	float large = w * min(max(s, 0.0) / 0.55, sqrt(max(1.0 - s, 0.0) / 0.45));
	return min(large - abs(v), min(s, 1.0 - s) * l);
}

void forme(inout vec3 rgb, float d, vec3 teinte, float e, float px) {
	rgb = mix(rgb, couleur_contour.rgb, smoothstep(-px * 0.5, px * 0.5, d + e));
	rgb = mix(rgb, teinte, smoothstep(-px * 0.5, px * 0.5, d));
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float px = fwidth(UV.x) * 2.0;

	// ===================== LE DISQUE =====================
	vec3 rgb = encre_color.rgb;
	float a = disque(r, 1.0, px);
	rgb = mix(rgb, mix(fond_centre.rgb, fond_color.rgb, smoothstep(0.0, 0.95, r)),
			disque(r, 1.0 - trait, px));
	float dedans = (1.0 - trait * 1.6) - r;

	// ===================== L'AILE (en haut à gauche) =====================
	vec2 racine = vec2(-0.12, -0.12);
	for (int i = 0; i < 5; i++) {
		float fi = float(i);
		float ang = radians(-170.0 + fi * 24.0);            // l'éventail, vers le haut à gauche
		vec2 u = vec2(cos(ang), sin(ang));
		float d = min(plume(p, racine, u, 0.62 - abs(fi - 2.0) * 0.06, 0.1), dedans);
		forme(rgb, d, mix(couleur_arriere.rgb, couleur.rgb, step(1.5, fi)), trait * 0.7, px);
	}

	// ===================== LES PLUMES ACÉRÉES (vers le bas à droite) =====================
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		vec2 u = normalize(vec2(0.55 + 0.18 * fi, 1.0));
		// éveillé, elles filent le long de leur course et reviennent
		float course = fract(temps * 0.45 + fi * 0.21) * eveil;
		vec2 b = vec2(0.02 + fi * 0.12, 0.02) + u * (0.12 + 0.18 * course);
		float l = 0.4;
		// le trait de vitesse, derrière
		float t = clamp(-dot(p - b, u) / 0.3, 0.0, 1.0);
		float v = abs(dot(p - b, vec2(-u.y, u.x)));
		float trait_v = step(dot(p - b, u), 0.0) * smoothstep(px, 0.0, v - 0.012 * (1.0 - t)) * (1.0 - t);
		rgb = mix(rgb, couleur.rgb, min(trait_v, 1.0) * 0.6 * step(0.0, dedans));
		float d = min(plume(p, b, u, l, 0.055), dedans);
		forme(rgb, d, couleur.rgb, trait * 0.6, px);
	}

	COLOR = vec4(rgb, a * opacite);
}
