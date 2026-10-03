shader_type canvas_item;
render_mode unshaded;
// BARRE DE FEU — LE SOCLE (2 oct. 2026) : le bloc de pierre au centre de la
// barre, comme le bloc des barres de feu de Mario, dans le style décor du pilon (SANS contour : le volume
// vient des tons). Un bloc chanfreiné, quatre rivets aux coins et, au milieu,
// l'emboîture de fer où tourne l'axe (la première boule de feu est posée
// dessus). La lumière reste en haut à gauche DANS LE MONDE même si on tourne
// la barre (calculée depuis MODEL_MATRIX).
// Repère : le centre du rectangle = l'axe. Posé par SCRIPT/INTERACTIBLE/barre_feu.gd.

uniform vec2 taille = vec2(64.0, 64.0);
uniform float demi_cote = 24.0;
uniform vec2 lumiere_monde = vec2(-0.6, -0.8);   // vers la lumière, dans le monde

uniform vec4 pierre : source_color = vec4(0.46, 0.52, 0.63, 1.0);
uniform vec4 pierre_ombre : source_color = vec4(0.29, 0.34, 0.44, 1.0);
uniform vec4 pierre_lumiere : source_color = vec4(0.61, 0.66, 0.76, 1.0);
uniform vec4 fer : source_color = vec4(0.26, 0.28, 0.33, 1.0);
uniform vec4 fer_lumiere : source_color = vec4(0.5, 0.53, 0.59, 1.0);

varying vec2 v_lumiere;


void vertex() {
	mat2 m = mat2(MODEL_MATRIX[0].xy, MODEL_MATRIX[1].xy);
	v_lumiere = normalize(inverse(m) * normalize(lumiere_monde));
}

// le hasard des nœuds du grain : ENTIER, exact
float alea_noeud(vec2 i) {
	uint x = uint(int(i.x) + 4096);
	uint y = uint(int(i.y) + 4096);
	uint n = x * 7919u + y * 104729u;
	n = (n << 13u) ^ n;
	n = n * (n * n * 15731u + 789221u) + 1376312589u;
	return float(n & 2147483647u) / 2147483647.0;
}

float bruit(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 s = f * f * (3.0 - 2.0 * f);
	return mix(mix(alea_noeud(i), alea_noeud(i + vec2(1.0, 0.0)), s.x),
			mix(alea_noeud(i + vec2(0.0, 1.0)), alea_noeud(i + vec2(1.0, 1.0)), s.x), s.y);
}

float couvre(float d, float px) {
	return clamp(0.5 - d / px, 0.0, 1.0);
}

vec4 sur(vec4 dst, vec4 src) {
	float a = src.a + dst.a * (1.0 - src.a);
	vec3 rgb = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 0.0001);
	return vec4(rgb, a);
}

float boite(vec2 p, vec2 c, vec2 b, float r) {
	vec2 d = abs(p - c) - b + r;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - r;
}

vec3 teinte(vec3 n, vec3 L3, vec3 base, vec3 clair, vec3 sombre) {
	float l = dot(normalize(n), L3);
	float l0 = L3.z;
	if (l < l0) {
		return mix(sombre, base, clamp(l / l0, 0.0, 1.0));
	}
	return mix(base, clair, clamp((l - l0) / max(1.0 - l0, 0.001), 0.0, 1.0));
}

void fragment() {
	vec2 pix = UV * taille;
	float px = max(fwidth(pix.x), 0.001);
	vec2 p = pix - taille * 0.5;
	vec3 L3 = normalize(vec3(v_lumiere, 0.9));
	vec4 c = vec4(pierre.rgb, 0.0);
	float h = demi_cote;

	// ===================== LE BLOC DE PIERRE =====================
	vec2 q = abs(p);
	float chanfrein = h * 0.22;
	float bx = 1.0 - clamp((h - q.x) / chanfrein, 0.0, 1.0);
	float by = 1.0 - clamp((h - q.y) / chanfrein, 0.0, 1.0);
	vec3 n = vec3(sign(p.x) * bx, sign(p.y) * by, 1.0);
	vec3 col = teinte(n, L3, pierre.rgb, pierre_lumiere.rgb, pierre_ombre.rgb);
	col *= 1.0 + 0.06 * dot(p / h, v_lumiere);
	col *= 1.0 - (bruit(p * 0.18 + vec2(31.0, 7.0)) - 0.5) * 0.09;
	c = sur(c, vec4(col, couvre(boite(p, vec2(0.0), vec2(h), 3.0), px)));

	// ===================== QUATRE RIVETS AUX COINS =====================
	for (int k = 0; k < 4; k++) {
		vec2 cr = vec2(k % 2 == 0 ? -1.0 : 1.0, k < 2 ? -1.0 : 1.0) * h * 0.74;
		float rr = h * 0.11;
		vec2 qr = (p - cr) / rr;
		vec3 nr = vec3(qr, sqrt(max(1.0 - dot(qr, qr), 0.0)));
		vec3 col_r = teinte(nr, L3, fer.rgb, fer_lumiere.rgb * 1.15, fer.rgb * 0.55);
		c = sur(c, vec4(col_r, couvre(length(p - cr) - rr, px)));
	}

	// ===================== L'EMBOÎTURE DE FER, où tourne l'axe =====================
	float r = length(p);
	float r_ext = h * 0.88;
	float r_int = h * 0.62;
	// l'anneau, bombé (un tore vu de face)
	float t = clamp((r - r_int) / (r_ext - r_int) * 2.0 - 1.0, -1.0, 1.0);
	vec2 radial = p / max(r, 0.001);
	vec3 na = vec3(radial * t, sqrt(max(1.0 - t * t, 0.0)));
	vec3 col_a = teinte(na, L3, fer.rgb, fer_lumiere.rgb, fer.rgb * 0.5);
	float d_anneau = max(r - r_ext, r_int - r);
	c = sur(c, vec4(col_a, couvre(d_anneau, px)));
	// le creux sombre au centre
	c = sur(c, vec4(fer.rgb * 0.35, couvre(r - r_int, px)));

	COLOR = c;
}
