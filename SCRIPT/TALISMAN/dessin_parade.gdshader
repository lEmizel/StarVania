shader_type canvas_item;
render_mode unshaded;
// DESSIN DU TALISMAN « PARADE » (menu START, 1er oct. 2026) — provisoire, en
// attendant le dessin de Kaoru.
// emplacement_talisman.gd le pose dans le rond et lui fournit `opacite`,
// `eveil` et `temps`.
// TOUT LE ROND est au dessin : un disque de nuit cerné d'un trait d'encre ;
// dedans, DEUX LAMES qui se croisent en X (blanc d'acier, garde et poignée
// rouge sang), et le CHOC à leur croisement : une étoile rouge vif. Aplats et
// trait d'encre. Pointé ou porté (`eveil`), le choc bat et tourne un peu.
// À dessiner dans un CARRÉ : le disque le remplit.

// --- fournis par emplacement_talisman.gd (les mêmes pour tout dessin de talisman) ---
uniform float opacite : hint_range(0.0, 1.0) = 1.0;
uniform float eveil : hint_range(0.0, 1.0) = 0.0;
uniform float temps = 0.0;
// ----------------------------------------------------------------------------

uniform vec4 encre_color : source_color = vec4(0.1, 0.02, 0.04, 1.0);
uniform vec4 fond_color : source_color = vec4(0.06, 0.02, 0.04, 1.0);
uniform vec4 fond_centre : source_color = vec4(0.17, 0.03, 0.05, 1.0);
uniform float trait : hint_range(0.0, 0.1) = 0.045;
uniform vec4 acier : source_color = vec4(0.92, 0.92, 0.95, 1.0);
uniform vec4 acier_ombre : source_color = vec4(0.62, 0.62, 0.7, 1.0);
uniform vec4 couleur : source_color = vec4(0.78, 0.04, 0.12, 1.0);
uniform vec4 couleur_vive : source_color = vec4(1.0, 0.24, 0.24, 1.0);

float disque(float d, float r, float px) {
	return smoothstep(r + px * 0.5, r - px * 0.5, d);
}

void forme(inout vec3 rgb, float d, vec3 teinte, float e, float px) {
	rgb = mix(rgb, encre_color.rgb, smoothstep(-px * 0.5, px * 0.5, d + e));
	rgb = mix(rgb, teinte, smoothstep(-px * 0.5, px * 0.5, d));
}

// dans le repère d'une épée tournée de `ang` : x le long de la lame (pointe
// vers +x), y en travers
vec2 repere(vec2 p, float ang) {
	return vec2(cos(ang) * p.x + sin(ang) * p.y, -sin(ang) * p.x + cos(ang) * p.y);
}

// une ÉPÉE : la lame (de x = -0.3 à la pointe en x = 0.78), la garde (en
// x = -0.32) et la poignée ; renvoie (lame, garde+poignée), positives dedans
vec2 epee(vec2 q) {
	float t = clamp((q.x + 0.3) / 1.08, 0.0, 1.0);
	float demi = 0.075 * (1.0 - pow(t, 4.0));                 // elle s'effile au bout
	float lame = min(demi - abs(q.y), min(q.x + 0.3, 0.78 - q.x));
	float garde = min(0.2 - abs(q.y), 0.045 - abs(q.x + 0.34));
	float poignee = min(0.042 - abs(q.y), 0.17 - abs(q.x + 0.55));
	return vec2(lame, max(garde, poignee));
}

// une étoile à `n` branches (positive dedans)
float etoile(vec2 q, float n, float re, float ri, float tourne) {
	float ang = atan(q.y, q.x) + tourne;
	float secteur = TAU / n;
	float x = abs(mod(ang, secteur) / secteur - 0.5) * 2.0;
	return mix(ri, re, pow(x, 2.0)) - length(q);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;                 // -1 … 1 : le médaillon est le disque de rayon 1
	float r = length(p);
	float px = fwidth(UV.x) * 2.0;

	// ===================== LE DISQUE =====================
	vec3 rgb = encre_color.rgb;
	float a = disque(r, 1.0, px);
	rgb = mix(rgb, mix(fond_centre.rgb, fond_color.rgb, smoothstep(0.0, 0.95, r)),
			disque(r, 1.0 - trait, px));

	// ===================== LES DEUX ÉPÉES, EN X =====================
	// la première monte vers la droite, la seconde vers la gauche (miroir)
	for (int i = 0; i < 2; i++) {
		float s = 1.0 - 2.0 * float(i);
		vec2 q = repere(vec2(p.x * s, p.y), -0.78);
		vec2 e = epee(q);
		forme(rgb, e.y, couleur.rgb, trait * 0.8, px);
		// la lame : un côté clair, un côté dans l'ombre
		vec3 teinte = mix(acier_ombre.rgb, acier.rgb, step(0.0, q.y * s));
		forme(rgb, e.x, teinte, trait * 0.8, px);
	}

	// ===================== LE CHOC =====================
	float bat = 1.0 + 0.15 * eveil * sin(temps * 7.0);
	vec2 c = p - vec2(0.0, -0.12);
	float tourne = 0.3 + temps * 0.6 * eveil;
	forme(rgb, etoile(c, 8.0, 0.3 * bat, 0.1 * bat, tourne), couleur.rgb, trait * 0.8, px);
	rgb = mix(rgb, couleur_vive.rgb, smoothstep(-px * 0.5, px * 0.5, etoile(c, 8.0, 0.16 * bat, 0.06 * bat, tourne)));

	COLOR = vec4(rgb, a * opacite);
}
