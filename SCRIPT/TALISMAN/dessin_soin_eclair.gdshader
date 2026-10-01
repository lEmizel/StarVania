shader_type canvas_item;
render_mode unshaded;
// DESSIN DU TALISMAN « SOIN ÉCLAIR » (menu START, 1er oct. 2026) — provisoire,
// en attendant le dessin de Kaoru.
// emplacement_talisman.gd le pose dans le rond et lui fournit `opacite`,
// `eveil` et `temps`.
// TOUT LE ROND est au dessin : un disque de nuit cerné d'un trait d'encre, un
// CADRAN sombre à douze encoches, une AIGUILLE de sang qui balaie le cadran en
// laissant derrière elle un éventail rouge (le temps qui file), et au centre un
// CŒUR de sang par-dessus. Aplats, encre, un reflet rouge clair (pas de blanc).
// Pointé ou porté (`eveil`), l'aiguille s'emballe.
// À dessiner dans un CARRÉ : le disque le remplit.

// --- fournis par emplacement_talisman.gd (les mêmes pour tout dessin de talisman) ---
uniform float opacite : hint_range(0.0, 1.0) = 1.0;
uniform float eveil : hint_range(0.0, 1.0) = 0.0;
uniform float temps = 0.0;
// ----------------------------------------------------------------------------

uniform vec4 encre_color : source_color = vec4(0.1, 0.02, 0.04, 1.0);
uniform vec4 fond_color : source_color = vec4(0.06, 0.02, 0.04, 1.0);
uniform vec4 fond_centre : source_color = vec4(0.17, 0.03, 0.05, 1.0);
uniform vec4 cadran : source_color = vec4(0.2, 0.04, 0.07, 1.0);
uniform float trait : hint_range(0.0, 0.1) = 0.045;
uniform vec4 couleur : source_color = vec4(0.78, 0.04, 0.12, 1.0);
uniform vec4 sombre : source_color = vec4(0.42, 0.03, 0.08, 1.0);
uniform vec4 reflet : source_color = vec4(1.0, 0.36, 0.36, 1.0);

float disque(float d, float r, float px) {
	return smoothstep(r + px * 0.5, r - px * 0.5, d);
}

void forme(inout vec3 rgb, float d, vec3 teinte, float e, float px) {
	rgb = mix(rgb, encre_color.rgb, smoothstep(-px * 0.5, px * 0.5, d + e));
	rgb = mix(rgb, teinte, smoothstep(-px * 0.5, px * 0.5, d));
}

// un cœur centré en `c`, de taille `s`, positif dedans
float coeur(vec2 p, vec2 c, float s) {
	vec2 q = (p - c) / s;
	float lobe_g = 0.36 - length(q - vec2(-0.28, -0.14));
	float lobe_d = 0.36 - length(q - vec2(0.28, -0.14));
	float pointe = min(q.y + 0.12, (0.7 - q.y) * 0.9 - abs(q.x));
	return max(max(lobe_g, lobe_d), pointe) * s;
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
	float dedans = (1.0 - trait * 1.6) - r;

	// ===================== LE CADRAN =====================
	float anneau = min(0.84 - r, r - 0.6);
	forme(rgb, min(anneau, dedans), cadran.rgb, trait * 0.7, px);
	// l'angle de ce point, 0 en haut, dans le sens des aiguilles d'une montre
	float ang = atan(p.x, -p.y);
	if (ang < 0.0) {
		ang += 6.2831853;
	}
	// ===================== L'ÉVENTAIL ET L'AIGUILLE =====================
	float tour = fract(temps * 0.32);
	float aiguille = tour * 6.2831853;
	// l'éventail : le cadran que l'aiguille vient de balayer, de plus en plus pâle
	float derriere = mod(aiguille - ang, 6.2831853);
	float balaye = 1.0 - smoothstep(0.0, 1.6, derriere);
	rgb = mix(rgb, sombre.rgb, balaye * 0.85 * step(0.0, 0.84 - r) * step(0.0, r - 0.12));
	// les douze encoches (les quatre grandes plus longues)
	float cran = abs(fract(ang / 6.2831853 * 12.0 + 0.5) - 0.5) / 12.0 * 6.2831853 * r;
	float grand = step(abs(fract(ang / 6.2831853 * 4.0 + 0.5) - 0.5), 0.02);
	float encoche = min(0.016 - cran, min(0.8 - r, r - mix(0.7, 0.64, grand)));
	rgb = mix(rgb, mix(encre_color.rgb, couleur.rgb, balaye), smoothstep(-px * 0.5, px * 0.5, encoche));
	// l'aiguille : une lame de sang effilée, du centre au cadran
	vec2 u = vec2(sin(aiguille), -cos(aiguille));
	float le_long = dot(p, u);
	float travers = abs(dot(p, vec2(-u.y, u.x)));
	float lame = min(0.045 * (1.0 - smoothstep(0.1, 0.78, le_long)) + 0.006 - travers,
			min(le_long + 0.05, 0.78 - le_long));
	forme(rgb, lame, couleur.rgb, trait * 0.6, px);

	// ===================== LE CŒUR =====================
	vec2 cc = vec2(0.0, -0.02);
	float d = coeur(p, cc, 0.56);
	// il bat avec l'aiguille, un peu plus quand on le pointe
	d += 0.02 * (0.5 + 0.5 * sin(temps * 6.0)) * (0.3 + 0.7 * eveil);
	forme(rgb, d, couleur.rgb, trait, px);
	float rf = min(d - 0.04, 0.085 - length((p - cc - vec2(-0.15, -0.12)) * vec2(1.0, 1.3)));
	rgb = mix(rgb, reflet.rgb, smoothstep(-px * 0.5, px * 0.5, rf));

	COLOR = vec4(rgb, a * opacite);
}
