shader_type canvas_item;
render_mode unshaded;
// DESSIN DU TALISMAN « PAS DE CÔTÉ » (menu START, 30 sept. 2026).
// emplacement_talisman.gd le pose dans le rond et lui fournit `opacite`,
// `eveil` et `temps`.
// TOUT LE ROND est au dessin : un disque de nuit cerné d'un trait d'encre ;
// une silhouette (tête ronde, corps en fuseau) d'os clair à droite, ses deux
// ÉCHOS de plus en plus pâles vers la gauche, et le TRAIT d'un coup — blanc,
// oblique — qui tombe là où elle était : il n'a fendu que du vide. Pointé ou
// porté (`eveil`), les échos frémissent et le trait luit.
// Aplats nets et trait d'encre. À dessiner dans un CARRÉ : le disque le remplit.

// --- fournis par emplacement_talisman.gd (les mêmes pour tout dessin de talisman) ---
uniform float opacite : hint_range(0.0, 1.0) = 1.0;
uniform float eveil : hint_range(0.0, 1.0) = 0.0;
uniform float temps = 0.0;
// ----------------------------------------------------------------------------

// --- le disque ---
uniform vec4 encre_color : source_color = vec4(0.1, 0.02, 0.04, 1.0);
uniform vec4 fond_color : source_color = vec4(0.08, 0.05, 0.1, 1.0);
// épaisseur du trait d'encre (en part du rayon du disque)
uniform float trait : hint_range(0.0, 0.1) = 0.045;
// --- la silhouette et le coup ---
uniform vec4 os_color : source_color = vec4(0.84, 0.79, 0.66, 1.0);
uniform vec4 echo_color : source_color = vec4(0.62, 0.42, 0.5, 1.0);
uniform vec4 coup_color : source_color = vec4(1.0, 0.97, 0.94, 1.0);
// écart entre la silhouette et ses échos (part du rayon)
uniform float pas : hint_range(0.1, 0.4) = 0.27;
// demi-largeur du trait du coup (part du rayon)
uniform float lame : hint_range(0.01, 0.08) = 0.032;

// (PI et TAU sont fournis par le langage de shader de Godot)

float disque(float d, float r, float px) {
	return smoothstep(r + px * 0.5, r - px * 0.5, d);
}

// distance signée d'un point à un segment [a, b] épaissi de `ra` en a et `rb`
// en b (une capsule qui change d'épaisseur : le corps en fuseau)
float fuseau(vec2 p, vec2 a, vec2 b, float ra, float rb) {
	vec2 ab = b - a;
	float t = clamp(dot(p - a, ab) / dot(ab, ab), 0.0, 1.0);
	return length(p - (a + ab * t)) - mix(ra, rb, t);
}

// la silhouette : tête ronde et corps en fuseau, centrée en `c` (négatif dedans)
float silhouette(vec2 p, vec2 c) {
	vec2 q = p - c;
	float tete = length(q - vec2(0.0, -0.4)) - 0.16;
	float corps = fuseau(q, vec2(0.0, -0.16), vec2(0.0, 0.5), 0.15, 0.09);
	return min(tete, corps);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float px = fwidth(UV.x) * 2.0;

	// ===================== LE DISQUE =====================
	vec3 rgb = encre_color.rgb;
	float a = disque(r, 1.0, px);
	rgb = mix(rgb, fond_color.rgb, disque(r, 1.0 - trait, px));
	float champ = disque(r, 1.0 - trait, px);

	// ===================== LES ÉCHOS, PUIS LA SILHOUETTE =====================
	// éveillé, les échos frémissent (un léger va-et-vient chacun à son rythme)
	float frem = eveil * 0.03;
	for (int i = 2; i >= 1; i--) {
		float fi = float(i);
		vec2 c = vec2(0.3 - pas * fi + frem * sin(temps * (3.0 + fi) + fi), 0.02);
		float d = silhouette(p, c);
		float part = (i == 1) ? 0.55 : 0.28;
		rgb = mix(rgb, mix(fond_color.rgb, echo_color.rgb, part), smoothstep(px * 0.5, -px * 0.5, d) * champ);
		rgb = mix(rgb, encre_color.rgb, smoothstep(px * 0.5, -px * 0.5, abs(d) - 0.012) * part * champ);
	}
	// le coup : un trait blanc oblique qui tombe dans le vide laissé à gauche,
	// effilé à ses deux bouts, cerné d'encre
	vec2 ca = vec2(-0.32, -0.78);
	vec2 cb = vec2(-0.72, 0.62);
	float lm = lame * (1.0 + 0.5 * eveil);
	float dc = fuseau(p, ca, cb, lm * 0.4, lm * 0.4);
	float t = clamp(dot(p - ca, cb - ca) / dot(cb - ca, cb - ca), 0.0, 1.0);
	dc += lm * 0.4 - lm * sin(t * PI);              // effilé aux bouts, plein au milieu
	rgb = mix(rgb, mix(rgb, coup_color.rgb, 0.35 * eveil), (1.0 - smoothstep(0.0, 0.16, dc)) * champ);
	rgb = mix(rgb, encre_color.rgb, smoothstep(px * 0.5, -px * 0.5, dc - trait * 0.7) * champ);
	rgb = mix(rgb, coup_color.rgb, smoothstep(px * 0.5, -px * 0.5, dc) * champ);
	// la silhouette elle-même, à droite, bien nette
	float ds = silhouette(p, vec2(0.3, 0.02));
	rgb = mix(rgb, encre_color.rgb, smoothstep(px * 0.5, -px * 0.5, ds - trait) * champ);
	rgb = mix(rgb, os_color.rgb, smoothstep(px * 0.5, -px * 0.5, ds) * champ);
	// un reflet sur la tête
	rgb = mix(rgb, mix(os_color.rgb, vec3(1.0), 0.7), disque(length(p - vec2(0.25, -0.44)), 0.05, px) * champ);

	COLOR = vec4(rgb, a * opacite);
}
