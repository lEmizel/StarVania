shader_type canvas_item;
render_mode unshaded;
// DESSIN DU TALISMAN « SANG VERSÉ » (menu START, 1er oct. 2026) — provisoire,
// en attendant le dessin de Kaoru.
// emplacement_talisman.gd le pose dans le rond et lui fournit `opacite`,
// `eveil` et `temps`.
// TOUT LE ROND est au dessin : un disque de nuit cerné d'un trait d'encre ;
// en haut, un CŒUR fêlé d'où le sang s'échappe en gouttes ; en bas, une BARRE
// de jauge qu'elles remplissent. Aplats et trait d'encre, pas de blanc. Pointé
// ou porté (`eveil`), les gouttes tombent et la jauge monte.
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
uniform vec4 couleur : source_color = vec4(0.78, 0.04, 0.12, 1.0);
uniform vec4 vive : source_color = vec4(1.0, 0.24, 0.24, 1.0);
uniform vec4 vide : source_color = vec4(0.24, 0.06, 0.09, 1.0);

float disque(float d, float r, float px) {
	return smoothstep(r + px * 0.5, r - px * 0.5, d);
}

void forme(inout vec3 rgb, float d, vec3 teinte, float e, float px) {
	rgb = mix(rgb, encre_color.rgb, smoothstep(-px * 0.5, px * 0.5, d + e));
	rgb = mix(rgb, teinte, smoothstep(-px * 0.5, px * 0.5, d));
}

// un cœur centré en `c`, de taille `s`, positif dedans : deux lobes ronds en
// haut, une pointe en bas
float coeur(vec2 p, vec2 c, float s) {
	vec2 q = (p - c) / s;
	float lobe_g = 0.36 - length(q - vec2(-0.28, -0.14));
	float lobe_d = 0.36 - length(q - vec2(0.28, -0.14));
	float pointe = min(q.y + 0.12, (0.7 - q.y) * 0.9 - abs(q.x));
	return max(max(lobe_g, lobe_d), pointe) * s;
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

	// ===================== LE CŒUR FÊLÉ =====================
	vec2 cc = vec2(0.0, -0.28);
	float d = coeur(p, cc, 0.5);
	forme(rgb, d, couleur.rgb, trait, px);
	rgb = mix(rgb, vive.rgb, smoothstep(-px * 0.5, px * 0.5, min(d - 0.05, 0.1 - length(p - cc - vec2(-0.14, -0.1)))));
	// la fêlure, en zigzag
	float zig = abs(p.x - 0.03 - 0.06 * sign(fract((p.y + 0.6) * 4.0) - 0.5) * (fract((p.y + 0.6) * 4.0) * 2.0 - 1.0)) - 0.018;
	rgb = mix(rgb, encre_color.rgb, smoothstep(px, 0.0, zig) * step(0.02, d));

	// ===================== LES GOUTTES =====================
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		float vie = fract(temps / 1.6 + fi / 3.0);
		vec2 cg = vec2(0.02 + (fi - 1.0) * 0.06, mix(0.12, 0.5, vie * eveil + 0.3 * fi * (1.0 - eveil)));
		float g = 0.04 - length((p - cg) * vec2(1.0, 0.8));
		forme(rgb, g, couleur.rgb, trait * 0.5, px);
	}

	// ===================== LA JAUGE =====================
	float barre = min(0.62 - abs(p.x), 0.085 - abs(p.y - 0.62));
	forme(rgb, barre, vide.rgb, trait, px);
	float niveau = mix(-0.55, 0.15, 0.5 + 0.5 * sin(temps * 1.2) * eveil);
	rgb = mix(rgb, couleur.rgb, smoothstep(-px * 0.5, px * 0.5, min(barre - 0.025, niveau - p.x)));

	COLOR = vec4(rgb, a * opacite);
}
