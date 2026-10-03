shader_type canvas_item;
render_mode unshaded;
// DESSIN DU TALISMAN « ÉPINES DE SANG » (menu START, 1er oct. 2026) —
// provisoire, en attendant le dessin définitif.
// emplacement_talisman.gd le pose dans le rond et lui fournit `opacite`,
// `eveil` et `temps`.
// TOUT LE ROND est au dessin : un disque de nuit cerné d'un trait d'encre, au
// fond un dégradé et une ONDE DE CHOC (rayons sombres, anneau déchiqueté) ;
// derrière, une couronne de longs pics sombres ; devant, une couronne de pics
// de sang plus courts, chacun avec son arête d'encre ; des gouttes projetées
// entre eux ; au centre, le CŒUR d'où tout jaillit. Aplats rouges et encre,
// reflets rouge clair (pas de blanc). Pointé ou porté (`eveil`), les pics
// jaillissent un peu plus loin à chaque pulsation et les gouttes filent.
// À dessiner dans un CARRÉ : le disque le remplit.

// --- fournis par emplacement_talisman.gd (les mêmes pour tout dessin de talisman) ---
uniform float opacite : hint_range(0.0, 1.0) = 1.0;
uniform float eveil : hint_range(0.0, 1.0) = 0.0;
uniform float temps = 0.0;
// ----------------------------------------------------------------------------

uniform vec4 encre_color : source_color = vec4(0.1, 0.02, 0.04, 1.0);
uniform vec4 fond_color : source_color = vec4(0.06, 0.02, 0.04, 1.0);
uniform vec4 fond_centre : source_color = vec4(0.2, 0.03, 0.06, 1.0);
uniform float trait : hint_range(0.0, 0.1) = 0.045;
uniform vec4 couleur : source_color = vec4(0.78, 0.04, 0.12, 1.0);
uniform vec4 sombre : source_color = vec4(0.32, 0.01, 0.06, 1.0);
uniform vec4 clair : source_color = vec4(1.0, 0.5, 0.5, 1.0);

float disque(float d, float r, float px) {
	return smoothstep(r + px * 0.5, r - px * 0.5, d);
}

void par_dessus(inout vec3 rgb, inout float a, vec3 teinte, float force) {
	float total = force + a * (1.0 - force);
	rgb = (teinte * force + rgb * a * (1.0 - force)) / max(total, 0.0001);
	a = total;
}

// une forme (distance positive dedans) avec son liseré d'encre
void forme(inout vec3 rgb, inout float a, float d, vec3 teinte, vec3 encre, float e, float px) {
	par_dessus(rgb, a, encre, smoothstep(0.0, px, d + e));
	par_dessus(rgb, a, teinte, smoothstep(0.0, px, d));
}

// distance signée à un cœur (négative dedans), pointe en bas, taille ~1
float sd_coeur(vec2 q) {
	q.x = abs(q.x);
	q.y = -q.y + 0.35;
	if (q.y + q.x > 1.0) {
		return sqrt(dot(q - vec2(0.25, 0.75), q - vec2(0.25, 0.75))) - sqrt(2.0) / 4.0;
	}
	float d1 = dot(q - vec2(0.0, 1.0), q - vec2(0.0, 1.0));
	float m = 0.5 * max(q.x + q.y, 0.0);
	float d2 = dot(q - vec2(m), q - vec2(m));
	return sqrt(min(d1, d2)) * sign(q.x - q.y);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float px = fwidth(UV.x) * 2.0;
	float ang = atan(p.y, p.x);
	float e = 0.04;

	// ===================== LE DISQUE =====================
	vec3 rgb = encre_color.rgb;
	float a = disque(r, 1.0, px);
	float champ = disque(r, 1.0 - trait, px);
	rgb = mix(rgb, mix(fond_centre.rgb, fond_color.rgb, smoothstep(0.0, 0.95, r)), champ);

	vec3 f_rgb = couleur.rgb;
	float f_a = 0.0;
	// la pulsation (éveillé) : un jaillissement bref, puis le repos
	float pouls = eveil * exp(-fract(temps * 0.9) * 6.0);

	// ===================== L'ONDE DE CHOC =====================
	float rayons = smoothstep(0.8, 1.0, abs(sin(ang * 12.0 + 0.4)))
			* smoothstep(0.3, 0.45, r) * (1.0 - smoothstep(0.78, 0.96, r));
	par_dessus(f_rgb, f_a, sombre.rgb, rayons * 0.55);
	float r_onde = 0.5 + 0.035 * sin(ang * 7.0) + 0.02 * sin(ang * 13.0 + 1.0) + 0.05 * pouls;
	par_dessus(f_rgb, f_a, sombre.rgb * 1.4, smoothstep(0.0, px, 0.022 - abs(r - r_onde)));

	// ===================== LES PICS : derrière, puis devant =====================
	for (int couche = 0; couche < 2; couche++) {
		float fc = float(couche);
		for (int i = 0; i < 8; i++) {
			float fi = float(i);
			float theta = (fi + 0.5 * fc) * TAU / 8.0 - PI * 0.5 + 0.1 * sin(fi * 2.7 + fc);
			vec2 dir = vec2(cos(theta), sin(theta));
			vec2 cote = vec2(-dir.y, dir.x);
			float L = mix(0.93, 0.74, fc) * (0.9 + 0.1 * sin(fi * 1.9 + fc * 3.0)) + 0.05 * pouls;
			float pied = 0.2;
			float w0 = mix(0.06, 0.095, fc);
			float u = dot(p, dir);
			float s = (u - pied) / (L - pied);
			float v = dot(p, cote) - 0.06 * sin(fi * 1.3 + fc) * s * s;
			float w = w0 * clamp(1.0 - s, 0.0, 1.0);
			float d = min(min(w - abs(v), u - pied + 0.03), L - u);
			forme(f_rgb, f_a, d, mix(sombre.rgb * 1.7, couleur.rgb, fc), encre_color.rgb, e * 0.8, px);
			if (couche == 1) {
				// l'arête d'encre au milieu du pic, qui s'arrête avant la pointe
				float arete = min(0.007 - abs(v), d - 0.012);
				par_dessus(f_rgb, f_a, encre_color.rgb, smoothstep(0.0, px, arete) * step(s, 0.8) * 0.85);
			}
		}
	}

	// ===================== LES GOUTTES PROJETÉES =====================
	for (int i = 0; i < 6; i++) {
		float fi = float(i);
		float theta = (fi * 1.333 + 0.25) * TAU / 8.0 - PI * 0.5 + 0.6;
		vec2 dir = vec2(cos(theta), sin(theta));
		vec2 cote = vec2(-dir.y, dir.x);
		float rg = mix(0.62, 0.8, fract(fi * 0.618)) + 0.06 * eveil * fract(temps * 0.9 + fi * 0.17);
		vec2 q = p - dir * rg;
		float uu = dot(q, dir);
		float vv = dot(q, cote);
		float taille = mix(0.035, 0.05, fract(fi * 0.381));
		// la tête vers l'extérieur, la traîne vers le cœur
		float dg = taille - length(vec2(uu > 0.0 ? uu : uu * 0.4, vv));
		forme(f_rgb, f_a, dg, couleur.rgb, encre_color.rgb, e * 0.6, px);
	}

	// ===================== LE CŒUR =====================
	float tc = 0.28 * (1.0 + 0.06 * pouls);
	vec2 qc = p / tc;
	qc.y += 0.12;
	float dc = -sd_coeur(qc) * tc;
	forme(f_rgb, f_a, dc, couleur.rgb, encre_color.rgb, e, px);
	// son reflet : un croissant rouge clair sur le lobe gauche
	float reflet = min(0.045 - length((p - vec2(-0.1, -0.1)) * vec2(1.0, 1.4)), dc - 0.02);
	par_dessus(f_rgb, f_a, clair.rgb, smoothstep(0.0, px, reflet) * 0.85);

	rgb = mix(rgb, f_rgb, f_a * champ);
	COLOR = vec4(rgb, a * opacite);
}
