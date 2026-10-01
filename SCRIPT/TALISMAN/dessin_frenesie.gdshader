shader_type canvas_item;
render_mode unshaded;
// DESSIN DU TALISMAN « FRÉNÉSIE » (menu START, 1er oct. 2026, refait le même
// jour : « un poil trop simpliste ») — provisoire, en attendant le dessin de
// Kaoru.
// emplacement_talisman.gd le pose dans le rond et lui fournit `opacite`,
// `eveil` et `temps`.
// TOUT LE ROND est au dessin : un disque de nuit cerné d'un trait d'encre, au
// fond une AURA DE RAGE déchiquetée en deux couches ; en travers, trois
// GRIFFURES de sang ; quelques veines ; au centre le DERNIER CŒUR, fêlé.
// Aplats rouges et encre, reflets rouge clair (pas de blanc). Pointé ou porté
// (`eveil`), le cœur bat vite (deux coups rapprochés) et l'aura vacille.
// À dessiner dans un CARRÉ : le disque le remplit.

// --- fournis par emplacement_talisman.gd (les mêmes pour tout dessin de talisman) ---
uniform float opacite : hint_range(0.0, 1.0) = 1.0;
uniform float eveil : hint_range(0.0, 1.0) = 0.0;
uniform float temps = 0.0;
// ----------------------------------------------------------------------------

uniform vec4 encre_color : source_color = vec4(0.1, 0.02, 0.04, 1.0);
uniform vec4 fond_color : source_color = vec4(0.06, 0.02, 0.04, 1.0);
uniform vec4 fond_centre : source_color = vec4(0.18, 0.03, 0.05, 1.0);
uniform float trait : hint_range(0.0, 0.1) = 0.045;
uniform vec4 couleur : source_color = vec4(0.85, 0.05, 0.12, 1.0);
uniform vec4 sombre : source_color = vec4(0.32, 0.01, 0.06, 1.0);
uniform vec4 clair : source_color = vec4(1.0, 0.52, 0.48, 1.0);

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

float sd_coeur(vec2 q) {
	q.x = abs(q.x);
	q.y = -q.y + 0.35;
	if (q.y + q.x > 1.0) {
		return sqrt(dot(q - vec2(0.25, 0.75), q - vec2(0.25, 0.75))) - sqrt(2.0) / 4.0;
	}
	float d1 = dot(q - vec2(0.0, 1.0), q - vec2(0.0, 1.0));
	float m = 0.5 * max(q.x + q.y, 0.0);
	float d2 = dot(q - vec2(m), q - vec2(m));
	return sqrt(min(d1, d2)) * sign(q.x - q.y);
}

// un battement « poum-poum » : deux coups rapprochés, puis le repos
float battement(float t) {
	float c = fract(t);
	return max(exp(-c * 14.0), 0.65 * exp(-max(c - 0.18, 0.0) * 14.0) * step(0.18, c));
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float px = fwidth(UV.x) * 2.0;
	float ang = atan(p.y, p.x);
	float e = 0.04;

	vec3 rgb = encre_color.rgb;
	float a = disque(r, 1.0, px);
	float champ = disque(r, 1.0 - trait, px);
	rgb = mix(rgb, mix(fond_centre.rgb, fond_color.rgb, smoothstep(0.0, 0.95, r)), champ);

	float b = battement(temps * mix(0.7, 1.6, eveil)) * mix(0.3, 1.0, eveil);
	float vacille = eveil * 0.04 * sin(temps * 9.0);
	vec3 f_rgb = couleur.rgb;
	float f_a = 0.0;

	// ===================== L'AURA DE RAGE : deux couronnes déchiquetées ======
	for (int k = 0; k < 2; k++) {
		float fk = float(k);
		float dents = abs(fract(ang * (fk == 0.0 ? 9.0 : 7.0) / TAU + 0.13 * fk) - 0.5) * 2.0;   // 0 au creux, 1 à la pointe
		float r_aura = mix(0.86, 0.66, fk) * (0.72 + 0.28 * pow(dents, 1.6)) + vacille + 0.03 * b;
		float d = r_aura - r;
		par_dessus(f_rgb, f_a, mix(sombre.rgb, sombre.rgb * 1.9, fk), smoothstep(0.0, px, d));
	}

	// ===================== LES VEINES =====================
	for (int i = 0; i < 5; i++) {
		float fi = float(i);
		float theta = fi * TAU / 5.0 + 0.5;
		vec2 dir = vec2(cos(theta), sin(theta));
		vec2 cote = vec2(-dir.y, dir.x);
		float u = dot(p, dir);
		float v = dot(p, cote) - 0.05 * sin(u * 11.0 + fi * 1.7) * smoothstep(0.25, 0.6, u);
		float ep = mix(0.025, 0.008, clamp((u - 0.3) / 0.6, 0.0, 1.0)) * (1.0 + 0.6 * b);
		float d = min(ep - abs(v), min(u - 0.3, 0.92 - u));
		par_dessus(f_rgb, f_a, mix(couleur.rgb * 0.7, couleur.rgb, b), smoothstep(0.0, px, d));
	}

	// ===================== LES TROIS GRIFFURES =====================
	vec2 dg = normalize(vec2(1.0, -0.62));
	vec2 cg = vec2(-dg.y, dg.x);
	for (int i = 0; i < 3; i++) {
		float fi = float(i) - 1.0;
		vec2 q = p - cg * fi * 0.2;
		float x = dot(q, dg);
		float y = dot(q, cg) - 0.12 * (x * x - 0.3);      // un peu cambrées
		float lim = 0.78 - 0.1 * abs(fi);
		float w = 0.045 * max(1.0 - pow(x / lim, 2.0), 0.0);
		float d = w - abs(y);
		forme(f_rgb, f_a, d, couleur.rgb, encre_color.rgb, e * 0.8, px);
		par_dessus(f_rgb, f_a, clair.rgb, smoothstep(0.0, px, min(w * 0.28 - abs(y + w * 0.35), d - 0.012)) * 0.75);
	}

	// ===================== LE DERNIER CŒUR =====================
	float tc = 0.42 * (1.0 + 0.09 * b);
	vec2 qc = p / tc;
	qc.y += 0.1;
	float dc = -sd_coeur(qc) * tc;
	forme(f_rgb, f_a, dc + 0.012, encre_color.rgb, encre_color.rgb, e, px);   // un halo d'encre épais
	forme(f_rgb, f_a, dc, mix(couleur.rgb, clair.rgb, 0.18 * b), encre_color.rgb, e, px);
	// l'ombre du bas du cœur, et son reflet
	par_dessus(f_rgb, f_a, couleur.rgb * 0.72, smoothstep(0.0, px, min(dc, p.y + p.x * 0.3 - 0.06)) * 0.9);
	par_dessus(f_rgb, f_a, clair.rgb, smoothstep(0.0, px, min(0.055 - length((p - vec2(-0.15, -0.17)) * vec2(1.0, 1.35)), dc - 0.02)) * 0.85);
	// la fêlure : un zigzag d'encre du haut vers le milieu du cœur
	float zz = abs(p.x - 0.03 - 0.07 * (abs(fract(p.y * 4.0 + 0.2) - 0.5) - 0.25));
	float fele = min(0.016 - zz, min(p.y + 0.32, 0.16 - p.y));
	par_dessus(f_rgb, f_a, encre_color.rgb, smoothstep(0.0, px, min(fele, dc)));

	rgb = mix(rgb, f_rgb, f_a * champ);
	COLOR = vec4(rgb, a * opacite);
}
