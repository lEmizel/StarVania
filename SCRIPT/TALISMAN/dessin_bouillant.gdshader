shader_type canvas_item;
render_mode unshaded;
// DESSIN DU TALISMAN « SANG BOUILLANT » (menu START, 1er oct. 2026) —
// provisoire, en attendant le dessin de Kaoru.
// emplacement_talisman.gd le pose dans le rond et lui fournit `opacite`,
// `eveil` et `temps`.
// TOUT LE ROND est au dessin : un disque de nuit cerné d'un trait d'encre ; au
// fond, des rayons sombres qui partent de la grande explosion ; au milieu, une
// GERBE DE SANG en étoile (des bras à bout rond, un cœur vif), et, plus loin
// et plus sombres, deux gerbes plus petites qu'elle a fait sauter — la
// cascade ; en bas, une flaque de sang qui BOUT (des bulles qui montent et
// crèvent). Aplats et dégradés, reflets rouge clair (pas de blanc). Pointé ou
// porté (`eveil`) : les gerbes respirent, les bulles montent et crèvent.
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
uniform vec4 couleur : source_color = vec4(0.78, 0.04, 0.12, 1.0);
uniform vec4 couleur_vive : source_color = vec4(1.0, 0.17, 0.2, 1.0);
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

float alea(float n) {
	return fract(sin(n * 12.9898 + 4.1414) * 43758.5453);
}

// une GERBE de sang centrée en `c`, de rayon `R` : `n` bras à bout rond autour
// d'un cœur ; positive dedans. `g` reçoit 0 au cœur → 1 au bout des bras.
float gerbe(vec2 p, vec2 c, float R, float n, float graine, out float g) {
	vec2 q = p - c;
	float d = length(q);
	float ang = atan(q.y, q.x);
	float secteur = TAU / n;
	float tour = mod(ang + PI + graine, TAU) / secteur;
	float idx0 = floor(tour);
	float best = 0.3 * R - d;                   // le cœur
	for (int k = -1; k <= 1; k++) {
		float idx = mod(idx0 + float(k), n);
		float h1 = alea(idx * 1.7 + graine);
		float h2 = alea(idx * 3.1 + graine * 1.3 + 5.0);
		float delta = (tour - (idx0 + float(k) + 0.5)) * secteur;
		float lg = R * (0.55 + 0.45 * h1);
		float ep = R * (0.07 + 0.05 * h2);
		// un bras : de 0 à lg le long de son axe, à bout rond, qui s'affine
		vec2 b = vec2(d * cos(delta), d * sin(delta));
		float u = clamp(b.x / lg, 0.0, 1.0);
		float bras = ep * mix(1.2, 0.75, u) - length(b - vec2(u * lg, 0.0));
		// la goutte au bout du bras
		float bout = ep * 1.35 - length(b - vec2(lg, 0.0));
		best = max(best, max(bras, bout));
	}
	g = clamp(d / R, 0.0, 1.0);
	return best;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float px = fwidth(UV.x) * 2.0;
	float e = 0.03;

	vec3 rgb = encre_color.rgb;
	float a = disque(r, 1.0, px);
	float champ = disque(r, 1.0 - trait, px);
	rgb = mix(rgb, mix(fond_centre.rgb, fond_color.rgb, smoothstep(0.0, 0.95, r)), champ);

	vec3 f_rgb = couleur.rgb;
	float f_a = 0.0;

	vec2 c0 = vec2(0.02, -0.12);       // la grande gerbe
	float respire = 1.0 + 0.05 * sin(temps * 5.0) * eveil;

	// ===================== LES RAYONS DU FOND =====================
	float ar = atan(p.y - c0.y, p.x - c0.x);
	float rr = length(p - c0);
	float rayons = smoothstep(0.7, 1.0, abs(sin(ar * 8.0 + 0.4))) * smoothstep(0.3, 0.55, rr);
	par_dessus(f_rgb, f_a, sombre.rgb, rayons * 0.55);

	// ===================== LES DEUX PETITES GERBES, PLUS LOIN =====================
	float g;
	float d1 = gerbe(p, vec2(-0.56, 0.18), 0.27 * respire, 7.0, 3.1, g);
	forme(f_rgb, f_a, d1, mix(couleur.rgb * 0.7, sombre.rgb * 1.3, g), encre_color.rgb, e * 0.7, px);
	float d2 = gerbe(p, vec2(0.6, 0.12), 0.24 * respire, 6.0, 7.7, g);
	forme(f_rgb, f_a, d2, mix(couleur.rgb * 0.7, sombre.rgb * 1.3, g), encre_color.rgb, e * 0.7, px);

	// ===================== LA FLAQUE QUI BOUT =====================
	float surface = 0.6 + 0.025 * sin(p.x * 9.0 + temps * 3.0 * eveil);
	float d_flaque = p.y - surface;
	par_dessus(f_rgb, f_a, mix(couleur.rgb, sombre.rgb, smoothstep(surface, surface + 0.35, p.y)), smoothstep(0.0, px, d_flaque));
	par_dessus(f_rgb, f_a, couleur_vive.rgb, smoothstep(0.0, px, min(d_flaque, 0.02 - d_flaque)) * 0.8);
	for (int k = 0; k < 5; k++) {
		float fk = float(k);
		float xk = (fk - 2.0) * 0.22 + 0.06 * sin(fk * 2.7);
		float cycle = fract(fk * 0.37 + temps * 0.6 * eveil + 0.15);
		float rk = (0.035 + 0.035 * alea(fk * 4.1)) * smoothstep(0.0, 0.5, cycle) * (1.0 - smoothstep(0.85, 1.0, cycle));
		vec2 cb = vec2(xk, surface - 0.02 - 0.18 * cycle * eveil);
		float db = rk - length(p - cb);
		forme(f_rgb, f_a, db, couleur.rgb, sombre.rgb, e * 0.6, px);
		par_dessus(f_rgb, f_a, clair.rgb, smoothstep(0.0, px, rk * 0.33 - length(p - cb - vec2(-rk * 0.35, -rk * 0.38))) * 0.85);
	}

	// ===================== LA GRANDE GERBE =====================
	float d0 = gerbe(p, c0, 0.62 * respire, 9.0, 1.3, g);
	vec3 c_gerbe = mix(couleur_vive.rgb, couleur.rgb, smoothstep(0.1, 0.55, g));
	c_gerbe = mix(c_gerbe, sombre.rgb * 1.4, smoothstep(0.6, 1.0, g));
	forme(f_rgb, f_a, d0, c_gerbe, encre_color.rgb, e, px);
	// le cœur vif, et son reflet rouge clair
	float dc = 0.12 * respire - length(p - c0);
	par_dessus(f_rgb, f_a, couleur_vive.rgb, smoothstep(0.0, px, dc));
	par_dessus(f_rgb, f_a, clair.rgb, smoothstep(0.0, px, 0.04 - length(p - c0 - vec2(-0.04, -0.045))) * 0.85);
	// quelques gouttes projetées
	for (int k = 0; k < 6; k++) {
		float fk = float(k);
		float ak = fk * 1.047 + 0.5;
		vec2 cg = c0 + vec2(cos(ak), sin(ak)) * (0.74 + 0.08 * alea(fk * 2.3)) * respire;
		float dg = 0.03 - length(p - cg);
		forme(f_rgb, f_a, dg, couleur.rgb, encre_color.rgb, e * 0.6, px);
	}

	rgb = mix(rgb, f_rgb, f_a * champ);
	COLOR = vec4(rgb, a * opacite);
}
