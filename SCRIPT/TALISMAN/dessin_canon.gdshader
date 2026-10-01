shader_type canvas_item;
render_mode unshaded;
// DESSIN DU TALISMAN « CANON DE VERRE » (menu START, 1er oct. 2026, refait le
// même jour : « un poil trop simpliste ») — provisoire, en attendant le dessin
// de Kaoru.
// emplacement_talisman.gd le pose dans le rond et lui fournit `opacite`,
// `eveil` et `temps`.
// TOUT LE ROND est au dessin : un disque de nuit cerné d'un trait d'encre, au
// fond du VERRE BRISÉ (des fêlures qui rayonnent d'un point d'impact, deux
// cercles cassés) ; en biais, une ÉPÉE DE CRISTAL de sang — lame taillée en
// deux facettes de part et d'autre de son arête, fêlée, garde à gemme, poignée
// bandée — qui perd des ÉCLATS. Terrible mais fragile. Aplats rouges et encre,
// reflets rouge clair (pas de blanc). Pointé ou porté (`eveil`), les éclats
// s'écartent et tournent.
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
uniform vec4 couleur : source_color = vec4(0.8, 0.05, 0.13, 1.0);
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

float segment(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

float alea(float n) {
	n = fract(n * 0.1031);
	n *= n + 33.33;
	n *= n + n;
	return fract(n);
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

	// ===================== LE VERRE BRISÉ =====================
	vec2 impact = vec2(0.28, -0.3);
	vec2 qi = p - impact;
	float ri = length(qi);
	float ai = atan(qi.y, qi.x);
	float n_f = 9.0;
	float secteur = floor(ai / TAU * n_f + 0.5);
	float ai0 = (secteur + 0.25 * (alea(secteur + 3.0) - 0.5)) * TAU / n_f;
	vec2 df = vec2(cos(ai0), sin(ai0));
	float zig = 0.02 * sin(ri * 23.0 + secteur * 1.7);
	float fissure = 0.008 - abs(dot(qi, vec2(-df.y, df.x)) + zig);
	fissure = min(fissure, dot(qi, df));
	par_dessus(f_rgb, f_a, sombre.rgb * 1.7, smoothstep(0.0, px, fissure) * 0.9);
	for (int k = 0; k < 2; k++) {
		float rk = 0.32 + 0.3 * float(k);
		float casse = step(0.35, alea(secteur * 1.3 + float(k) * 7.0));
		par_dessus(f_rgb, f_a, sombre.rgb * 1.5, smoothstep(0.0, px, 0.007 - abs(ri - rk - 0.02 * sin(ai * 5.0))) * casse * 0.9);
	}

	// ===================== L'ÉPÉE DE CRISTAL =====================
	vec2 dir = normalize(vec2(1.0, -1.0));              // vers la pointe (en haut à droite)
	vec2 cote = vec2(-dir.y, dir.x);
	float u = dot(p, dir);
	float v = dot(p, cote);
	// la lame : large, pointe effilée, deux facettes de part et d'autre de l'arête
	float base = -0.38;
	float pointe = 0.86;
	float s = (u - base) / (pointe - base);
	float w = 0.13 * min(1.0, (1.0 - s) / 0.3);
	float lame = min(min(w - abs(v), u - base), pointe - u);
	forme(f_rgb, f_a, lame, couleur.rgb, encre_color.rgb, e, px);
	// la facette à l'ombre (un côté de l'arête) et le fil clair de l'arête
	par_dessus(f_rgb, f_a, couleur.rgb * 0.68, smoothstep(0.0, px, min(lame, -v)) * 0.95);
	par_dessus(f_rgb, f_a, clair.rgb, smoothstep(0.0, px, min(0.012 - abs(v - 0.02), lame - 0.015)) * step(s, 0.86) * 0.9);
	// les fêlures sur la lame
	for (int i = 0; i < 2; i++) {
		float u0 = mix(-0.05, 0.36, float(i));
		vec2 a0 = dir * u0 + cote * 0.13;
		vec2 b0 = dir * (u0 + 0.05) + cote * 0.01;
		vec2 c0 = dir * (u0 + 0.01) - cote * 0.13;
		float dfl = min(segment(p, a0, b0), segment(p, b0, c0));
		par_dessus(f_rgb, f_a, encre_color.rgb, smoothstep(0.0, px, min(0.011 - dfl, lame)));
	}
	// la garde, sa gemme, la poignée bandée, le pommeau
	float garde = min(0.27 - abs(v), 0.045 - abs(u - base + 0.03));
	forme(f_rgb, f_a, garde, sombre.rgb * 1.8, encre_color.rgb, e, px);
	float gemme = 0.055 - length(p - dir * (base - 0.03));
	forme(f_rgb, f_a, gemme, couleur.rgb, encre_color.rgb, e * 0.8, px);
	par_dessus(f_rgb, f_a, clair.rgb, smoothstep(0.0, px, 0.018 - length(p - dir * (base - 0.03) - vec2(-0.015, -0.015))) * 0.9);
	float poignee = min(0.045 - abs(v), min(base - 0.075 - u, u - (base - 0.36)));
	forme(f_rgb, f_a, poignee, sombre.rgb * 1.5, encre_color.rgb, e, px);
	float bandes = smoothstep(0.0, px, min(0.01 - abs(fract((u - base) * 14.0) - 0.5) / 14.0, poignee));
	par_dessus(f_rgb, f_a, encre_color.rgb, bandes);
	float pommeau = 0.065 - length(p - dir * (base - 0.42));
	forme(f_rgb, f_a, pommeau, sombre.rgb * 1.8, encre_color.rgb, e, px);

	// ===================== LES ÉCLATS QUI SE DÉTACHENT =====================
	for (int i = 0; i < 5; i++) {
		float fi = float(i);
		float h1 = alea(fi * 1.7 + 2.0);
		float h2 = alea(fi * 3.3 + 5.0);
		float ecarte = 1.0 + 0.25 * eveil * (0.5 + 0.5 * sin(temps * 1.5 + fi));
		vec2 c = dir * mix(-0.05, 0.5, h1) + cote * (0.22 + 0.14 * h2) * (fi < 2.5 ? 1.0 : -1.0) * ecarte;
		float rot = fi * 1.9 + temps * 0.8 * eveil * (h2 - 0.5);
		vec2 q = p - c;
		q = vec2(cos(rot) * q.x - sin(rot) * q.y, sin(rot) * q.x + cos(rot) * q.y);
		float t = mix(0.06, 0.09, h2);
		// un éclat : un petit triangle effilé
		float d = min(min(t - abs(q.x) * 1.8 - q.y, q.y + t * 0.6), t);
		forme(f_rgb, f_a, d, mix(couleur.rgb, clair.rgb, 0.3), encre_color.rgb, e * 0.6, px);
	}

	rgb = mix(rgb, f_rgb, f_a * champ);
	COLOR = vec4(rgb, a * opacite);
}
