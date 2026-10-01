shader_type canvas_item;
render_mode unshaded;
// COURONNE DU DÉFI (1er oct. 2026) — talisman « Couronne du défi » (idée de
// Kaoru : « un talisman de défi, on n'a plus qu'un cœur, il te donne une
// magnifique couronne en or qui tourne au-dessus de la tête »).
// La forme de la couronne de la Vengeance (couronne_vengeance.gdshader, non
// touchée) faite ROYALE :
//   • un ANNEAU d'or vu de trois quarts qui TOURNE lentement : bande en
//     dégradé (or vif en haut, or sombre en bas), un fil clair le long du bord ;
//   • huit POINTES — de grands fleurons coiffés d'une PERLE, de petites pointes
//     entre eux — sombres derrière, dorées devant ;
//   • des RUBIS sertis dans la bande, au pied des grands fleurons, qui passent
//     devant puis derrière avec la rotation ;
//   • un REFLET qui balaie la couronne de temps en temps, et de petites
//     ÉTINCELLES qui scintillent sur l'or ;
//   • elle se POSE d'un coup sec (un peu grande puis à sa taille), et
//     s'EFFACE en rapetissant quand on l'ôte.
// Un fin trait sombre la détache des décors clairs (`encre`, 0 = sans).
// Repère : l'origine est le MILIEU du rectangle, en pixels, y vers le bas.

const int NB_POINTES = 8;

// --- fournis par couronne_defi.gd -------------------------------------------
uniform vec2 taille = vec2(150.0, 130.0);
// 0 → 1 : la pose ; 0 → 1 : elle s'efface
uniform float apparition : hint_range(0.0, 1.0) = 1.0;
uniform float efface : hint_range(0.0, 1.0) = 0.0;
// le temps qui passe (s) : elle tourne, le reflet passe, les étincelles
uniform float temps = 0.0;
// ----------------------------------------------------------------------------

// l'anneau : sa demi-largeur, son demi-axe vertical (la vue de trois quarts),
// la hauteur de sa bande (px)
uniform float largeur : hint_range(10.0, 60.0) = 36.0;
uniform float profondeur : hint_range(0.0, 24.0) = 9.0;
uniform float bande : hint_range(4.0, 24.0) = 11.0;
// les fleurons : leur hauteur, leur demi-largeur vue de face, leur évasement
uniform float hauteur : hint_range(8.0, 60.0) = 30.0;
uniform float largeur_pointe : hint_range(2.0, 16.0) = 7.5;
uniform float evase : hint_range(0.0, 12.0) = 4.5;
// la taille des petites pointes par rapport aux grandes
uniform float petites : hint_range(0.3, 1.0) = 0.58;
// sa vitesse de rotation (rad/s)
uniform float tour : hint_range(-4.0, 4.0) = 0.6;
// la perle au bout des fleurons, les rubis de la bande (rayons, px)
uniform float perle : hint_range(0.0, 8.0) = 3.6;
uniform float rubis : hint_range(0.0, 8.0) = 3.4;
// le reflet qui balaie la couronne (0 = aucun) ; les étincelles (0 = aucune)
uniform float reflet : hint_range(0.0, 1.0) = 0.85;
uniform float etincelles : hint_range(0.0, 1.0) = 1.0;
uniform float fil : hint_range(0.0, 1.0) = 0.9;
uniform float encre : hint_range(0.0, 6.0) = 1.2;
uniform vec4 or_vif : source_color = vec4(1.0, 0.9, 0.42, 1.0);
uniform vec4 or_couleur : source_color = vec4(0.93, 0.66, 0.14, 1.0);
uniform vec4 or_sombre : source_color = vec4(0.42, 0.24, 0.04, 1.0);
uniform vec4 couleur_fil : source_color = vec4(1.0, 0.96, 0.74, 1.0);
uniform vec4 couleur_rubis : source_color = vec4(0.8, 0.04, 0.14, 1.0);
uniform vec4 rubis_vif : source_color = vec4(1.0, 0.36, 0.42, 1.0);
uniform vec4 couleur_perle : source_color = vec4(0.98, 0.92, 0.76, 1.0);
uniform vec4 couleur_encre : source_color = vec4(0.18, 0.09, 0.02, 1.0);

void par_dessus(inout vec3 rgb, inout float a, vec3 teinte, float force) {
	float total = force + a * (1.0 - force);
	rgb = (teinte * force + rgb * a * (1.0 - force)) / max(total, 0.0001);
	a = total;
}

// une pièce pleine, cernée d'encre si `e` > 0 (`d` positive dedans)
void piece(inout vec3 rgb, inout float a, float d, vec3 teinte, float e, float aa) {
	par_dessus(rgb, a, couleur_encre.rgb, smoothstep(0.0, aa, d + e) * step(0.01, e));
	par_dessus(rgb, a, teinte, smoothstep(0.0, aa, d));
}

float alea(float n) {
	return fract(sin(n * 12.9898 + 4.1414) * 43758.5453);
}

// triangle isocèle : sommet à l'origine, base à y = q.y, demi-largeur q.x
// (négatif dedans)
float triangle(vec2 p, vec2 q) {
	p.x = abs(p.x);
	vec2 a = p - q * clamp(dot(p, q) / dot(q, q), 0.0, 1.0);
	vec2 b = p - q * vec2(clamp(p.x / q.x, 0.0, 1.0), 1.0);
	float s = -sign(q.y);
	vec2 d = min(vec2(dot(a, a), s * (p.x * q.y - p.y * q.x)), vec2(dot(b, b), s * (p.y - q.y)));
	return -sqrt(d.x) * sign(d.y);
}

// le reflet qui balaie : une bande claire en biais qui traverse la couronne
float balayage(vec2 q) {
	float cycle = fract(temps * 0.32);
	float x = mix(-1.6, 1.6, cycle) * largeur;
	return smoothstep(7.0, 0.0, abs(q.x + q.y * 0.45 - x)) * reflet;
}

void fragment() {
	vec2 p = (UV - 0.5) * taille;
	float ap = clamp(apparition, 0.0, 1.0);
	float pose = 1.0 - pow(1.0 - ap, 3.0);
	float ef = clamp(efface, 0.0, 1.0);
	float echelle = mix(1.35, 1.0, pose) * mix(1.0, 0.6, ef);
	float maigrit = 1.0 - ef;
	vec2 q = p / echelle;
	q.y -= 6.0;                                     // l'anneau sous le milieu : les fleurons ont la place
	float aa = max(length(vec2(dFdx(q.x), dFdy(q.x))), 0.35) * 1.2;
	float e = encre * maigrit;
	float ai = ap - 1.0;
	float ressort = 1.0 + 2.7 * ai * ai * ai + 1.7 * ai * ai;

	// L'ANNEAU à cet x : devant il est plus bas à l'écran, derrière plus haut
	float b2 = bande * 0.5 * maigrit;
	float xr = clamp(q.x / largeur, -1.0, 1.0);
	float zf = sqrt(max(1.0 - xr * xr, 0.0));
	float bord = largeur - abs(q.x);
	float d_bande_dos = min(b2 - abs(q.y + profondeur * zf), bord);
	float d_bande_face = min(b2 - abs(q.y - profondeur * zf), bord);

	// LES FLEURONS (et les perles), qui tournent avec l'anneau
	float d_dos = -1000.0;
	float d_face = -1000.0;
	float g_dos = 0.0;
	float g_face = 0.0;
	float z_face = 1.0;
	float perle_dos = -1000.0;
	float perle_face = -1000.0;
	for (int k = 0; k < NB_POINTES; k++) {
		float phi = TAU * float(k) / float(NB_POINTES) + temps * tour;
		float z = cos(phi);
		float sx = sin(phi);
		bool grand = (k & 1) == 0;
		float rang = grand ? 1.0 : petites;
		float h = hauteur * rang * ressort * mix(0.9, 1.0, 0.5 + 0.5 * z);
		float w = largeur_pointe * mix(0.8, 1.0, rang) * (0.35 + 0.65 * abs(z)) * maigrit;
		if (h < 0.5 || w < 0.3) {
			continue;
		}
		vec2 qp = q - vec2(largeur * sx, profondeur * z - b2 + 1.0);
		float g = clamp(-qp.y / h, 0.0, 1.0);
		qp.x -= evase * sx * g;
		float dp = -triangle(vec2(qp.x, qp.y + h), vec2(w, h));
		// la perle, au bout des grands fleurons
		float dperle = -1000.0;
		if (grand && perle > 0.01) {
			vec2 bout = vec2(largeur * sx + evase * sx, profondeur * z - b2 + 1.0 - h);
			dperle = perle * (0.75 + 0.25 * abs(z)) * maigrit - length(q - bout);
		}
		if (z < 0.0) {
			if (dp > d_dos) {
				d_dos = dp;
				g_dos = g;
			}
			perle_dos = max(perle_dos, dperle);
		} else {
			if (dp > d_face) {
				d_face = dp;
				g_face = g;
				z_face = z;
			}
			perle_face = max(perle_face, dperle);
		}
	}

	vec3 rgb = or_couleur.rgb;
	float a = 0.0;
	float bal = balayage(q);

	// 1. DERRIÈRE : l'intérieur de la bande, les fleurons et perles de derrière — sombres
	piece(rgb, a, d_bande_dos, or_sombre.rgb * 0.8, e, aa);
	piece(rgb, a, d_dos, mix(or_sombre.rgb, or_couleur.rgb, 0.35 * g_dos), e, aa);
	piece(rgb, a, perle_dos, mix(or_sombre.rgb, couleur_perle.rgb, 0.4), e * 0.7, aa);

	// 2. DEVANT : les fleurons, dégradés du pied (or) à la pointe (or vif) ; un
	// fleuron qui arrive par le côté sort de l'ombre
	vec3 c_face = mix(or_couleur.rgb, or_vif.rgb, pow(g_face, 1.2));
	c_face = mix(mix(or_sombre.rgb, or_couleur.rgb, 0.35 * g_face), c_face, smoothstep(0.0, 0.35, z_face));
	c_face = mix(c_face, couleur_fil.rgb, bal);
	piece(rgb, a, d_face, c_face, e, aa);
	vec3 c_perle = mix(couleur_perle.rgb, or_vif.rgb, 0.15);
	piece(rgb, a, perle_face, c_perle, e * 0.7, aa);

	// 3. DEVANT : la bande, dégradée de haut (or vif) en bas (or sombre), son fil
	// clair, et ses rubis
	float haut_bande = profondeur * zf - b2;
	float gb = clamp((q.y - haut_bande) / max(2.0 * b2, 1.0), 0.0, 1.0);
	vec3 c_bande = mix(or_vif.rgb, mix(or_couleur.rgb, or_sombre.rgb, 0.7), gb);
	c_bande = mix(c_bande, couleur_fil.rgb, bal * 0.8);
	piece(rgb, a, d_bande_face, c_bande, e, aa);
	float d_fil = min(1.1 - abs(q.y - haut_bande - 1.8), bord - 3.0);
	par_dessus(rgb, a, couleur_fil.rgb, smoothstep(0.0, aa, d_fil) * fil * step(3.0, b2 * 2.0));
	if (rubis > 0.01 && d_bande_face > -1.0) {
		for (int k = 0; k < NB_POINTES; k += 2) {
			float phi = TAU * float(k) / float(NB_POINTES) + temps * tour;
			float z = cos(phi);
			if (z <= 0.05) {
				continue;
			}
			vec2 c = vec2(largeur * sin(phi), profondeur * z);
			vec2 dq = (q - c) / vec2(0.35 + 0.65 * z, 1.0);
			float d_rubis = rubis * maigrit - length(dq);
			// une pierre taillée : sombre dessous, vive dessus, un point clair
			vec3 c_r = mix(couleur_rubis.rgb, rubis_vif.rgb, smoothstep(1.5, -2.5, dq.y));
			piece(rgb, a, d_rubis, c_r, e * 0.6, aa);
			par_dessus(rgb, a, rubis_vif.rgb, smoothstep(0.0, aa, rubis * 0.32 - length(dq - vec2(-0.9, -1.0))) * step(0.0, d_rubis));
		}
	}

	// 4. LES ÉTINCELLES : de petites croix claires qui scintillent sur l'or
	if (etincelles > 0.001 && a > 0.5) {
		for (int i = 0; i < 3; i++) {
			float fi = float(i);
			float cycle = temps * 0.9 + fi * 0.37;
			float n = floor(cycle);
			float u = fract(cycle);
			vec2 c = vec2((alea(n * 3.7 + fi) * 2.0 - 1.0) * largeur * 0.85,
					profondeur * 0.6 - b2 - alea(n * 5.3 + fi * 2.0) * hauteur * 0.8);
			float eclat = sin(u * PI) * etincelles;
			vec2 dq = abs(q - c);
			float croix = max(smoothstep(1.2, 0.0, dq.x) * smoothstep(5.5 * eclat, 0.0, dq.y),
					smoothstep(1.2, 0.0, dq.y) * smoothstep(5.5 * eclat, 0.0, dq.x));
			rgb = mix(rgb, couleur_fil.rgb, croix * eclat);
		}
	}

	// elle apparaît en un éclair, s'efface en rapetissant
	a *= smoothstep(0.0, 0.25, apparition) * (1.0 - ef * ef);
	COLOR = vec4(rgb, a);
}
