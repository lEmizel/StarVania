shader_type canvas_item;
render_mode unshaded;
// DESSIN DU TALISMAN « TROP-PLEIN » (menu START, 2 oct. 2026) — provisoire,
// en attendant le dessin de Kaoru.
// emplacement_talisman.gd le pose dans le rond et lui fournit `opacite`,
// `eveil` et `temps`.
// TOUT LE ROND est au dessin : un disque de nuit cerné d'un trait d'encre ;
// derrière, l'OMBRE de la grosse boule qui viendra (sombre, avec sa traînée) ;
// devant, la ROUE du jeu (façon endurance de Zelda) : un anneau en trois tiers,
// rempli, et en son cœur la boule de sang. Aplats rouges et encre, reflet
// rouge clair (pas de blanc). Pointé ou porté (`eveil`), l'anneau se remplit
// tiers par tiers en tournant, son cœur se remplit et bat, puis tout se vide,
// en boucle.
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

const vec2 ROUE = vec2(-0.1, -0.04);
const float R_EXT = 0.52;
const float EPAISSEUR = 0.17;

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

	// le cycle éveillé : un tiers par 0,15 du cycle (en tournant), pleine
	// jusqu'à 0,85 (son cœur se remplit et bat), puis elle se vide ; au repos :
	// pleine
	float cycle = fract(temps * 0.33);
	float tiers = min(floor(cycle / 0.15), 2.0);
	float dans_tiers = clamp((cycle - tiers * 0.15) / 0.06, 0.0, 1.0);
	float rempli_anim = (tiers + dans_tiers) / 3.0 * step(cycle, 0.85);
	float rempli = mix(1.0, rempli_anim, eveil);
	float coeur_anim = smoothstep(0.45, 0.5, cycle) * (1.0 - smoothstep(0.85, 0.9, cycle));
	float coeur = mix(1.0, coeur_anim, eveil);
	float bat = pow(0.5 + 0.5 * sin(temps * 7.0), 8.0) * eveil * coeur;

	// ===================== L'OMBRE DE LA GROSSE BOULE =====================
	vec2 g = p - vec2(0.3, 0.1);
	float boule = 0.56 - length(g);
	float k = clamp(-g.x / 1.2, 0.0, 1.0);
	float trainee = min(0.5 * (1.0 - k) - abs(g.y + g.x * 0.08), min(-g.x, 1.2 + g.x));
	forme(f_rgb, f_a, max(boule, trainee), sombre.rgb, encre_color.rgb, e * 0.8, px);
	// un liseré plus clair sur son bord haut (pas dans le creux de la roue)
	par_dessus(f_rgb, f_a, sombre.rgb * 1.8, smoothstep(px, 0.0, abs(boule - 0.035) - 0.012) * step(g.y, -0.12)
		* step(R_EXT + 0.02, length(p - ROUE)) * 0.8);

	// ===================== LA ROUE =====================
	vec2 q = (p - ROUE) / (1.0 + 0.05 * bat);
	float rq = length(q);
	float r_mi = R_EXT - EPAISSEUR * 0.5;
	float d_anneau = EPAISSEUR * 0.5 - abs(rq - r_mi);
	// le fond de l'anneau
	forme(f_rgb, f_a, d_anneau, sombre.rgb * 0.7, encre_color.rgb, e, px);
	// la part remplie, depuis midi dans le sens des aiguilles d'une montre
	float f = fract(atan(q.x, -q.y) / TAU + 1.0);
	float arc = (rempli - f) * TAU * r_mi;
	float d_rempli = min(d_anneau - 0.012, arc);
	par_dessus(f_rgb, f_a, couleur.rgb, smoothstep(0.0, px, d_rempli) * step(0.001, rempli));
	// son ombre, côté bas de l'anneau
	par_dessus(f_rgb, f_a, couleur.rgb * 0.72, smoothstep(0.0, px, min(d_rempli, rq - r_mi - 0.01)) * step(0.0, q.y) * 0.85);
	// un reflet rouge clair sur le haut de l'anneau
	float reflet = max(abs(rq - r_mi - 0.035) - 0.016, abs(f - 0.9) - 0.06);
	par_dessus(f_rgb, f_a, clair.rgb, smoothstep(px, 0.0, reflet) * step(f, rempli) * 0.85);
	// les encoches des tiers
	for (int i = 0; i < 3; i++) {
		float an = float(i) / 3.0 * TAU;
		vec2 dir = vec2(sin(an), -cos(an));
		float le_long = dot(q, dir);
		float travers = abs(dot(q, vec2(-dir.y, dir.x)));
		float d_enc = max(travers - 0.018, abs(le_long - r_mi) - EPAISSEUR * 0.5 - 0.02);
		par_dessus(f_rgb, f_a, encre_color.rgb, smoothstep(px, 0.0, d_enc));
	}

	// ===================== SON CŒUR : LA BOULE DE SANG =====================
	float r_c = (R_EXT - EPAISSEUR - 0.06) * smoothstep(0.0, 1.0, coeur);
	if (r_c > 0.005) {
		float dc = r_c - rq;
		forme(f_rgb, f_a, dc, couleur.rgb, encre_color.rgb, e, px);
		par_dessus(f_rgb, f_a, couleur.rgb * 0.7, smoothstep(0.0, px, min(dc, q.y + q.x * 0.5 - 0.06)) * 0.9);
		par_dessus(f_rgb, f_a, clair.rgb, smoothstep(0.0, px, min(0.05 - length((q - vec2(-0.08, -0.09)) * vec2(1.0, 1.4)), dc - 0.02)) * 0.9);
	}

	rgb = mix(rgb, f_rgb, f_a * champ);
	COLOR = vec4(rgb, a * opacite);
}
