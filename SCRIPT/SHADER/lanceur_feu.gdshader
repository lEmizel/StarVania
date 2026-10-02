shader_type canvas_item;
render_mode unshaded;
// LANCEUR DE BOULES DE FEU (2 oct. 2026, demande de Kaoru) — le DÉCOR du
// lanceur, SANS contour (comme le pilon et la roue : le volume vient des tons).
// Une plaque de pierre scellée dans le mur et ses deux boulons, un canon de fer
// cerclé de deux bandes, une bouche évasée. Il tire vers la DROITE de son
// repère ; la lumière, elle, reste en haut à gauche DANS LE MONDE même si on
// tourne ou retourne le lanceur (calculée depuis MODEL_MATRIX).
//   • `chaleur` (0 → 1) : la charge — l'intérieur de la bouche s'embrase, le
//     fer du bout rougit, un halo monte ; la boule elle-même est le visuel de
//     la boule de feu, posé devant la bouche par le script ;
//   • `tir` (1 → 0 après un tir) : le canon recule d'un coup et revient, une
//     bouffée de fumée sort de la bouche.
// Repère : `origine` = la surface du mur, au milieu du lanceur, dans le
// rectangle (px). Piloté par SCRIPT/INTERACTIBLE/lanceur_feu.gd.

uniform vec2 taille = vec2(160.0, 112.0);
uniform vec2 origine = vec2(10.0, 56.0);
uniform float chaleur : hint_range(0.0, 1.0) = 0.0;
uniform float tir : hint_range(0.0, 1.0) = 0.0;
uniform float temps = 0.0;
uniform vec2 lumiere_monde = vec2(-0.6, -0.8);   // vers la lumière, dans le monde

uniform vec4 pierre : source_color = vec4(0.46, 0.52, 0.63, 1.0);
uniform vec4 pierre_ombre : source_color = vec4(0.29, 0.34, 0.44, 1.0);
uniform vec4 pierre_lumiere : source_color = vec4(0.61, 0.66, 0.76, 1.0);
uniform vec4 fer : source_color = vec4(0.26, 0.28, 0.33, 1.0);
uniform vec4 fer_lumiere : source_color = vec4(0.5, 0.53, 0.59, 1.0);
uniform vec4 braise_rouge : source_color = vec4(0.75, 0.1, 0.03, 1.0);
uniform vec4 braise_orange : source_color = vec4(1.0, 0.45, 0.06, 1.0);
uniform vec4 braise_jaune : source_color = vec4(1.0, 0.86, 0.35, 1.0);
uniform vec4 couleur_fumee : source_color = vec4(0.52, 0.54, 0.59, 1.0);

varying vec2 v_lumiere;


void vertex() {
	// la direction de la lumière dans le repère du lanceur : elle reste fixe dans
	// le monde quand on tourne ou qu'on retourne le nœud
	mat2 m = mat2(MODEL_MATRIX[0].xy, MODEL_MATRIX[1].xy);
	v_lumiere = normalize(inverse(m) * normalize(lumiere_monde));
}

// le hasard des nœuds du grain : ENTIER, exact (le hasard flottant faisait des
// marches aux raccords, vu sur la faille de la pluie d'étoiles)
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

// la teinte d'une surface d'après sa normale (z vers nous) : une face tournée
// vers nous garde `base`, celle qui regarde la lumière va vers `clair`,
// l'autre vers `sombre`
vec3 teinte(vec3 n, vec3 L3, vec3 base, vec3 clair, vec3 sombre) {
	float l = dot(normalize(n), L3);
	float l0 = L3.z;
	if (l < l0) {
		return mix(sombre, base, clamp(l / l0, 0.0, 1.0));
	}
	return mix(base, clair, clamp((l - l0) / max(1.0 - l0, 0.001), 0.0, 1.0));
}

// une boîte à chanfreins : face plate, bords en biseau à 45°
vec3 normale_boite(vec2 p, vec2 c, vec2 b, float chanfrein) {
	vec2 q = p - c;
	vec2 dq = b - abs(q);
	float bx = 1.0 - clamp(dq.x / chanfrein, 0.0, 1.0);
	float by = 1.0 - clamp(dq.y / chanfrein, 0.0, 1.0);
	return vec3(sign(q.x) * bx, sign(q.y) * by, 1.0);
}

// un cylindre couché le long de x, de rayon r, vu de côté
vec3 normale_cylindre(float y, float r, float pente) {
	float s = clamp(y / max(r, 0.001), -1.0, 1.0);
	return vec3(pente, s, sqrt(max(1.0 - s * s, 0.0)));
}

// un rivet ou un boulon : une demi-sphère
vec4 rivet(vec2 p, vec2 c, float r, vec3 L3, float px) {
	vec2 q = (p - c) / r;
	vec3 n = vec3(q, sqrt(max(1.0 - dot(q, q), 0.0)));
	vec3 col = teinte(n, L3, fer.rgb, fer_lumiere.rgb * 1.15, fer.rgb * 0.55);
	col += fer_lumiere.rgb * pow(max(dot(normalize(n), L3), 0.0), 18.0) * 0.5;
	return vec4(col, couvre(length(p - c) - r, px));
}

void fragment() {
	vec2 pix = UV * taille;
	float px = max(fwidth(pix.x), 0.001);
	vec2 p = pix - origine;                          // x hors du mur, y vers le bas
	vec3 L3 = normalize(vec3(v_lumiere, 0.9));
	vec4 c = vec4(pierre.rgb, 0.0);
	// le recul du canon au tir : d'un coup, puis il revient
	float recul = 5.0 * smoothstep(0.72, 1.0, tir);
	vec2 pc = vec2(p.x + recul, p.y);                // le repère du canon (il recule)

	// ===================== LE HALO DE LA CHARGE (derrière tout) =====================
	float d_halo = length((pc - vec2(64.0, 0.0)) * vec2(0.85, 1.0));
	float halo = exp(-max(d_halo - 16.0, 0.0) / 13.0) * chaleur * 0.38;
	c = sur(c, vec4(mix(braise_orange.rgb, braise_rouge.rgb, smoothstep(16.0, 50.0, d_halo)), halo));

	// ===================== LA PLAQUE DE PIERRE, scellée dans le mur =====================
	vec2 cp = vec2(8.0, 0.0);
	vec2 bp = vec2(8.0, 40.0);
	float d_plaque = boite(p, cp, bp, 2.0);
	vec3 col_p = teinte(normale_boite(p, cp, bp, 3.5), L3, pierre.rgb, pierre_lumiere.rgb, pierre_ombre.rgb);
	col_p *= 1.0 + 0.06 * dot((p - cp) / bp, v_lumiere);
	col_p *= 1.0 - (bruit(p * 0.18) - 0.5) * 0.09;
	c = sur(c, vec4(col_p, couvre(d_plaque, px)));
	// ses deux boulons
	c = sur(c, rivet(p, vec2(8.0, -30.0), 3.4, L3, px));
	c = sur(c, rivet(p, vec2(8.0, 30.0), 3.4, L3, px));

	// ===================== LE CANON DE FER =====================
	float d_canon = boite(pc, vec2(33.0, 0.0), vec2(19.0, 17.0), 1.0);
	vec3 col_c = teinte(normale_cylindre(p.y, 17.0, 0.0), L3, fer.rgb, fer_lumiere.rgb, fer.rgb * 0.5);
	col_c += fer_lumiere.rgb * pow(max(dot(normalize(normale_cylindre(p.y, 17.0, 0.0)), L3), 0.0), 14.0) * 0.35;
	// il s'enfonce dans la plaque : plus sombre à sa racine
	col_c *= mix(0.72, 1.0, smoothstep(14.0, 24.0, pc.x));
	// le bout rougit pendant la charge
	col_c = mix(col_c, braise_rouge.rgb * 0.85, chaleur * smoothstep(34.0, 54.0, pc.x) * 0.45);
	c = sur(c, vec4(col_c, couvre(d_canon, px)));

	// ses deux bandes de fer, un rivet chacune
	for (int k = 0; k < 2; k++) {
		float xb = k == 0 ? 22.0 : 44.0;
		float d_bande = boite(pc, vec2(xb, 0.0), vec2(3.0, 19.5), 1.0);
		float bord = clamp((pc.x - xb) / 3.0, -1.0, 1.0);
		vec3 n_b = normale_cylindre(p.y, 19.5, smoothstep(0.55, 1.0, abs(bord)) * sign(bord) * 0.8);
		vec3 col_b = teinte(n_b, L3, fer.rgb * 1.05, fer_lumiere.rgb * 1.08, fer.rgb * 0.5);
		col_b = mix(col_b, braise_rouge.rgb * 0.8, chaleur * smoothstep(34.0, 54.0, pc.x) * 0.4);
		c = sur(c, vec4(col_b, couvre(d_bande, px)));
		c = sur(c, rivet(pc, vec2(xb, -10.0), 2.0, L3, px));
	}

	// ===================== LA BOUCHE ÉVASÉE =====================
	float flare = smoothstep(50.0, 62.0, pc.x);
	float r_bouche = mix(17.0, 24.0, flare);
	float d_bouche = max(abs(p.y) - r_bouche, max(50.0 - pc.x, pc.x - 62.0));
	vec3 n_bouche = normale_cylindre(p.y, r_bouche, -0.45 * (1.0 - abs(flare * 2.0 - 1.0)) - 0.1);
	vec3 col_bo = teinte(n_bouche, L3, fer.rgb, fer_lumiere.rgb, fer.rgb * 0.5);
	col_bo += fer_lumiere.rgb * pow(max(dot(normalize(n_bouche), L3), 0.0), 14.0) * 0.3;
	// la lèvre du bout, un peu plus claire
	col_bo = mix(col_bo, fer_lumiere.rgb * 0.95, smoothstep(59.5, 61.5, pc.x) * 0.35);
	col_bo = mix(col_bo, braise_rouge.rgb, chaleur * (0.35 + 0.25 * flare));
	c = sur(c, vec4(col_bo, couvre(d_bouche, px)));

	// l'ouverture, vue de biais : un fond noir qui s'embrase pendant la charge
	vec2 qo = vec2((pc.x - 62.0) / 5.0, p.y / 21.0);
	float lo = length(qo);
	float d_ouv = (lo - 1.0) * 5.0;
	float braise = chaleur * clamp(1.15 - lo, 0.0, 1.0);
	braise *= 0.85 + 0.15 * sin(temps * 23.0 + p.y * 0.4);
	vec3 col_o = fer.rgb * 0.22;
	col_o = mix(col_o, braise_rouge.rgb, smoothstep(0.0, 0.3, braise));
	col_o = mix(col_o, braise_orange.rgb, smoothstep(0.3, 0.65, braise));
	col_o = mix(col_o, braise_jaune.rgb, smoothstep(0.65, 1.0, braise));
	c = sur(c, vec4(col_o, couvre(d_ouv, px)));

	// ===================== LA FUMÉE DU TIR =====================
	float vie = 1.0 - tir;                           // 0 au tir → 1
	if (tir > 0.0) {
		float fumee = 0.0;
		float clair = 0.0;
		for (int k = 0; k < 4; k++) {
			float fk = float(k);
			vec2 cf = vec2(66.0 + vie * (18.0 + 10.0 * fk), (fk - 1.5) * 5.0 - vie * (6.0 + 7.0 * fk));
			float rf = 6.0 + vie * (10.0 + 3.0 * fk);
			float k2 = clamp(1.0 - length(p - cf) / rf, 0.0, 1.0);
			k2 = k2 * (2.0 - k2);                    // une bouffée pleine, au bord doux
			fumee = max(fumee, k2);
			clair = max(clair, k2 * clamp(-(p.y - cf.y) / rf, 0.0, 1.0));
		}
		vec3 col_f = mix(couleur_fumee.rgb * 0.85, couleur_fumee.rgb * 1.2, clair);
		float a_f = fumee * 0.7 * pow(tir, 1.2) * smoothstep(0.0, 0.08, vie);
		c = sur(c, vec4(col_f, a_f));
	}

	// rien ne touche le bord du rectangle
	float bord_r = min(min(pix.x, taille.x - pix.x), min(pix.y, taille.y - pix.y));
	c.a *= smoothstep(0.0, 3.0, bord_r);
	COLOR = c;
}
