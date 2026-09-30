shader_type canvas_item;
render_mode unshaded;
// DESSIN DU TALISMAN « BOUCLIER DE SANG » (menu START, 30 sept. 2026).
// emplacement_talisman.gd le pose dans le rond et lui fournit `opacite`,
// `eveil` et `temps`.
// TOUT LE ROND est au dessin : un disque sombre cerné d'un trait d'encre, et
// dedans un grand hexagone de sang taillé en facettes hexagonales, aux arêtes
// claires, cerné d'encre. Pointé ou porté (`eveil`), un reflet balaie les
// facettes et leurs arêtes s'allument.
// Aplats nets et trait d'encre. À dessiner dans un CARRÉ : le disque le remplit.

// --- fournis par emplacement_talisman.gd (les mêmes pour tout dessin de talisman) ---
uniform float opacite : hint_range(0.0, 1.0) = 1.0;
uniform float eveil : hint_range(0.0, 1.0) = 0.0;
uniform float temps = 0.0;
// ----------------------------------------------------------------------------

// --- le disque ---
uniform vec4 encre_color : source_color = vec4(0.1, 0.02, 0.04, 1.0);
uniform vec4 fond_color : source_color = vec4(0.13, 0.02, 0.05, 1.0);
// épaisseur du trait d'encre (en part du rayon du disque)
uniform float trait : hint_range(0.0, 0.1) = 0.045;
// --- le bouclier ---
uniform vec4 sang_color : source_color = vec4(0.72, 0.13, 0.17, 1.0);
uniform vec4 arete_color : source_color = vec4(1.0, 0.55, 0.5, 1.0);
uniform vec4 reflet_color : source_color = vec4(1.0, 0.93, 0.9, 1.0);
// rayon du grand hexagone (part du rayon du disque)
uniform float rayon : hint_range(0.5, 0.95) = 0.8;
// taille des facettes (part du rayon du disque)
uniform float facette : hint_range(0.15, 0.6) = 0.46;
// épaisseur des arêtes entre facettes (part du rayon)
uniform float lignes : hint_range(0.005, 0.05) = 0.022;

// (PI et TAU sont fournis par le langage de shader de Godot)

float disque(float d, float r, float px) {
	return smoothstep(r + px * 0.5, r - px * 0.5, d);
}

float alea(vec2 p) {
	p = fract(p * vec2(443.897, 441.423));
	p += dot(p, p.yx + 19.19);
	return fract((p.x + p.y) * p.x);
}

// le pavage d'hexagones (pointe en haut, rayon inscrit 0,5) : le centre de la
// cellule du point `u`, et son identité dans `id`
vec2 centre_hex(vec2 u, out vec2 id) {
	const float H = 0.8660254;
	vec2 meilleur = vec2(0.0);
	float dmin = 1e9;
	float j0 = floor(u.y / H);
	for (int k = 0; k < 2; k++) {
		float j = j0 + float(k);
		float decale = 0.5 * mod(j, 2.0);
		float i = floor(u.x - decale + 0.5);
		vec2 c = vec2(i + decale, j * H);
		float d = dot(u - c, u - c);
		if (d < dmin) {
			dmin = d;
			meilleur = c;
			id = vec2(i, j);
		}
	}
	return meilleur;
}

// distance au bord d'un hexagone pointe en haut de rayon inscrit `ri`
// (positive dedans), `v` depuis son centre
float dedans_hex(vec2 v, float ri) {
	v = abs(v);
	return ri - max(v.x, 0.5 * v.x + 0.8660254 * v.y);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float px = fwidth(UV.x) * 2.0;

	// ===================== LE DISQUE =====================
	vec3 rgb = encre_color.rgb;
	float a = disque(r, 1.0, px);
	rgb = mix(rgb, fond_color.rgb, disque(r, 1.0 - trait, px));

	// ===================== LE BOUCLIER =====================
	// le grand hexagone (pointe en haut), cerné d'encre
	float grand = dedans_hex(p, rayon * 0.8660254);
	// ses facettes
	vec2 id;
	vec2 c = centre_hex(p / facette, id);
	float d_bord = dedans_hex(p / facette - c, 0.5) * facette;   // en part du rayon
	float chair = smoothstep(-px * 0.5, px * 0.5, min(grand, d_bord - lignes * 0.5));
	float arete = smoothstep(-px * 0.5, px * 0.5, grand) * (1.0 - smoothstep(lignes * 0.5 - px * 0.5, lignes * 0.5 + px * 0.5, d_bord));
	// chaque facette a sa nuance ; éveillé, un reflet les balaie en diagonale
	float nuance = 0.85 + 0.3 * alea(id + vec2(7.0, 3.0));
	float balayage = fract(temps * 0.35);
	float bande = dot(p, vec2(0.7071, 0.7071)) * 0.5 + 0.5;      // 0 en haut à gauche → 1 en bas à droite
	float reflet = eveil * (1.0 - smoothstep(0.0, 0.16, abs(bande - balayage * 1.4 + 0.2)));
	vec3 rgb_chair = sang_color.rgb * nuance;
	rgb_chair = mix(rgb_chair, reflet_color.rgb, 0.7 * reflet);
	rgb = mix(rgb, encre_color.rgb, smoothstep(-px * 0.5, px * 0.5, grand + trait));
	rgb = mix(rgb, rgb_chair, chair);
	rgb = mix(rgb, mix(arete_color.rgb, reflet_color.rgb, 0.5 * eveil + 0.5 * reflet), arete);

	COLOR = vec4(rgb, a * opacite);
}
