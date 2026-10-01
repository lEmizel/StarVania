shader_type canvas_item;
render_mode unshaded;
// DESSIN DU TALISMAN « CRESCENDO » (menu START, 1er oct. 2026) — provisoire,
// en attendant le dessin de Kaoru.
// emplacement_talisman.gd le pose dans le rond et lui fournit `opacite`,
// `eveil` et `temps`.
// TOUT LE ROND est au dessin : un disque de nuit cerné d'un trait d'encre ;
// dedans, CINQ lames de sang dressées, de plus en plus hautes et de plus en
// plus vives de gauche à droite — les cinq paliers de la série (5, 10, 20,
// 40, 50 %). Pointé ou porté (`eveil`), elles s'allument l'une après l'autre,
// puis toutes ensemble, et recommencent. Aplats et trait d'encre, pas de blanc.
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
uniform vec4 eteinte : source_color = vec4(0.3, 0.03, 0.07, 1.0);
uniform vec4 couleur : source_color = vec4(0.78, 0.04, 0.12, 1.0);
uniform vec4 couleur_vive : source_color = vec4(1.0, 0.24, 0.24, 1.0);
// une lame s'allume toutes les… (s de `temps`)
uniform float cadence = 0.35;

float disque(float d, float r, float px) {
	return smoothstep(r + px * 0.5, r - px * 0.5, d);
}

void forme(inout vec3 rgb, float d, vec3 teinte, float e, float px) {
	rgb = mix(rgb, encre_color.rgb, smoothstep(-px * 0.5, px * 0.5, d + e));
	rgb = mix(rgb, teinte, smoothstep(-px * 0.5, px * 0.5, d));
}

// une LAME dressée : de sa base (en bas, largeur `w`) à sa pointe, haute de
// `h`, posée en x = cx sur la ligne y = base (positive dedans)
float lame(vec2 p, float cx, float base, float w, float h) {
	float y = clamp((base - p.y) / max(h, 0.001), 0.0, 1.0);   // 0 au pied → 1 à la pointe
	float demi = w * (1.0 - pow(y, 1.6));                       // elle s'effile vers la pointe
	float dedans = demi - abs(p.x - cx);
	float bas = p.y - (base - h);                               // sous la pointe
	float haut = base - p.y + w * 0.6;                          // le pied, un peu arrondi
	return min(min(dedans, bas), haut);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;                 // -1 … 1 : le médaillon est le disque de rayon 1
	float r = length(p);
	float px = fwidth(UV.x) * 2.0;

	// ===================== LE DISQUE =====================
	vec3 rgb = encre_color.rgb;
	float a = disque(r, 1.0, px);
	rgb = mix(rgb, mix(fond_centre.rgb, fond_color.rgb, smoothstep(0.0, 0.95, r)),
			disque(r, 1.0 - trait, px));

	// ===================== LES CINQ LAMES =====================
	// au repos : toutes allumées, de plus en plus vives ; éveillé : elles
	// s'allument l'une après l'autre (5 pas), restent toutes allumées 2 pas,
	// puis recommencent
	float pas = floor(temps / cadence);
	float cycle = mod(pas, 7.0);
	float base = 0.5;
	for (int i = 0; i < 5; i++) {
		float fi = float(i);
		float cx = -0.52 + fi * 0.26;
		float h = 0.28 + fi * 0.15;
		float w = 0.075 + fi * 0.008;
		float d = lame(p, cx, base, w, h);
		float allumee = mix(1.0, step(fi, cycle), eveil);
		vec3 vive = mix(couleur.rgb, couleur_vive.rgb, fi / 4.0);
		forme(rgb, d, mix(eteinte.rgb, vive, allumee), trait * 0.8, px);
	}
	// le sol où elles sont plantées
	float sol = min(0.03 - abs(p.y - base - 0.03), 0.72 - abs(p.x));
	forme(rgb, sol, couleur.rgb * 0.6, trait * 0.6, px);

	COLOR = vec4(rgb, a * opacite);
}
