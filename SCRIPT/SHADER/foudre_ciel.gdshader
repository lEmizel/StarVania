shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;
// FOUDRE DU CIEL (2 oct. 2026, piège « pilier de foudre », idée de Kaoru) —
// l'éclair que le pilier appelle sur le joueur, de la même famille que l'arc de
// la Lame de foudre (cœur blanc, lueur bleue, brins brisés). Dessiné dans un
// rectangle debout : le POINT D'IMPACT au sol est `sol`, le ciel en haut.
// Piloté par foudre_ciel.gd. Trois temps :
//   • AVERTISSEMENT (`avert` 0 → 1) : une marque crépitante sur l'arête du sol,
//     de petites étincelles qui sautent dessus, et un TRAIT DE VISÉE pointillé
//     qui descend du ciel, de plus en plus pressant — plein et vif à la fin.
//   • FRAPPE (`frappe` 0 → 1) : un gros éclair brisé du ciel au sol, avec ses
//     branches, qui crépite (il change de forme plusieurs fois) ; un éclat au
//     point d'impact, un éclair de lumière qui court sur le sol.
//   • TRACE (`trace` 0 → 1) : une brûlure sur le sol qui refroidit, des
//     étincelles qui rebondissent en maigrissant (les fuseaux de la griffe).
// Vue de côté (comme les décors) : rien n'est dessiné sous l'arête du sol, seule
// la lueur y déborde un peu. Tout s'ajoute en lumière (alpha prémultiplié).

uniform vec2 taille = vec2(300.0, 760.0);
uniform vec2 sol = vec2(150.0, 720.0);       // le point d'impact (au ras du sol) dans le rectangle
uniform float hauteur = 700.0;               // du ciel au sol (px)
uniform float largeur = 70.0;                // la bande frappée (px)
// --- fournis par foudre_ciel.gd ---
uniform float avert : hint_range(0.0, 1.0) = 0.0;
uniform float frappe : hint_range(0.0, 1.0) = 0.0;
uniform float trace : hint_range(0.0, 1.0) = 0.0;
uniform float temps = 0.0;
uniform float graine = 0.0;
// --- l'allure ---
uniform float ampleur = 26.0;                // combien l'éclair s'écarte de la verticale (px)
uniform float epaisseur = 3.2;               // le cœur blanc (px)
uniform float cadence = 14.0;                // l'éclair change de forme… fois par seconde
uniform float lueur_mur = 0.35;
uniform vec4 couleur : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 couleur_foudre : source_color = vec4(0.45, 0.72, 1.0, 1.0);
uniform vec4 brulure : source_color = vec4(0.1, 0.1, 0.14, 1.0);


float couvre(float d, float px) {
	return clamp(0.5 - d / px, 0.0, 1.0);
}

float alea(vec2 p) {
	p = fract(p * vec2(443.897, 441.423));
	p += dot(p, p.yx + 19.19);
	return fract((p.x + p.y) * p.x);
}

// un hasard ENTIER, exact : deux appels sur le même entier rendent la même
// valeur au bit près. Avec un hasard flottant, le sommet calculé depuis le
// segment du dessous et celui du dessus ne tombaient pas pareil une fois
// compilés (plus l'entier est grand, pire c'est) : le tronc sautait d'une ligne
// à l'autre et sa lueur s'étalait en LIGNES HORIZONTALES au-dessus de l'impact.
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

// l'écart du tronc à la verticale, à `y` px au-dessus du sol : nul au point
// d'impact, libre en haut. En PIXELS (un sommet tous les ~78 px, un petit tous
// les ~31) et pas en part de la hauteur : l'éclair part de très haut (une
// hauteur d'écran au-dessus de la vue, pour qu'on n'en voie jamais le bout en
// sautant), sa forme près du sol ne doit pas s'étirer pour autant.
float ecart(float y, float g) {
	float z = brisee(y / 78.0, g) + 0.5 * brisee(y / 31.0 + 4.7, g + 1.3);
	return ampleur * z * smoothstep(0.0, 56.0, y);
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

void fragment() {
	vec2 pix = UV * taille;
	float px = max(fwidth(pix.x), 0.001);
	vec2 q = pix - sol;                    // px depuis le point d'impact, +y vers le bas
	float y_up = -q.y;                     // hauteur au-dessus du sol
	float au_dessus = step(q.y, 0.5);
	float sous = q.y > 0.0 ? exp(-q.y / 7.0) * lueur_mur : 1.0;
	vec3 rgb = vec3(0.0);
	float alpha = 0.0;
	vec3 ajout = vec3(0.0);
	vec3 bleu = couleur_foudre.rgb;
	vec3 blanc = couleur.rgb;

	// ===================== L'AVERTISSEMENT =====================
	if (avert > 0.0 && frappe <= 0.0) {
		float presse = avert * avert;
		float vif = 0.55 + 0.45 * sin(temps * (10.0 + 40.0 * presse));
		// la marque sur l'arête : une ligne plus épaisse au milieu
		float xr = clamp(q.x / (largeur * 0.5), -1.0, 1.0);
		float demi_l = 0.8 + 1.6 * sqrt(max(1.0 - xr * xr, 0.0));
		float d_marque = max(abs(q.y + demi_l) - demi_l, abs(q.x) - largeur * 0.5);
		float cm = couvre(d_marque, px) * au_dessus;
		rgb = mix(rgb, mix(bleu, blanc, presse), cm);
		alpha = max(alpha, cm * (0.45 + 0.55 * avert) * vif);
		ajout += bleu * exp(-max(d_marque, 0.0) / 6.0) * (0.25 + 0.6 * avert) * vif * sous;
		// de petites étincelles qui sautent sur la marque
		for (int k = 0; k < 5; k++) {
			float fk = float(k);
			float tick = floor(temps * 16.0 + fk * 0.37);
			float x0 = (alea(vec2(tick, fk + graine)) - 0.5) * largeur;
			float h0 = 4.0 + 10.0 * alea(vec2(fk, tick + 3.0)) * (0.4 + avert);
			vec2 a = vec2(x0, 0.0);
			vec2 b = vec2(x0 + (alea(vec2(tick, fk + 7.0)) - 0.5) * 8.0, -h0 * 0.5);
			vec2 c = vec2(x0 + (alea(vec2(tick + 1.0, fk)) - 0.5) * 10.0, -h0);
			float de = min(segment(q, a, b), segment(q, b, c)) - 0.5;
			ajout += blanc * couvre(de, px) * avert * au_dessus;
		}
		// le trait de visée qui descend du ciel : pointillé qui file vers le bas,
		// puis plein et vif sur la fin
		if (y_up >= 0.0 && y_up <= hauteur) {
			float tiret = step(0.45, fract(y_up / 22.0 + temps * 3.5));
			float plein = smoothstep(0.82, 0.95, avert);
			float force = mix(tiret * 0.55, 1.0, plein) * smoothstep(0.0, 0.25, avert);
			float d_v = abs(q.x) - mix(0.6, 1.1, plein);
			ajout += mix(bleu, blanc, plein) * couvre(d_v, px) * force * mix(0.5, 1.0, exp(-y_up / 900.0));
			ajout += bleu * exp(-abs(q.x) / 5.0) * force * 0.25;
		}
	}

	// ===================== LA FRAPPE =====================
	if (frappe > 0.0 && trace <= 0.0) {
		float g = graine + floor(frappe * 0.28 * cadence) * 7.13;
		// il crépite : quelques éclipses rapides, plus fort au début
		float strobe = 0.65 + 0.35 * step(0.35, fract(frappe * 6.0));
		float I = pow(1.0 - frappe, 0.6) * strobe;
		if (y_up >= 0.0 && y_up <= hauteur) {
			// le tronc
			// sa vraie distance : aux segments du tronc échantillonné tous les 6 px
			// autour de cette hauteur (une distance « horizontale ÷ pente »
			// s'étalait en traînées horizontales aux angles vifs)
			float d_tronc = 100000.0;
			float y0 = clamp(y_up - 24.0, 0.0, hauteur);
			vec2 sa = vec2(ecart(y0, g), y0);
			for (int k = 1; k <= 8; k++) {
				float yk = clamp(y_up - 24.0 + float(k) * 6.0, 0.0, hauteur);
				vec2 sb = vec2(ecart(yk, g), yk);
				d_tronc = min(d_tronc, segment(vec2(q.x, y_up), sa, sb));
				sa = sb;
			}
			float epais = epaisseur * mix(1.2, 0.7, clamp(y_up / 700.0, 0.0, 1.0));
			ajout += blanc * couvre(d_tronc - epais * 0.5, px) * I * 1.4;
			ajout += bleu * exp(-d_tronc / 9.0) * I * 0.9;
			ajout += bleu * exp(-d_tronc / 28.0) * I * 0.35;
			// les branches : elles partent du tronc et descendent en s'écartant
			for (int b = 0; b < 3; b++) {
				float fb = float(b);
				// les branches partent entre 220 et 540 px au-dessus du sol (là où on les voit)
				float yb = 220.0 + 320.0 * alea(vec2(fb, g + 2.0));
				float cote = alea(vec2(fb + 5.0, g)) < 0.5 ? -1.0 : 1.0;
				float lb = 70.0 + 110.0 * alea(vec2(fb, g + 9.0));
				if (y_up > yb || y_up < yb - lb) {
					continue;
				}
				float s = (yb - y_up) / lb;                    // 0 au départ, 1 au bout
				float xb = ecart(yb, g) + cote * s * (30.0 + 60.0 * alea(vec2(fb, g + 4.0)))
					+ 9.0 * brisee(s * 6.0, g + fb * 3.1);
				float d_b = abs(q.x - xb);
				float fin = 1.0 - s;
				ajout += blanc * couvre(d_b - epaisseur * 0.35 * fin, px) * I * fin;
				ajout += bleu * exp(-d_b / 7.0) * I * 0.6 * fin;
			}
		}
		// l'éclat au point d'impact, et la lumière qui court sur le sol
		float r = length(q);
		float an = atan(q.y, q.x);
		float rayons = pow(abs(cos(an * 3.0 + graine)), 6.0);
		float d_eclat = r - (14.0 + 30.0 * rayons) * (1.0 - frappe * 0.6);
		ajout += blanc * couvre(d_eclat, px) * I * au_dessus;
		ajout += bleu * exp(-r / 26.0) * I * 1.1 * sous;
		float sur_sol = exp(-abs(q.y + 1.5) / 2.5) * exp(-abs(q.x) / (40.0 + 140.0 * frappe));
		ajout += blanc * sur_sol * I * 0.9 * sous;
		// toute la bande s'éclaire un instant
		ajout += bleu * smoothstep(largeur * 0.9, 0.0, abs(q.x)) * step(0.0, y_up) * exp(-y_up / 500.0) * I * 0.12;
	}

	// ===================== LA TRACE =====================
	if (trace > 0.0) {
		// la brûlure sur l'arête, qui refroidit
		float xr = clamp(q.x / (largeur * 0.4), -1.0, 1.0);
		float demi_b = 1.0 + 1.6 * sqrt(max(1.0 - xr * xr, 0.0));
		float d_b = max(abs(q.y + demi_b) - demi_b, abs(q.x) - largeur * 0.4);
		float cb = couvre(d_b, px) * au_dessus * (1.0 - smoothstep(0.6, 1.0, trace));
		rgb = mix(rgb, brulure.rgb, cb);
		alpha = max(alpha, cb * 0.85);
		ajout += mix(blanc, bleu, trace) * exp(-max(d_b, 0.0) / 4.0) * pow(1.0 - trace, 2.0) * 0.8 * sous;
		// des étincelles qui rebondissent en maigrissant
		float t = trace * 0.7;
		for (int k = 0; k < 10; k++) {
			float fk = float(k);
			float a = alea(vec2(fk, graine + 11.0));
			vec2 v0 = vec2((a - 0.5) * 520.0, -(160.0 + 260.0 * alea(vec2(fk + 3.0, graine))));
			vec2 pos = v0 * t + vec2(0.0, 0.5 * 1500.0 * t * t);
			if (pos.y > 0.0) {
				pos.y = -abs(pos.y) * 0.3;               // un rebond sur le sol
			}
			vec2 dir = normalize(v0 + vec2(0.0, 1500.0 * t));
			float rr = clamp(trace * (1.0 + 0.6 * alea(vec2(fk, 5.0))), 0.0, 1.0);
			float lng = mix(8.0, 14.0, a) * (1.0 - 0.5 * rr);
			float demi = 1.5 * (1.0 - rr * rr);
			vec2 d = q - pos;
			float f = fuseau(dot(d, dir), d.x * dir.y - d.y * dir.x, -lng, 0.0, demi, 0.7);
			float ce = couvre(-f, px) * au_dessus;
			rgb = mix(rgb, mix(blanc, bleu, smoothstep(0.2, 0.9, rr)), ce);
			alpha = max(alpha, ce);
		}
	}

	COLOR = vec4(rgb * alpha + ajout, alpha);
}
