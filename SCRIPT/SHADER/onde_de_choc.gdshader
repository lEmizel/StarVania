shader_type canvas_item;
render_mode unshaded;
// ONDE DE CHOC AU SOL — le coup de pied du boss. Même famille que impact_blanc
// (aplats nets, contour d'encre, tout piloté par `progress`, des formes qui
// MAIGRISSENT au lieu de s'estomper), mais couchée sur le sol.
//
// Repère : l'origine est le milieu de la zone de dégâts, SUR le sol ; l'unité
// est le pixel. Tout ce qui dépend du jeu est fourni par onde_de_choc.gd : la
// largeur de la zone, la hauteur du sol, et les deux instants entre lesquels
// la zone blesse. Le visuel ne peut donc pas mentir sur ce qui touche.
//
// TROIS FORMES, dans l'ordre où elles arrivent :
//   • l'ÉCRASEMENT — là où le pied tombe : un cœur et une gerbe d'éclats en
//     demi-étoile au-dessus du sol. C'est le « boum », parti en un instant.
//   • l'ANNEAU — l'onde qui file sur le sol des deux côtés : un anneau vu
//     presque à plat, épais à ses deux pointes. Il atteint les bords de la zone
//     pile quand elle devient dangereuse. C'est l'annonce.
//   • la COURONNE — le danger : des éclats plantés tout le long de la zone.
//     Petits au passage de l'anneau, ils JAILLISSENT du sol juste avant
//     `debut_coup` (du centre vers les bords), tiennent jusqu'à `fin_coup`,
//     puis rentrent sous terre. Chacun arrache un DÉBRIS qui monte en biais.

uniform float progress : hint_range(0.0, 1.0) = 0.0;

// --- fournis par onde_de_choc.gd à chaque image -----------------------------
// taille du rectangle (px) et place de l'origine du nœud dedans
uniform vec2 taille = vec2(1560.0, 290.0);
uniform vec2 origine = vec2(0.5, 0.724);
// hauteur du sol sous l'origine du nœud, et décalage du milieu de la zone (px)
uniform float sol = 22.0;
uniform float centre_x = 0.0;
// demi-largeur de la zone de dégâts (px)
uniform float demi_largeur = 555.0;
// instants (0 → 1) où la zone devient, puis cesse d'être dangereuse
uniform float debut_coup = 0.556;
uniform float fin_coup = 0.778;
// ----------------------------------------------------------------------------

// nombre d'éclats dressés le long de la zone
uniform int nb_eclats : hint_range(6, 40) = 30;
// hauteur des plus grands éclats de la couronne (px)
uniform float hauteur : hint_range(20.0, 200.0) = 95.0;
// 0 = éclats bien droits, 1 = ils penchent franchement vers l'extérieur
uniform float penche : hint_range(0.0, 1.0) = 0.5;
// 0 = éclats rectilignes, 1 = ils se recourbent franchement vers l'extérieur
uniform float courbe : hint_range(0.0, 1.0) = 0.5;
// épaisseur de tous les traits
uniform float epaisseur : hint_range(0.2, 2.0) = 1.0;
// l'anneau qui file sur le sol (0 = aucun)
uniform float anneau : hint_range(0.0, 1.0) = 0.7;
// la gerbe à l'endroit où le pied tombe (0 = aucune)
uniform float ecrasement : hint_range(0.0, 1.0) = 1.0;
// liseré d'encre autour du blanc (0 = aucun)
uniform float contour : hint_range(0.0, 1.0) = 0.5;
// une valeur par onde : deux coups de pied ne se ressemblent pas
uniform float graine = 0.0;
uniform vec4 couleur : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 couleur_contour : source_color = vec4(0.05, 0.03, 0.06, 1.0);

const int MAX_ECLATS = 40;
const int NB_GERBE = 9;
// part de l'épaisseur d'une forme que son contour peut ajouter, au plus : le
// liseré s'affine avec la forme, et une pointe finit en pointe
const float PART_CONTOUR = 0.6;

// hash 1D sans sin : une valeur stable par éclat
float alea(float n) {
	n = fract(n * 0.1031);
	n *= n + 33.33;
	n *= n + n;
	return fract(n);
}

// Un FUSEAU couché sur l'axe u, de u0 à u1, pointu aux deux bouts. `demi` est
// sa demi-largeur au ventre, placé à la fraction `ventre` de sa longueur, `c`
// la largeur du contour. Renvoie deux distances, positives dedans : (le blanc,
// le blanc épaissi de son contour).
vec2 fuseau(float u, float v, float u0, float u1, float demi, float ventre, float c) {
	float s = (u - u0) / max(u1 - u0, 0.0001);
	if (u1 <= u0 || s <= 0.0) {
		return vec2(-length(vec2(u - u0, v)));
	}
	if (s >= 1.0) {
		return vec2(-length(vec2(u - u1, v)));
	}
	float large = demi * min(s / ventre, (1.0 - s) / (1.0 - ventre));
	return vec2(large, large + min(c, large * PART_CONTOUR)) - abs(v);
}

// Une ÉPINE plantée à l'origine de `e`, haute de `l` le long de `dir`, large
// de `demi` à sa base. Ses flancs sont creusés (elle s'effile vite) et son axe
// se courbe de `courbure` × l vers la droite en arrivant au sommet. Sous sa
// base elle garde sa largeur : c'est le sol qui la coupe. Mêmes deux distances
// que `fuseau`.
vec2 epine(vec2 e, vec2 dir, float l, float demi, float courbure, float c) {
	if (l <= 0.0001) {
		return vec2(-1.0e4);
	}
	float u = dot(e, dir);
	float v = e.x * dir.y - e.y * dir.x;        // positif à GAUCHE de l'axe
	float s = u / l;
	if (s >= 1.0) {
		return vec2(-length(vec2(u - l, v + courbure * l)));
	}
	float sc = max(s, 0.0);
	float large = demi * pow(1.0 - sc, 1.6);
	return vec2(large, large + min(c, large * PART_CONTOUR)) - abs(v + courbure * l * sc * sc);
}


void fragment() {
	// origine au milieu de la zone, sur le sol ; y négatif = au-dessus du sol
	vec2 p = (UV - origine) * taille - vec2(centre_x, sol);
	float t = clamp(progress, 0.0, 1.0);
	float td = max(debut_coup, 0.05);
	float tf = clamp(fin_coup, td + 0.02, 0.96);
	// un pixel d'écran, en pixels du rectangle : des bords nets à toute échelle
	float px = length(vec2(dFdx(UV.y), dFdy(UV.y))) * taille.y * 1.5;
	float c = contour * 3.5;
	// les formes s'additionnent par le max de leurs distances : x = le blanc,
	// y = le blanc épaissi de son contour
	vec2 sd = vec2(-1.0e4);
	float f;

	// 1) L'ÉCRASEMENT : fini dans le premier tiers
	float ta = clamp(t / 0.30, 0.0, 1.0);
	float pa = 1.0 - pow(1.0 - ta, 3.0);        // ça part très vite puis ça freine
	float flash = 1.0 - smoothstep(0.0, 0.3, ta);
	// le cœur : un demi-disque posé sur le sol
	float r_coeur = 40.0 * ecrasement * clamp(1.0 - ta * 2.2, 0.0, 1.0);
	f = min(r_coeur - length(p), -p.y);
	sd = max(sd, vec2(f, f + min(c, r_coeur * PART_CONTOUR)));
	// la gerbe : des éclats en éventail au-dessus du sol, plus longs au ras du sol
	for (int k = 0; k < NB_GERBE; k++) {
		float fk = float(k);
		float h1 = alea(fk * 1.7 + graine + 40.0);
		float h2 = alea(fk * 3.1 + graine * 1.3 + 45.0);
		float h3 = alea(fk * 5.3 + graine * 0.7 + 49.0);
		float ang = radians(14.0) + (fk + 0.5 + (h3 - 0.5) * 0.6) / float(NB_GERBE) * radians(152.0);
		vec2 dir = vec2(cos(ang), -sin(ang));
		float r1 = 170.0 * ecrasement * (0.55 + 0.45 * h1) * (0.55 + 0.45 * abs(dir.x))
				* (0.55 + 0.45 * pa);
		float r0 = r1 * 0.85 * ta;              // la base décolle : l'éclat s'en va
		float demi = epaisseur * (8.0 + 9.0 * h2) * ((1.0 - ta) + flash);
		sd = max(sd, fuseau(dot(p, dir), p.x * dir.y - p.y * dir.x, r0, r1, demi, 0.24, c));
	}

	// 2) L'ANNEAU : il s'élargit jusqu'aux bords de la zone, qu'il atteint à
	// `debut_coup`, puis il s'y tient et maigrit après `fin_coup`
	float avance = clamp(t / td, 0.0, 1.0);
	float a = max(demi_largeur * (1.0 - (1.0 - avance) * (1.0 - avance)), 1.0);
	float b = a * 0.03 + 3.0;                   // vu presque à plat
	// l'ellipse ramenée à un cercle de rayon b ; `pente` corrige l'étirement
	// pour que l'épaisseur du trait reste la même tout autour
	vec2 q = vec2(p.x * (b / a), p.y);
	float dq = max(length(q), 0.0001);
	float pente = length(vec2(q.x * (b / a), q.y)) / dq;
	float cq = q.x / dq;
	// trait de pinceau : épais aux deux pointes, plus fin du côté éloigné (le haut)
	float pinceau = (0.22 + 0.78 * cq * cq) * mix(0.6, 1.0, smoothstep(-0.3, 0.3, q.y / dq));
	float demi_a = 9.0 * anneau * epaisseur * pinceau
			* smoothstep(0.0, 0.06, t) * (1.0 - smoothstep(tf, 0.97, t));
	f = demi_a - abs(dq - b) / pente;
	sd = max(sd, vec2(f, f + min(c, demi_a * PART_CONTOUR)));

	// 3) LA COURONNE
	float n = float(nb_eclats);
	for (int i = 0; i < MAX_ECLATS; i++) {
		if (i >= nb_eclats) {
			break;
		}
		float fi = float(i);
		float h1 = alea(fi * 1.7 + graine);
		float h2 = alea(fi * 3.1 + graine * 1.3 + 5.0);
		float h3 = alea(fi * 5.3 + graine * 0.7 + 9.0);
		float h4 = alea(fi * 7.9 + graine * 2.1 + 3.0);
		// une place par éclat le long de la zone (-1 → 1), un peu décalée
		float place = (fi + 0.5 + (h3 - 0.5) * 0.7) / n * 2.0 - 1.0;
		float x = place * demi_largeur;
		// petit quand l'anneau le frôle, il jaillit d'un coup juste avant que la
		// zone ne blesse : le centre d'abord, les bords un rien plus tard
		float frole = 0.22 * smoothstep(abs(x) - 30.0, abs(x) + 50.0, a);
		float ts = td - 0.10 + 0.08 * abs(place);
		float grand = mix(frole, 1.0, smoothstep(ts, ts + 0.045, t));
		// après le coup : il rentre dans le sol en maigrissant
		float chute = clamp((t - tf - 0.03 * h4) / max(1.0 - tf - 0.03, 0.01), 0.0, 1.0);
		grand *= 1.0 - chute * chute;
		// en éventail : droits au milieu, de plus en plus couchés vers les bords
		float incline = penche * (0.85 * place + (h4 - 0.5) * 0.4);
		vec2 dir = vec2(sin(incline), -cos(incline));
		// quelques grands, beaucoup de moyens, plus hauts vers les bords
		float l = hauteur * (0.38 + 0.62 * h1 * h1) * (0.8 + 0.2 * abs(place)) * grand;
		float demi = epaisseur * (11.0 + 12.0 * h2) * (0.5 + 0.5 * grand) * (1.0 - chute);
		// une épine PLANTÉE, courbée vers l'extérieur comme la couronne d'une
		// éclaboussure ; tout ce qui passe sous le sol est coupé — elle sort de terre
		vec2 e = p - vec2(x, 0.0);
		float courbure = courbe * (0.8 * place + (h2 - 0.5) * 0.5);
		sd = max(sd, min(epine(e, dir, l, demi, courbure, c), vec2(-p.y)));

		// 4) LES DÉBRIS : un petit éclat arraché par chaque jaillissement, qui
		// monte en biais et maigrit jusqu'à la fin
		float vol = clamp((t - ts) / max(1.0 - ts, 0.01), 0.0, 1.0);
		float monte = 1.0 - (1.0 - vol) * (1.0 - vol);
		vec2 d_dir = vec2(sin(incline * 2.2 + (h2 - 0.5) * 0.8), -cos(incline * 2.2 + (h2 - 0.5) * 0.8));
		float d0 = hauteur * (0.5 + 1.5 * h3) * monte;
		float d_l = 12.0 + 22.0 * h1;
		float d_demi = epaisseur * (3.0 + 4.0 * h4) * (1.0 - vol * vol) * step(0.0001, vol)
				* step(0.35, h2);               // un éclat sur trois n'en arrache pas
		sd = max(sd, fuseau(dot(e, d_dir), e.x * d_dir.y - e.y * d_dir.x, d0, d0 + d_l, d_demi, 0.4, c));
	}

	float blanc = smoothstep(0.0, px, sd.x);
	float encre = smoothstep(0.0, px, sd.y);
	// là où il n'y a pas de contour, encre == blanc : du blanc pur, sans frange
	vec3 rgb = mix(couleur_contour.rgb, couleur.rgb, blanc / max(encre, 0.0001));
	COLOR = vec4(rgb, couleur.a * encre);
}
