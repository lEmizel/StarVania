shader_type canvas_item;
render_mode unshaded;
// DESSIN DU TALISMAN « PACTE DE SANG » (menu START, 2 oct. 2026) — provisoire,
// en attendant le dessin définitif.
// emplacement_talisman.gd le pose dans le rond et lui fournit `opacite`,
// `eveil` et `temps`.
// TOUT LE ROND est au dessin : un disque de nuit cerné d'un trait d'encre ;
// derrière, un PARCHEMIN sombre penché, ses lignes écrites ; devant, un SCEAU de
// cire de sang au bord ondulé, une goutte frappée en son milieu, et une COULURE
// qui en descend. Aplats rouges et encre, reflet rouge clair (pas de blanc).
// Pointé ou porté (`eveil`), le sceau bat et la coulure s'allonge jusqu'à
// lâcher sa goutte.
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
uniform vec4 couleur : source_color = vec4(0.62, 0.02, 0.09, 1.0);
uniform vec4 sombre : source_color = vec4(0.3, 0.01, 0.06, 1.0);
uniform vec4 clair : source_color = vec4(1.0, 0.5, 0.5, 1.0);
uniform vec4 parchemin : source_color = vec4(0.26, 0.1, 0.08, 1.0);

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

float triangle(vec2 p, vec2 q) {
	p.x = abs(p.x);
	vec2 a = p - q * clamp(dot(p, q) / dot(q, q), 0.0, 1.0);
	vec2 b = p - q * vec2(clamp(p.x / q.x, 0.0, 1.0), 1.0);
	float s = -sign(q.y);
	vec2 d = min(vec2(dot(a, a), s * (p.x * q.y - p.y * q.x)), vec2(dot(b, b), s * (p.y - q.y)));
	return -sqrt(d.x) * sign(d.y);
}

// la goutte (négative dedans), en px d'une goutte de ~30 px de haut
float sd_goutte(vec2 p) {
	float rond = length(p - vec2(0.0, 4.0)) - 9.0;
	float pointe = triangle(p - vec2(0.0, -16.0), vec2(8.2, 17.0));
	float h = clamp(0.5 + 0.25 * (pointe - rond), 0.0, 1.0);
	return mix(pointe, rond, h) - 2.0 * h * (1.0 - h);
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

	float cycle = fract(temps * 0.4);
	float bat = pow(0.5 + 0.5 * sin(temps * 6.0), 8.0) * eveil;
	// la coulure : au repos à mi-longueur ; éveillée, elle s'allonge puis lâche
	float coule = mix(0.5, smoothstep(0.0, 0.7, cycle), eveil);
	float lache = eveil * smoothstep(0.7, 1.0, cycle);

	// ===================== LE PARCHEMIN (derrière) =====================
	float ang = -0.22;
	mat2 rot = mat2(vec2(cos(ang), sin(ang)), vec2(-sin(ang), cos(ang)));
	vec2 pp = rot * (p - vec2(-0.12, -0.12));
	vec2 dpp = abs(pp) - vec2(0.48, 0.56);
	float d_par = -(length(max(dpp, 0.0)) + min(max(dpp.x, dpp.y), 0.0) - 0.04);
	forme(f_rgb, f_a, d_par, parchemin.rgb, encre_color.rgb, e, px);
	// ses lignes écrites
	for (int i = 0; i < 4; i++) {
		float y = -0.4 + float(i) * 0.13;
		float longueur = 0.34 - float(i % 2) * 0.1;
		float l = max(abs(pp.y - y) - 0.014, abs(pp.x + 0.02) - longueur);
		par_dessus(f_rgb, f_a, encre_color.rgb, smoothstep(px, 0.0, l) * 0.85 * step(0.0, d_par));
	}

	// ===================== LA COULURE (sous le sceau) =====================
	vec2 cs = vec2(0.1, 0.18);
	float r_sceau = 0.38 * (1.0 + 0.04 * bat);
	float bas = cs.y + r_sceau * 0.9;
	float fin = bas + 0.06 + 0.3 * coule;
	vec2 pc = p - vec2(cs.x + 0.12, 0.0);
	float d_coulure = min(0.04 - abs(pc.x) + (p.y - bas) * 0.03, min(p.y - (bas - 0.1), fin - p.y));
	forme(f_rgb, f_a, d_coulure * (1.0 - lache) - lache * 0.2, couleur.rgb, encre_color.rgb, e * 0.7, px);
	float d_bout = 0.055 - length(p - vec2(cs.x + 0.12, fin));
	forme(f_rgb, f_a, d_bout * (1.0 - lache) - lache * 0.2, couleur.rgb, encre_color.rgb, e * 0.7, px);
	// la goutte lâchée tombe
	float y_chute = fin + lache * lache * 0.4;
	float d_chute = 0.05 - length(p - vec2(cs.x + 0.12, y_chute));
	float vis = lache * (1.0 - smoothstep(0.85, 1.0, cycle));
	forme(f_rgb, f_a, d_chute * vis - (1.0 - vis) * 0.2, couleur.rgb, encre_color.rgb, e * 0.7, px);

	// ===================== LE SCEAU DE CIRE =====================
	vec2 q = p - cs;
	float aq = atan(q.y, q.x);
	float bord = r_sceau + 0.022 * sin(aq * 9.0) + 0.014 * sin(aq * 5.0 + 1.0);
	float d_sceau = bord - length(q);
	forme(f_rgb, f_a, d_sceau, couleur.rgb, encre_color.rgb, e, px);
	// son bourrelet, plus sombre
	par_dessus(f_rgb, f_a, couleur.rgb * 0.68, smoothstep(px, 0.0, abs(length(q) - r_sceau * 0.78) - 0.035) * smoothstep(0.0, px, d_sceau));
	// la goutte frappée au milieu : un creux sombre, un fil clair d'un côté
	float k_g = 30.0 / 0.4;
	float dg = -sd_goutte(q * k_g) / k_g;
	par_dessus(f_rgb, f_a, couleur.rgb * 0.62, smoothstep(0.0, px, dg));
	par_dessus(f_rgb, f_a, encre_color.rgb, smoothstep(px, 0.0, abs(dg) - 0.012) * step(0.0, -q.x - q.y * 0.3) * 0.8);
	par_dessus(f_rgb, f_a, clair.rgb, smoothstep(px, 0.0, abs(dg) - 0.012) * step(0.0, q.x + q.y * 0.3) * 0.85);
	// un reflet sur la cire
	float reflet = max(abs(length(q) - r_sceau * 0.9) - 0.018, abs(aq + 2.2) - 0.35);
	par_dessus(f_rgb, f_a, clair.rgb, smoothstep(px, 0.0, reflet) * 0.8);

	rgb = mix(rgb, f_rgb, f_a * champ);
	COLOR = vec4(rgb, a * opacite);
}
