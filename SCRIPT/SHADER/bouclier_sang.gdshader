shader_type canvas_item;
render_mode unshaded;
// BOUCLIER DE SANG — la bulle rouge à facettes hexagonales qui se dresse
// autour du joueur quand il encaisse un coup (talisman « Bouclier de sang »,
// 30 sept. 2026). bouclier_sang.gd la fait vivre.
//
// Une bulle (ellipse `rayons`) vue comme une sphère : ses facettes — un pavage
// d'hexagones — se serrent vers le bord (`bombe`), le bord s'éclaire comme le
// contour d'une bulle de verre, avec un reflet en haut à gauche. Chaque facette
// a sa nuance et scintille lentement.
//   • MONTÉE (`montee` 0 → 1) : les facettes naissent une à une depuis
//     `origine`, le côté d'où le coup est venu, et s'ouvrent chacune depuis
//     son centre.
//   • PARADE (`onde` = secondes depuis le coup paré, depuis `onde_origine`) :
//     un éclat à l'impact et une onde qui court sur la bulle en éclaircissant
//     les facettes qu'elle traverse.
//   • FIN : sous `clignote` secondes restantes la bulle clignote ; puis
//     CHUTE (`chute` 0 → 1) : les facettes se referment dans le désordre.

// --- fournis par bouclier_sang.gd ---
uniform vec2 taille = vec2(288.0, 288.0);
uniform vec2 rayons = vec2(120.0, 120.0);
uniform float temps = 0.0;
uniform float montee : hint_range(0.0, 1.0) = 1.0;
uniform float chute : hint_range(0.0, 1.0) = 0.0;
uniform float restant = 2.0;
uniform vec2 origine = vec2(-1.0, 0.0);
uniform float onde = 9.0;
uniform vec2 onde_origine = vec2(1.0, 0.0);
uniform float graine = 0.0;
// --- l'allure ---
// taille des facettes (part du petit rayon)
uniform float facette : hint_range(0.1, 0.6) = 0.4;
// épaisseur des arêtes entre facettes (px)
uniform float lignes : hint_range(0.5, 4.0) = 1.5;
// opacité de la chair des facettes, et de leurs arêtes
uniform float opacite_fond : hint_range(0.0, 1.0) = 0.3;
uniform float opacite_bord : hint_range(0.0, 1.0) = 0.8;
// combien les facettes se serrent vers le bord (0 = plates, 1 = vraie sphère)
uniform float bombe : hint_range(0.0, 1.0) = 0.6;
// sous tant de secondes restantes, la bulle clignote
uniform float clignote : hint_range(0.0, 2.0) = 0.6;
// la chair : le sang ; les arêtes et le reflet : plus clairs ; l'éclat d'une parade
uniform vec4 couleur : source_color = vec4(0.72, 0.13, 0.17, 1.0);
uniform vec4 couleur_arete : source_color = vec4(1.0, 0.5, 0.48, 1.0);
uniform vec4 couleur_eclat : source_color = vec4(1.0, 0.93, 0.9, 1.0);

float alea(vec2 p) {
	p = fract(p * vec2(443.897, 441.423));
	p += dot(p, p.yx + 19.19);
	return fract((p.x + p.y) * p.x);
}

// le pavage d'hexagones (pointe en haut, rayon inscrit 0,5 : les centres sont
// espacés de 1 en x et de 0,866 en y, une rangée sur deux décalée) : renvoie
// le centre de la cellule du point `u`, et son identité dans `id`
vec2 centre_hex(vec2 u, out vec2 id) {
	const float H = 0.8660254;
	vec2 meilleur = vec2(0.0);
	float dmin = 1e9;
	float j0 = floor(u.y / H);
	for (int k = 0; k < 2; k++) {
		float j = j0 + float(k);
		float decale = 0.5 * mod(j, 2.0);
		float i = floor(u.x - decale + 0.5);
		vec2 c = vec2(i + decale, j * H);
		float d = dot(u - c, u - c);
		if (d < dmin) {
			dmin = d;
			meilleur = c;
			id = vec2(i, j);
		}
	}
	return meilleur;
}

// distance au bord de l'hexagone (positive dedans), `v` depuis son centre
float dedans_hex(vec2 v) {
	v = abs(v);
	return 0.5 - max(v.x, 0.5 * v.x + 0.8660254 * v.y);
}

vec4 par_dessus(vec4 dessous, vec4 dessus) {
	float a = dessus.a + dessous.a * (1.0 - dessus.a);
	return vec4((dessus.rgb * dessus.a + dessous.rgb * dessous.a * (1.0 - dessus.a)) / max(a, 0.0001), a);
}

void fragment() {
	vec2 p = (UV - 0.5) * taille;
	vec2 e = p / rayons;                  // coordonnées de bulle : son bord est à 1
	float r = length(e);
	float rmin = min(rayons.x, rayons.y);
	float px = max(fwidth(p.x), fwidth(p.y)) * 0.75;    // un pixel d'écran (px du rectangle)
	float px_e = px / rmin;                             // en unités de bulle

	// la sphère : hauteur en chaque point, et le bord qui s'éclaire
	float z = sqrt(max(1.0 - r * r, 0.0));
	float fres = pow(1.0 - z, 2.5);
	float interieur = 1.0 - smoothstep(1.0 - px_e, 1.0 + px_e, r);
	float vivant = smoothstep(0.0, 0.3, montee) * (1.0 - smoothstep(0.7, 1.0, chute));

	// ------- les facettes, plaquées sur la sphère -------
	float serre = mix(1.0, 0.35 + 0.65 * z, bombe);     // plus petit vers le bord
	vec2 q = e / (serre * facette);
	vec2 id;
	vec2 c = centre_hex(q, id);
	float d_bord = dedans_hex(q - c);                   // en cellules
	float cellule_px = facette * serre * rmin;          // une cellule (rayon inscrit 0,5) en px
	// où est cette facette sur la bulle (pour l'ordre de montée)
	vec2 c_e = c * facette * serre;
	// MONTÉE : depuis `origine`, chaque facette s'ouvre depuis son centre
	float seuil_m = clamp(length(c_e - origine) / 2.3, 0.0, 1.0);
	float ouverte = clamp((montee - seuil_m * 0.75) / 0.25, 0.0, 1.0);
	// CHUTE : dans le désordre, chacune se referme
	float seuil_c = alea(id + vec2(graine, 3.0));
	float fermee = clamp((chute - seuil_c * 0.7) / 0.3, 0.0, 1.0);
	float d_eff = d_bord - 0.5 * (1.0 - ouverte) - 0.5 * fermee;   // le bord effectif de la facette
	float px_c = px / cellule_px;
	float chair = smoothstep(0.0, px_c, d_eff);
	float lignes_c = lignes / cellule_px;
	float arete = (1.0 - smoothstep(lignes_c - px_c, lignes_c + px_c, d_eff)) * step(-px_c, d_eff);
	// chaque facette a sa nuance, qui scintille lentement
	float t2 = temps * 1.5;
	float nuance = mix(alea(id + vec2(floor(t2), graine)), alea(id + vec2(floor(t2) + 1.0, graine)), fract(t2));

	// ------- le reflet, l'onde d'une parade, le clignotement -------
	vec3 n = normalize(vec3(e * vec2(1.0, rayons.y / rayons.x), z));
	float reflet = pow(max(dot(n, normalize(vec3(-0.45, -0.6, 0.66))), 0.0), 14.0);
	float d_onde = length(e - onde_origine);
	float anneau = (1.0 - smoothstep(0.0, 0.28, abs(d_onde - onde * 5.0))) * (1.0 - smoothstep(0.0, 0.45, onde));
	float eclat = (1.0 - smoothstep(0.0, 0.4, d_onde)) * (1.0 - smoothstep(0.0, 0.18, onde));
	float parade = clamp(anneau + eclat, 0.0, 1.0);
	float clin = 1.0;
	if (restant < clignote && chute <= 0.0) {
		clin = 0.6 + 0.4 * step(0.5, fract(temps * 7.0));
	}

	// ------- composition -------
	// la chair des facettes, teintée par le bord de la bulle et le reflet
	vec3 rgb_chair = mix(couleur.rgb, couleur_arete.rgb, 0.55 * fres + 0.5 * reflet);
	rgb_chair = mix(rgb_chair, couleur_eclat.rgb, 0.8 * parade);
	float a_chair = (opacite_fond * (0.7 + 0.6 * nuance) + 0.45 * fres + 0.5 * reflet + 0.5 * parade) * chair;
	vec4 col = vec4(rgb_chair, clamp(a_chair, 0.0, 1.0) * interieur);
	// les arêtes
	vec3 rgb_arete = mix(couleur_arete.rgb, couleur_eclat.rgb, 0.6 * parade + 0.3 * fres);
	col = par_dessus(col, vec4(rgb_arete, opacite_bord * arete * interieur));
	// le contour de la bulle et sa lueur au-dehors
	float contour = 1.0 - smoothstep(0.0, 2.5 * px_e, abs(r - 1.0));
	float lueur = (1.0 - smoothstep(1.0, 1.16, r)) * step(1.0, r) * 0.35;
	col = par_dessus(col, vec4(mix(couleur_arete.rgb, couleur_eclat.rgb, 0.5 * parade), contour * 0.9 * vivant));
	col = par_dessus(vec4(couleur.rgb, lueur * vivant), col);
	COLOR = vec4(col.rgb, col.a * clin);
}
