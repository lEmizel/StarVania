shader_type canvas_item;
render_mode unshaded;
// DESSIN DU TALISMAN « LAME CORROMPUE » (menu START, 1er oct. 2026) —
// provisoire, en attendant le dessin de Kaoru.
// emplacement_talisman.gd le pose dans le rond et lui fournit `opacite`,
// `eveil` et `temps`.
// TOUT LE ROND est au dessin : un disque de nuit violette cerné d'un trait
// d'encre ; dedans, une ÉPÉE en diagonale dont la lame est violette (son fil
// mauve), d'où pendent deux coulures de poison qui lâchent leur goutte, et
// d'où montent des volutes violettes — la sœur du dessin du Sang corrompu.
// Aplats et trait d'encre, pas de blanc. Le temps passe plus vite quand le
// talisman est pointé ou porté (`temps`).
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
uniform vec4 couleur : source_color = vec4(0.58, 0.14, 0.84, 1.0);
uniform vec4 couleur_vive : source_color = vec4(0.78, 0.42, 1.0, 1.0);
uniform vec4 sombre : source_color = vec4(0.24, 0.03, 0.36, 1.0);
uniform vec4 clair : source_color = vec4(0.92, 0.74, 1.0, 1.0);
uniform vec4 garde : source_color = vec4(0.32, 0.22, 0.36, 1.0);

float disque(float d, float r, float px) {
	return smoothstep(r + px * 0.5, r - px * 0.5, d);
}

float alea(float n) {
	return fract(sin(n * 12.9898 + 4.1414) * 43758.5453);
}

float smax(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (a - b) / k, 0.0, 1.0);
	return mix(b, a, h) + k * h * (1.0 - h);
}

void forme(inout vec3 rgb, float d, vec3 teinte, float e, float px, float f) {
	rgb = mix(rgb, encre_color.rgb, f * smoothstep(-px * 0.5, px * 0.5, d + e));
	rgb = mix(rgb, teinte, f * smoothstep(-px * 0.5, px * 0.5, d));
}

// dans le repère de l'épée (tournée de `ang`) : x le long de la lame
vec2 repere(vec2 p, float ang) {
	return vec2(cos(ang) * p.x + sin(ang) * p.y, -sin(ang) * p.x + cos(ang) * p.y);
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
	float clip = disque(r, 1.0 - trait * 1.6, px);

	// l'épée monte vers la droite ; sa lame va de x = -0.28 à la pointe en 0.74
	float ang = -0.62;
	vec2 q = repere(p - vec2(-0.04, 0.06), ang);

	// ===================== LES VOLUTES (derrière) =====================
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		float u = temps / (1.5 + 0.5 * alea(fi * 3.1)) + alea(fi * 7.3);
		float k = floor(u);
		float vie = u - k;
		// elles partent de la lame (un point au hasard le long d'elle) et montent
		float le_long = mix(-0.1, 0.6, alea(fi * 1.9 + k * 2.3));
		vec2 depart = vec2(-0.04, 0.06) + vec2(cos(ang), sin(ang)) * le_long;
		vec2 c = depart + vec2(sin(vie * 4.0 + fi * 2.0) * 0.05, -0.12 - vie * 0.42);
		float rv = 0.1 * smoothstep(0.0, 0.3, vie) * (1.0 - 0.4 * vie);
		float efface = 1.0 - smoothstep(0.55, 1.0, vie);
		vec2 qv = p - c;
		qv.y *= mix(1.0, 0.75, step(0.0, -qv.y));
		forme(rgb, rv - length(qv), mix(couleur.rgb, couleur_vive.rgb, 0.25), trait * 0.6, px, clip * efface);
	}

	// ===================== LES COULURES (sous la lame) =====================
	for (int i = 0; i < 2; i++) {
		float fi = float(i);
		float le_long = 0.12 + fi * 0.3;
		// le point du fil de la lame (côté bas) d'où elle pend — la tige part de
		// sous la lame, qui est dessinée par-dessus
		vec2 bord = vec2(-0.04, 0.06) + vec2(cos(ang), sin(ang)) * le_long + vec2(-sin(ang), cos(ang)) * 0.05;
		float vie = fract(temps / (2.0 + 0.6 * alea(fi * 5.7)) + alea(fi * 9.1));
		float croit = smoothstep(0.0, 0.7, vie);
		float lache = smoothstep(0.7, 0.78, vie);
		float l_max = 0.2 + 0.08 * alea(fi * 2.2);
		float yb = bord.y + mix(0.03, l_max, croit) * (1.0 - 0.75 * lache);
		float rg = mix(0.03, 0.055, croit) * (1.0 - lache);
		float y = clamp(p.y, bord.y - 0.04, yb);
		float tt = clamp((y - bord.y) / max(yb - bord.y, 0.001), 0.0, 1.0);
		float tige = mix(0.045, 0.02, tt) - length(vec2(p.x - bord.x, p.y - y));
		float goutte = rg - length(p - vec2(bord.x, yb + rg * 0.5));
		float d = smax(tige, goutte, 0.03);
		float tc = max(vie - 0.7, 0.0);
		vec2 cg = vec2(bord.x, bord.y + l_max + 0.05 + 5.0 * tc * tc);
		d = max(d, mix(-1.0, 0.05 - length((p - cg) * vec2(1.0, 0.8)), step(0.7, vie)));
		forme(rgb, d, couleur.rgb, trait * 0.8, px, clip);
	}

	// ===================== L'ÉPÉE =====================
	float t = clamp((q.x + 0.28) / 1.02, 0.0, 1.0);
	float demi = 0.085 * (1.0 - pow(t, 4.0));
	float lame = min(demi - abs(q.y), min(q.x + 0.28, 0.74 - q.x));
	float garde_d = min(0.2 - abs(q.y), 0.045 - abs(q.x + 0.32));
	float poignee = min(0.042 - abs(q.y), 0.16 - abs(q.x + 0.52));
	float pommeau = 0.06 - length(q - vec2(-0.7, 0.0));
	forme(rgb, max(max(garde_d, poignee), pommeau), garde.rgb, trait * 0.8, px, 1.0);
	// la lame : un côté sombre, un côté violet, et son fil mauve qui bat quand
	// le talisman est éveillé
	vec3 teinte = mix(sombre.rgb, couleur.rgb, step(0.0, -q.y));
	forme(rgb, lame, teinte, trait * 0.8, px, 1.0);
	float fil = min(lame, demi * 0.3 - abs(q.y + demi * 0.45));
	float bat = 0.75 + 0.25 * eveil * sin(temps * 3.0);
	rgb = mix(rgb, mix(couleur_vive.rgb, clair.rgb, 0.35), smoothstep(-px * 0.5, px * 0.5, fil) * bat);

	COLOR = vec4(rgb, a * opacite);
}
