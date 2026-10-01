shader_type canvas_item;
render_mode unshaded;
// DESSIN DU TALISMAN « SANG PLEIN » (menu START, 1er oct. 2026) — provisoire,
// en attendant le dessin de Kaoru.
// emplacement_talisman.gd le pose dans le rond et lui fournit `opacite`,
// `eveil` et `temps`.
// TOUT LE ROND est au dessin : un disque de nuit cerné d'un trait d'encre ;
// dedans, une FIOLE ronde PLEINE de sang à ras bord (la jauge pleine), son
// bouchon, un reflet sur le verre ; une goutte déborde et coule le long du col.
// Aplats et trait d'encre, pas de blanc. Pointé ou porté (`eveil`), la surface
// ondule et la goutte coule.
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
uniform vec4 verre : source_color = vec4(0.32, 0.26, 0.32, 1.0);
uniform vec4 bouchon : source_color = vec4(0.42, 0.27, 0.18, 1.0);
uniform vec4 couleur : source_color = vec4(0.78, 0.04, 0.12, 1.0);
uniform vec4 sombre : source_color = vec4(0.4, 0.02, 0.07, 1.0);
uniform vec4 clair : source_color = vec4(1.0, 0.45, 0.45, 1.0);

float disque(float d, float r, float px) {
	return smoothstep(r + px * 0.5, r - px * 0.5, d);
}

void forme(inout vec3 rgb, float d, vec3 teinte, float e, float px) {
	rgb = mix(rgb, encre_color.rgb, smoothstep(-px * 0.5, px * 0.5, d + e));
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

	// ===================== LA FIOLE =====================
	vec2 c = vec2(0.0, 0.2);                      // le centre de la panse
	float panse = 0.5 - length(p - c);
	float col = min(0.15 - abs(p.x), min(p.y + 0.6, 0.1 - p.y));          // le col
	float fiole = max(panse, col);
	forme(rgb, fiole, verre.rgb, trait, px);
	// le sang, à ras bord (jusqu'au haut du col), sa surface qui ondule
	float onde = 0.012 * sin(p.x * 30.0 + temps * 4.0) * eveil;
	float niveau = -0.5 + onde;
	float sang = min(fiole - 0.035, p.y - niveau);
	vec3 teinte = mix(couleur.rgb, sombre.rgb, smoothstep(0.0, 0.5, p.x + 0.1 - (p.y - c.y) * 0.3));
	rgb = mix(rgb, teinte, smoothstep(-px * 0.5, px * 0.5, sang));
	// le reflet sur le verre, à gauche de la panse
	float reflet = min(0.06 - abs(length(p - c) - 0.36), min(-(p.x - c.x) - 0.1, -(p.y - c.y) + 0.15));
	rgb = mix(rgb, clair.rgb, smoothstep(-px * 0.5, px * 0.5, reflet) * 0.8);
	// le bouchon
	float b = min(0.19 - abs(p.x), min(p.y + 0.78, -0.58 - p.y));
	forme(rgb, b, bouchon.rgb, trait * 0.8, px);

	// ===================== LA GOUTTE QUI DÉBORDE =====================
	float vie = fract(temps / 2.4);
	float yg = mix(-0.5, -0.05, smoothstep(0.1, 1.0, vie) * eveil + 0.35 * (1.0 - eveil));
	vec2 cg = vec2(0.17, yg);
	float goutte = 0.045 - length((p - cg) * vec2(1.0, 0.8));
	forme(rgb, goutte, couleur.rgb, trait * 0.6, px);

	COLOR = vec4(rgb, a * opacite);
}
