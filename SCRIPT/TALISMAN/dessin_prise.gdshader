shader_type canvas_item;
render_mode unshaded;
// DESSIN DU TALISMAN « PRISE FERME » (menu START, 1er oct. 2026) — provisoire,
// en attendant le dessin définitif.
// emplacement_talisman.gd le pose dans le rond et lui fournit `opacite`,
// `eveil` et `temps`.
// TOUT LE ROND est au dessin : un disque de nuit cerné d'un trait d'encre ; à
// gauche, un MUR de pierres ; de la droite, une patte rouge dont les TROIS
// GRIFFES se plantent dans le mur, avec des fêlures autour des pointes.
// Aplats et trait d'encre. Pointé ou porté (`eveil`), les griffes serrent.
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
uniform vec4 pierre : source_color = vec4(0.27, 0.23, 0.29, 1.0);
uniform vec4 pierre_claire : source_color = vec4(0.34, 0.3, 0.36, 1.0);
uniform vec4 couleur : source_color = vec4(0.78, 0.04, 0.12, 1.0);
uniform vec4 sombre : source_color = vec4(0.4, 0.02, 0.07, 1.0);
uniform vec4 vive : source_color = vec4(1.0, 0.24, 0.24, 1.0);

float disque(float d, float r, float px) {
	return smoothstep(r + px * 0.5, r - px * 0.5, d);
}

void forme(inout vec3 rgb, float d, vec3 teinte, float e, float px) {
	rgb = mix(rgb, encre_color.rgb, smoothstep(-px * 0.5, px * 0.5, d + e));
	rgb = mix(rgb, teinte, smoothstep(-px * 0.5, px * 0.5, d));
}

// un segment qui s'effile de a (rayon ra) à b (rayon rb), positif dedans
float effile(vec2 p, vec2 a, vec2 b, float ra, float rb) {
	vec2 ab = b - a;
	float t = clamp(dot(p - a, ab) / dot(ab, ab), 0.0, 1.0);
	return mix(ra, rb, t) - length(p - (a + ab * t));
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

	// ===================== LE MUR =====================
	float bord_mur = -0.1;
	float mur = min(bord_mur - p.x, dedans);
	// des pierres : rangs de 0,26 de haut, joints décalés d'un rang à l'autre
	float rang = floor(p.y / 0.26);
	float x_joint = fract((p.x + mod(rang, 2.0) * 0.17) / 0.34);
	float joint = min(abs(fract(p.y / 0.26) - 0.5) * 0.26 * 2.0, abs(x_joint - 0.5) * 0.34 * 2.0);
	vec3 teinte_mur = mix(pierre.rgb, pierre_claire.rgb, step(0.5, fract(rang * 0.37 + 0.2)));
	forme(rgb, mur, teinte_mur, trait, px);
	// les joints, en encre, à l'intérieur du mur
	rgb = mix(rgb, encre_color.rgb, smoothstep(px, 0.0, joint - 0.012) * smoothstep(-px, px, mur));

	// ===================== LA PATTE ET SES GRIFFES =====================
	float serre = 0.03 * eveil * (0.5 + 0.5 * sin(temps * 3.0));
	vec2 paume = vec2(0.42, 0.05);
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		vec2 base = paume + vec2(-0.08, (fi - 1.0) * 0.17);
		vec2 pointe = vec2(-0.27 - serre, (fi - 1.0) * 0.25 + 0.06);
		// les fêlures autour de la pointe, dans le mur
		for (int k = 0; k < 3; k++) {
			float ang = 2.2 + float(k) * 0.9 + fi;
			vec2 u = vec2(cos(ang), sin(ang));
			float fel = effile(p, pointe, pointe + u * 0.13, 0.012, 0.002);
			rgb = mix(rgb, encre_color.rgb, smoothstep(-px * 0.5, px * 0.5, min(fel, mur)));
		}
		// la griffe : un croc qui s'effile, un peu courbé (deux segments)
		vec2 coude = mix(base, pointe, 0.55) + vec2(0.0, -0.06);
		float g = max(effile(p, base, coude, 0.075, 0.05), effile(p, coude, pointe, 0.05, 0.004));
		forme(rgb, g, mix(sombre.rgb, couleur.rgb, step(0.0, -(p.y - mix(base.y, pointe.y, 0.5)) + 0.02)), trait * 0.8, px);
	}
	// la paume, par-dessus la racine des griffes
	float paume_d = min(0.2 - length((p - paume) * vec2(1.0, 0.85)), dedans);
	forme(rgb, paume_d, couleur.rgb, trait, px);
	rgb = mix(rgb, vive.rgb, smoothstep(-px * 0.5, px * 0.5, 0.07 - length(p - paume - vec2(-0.04, -0.07))));

	COLOR = vec4(rgb, a * opacite);
}
