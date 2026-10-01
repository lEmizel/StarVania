shader_type canvas_item;
render_mode unshaded;
// DESSIN DU TALISMAN « INÉBRANLABLE » (menu START, 2 oct. 2026) — provisoire,
// en attendant le dessin de Kaoru.
// emplacement_talisman.gd le pose dans le rond et lui fournit `opacite`,
// `eveil` et `temps`.
// TOUT LE ROND est au dessin : un disque de nuit cerné d'un trait d'encre ; un
// SOL sombre fendu ; planté dessus, un lourd ROC de sang à facettes ; des deux
// côtés, des CHEVRONS (les coups) qui viennent s'y briser. Aplats rouges et
// encre, reflet rouge clair (pas de blanc). Pointé ou porté (`eveil`), les
// chevrons foncent sur le roc et s'y écrasent (un éclat rouge clair), le roc ne
// bouge pas, ses fissures battent.
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
uniform vec4 couleur : source_color = vec4(0.62, 0.1, 0.12, 1.0);
uniform vec4 sombre : source_color = vec4(0.3, 0.01, 0.06, 1.0);
uniform vec4 clair : source_color = vec4(1.0, 0.5, 0.5, 1.0);

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

// distance à un segment
float segment(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

// les sommets du roc (un hexagone un peu irrégulier, base à plat)
vec2 sommet(int i) {
	if (i == 0) return vec2(-0.4, 0.42);
	if (i == 1) return vec2(-0.47, 0.02);
	if (i == 2) return vec2(-0.2, -0.36);
	if (i == 3) return vec2(0.24, -0.38);
	if (i == 4) return vec2(0.46, -0.02);
	return vec2(0.4, 0.42);
}

// distance signée au roc (négative dedans)
float sd_roc(vec2 p) {
	float d = dot(p - sommet(0), p - sommet(0));
	float s = 1.0;
	for (int i = 0; i < 6; i++) {
		int j = i == 0 ? 5 : i - 1;
		vec2 vi = sommet(i);
		vec2 vj = sommet(j);
		vec2 ed = vj - vi;
		vec2 w = p - vi;
		vec2 b = w - ed * clamp(dot(w, ed) / dot(ed, ed), 0.0, 1.0);
		d = min(d, dot(b, b));
		bvec3 cond = bvec3(p.y >= vi.y, p.y < vj.y, ed.x * w.y > ed.y * w.x);
		if (all(cond) || all(not(cond))) s *= -1.0;
	}
	return s * sqrt(d);
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

	// éveillé : les chevrons foncent (0 → 0,5 du cycle) et s'écrasent sur le roc
	float cycle = fract(temps * 0.7);
	float avance = smoothstep(0.0, 0.5, cycle) * eveil;
	float choc = eveil * (1.0 - smoothstep(0.5, 0.75, cycle)) * step(0.5, cycle);

	// ===================== LE SOL FENDU =====================
	float sol = p.y - 0.52;
	par_dessus(f_rgb, f_a, sombre.rgb * 0.75, smoothstep(0.0, px, sol));
	par_dessus(f_rgb, f_a, encre_color.rgb, smoothstep(px, 0.0, abs(sol) - 0.014));
	// les fissures qui partent du pied du roc
	float fissures = 10.0;
	fissures = min(fissures, segment(p, vec2(-0.3, 0.52), vec2(-0.62, 0.78)));
	fissures = min(fissures, segment(p, vec2(-0.62, 0.78), vec2(-0.7, 0.98)));
	fissures = min(fissures, segment(p, vec2(0.1, 0.52), vec2(0.18, 0.82)));
	fissures = min(fissures, segment(p, vec2(0.32, 0.52), vec2(0.66, 0.72)));
	float bat = 0.6 + 0.4 * choc;
	par_dessus(f_rgb, f_a, mix(encre_color.rgb, couleur.rgb, choc), smoothstep(px, 0.0, fissures - 0.014) * bat);

	// ===================== LES CHEVRONS =====================
	for (int i = 0; i < 4; i++) {
		float cote = i < 2 ? -1.0 : 1.0;
		float rang = float(i % 2);
		// au repos : posés de part et d'autre ; éveillés : ils foncent sur le roc
		float x = cote * (0.86 - rang * 0.17 - avance * (0.3 - rang * 0.0));
		float vis = 1.0 - smoothstep(0.42, 0.5, cycle) * eveil * step(rang, 0.5)
			- smoothstep(0.46, 0.52, cycle) * eveil * step(0.5, rang);
		vis = clamp(vis, 0.0, 1.0);
		vec2 q = vec2((p.x - x) * -cote, p.y - 0.02);
		// un « > » tourné vers le roc
		float d_ch = min(segment(q, vec2(-0.06, -0.12), vec2(0.05, 0.0)), segment(q, vec2(0.05, 0.0), vec2(-0.06, 0.12))) - 0.035;
		forme(f_rgb, f_a, -d_ch * vis - (1.0 - vis) * 0.2, couleur.rgb * 0.9, encre_color.rgb, e * 0.7, px);
	}

	// ===================== LE ROC =====================
	vec2 pr = p - vec2(0.0, 0.08);
	float d_roc = -sd_roc(pr);
	forme(f_rgb, f_a, d_roc, couleur.rgb, encre_color.rgb, e, px);
	// ses facettes : trois tons autour d'un point haut à gauche
	vec2 centre = vec2(-0.06, -0.06);
	vec2 v = pr - centre;
	float ang = atan(v.y, v.x);
	float facette = ang < -2.0 ? 0.0 : (ang < -0.4 ? 1.0 : (ang < 1.2 ? 2.0 : 3.0));
	vec3 ton = facette == 1.0 ? couleur.rgb * 1.12 : (facette == 2.0 ? couleur.rgb * 0.82 : (facette == 3.0 ? sombre.rgb * 1.5 : couleur.rgb * 0.95));
	par_dessus(f_rgb, f_a, ton, smoothstep(0.0, px, d_roc - 0.02));
	// les arêtes, à l'encre
	float aretes = 10.0;
	for (int i = 0; i < 6; i++) {
		aretes = min(aretes, segment(pr, centre, sommet(i)));
	}
	par_dessus(f_rgb, f_a, encre_color.rgb, smoothstep(px, 0.0, aretes - 0.011) * smoothstep(0.0, px, d_roc - 0.02));
	// un reflet rouge clair sur l'arête du haut
	float reflet = segment(pr, vec2(-0.17, -0.3), vec2(0.18, -0.32)) - 0.016;
	par_dessus(f_rgb, f_a, clair.rgb, smoothstep(px, 0.0, reflet) * 0.85);

	// ===================== LES ÉCLATS DU CHOC =====================
	for (int i = 0; i < 2; i++) {
		float cote = i == 0 ? -1.0 : 1.0;
		vec2 ce = p - vec2(cote * 0.5, 0.06);
		float ae = atan(ce.y, ce.x);
		float rayon = 0.05 + 0.1 * pow(abs(cos(ae * 2.0)), 8.0);
		float d_e = rayon * (0.6 + 0.6 * choc) - length(ce);
		par_dessus(f_rgb, f_a, clair.rgb, smoothstep(0.0, px, d_e) * choc);
	}

	rgb = mix(rgb, f_rgb, f_a * champ);
	COLOR = vec4(rgb, a * opacite);
}
