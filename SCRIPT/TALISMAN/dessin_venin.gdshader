shader_type canvas_item;
render_mode unshaded;
// DESSIN DU TALISMAN « VENIN » (menu START, 1er oct. 2026) — provisoire, en
// attendant le dessin de Kaoru.
// emplacement_talisman.gd le pose dans le rond et lui fournit `opacite`,
// `eveil` et `temps`.
// TOUT LE ROND est au dessin : un disque de nuit violette cerné d'un trait
// d'encre ; en haut, une MÂCHOIRE d'où pendent DEUX CROCS courbés ; à la
// pointe du croc de droite, une GOUTTE de venin violette perle, grossit, tombe
// et recommence ; une perle reste au croc de gauche. Aplats, trait d'encre,
// reflet mauve (pas de blanc). (Un seul croc droit et sa goutte se lisaient
// comme un « ! ».) Le temps passe plus vite quand le talisman est pointé ou
// porté (`temps`).
// À dessiner dans un CARRÉ : le disque le remplit.

// --- fournis par emplacement_talisman.gd (les mêmes pour tout dessin de talisman) ---
uniform float opacite : hint_range(0.0, 1.0) = 1.0;
uniform float eveil : hint_range(0.0, 1.0) = 0.0;
uniform float temps = 0.0;
// ----------------------------------------------------------------------------

uniform vec4 encre_color : source_color = vec4(0.07, 0.02, 0.09, 1.0);
uniform vec4 fond_color : source_color = vec4(0.05, 0.02, 0.07, 1.0);
uniform vec4 fond_centre : source_color = vec4(0.16, 0.05, 0.21, 1.0);
uniform float trait : hint_range(0.0, 0.1) = 0.045;
uniform vec4 gencive : source_color = vec4(0.34, 0.07, 0.22, 1.0);
uniform vec4 ivoire : source_color = vec4(0.86, 0.8, 0.7, 1.0);
uniform vec4 ivoire_ombre : source_color = vec4(0.62, 0.55, 0.5, 1.0);
uniform vec4 couleur : source_color = vec4(0.58, 0.14, 0.84, 1.0);
uniform vec4 couleur_vive : source_color = vec4(0.78, 0.42, 1.0, 1.0);
uniform vec4 clair : source_color = vec4(0.92, 0.74, 1.0, 1.0);

float disque(float d, float r, float px) {
	return smoothstep(r + px * 0.5, r - px * 0.5, d);
}

void forme(inout vec3 rgb, float d, vec3 teinte, float e, float px) {
	rgb = mix(rgb, encre_color.rgb, smoothstep(-px * 0.5, px * 0.5, d + e));
	rgb = mix(rgb, teinte, smoothstep(-px * 0.5, px * 0.5, d));
}

// un CROC qui pend de `base` à `pointe` en se courbant vers l'intérieur,
// large de `w` à la base ; positif dedans. `cote` reçoit -1/+1 (côté du croc
// par rapport à son axe) pour l'ombrer.
float croc(vec2 p, vec2 base, vec2 pointe, float w, out float cote) {
	float t = clamp((p.y - base.y) / (pointe.y - base.y), 0.0, 1.0);
	float axe = mix(base.x, pointe.x, t * t);
	float demi = w * (1.0 - pow(t, 1.3));
	cote = sign(p.x - axe);
	return min(demi - abs(p.x - axe), min(p.y - base.y + 0.05, pointe.y - p.y));
}

// une goutte (pointe en haut) de rayon `rg` centrée en `c`, positive dedans
float goutte(vec2 p, vec2 c, float rg) {
	vec2 q = p - c;
	float rond = rg - length(q);
	float pointe = rg * 0.9 - abs(q.x) * 1.7 + q.y * 0.55;
	// sous son centre : le rond seul (multiplier par un step donnait 0, c.-à-d.
	// « sur le bord », partout dessous : la moitié du disque se teintait)
	return mix(max(rond, min(pointe, rg * 1.6 + q.y)), rond, step(0.0, q.y));
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

	// ===================== LES DEUX CROCS =====================
	for (int i = 0; i < 2; i++) {
		float s = 1.0 - 2.0 * float(i);                       // droite, puis gauche
		vec2 base = vec2(s * 0.27, -0.5);
		vec2 pointe = vec2(s * 0.15, 0.08 + 0.04 * float(i));
		float cote;
		float d = min(croc(p, base, pointe, 0.12, cote), dedans);
		forme(rgb, d, mix(ivoire.rgb, ivoire_ombre.rgb, step(0.0, cote * s)), trait, px);
	}

	// ===================== LA MÂCHOIRE (par-dessus la racine des crocs) =====================
	float machoire = min(0.36 - length((p - vec2(0.0, -0.86)) * vec2(0.58, 1.5)), dedans);
	forme(rgb, machoire, gencive.rgb, trait, px);

	// ===================== LE VENIN =====================
	// au croc de droite : la goutte perle (0 → 0,6), puis tombe (0,6 → 1)
	float vie = fract(temps / 1.8);
	float perle = smoothstep(0.0, 0.6, vie);
	float tombe = max(vie - 0.6, 0.0) / 0.4;
	float rg = mix(0.05, 0.15, perle) * (1.0 - 0.3 * tombe);
	vec2 c = vec2(0.15, 0.1 + rg * 0.9 + 0.75 * tombe * tombe);
	float g = min(goutte(p, c, rg), dedans);
	forme(rgb, g, couleur.rgb, trait * 0.8, px);
	rgb = mix(rgb, mix(couleur_vive.rgb, clair.rgb, 0.4),
			smoothstep(-px * 0.5, px * 0.5, min(rg * 0.33 - length(p - c - vec2(-rg * 0.35, -rg * 0.2)), g)));
	// une perle restée au croc de droite pendant que la goutte tombe, et une
	// au croc de gauche
	forme(rgb, min(0.035 * step(0.6, vie) - length(p - vec2(0.15, 0.11)), dedans), couleur.rgb, trait * 0.6, px);
	forme(rgb, min(0.05 - length(p - vec2(-0.15, 0.17)), dedans), couleur.rgb, trait * 0.6, px);

	COLOR = vec4(rgb, a * opacite);
}
