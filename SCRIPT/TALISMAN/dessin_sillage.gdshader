shader_type canvas_item;
render_mode unshaded;
// DESSIN DU TALISMAN « SILLAGE DE SANG » (menu START, 1er oct. 2026).
// emplacement_talisman.gd le pose dans le rond et lui fournit `opacite`,
// `eveil` et `temps`.
// TOUT LE ROND est au dessin : un disque de nuit cerné d'un trait d'encre, et
// la même FUMÉE DE SANG que dans le jeu (bruits empilés qui s'enroulent en
// volutes, filaments clairs, profondeurs sombres), qui monte en diagonale du
// bas à gauche vers le haut à droite. Pointé ou porté (`eveil`), elle
// tourbillonne et monte.
// À dessiner dans un CARRÉ : le disque le remplit.

// --- fournis par emplacement_talisman.gd (les mêmes pour tout dessin de talisman) ---
uniform float opacite : hint_range(0.0, 1.0) = 1.0;
uniform float eveil : hint_range(0.0, 1.0) = 0.0;
uniform float temps = 0.0;
// ----------------------------------------------------------------------------

uniform vec4 encre_color : source_color = vec4(0.1, 0.02, 0.04, 1.0);
uniform vec4 fond_color : source_color = vec4(0.06, 0.02, 0.04, 1.0);
uniform float trait : hint_range(0.0, 0.1) = 0.045;
// les couleurs de la fumée du jeu : profondeurs, fumée, filaments
uniform vec4 couleur_sombre : source_color = vec4(0.12, 0.0, 0.02, 1.0);
uniform vec4 couleur_fumee : source_color = vec4(0.78, 0.07, 0.1, 1.0);
uniform vec4 couleur_filament : source_color = vec4(1.0, 0.42, 0.4, 1.0);

float disque(float d, float r, float px) {
	return smoothstep(r + px * 0.5, r - px * 0.5, d);
}

vec2 gradient(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(vec2(p.x * p.y, p.x + p.y)) * 2.0 - 1.0;
}

float bruit(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = dot(gradient(i), f);
	float b = dot(gradient(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
	float c = dot(gradient(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
	float d = dot(gradient(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 0.75 + 0.5;
}

float fbm(vec2 p) {
	const mat2 ROT = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += bruit(p) * amp;
		p = ROT * p * 2.02 + vec2(17.1, 9.2);
		amp *= 0.5;
	}
	return v / 0.9375;
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

	// ===================== LA FUMÉE =====================
	// trois bruits empilés, chacun déforme le suivant (comme en jeu)
	float tt = temps * (0.04 + 0.2 * eveil);
	vec2 q = vec2(p.x, p.y * 0.8) * 1.3 + vec2(3.1, 1.7) + vec2(0.0, tt);
	vec2 w1 = vec2(fbm(q + vec2(0.0, tt * 0.5)), fbm(q + vec2(5.2, 1.3)));
	vec2 w2 = vec2(fbm(q + 3.2 * w1 + vec2(1.7, 9.2)), fbm(q + 3.2 * w1 + vec2(8.3, 2.8)));
	vec2 rr = q + 3.6 * w2;
	float fumee = fbm(rr);
	float crete = 1.0 - abs(2.0 * fbm(rr * 1.7 + vec2(3.3, 7.1)) - 1.0);
	float filament = pow(crete, 5.0);
	// l'enveloppe : une traînée en diagonale montante, plus large en bas à
	// gauche, tordue par les bruits
	vec2 dir = normalize(vec2(1.0, -0.8));
	vec2 tordu = p + (w2 - 0.5) * 0.7;
	float le_long = dot(tordu, dir);
	float travers = dot(tordu, vec2(-dir.y, dir.x));
	float demi = mix(0.52, 0.18, clamp(le_long * 0.55 + 0.5, 0.0, 1.0));
	float env = (1.0 - smoothstep(demi * 0.3, demi, abs(travers))) * (1.0 - smoothstep(0.7, 1.0, le_long));
	float voile = smoothstep(0.3, 0.72, fumee);
	float densite = pow(env * voile, 1.1);
	vec3 f_rgb = couleur_fumee.rgb * mix(0.75, 1.15, fumee);
	f_rgb = mix(f_rgb, couleur_sombre.rgb, 0.45 * smoothstep(0.55, 1.0, densite * voile));
	float lumiere = filament * 0.9 * env;
	f_rgb = mix(f_rgb, couleur_filament.rgb, clamp(lumiere * 1.4, 0.0, 1.0));
	float f_a = clamp(densite * 1.2 + lumiere * 0.5, 0.0, 1.0);
	rgb = mix(rgb, f_rgb, f_a * champ);

	COLOR = vec4(rgb, a * opacite);
}
