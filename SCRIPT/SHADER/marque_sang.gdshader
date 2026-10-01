shader_type canvas_item;
render_mode unshaded;
// MARQUE DE SANG (1er oct. 2026) — la rune que la boule de sang pose au-dessus
// de l'ennemi qu'elle touche (talisman « Marque de sang ») : une GOUTTE de sang
// dans un ANNEAU qui sert de compte à rebours (l'arc se vide dans le sens des
// aiguilles d'une montre pendant que la marque attend le coup d'épée).
// Sobre comme les autres effets de sang : un aplat rouge cerné d'encre, aucun
// blanc.
//   • elle se POSE d'un coup sec (un tampon : plus grande, puis à sa taille) ;
//   • elle ÉCLATE quand le coup d'épée porte : l'anneau s'ouvre en grand et
//     s'amincit jusqu'à rien, la goutte gonfle et maigrit ;
//   • elle s'EFFACE si le temps passe (ou si l'ennemi meurt) : tout rapetisse
//     et maigrit.
// Repère : l'origine est le MILIEU du rectangle, en pixels.

// --- fournis par marque_sang.gd ---------------------------------------------
uniform vec2 taille = vec2(112.0, 112.0);
// 0 → 1 : la pose (le coup de tampon)
uniform float apparition : hint_range(0.0, 1.0) = 1.0;
// 1 → 0 : le temps qu'il lui reste (l'arc de l'anneau)
uniform float restant : hint_range(0.0, 1.0) = 1.0;
// 0 → 1 : elle éclate (coup porté) ; 0 → 1 : elle s'efface (temps écoulé)
uniform float eclat : hint_range(0.0, 1.0) = 0.0;
uniform float efface : hint_range(0.0, 1.0) = 0.0;
// ----------------------------------------------------------------------------

// rayon de l'anneau et son épaisseur (px)
uniform float rayon : hint_range(8.0, 50.0) = 25.0;
uniform float epaisseur : hint_range(1.0, 12.0) = 4.0;
// taille de la goutte (1 = 30 px de haut)
uniform float goutte : hint_range(0.3, 2.0) = 1.0;
// épaisseur du liseré d'encre (px)
uniform float encre : hint_range(0.0, 6.0) = 2.0;
uniform vec4 couleur : source_color = vec4(0.76, 0.03, 0.11, 1.0);
uniform vec4 couleur_encre : source_color = vec4(0.12, 0.0, 0.03, 1.0);

// (PI et TAU sont fournis par le langage de shader de Godot)

void par_dessus(inout vec3 rgb, inout float a, vec3 teinte, float force) {
	float total = force + a * (1.0 - force);
	rgb = (teinte * force + rgb * a * (1.0 - force)) / max(total, 0.0001);
	a = total;
}

// triangle isocèle (sommet à l'origine, base à y = q.y, demi-largeur q.x),
// distance signée (négative dedans) — d'après Inigo Quilez
float triangle(vec2 p, vec2 q) {
	p.x = abs(p.x);
	vec2 a = p - q * clamp(dot(p, q) / dot(q, q), 0.0, 1.0);
	vec2 b = p - q * vec2(clamp(p.x / q.x, 0.0, 1.0), 1.0);
	float s = -sign(q.y);
	vec2 d = min(vec2(dot(a, a), s * (p.x * q.y - p.y * q.x)), vec2(dot(b, b), s * (p.y - q.y)));
	return -sqrt(d.x) * sign(d.y);
}

// la GOUTTE (distance signée, négative dedans) : un rond en bas, une pointe en
// haut, unis en douceur
float sd_goutte(vec2 p) {
	float rond = length(p - vec2(0.0, 4.0)) - 9.0;
	float pointe = triangle(p - vec2(0.0, -16.0), vec2(8.2, 17.0));
	float k = 2.0;
	float h = clamp(0.5 + 0.5 * (pointe - rond) / k, 0.0, 1.0);
	return mix(pointe, rond, h) - k * h * (1.0 - h);
}


void fragment() {
	vec2 p = (UV - 0.5) * taille;
	float aa = max(length(vec2(dFdx(p.x), dFdy(p.x))), 0.35) * 1.2;

	// la pose : un coup de tampon (plus grande, puis à sa taille)
	float pose = 1.0 - pow(1.0 - clamp(apparition, 0.0, 1.0), 3.0);
	float echelle = mix(1.5, 1.0, pose);
	// l'éclat : l'anneau s'ouvre, tout maigrit ; l'effacement : tout rapetisse
	float ec = clamp(eclat, 0.0, 1.0);
	float ef = clamp(efface, 0.0, 1.0);
	float maigrit = (1.0 - ec) * (1.0 - ef);
	echelle *= mix(1.0, 0.6, ef);

	vec3 rgb = couleur.rgb;
	float a = 0.0;
	float e = encre * maigrit;

	// L'ANNEAU : un arc qui se vide dans le sens des aiguilles d'une montre,
	// depuis le haut
	float r_anneau = rayon * echelle * mix(1.0, 1.9, 1.0 - (1.0 - ec) * (1.0 - ec));
	float ep = epaisseur * maigrit * mix(1.0, 0.0, ec);
	float ang = atan(p.x, -p.y);                       // 0 en haut, croît vers la droite
	float part = fract(ang / TAU + 1.0);
	float arc = (restant - part) * r_anneau * TAU;      // > 0 : dans l'arc (en px le long)
	float bande = ep * 0.5 - abs(length(p) - r_anneau);
	float d_anneau = min(bande, ec > 0.0 ? 1e4 : arc);  // à l'éclat, l'anneau entier s'ouvre
	if (ep > 0.05) {
		par_dessus(rgb, a, couleur_encre.rgb, smoothstep(0.0, aa, d_anneau + e));
		par_dessus(rgb, a, couleur.rgb, smoothstep(0.0, aa, d_anneau));
	}

	// LA GOUTTE
	float tg = goutte * echelle * mix(1.0, 1.3, ec);
	float dg = -sd_goutte(p / tg) * tg;                // positive dedans, en px
	// à l'éclat et à l'effacement, elle maigrit (on ronge son bord)
	dg -= (1.0 - maigrit) * 10.0 * goutte;
	par_dessus(rgb, a, couleur_encre.rgb, smoothstep(0.0, aa, dg + e) * step(0.02, maigrit));
	par_dessus(rgb, a, couleur.rgb, smoothstep(0.0, aa, dg));

	// elle apparaît en un éclair (pas de fondu lent)
	a *= smoothstep(0.0, 0.25, apparition);
	COLOR = vec4(rgb, a);
}
