shader_type canvas_item;
render_mode unshaded;
// DESSIN DU TALISMAN « ÉPINES DE SANG » (menu START, 1er oct. 2026) —
// provisoire, en attendant le dessin de Kaoru.
// emplacement_talisman.gd le pose dans le rond et lui fournit `opacite`,
// `eveil` et `temps`.
// TOUT LE ROND est au dessin : un disque de nuit cerné d'un trait d'encre, et
// la même étoile de pics de sang cristallisé que dans le jeu (une face
// éclairée, une face à l'ombre, une arête claire, un liseré d'encre) autour
// d'un cœur de sang. Pointé ou porté (`eveil`), les pics battent : ils
// jaillissent un peu plus loin à chaque pulsation.
// À dessiner dans un CARRÉ : le disque le remplit.

// --- fournis par emplacement_talisman.gd (les mêmes pour tout dessin de talisman) ---
uniform float opacite : hint_range(0.0, 1.0) = 1.0;
uniform float eveil : hint_range(0.0, 1.0) = 0.0;
uniform float temps = 0.0;
// ----------------------------------------------------------------------------

uniform vec4 encre_color : source_color = vec4(0.1, 0.02, 0.04, 1.0);
uniform vec4 fond_color : source_color = vec4(0.06, 0.02, 0.04, 1.0);
uniform float trait : hint_range(0.0, 0.1) = 0.045;
uniform vec4 couleur_sombre : source_color = vec4(0.32, 0.0, 0.05, 1.0);
uniform vec4 couleur : source_color = vec4(0.78, 0.04, 0.12, 1.0);
uniform vec4 couleur_claire : source_color = vec4(1.0, 0.52, 0.52, 1.0);

const int NB = 9;

float disque(float d, float r, float px) {
	return smoothstep(r + px * 0.5, r - px * 0.5, d);
}

void par_dessus(inout vec3 rgb, inout float a, vec3 teinte, float force) {
	float total = force + a * (1.0 - force);
	rgb = (teinte * force + rgb * a * (1.0 - force)) / max(total, 0.0001);
	a = total;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float px = fwidth(UV.x) * 2.0;

	// ===================== LE DISQUE =====================
	vec3 rgb = encre_color.rgb;
	float a = disque(r, 1.0, px);
	float champ = disque(r, 1.0 - trait, px);
	rgb = mix(rgb, fond_color.rgb, champ);

	// ===================== L'ÉTOILE DE PICS =====================
	// la pulsation (éveillé) : un jaillissement bref, puis le repos
	float cycle = fract(temps * 0.9);
	float pouls = eveil * exp(-cycle * 7.0);
	vec3 f_rgb = vec3(0.0);
	float f_a = 0.0;
	float e = 0.028;                      // le liseré d'encre
	for (int i = 0; i < NB; i++) {
		float fi = float(i);
		float theta = fi * TAU / float(NB) - PI * 0.5 + 0.18 * sin(fi * 2.3);
		vec2 dir = vec2(cos(theta), sin(theta));
		vec2 cote = vec2(-dir.y, dir.x);
		float L = mix(0.62, 0.86, fract(fi * 0.618)) + 0.07 * pouls;
		float pied = 0.16;
		float w0 = 0.095;
		float u = dot(p, dir);
		float v = dot(p, cote);
		float s = (u - pied) / (L - pied);
		float w = w0 * clamp(1.0 - s, 0.0, 1.0);
		float dedans = min(min(w - abs(v), u - pied), L - u);
		par_dessus(f_rgb, f_a, encre_color.rgb, smoothstep(0.0, px, dedans + e));
		vec3 face = mix(couleur_sombre.rgb, couleur.rgb, smoothstep(-px, px, v));
		par_dessus(f_rgb, f_a, face, smoothstep(0.0, px, dedans));
		float arete = min(0.012 - abs(v - w * 0.18), dedans - 0.02);
		par_dessus(f_rgb, f_a, couleur_claire.rgb, smoothstep(0.0, px, arete) * step(s, 0.8));
	}
	// le cœur de sang d'où ils sortent
	float rc = 0.2 + 0.03 * pouls;
	par_dessus(f_rgb, f_a, encre_color.rgb, disque(r, rc + e, px));
	vec3 coeur = mix(couleur.rgb, couleur_sombre.rgb, smoothstep(-0.2, 0.2, p.y + p.x * 0.4));
	par_dessus(f_rgb, f_a, coeur, disque(r, rc, px));
	par_dessus(f_rgb, f_a, couleur_claire.rgb, disque(length(p - vec2(-0.06, -0.07)), 0.05, px) * 0.8);
	rgb = mix(rgb, f_rgb, f_a * champ);

	COLOR = vec4(rgb, a * opacite);
}
