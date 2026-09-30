shader_type canvas_item;
render_mode unshaded;
// DESSIN DU TALISMAN « LAME DE FOUDRE » (menu START, 30 sept. 2026).
// emplacement_talisman.gd le pose dans le rond et lui fournit `opacite`,
// `eveil` et `temps`.
// TOUT LE ROND est au dessin (Kaoru, 30 sept. 2026 : ni anneau ni grenats
// autour) : un disque de nuit d'orage cerné d'un simple trait d'encre, et un
// ÉCLAIR qui le traverse de haut en bas — la silhouette classique, bleue,
// blanche à cœur, cernée d'encre. Pointé ou porté (`eveil`) il tremble, sa
// lueur monte et des étincelles sautent autour.
// Aplats nets et trait d'encre. À dessiner dans un CARRÉ : le disque le
// remplit.

// --- fournis par emplacement_talisman.gd (les mêmes pour tout dessin de talisman) ---
// 1 = normal ; moins quand il est montré éteint (déjà porté ailleurs)
uniform float opacite : hint_range(0.0, 1.0) = 1.0;
// 0 = au repos, 1 = pointé ou porté
uniform float eveil : hint_range(0.0, 1.0) = 0.0;
// temps propre du talisman (s) : il passe plus vite quand il est éveillé
uniform float temps = 0.0;
// ----------------------------------------------------------------------------

// --- le trait d'encre (le même que la tornade) ---
uniform vec4 encre_color : source_color = vec4(0.1, 0.02, 0.04, 1.0);
// épaisseur du trait d'encre (en part du rayon du disque)
uniform float trait : hint_range(0.0, 0.1) = 0.045;
// --- la nuit d'orage et l'éclair ---
uniform vec4 fond_color : source_color = vec4(0.02, 0.03, 0.10, 1.0);
uniform vec4 coeur_color : source_color = vec4(0.97, 0.98, 1.0, 1.0);
uniform vec4 foudre_color : source_color = vec4(0.45, 0.72, 1.0, 1.0);
// largeur du cœur blanc dans l'éclair (part du rayon, 0 = pas de cœur)
uniform float coeur : hint_range(0.0, 0.1) = 0.05;
// combien l'éclair tremble quand il est éveillé (part du rayon)
uniform float tremblement : hint_range(0.0, 0.06) = 0.022;
// changements de forme par seconde de `temps` (le temps s'accélère à l'éveil)
uniform float cadence : hint_range(0.1, 20.0) = 6.0;

// (PI et TAU sont fournis par le langage de shader de Godot)

// la silhouette de l'éclair : six sommets (part du rayon), dans l'ordre
const vec2 SOMMETS[6] = vec2[6](vec2(0.20, -0.80), vec2(-0.375, 0.075), vec2(-0.04, 0.075),
		vec2(-0.20, 0.80), vec2(0.375, -0.125), vec2(0.04, -0.125));

// 1 à moins de `rayon`, 0 au-delà, bord lissé sur un pixel
float disque(float d, float rayon, float px) {
	return smoothstep(rayon + px * 0.5, rayon - px * 0.5, d);
}

float alea(vec2 p) {
	p = fract(p * vec2(443.897, 441.423));
	p += dot(p, p.yx + 19.19);
	return fract((p.x + p.y) * p.x);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;                 // -1 … 1 : le médaillon est le disque de rayon 1
	float r = length(p);
	float px = fwidth(UV.x) * 2.0;             // un pixel d'écran, dans cette unité

	// ===================== LE DISQUE =====================
	// un disque d'encre : son bord est le trait de l'icône ; dedans, la nuit
	// d'orage, plus claire au centre
	vec3 rgb = encre_color.rgb;
	float a = disque(r, 1.0, px);
	vec3 fond = mix(fond_color.rgb, fond_color.rgb + foudre_color.rgb * 0.12, 1.0 - smoothstep(0.0, 1.0, r));
	float dans_le_champ = disque(r, 1.0 - trait, px);
	rgb = mix(rgb, fond, dans_le_champ);

	// ===================== L'ÉCLAIR =====================
	// distance signée au polygone (négative dedans) ; éveillé, ses sommets
	// tremblent `cadence` fois par seconde
	float g = floor(temps * cadence);
	float sd = 1e9;
	float signe = 1.0;
	for (int i = 0, j = 5; i < 6; j = i, i++) {
		vec2 vi = SOMMETS[i] + tremblement * eveil * (vec2(alea(vec2(g, float(i))), alea(vec2(g, float(i) + 7.0))) - 0.5);
		vec2 vj = SOMMETS[j] + tremblement * eveil * (vec2(alea(vec2(g, float(j))), alea(vec2(g, float(j) + 7.0))) - 0.5);
		vec2 e = vj - vi;
		vec2 w = p - vi;
		vec2 b = w - e * clamp(dot(w, e) / dot(e, e), 0.0, 1.0);
		sd = min(sd, dot(b, b));
		bvec3 c = bvec3(p.y >= vi.y, p.y < vj.y, e.x * w.y > e.y * w.x);
		if (all(c) || all(not(c))) {
			signe = -signe;
		}
	}
	sd = signe * sqrt(sd);
	// sa lueur sur la nuit, qui monte à l'éveil
	float lueur = (0.35 + 0.65 * eveil) * (1.0 - smoothstep(0.0, 0.3 + 0.12 * eveil, sd));
	rgb = mix(rgb, mix(rgb, foudre_color.rgb, 0.55), lueur * dans_le_champ);
	// l'encre, le bleu, le cœur blanc
	rgb = mix(rgb, encre_color.rgb, smoothstep(px * 0.5, -px * 0.5, sd - trait) * dans_le_champ);
	rgb = mix(rgb, foudre_color.rgb, smoothstep(px * 0.5, -px * 0.5, sd) * dans_le_champ);
	rgb = mix(rgb, mix(foudre_color.rgb, coeur_color.rgb, 0.75 + 0.25 * eveil),
			smoothstep(px * 0.5, -px * 0.5, sd + coeur) * dans_le_champ);

	// ===================== LES ÉTINCELLES =====================
	// six petits points qui sautent autour de l'éclair quand il est éveillé
	for (int i = 0; i < 6; i++) {
		float fi = float(i);
		float ge = floor(temps * 6.0) + fi * 13.0;
		float ang = alea(vec2(ge, 1.0)) * TAU;
		float rr = 0.45 + 0.42 * alea(vec2(ge, 2.0));
		vec2 c = vec2(cos(ang), sin(ang)) * rr;
		float allume = step(0.45, alea(vec2(ge, 3.0))) * eveil;
		rgb = mix(rgb, coeur_color.rgb, allume * disque(length(p - c), 0.022, px));
	}

	COLOR = vec4(rgb, a * opacite);
}
