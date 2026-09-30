shader_type canvas_item;
render_mode unshaded;
// DESSIN DU TALISMAN « SOIF DE SANG » (menu START, 30 sept. 2026).
// emplacement_talisman.gd le pose dans le rond et lui fournit `opacite`,
// `eveil` et `temps`.
// TOUT LE ROND est au dessin : un disque sombre cerné d'un trait d'encre ; une
// grosse GOUTTE de sang, cernée d'encre, avec son reflet, et une pastille
// « + » d'os en haut à droite ; trois gouttelettes montent vers elle quand le
// talisman est pointé ou porté (`eveil`).
// Aplats nets et trait d'encre. À dessiner dans un CARRÉ : le disque le remplit.

// --- fournis par emplacement_talisman.gd (les mêmes pour tout dessin de talisman) ---
uniform float opacite : hint_range(0.0, 1.0) = 1.0;
uniform float eveil : hint_range(0.0, 1.0) = 0.0;
uniform float temps = 0.0;
// ----------------------------------------------------------------------------

// --- le disque ---
uniform vec4 encre_color : source_color = vec4(0.1, 0.02, 0.04, 1.0);
uniform vec4 fond_color : source_color = vec4(0.12, 0.03, 0.05, 1.0);
// épaisseur du trait d'encre (en part du rayon du disque)
uniform float trait : hint_range(0.0, 0.1) = 0.045;
// --- la goutte ---
uniform vec4 sang_color : source_color = vec4(0.78, 0.06, 0.08, 1.0);
uniform vec4 reflet_color : source_color = vec4(1.0, 0.75, 0.7, 1.0);
uniform vec4 os_color : source_color = vec4(0.84, 0.79, 0.66, 1.0);
// rayon de la panse de la goutte (part du rayon du disque)
uniform float panse : hint_range(0.2, 0.5) = 0.36;

float disque(float d, float r, float px) {
	return smoothstep(r + px * 0.5, r - px * 0.5, d);
}

float alea(vec2 p) {
	p = fract(p * vec2(443.897, 441.423));
	p += dot(p, p.yx + 19.19);
	return fract((p.x + p.y) * p.x);
}

// une goutte : une panse ronde de rayon `rp` en `c`, et un cône effilé jusqu'à
// la pointe `pointe` (négatif dedans)
float goutte(vec2 p, vec2 c, float rp, vec2 pointe) {
	float d = length(p - c) - rp;
	vec2 v = c - pointe;
	float t = clamp(dot(p - pointe, v) / dot(v, v), 0.0, 1.0);
	float cone = length(p - (pointe + v * t)) - rp * t;
	return min(d, cone);
}

// une croix « + » de demi-longueur `l` et de demi-épaisseur `e` (négatif dedans)
float croix(vec2 q, float l, float e) {
	vec2 a = abs(q);
	float h = max(a.x - l, a.y - e);
	float v = max(a.y - l, a.x - e);
	return min(h, v);
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

	// ===================== LES GOUTTELETTES =====================
	// trois petites gouttes qui montent vers la grande quand il est éveillé,
	// chacune à son rythme, et disparaissent en l'atteignant
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		float cycle = temps * (0.5 + 0.15 * fi) + fi * 0.37;
		float v = fract(cycle);
		float ang = 2.4 + fi * 1.1 + 0.4 * alea(vec2(floor(cycle), fi));
		vec2 c = vec2(cos(ang), sin(ang)) * mix(0.86, 0.3, v) - vec2(0.12, 0.0);
		float taille = 0.07 * (1.0 - v * 0.6) * eveil;
		float dg = goutte(p, c, taille, c + vec2(0.0, -taille * 1.9));
		rgb = mix(rgb, encre_color.rgb, smoothstep(px * 0.5, -px * 0.5, dg - trait * 0.6) * champ * eveil);
		rgb = mix(rgb, sang_color.rgb, smoothstep(px * 0.5, -px * 0.5, dg) * champ * eveil);
	}

	// ===================== LA GOUTTE =====================
	vec2 c = vec2(-0.12, 0.2);
	float rp = panse * (1.0 + 0.03 * eveil * sin(temps * 2.5));
	float dg = goutte(p, c, rp, vec2(-0.12, -0.72));
	rgb = mix(rgb, encre_color.rgb, smoothstep(px * 0.5, -px * 0.5, dg - trait) * champ);
	rgb = mix(rgb, sang_color.rgb, smoothstep(px * 0.5, -px * 0.5, dg) * champ);
	// une ombre en bas à droite, un reflet en haut à gauche
	rgb = mix(rgb, sang_color.rgb * 0.7, smoothstep(px * 0.5, -px * 0.5, dg + rp * 0.18) * smoothstep(-0.1, 0.35, dot(p - c, vec2(0.6, 0.8))) * champ);
	rgb = mix(rgb, reflet_color.rgb, disque(length(p - c - vec2(-rp * 0.42, -rp * 0.4)), rp * 0.2, px) * champ);
	rgb = mix(rgb, reflet_color.rgb, disque(length(p - c - vec2(-rp * 0.22, -rp * 0.62)), rp * 0.08, px) * champ);

	// ===================== LA PASTILLE « + » =====================
	vec2 cp = vec2(0.5, -0.46);
	float rpast = 0.24;
	rgb = mix(rgb, encre_color.rgb, disque(length(p - cp), rpast + trait, px) * champ);
	rgb = mix(rgb, os_color.rgb, disque(length(p - cp), rpast, px) * champ);
	float dx = croix(p - cp, 0.14, 0.04);
	rgb = mix(rgb, mix(sang_color.rgb, reflet_color.rgb, 0.5 * eveil), smoothstep(px * 0.5, -px * 0.5, dx) * champ);

	COLOR = vec4(rgb, a * opacite);
}
