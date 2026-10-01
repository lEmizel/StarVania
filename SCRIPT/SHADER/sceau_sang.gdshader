shader_type canvas_item;
render_mode unshaded;
// SCEAU DE SANG (1er oct. 2026) — talisman « Offrande » : se soigner fait
// naître ce sceau sous les pieds du joueur ; à peine dessiné, il lâche une
// ONDE qui court au sol et repousse les ennemis qu'elle atteint.
// Vu de TROIS QUARTS, posé au sol (comme la couronne de la Vengeance) : un
// point du sol (u, w) se voit en (u, w·aplat). Aplats rouges et dégradés,
// aucun blanc, pas de liseré d'encre.
//   • LE SCEAU : deux cercles, une étoile à six branches inscrite dans le
//     cercle intérieur, des runes entre les deux cercles, un losange au
//     centre ; l'anneau entre les cercles est teinté. Il SE DESSINE (`trace`) :
//     les cercles et les runes d'un balayage, puis les six traits de l'étoile
//     l'un après l'autre. Il tourne lentement et ses traits battent tant qu'il
//     vit ; il s'éteint en maigrissant (`fin`).
//   • L'ONDE : une crête de sang qui part du bord du sceau et court au sol
//     jusqu'à `rayon_onde` en s'aplatissant ; sa moitié de derrière passe
//     derrière le sceau, celle de devant par-dessus. Sa crête ondule.
// Repère : l'origine est sous les PIEDS du joueur (`origine`, en px depuis le
// coin haut-gauche du rectangle), y vers le bas.

// --- fournis par sceau_sang.gd ---------------------------------------------
uniform vec2 taille = vec2(640.0, 210.0);
uniform vec2 origine = vec2(320.0, 127.0);
// 0 → 1 : il se dessine ; 0 → 1 : l'onde court ; 0 → 1 : il s'éteint
uniform float trace : hint_range(0.0, 1.0) = 1.0;
uniform float onde : hint_range(0.0, 1.0) = 0.0;
uniform float fin : hint_range(0.0, 1.0) = 0.0;
// jusqu'où l'onde court (px) ; le temps qui passe (s)
uniform float rayon_onde = 280.0;
uniform float temps = 0.0;
// où un mur l'arrête, à gauche et à droite (px depuis les pieds)
uniform float mur_gauche = 10000.0;
uniform float mur_droit = 10000.0;
// ----------------------------------------------------------------------------

// le sceau : son rayon (px), l'aplatissement du sol (1 = vu de dessus)
uniform float rayon_sceau : hint_range(40.0, 200.0) = 105.0;
uniform float aplat : hint_range(0.1, 1.0) = 0.24;
// épaisseur des traits (px) : les cercles, l'étoile et les runes
uniform float trait_cercle : hint_range(0.5, 8.0) = 3.0;
uniform float trait_etoile : hint_range(0.5, 8.0) = 2.2;
// sa rotation lente (rad/s), la teinte de l'anneau, la force du battement
uniform float tour : hint_range(-3.0, 3.0) = 0.45;
uniform float remplissage : hint_range(0.0, 1.0) = 0.5;
uniform float battement : hint_range(0.0, 1.0) = 0.6;
// la hauteur de la crête de l'onde à son départ (px)
uniform float hauteur_onde : hint_range(0.0, 80.0) = 36.0;
uniform vec4 couleur_vive : source_color = vec4(1.0, 0.17, 0.2, 1.0);
uniform vec4 couleur : source_color = vec4(0.78, 0.04, 0.12, 1.0);
uniform vec4 sombre : source_color = vec4(0.32, 0.01, 0.06, 1.0);

void par_dessus(inout vec3 rgb, inout float a, vec3 teinte, float force) {
	float total = force + a * (1.0 - force);
	rgb = (teinte * force + rgb * a * (1.0 - force)) / max(total, 0.0001);
	a = total;
}

float segment(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.0001), 0.0, 1.0);
	return length(pa - ba * h);
}

// Une distance mesurée sur le sol, en pixels d'écran : le sol est écrasé en
// hauteur (`aplat`), donc un trait de sol parait d'autant plus fin qu'il
// court en largeur. Pour un trait de direction `t` (unitaire, sur le sol), un
// écart `d` au sol fait `d · aplat / |(t.x, aplat · t.y)|` pixels.
// (Calculé, pas mesuré entre pixels voisins : sur l'arête d'un trait ou à la
// frontière de deux runes la mesure s'effondre — pointillés et rayons
// parasites, première version.)
float en_px(float d, vec2 t) {
	return d * aplat / max(length(vec2(t.x, aplat * t.y)), 0.0001);
}

vec2 tourne(vec2 v, float a) {
	return vec2(v.x * cos(a) - v.y * sin(a), v.x * sin(a) + v.y * cos(a));
}

// un trait de `w` px de large autour de la distance `d_px`
float trait(float d_px, float w) {
	return smoothstep(-0.5, 0.5, w * 0.5 - d_px) * step(0.05, w);
}

void fragment() {
	vec2 p = UV * taille - origine;
	vec2 g = vec2(p.x, p.y / aplat);               // le point, ramené sur le sol
	float r = length(g);
	float vie = 1.0 - clamp(fin, 0.0, 1.0);
	float tr = clamp(trace, 0.0, 1.0);
	float pouls = 0.5 + 0.5 * sin(temps * 7.0);
	vec3 c_trait = mix(couleur.rgb, couleur_vive.rgb, pouls * battement * vie);

	// ================= L'ONDE (calculée une fois, dessinée en deux) =================
	float u = clamp(onde, 0.0, 1.0);
	float en_course = step(0.0001, u) * step(u, 0.9999);
	float rw = mix(rayon_sceau, rayon_onde, 1.0 - (1.0 - u) * (1.0 - u));
	float h = hauteur_onde * pow(1.0 - u, 0.8) * smoothstep(0.0, 0.08, u);
	h *= 1.0 + 0.25 * sin(p.x * 0.08 + temps * 18.0);            // la crête ondule
	float xr = clamp(p.x / rw, -1.0, 1.0);
	float zf = sqrt(max(1.0 - xr * xr, 0.0));
	float bord_o = rw - abs(p.x);
	// un mur l'arrête net : rien au-delà
	bord_o = min(bord_o, min(p.x + mur_gauche, mur_droit - p.x));
	float y_dos = -aplat * rw * zf;
	float y_face = aplat * rw * zf;
	float epais_o = 1.5 + 2.0 * (1.0 - u);                         // le pied de la crête
	float d_dos = min(min(p.y - (y_dos - h), y_dos + epais_o - p.y), bord_o);
	float d_face = min(min(p.y - (y_face - h), y_face + epais_o - p.y), bord_o);
	float g_dos = clamp((y_dos - p.y) / max(h, 1.0), 0.0, 1.0);   // 0 au pied, 1 en haut
	float g_face = clamp((y_face - p.y) / max(h, 1.0), 0.0, 1.0);

	vec3 rgb = couleur.rgb;
	float a = 0.0;

	// 1. l'onde, DERRIÈRE : sombre, un peu plus claire vers sa crête
	par_dessus(rgb, a, mix(sombre.rgb, couleur.rgb * 0.75, g_dos), smoothstep(0.0, 1.0, d_dos) * en_course);

	// ================= LE SCEAU =================
	float R = rayon_sceau;
	float Ri = R * 0.8;
	float rot = temps * tour;
	vec2 gs = vec2(g.x * cos(rot) - g.y * sin(rot), g.x * sin(rot) + g.y * cos(rot));
	float ang = atan(gs.y, gs.x);
	float ang01 = fract((ang + PI * 0.5) / TAU);
	// le balayage du tracé : les cercles et les runes apparaissent en tournant
	float balaye = smoothstep(ang01, ang01 + 0.03, tr * 1.03);
	// la direction des cercles ici (sur le sol, non tournée)
	vec2 t_cercle = r > 0.001 ? vec2(-g.y, g.x) / r : vec2(1.0, 0.0);

	// l'anneau teinté entre les deux cercles, et le disque intérieur à peine
	float d_anneau = en_px(min(r - Ri, R - r), t_cercle);
	par_dessus(rgb, a, sombre.rgb, smoothstep(-0.5, 0.5, d_anneau) * remplissage * vie * balaye);
	float d_disque = en_px(Ri - r, t_cercle);
	par_dessus(rgb, a, sombre.rgb, smoothstep(-0.5, 0.5, d_disque) * 0.18 * vie * smoothstep(0.6, 1.0, tr));

	// les deux cercles
	float f_cercles = max(trait(en_px(abs(r - R), t_cercle), trait_cercle * vie),
			trait(en_px(abs(r - Ri), t_cercle), trait_cercle * 0.7 * vie)) * balaye;

	// les runes : dans chacun des 18 secteurs, un trait radial ou un petit losange
	float secteur = TAU / 18.0;
	float n = floor(ang / secteur);
	float ak = (n + 0.5) * secteur;
	vec2 dir = vec2(cos(ak), sin(ak));
	float le_long = dot(gs, dir);
	float travers = abs(dot(gs, vec2(-dir.y, dir.x)));
	float m = (R + Ri) * 0.5;
	float d_rune;
	if (mod(n, 2.0) < 0.5) {
		d_rune = max(travers, abs(le_long - m) - (R - Ri) * 0.28);
	} else {
		d_rune = (abs(le_long - m) + travers * 1.6) - (R - Ri) * 0.2;
		d_rune = max(d_rune, 0.0);
	}
	// un trait radial court dans la direction du secteur ; un losange, on le
	// prend comme les cercles
	vec2 t_rune = (mod(n, 2.0) < 0.5) ? tourne(dir, -rot) : t_cercle;
	float f_runes = trait(en_px(d_rune, t_rune), trait_etoile * vie) * balaye;

	// l'étoile : deux triangles inscrits dans le cercle intérieur, ses six
	// traits tracés l'un après l'autre une fois les cercles posés
	float d_et = 10000.0;
	vec2 t_et = vec2(1.0, 0.0);
	for (int k = 0; k < 6; k++) {
		float a0 = float(k) * TAU / 6.0 - PI * 0.5;
		float a1 = float(k + 2) * TAU / 6.0 - PI * 0.5;
		vec2 A = Ri * vec2(cos(a0), sin(a0));
		vec2 B = Ri * vec2(cos(a1), sin(a1));
		float v = clamp((tr - 0.35 - float(k) * 0.09) / 0.12, 0.0, 1.0);
		if (v > 0.0) {
			float dk = segment(gs, A, mix(A, B, v));
			if (dk < d_et) {
				d_et = dk;
				t_et = normalize(B - A);
			}
		}
	}
	float f_etoile = trait(en_px(d_et, tourne(t_et, -rot)), trait_etoile * vie);

	// le losange du centre
	float d_centre = en_px(abs(gs.x) + abs(gs.y) * 1.4 - R * 0.11, t_cercle);
	float f_centre = smoothstep(-0.5, 0.5, -d_centre) * smoothstep(0.85, 1.0, tr) * vie;

	par_dessus(rgb, a, c_trait, max(max(f_cercles, f_runes), max(f_etoile, f_centre)));

	// 2. l'onde, DEVANT : du rouge au pied au rouge vif sur la crête
	par_dessus(rgb, a, mix(couleur.rgb, couleur_vive.rgb, g_face), smoothstep(0.0, 1.0, d_face) * en_course);

	COLOR = vec4(rgb, a);
}
