shader_type canvas_item;
render_mode unshaded;
// DESSIN DU TALISMAN « MARQUE DE SANG » (menu START, 1er oct. 2026, refait le
// même jour : « un poil trop simpliste ») — provisoire, en attendant le dessin
// de Kaoru.
// emplacement_talisman.gd le pose dans le rond et lui fournit `opacite`,
// `eveil` et `temps`.
// TOUT LE ROND est au dessin : un SCEAU. Un disque de nuit cerné d'un trait
// d'encre ; une couronne de RUNES (des encoches longues et courtes) qui tourne
// lentement ; l'ANNEAU de la marque, avec ses trois CROCS tournés vers le
// centre ; un fond sombre derrière la GOUTTE, qui porte un œil (la cible est
// marquée). Aplats rouges et encre, reflet rouge clair (pas de blanc). Pointé
// ou porté (`eveil`), l'anneau devient un compte à rebours qui se vide et se
// recharge, et la couronne tourne.
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
uniform vec4 couleur : source_color = vec4(0.76, 0.03, 0.11, 1.0);
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

// la goutte (négative dedans), en px de la rune du jeu (~30 px de haut)
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

	// ===================== LA COURONNE DE RUNES =====================
	float tourne = temps * 0.25 * eveil;
	float ang = atan(p.y, p.x) + tourne;
	float bande = 0.045 - abs(r - 0.83);
	forme(f_rgb, f_a, bande, sombre.rgb * 1.6, encre_color.rgb, e * 0.7, px);
	// les encoches : 16, une longue sur deux
	float k = fract(ang / TAU * 16.0);
	float longue = step(0.5, fract(floor(ang / TAU * 16.0) * 0.5));
	float encoche = min(0.012 - abs(k - 0.5) * TAU * 0.83 / 16.0, (0.045 + 0.03 * longue) - abs(r - 0.83));
	par_dessus(f_rgb, f_a, encre_color.rgb, smoothstep(0.0, px, encoche));

	// ===================== LE FOND DU SCEAU, L'ANNEAU ET SES CROCS =====================
	forme(f_rgb, f_a, 0.5 - r, sombre.rgb, encre_color.rgb, e * 0.7, px);
	float restant = mix(1.0, 1.0 - fract(temps * 0.35), eveil);
	float part = fract(atan(p.x, -p.y) / TAU + 1.0);
	float arc = (restant - part) * 0.6 * TAU;
	float anneau = min(0.07 - abs(r - 0.6), arc);
	forme(f_rgb, f_a, anneau, couleur.rgb, encre_color.rgb, e, px);
	for (int i = 0; i < 3; i++) {
		float th = float(i) * TAU / 3.0 + PI * 0.5 + 0.35;
		vec2 dir = vec2(cos(th), sin(th));
		vec2 cote = vec2(-dir.y, dir.x);
		// un croc : un triangle planté dans l'anneau, sa pointe vers le centre
		vec2 q = vec2(dot(p, cote), dot(p, dir) - 0.36);
		float dcroc = -triangle(q, vec2(0.085, 0.2));
		forme(f_rgb, f_a, dcroc, couleur.rgb, encre_color.rgb, e, px);
	}

	// ===================== LA GOUTTE =====================
	float k_g = 30.0 / 0.78;
	float dg = -sd_goutte(p * k_g) / k_g;
	forme(f_rgb, f_a, dg, couleur.rgb, encre_color.rgb, e, px);
	// l'ombre du bas de la goutte, et son reflet
	par_dessus(f_rgb, f_a, couleur.rgb * 0.7, smoothstep(0.0, px, min(dg, p.y - 0.12 + p.x * 0.4)) * 0.9);
	par_dessus(f_rgb, f_a, clair.rgb, smoothstep(0.0, px, min(0.04 - length((p - vec2(-0.1, 0.0)) * vec2(1.6, 1.0)), dg - 0.02)) * 0.85);
	// l'œil : une fente d'encre dans le bas de la goutte, qui cligne éveillé
	float cligne = 1.0 - eveil * smoothstep(0.92, 1.0, fract(temps * 0.4)) * 0.9;
	vec2 qo = (p - vec2(0.0, 0.13)) / vec2(0.1, 0.055 * cligne);
	float oeil = 1.0 - length(qo);
	par_dessus(f_rgb, f_a, encre_color.rgb, smoothstep(0.0, px * 12.0, oeil));
	float pupille = min(0.018 - abs(p.x), 0.05 * cligne - abs(p.y - 0.13));
	par_dessus(f_rgb, f_a, couleur.rgb, smoothstep(0.0, px, pupille));

	rgb = mix(rgb, f_rgb, f_a * champ);
	COLOR = vec4(rgb, a * opacite);
}
