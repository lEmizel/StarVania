shader_type canvas_item;
render_mode unshaded;
// DESSIN DU TALISMAN « CROISSANT DE SANG » (menu START, 1er oct. 2026) —
// provisoire, en attendant le dessin définitif.
// emplacement_talisman.gd le pose dans le rond et lui fournit `opacite`,
// `eveil` et `temps`.
// TOUT LE ROND est au dessin : un disque de nuit cerné d'un trait d'encre, au
// fond des lignes de vitesse ; une ÉPÉE en bas à gauche dont le coup LÂCHE un
// grand CROISSANT de sang qui file vers la droite, avec ses traînées. Aplats
// rouges et encre, reflets rouge clair (pas de blanc). Pointé ou porté
// (`eveil`), le croissant avance et revient, ses traînées s'étirent.
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

// un croissant bombé vers +x (positif dedans)
float croissant(vec2 p, float r, float ep) {
	float avant = r - length(p - vec2(-r * 0.55, 0.0));
	float arriere = r - length(p - vec2(-r * 0.55 - ep, 0.0));
	return min(avant, -arriere);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float px = fwidth(UV.x) * 2.0;
	float e = 0.04;

	vec3 rgb = encre_color.rgb;
	float a = disque(r, 1.0, px);
	float champ = disque(r, 1.0 - trait, px);
	rgb = mix(rgb, mix(fond_centre.rgb, fond_color.rgb, smoothstep(0.0, 0.95, r)), champ);

	vec3 f_rgb = couleur.rgb;
	float f_a = 0.0;

	// ===================== LES LIGNES DE VITESSE =====================
	for (int i = 0; i < 6; i++) {
		float fi = float(i);
		float y = -0.62 + fi * 0.25;
		float x0 = -0.85 + 0.25 * fract(fi * 0.618 + temps * 0.6 * eveil);
		float d = min(0.012 - abs(p.y - y), min(p.x - x0, x0 + 0.55 - p.x));
		par_dessus(f_rgb, f_a, sombre.rgb * 1.6, smoothstep(0.0, px, d) * 0.9);
	}

	// ===================== LE CROISSANT ET SES TRAÎNÉES =====================
	float avance = 0.06 * sin(temps * 2.2) * eveil;
	vec2 c = vec2(0.22 + avance, -0.1);
	for (int k = 3; k >= 1; k--) {
		float fk = float(k);
		vec2 q = p - c + vec2(fk * (0.13 + 0.03 * eveil), 0.0);
		float d = croissant(q, 0.6 * (1.0 - fk * 0.06), 0.12 * (0.5 - fk * 0.12));
		d = min(d, 0.6 * (0.62 - fk * 0.12) - abs(q.y));
		par_dessus(f_rgb, f_a, mix(couleur.rgb, sombre.rgb * 1.6, fk / 3.0), smoothstep(0.0, px, d));
	}
	float dc = croissant(p - c, 0.6, 0.14);
	forme(f_rgb, f_a, dc, couleur.rgb, encre_color.rgb, e, px);
	par_dessus(f_rgb, f_a, clair.rgb, smoothstep(0.0, px, min(dc - 0.02, 0.6 - length(p - c - vec2(-0.6 * 0.55 + 0.015, 0.0)) - 0.02)) * 0.0);
	// un fil clair le long du bord avant
	float bord = 0.6 - length(p - c - vec2(-0.6 * 0.55, 0.0));
	par_dessus(f_rgb, f_a, clair.rgb, smoothstep(0.0, px, min(0.022 - abs(bord - 0.035), dc - 0.012)) * 0.85);

	// ===================== L'ÉPÉE, en bas à gauche =====================
	vec2 dir = normalize(vec2(1.0, -0.55));
	vec2 cote = vec2(-dir.y, dir.x);
	vec2 q = p - vec2(-0.6, 0.55);
	float u = dot(q, dir);
	float v = dot(q, cote);
	float s = (u - 0.1) / 0.55;
	float w = 0.06 * min(1.0, (1.0 - s) / 0.25);
	float lame = min(min(w - abs(v), u - 0.1), 0.65 - u);
	forme(f_rgb, f_a, lame, couleur.rgb * 0.85, encre_color.rgb, e, px);
	par_dessus(f_rgb, f_a, couleur.rgb * 0.62, smoothstep(0.0, px, min(lame, -v)) * 0.9);
	float garde = min(0.13 - abs(v), 0.03 - abs(u - 0.08));
	forme(f_rgb, f_a, garde, sombre.rgb * 1.8, encre_color.rgb, e, px);
	float poignee = min(0.03 - abs(v), min(0.05 - u, u + 0.14));
	forme(f_rgb, f_a, poignee, sombre.rgb * 1.5, encre_color.rgb, e, px);
	float pommeau = 0.04 - length(q + dir * 0.17);
	forme(f_rgb, f_a, pommeau, sombre.rgb * 1.8, encre_color.rgb, e, px);

	rgb = mix(rgb, f_rgb, f_a * champ);
	COLOR = vec4(rgb, a * opacite);
}
