shader_type canvas_item;
render_mode unshaded;
// DESSIN DU TALISMAN « VENGEANCE » (menu START, 1er oct. 2026) — provisoire,
// en attendant le dessin de Kaoru.
// emplacement_talisman.gd le pose dans le rond et lui fournit `opacite`,
// `eveil` et `temps`.
// TOUT LE ROND est au dessin : un disque de nuit cerné d'un trait d'encre, au
// fond des rayons sombres ; en bas un CŒUR BLESSÉ (une entaille d'encre, une
// goutte qui en coule) ; au-dessus, flottante, la même COURONNE DE SANG qu'en
// jeu — cinq pointes, une bande sombre, un joyau en goutte. Aplats rouges et
// encre, reflets rouge clair (pas de blanc). Pointé ou porté (`eveil`), la
// couronne flotte et oscille, la goutte tombe.
// À dessiner dans un CARRÉ : le disque le remplit.

// --- fournis par emplacement_talisman.gd (les mêmes pour tout dessin de talisman) ---
uniform float opacite : hint_range(0.0, 1.0) = 1.0;
uniform float eveil : hint_range(0.0, 1.0) = 0.0;
uniform float temps = 0.0;
// ----------------------------------------------------------------------------

uniform vec4 encre_color : source_color = vec4(0.1, 0.02, 0.04, 1.0);
uniform vec4 fond_color : source_color = vec4(0.06, 0.02, 0.04, 1.0);
uniform vec4 fond_centre : source_color = vec4(0.18, 0.03, 0.06, 1.0);
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

float triangle(vec2 p, vec2 q) {
	p.x = abs(p.x);
	vec2 a = p - q * clamp(dot(p, q) / dot(q, q), 0.0, 1.0);
	vec2 b = p - q * vec2(clamp(p.x / q.x, 0.0, 1.0), 1.0);
	float s = -sign(q.y);
	vec2 d = min(vec2(dot(a, a), s * (p.x * q.y - p.y * q.x)), vec2(dot(b, b), s * (p.y - q.y)));
	return -sqrt(d.x) * sign(d.y);
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

	vec3 f_rgb = couleur.rgb;
	float f_a = 0.0;

	// ===================== LES RAYONS DU FOND =====================
	vec2 c_rayons = vec2(0.0, -0.32);
	float ar = atan(p.y - c_rayons.y, p.x - c_rayons.x);
	float rr = length(p - c_rayons);
	float rayons = smoothstep(0.75, 1.0, abs(sin(ar * 9.0))) * smoothstep(0.25, 0.4, rr);
	par_dessus(f_rgb, f_a, sombre.rgb, rayons * 0.6);

	// ===================== LE CŒUR BLESSÉ =====================
	float tc = 0.36;
	vec2 qc = (p - vec2(0.0, 0.3)) / tc;
	qc.y += 0.1;
	float dc = -sd_coeur(qc) * tc;
	forme(f_rgb, f_a, dc, couleur.rgb, encre_color.rgb, e, px);
	par_dessus(f_rgb, f_a, couleur.rgb * 0.72, smoothstep(0.0, px, min(dc, p.y - 0.36 + p.x * 0.3)) * 0.9);
	par_dessus(f_rgb, f_a, clair.rgb, smoothstep(0.0, px, min(0.045 - length((p - vec2(-0.15, 0.2)) * vec2(1.0, 1.35)), dc - 0.02)) * 0.85);
	// l'entaille : un trait d'encre en biais
	vec2 qe = p - vec2(0.04, 0.33);
	float entaille = min(0.02 - abs(qe.y + qe.x * 0.55), 0.17 - abs(qe.x));
	par_dessus(f_rgb, f_a, encre_color.rgb, smoothstep(0.0, px, min(entaille, dc)));
	// la goutte qui coule de l'entaille (éveillé : elle tombe)
	float chute = eveil * fract(temps * 0.5) * 0.25;
	vec2 qg = p - vec2(0.12, 0.47 + chute);
	float dg = 0.04 - length(vec2(qg.x, qg.y < 0.0 ? qg.y * 0.45 : qg.y));
	forme(f_rgb, f_a, dg, couleur.rgb, encre_color.rgb, e * 0.7, px);

	// ===================== LA COURONNE DE SANG =====================
	float flotte = 0.025 * sin(temps * 2.4) * eveil;
	vec2 q = p - vec2(0.0, -0.32 + flotte);
	float penche = 0.05 * sin(temps * 1.7) * eveil;
	q = vec2(cos(penche) * q.x - sin(penche) * q.y, sin(penche) * q.x + cos(penche) * q.y);
	float larg = 0.5;
	float bande = 0.17;
	float haut = 0.42;
	for (int i = 0; i < 5; i++) {
		float fi = float(i) - 2.0;
		float rang = abs(fi);
		float h = haut * mix(1.0, 0.62, rang * 0.5);
		vec2 qp = q - vec2(fi * larg * 0.4, -bande * 0.5);
		qp.x -= fi * 0.12 * max(-qp.y, 0.0);
		float dp = -triangle(vec2(qp.x, qp.y + h), vec2(larg * 0.17, h));
		forme(f_rgb, f_a, dp, couleur.rgb, encre_color.rgb, e, px);
		// un reflet sur le flanc gauche de chaque pointe
		par_dessus(f_rgb, f_a, clair.rgb, smoothstep(0.0, px, min(dp - 0.015, -(qp.x + 0.01))) * 0.35);
	}
	float yb = q.y + 0.1 * q.x * q.x;
	float d_bande = min(larg - abs(q.x), bande * 0.5 - abs(yb - bande * 0.15));
	forme(f_rgb, f_a, d_bande, couleur.rgb, encre_color.rgb, e, px);
	par_dessus(f_rgb, f_a, sombre.rgb, smoothstep(0.0, px, min(min(larg - 0.04 - abs(q.x), 0.025 - abs(yb - bande * 0.42)), d_bande - 0.015)));
	// le joyau en goutte au milieu de la bande
	vec2 qj = q - vec2(0.0, bande * 0.1);
	float d_joyau = max(0.068 - length(qj * vec2(1.0, 0.85)), -triangle(vec2(qj.x, qj.y + 0.14), vec2(0.055, 0.1)));
	forme(f_rgb, f_a, d_joyau, sombre.rgb, encre_color.rgb, e * 0.8, px);
	par_dessus(f_rgb, f_a, clair.rgb, smoothstep(0.0, px, 0.016 - length(qj - vec2(-0.02, -0.01))) * 0.8);

	rgb = mix(rgb, f_rgb, f_a * champ);
	COLOR = vec4(rgb, a * opacite);
}
