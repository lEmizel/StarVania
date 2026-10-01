shader_type canvas_item;
render_mode unshaded;
// DESSIN DU TALISMAN « FRÉNÉSIE » (menu START, 1er oct. 2026) — provisoire,
// en attendant le dessin de Kaoru.
// emplacement_talisman.gd le pose dans le rond et lui fournit `opacite`,
// `eveil` et `temps`.
// TOUT LE ROND est au dessin : un disque de nuit cerné d'un trait d'encre, le
// DERNIER CŒUR au milieu, fêlé, et des VEINES de sang qui en partent jusqu'au
// bord du rond — les mêmes que celles qui envahissent les bords de l'écran en
// jeu. Pointé ou porté (`eveil`), le cœur bat vite (deux coups rapprochés) et
// les veines s'allument à chaque battement.
// À dessiner dans un CARRÉ : le disque le remplit.

// --- fournis par emplacement_talisman.gd (les mêmes pour tout dessin de talisman) ---
uniform float opacite : hint_range(0.0, 1.0) = 1.0;
uniform float eveil : hint_range(0.0, 1.0) = 0.0;
uniform float temps = 0.0;
// ----------------------------------------------------------------------------

uniform vec4 encre_color : source_color = vec4(0.1, 0.02, 0.04, 1.0);
uniform vec4 fond_color : source_color = vec4(0.06, 0.02, 0.04, 1.0);
uniform float trait : hint_range(0.0, 0.1) = 0.045;
uniform vec4 couleur_sombre : source_color = vec4(0.36, 0.0, 0.05, 1.0);
uniform vec4 couleur : source_color = vec4(0.85, 0.05, 0.12, 1.0);
uniform vec4 couleur_claire : source_color = vec4(1.0, 0.55, 0.5, 1.0);

float disque(float d, float r, float px) {
	return smoothstep(r + px * 0.5, r - px * 0.5, d);
}

void par_dessus(inout vec3 rgb, inout float a, vec3 teinte, float force) {
	float total = force + a * (1.0 - force);
	rgb = (teinte * force + rgb * a * (1.0 - force)) / max(total, 0.0001);
	a = total;
}

// distance signée à un cœur (négative dedans), pointe en bas, taille ~1
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

// un battement « lub-dub » : deux coups rapprochés, puis le repos
float battement(float t) {
	float c = fract(t);
	return exp(-c * 18.0) + 0.6 * exp(-max(c - 0.2, 0.0) * 18.0) * step(0.2, c);
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

	float b = battement(temps * mix(0.8, 1.7, eveil)) * mix(0.35, 1.0, eveil);
	vec3 f_rgb = vec3(0.0);
	float f_a = 0.0;

	// ===================== LES VEINES =====================
	// six veines qui partent du cœur vers le bord en ondulant, chacune avec
	// une branche ; elles s'épaississent et s'allument à chaque battement
	for (int i = 0; i < 6; i++) {
		float fi = float(i);
		float theta = fi * TAU / 6.0 + 0.4;
		vec2 dir = vec2(cos(theta), sin(theta));
		vec2 cote = vec2(-dir.y, dir.x);
		float u = dot(p, dir);
		float v = dot(p, cote) - 0.07 * sin(u * 9.0 + fi * 1.7) * smoothstep(0.2, 0.6, u);
		float ep = mix(0.035, 0.012, clamp((u - 0.25) / 0.7, 0.0, 1.0)) * (1.0 + 0.5 * b);
		float veine = min(ep - abs(v), min(u - 0.22, 0.97 - u));
		// la branche : part aux deux tiers, s'écarte d'un côté
		float ub = u - 0.55;
		float vb = dot(p, cote) - (0.05 + ub * 0.7) * (mod(fi, 2.0) * 2.0 - 1.0);
		float branche = min(0.012 * (1.0 + 0.5 * b) - abs(vb), min(ub, 0.3 - ub));
		float d = max(veine, branche);
		par_dessus(f_rgb, f_a, mix(couleur_sombre.rgb, couleur.rgb, b), smoothstep(0.0, px, d));
	}

	// ===================== LE DERNIER CŒUR =====================
	float taille = 0.46 * (1.0 + 0.1 * b);
	vec2 q = p / taille;
	q.y += 0.12;
	float dc = sd_coeur(q) * taille;
	par_dessus(f_rgb, f_a, encre_color.rgb, smoothstep(px, -px, dc - 0.035));
	vec3 coeur = mix(couleur.rgb, couleur_sombre.rgb, smoothstep(-0.3, 0.4, p.y + p.x * 0.5));
	coeur = mix(coeur, couleur_claire.rgb, 0.35 * b);
	par_dessus(f_rgb, f_a, coeur, smoothstep(px, -px, dc));
	// le reflet
	par_dessus(f_rgb, f_a, couleur_claire.rgb, disque(length(p - vec2(-0.17, -0.2)), 0.055, px) * 0.85);
	// la fêlure : un zigzag d'encre du haut vers le milieu
	float zz = abs(p.x - 0.04 - 0.05 * sign(sin(p.y * 22.0)) * abs(fract(p.y * 7.0) - 0.5));
	float fele = min(0.016 - zz, min(p.y + 0.3, 0.12 - p.y));
	par_dessus(f_rgb, f_a, encre_color.rgb, smoothstep(0.0, px, fele) * smoothstep(px, -px, dc));
	rgb = mix(rgb, f_rgb, f_a * champ);

	COLOR = vec4(rgb, a * opacite);
}
