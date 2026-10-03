shader_type canvas_item;
render_mode unshaded;
// ENTRAVE DE SANG (v2, 1er oct. 2026) — talisman « Entraves » : un ennemi
// entravé (ralenti) est pris dans un ANNEAU DE SANG à mi-hauteur de son corps,
// au sol comme en vol.
// v1 : un anneau plat cerné d'encre, des épines vers l'intérieur, des filets
// jusqu'au sol → remplacé par un anneau semblable à la couronne, avec un
// décompte. C'est donc LA COURONNE DE LA VENGEANCE
// (couronne_vengeance.gdshader, recopiée ici : la couronne n'est pas touchée)
// passée autour de l'ennemi :
//   • un ANNEAU vu de trois quarts qui TOURNE lentement, huit POINTES tout
//     autour (une grande, une petite…) — vers le BAS par défaut (`sens` -1 :
//     une entrave qui le tire au sol ; +1 : vers le haut, comme la couronne) —,
//     un DÉGRADÉ, un FIL rouge clair sur la bande, des GOUTTES qui tombent ;
//   • le DÉCOMPTE : ses pointes rentrent une à une avec le temps qui reste
//     (`restant`), les petites d'abord ;
//   • il se POSE d'un coup sec ; un nouveau coup qui entrave le fait BATTRE
//     (`pouls`) et ses pointes ressortent (le temps repart) ;
//   • libéré, il s'EFFACE en se desserrant.
// Deux rectangles : `Derriere` (sous le sprite de l'ennemi) dessine ce qui est
// derrière lui (le fond de la bande, les pointes de derrière), `Devant`
// (par-dessus) le reste — l'anneau l'entoure vraiment.
// Repère : des pixels, l'origine au centre de l'anneau ; ses mesures sont
// celles de la couronne, multipliées par `echelle` (posée selon la largeur de
// l'ennemi).

const int NB_POINTES = 8;

// --- fournis par entrave_sang.gd --------------------------------------------
uniform vec2 taille = vec2(110.0, 160.0);
uniform vec2 ancre = vec2(55.0, 80.0);
// 0 : le rectangle de derrière ; 1 : celui de devant
uniform float couche : hint_range(0.0, 1.0) = 1.0;
// la taille de l'anneau par rapport à la couronne (1 = la couronne)
uniform float echelle = 1.0;
// 0 → 1 : la pose ; 1 → 0 : le temps qui reste ; 0 → 1 : il s'efface
uniform float apparition : hint_range(0.0, 1.0) = 1.0;
uniform float restant : hint_range(0.0, 1.0) = 1.0;
uniform float efface : hint_range(0.0, 1.0) = 0.0;
// le temps qui passe (s) : il tourne, ses gouttes tombent
uniform float temps = 0.0;
// 0 → 1 → 0 : un coup vient de l'entraver de nouveau
uniform float pouls : hint_range(0.0, 1.0) = 0.0;
// ----------------------------------------------------------------------------

// les pointes vers le bas (-1 : une entrave qui le tire au sol) ou vers le haut (+1)
uniform float sens : hint_range(-1.0, 1.0) = -1.0;
// les mesures de la couronne (à l'échelle 1)
uniform float largeur : hint_range(10.0, 60.0) = 32.0;
uniform float profondeur : hint_range(0.0, 24.0) = 8.0;
uniform float bande : hint_range(4.0, 20.0) = 9.0;
uniform float hauteur : hint_range(8.0, 50.0) = 22.0;
uniform float largeur_pointe : hint_range(2.0, 16.0) = 6.0;
uniform float evase : hint_range(0.0, 12.0) = 3.0;
uniform float petites : hint_range(0.3, 1.0) = 0.68;
uniform float tour : hint_range(-4.0, 4.0) = 0.9;
uniform float degrade : hint_range(0.0, 1.0) = 1.0;
uniform float fil : hint_range(0.0, 1.0) = 0.8;
uniform float gouttes : hint_range(0.0, 1.0) = 1.0;
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
	vec2 p = UV * taille - ancre;
	float devant = step(0.5, couche);

	// la pose : un coup de tampon ; l'effacement : il se desserre en maigrissant
	float ap = clamp(apparition, 0.0, 1.0);
	float pose = 1.0 - pow(1.0 - ap, 3.0);
	float ef = clamp(efface, 0.0, 1.0);
	float ech = max(echelle, 0.05) * mix(1.35, 1.0, pose) * mix(1.0, 1.25, ef);
	float maigrit = 1.0 - ef;
	vec2 q = p / ech;
	float aa = max(length(vec2(dFdx(q.x), dFdy(q.x))), 0.35) * 1.2;
	float pl = clamp(pouls, 0.0, 1.0);
	float e = encre * maigrit;
	float s = sens < 0.0 ? -1.0 : 1.0;
	// les pointes jaillissent de la bande à la pose (elles dépassent, puis se posent)
	float ai = ap - 1.0;
	float ressort = 1.0 + 2.7 * ai * ai * ai + 1.7 * ai * ai;

	// L'ANNEAU à cet x : sa profondeur (0 sur les côtés, 1 au milieu) — devant
	// il est plus BAS à l'écran, derrière plus haut
	float b2 = bande * 0.5 * maigrit;
	float xr = clamp(q.x / largeur, -1.0, 1.0);
	float zf = sqrt(max(1.0 - xr * xr, 0.0));
	float bord = largeur - abs(q.x);
	float d_bande_dos = min(b2 - abs(q.y + profondeur * zf), bord);
	float d_bande_face = min(b2 - abs(q.y - profondeur * zf), bord);

	// LES POINTES : huit autour de l'anneau, qui tournent avec lui
	float d_dos = -1000.0;
	float d_face = -1000.0;
	float g_dos = 0.0;
	float g_face = 0.0;
	float z_face = 1.0;
	for (int k = 0; k < NB_POINTES; k++) {
		float phi = TAU * float(k) / float(NB_POINTES) + temps * tour;
		float z = cos(phi);
		float sx = sin(phi);
		// LE DÉCOMPTE : elles rentrent une à une, réparties autour de l'anneau
		// (0, 4, 2, 6, 1, 5, 3, 7) — les petites d'abord
		float ordre = float(((k & 1) << 2) | (k & 2) | ((k & 4) >> 2));
		float tient = clamp((restant * float(NB_POINTES) - ordre) / 0.6, 0.0, 1.0);
		float rang = ((k & 1) == 0) ? 1.0 : petites;
		float h = hauteur * rang * ressort * tient * (1.0 + 0.25 * pl) * mix(0.9, 1.0, 0.5 + 0.5 * z);
		float w = largeur_pointe * mix(0.8, 1.0, rang) * (0.35 + 0.65 * abs(z)) * maigrit;
		if (h < 0.5 || w < 0.3) {
			continue;
		}
		// son pied : sur le bord de la bande (en bas si elles pointent vers le
		// bas), là où elle est sur l'anneau
		vec2 qp = q - vec2(largeur * sx, profondeur * z - s * (b2 - 1.0));
		float g = clamp(-s * qp.y / h, 0.0, 1.0);          // 0 au pied, 1 au sommet
		qp.x -= evase * sx * g;                              // évasée vers l'extérieur
		float dp = -triangle(vec2(qp.x, h + s * qp.y), vec2(w, h));
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

	if (devant < 0.5) {
		// DERRIÈRE L'ENNEMI : le fond de la bande, puis ses pointes — sombres
		vec3 c_dos = mix(sombre.rgb, couleur.rgb, 0.3 * g_dos * degrade);
		piece(rgb, a, d_bande_dos, sombre.rgb * 0.85, e, aa);
		piece(rgb, a, d_dos, c_dos, e, aa);
	} else {
		// DEVANT : les pointes, dégradées du pied (rouge) au sommet (vif) ; une
		// pointe qui arrive par le côté sort de l'ombre
		vec3 c_ombre = mix(sombre.rgb, couleur.rgb, 0.3 * g_face * degrade);
		vec3 c_face = mix(couleur.rgb, couleur_vive.rgb, pow(g_face, 1.3) * degrade);
		c_face = mix(c_ombre, c_face, smoothstep(0.0, 0.35, z_face));
		c_face = mix(c_face, couleur_vive.rgb, 0.7 * pl);
		piece(rgb, a, d_face, c_face, e, aa);
		// LES GOUTTES : elles perlent sous la bande (au bout des pointes quand
		// elles pointent vers le bas) et tombent en maigrissant
		if (gouttes > 0.001 && maigrit > 0.5) {
			for (int i = 0; i < 2; i++) {
				float fi = float(i);
				float cycle = temps / 1.2 + fi * 0.5;
				float n = floor(cycle);
				float u = fract(cycle);
				float xd = largeur * 0.8 * (alea(n * 7.3 + fi * 3.1) * 2.0 - 1.0);
				float zd = sqrt(max(1.0 - (xd / largeur) * (xd / largeur), 0.0));
				float chute = smoothstep(0.4, 1.0, u);
				float rg = 2.6 * smoothstep(0.0, 0.35, u) * (1.0 - chute * chute) * gouttes;
				float depart = profondeur * zd + b2 + 0.5 + (s < 0.0 ? hauteur * 0.55 * restant : 0.0);
				vec2 gq = q - vec2(xd, depart + 26.0 * chute * chute);
				gq.y /= (1.0 + 1.2 * chute);                    // elle s'étire en tombant
				par_dessus(rgb, a, mix(couleur.rgb, sombre.rgb, 0.4),
					smoothstep(0.0, aa, rg - length(gq)) * step(0.3, rg));
			}
		}
		// la bande, dégradée de haut (rouge) en bas (sombre), et son fil clair
		// le long du bord du haut
		float haut_bande = profondeur * zf - b2;
		float gb = clamp((q.y - haut_bande) / max(2.0 * b2, 1.0), 0.0, 1.0);
		vec3 c_bande = mix(couleur.rgb, mix(couleur.rgb, sombre.rgb, 0.75), gb * degrade);
		c_bande = mix(c_bande, couleur_vive.rgb, 0.6 * pl);
		piece(rgb, a, d_bande_face, c_bande, e, aa);
		float d_fil = min(1.1 - abs(q.y - haut_bande - 1.7), bord - 3.0);
		par_dessus(rgb, a, couleur_fil.rgb, smoothstep(0.0, aa, d_fil) * fil * step(3.0, b2 * 2.0));
	}

	// il apparaît en un éclair, s'efface en se desserrant
	a *= smoothstep(0.0, 0.25, apparition) * (1.0 - ef);
	COLOR = vec4(rgb, a);
}
