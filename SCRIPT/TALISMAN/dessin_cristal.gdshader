shader_type canvas_item;
render_mode unshaded;
// DESSIN DU TALISMAN « SANG CRISTALLISÉ » (menu START, 1er oct. 2026) —
// provisoire, en attendant le dessin définitif.
// emplacement_talisman.gd le pose dans le rond et lui fournit `opacite`,
// `eveil` et `temps`.
// TOUT LE ROND est au dessin : un disque de nuit cerné d'un trait d'encre ;
// dedans, TROIS CRISTAUX de sang qui montent du bas (un grand au milieu, deux
// petits penchés), taillés en facettes (trois tons de rouge), cernés d'encre ;
// un reflet passe sur eux quand le talisman est pointé ou porté. Pas de blanc.
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
uniform vec4 sombre : source_color = vec4(0.36, 0.02, 0.08, 1.0);
uniform vec4 couleur : source_color = vec4(0.78, 0.06, 0.14, 1.0);
uniform vec4 clair : source_color = vec4(1.0, 0.5, 0.55, 1.0);

float disque(float d, float r, float px) {
	return smoothstep(r + px * 0.5, r - px * 0.5, d);
}

// dans le repère d'un cristal penché de `ang` (x en travers, y vers sa pointe)
vec2 repere(vec2 p, vec2 pied, float ang) {
	vec2 q = p - pied;
	return vec2(cos(ang) * q.x + sin(ang) * q.y, -sin(ang) * q.x + cos(ang) * q.y);
}

// un CRISTAL : un prisme de demi-largeur w et de hauteur h, pointe en haut
// (repère : y négatif vers la pointe). Renvoie la distance (positive dedans) ;
// `face` reçoit -1 (face gauche), 0 (face du milieu), +1 (face droite).
float cristal(vec2 q, float w, float h, out float face) {
	float corps = min(w - abs(q.x), min(q.y + h * 0.72, 0.02 - q.y));
	// la pointe : deux pentes de la largeur au sommet
	float pointe = (h - (-q.y)) * (w / (h * 0.28)) - abs(q.x);
	float d = mix(corps, min(pointe, w - abs(q.x)), step(q.y, -h * 0.72));
	face = step(w * 0.35, q.x) - step(q.x, -w * 0.35);
	return d;
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

	// ===================== LES CRISTAUX (les petits d'abord) =====================
	for (int i = 0; i < 3; i++) {
		vec2 pied;
		float ang;
		float w;
		float h;
		if (i == 0) {
			pied = vec2(-0.3, 0.62); ang = -0.45; w = 0.12; h = 0.62;
		} else if (i == 1) {
			pied = vec2(0.32, 0.62); ang = 0.5; w = 0.11; h = 0.55;
		} else {
			pied = vec2(0.0, 0.66); ang = 0.0; w = 0.2; h = 1.15;
		}
		vec2 q = repere(p, pied, ang);
		float face;
		float d = min(cristal(q, w, h, face), dedans);
		vec3 teinte = mix(couleur.rgb, clair.rgb, step(face, -0.5));
		teinte = mix(teinte, sombre.rgb, step(0.5, face));
		// un reflet qui passe en diagonale quand le talisman est éveillé
		float bande = abs(fract((p.x + p.y) * 0.8 - temps * 0.35) - 0.5);
		teinte = mix(teinte, clair.rgb, (1.0 - smoothstep(0.02, 0.06, bande)) * 0.7 * eveil);
		rgb = mix(rgb, encre_color.rgb, smoothstep(-px * 0.5, px * 0.5, d + trait));
		rgb = mix(rgb, teinte, smoothstep(-px * 0.5, px * 0.5, d));
		// les arêtes entre les faces, en encre fine
		float arete = min(abs(abs(q.x) - w * 0.35) - 0.006, 1.0);
		rgb = mix(rgb, encre_color.rgb, smoothstep(px, 0.0, arete) * smoothstep(-px, px, d - 0.01));
	}

	COLOR = vec4(rgb, a * opacite);
}
