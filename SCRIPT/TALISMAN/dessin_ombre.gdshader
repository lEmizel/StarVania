shader_type canvas_item;
render_mode unshaded;
// DESSIN DU TALISMAN « OMBRE DE SANG » (menu START, 1er oct. 2026) —
// provisoire, en attendant le dessin de Kaoru.
// emplacement_talisman.gd le pose dans le rond et lui fournit `opacite`,
// `eveil` et `temps`.
// TOUT LE ROND est au dessin : un disque de nuit cerné d'un trait d'encre ; au
// fond des traits de vitesse ; devant, le SLASH du héros (un croissant rouge
// vif, son fil clair, son épée) et, décalé derrière lui, son ÉCHO — le même
// slash en sang sombre, un peu en retard, relié au premier par des traînées :
// le double qui refait le coup. Aplats et dégradés, reflets rouge clair (pas
// de blanc). Pointé ou porté (`eveil`) : l'écho rattrape le slash et repart.
// À dessiner dans un CARRÉ : le disque le remplit.

// --- fournis par emplacement_talisman.gd (les mêmes pour tout dessin de talisman) ---
uniform float opacite : hint_range(0.0, 1.0) = 1.0;
uniform float eveil : hint_range(0.0, 1.0) = 0.0;
uniform float temps = 0.0;
// ----------------------------------------------------------------------------

uniform vec4 encre_color : source_color = vec4(0.1, 0.02, 0.04, 1.0);
uniform vec4 fond_color : source_color = vec4(0.06, 0.02, 0.04, 1.0);
uniform vec4 fond_centre : source_color = vec4(0.16, 0.03, 0.05, 1.0);
uniform float trait : hint_range(0.0, 0.1) = 0.045;
uniform vec4 couleur : source_color = vec4(0.78, 0.04, 0.12, 1.0);
uniform vec4 couleur_vive : source_color = vec4(1.0, 0.17, 0.2, 1.0);
uniform vec4 sombre : source_color = vec4(0.32, 0.01, 0.06, 1.0);
uniform vec4 clair : source_color = vec4(1.0, 0.55, 0.52, 1.0);

float disque(float d, float r, float px) {
	return smoothstep(r + px * 0.5, r - px * 0.5, d);
}

void par_dessus(inout vec3 rgb, inout float a, vec3 teinte, float force) {
	float total = force + a * (1.0 - force);
	rgb = (teinte * force + rgb * a * (1.0 - force)) / max(total, 0.0001);
	a = total;
}

void forme(inout vec3 rgb, inout float a, float d, vec3 teinte, vec3 encre, float e, float px) {
	par_dessus(rgb, a, encre, smoothstep(0.0, px, d + e));
	par_dessus(rgb, a, teinte, smoothstep(0.0, px, d));
}

// un croissant de slash : bombé vers +x et vers le haut, effilé aux pointes
// (positif dedans) ; `g` reçoit 0 au bord d'attaque → 1 au bord de fuite
float croissant(vec2 p, float r, float ep, out float g) {
	float avant = r - length(p - vec2(-r * 0.5, r * 0.15));
	float arriere = r - length(p - vec2(-r * 0.5 - ep, r * 0.15 + ep * 0.35));
	g = clamp(avant / max(ep, 0.001), 0.0, 1.0);
	return min(avant, -arriere);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float px = fwidth(UV.x) * 2.0;
	float e = 0.035;

	vec3 rgb = encre_color.rgb;
	float a = disque(r, 1.0, px);
	float champ = disque(r, 1.0 - trait, px);
	rgb = mix(rgb, mix(fond_centre.rgb, fond_color.rgb, smoothstep(0.0, 0.95, r)), champ);

	vec3 f_rgb = couleur.rgb;
	float f_a = 0.0;

	// l'écho rattrape le slash puis repart (éveillé)
	float retard = 0.2 + 0.08 * sin(temps * 3.0) * eveil;
	vec2 c_slash = vec2(0.12, -0.05);
	vec2 c_echo = c_slash + vec2(-retard * 1.1, retard * 0.75);

	// ===================== LES TRAITS DE VITESSE =====================
	vec2 dir = normalize(c_slash - c_echo);
	vec2 nrm = vec2(-dir.y, dir.x);
	for (int k = 0; k < 5; k++) {
		float fk = float(k);
		float off = -0.6 + fk * 0.3;
		float le_long = dot(p, dir);
		float travers = dot(p, nrm);
		float s0 = -0.85 + 0.3 * fract(fk * 0.618 + temps * 0.5 * eveil);
		float d = min(0.012 - abs(travers - off), min(le_long - s0, s0 + 0.5 - le_long));
		par_dessus(f_rgb, f_a, sombre.rgb * 1.5, smoothstep(0.0, px, d) * 0.85);
	}

	// ===================== L'ÉCHO (derrière) =====================
	float g;
	float d_echo = croissant(p - c_echo, 0.62, 0.16, g);
	vec3 c_e = mix(sombre.rgb * 1.6, sombre.rgb, g);
	forme(f_rgb, f_a, d_echo, c_e, encre_color.rgb, e * 0.8, px);
	// les traînées entre l'écho et le slash : trois filets le long du bord d'attaque
	for (int k = 0; k < 3; k++) {
		float fk = float(k) - 1.0;
		vec2 a0 = c_echo + vec2(0.18, -0.32 + fk * 0.3);
		vec2 a1 = c_slash + vec2(0.18, -0.32 + fk * 0.3);
		vec2 pa = p - a0;
		vec2 ba = a1 - a0;
		float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
		float dt = 0.014 * (1.0 - h) - length(pa - ba * h);
		par_dessus(f_rgb, f_a, mix(sombre.rgb * 1.6, couleur.rgb, h), smoothstep(0.0, px, dt) * 0.9);
	}

	// ===================== LE SLASH (devant) =====================
	float d_slash = croissant(p - c_slash, 0.62, 0.18, g);
	vec3 c_s = mix(couleur_vive.rgb, couleur.rgb, smoothstep(0.0, 0.6, g));
	c_s = mix(c_s, sombre.rgb * 1.4, smoothstep(0.6, 1.0, g));
	forme(f_rgb, f_a, d_slash, c_s, encre_color.rgb, e, px);
	// son fil clair le long du bord d'attaque
	float bord = 0.62 - length(p - c_slash - vec2(-0.62 * 0.5, 0.62 * 0.15));
	par_dessus(f_rgb, f_a, clair.rgb, smoothstep(0.0, px, min(0.02 - abs(bord - 0.03), d_slash - 0.01)) * 0.85);

	// ===================== L'ÉPÉE, en bas à gauche =====================
	vec2 dir_e = normalize(vec2(1.0, -0.6));
	vec2 cote = vec2(-dir_e.y, dir_e.x);
	vec2 q = p - vec2(-0.55, 0.55);
	float u = dot(q, dir_e);
	float v = dot(q, cote);
	float s = (u - 0.1) / 0.5;
	float w = 0.055 * min(1.0, (1.0 - s) / 0.25);
	float lame = min(min(w - abs(v), u - 0.1), 0.6 - u);
	forme(f_rgb, f_a, lame, couleur.rgb * 0.85, encre_color.rgb, e, px);
	par_dessus(f_rgb, f_a, couleur.rgb * 0.62, smoothstep(0.0, px, min(lame, -v)) * 0.9);
	float garde = min(0.12 - abs(v), 0.028 - abs(u - 0.08));
	forme(f_rgb, f_a, garde, sombre.rgb * 1.8, encre_color.rgb, e, px);
	float poignee = min(0.028 - abs(v), min(0.05 - u, u + 0.13));
	forme(f_rgb, f_a, poignee, sombre.rgb * 1.5, encre_color.rgb, e, px);

	rgb = mix(rgb, f_rgb, f_a * champ);
	COLOR = vec4(rgb, a * opacite);
}
