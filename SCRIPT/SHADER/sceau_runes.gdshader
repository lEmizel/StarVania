shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;
// SCEAU DE RUNES (2 oct. 2026, piège proposé à Kaoru), dans les couleurs DORÉES
// de Kaoru (celles qu'il a mises sur la pince du grappin). Piloté par
// sceau_runes.gd.
//
// V2 EN VUE DE CÔTÉ (Kaoru : « la perspective n'est pas heureuse avec le
// décor ») : le décor est en pure vue de côté — le sol n'est qu'une ARÊTE, avec
// un mur dessous — donc l'ellipse posée au sol (v1) débordait sur le mur. Ici,
// rien n'est dessiné SOUS l'arête (seule une lueur douce y déborde, comme une
// vraie lumière qui éclaire le mur) :
//   • le CERCLE vu par la tranche : une LIGNE de lumière couchée sur l'arête ;
//   • les RUNES se dressent DEBOUT sur cette ligne ;
//   • juste avant le jet, le cercle SE LÈVE : un demi-cercle de lumière pousse
//     depuis les deux bouts de la ligne et se referme en DÔME au-dessus.
// Quatre temps :
//   • ENDORMI : une ligne à peine gravée et ses runes, sombres — on peut le repérer.
//   • ARMÉ (quelqu'un a marché dessus) : la ligne se TRACE depuis le milieu (deux
//     têtes brûlantes filent vers les bouts), les runes s'allument une à une du
//     centre vers les bords en se HAUSSANT — le temps de fuir ; puis le dôme
//     pousse, des FILS de lumière montent de la ligne.
//   • JAILLIT : une COLONNE de lumière part de la ligne vers le ciel (cœur crème,
//     bords or, stries qui filent vers le haut) ; l'onde court sur le sol, à
//     gauche et à droite.
//   • RETOMBE : la colonne MAIGRIT jusqu'au fil et s'éteint, des braises montent
//     en maigrissant, les runes se rentrent, le sceau se rendort.
// Tout s'AJOUTE en lumière (alpha prémultiplié) : la colonne éclaire le décor.

uniform vec2 taille = vec2(240.0, 380.0);    // le rectangle (px)
uniform vec2 centre = vec2(120.0, 340.0);    // le milieu du sceau, AU RAS DU SOL, dans le rectangle (px)
uniform float rayon = 70.0;                  // demi-largeur du sceau (px)
uniform float hauteur_colonne = 320.0;
uniform float largeur_colonne = 110.0;
uniform int nb_runes : hint_range(4, 12) = 8;
uniform float hauteur_rune = 16.0;           // (px)

// --- fournis par sceau_runes.gd ---
uniform float trace : hint_range(0.0, 1.0) = 0.0;     // la ligne qui se trace
uniform float runes : hint_range(0.0, 12.0) = 0.0;    // combien de runes sont allumées
uniform float charge : hint_range(0.0, 1.0) = 0.0;    // juste avant le jet : le dôme pousse, ça monte
uniform float jaillit : hint_range(0.0, 1.0) = 0.0;   // la colonne (0 → 1 pendant qu'elle blesse)
uniform float apres : hint_range(0.0, 1.0) = 0.0;     // elle retombe (0 → 1)
uniform float depuis_jet = -1.0;                      // secondes depuis le jet (< 0 : aucun)
uniform float temps = 0.0;
// ----------------------------------

uniform vec4 or_vif : source_color = vec4(0.9, 0.63, 0.21, 1.0);
uniform vec4 or_clair : source_color = vec4(0.99, 0.94, 0.75, 1.0);
uniform vec4 ambre : source_color = vec4(0.86, 0.65, 0.24, 1.0);
uniform vec4 grave : source_color = vec4(0.4, 0.26, 0.09, 1.0);      // le sceau endormi
uniform float grave_force : hint_range(0.0, 1.0) = 0.45;
uniform float trait = 1.3;                 // épaisseur des traits (px)
uniform float lueur = 0.55;                // la lueur autour des traits allumés
uniform float lueur_mur = 0.35;            // ce que la lueur déborde SOUS l'arête, sur le mur


float couvre(float d, float px) {
	return clamp(0.5 - d / px, 0.0, 1.0);
}

float alea(float n) {
	n = fract(n * 0.1031);
	n *= n + 33.33;
	n *= n + n;
	return fract(n);
}

float bruit(float x) {
	float i = floor(x);
	float f = fract(x);
	return mix(alea(i), alea(i + 1.0), f * f * (3.0 - 2.0 * f));
}

float bruit2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = alea(dot(i, vec2(1.0, 57.0)));
	float b = alea(dot(i + vec2(1.0, 0.0), vec2(1.0, 57.0)));
	float c = alea(dot(i + vec2(0.0, 1.0), vec2(1.0, 57.0)));
	float d = alea(dot(i + vec2(1.0, 1.0), vec2(1.0, 57.0)));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float segment(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

// un fuseau couché sur l'axe u (celui de la trace de griffe) ; positive dedans
float fuseau(float u, float v, float u0, float u1, float demi, float ventre) {
	float s = (u - u0) / max(u1 - u0, 0.0001);
	if (u1 <= u0 || s <= 0.0 || s >= 1.0) {
		return -1.0;
	}
	return demi * min(s / ventre, (1.0 - s) / (1.0 - ventre)) - abs(v);
}

// un trait de rune, dans la case de la rune ([-0.6, 0.6] × [-1, 1], +y vers le haut)
float trait_rune(vec2 q, int k) {
	if (k == 0) return segment(q, vec2(0.0, 0.3), vec2(0.55, 0.8));
	if (k == 1) return segment(q, vec2(0.0, 0.3), vec2(-0.55, 0.8));
	if (k == 2) return segment(q, vec2(0.0, -0.2), vec2(0.55, -0.65));
	if (k == 3) return segment(q, vec2(0.0, -0.2), vec2(-0.55, -0.65));
	if (k == 4) return min(segment(q, vec2(-0.5, 0.25), vec2(0.0, -0.25)), segment(q, vec2(0.0, -0.25), vec2(0.5, 0.25)));
	return segment(q, vec2(-0.45, 0.05), vec2(0.45, 0.05));
}

void fragment() {
	vec2 pix = UV * taille;
	float px = max(fwidth(pix.x), 0.001);
	vec2 q = pix - centre;                       // px depuis le milieu du sceau, +y vers le BAS
	vec3 rgb = vec3(0.0);
	float alpha = 0.0;
	vec3 ajout = vec3(0.0);
	// rien n'est dessiné sous l'arête du sol (la lueur, elle, y déborde un peu)
	float au_dessus = step(q.y, 0.5);
	float sous = q.y > 0.0 ? exp(-q.y / 7.0) * lueur_mur : 1.0;

	float eveil = max(max(trace, charge), jaillit) * (1.0 - apres);   // 0 endormi, 1 tout allumé
	float chaud = clamp(charge * 0.6 + jaillit, 0.0, 1.0) * (1.0 - apres);
	vec3 teinte = mix(or_vif.rgb, or_clair.rgb, chaud * 0.7);
	float d_allume = 1000.0;          // distance au trait allumé le plus proche (px), pour la lueur

	// ===================== LA LIGNE (le cercle vu par la tranche) =====================
	// plus épaisse au milieu, effilée aux bouts ; elle se trace depuis le milieu
	float xr = clamp(q.x / rayon, -1.0, 1.0);
	float demi_l = trait * (0.55 + 0.9 * sqrt(max(1.0 - xr * xr, 0.0)));
	float d_ligne = max(abs(q.y + demi_l) - demi_l, abs(q.x) - rayon);
	float trace_ici = step(abs(q.x), trace * rayon) * (1.0 - apres);
	float c_ligne = couvre(d_ligne, px) * au_dessus;
	rgb = mix(rgb, mix(grave.rgb, teinte, trace_ici), c_ligne);
	alpha = max(alpha, c_ligne * mix(grave_force, 1.0, trace_ici));
	if (trace_ici > 0.0) {
		d_allume = min(d_allume, max(d_ligne, 0.0));
	}
	// les deux têtes brûlantes qui tracent la ligne
	if (trace > 0.0 && trace < 1.0) {
		vec2 t1 = q - vec2(trace * rayon, -demi_l);
		vec2 t2 = q - vec2(-trace * rayon, -demi_l);
		float tete = exp(-dot(t1, t1) / 18.0) + exp(-dot(t2, t2) / 18.0);
		ajout += or_clair.rgb * tete * 1.5 * sous;
	}

	// ===================== LES RUNES, DEBOUT SUR LA LIGNE =====================
	// elles s'allument une à une, du centre vers les bords, en se haussant
	float nr = float(nb_runes);
	float milieu = (nr - 1.0) * 0.5;
	float pas_x = rayon * 1.6 / max(nr - 1.0, 1.0);
	float d_runes = 1000.0;
	for (int i = 0; i < 12; i++) {
		if (i >= nb_runes) {
			break;
		}
		float fi = float(i);
		float ecart = abs(fi - milieu);
		float rang = floor(ecart) * 2.0 + (fi > milieu ? 1.0 : 0.0);
		float allume = clamp(runes - rang, 0.0, 1.0) * (1.0 - apres);
		float hausse = allume * 3.0 * (1.0 - apres);
		float demi_h = hauteur_rune * 0.5;
		vec2 c = vec2((fi - milieu) * pas_x, -(demi_l * 2.0 + 2.0 + demi_h + hausse));
		vec2 r = (q - c) / demi_h;
		r.y = -r.y;                                // +y vers le haut dans la case
		if (abs(r.x) > 1.2 || abs(r.y) > 1.4) {
			continue;
		}
		float h = alea(fi * 7.31 + 1.7);
		int k1 = int(floor(h * 6.0));
		int k2 = int(floor(fract(h * 13.7) * 6.0));
		if (k2 == k1) {
			k2 = (k1 + 3) % 6;
		}
		float dq = min(segment(r, vec2(0.0, -0.95), vec2(0.0, 0.95)), min(trait_rune(r, k1), trait_rune(r, k2)));
		float d_px = dq * demi_h - trait * 0.5;
		// celle qui s'allume éclate un instant
		float eclate = allume * (1.0 - allume) * 4.0;
		float cr = couvre(d_px - eclate * 0.7, px) * au_dessus;
		float on = step(0.01, allume);
		rgb = mix(rgb, mix(grave.rgb, mix(teinte, or_clair.rgb, eclate), on), cr);
		alpha = max(alpha, cr * mix(grave_force, 1.0, on));
		if (on > 0.0) {
			d_runes = min(d_runes, max(d_px, 0.0));
			ajout += or_clair.rgb * eclate * exp(-max(d_px, 0.0) * 0.25) * 0.8;
		}
	}
	d_allume = min(d_allume, d_runes);

	// ===================== LE DÔME (le cercle se lève) =====================
	// deux arcs poussent depuis les bouts de la ligne et se rejoignent en haut
	if (charge > 0.0 && apres < 1.0) {
		vec2 qd = vec2(q.x, -q.y);                         // +y vers le haut
		float rd = length(qd);
		float ad = atan(qd.y, qd.x);                        // 0 à droite, π à gauche, π/2 en haut
		float pousse = charge * 1.5708;
		float sur_arc = step(0.0, qd.y) * (step(ad, pousse) + step(3.14159 - pousse, ad));
		float d_dome = abs(rd - rayon) - trait * 0.5;
		float d_dome2 = abs(rd - rayon * 0.86) - trait * 0.3;
		float env = (1.0 - apres) * (1.0 - smoothstep(0.35, 1.0, jaillit));
		float cd = max(couvre(d_dome, px), couvre(d_dome2, px) * 0.6) * min(sur_arc, 1.0) * env * au_dessus;
		rgb = mix(rgb, mix(teinte, or_clair.rgb, 0.4), cd);
		alpha = max(alpha, cd);
		if (sur_arc > 0.0 && env > 0.0) {
			d_allume = min(d_allume, max(d_dome, 0.0) + (1.0 - env) * 30.0);
		}
		// les têtes qui font pousser les arcs
		if (charge < 1.0) {
			vec2 h1 = qd - vec2(cos(pousse), sin(pousse)) * rayon;
			vec2 h2 = qd - vec2(-cos(pousse), sin(pousse)) * rayon;
			ajout += or_clair.rgb * (exp(-dot(h1, h1) / 14.0) + exp(-dot(h2, h2) / 14.0)) * 1.3 * env;
		}
	}

	// la lueur dorée autour de tout ce qui est allumé (elle déborde un peu sur le mur)
	ajout += teinte * exp(-d_allume / 5.0) * lueur * eveil * (0.45 + 0.55 * charge)
		* (0.9 + 0.1 * sin(temps * 9.0)) * sous;
	// la lumière posée sur l'arête quand ça monte
	float sur_sol = exp(-abs(q.y + 1.0) / 2.5) * smoothstep(rayon * 1.05, rayon * 0.6, abs(q.x));
	ajout += or_vif.rgb * sur_sol * (charge * 0.35 + jaillit * 0.6) * (1.0 - apres) * sous;

	// ===================== LES FILS QUI MONTENT (juste avant le jet) =====================
	if (charge > 0.0 && apres < 1.0) {
		for (int k = 0; k < 12; k++) {
			float fk = float(k);
			float x0 = (fk / 11.0 * 2.0 - 1.0) * rayon * 0.92 + (alea(fk * 3.1) - 0.5) * 6.0;
			float haut = charge * (24.0 + 60.0 * alea(fk * 5.7)) * (0.75 + 0.25 * bruit(temps * 10.0 + fk));
			float y = -q.y;
			if (y < 0.0 || y > haut) {
				continue;
			}
			float d = abs(q.x - x0) - 0.6;
			float f = couvre(d, px) * (1.0 - y / haut) * (1.0 - jaillit);
			ajout += or_clair.rgb * f * charge * 1.2;
		}
	}

	// ===================== LA COLONNE =====================
	if (jaillit > 0.0) {
		float monte = smoothstep(0.0, 0.18, jaillit);
		float h = hauteur_colonne * monte;
		float y_up = -q.y / max(h, 1.0);
		float x_rel = q.x / (largeur_colonne * 0.5);
		float maigrit = mix(1.0, 0.08, smoothstep(0.0, 0.85, apres));
		float wf = mix(1.0, 0.62, clamp(y_up, 0.0, 1.0)) * maigrit;
		float dans = smoothstep(wf, wf * 0.72, abs(x_rel)) * step(-0.02, y_up) * smoothstep(1.0, 0.8, y_up);
		float coeur = smoothstep(wf * 0.42, 0.0, abs(x_rel)) * step(-0.02, y_up) * smoothstep(1.0, 0.7, y_up);
		float stries = smoothstep(0.55, 0.95, bruit2(vec2(x_rel * 7.0, y_up * 5.0 - temps * 7.0)));
		float env = 1.0 - smoothstep(0.2, 1.0, apres);
		float I = (dans * 0.45 + coeur * 0.95 + stries * dans * 0.5) * env;
		ajout += mix(or_vif.rgb, or_clair.rgb, coeur) * I;
		// l'onde qui court sur le sol, à gauche et à droite, au départ du jet
		float k = clamp(jaillit * 2.2, 0.0, 1.0);
		float x_onde = rayon * (0.9 + 1.4 * k);
		float d_onde = max(abs(abs(q.x) - x_onde) - 10.0 * (1.0 - k) - 3.0, abs(q.y + 2.0) - 2.2 * (1.0 - k) - 0.6);
		ajout += or_clair.rgb * couvre(d_onde, px) * pow(1.0 - k, 1.5) * 1.3 * au_dessus;
		ajout += or_clair.rgb * exp(-abs(q.y + 2.0) / 3.0) * exp(-pow((abs(q.x) - x_onde) / 14.0, 2.0))
			* pow(1.0 - k, 2.0) * 0.8 * sous;
	}

	// ===================== LES BRAISES (le jet retombe) =====================
	if (depuis_jet >= 0.0) {
		for (int b = 0; b < 12; b++) {
			float fb = float(b);
			float naissance = alea(fb * 2.3) * 0.35;
			float t = depuis_jet - naissance;
			float vie = 0.55 + 0.35 * alea(fb * 4.1);
			if (t < 0.0 || t > vie) {
				continue;
			}
			float r = t / vie;
			float x0 = (alea(fb * 6.7) - 0.5) * largeur_colonne * 0.9;
			float vit = 90.0 + 140.0 * alea(fb * 8.9);
			vec2 pos = vec2(x0 + sin(t * 6.0 + fb) * 6.0, -10.0 - vit * t);
			float lng = mix(9.0, 15.0, alea(fb * 1.9)) * (1.0 - 0.4 * r);
			float demi = mix(1.2, 2.0, alea(fb * 3.3)) * (1.0 - r * r);
			vec2 d = q - pos;
			// la tête en haut, la traîne en dessous
			float f = fuseau(-d.y, d.x, -lng, 0.0, demi, 0.7);
			float cb = couvre(-f, px) * au_dessus;
			rgb = mix(rgb, mix(or_clair.rgb, ambre.rgb, smoothstep(0.2, 0.9, r)), cb);
			alpha = max(alpha, cb);
		}
	}

	COLOR = vec4(rgb * alpha + ajout, alpha);
}
