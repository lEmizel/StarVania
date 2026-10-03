shader_type canvas_item;
render_mode unshaded;
// DESSIN DU TALISMAN « RELIQUAIRE » (menu START, 1er oct. 2026) — provisoire,
// en attendant le dessin définitif.
// emplacement_talisman.gd le pose dans le rond et lui fournit `opacite`,
// `eveil` et `temps`.
// TOUT LE ROND est au dessin : un disque de nuit cerné d'un trait d'encre ;
// dedans, un RELIQUAIRE gothique (une châsse à toit pointu) dont la vitre montre
// une GOUTTE de sang À MOITIÉ PLEINE — la moitié qu'on garde en mourant. Aplats
// et trait d'encre, pas de blanc. Pointé ou porté (`eveil`), le sang ondule.
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
uniform vec4 metal : source_color = vec4(0.62, 0.48, 0.26, 1.0);
uniform vec4 metal_ombre : source_color = vec4(0.38, 0.27, 0.14, 1.0);
uniform vec4 vitre : source_color = vec4(0.13, 0.06, 0.1, 1.0);
uniform vec4 couleur : source_color = vec4(0.78, 0.04, 0.12, 1.0);
uniform vec4 vive : source_color = vec4(1.0, 0.24, 0.24, 1.0);

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

	// ===================== LA CHÂSSE =====================
	// le corps (une boîte), le toit (un pignon pointu), le socle
	float corps = min(0.42 - abs(p.x), min(p.y + 0.12, 0.5 - p.y));
	float toit = min(min(0.5 - abs(p.x), p.y + 0.62 - abs(p.x) * 0.0), min(-0.1 - p.y, (p.y + 0.66) - abs(p.x) * 0.95));
	float socle = min(0.52 - abs(p.x), 0.07 - abs(p.y - 0.56));
	forme(rgb, max(max(corps, toit), socle), metal.rgb, trait, px);
	// une croix au sommet
	float croix = max(min(0.03 - abs(p.x), 0.11 - abs(p.y + 0.74)), min(0.08 - abs(p.x), 0.03 - abs(p.y + 0.77)));
	forme(rgb, croix, metal.rgb, trait * 0.6, px);
	// l'ombre sur la moitié droite du métal
	rgb = mix(rgb, metal_ombre.rgb, smoothstep(-px, px, p.x - 0.05) * smoothstep(-px, px, max(max(corps, toit), socle) - trait) * 0.6);

	// ===================== LA VITRE ET LA GOUTTE À MOITIÉ PLEINE =====================
	float fenetre = min(0.27 - abs(p.x), min(p.y + 0.02, 0.4 - p.y));
	forme(rgb, fenetre, vitre.rgb, trait * 0.6, px);
	vec2 cg = vec2(0.0, 0.24);
	float rond = 0.14 - length(p - cg);
	float pointe = 0.13 - abs(p.x) * 1.7 + (p.y - cg.y) * 0.6;
	float goutte = mix(max(rond, min(pointe, 0.23 + (p.y - cg.y))), rond, step(0.0, p.y - cg.y));
	// son contour d'encre, et le sang jusqu'à mi-hauteur
	rgb = mix(rgb, encre_color.rgb, smoothstep(-px * 0.5, px * 0.5, goutte + trait * 0.6) * (1.0 - smoothstep(-px * 0.5, px * 0.5, goutte)));
	float onde = 0.012 * sin(p.x * 40.0 + temps * 4.0) * eveil;
	float niveau = cg.y + 0.0 + onde;
	rgb = mix(rgb, couleur.rgb, smoothstep(-px * 0.5, px * 0.5, min(goutte, p.y - niveau)));
	rgb = mix(rgb, vive.rgb, smoothstep(-px * 0.5, px * 0.5, min(min(goutte - 0.03, p.y - niveau - 0.03), 0.035 - abs(p.x + 0.05))));

	COLOR = vec4(rgb, a * opacite);
}
