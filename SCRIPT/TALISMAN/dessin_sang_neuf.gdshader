shader_type canvas_item;
render_mode unshaded;
// DESSIN DU TALISMAN « SANG NEUF » (menu START, 2 oct. 2026) —
// provisoire, en attendant le dessin définitif.
// emplacement_talisman.gd le pose dans le rond et lui fournit `opacite`,
// `eveil` et `temps`.
// TOUT LE ROND est au dessin : un disque de nuit cerné d'un trait d'encre ;
// derrière, une STÈLE sombre (la mort) ; devant, une grande GOUTTE de verre
// PLEINE de sang (la jauge de soin) ; autour d'elle, une FLÈCHE en cercle (on
// revient). Aplats rouges et encre, reflet rouge clair (pas de blanc). Pointé ou
// porté (`eveil`), la goutte se vide puis se remplit de bas en haut, et la
// flèche tourne.
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

	// éveillée : la goutte se remplit (0 → 0,55 du cycle), reste pleine, puis
	// repart vide ; au repos : pleine
	float cycle = fract(temps * 0.4);
	float niveau = mix(1.0, smoothstep(0.05, 0.55, cycle), eveil);

	// ===================== LA STÈLE (derrière) =====================
	vec2 ps = p - vec2(0.0, 0.1);
	float corps = min(0.42 - abs(ps.x), ps.y + 0.12);
	float tete = 0.42 - length(ps - vec2(0.0, -0.12));
	float stele = max(corps, tete);
	forme(f_rgb, f_a, stele, sombre.rgb * 0.95, encre_color.rgb, e, px);
	// deux lignes gravées
	for (int i = 0; i < 2; i++) {
		float y = -0.3 + float(i) * 0.09;
		float l = max(abs(ps.y - y) - 0.012, abs(ps.x) - (0.2 - float(i) * 0.06));
		par_dessus(f_rgb, f_a, encre_color.rgb, smoothstep(px, 0.0, l) * 0.9);
	}
	// le sol sombre
	float sol = p.y - 0.66;
	par_dessus(f_rgb, f_a, fond_color.rgb * 0.6, smoothstep(0.0, px, sol));
	par_dessus(f_rgb, f_a, encre_color.rgb, smoothstep(px, 0.0, abs(sol) - 0.012));

	// ===================== LA FLÈCHE EN CERCLE =====================
	vec2 c = p - vec2(0.0, 0.05);
	float rc = length(c);
	float tour = temps * 1.6 * eveil;
	float depart = 2.4 + tour;
	float ang = fract((atan(c.y, c.x) - depart) / TAU) * TAU;
	float etendue = 0.72 * TAU;
	float r_fl = 0.7;
	float d_cercle = min(0.045 - abs(rc - r_fl), min(ang, etendue - ang) * r_fl);
	forme(f_rgb, f_a, d_cercle, couleur.rgb, encre_color.rgb, e * 0.8, px);
	// sa pointe, au bout, dans le sens où elle tourne
	float a_fin = depart + etendue;
	vec2 bout = vec2(cos(a_fin), sin(a_fin)) * r_fl;
	vec2 sens = vec2(-sin(a_fin), cos(a_fin));
	vec2 l = c - bout - sens * 0.1;
	vec2 qt = vec2(dot(l, vec2(-sens.y, sens.x)), -dot(l, sens));
	float d_pointe = -triangle(qt, vec2(0.12, 0.2));
	forme(f_rgb, f_a, d_pointe, couleur.rgb, encre_color.rgb, e * 0.8, px);

	// ===================== LA GOUTTE, PLEINE DE SANG =====================
	float k_g = 30.0 / 0.82;
	vec2 pg = (p - vec2(0.0, 0.1)) * k_g;
	float dg = -sd_goutte(pg) / k_g;
	// le verre vide
	forme(f_rgb, f_a, dg, sombre.rgb * 0.55, encre_color.rgb, e, px);
	// le sang, de bas en haut
	float y_bas = 0.1 + 13.0 / k_g;
	float y_haut = 0.1 - 16.0 / k_g;
	float ys = mix(y_bas + 0.02, y_haut - 0.02, niveau) + sin(p.x * 14.0 + temps * 4.0) * 0.008 * eveil;
	float sang = min(dg - 0.018, p.y - ys);
	par_dessus(f_rgb, f_a, couleur.rgb, smoothstep(0.0, px, sang));
	// sa surface, plus sombre, tant qu'elle n'est pas pleine
	par_dessus(f_rgb, f_a, couleur.rgb * 0.55, smoothstep(px, 0.0, abs(p.y - ys) - 0.012)
		* smoothstep(0.0, px, dg - 0.018) * step(niveau, 0.97));
	// son ombre en bas à droite, son reflet en haut à gauche
	par_dessus(f_rgb, f_a, couleur.rgb * 0.7, smoothstep(0.0, px, min(sang, p.y - 0.18 - p.x * 0.5)) * 0.9);
	par_dessus(f_rgb, f_a, clair.rgb, smoothstep(0.0, px, min(0.045 - length((p - vec2(-0.1, 0.08)) * vec2(1.4, 1.0)), sang - 0.02)) * 0.85);
	// le trait d'encre de la goutte, par-dessus le sang
	par_dessus(f_rgb, f_a, encre_color.rgb, smoothstep(px, 0.0, abs(dg) - e * 0.5));

	rgb = mix(rgb, f_rgb, f_a * champ);
	COLOR = vec4(rgb, a * opacite);
}
