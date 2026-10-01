shader_type canvas_item;
render_mode unshaded;
// DESSIN DU TALISMAN « COURONNE DU DÉFI » (menu START, 1er oct. 2026) —
// provisoire, en attendant le dessin de Kaoru.
// emplacement_talisman.gd le pose dans le rond et lui fournit `opacite`,
// `eveil` et `temps`.
// TOUT LE ROND est au dessin : un disque de nuit, plus chaud au milieu, cerné
// d'un trait d'encre ; une COURONNE D'OR vue de face (cinq fleurons coiffés de
// perles, une bande sertie de rubis) au-dessus d'UN SEUL cœur rouge — le défi.
// L'or en dégradé, cerné d'un trait sombre. Pointé ou porté (`eveil`), un
// reflet balaie la couronne et le cœur bat.
// À dessiner dans un CARRÉ : le disque le remplit.

// --- fournis par emplacement_talisman.gd (les mêmes pour tout dessin de talisman) ---
uniform float opacite : hint_range(0.0, 1.0) = 1.0;
uniform float eveil : hint_range(0.0, 1.0) = 0.0;
uniform float temps = 0.0;
// ----------------------------------------------------------------------------

uniform vec4 encre_color : source_color = vec4(0.1, 0.02, 0.04, 1.0);
uniform vec4 fond_color : source_color = vec4(0.06, 0.02, 0.04, 1.0);
uniform vec4 fond_centre : source_color = vec4(0.26, 0.14, 0.05, 1.0);
uniform float trait : hint_range(0.0, 0.1) = 0.045;
uniform vec4 or_vif : source_color = vec4(1.0, 0.9, 0.42, 1.0);
uniform vec4 or_couleur : source_color = vec4(0.93, 0.66, 0.14, 1.0);
uniform vec4 or_sombre : source_color = vec4(0.48, 0.28, 0.05, 1.0);
uniform vec4 couleur_fil : source_color = vec4(1.0, 0.96, 0.74, 1.0);
uniform vec4 rubis : source_color = vec4(0.8, 0.04, 0.14, 1.0);
uniform vec4 perle : source_color = vec4(0.98, 0.92, 0.76, 1.0);
uniform vec4 couleur_coeur : source_color = vec4(0.82, 0.05, 0.12, 1.0);
uniform vec4 encre_or : source_color = vec4(0.2, 0.1, 0.02, 1.0);

float disque(float d, float r, float px) {
	return smoothstep(r + px * 0.5, r - px * 0.5, d);
}

// positive dedans
void forme(inout vec3 rgb, float d, vec3 teinte, vec3 encre, float e, float px) {
	rgb = mix(rgb, encre, smoothstep(-px * 0.5, px * 0.5, d + e));
	rgb = mix(rgb, teinte, smoothstep(-px * 0.5, px * 0.5, d));
}

float smax(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (a - b) / k, 0.0, 1.0);
	return mix(b, a, h) + k * h * (1.0 - h);
}

// un cœur centré en `c`, de taille `s`, positif dedans
float coeur(vec2 p, vec2 c, float s) {
	vec2 q = (p - c) / s;
	float lobe_g = 0.36 - length(q - vec2(-0.28, -0.14));
	float lobe_d = 0.36 - length(q - vec2(0.28, -0.14));
	float pointe = min(q.y + 0.02, (0.72 - q.y) * 0.8 - abs(q.x));
	return smax(smax(lobe_g, lobe_d, 0.06), pointe, 0.12) * s;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float px = fwidth(UV.x) * 2.0;

	// ===================== LE DISQUE =====================
	vec3 rgb = encre_color.rgb;
	float a = disque(r, 1.0, px);
	rgb = mix(rgb, mix(fond_centre.rgb, fond_color.rgb, smoothstep(0.0, 0.95, r)), disque(r, 1.0 - trait, px));
	float dedans = (1.0 - trait * 1.6) - r;

	// ===================== LA COURONNE (vue de face) =====================
	// la bande : un peu bombée (plus haute au milieu), et cinq fleurons
	float bande_haut = -0.12 - 0.04 * (1.0 - p.x * p.x / 0.36);
	float bande_bas = 0.1 - 0.03 * (1.0 - p.x * p.x / 0.36);
	float d_bande = min(min(p.y - bande_haut, bande_bas - p.y), 0.62 - abs(p.x));
	float d_fleurons = -1.0;
	float d_perles = -1.0;
	for (int i = 0; i < 5; i++) {
		float fi = float(i) - 2.0;
		float x = fi * 0.27;
		float grand = 1.0 - 0.28 * abs(fi) / 2.0;
		float h = 0.42 * grand;
		float base = bande_haut + 0.02;
		// un triangle effilé, du haut de la bande vers le haut
		float t = clamp((base - p.y) / h, 0.0, 1.0);
		float w = 0.1 * (1.0 - t);
		float df = min(w - abs(p.x - x), min(base - p.y + 0.02, h - (base - p.y)));
		d_fleurons = max(d_fleurons, df);
		d_perles = max(d_perles, 0.045 - length(p - vec2(x, base - h - 0.02)));
	}
	float d_or = max(d_bande, d_fleurons);
	// l'or : dégradé vertical (vif en haut des fleurons, sombre au bas de la bande)
	vec3 c_or = mix(or_vif.rgb, or_couleur.rgb, smoothstep(-0.55, -0.05, p.y));
	c_or = mix(c_or, or_sombre.rgb, smoothstep(0.0, 0.12, p.y) * 0.75);
	// le reflet qui balaie (éveillé)
	float pos = mix(-1.2, 1.2, fract(temps * 0.4));
	float balaye = smoothstep(0.08, 0.0, abs(p.x + p.y * 0.5 - pos)) * eveil;
	c_or = mix(c_or, couleur_fil.rgb, balaye * 0.85);
	forme(rgb, min(d_or, dedans), c_or, encre_or.rgb, trait * 0.8, px);
	// le fil clair le long du haut de la bande
	float fil = min(0.012 - abs(p.y - bande_haut - 0.035), 0.56 - abs(p.x));
	rgb = mix(rgb, couleur_fil.rgb, smoothstep(-px * 0.5, px * 0.5, fil) * 0.9);
	// les perles, les rubis
	forme(rgb, min(d_perles, dedans), perle.rgb, encre_or.rgb, trait * 0.5, px);
	for (int i = 0; i < 3; i++) {
		float x = (float(i) - 1.0) * 0.36;
		float d_r = 0.055 - length((p - vec2(x, (bande_haut + bande_bas) * 0.5 + 0.01)) * vec2(1.0, 1.15));
		forme(rgb, min(d_r, dedans), rubis.rgb, encre_or.rgb, trait * 0.5, px);
		rgb = mix(rgb, perle.rgb, smoothstep(px, 0.0, length(p - vec2(x - 0.018, -0.012 + (bande_haut + bande_bas) * 0.5)) - 0.014) * step(0.0, d_r));
	}

	// ===================== UN SEUL CŒUR =====================
	float bat = 1.0 + 0.07 * pow(0.5 + 0.5 * sin(temps * 5.0), 6.0) * (0.3 + 0.7 * eveil);
	float dc = coeur(p, vec2(0.0, 0.47), 0.34 * bat);
	forme(rgb, min(dc, dedans), couleur_coeur.rgb, encre_color.rgb, trait * 0.8, px);
	float rf = min(dc - 0.03, 0.045 - length((p - vec2(-0.09, 0.4)) * vec2(1.0, 1.4)));
	rgb = mix(rgb, vec3(1.0, 0.36, 0.36), smoothstep(-px * 0.5, px * 0.5, rf));

	COLOR = vec4(rgb, a * opacite);
}
