shader_type canvas_item;
render_mode unshaded;
// DESSIN DU TALISMAN « ENTRAVES » (menu START, 1er oct. 2026) — provisoire, en
// attendant le dessin de Kaoru.
// emplacement_talisman.gd le pose dans le rond et lui fournit `opacite`,
// `eveil` et `temps`.
// TOUT LE ROND est au dessin : un disque de nuit cerné d'un trait d'encre ; une
// silhouette sombre (une jambe, un pied) prise dans un ANNEAU DE SANG hérissé
// d'épines tournées vers elle, d'où pendent des filets jusqu'à une flaque. Aplats
// et trait d'encre, comme l'anneau du jeu. Pointé ou porté (`eveil`), l'anneau
// se resserre par saccades et des gouttes tombent des filets.
// À dessiner dans un CARRÉ : le disque le remplit.

// --- fournis par emplacement_talisman.gd (les mêmes pour tout dessin de talisman) ---
uniform float opacite : hint_range(0.0, 1.0) = 1.0;
uniform float eveil : hint_range(0.0, 1.0) = 0.0;
uniform float temps = 0.0;
// ----------------------------------------------------------------------------

uniform vec4 encre_color : source_color = vec4(0.1, 0.02, 0.04, 1.0);
uniform vec4 fond_color : source_color = vec4(0.06, 0.02, 0.04, 1.0);
uniform vec4 fond_centre : source_color = vec4(0.2, 0.04, 0.06, 1.0);
uniform float trait : hint_range(0.0, 0.1) = 0.045;
uniform vec4 couleur : source_color = vec4(0.74, 0.04, 0.1, 1.0);
uniform vec4 couleur_fond : source_color = vec4(0.5, 0.03, 0.07, 1.0);
uniform vec4 silhouette : source_color = vec4(0.05, 0.012, 0.025, 1.0);

float disque(float d, float r, float px) {
	return smoothstep(r + px * 0.5, r - px * 0.5, d);
}

// positive dedans
void forme(inout vec3 rgb, float d, vec3 teinte, float e, float px) {
	rgb = mix(rgb, encre_color.rgb, smoothstep(-px * 0.5, px * 0.5, d + e));
	rgb = mix(rgb, teinte, smoothstep(-px * 0.5, px * 0.5, d));
}

// un trait effilé de a (rayon ra) à b (rayon rb) : positif dedans
float effile(vec2 p, vec2 a, vec2 b, float ra, float rb) {
	vec2 ba = b - a;
	float t = clamp(dot(p - a, ba) / max(dot(ba, ba), 0.00001), 0.0, 1.0);
	return mix(ra, rb, t) - length(p - (a + ba * t));
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float px = fwidth(UV.x) * 2.0;

	// ===================== LE DISQUE =====================
	vec3 rgb = encre_color.rgb;
	float a = disque(r, 1.0, px);
	rgb = mix(rgb, mix(fond_centre.rgb, fond_color.rgb, smoothstep(0.0, 0.95, r)), disque(r, 1.0 - trait, px));
	float dedans = (1.0 - trait * 1.6) - r;

	// l'anneau se resserre par saccades quand on le pointe
	float saccade = pow(0.5 + 0.5 * sin(temps * 3.0), 4.0) * eveil;
	vec2 c = vec2(0.0, 0.18);
	vec2 R = vec2(0.5, 0.15) * (1.0 - 0.1 * saccade);

	// ===================== LA FLAQUE =====================
	vec2 qf = (p - vec2(0.0, 0.72)) / vec2(0.5, 0.1);
	forme(rgb, min((1.0 - length(qf)) * 0.1, dedans), couleur_fond.rgb, trait * 0.7, px);

	// ===================== LA MOITIÉ DU FOND DE L'ANNEAU =====================
	vec2 q = (p - c) / R;
	float lq = length(q);
	float d_anneau = (lq - 1.0) * lq / max(length((p - c) / (R * R)), 0.00001);
	float bande = 0.065 - abs(d_anneau);
	forme(rgb, min(bande, dedans) - step(0.0, p.y - c.y) * 10.0, couleur_fond.rgb, trait * 0.7, px);

	// ===================== LA SILHOUETTE (une jambe, un pied) =====================
	float jambe = effile(p, vec2(0.04, -1.0), vec2(0.0, 0.42), 0.2, 0.17);
	float pied = effile(p, vec2(0.0, 0.48), vec2(0.3, 0.55), 0.13, 0.08);
	forme(rgb, min(max(jambe, pied), dedans), silhouette.rgb, trait, px);

	// ===================== LA MOITIÉ DE DEVANT, SES ÉPINES =====================
	forme(rgb, min(bande, dedans) - step(p.y - c.y, 0.0) * 10.0, couleur.rgb, trait * 0.7, px);
	for (int k = 0; k < 8; k++) {
		float th = float(k) / 8.0 * 6.2831853 + 0.2;
		vec2 base = c + vec2(cos(th), sin(th)) * R;
		vec2 pointe = c + vec2(cos(th), sin(th)) * R * 0.66;
		float e = effile(p, base, pointe, 0.055, 0.006);
		float devant = step(0.0, sin(th));
		forme(rgb, min(e, dedans), mix(couleur_fond.rgb, couleur.rgb, devant), trait * 0.5, px);
	}

	// ===================== LES FILETS, LES GOUTTES =====================
	for (int k = 0; k < 3; k++) {
		float fk = float(k);
		float th = 1.15 + fk * 0.42;
		vec2 haut = c + vec2(cos(th), sin(th)) * R;
		float t = clamp((p.y - haut.y) / 0.4, 0.0, 1.0);
		float x = sin(t * 3.0 + temps * 2.0 + fk) * 0.025 * t;
		float f = effile(vec2(p.x - x, p.y), haut, haut + vec2(0.0, 0.42 - fk * 0.06), 0.04, 0.012);
		forme(rgb, min(f, dedans), couleur.rgb, trait * 0.5, px);
		float vie = fract(temps * 0.9 + fk * 0.33);
		vec2 g = haut + vec2(0.0, 0.42 + vie * 0.18);
		float goutte = effile(p, g, g - vec2(0.0, 0.05), 0.03, 0.006) - (1.0 - step(0.05, eveil)) * 10.0;
		forme(rgb, min(goutte, dedans), couleur.rgb, trait * 0.4, px);
	}

	COLOR = vec4(rgb, a * opacite);
}
