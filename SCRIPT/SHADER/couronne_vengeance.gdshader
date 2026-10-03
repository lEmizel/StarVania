shader_type canvas_item;
render_mode unshaded;
// COURONNE DE VENGEANCE (v2, 1er oct. 2026) — talisman « Vengeance » : tant que
// la vengeance est chargée (un coup encaissé : tous les coups d'épée +50 %
// pendant 5 s), une COURONNE DE SANG flotte au-dessus du perso (l'épée ne
// se voit pas hors des coups).
//
// EN VOLUME (la première était un aplat vu de face) : un ANNEAU vu de trois
// quarts — on voit dans la couronne —, huit POINTES réparties tout autour (une
// grande, une petite, une grande…), et
// elle TOURNE lentement sur elle-même : les pointes passent devant, sur le
// côté (de profil, plus fines), derrière. Ce qui est derrière est sombre,
// ce qui est devant porte un DÉGRADÉ (la base rouge, la pointe vive) et un
// FIL rouge clair sur le bord de la bande. De temps en temps une GOUTTE perle
// sous la bande et tombe. Aucun blanc ; pas de liseré d'encre par défaut
// (comme sur les épines et le croissant).
//   • elle se POSE d'un coup sec : un peu grande puis à sa taille, ses pointes
//     jaillissent de la bande ;
//   • le TEMPS QUI RESTE : ses pointes rentrent une à une, bien réparties
//     autour de l'anneau — les petites d'abord, puis les grandes : huit au
//     départ, la bande nue à la fin ;
//   • elle BAT à chaque coup vengeur (`pouls`) : ses pointes s'allongent, elle
//     s'éclaire ;
//   • elle s'EFFACE quand le temps est écoulé : elle rapetisse et maigrit
//     (`eclat` : elle s'élargit en maigrissant — plus utilisé par le jeu).
// Repère : l'origine est le MILIEU du rectangle, en pixels, y vers le bas.

const int NB_POINTES = 8;

// --- fournis par couronne_vengeance.gd -------------------------------------
uniform vec2 taille = vec2(130.0, 120.0);
// 0 → 1 : la pose ; 1 → 0 : le temps qui reste
uniform float apparition : hint_range(0.0, 1.0) = 1.0;
uniform float restant : hint_range(0.0, 1.0) = 1.0;
// 0 → 1 : elle éclate ; 0 → 1 : elle s'efface
uniform float eclat : hint_range(0.0, 1.0) = 0.0;
uniform float efface : hint_range(0.0, 1.0) = 0.0;
// le temps qui passe (s) : elle tourne, ses gouttes tombent
uniform float temps = 0.0;
// 0 → 1 → 0 : un coup vengeur vient de porter
uniform float pouls : hint_range(0.0, 1.0) = 0.0;
// ----------------------------------------------------------------------------

// l'anneau : sa demi-largeur (px), et son demi-axe vertical — c'est lui qui
// fait la vue de trois quarts (0 = couronne vue de face, plate)
uniform float largeur : hint_range(10.0, 60.0) = 32.0;
uniform float profondeur : hint_range(0.0, 24.0) = 8.0;
// hauteur de la bande (px)
uniform float bande : hint_range(4.0, 20.0) = 9.0;
// les pointes : leur hauteur, leur demi-largeur vues de face, de combien leur
// sommet penche vers l'extérieur (px)
uniform float hauteur : hint_range(8.0, 50.0) = 27.0;
uniform float largeur_pointe : hint_range(2.0, 16.0) = 7.0;
uniform float evase : hint_range(0.0, 12.0) = 4.0;
// taille des petites pointes (une sur deux) par rapport aux grandes (1 = égales)
uniform float petites : hint_range(0.3, 1.0) = 0.68;
// vitesse à laquelle elle tourne sur elle-même (rad/s ; 0 = immobile)
uniform float tour : hint_range(-4.0, 4.0) = 0.7;
// 0 = des aplats, 1 = le dégradé complet
uniform float degrade : hint_range(0.0, 1.0) = 1.0;
// le fil rouge clair sur le haut de la bande (0 = sans)
uniform float fil : hint_range(0.0, 1.0) = 0.8;
// les gouttes qui perlent sous la bande (0 = aucune)
uniform float gouttes : hint_range(0.0, 1.0) = 1.0;
// épaisseur du liseré d'encre (px ; 0 = sans)
uniform float encre : hint_range(0.0, 6.0) = 0.0;
uniform vec4 couleur_vive : source_color = vec4(1.0, 0.17, 0.2, 1.0);
uniform vec4 couleur : source_color = vec4(0.76, 0.03, 0.11, 1.0);
uniform vec4 sombre : source_color = vec4(0.32, 0.01, 0.06, 1.0);
uniform vec4 couleur_fil : source_color = vec4(1.0, 0.5, 0.48, 1.0);
uniform vec4 couleur_encre : source_color = vec4(0.12, 0.0, 0.03, 1.0);

void par_dessus(inout vec3 rgb, inout float a, vec3 teinte, float force) {
	float total = force + a * (1.0 - force);
	rgb = (teinte * force + rgb * a * (1.0 - force)) / max(total, 0.0001);
	a = total;
}

// une pièce pleine, cernée d'encre si `e` > 0
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

void fragment() {
	vec2 p = (UV - 0.5) * taille;
	float aa = max(length(vec2(dFdx(p.x), dFdy(p.x))), 0.35) * 1.2;

	// la pose : un coup de tampon ; l'éclat : elle s'élargit ; l'effacement :
	// elle rapetisse — et dans les deux derniers cas, elle maigrit
	float ap = clamp(apparition, 0.0, 1.0);
	float pose = 1.0 - pow(1.0 - ap, 3.0);
	float ec = clamp(eclat, 0.0, 1.0);
	float ef = clamp(efface, 0.0, 1.0);
	float echelle = mix(1.35, 1.0, pose) * mix(1.0, 1.7, 1.0 - (1.0 - ec) * (1.0 - ec)) * mix(1.0, 0.6, ef);
	float maigrit = (1.0 - ec) * (1.0 - ef);
	vec2 q = p / echelle;
	q.y -= 2.0;                                   // l'anneau juste sous le milieu : les pointes ont la place
	float pl = clamp(pouls, 0.0, 1.0);
	float e = encre * maigrit;
	// les pointes jaillissent de la bande à la pose (elles dépassent, puis se posent)
	float ai = ap - 1.0;
	float ressort = 1.0 + 2.7 * ai * ai * ai + 1.7 * ai * ai;

	// L'ANNEAU à cet x : sa profondeur (0 sur les côtés, 1 au milieu) — devant
	// il est plus BAS à l'écran, derrière plus haut : on voit dedans
	float b2 = bande * 0.5 * maigrit;
	float xr = clamp(q.x / largeur, -1.0, 1.0);
	float zf = sqrt(max(1.0 - xr * xr, 0.0));
	float bord = largeur - abs(q.x);
	float d_bande_dos = min(b2 - abs(q.y + profondeur * zf), bord);
	float d_bande_face = min(b2 - abs(q.y - profondeur * zf), bord);

	// LES POINTES : huit autour de l'anneau, qui tournent avec lui. Celles de
	// derrière (z < 0) et celles de devant se dessinent à part.
	float d_dos = -1000.0;
	float d_face = -1000.0;
	float g_dos = 0.0;
	float g_face = 0.0;
	float z_face = 1.0;
	for (int k = 0; k < NB_POINTES; k++) {
		float phi = TAU * float(k) / float(NB_POINTES) + temps * tour;
		float z = cos(phi);
		float sx = sin(phi);
		// le temps qui reste : elles rentrent une à une, dans un ordre qui les
		// répartit autour de l'anneau (0, 4, 2, 6, 1, 5, 3, 7)
		float ordre = float(((k & 1) << 2) | (k & 2) | ((k & 4) >> 2));
		float tient = clamp((restant * float(NB_POINTES) - ordre) / 0.6, 0.0, 1.0);
		// une grande, une petite : les petites ont les ordres 4 à 7, elles
		// rentrent donc les premières
		float rang = ((k & 1) == 0) ? 1.0 : petites;
		float h = hauteur * rang * ressort * tient * (1.0 + 0.18 * pl) * mix(0.9, 1.0, 0.5 + 0.5 * z);
		// de profil (sur les côtés de l'anneau) une pointe est plus fine
		float w = largeur_pointe * mix(0.8, 1.0, rang) * (0.35 + 0.65 * abs(z)) * maigrit;
		if (h < 0.5 || w < 0.3) {
			continue;
		}
		// son pied : sur le haut de la bande, là où elle est sur l'anneau
		vec2 qp = q - vec2(largeur * sx, profondeur * z - b2 + 1.0);
		float g = clamp(-qp.y / h, 0.0, 1.0);            // 0 au pied, 1 au sommet
		qp.x -= evase * sx * g;                            // évasée vers l'extérieur
		float dp = -triangle(vec2(qp.x, qp.y + h), vec2(w, h));
		if (z < 0.0) {
			if (dp > d_dos) {
				d_dos = dp;
				g_dos = g;
			}
		} else if (dp > d_face) {
			d_face = dp;
			g_face = g;
			z_face = z;
		}
	}

	vec3 rgb = couleur.rgb;
	float a = 0.0;

	// 1. DERRIÈRE : l'intérieur de la bande, puis ses pointes — sombres
	vec3 c_dos = mix(sombre.rgb, couleur.rgb, 0.3 * g_dos * degrade);
	piece(rgb, a, d_bande_dos, sombre.rgb * 0.85, e, aa);
	piece(rgb, a, d_dos, c_dos, e, aa);

	// 2. DEVANT : les pointes, dégradées du pied (rouge) au sommet (vif) ; une
	// pointe qui arrive par le côté sort de l'ombre
	vec3 c_face = mix(couleur.rgb, couleur_vive.rgb, pow(g_face, 1.3) * degrade);
	c_face = mix(c_dos, c_face, smoothstep(0.0, 0.35, z_face));
	c_face = mix(c_face, couleur_vive.rgb, 0.7 * pl);
	piece(rgb, a, d_face, c_face, e, aa);

	// 3. LES GOUTTES : elles perlent sous la bande, devant, et tombent en
	// maigrissant
	if (gouttes > 0.001 && maigrit > 0.5) {
		for (int i = 0; i < 2; i++) {
			float fi = float(i);
			float cycle = temps / 1.5 + fi * 0.5;
			float n = floor(cycle);
			float u = fract(cycle);
			float xd = largeur * 0.8 * (alea(n * 7.3 + fi * 3.1) * 2.0 - 1.0);
			float zd = sqrt(max(1.0 - (xd / largeur) * (xd / largeur), 0.0));
			float chute = smoothstep(0.4, 1.0, u);
			float rg = 2.6 * smoothstep(0.0, 0.35, u) * (1.0 - chute * chute) * gouttes;
			vec2 gq = q - vec2(xd, profondeur * zd + b2 + 0.5 + 24.0 * chute * chute);
			gq.y /= (1.0 + 1.2 * chute);                    // elle s'étire en tombant
			par_dessus(rgb, a, mix(couleur.rgb, sombre.rgb, 0.4),
				smoothstep(0.0, aa, rg - length(gq)) * step(0.3, rg));
		}
	}

	// 4. DEVANT : la bande, dégradée de haut (rouge) en bas (sombre), et son
	// fil clair le long du bord du haut
	float haut_bande = profondeur * zf - b2;
	float gb = clamp((q.y - haut_bande) / max(2.0 * b2, 1.0), 0.0, 1.0);
	vec3 c_bande = mix(couleur.rgb, mix(couleur.rgb, sombre.rgb, 0.75), gb * degrade);
	c_bande = mix(c_bande, couleur_vive.rgb, 0.6 * pl);
	piece(rgb, a, d_bande_face, c_bande, e, aa);
	float d_fil = min(1.1 - abs(q.y - haut_bande - 1.7), bord - 3.0);
	par_dessus(rgb, a, couleur_fil.rgb, smoothstep(0.0, aa, d_fil) * fil * step(3.0, b2 * 2.0));

	// elle apparaît en un éclair (pas de fondu lent)
	a *= smoothstep(0.0, 0.25, apparition);
	COLOR = vec4(rgb, a);
}
