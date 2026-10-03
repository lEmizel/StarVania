shader_type canvas_item;
render_mode unshaded;
// DESSIN DU TALISMAN « CŒUR NOIR » (menu START, 1er oct. 2026) — provisoire, en
// attendant le dessin définitif.
// emplacement_talisman.gd le pose dans le rond et lui fournit `opacite`,
// `eveil` et `temps`.
// TOUT LE ROND est au dessin : un disque de nuit, plus chaud au milieu, cerné
// d'un trait d'encre ; un CŒUR NOIR liseré de sang, fêlé, et derrière lui l'ONDE
// noire qu'il lâche en se brisant, avec quelques éclats. Aplats et encre, un
// reflet rouge sombre (pas de blanc). Pointé ou porté (`eveil`), il bat et
// l'onde part de lui, encore et encore.
// À dessiner dans un CARRÉ : le disque le remplit.

// --- fournis par emplacement_talisman.gd (les mêmes pour tout dessin de talisman) ---
uniform float opacite : hint_range(0.0, 1.0) = 1.0;
uniform float eveil : hint_range(0.0, 1.0) = 0.0;
uniform float temps = 0.0;
// ----------------------------------------------------------------------------

uniform vec4 encre_color : source_color = vec4(0.1, 0.02, 0.04, 1.0);
uniform vec4 fond_color : source_color = vec4(0.06, 0.02, 0.04, 1.0);
uniform vec4 fond_centre : source_color = vec4(0.24, 0.04, 0.07, 1.0);
uniform float trait : hint_range(0.0, 0.1) = 0.045;
uniform vec4 noir : source_color = vec4(0.07, 0.015, 0.035, 1.0);
uniform vec4 sang : source_color = vec4(0.82, 0.05, 0.12, 1.0);
uniform vec4 reflet : source_color = vec4(0.36, 0.06, 0.1, 1.0);

float disque(float d, float r, float px) {
	return smoothstep(r + px * 0.5, r - px * 0.5, d);
}

// union adoucie de deux formes positives dedans
float smax(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (a - b) / k, 0.0, 1.0);
	return mix(b, a, h) + k * h * (1.0 - h);
}

// un cœur centré en `c`, de taille `s`, positif dedans — la pointe reste dans
// la largeur des lobes, soudée en douceur (sinon ses coins dépassaient en deux
// encoches sur les flancs, que le liseré rouge faisait ressortir)
float coeur(vec2 p, vec2 c, float s) {
	vec2 q = (p - c) / s;
	float lobe_g = 0.36 - length(q - vec2(-0.28, -0.14));
	float lobe_d = 0.36 - length(q - vec2(0.28, -0.14));
	float pointe = min(q.y + 0.02, (0.72 - q.y) * 0.8 - abs(q.x));
	return smax(smax(lobe_g, lobe_d, 0.06), pointe, 0.12) * s;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float px = fwidth(UV.x) * 2.0;

	// ===================== LE DISQUE =====================
	vec3 rgb = encre_color.rgb;
	float a = disque(r, 1.0, px);
	rgb = mix(rgb, mix(fond_centre.rgb, fond_color.rgb, smoothstep(0.0, 0.95, r)), disque(r, 1.0 - trait, px));
	float dedans = (1.0 - trait * 1.6) - r;

	// ===================== L'ONDE (derrière) =====================
	// au repos : un anneau posé ; pointé : il part du cœur, encore et encore
	float course = mix(0.62, 0.3 + 0.62 * fract(temps * 0.55), eveil);
	float anneau = abs(r - course) - 0.045 * (1.0 - 0.5 * eveil * fract(temps * 0.55));
	float vie = 1.0 - eveil * smoothstep(0.6, 1.0, fract(temps * 0.55));
	rgb = mix(rgb, noir.rgb, smoothstep(px, -px, anneau) * vie * step(0.0, dedans));
	rgb = mix(rgb, sang.rgb, smoothstep(px, -px * 0.5, abs(r - course - 0.045) - 0.012) * vie * step(0.0, dedans));

	// ===================== LES ÉCLATS =====================
	for (int i = 0; i < 6; i++) {
		float fi = float(i);
		float ang = fi / 6.0 * 6.2831853 + 0.4;
		vec2 dir = vec2(cos(ang), sin(ang));
		vec2 c = dir * (0.72 + 0.05 * sin(temps * 2.0 + fi));
		vec2 q = p - c;
		float rot = ang + 1.2;
		q = vec2(cos(rot) * q.x + sin(rot) * q.y, -sin(rot) * q.x + cos(rot) * q.y);
		float e = min(0.05 - abs(q.x) - q.y * 0.4, min(q.y + 0.07, 0.07 - q.y));
		rgb = mix(rgb, sang.rgb, smoothstep(-px, px, e + 0.016) * step(0.0, dedans));
		rgb = mix(rgb, noir.rgb, smoothstep(-px, px, e) * step(0.0, dedans));
	}

	// ===================== LE CŒUR NOIR =====================
	float bat = 1.0 + 0.06 * pow(0.5 + 0.5 * sin(temps * 5.5), 6.0) * (0.3 + 0.7 * eveil);
	vec2 cc = vec2(0.0, -0.04);
	float d = coeur(p, cc, 0.62 * bat);
	rgb = mix(rgb, sang.rgb, smoothstep(-px * 0.5, px * 0.5, d + trait * 1.2));
	rgb = mix(rgb, noir.rgb, smoothstep(-px * 0.5, px * 0.5, d));
	// le reflet, rouge sombre
	float rf = min(d - 0.04, 0.09 - length((p - cc - vec2(-0.17, -0.13)) * vec2(1.0, 1.4)));
	rgb = mix(rgb, reflet.rgb, smoothstep(-px * 0.5, px * 0.5, rf));
	// la fêlure : un zigzag de sang
	float y = p.y - cc.y;
	float zig = abs(p.x - 0.04 - 0.07 * (fract((y + 0.5) * 3.6) * 2.0 - 1.0) * sign(fract((y + 0.5) * 1.8) - 0.5)) - 0.016;
	rgb = mix(rgb, sang.rgb, smoothstep(px, 0.0, zig) * step(0.03, d));

	COLOR = vec4(rgb, a * opacite);
}
