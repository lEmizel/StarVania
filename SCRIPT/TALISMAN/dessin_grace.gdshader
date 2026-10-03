shader_type canvas_item;
render_mode unshaded;
// DESSIN DU TALISMAN « COUP DE GRÂCE » (menu START, 1er oct. 2026) —
// provisoire, en attendant le dessin définitif.
// emplacement_talisman.gd le pose dans le rond et lui fournit `opacite`,
// `eveil` et `temps`.
// TOUT LE ROND est au dessin : un disque de nuit cerné d'un trait d'encre ;
// dedans, un CRÂNE sombre parcouru de FISSURES rouges (comme l'ennemi à portée
// d'exécution en jeu), tranché en diagonale par un trait rouge vif, et des
// ÉCLATS qui s'en détachent. Aplats et trait d'encre, pas de blanc. Pointé ou
// porté (`eveil`), les fissures battent.
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
uniform vec4 os : source_color = vec4(0.36, 0.32, 0.34, 1.0);
uniform vec4 os_clair : source_color = vec4(0.46, 0.42, 0.44, 1.0);
uniform vec4 couleur : source_color = vec4(0.78, 0.04, 0.12, 1.0);
uniform vec4 vive : source_color = vec4(1.0, 0.24, 0.24, 1.0);

float disque(float d, float r, float px) {
	return smoothstep(r + px * 0.5, r - px * 0.5, d);
}

void forme(inout vec3 rgb, float d, vec3 teinte, float e, float px) {
	rgb = mix(rgb, encre_color.rgb, smoothstep(-px * 0.5, px * 0.5, d + e));
	rgb = mix(rgb, teinte, smoothstep(-px * 0.5, px * 0.5, d));
}

vec2 hachis2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

// distance au bord de cellule de Voronoï le plus proche (en cellules)
float bord_voronoi(vec2 x) {
	vec2 n = floor(x);
	vec2 f = fract(x);
	vec2 mg = vec2(0.0);
	vec2 mr = vec2(0.0);
	float md = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 r = g + hachis2(n + g) - f;
			float d = dot(r, r);
			if (d < md) {
				md = d;
				mr = r;
				mg = g;
			}
		}
	}
	md = 8.0;
	for (int j = -2; j <= 2; j++) {
		for (int i = -2; i <= 2; i++) {
			vec2 g = mg + vec2(float(i), float(j));
			vec2 r = g + hachis2(n + g) - f;
			if (dot(mr - r, mr - r) > 0.00001) {
				md = min(md, dot(0.5 * (mr + r), normalize(r - mr)));
			}
		}
	}
	return md;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float px = fwidth(UV.x) * 2.0;

	// ===================== LE DISQUE =====================
	vec3 rgb = encre_color.rgb;
	float a = disque(r, 1.0, px);
	rgb = mix(rgb, mix(fond_centre.rgb, fond_color.rgb, smoothstep(0.0, 0.95, r)),
			disque(r, 1.0 - trait, px));

	// ===================== LE CRÂNE =====================
	vec2 c = p - vec2(0.0, -0.05);
	float boite = 0.5 - length(c * vec2(1.0, 1.08));                    // la calotte
	float machoire = min(0.28 - abs(c.x), min(c.y - 0.1, 0.52 - c.y));  // la mâchoire
	float crane = max(boite, min(machoire, 0.3 - length((c - vec2(0.0, 0.32)) * vec2(1.0, 1.6))));
	forme(rgb, crane, mix(os.rgb, os_clair.rgb, step(c.x + c.y * 0.3, -0.05)), trait, px);
	// les orbites et le nez, en encre
	float orbites = min(0.13 - length(c - vec2(-0.18, 0.04)), 1.0);
	orbites = max(orbites, 0.13 - length(c - vec2(0.18, 0.04)));
	float nez = min(0.05 - abs(c.x), min(c.y - 0.16, 0.27 - c.y) - abs(c.x));
	rgb = mix(rgb, encre_color.rgb, smoothstep(-px * 0.5, px * 0.5, max(orbites, nez)));
	// des yeux rouges, au fond des orbites
	float yeux = max(0.04 - length(c - vec2(-0.18, 0.05)), 0.04 - length(c - vec2(0.18, 0.05)));
	rgb = mix(rgb, couleur.rgb, smoothstep(-px * 0.5, px * 0.5, yeux));

	// ===================== LES FISSURES ROUGES =====================
	float bat = 0.75 + 0.25 * eveil * sin(temps * 5.0);
	float b = bord_voronoi(c * 4.2 + vec2(3.1, 1.7));
	float fissure = (1.0 - smoothstep(0.02, 0.05, b)) * step(0.0, crane - trait);
	rgb = mix(rgb, mix(couleur.rgb, vive.rgb, 0.5 * bat), fissure * bat);

	// ===================== LE TRAIT QUI TRANCHE =====================
	vec2 u = normalize(vec2(1.0, -0.85));
	float le_long = dot(p, u);
	float travers = dot(p, vec2(-u.y, u.x));
	float tt = clamp(le_long / 0.85, -1.0, 1.0);
	float tranche = min(0.05 * (1.0 - tt * tt) - abs(travers), 0.85 - abs(le_long));
	forme(rgb, tranche, vive.rgb, trait * 0.7, px);

	// ===================== LES ÉCLATS =====================
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		float ang = 0.6 + fi * 1.55;
		vec2 ce = vec2(cos(ang), sin(ang)) * (0.66 + 0.04 * sin(temps * 2.0 + fi) * eveil);
		vec2 q = p - ce;
		float rot = ang + fi;
		q = vec2(cos(rot) * q.x + sin(rot) * q.y, -sin(rot) * q.x + cos(rot) * q.y);
		float tri = min(min(0.07 - abs(q.y) - q.x * 0.6, q.x + 0.06), 0.11 - q.x);
		forme(rgb, tri, couleur.rgb, trait * 0.6, px);
	}

	COLOR = vec4(rgb, a * opacite);
}
