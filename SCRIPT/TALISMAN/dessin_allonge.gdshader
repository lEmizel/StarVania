shader_type canvas_item;
render_mode unshaded;
// DESSIN DU TALISMAN « ALLONGE » (menu START, 1er oct. 2026) — provisoire, en
// attendant le dessin définitif.
// emplacement_talisman.gd le pose dans le rond et lui fournit `opacite`,
// `eveil` et `temps`.
// TOUT LE ROND est au dessin : un disque de nuit cerné d'un trait d'encre, au
// fond des arcs concentriques (une portée qu'on mesure) ; une ÉPÉE en biais ;
// devant sa pointe le CROISSANT de son coup, et au-delà un second arc en
// POINTILLÉS gradués comme une règle — la portée gagnée. Aplats rouges et
// encre, reflets rouge clair (pas de blanc). Pointé ou porté (`eveil`), les
// pointillés courent le long de l'arc.
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

	// le point d'où l'on mesure : la main, en bas à gauche
	vec2 main = vec2(-0.5, 0.5);
	vec2 q = p - main;
	float rq = length(q);
	float aq = atan(q.y, q.x);                       // vers le haut à droite : autour de -0.785

	// ===================== LES ARCS DE MESURE, au fond =====================
	for (int k = 0; k < 4; k++) {
		float rk = 0.4 + 0.3 * float(k);
		par_dessus(f_rgb, f_a, sombre.rgb * 1.5, smoothstep(0.0, px, 0.007 - abs(rq - rk)) * 0.8);
	}

	// ===================== LE CROISSANT DU COUP =====================
	// un arc épais au bout de l'épée, effilé à ses deux bouts
	float centre_ang = -0.785;
	float da = aq - centre_ang;
	float ouverture = 0.95;
	float t = clamp(abs(da) / ouverture, 0.0, 1.0);
	float ep = 0.1 * (1.0 - t * t);
	float r_coup = 1.05;
	float croissant = min(ep - abs(rq - r_coup + 0.03 * (1.0 - t * t)), ouverture - abs(da));
	forme(f_rgb, f_a, croissant, couleur.rgb, encre_color.rgb, e, px);
	par_dessus(f_rgb, f_a, clair.rgb, smoothstep(0.0, px, min(ep * 0.22 - abs(rq - r_coup - ep * 0.35), croissant - 0.012)) * 0.85);

	// ===================== LA PORTÉE GAGNÉE : un arc en pointillés gradués =====
	float r_plus = 1.3;
	float course = temps * 0.4 * eveil;
	float tiret = step(0.42, fract(aq * 9.0 + course));
	float pointilles = min(0.026 - abs(rq - r_plus), 0.85 - abs(da));
	forme(f_rgb, f_a, pointilles - (1.0 - tiret) * 0.05, couleur.rgb * 0.85, encre_color.rgb, e * 0.7, px);
	// les graduations, comme une règle
	float grad = abs(fract(aq * 6.0 / 1.0 + 0.5) - 0.5) / 6.0 * r_plus;
	float traits = min(0.012 - grad, min(0.075 - abs(rq - r_plus + 0.06), 0.85 - abs(da)));
	par_dessus(f_rgb, f_a, encre_color.rgb, smoothstep(0.0, px, traits));

	// ===================== L'ÉPÉE =====================
	vec2 dir = normalize(vec2(1.0, -1.0));
	vec2 cote = vec2(-dir.y, dir.x);
	float u = dot(q, dir);
	float v = dot(q, cote);
	float base = 0.15;
	float pointe = 0.95;
	float s = (u - base) / (pointe - base);
	float w = 0.075 * min(1.0, (1.0 - s) / 0.25);
	float lame = min(min(w - abs(v), u - base), pointe - u);
	forme(f_rgb, f_a, lame, couleur.rgb, encre_color.rgb, e, px);
	par_dessus(f_rgb, f_a, couleur.rgb * 0.7, smoothstep(0.0, px, min(lame, -v)) * 0.9);
	par_dessus(f_rgb, f_a, clair.rgb, smoothstep(0.0, px, min(0.01 - abs(v - 0.015), lame - 0.012)) * step(s, 0.82) * 0.85);
	float garde = min(0.17 - abs(v), 0.035 - abs(u - base + 0.02));
	forme(f_rgb, f_a, garde, sombre.rgb * 1.8, encre_color.rgb, e, px);
	float poignee = min(0.035 - abs(v), min(base - 0.05 - u, u + 0.12));
	forme(f_rgb, f_a, poignee, sombre.rgb * 1.5, encre_color.rgb, e, px);
	float pommeau = 0.05 - length(q + dir * 0.16);
	forme(f_rgb, f_a, pommeau, sombre.rgb * 1.8, encre_color.rgb, e, px);

	rgb = mix(rgb, f_rgb, f_a * champ);
	COLOR = vec4(rgb, a * opacite);
}
