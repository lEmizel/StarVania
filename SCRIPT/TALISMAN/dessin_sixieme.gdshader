shader_type canvas_item;
render_mode unshaded;
// DESSIN DU TALISMAN « SIXIÈME COUP » (menu START, 2 oct. 2026) — provisoire,
// en attendant le dessin de Kaoru.
// emplacement_talisman.gd le pose dans le rond et lui fournit `opacite`,
// `eveil` et `temps`.
// TOUT LE ROND est au dessin : un disque de nuit cerné d'un trait d'encre ; au
// milieu, l'ENTAILLE d'un coup d'épée (un croissant) ; autour, SIX crans : cinq
// pastilles et, en haut, la sixième : une grande ÉTOILE d'impact (le critique).
// Aplats rouges et encre, reflet rouge clair (pas de blanc). Pointé ou porté
// (`eveil`), les cinq pastilles s'allument une à une, puis l'étoile éclate, et
// tout recommence.
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

// une étoile d'impact (positive dedans) : quatre longues pointes, quatre courtes
float etoile(vec2 q, float taille) {
	float an = atan(q.y, q.x);
	float longues = pow(abs(cos(an * 2.0)), 10.0);
	float courtes = pow(abs(sin(an * 2.0)), 10.0);
	float rayon = taille * (0.32 + 0.68 * longues + 0.3 * courtes);
	return rayon - length(q);
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

	// éveillé : une pastille de plus tous les 0,12 du cycle, l'étoile éclate à
	// 0,6, puis tout s'éteint ; au repos : les cinq allumées, l'étoile prête
	float cycle = fract(temps * 0.45);
	float allumees = mix(5.0, floor(cycle / 0.12), eveil);
	float eclate = eveil * smoothstep(0.6, 0.66, cycle) * (1.0 - smoothstep(0.82, 0.95, cycle));

	// ===================== L'ANNEAU SOMBRE QUI PORTE LES CRANS =====================
	float anneau = 0.035 - abs(r - 0.7);
	par_dessus(f_rgb, f_a, sombre.rgb * 1.3, smoothstep(0.0, px, anneau));

	// ===================== L'ENTAILLE (le croissant fin d'un coup d'épée) =====================
	// deux cercles presque égaux : un croissant effilé aux deux bouts, en travers
	vec2 c = p - vec2(0.0, 0.04);
	vec2 ca = vec2(0.2, 0.22);
	vec2 cb = vec2(0.3, 0.1);
	float d_cr = min(0.5 - length(c - ca), length(c - cb) - 0.5);
	// borné au milieu du rond (les crans restent libres)
	d_cr = min(d_cr, 0.52 - length(c));
	forme(f_rgb, f_a, d_cr, couleur.rgb, encre_color.rgb, e, px);
	// son ombre côté extérieur, son fil rouge clair côté lame
	par_dessus(f_rgb, f_a, couleur.rgb * 0.7, smoothstep(0.0, px, min(d_cr, length(c - ca) - 0.43)) * 0.9);
	par_dessus(f_rgb, f_a, clair.rgb, smoothstep(px, 0.0, abs(length(c - cb) - 0.52) - 0.012) * smoothstep(0.0, px, d_cr - 0.008) * 0.85);

	// ===================== LES CINQ PASTILLES =====================
	for (int k = 1; k <= 5; k++) {
		float an = -1.5708 + float(k) * 1.0472;
		vec2 pos = vec2(cos(an), sin(an)) * 0.7;
		float dp = 0.085 - length(p - pos);
		float allumee = step(float(k), allumees + 0.01);
		forme(f_rgb, f_a, dp, mix(sombre.rgb * 1.2, couleur.rgb, allumee), encre_color.rgb, e * 0.8, px);
		par_dessus(f_rgb, f_a, clair.rgb, smoothstep(0.0, px, min(0.022 - length(p - pos - vec2(-0.03, -0.03)), dp - 0.02)) * allumee * 0.85);
	}

	// ===================== LA SIXIÈME : L'ÉTOILE =====================
	vec2 pe = p - vec2(0.0, -0.7);
	float t_e = 0.24 * (1.0 + 0.35 * eclate);
	float de = etoile(pe, t_e);
	forme(f_rgb, f_a, de, mix(couleur.rgb, clair.rgb, eclate * 0.6), encre_color.rgb, e * 0.8, px);
	par_dessus(f_rgb, f_a, clair.rgb, smoothstep(0.0, px, 0.045 - length(pe)) * 0.9);
	// son onde quand elle éclate
	float onde = abs(length(pe) - (0.16 + 0.22 * smoothstep(0.6, 0.85, cycle))) - 0.014;
	par_dessus(f_rgb, f_a, couleur.rgb, smoothstep(px, 0.0, onde) * eclate);

	rgb = mix(rgb, f_rgb, f_a * champ);
	COLOR = vec4(rgb, a * opacite);
}
