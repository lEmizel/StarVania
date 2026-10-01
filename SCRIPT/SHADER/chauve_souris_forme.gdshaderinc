// LA CHAUVE-SOURIS DE PAPIER (1er oct. 2026) — la silhouette commune à la
// chauve-souris de sang en jeu (chauve_souris_sang.gdshader) et au dessin du
// talisman « Essaim » (dessin_essaim.gdshader). D'après le croquis de Kaoru :
// pas une chauve-souris « littérale » mais un ORIGAMI SIMPLE, vu de côté
// (trois quarts), comme l'aile du héros : un corps en losange, la tête = UNE
// pointe, chaque aile = DEUX triangles (un grand dont la pointe part loin
// derrière, un petit dessous), rien de plus (« la tête un simple pic, les
// ailes juste deux triangles, pas plus »). Des aplats cernés d'encre ; l'aile
// lointaine, plus petite et plus sombre, passe derrière le corps.
//
// Repère : « unités de chauve-souris », l'origine est l'ÉPAULE, elle vole vers
// +x, y vers le BAS. Les ailes tournent autour de l'épaule : angle 0 = à plat
// vers l'arrière, positif = levée (+1,2 ≈ dressée), négatif = baissée.
// Toutes les distances sont positives DEDANS, comme dans les autres effets.

void cs_par_dessus(inout vec3 rgb, inout float a, vec3 teinte, float force) {
	float total = force + a * (1.0 - force);
	rgb = (teinte * force + rgb * a * (1.0 - force)) / max(total, 0.0001);
	a = total;
}

vec2 cs_tourne(vec2 p, float th) {
	return vec2(p.x * cos(th) - p.y * sin(th), p.x * sin(th) + p.y * cos(th));
}

// les pièces du pliage : 0 corps, 1 pointe de la tête, 2 grand triangle de
// l'aile, 3 petit triangle de l'aile (ailes à plat, vers l'arrière)
float cs_forme(vec2 p, int forme) {
	vec2 v[5];
	int n = 0;
	if (forme == 0) {
		// le corps : un losange, le poitrail en avant, la queue en pointe
		v[0] = vec2(12.0, -5.0); v[1] = vec2(18.0, 4.0); v[2] = vec2(2.0, 10.0); v[3] = vec2(-16.0, 7.0); v[4] = vec2(-8.0, -4.0);
		n = 5;
	} else if (forme == 1) {
		// la tête : une seule pointe, en avant et un peu levée
		v[0] = vec2(8.0, -6.0); v[1] = vec2(31.0, -9.0); v[2] = vec2(17.0, 2.0);
		n = 3;
	} else if (forme == 2) {
		// l'aile, le grand triangle : la pointe loin derrière
		v[0] = vec2(3.0, -3.0); v[1] = vec2(-44.0, -13.0); v[2] = vec2(-20.0, 2.0);
		n = 3;
	} else {
		// l'aile, le petit triangle dessous : une seconde pointe, plus courte
		v[0] = vec2(1.0, 0.0); v[1] = vec2(-27.0, 10.0); v[2] = vec2(-6.0, 9.0);
		n = 3;
	}
	float d = dot(p - v[0], p - v[0]);
	float s = 1.0;
	for (int i = 0; i < n; i++) {
		int j = (i == 0) ? n - 1 : i - 1;
		vec2 e = v[j] - v[i];
		vec2 w = p - v[i];
		vec2 b = w - e * clamp(dot(w, e) / max(dot(e, e), 0.0001), 0.0, 1.0);
		d = min(d, dot(b, b));
		bool c1 = p.y >= v[i].y;
		bool c2 = p.y < v[j].y;
		bool c3 = e.x * w.y > e.y * w.x;
		if ((c1 && c2 && c3) || (!c1 && !c2 && !c3)) {
			s = -s;
		}
	}
	return -s * sqrt(d);
}

// une pièce pleine cernée d'encre ; `d` en unités, `ppu` pixels par unité,
// `e_px` épaisseur du liseré en pixels. `ppu` doit être l'échelle qui a servi
// à passer en unités ; à 0 (forme réduite à rien) on ne peint RIEN — sinon
// toute distance vaut 0 px et le rectangle entier se peint.
void cs_piece(inout vec3 rgb, inout float a, float d, vec3 teinte, vec3 encre, float e_px, float ppu) {
	float d_px = d * ppu;
	float la = step(0.00001, ppu);
	cs_par_dessus(rgb, a, encre, smoothstep(-0.5, 0.5, d_px + e_px) * la);
	cs_par_dessus(rgb, a, teinte, smoothstep(-0.5, 0.5, d_px) * la);
}

// TOUTE la chauve-souris, de l'arrière vers l'avant.
//   b          le point, en unités (origine = l'épaule, elle vole vers +x)
//   th         angle de l'aile proche ; th_loin : de l'aile lointaine
//   squash     raccourci des ailes (1 = à plat dans l'écran, 0,78 = de biais)
//   teinte / teinte_loin / encre   les couleurs
//   e_px       le liseré (px) ; ppu : pixels par unité
void cs_dessiner(inout vec3 rgb, inout float a, vec2 b, float th, float th_loin, float squash,
		vec3 teinte, vec3 teinte_loin, vec3 encre, float e_px, float ppu) {
	// l'aile lointaine : plus petite, un peu plus haut et en avant, derrière tout
	vec2 ql = cs_tourne(b - vec2(5.0, -5.0), -th_loin) / 0.8;
	ql.x /= squash;
	cs_piece(rgb, a, cs_forme(ql, 3) * 0.8, teinte_loin, encre, e_px, ppu);
	cs_piece(rgb, a, cs_forme(ql, 2) * 0.8, teinte_loin, encre, e_px, ppu);
	cs_piece(rgb, a, cs_forme(b, 0), teinte, encre, e_px, ppu);
	cs_piece(rgb, a, cs_forme(b, 1), teinte, encre, e_px, ppu);
	// l'aile proche, par-dessus : le petit triangle, puis le grand
	vec2 q = cs_tourne(b, -th);
	q.x /= squash;
	cs_piece(rgb, a, cs_forme(q, 3), teinte, encre, e_px, ppu);
	cs_piece(rgb, a, cs_forme(q, 2), teinte, encre, e_px, ppu);
}
