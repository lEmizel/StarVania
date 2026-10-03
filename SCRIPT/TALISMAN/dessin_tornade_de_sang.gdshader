shader_type canvas_item;
render_mode unshaded;
// DESSIN DU TALISMAN « TORNADE DE SANG » (menu START, 30 sept. 2026).
// emplacement_talisman.gd le pose dans le rond et lui fournit `opacite`,
// `eveil` et `temps`.
// TOUT LE ROND est au dessin (ni anneau ni grenats
// autour) : un disque sombre cerné d'un simple trait d'encre ; dedans, la
// boule de sang vue de face et ses bras enroulés autour d'elle, qui TOURNENT :
// lentement au repos, plus vite quand le talisman est pointé ou porté (c'est
// `temps` qui s'accélère). Aplats nets et trait d'encre. À dessiner dans un
// CARRÉ : le disque le remplit.

// --- fournis par emplacement_talisman.gd (les mêmes pour tout dessin de talisman) ---
// 1 = normal ; moins quand il est montré éteint (déjà porté ailleurs)
uniform float opacite : hint_range(0.0, 1.0) = 1.0;
// 0 = au repos, 1 = pointé ou porté
uniform float eveil : hint_range(0.0, 1.0) = 0.0;
// temps propre du talisman (s) : il passe plus vite quand il est éveillé
uniform float temps = 0.0;
// ----------------------------------------------------------------------------

// --- le disque ---
uniform vec4 encre_color : source_color = vec4(0.1, 0.02, 0.04, 1.0);
uniform vec4 fond_color : source_color = vec4(0.19, 0.0, 0.035, 1.0);
// épaisseur du trait d'encre (en part du rayon du disque)
uniform float trait : hint_range(0.0, 0.1) = 0.045;
// --- la spirale ---
uniform vec4 core_color : source_color = vec4(1.0, 0.88, 0.6, 1.0);
uniform vec4 blood_color : source_color = vec4(0.8, 0.05, 0.05, 1.0);
uniform int nb_bras : hint_range(1, 4) = 2;
// nombre de tours que fait un bras du centre à son bout
uniform float tours : hint_range(0.3, 2.5) = 1.2;
// demi-largeur d'un bras près de la boule, et rayon de la boule (part du rayon)
uniform float largeur_bras : hint_range(0.05, 0.35) = 0.23;
uniform float rayon_boule : hint_range(0.08, 0.4) = 0.23;
// tours par seconde de `temps`
uniform float vitesse : hint_range(0.0, 1.0) = 0.12;

// (PI et TAU sont fournis par le langage de shader de Godot)

// jusqu'où vont les bras (part du rayon du disque)
const float PORTEE = 0.9;

// 1 à moins de `rayon`, 0 au-delà, bord lissé sur un pixel
float disque(float d, float rayon, float px) {
	return smoothstep(rayon + px * 0.5, rayon - px * 0.5, d);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;                 // -1 … 1 : le médaillon est le disque de rayon 1
	float r = length(p);
	float px = fwidth(UV.x) * 2.0;             // un pixel d'écran, dans cette unité

	// ===================== LE DISQUE =====================
	// un disque d'encre : son bord est le trait de l'icône ; dedans, le fond
	vec3 rgb = encre_color.rgb;
	float a = disque(r, 1.0, px);
	rgb = mix(rgb, fond_color.rgb, disque(r, 1.0 - trait, px));

	// ===================== LA SPIRALE =====================
	// chaque bras part de la boule et s'enroule en s'affinant jusqu'à sa pointe
	float t = clamp(r / PORTEE, 0.0, 1.0);
	float nb = float(nb_bras);
	float phase = (atan(p.y, p.x) / TAU - tours * t - temps * vitesse) * nb;
	float ecart = fract(phase + 0.5) - 0.5;          // au bras le plus proche, signé
	float pente = TAU * tours * r / PORTEE;          // inclinaison du bras sur le rayon
	float d_bras = abs(ecart) / nb * TAU * r / sqrt(1.0 + pente * pente);
	float demi = largeur_bras * pow(1.0 - t, 0.75);
	float la = step(0.004, demi);                    // plus de bras au-delà de sa pointe
	float bras = demi - d_bras;                      // positif dans le bras
	rgb = mix(rgb, encre_color.rgb, la * smoothstep(-px * 0.5, px * 0.5, bras + trait * smoothstep(0.0, 0.05, demi)));
	rgb = mix(rgb, mix(blood_color.rgb, core_color.rgb, 0.08 * eveil), la * smoothstep(-px * 0.5, px * 0.5, bras));
	// un filet clair le long de chaque bras, du côté qui avance
	float filet = demi * 0.2 - abs(sign(ecart) * d_bras + demi * 0.36);
	rgb = mix(rgb, mix(blood_color.rgb, core_color.rgb, 0.62),
			smoothstep(-px * 0.5, px * 0.5, filet) * step(0.03, demi));

	// ===================== LA BOULE =====================
	// elle bat doucement quand le talisman est éveillé
	float rb = rayon_boule * (1.0 + 0.07 * eveil * sin(temps * 2.2));
	rgb = mix(rgb, encre_color.rgb, disque(r, rb * 1.36 + trait, px));
	rgb = mix(rgb, mix(blood_color.rgb, core_color.rgb, 0.45), disque(r, rb * 1.36, px));
	rgb = mix(rgb, core_color.rgb, disque(r, rb, px));
	rgb = mix(rgb, mix(core_color.rgb, vec3(1.0), 0.7), disque(length(p + vec2(0.35, 0.4) * rb), rb * 0.26, px));

	COLOR = vec4(rgb, a * opacite);
}
