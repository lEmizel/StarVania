shader_type canvas_item;
render_mode unshaded;
// DESSIN DU TALISMAN « SANG CORROMPU » (menu START, 1er oct. 2026) —
// provisoire, en attendant le dessin définitif.
// emplacement_talisman.gd le pose dans le rond et lui fournit `opacite`,
// `eveil` et `temps`.
// TOUT LE ROND est au dessin : un disque de nuit violette cerné d'un trait
// d'encre ; au milieu, la BOULE CORROMPUE (violette, cœur mauve) d'où pendent
// trois coulures de poison qui s'allongent, lâchent leur goutte et
// recommencent ; au-dessus, des volutes violettes montent. Aplats (trois tons
// sur la boule), trait d'encre, reflets mauves (pas de blanc). Le temps passe
// plus vite quand le talisman est pointé ou porté (`temps`), et la boule bat.
// À dessiner dans un CARRÉ : le disque le remplit.

// --- fournis par emplacement_talisman.gd (les mêmes pour tout dessin de talisman) ---
uniform float opacite : hint_range(0.0, 1.0) = 1.0;
uniform float eveil : hint_range(0.0, 1.0) = 0.0;
uniform float temps = 0.0;
// ----------------------------------------------------------------------------

uniform vec4 encre_color : source_color = vec4(0.07, 0.02, 0.09, 1.0);
uniform vec4 fond_color : source_color = vec4(0.05, 0.02, 0.07, 1.0);
uniform vec4 fond_centre : source_color = vec4(0.16, 0.05, 0.21, 1.0);
// épaisseur du trait d'encre (en part du rayon du disque)
uniform float trait : hint_range(0.0, 0.1) = 0.045;
uniform vec4 couleur : source_color = vec4(0.58, 0.14, 0.84, 1.0);
uniform vec4 couleur_vive : source_color = vec4(0.78, 0.42, 1.0, 1.0);
uniform vec4 sombre : source_color = vec4(0.24, 0.03, 0.36, 1.0);
uniform vec4 clair : source_color = vec4(0.92, 0.74, 1.0, 1.0);
// la boule : son centre et son rayon (part du rayon du disque)
uniform vec2 centre_boule = vec2(0.0, -0.1);
uniform float rayon_boule : hint_range(0.1, 0.5) = 0.34;

float disque(float d, float r, float px) {
	return smoothstep(r + px * 0.5, r - px * 0.5, d);
}

float alea(float n) {
	return fract(sin(n * 12.9898 + 4.1414) * 43758.5453);
}

// union adoucie de deux formes (positives dedans)
float smax(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (a - b) / k, 0.0, 1.0);
	return mix(b, a, h) + k * h * (1.0 - h);
}

// une forme (positive dedans), cernée d'encre, posée sur le dessin
void forme(inout vec3 rgb, float d, vec3 teinte, float e, float px, float f) {
	rgb = mix(rgb, encre_color.rgb, f * smoothstep(-px * 0.5, px * 0.5, d + e));
	rgb = mix(rgb, teinte, f * smoothstep(-px * 0.5, px * 0.5, d));
}

// une COULURE qui pend en x = xc, de y0 (dans la boule) à yb : une tige qui
// s'affine jusqu'à sa goutte de rayon rg ; positive dedans
float coulure(vec2 p, float xc, float y0, float yb, float w, float rg) {
	float y = clamp(p.y, y0, yb);
	float t = clamp((y - y0) / max(yb - y0, 0.001), 0.0, 1.0);
	float tige = mix(w, w * 0.45, t) - length(vec2(p.x - xc, p.y - y));
	float goutte = rg - length(p - vec2(xc, yb + rg * 0.5));
	return smax(tige, goutte, 0.03);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;                 // -1 … 1 : le médaillon est le disque de rayon 1
	float r = length(p);
	float px = fwidth(UV.x) * 2.0;             // un pixel d'écran, dans cette unité

	// ===================== LE DISQUE =====================
	vec3 rgb = encre_color.rgb;
	float a = disque(r, 1.0, px);
	rgb = mix(rgb, mix(fond_centre.rgb, fond_color.rgb, smoothstep(0.0, 0.95, r)),
			disque(r, 1.0 - trait, px));
	// rien ne déborde du fond
	float clip = disque(r, 1.0 - trait * 1.6, px);

	vec2 cb = centre_boule;
	float R = rayon_boule * (1.0 + 0.05 * eveil * sin(temps * 2.4));

	// ===================== LES VOLUTES (derrière la boule) =====================
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		float u = temps / (1.6 + 0.5 * alea(fi * 3.1)) + alea(fi * 7.3);
		float k = floor(u);
		float vie = u - k;
		vec2 c = vec2((alea(fi * 1.9 + k * 2.3) - 0.5) * 0.42 + sin(vie * 4.0 + fi * 2.0) * 0.05,
				cb.y - R * 0.55 - vie * 0.5);
		float rv = 0.12 * smoothstep(0.0, 0.3, vie) * (1.0 - 0.4 * vie);
		float efface = 1.0 - smoothstep(0.55, 1.0, vie);
		vec2 q = p - c;
		q.y *= mix(1.0, 0.75, step(0.0, -q.y));   // étirée vers le haut
		forme(rgb, rv - length(q), mix(couleur.rgb, couleur_vive.rgb, 0.25), trait * 0.6, px, clip * efface);
	}

	// ===================== LES COULURES (derrière la boule : elles en sortent) =====================
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		float xc = (fi - 1.0) * 0.17 + 0.02;
		float vie = fract(temps / (2.2 + 0.6 * alea(fi * 5.7)) + alea(fi * 9.1));
		// elle s'allonge (0 → 0,7), lâche sa goutte (0,7), se rétracte
		float croit = smoothstep(0.0, 0.7, vie);
		float lache = smoothstep(0.7, 0.78, vie);
		float y_bord = cb.y + sqrt(max(R * R - (xc - cb.x) * (xc - cb.x), 0.0));
		float l_max = 0.24 + 0.1 * alea(fi * 2.2);
		float yb = y_bord + mix(0.04, l_max, croit) * (1.0 - 0.75 * lache);
		float rg = mix(0.035, 0.065, croit) * (1.0 - lache);
		float d = coulure(p, xc, y_bord - 0.08, yb, 0.055, rg);
		// la goutte lâchée tombe en accélérant
		float tc = max(vie - 0.7, 0.0);
		vec2 cg = vec2(xc, y_bord + l_max + 0.06 + 5.0 * tc * tc);
		float d_goutte = 0.06 - length((p - cg) * vec2(1.0, 0.8));
		d = max(d, mix(-1.0, d_goutte, step(0.7, vie)));
		forme(rgb, d, couleur.rgb, trait * 0.8, px, clip);
	}

	// ===================== LA BOULE =====================
	vec2 l = (p - cb) / R;
	float db = R - length(p - cb);
	// éclairée d'en haut à gauche : trois tons francs en croissants (l'ombre en
	// bas à droite, le violet, le vif autour du cœur) — avec un éclairage en
	// ligne droite, c'étaient des rayures de bonbon
	float eclaire = 1.0 - length(l - vec2(-0.38, -0.38)) / 1.75;
	float bord_px = px * 2.0 / R;
	vec3 teinte = mix(sombre.rgb, couleur.rgb, smoothstep(0.22 - bord_px, 0.22 + bord_px, eclaire));
	teinte = mix(teinte, couleur_vive.rgb, smoothstep(0.62 - bord_px, 0.62 + bord_px, eclaire));
	forme(rgb, db, teinte, trait, px, 1.0);
	// son cœur mauve et son reflet
	float dc = R * 0.36 - length(l * R - vec2(-0.12, -0.12) * R / 0.34);
	rgb = mix(rgb, mix(couleur_vive.rgb, clair.rgb, 0.45), smoothstep(-px * 0.5, px * 0.5, dc));
	float dh = R * 0.12 - length(l * R - vec2(-0.17, -0.18) * R / 0.34);
	rgb = mix(rgb, clair.rgb, smoothstep(-px * 0.5, px * 0.5, dh));

	COLOR = vec4(rgb, a * opacite);
}
