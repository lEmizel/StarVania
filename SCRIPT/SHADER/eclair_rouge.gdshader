shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;
// ÉCLAIR ROUGE (4 oct. 2026, piège « tour au cristal rouge ») — l'éclair que le
// cristal tire droit sur sa cible, de la même famille que la foudre du ciel
// (cœur clair, lueur, brins brisés), en rouge. Dessiné dans un rectangle
// COUCHÉ le long du tir : le cristal en `depart`, le point d'impact `longueur`
// px plus loin sur l'axe x. Piloté par eclair_rouge.gd. Quatre temps :
//   • VISÉE (`vise`) : un pointillé discret qui suit la cible, un point au bout.
//   • AVERTISSEMENT (`avert` 0 → 1) : la visée est verrouillée — le pointillé
//     file, de plus en plus pressant, plein et vif à la fin ; la bande qui sera
//     frappée se devine ; une marque crépite au point d'impact.
//   • FRAPPE (`frappe` 0 → 1) : un gros éclair brisé du cristal à l'impact, avec
//     ses branches, qui crépite ; un éclat au point d'impact, un éclair de
//     lumière qui court sur la surface touchée.
//   • TRACE (`trace` 0 → 1) : une rémanence le long du tir, une brûlure sur la
//     surface qui refroidit, des étincelles qui retombent.
// Rien n'est dessiné DANS la surface touchée (`normale`), seule la lueur y
// déborde un peu. Tout s'ajoute en lumière (alpha prémultiplié) et s'éteint
// avant le bord du rectangle.

uniform vec2 taille = vec2(900.0, 240.0);
uniform vec2 depart = vec2(40.0, 120.0);     // le cristal, dans le rectangle
uniform float longueur = 800.0;              // du cristal au point d'impact (px)
uniform float largeur = 46.0;                // la bande frappée (px)
// --- fournis par eclair_rouge.gd ---
uniform float vise : hint_range(0.0, 1.0) = 0.0;
uniform float avert : hint_range(0.0, 1.0) = 0.0;
uniform float frappe : hint_range(0.0, 1.0) = 0.0;
uniform float trace : hint_range(0.0, 1.0) = 0.0;
uniform float temps = 0.0;
uniform float graine = 0.0;
// le bas du monde, dans le repère de l'éclair (les étincelles y retombent)
uniform vec2 bas = vec2(0.0, 1.0);
// la surface touchée, vers l'extérieur, dans le repère de l'éclair ; (0, 0) : aucune
uniform vec2 normale = vec2(-1.0, 0.0);
// --- l'allure ---
uniform float ampleur = 16.0;                // combien l'éclair s'écarte de la ligne droite (px)
uniform float epaisseur = 3.0;               // le cœur clair (px)
uniform float cadence = 16.0;                // l'éclair change de forme… fois par seconde
uniform float lueur_mur = 0.35;
uniform vec4 couleur : source_color = vec4(1.0, 0.88, 0.84, 1.0);
uniform vec4 couleur_foudre : source_color = vec4(1.0, 0.13, 0.16, 1.0);
uniform vec4 brulure : source_color = vec4(0.13, 0.05, 0.06, 1.0);


float couvre(float d, float px) {
	return clamp(0.5 - d / px, 0.0, 1.0);
}

float alea(vec2 p) {
	p = fract(p * vec2(443.897, 441.423));
	p += dot(p, p.yx + 19.19);
	return fract((p.x + p.y) * p.x);
}

// un hasard ENTIER, exact : le même sommet, calculé depuis le segment d'avant
// et depuis celui d'après, tombe au même endroit (avec un hasard flottant le
// tronc sautait d'une ligne à l'autre : vécu sur la foudre du ciel)
float alea_u(uint n) {
	n = (n << 13u) ^ n;
	n = n * (n * n * 15731u + 789221u) + 1376312589u;
	return float(n & 2147483647u) / 2147483647.0;
}

// une ligne brisée au hasard : entre -1 et 1, un sommet à chaque entier
float brisee(float x, float g) {
	float fi = floor(x);
	uint i = uint(int(fi) + 4096);
	uint s = uint(int(g * 97.0)) * 1013u;
	float a = alea_u(i * 7919u + s) * 2.0 - 1.0;
	float b = alea_u((i + 1u) * 7919u + s) * 2.0 - 1.0;
	return mix(a, b, x - fi);
}

// l'écart du tronc à la ligne droite, à `x` px du cristal : nul aux deux bouts.
// En PIXELS (un sommet tous les ~78 px, un petit tous les ~31) : un tir long
// n'a pas des zigzags étirés.
float ecart(float x, float L, float g) {
	float z = brisee(x / 78.0, g) + 0.5 * brisee(x / 31.0 + 4.7, g + 1.3);
	return ampleur * z * smoothstep(0.0, 56.0, x) * smoothstep(0.0, 40.0, L - x);
}

float segment(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.0001), 0.0, 1.0);
	return length(pa - ba * h);
}

// un fuseau couché sur l'axe u ; positive dedans
float fuseau(float u, float v, float u0, float u1, float demi, float ventre) {
	float s = (u - u0) / max(u1 - u0, 0.0001);
	if (u1 <= u0 || s <= 0.0 || s >= 1.0) {
		return -1.0;
	}
	return demi * min(s / ventre, (1.0 - s) / (1.0 - ventre)) - abs(v);
}

vec2 tourner(vec2 v, float a) {
	return vec2(v.x * cos(a) - v.y * sin(a), v.x * sin(a) + v.y * cos(a));
}

void fragment() {
	vec2 pix = UV * taille;
	float px = max(fwidth(pix.x), 0.001);
	vec2 q = pix - depart;                 // x le long du tir, y en travers
	float L = longueur;
	vec2 r = q - vec2(L, 0.0);             // depuis le point d'impact
	bool surface = dot(normale, normale) > 0.01;
	// dans la surface touchée : seule la lueur déborde un peu
	float dedans = surface ? -dot(r, normale) : -1.0;
	float sous = dedans > 0.0 ? exp(-dedans / 7.0) * lueur_mur : 1.0;
	float dehors = step(dedans, 0.5);
	float le_long = step(0.0, q.x) * step(q.x, L);
	vec3 rgb = vec3(0.0);
	float alpha = 0.0;
	vec3 ajout = vec3(0.0);
	vec3 rouge = couleur_foudre.rgb;
	vec3 blanc = couleur.rgb;
	float rr = length(r);

	// ===================== LA VISÉE : elle suit sa cible =====================
	if (vise > 0.0 && avert <= 0.0 && frappe <= 0.0 && trace <= 0.0) {
		float tiret = step(0.5, fract(q.x / 26.0 - temps * 3.0));
		float hors_cristal = smoothstep(24.0, 60.0, q.x);
		ajout += rouge * couvre(abs(q.y) - 0.6, px) * tiret * le_long * hors_cristal * 0.55 * vise;
		ajout += rouge * exp(-abs(q.y) / 4.0) * tiret * le_long * hors_cristal * 0.12 * vise;
		ajout += rouge * exp(-pow(rr / 7.0, 2.0)) * 0.7 * vise * sous;
	}

	// ===================== L'AVERTISSEMENT : elle est verrouillée =====================
	if (avert > 0.0 && frappe <= 0.0) {
		float presse = avert * avert;
		float vif = 0.55 + 0.45 * sin(temps * (10.0 + 40.0 * presse));
		float tiret = step(0.45, fract(q.x / 22.0 - temps * 5.0));
		float plein = smoothstep(0.7, 0.92, avert);
		float force = mix(tiret * 0.7, 1.0, plein);
		float hors_cristal = smoothstep(18.0, 46.0, q.x);
		ajout += mix(rouge, blanc, plein * 0.7) * couvre(abs(q.y) - mix(0.7, 1.3, plein), px)
				* force * le_long * hors_cristal * (0.6 + 0.4 * vif);
		ajout += rouge * exp(-abs(q.y) / 5.0) * force * le_long * hors_cristal * 0.3;
		// la bande qui sera frappée se devine
		ajout += rouge * smoothstep(largeur * 0.5, largeur * 0.2, abs(q.y)) * le_long * hors_cristal * 0.07 * presse;
		// la marque au point d'impact, qui crépite
		ajout += rouge * exp(-pow(rr / (8.0 + 8.0 * avert), 2.0)) * (0.5 + 0.5 * vif) * sous;
		ajout += blanc * exp(-pow(rr / 4.0, 2.0)) * avert * vif * dehors;
		vec2 n0 = surface ? normale : vec2(-1.0, 0.0);
		for (int k = 0; k < 4; k++) {
			float fk = float(k);
			float tick = floor(temps * 16.0 + fk * 0.37);
			vec2 dir = tourner(n0, (alea(vec2(tick, fk + graine)) - 0.5) * 2.6);
			float lng = (5.0 + 12.0 * alea(vec2(fk, tick + 3.0))) * (0.4 + avert);
			vec2 coude = dir * lng * 0.5 + tourner(dir, 1.5708) * (alea(vec2(tick, fk + 7.0)) - 0.5) * 6.0;
			float de = min(segment(r, vec2(0.0), coude), segment(r, coude, dir * lng)) - 0.5;
			ajout += blanc * couvre(de, px) * avert * dehors;
		}
	}

	// ===================== LA FRAPPE =====================
	if (frappe > 0.0 && trace <= 0.0) {
		float g = graine + floor(frappe * 0.25 * cadence) * 7.13;
		// il crépite : quelques éclipses rapides, plus fort au début
		float strobe = 0.65 + 0.35 * step(0.35, fract(frappe * 6.0));
		float I = pow(1.0 - frappe, 0.6) * strobe;
		if (q.x >= 0.0 && q.x <= L) {
			// le tronc : sa vraie distance, aux segments échantillonnés tous les
			// 6 px autour de ce point
			float d_tronc = 100000.0;
			float x0 = clamp(q.x - 24.0, 0.0, L);
			vec2 sa = vec2(x0, ecart(x0, L, g));
			for (int k = 1; k <= 8; k++) {
				float xk = clamp(q.x - 24.0 + float(k) * 6.0, 0.0, L);
				vec2 sb = vec2(xk, ecart(xk, L, g));
				d_tronc = min(d_tronc, segment(q, sa, sb));
				sa = sb;
			}
			ajout += blanc * couvre(d_tronc - epaisseur * 0.5, px) * I * 1.4;
			ajout += rouge * exp(-d_tronc / 9.0) * I * 0.95;
			ajout += rouge * exp(-d_tronc / 28.0) * I * 0.35;
			// les branches : elles quittent le tronc et filent en s'écartant
			for (int b = 0; b < 3; b++) {
				float fb = float(b);
				float xb = L * (0.18 + 0.6 * alea(vec2(fb, g + 2.0)));
				float cote = alea(vec2(fb + 5.0, g)) < 0.5 ? -1.0 : 1.0;
				float lb = 60.0 + 100.0 * alea(vec2(fb, g + 9.0));
				if (q.x < xb || q.x > xb + lb) {
					continue;
				}
				float s = (q.x - xb) / lb;                   // 0 au départ, 1 au bout
				float yb = ecart(xb, L, g) + cote * s * (22.0 + 40.0 * alea(vec2(fb, g + 4.0)))
						+ 7.0 * brisee(s * 6.0, g + fb * 3.1);
				float d_b = abs(q.y - yb);
				float fin = 1.0 - s;
				ajout += blanc * couvre(d_b - epaisseur * 0.35 * fin, px) * I * fin;
				ajout += rouge * exp(-d_b / 7.0) * I * 0.6 * fin;
			}
		}
		// l'éclat au point d'impact
		float an = atan(r.y, r.x);
		float rayons = pow(abs(cos(an * 3.0 + graine)), 6.0);
		float d_eclat = rr - (12.0 + 26.0 * rayons) * (1.0 - frappe * 0.6);
		ajout += blanc * couvre(d_eclat, px) * I * dehors;
		ajout += rouge * exp(-rr / 26.0) * I * 1.1 * sous;
		// la lumière qui court sur la surface touchée
		if (surface) {
			vec2 tg = vec2(-normale.y, normale.x);
			float court = exp(-abs(dot(r, normale) - 1.5) / 2.5) * exp(-abs(dot(r, tg)) / (40.0 + 140.0 * frappe));
			ajout += blanc * court * I * 0.9 * sous;
		}
		// la lumière au départ, et toute la bande qui s'éclaire un instant
		ajout += rouge * exp(-pow(length(q) / 30.0, 2.0)) * I * 0.8;
		ajout += rouge * smoothstep(largeur * 0.9, 0.0, abs(q.y)) * le_long * I * 0.1;
	}

	// ===================== LA TRACE =====================
	if (trace > 0.0) {
		// la rémanence le long du tir
		ajout += rouge * exp(-abs(q.y) / 4.0) * le_long * pow(1.0 - trace, 3.0) * 0.45;
		vec2 n0 = surface ? normale : vec2(-1.0, 0.0);
		if (surface) {
			// la brûlure sur la surface, qui refroidit
			vec2 tg = vec2(-normale.y, normale.x);
			float le_long_mur = dot(r, tg);
			float xt = clamp(le_long_mur / (largeur * 0.45), -1.0, 1.0);
			float demi_b = 1.0 + 1.6 * sqrt(max(1.0 - xt * xt, 0.0));
			float d_b = max(abs(dot(r, normale) - demi_b) - demi_b, abs(le_long_mur) - largeur * 0.45);
			float cb = couvre(d_b, px) * dehors * (1.0 - smoothstep(0.6, 1.0, trace));
			rgb = mix(rgb, brulure.rgb, cb);
			alpha = max(alpha, cb * 0.85);
			ajout += mix(blanc, rouge, trace) * exp(-max(d_b, 0.0) / 4.0) * pow(1.0 - trace, 2.0) * 0.8 * sous;
		}
		// des étincelles, renvoyées par la surface, qui retombent en maigrissant
		float t = trace * 0.6;
		for (int k = 0; k < 9; k++) {
			float fk = float(k);
			float a = alea(vec2(fk, graine + 11.0));
			vec2 v0 = tourner(n0, (a - 0.5) * 2.4) * (170.0 + 260.0 * alea(vec2(fk + 3.0, graine)));
			vec2 pos = v0 * t + bas * (0.5 * 1500.0 * t * t);
			vec2 dir = normalize(v0 + bas * (1500.0 * t));
			float rv = clamp(trace * (1.0 + 0.6 * alea(vec2(fk, 5.0))), 0.0, 1.0);
			float lng = mix(8.0, 14.0, a) * (1.0 - 0.5 * rv);
			float demi = 1.5 * (1.0 - rv * rv);
			vec2 d = r - pos;
			float f = fuseau(dot(d, dir), d.x * dir.y - d.y * dir.x, -lng, 0.0, demi, 0.7);
			float ce = couvre(-f, px) * dehors;
			rgb = mix(rgb, mix(blanc, rouge, smoothstep(0.2, 0.9, rv)), ce);
			alpha = max(alpha, ce);
		}
	}

	// la lumière s'éteint avant le bord du rectangle (aucun carré)
	float bord = min(min(pix.x, taille.x - pix.x), min(pix.y, taille.y - pix.y));
	ajout *= smoothstep(0.0, 16.0, bord);
	COLOR = vec4(rgb * alpha + ajout, alpha);
}
