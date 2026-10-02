shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;
// PILIER DE FOUDRE (2 oct. 2026, piège imaginé par Kaoru) — le pilier, vu de
// côté : un OBÉLISQUE de pierre, une RUNE d'éclair gravée sur sa face, et un
// CRISTAL qui flotte au-dessus. Visuel PROVISOIRE (Kaoru pourra le dessiner) ;
// piloté par SCRIPT/INTERACTIBLE/pilier_foudre.gd :
//   • `eveil` : il est à l'écran, il veille — le cristal luit doucement ;
//   • `charge` (0 → 1) : il va appeler la foudre — la rune se REMPLIT de lumière
//     de bas en haut, le cristal s'embrase, de petits arcs crépitent entre le
//     cristal et la pointe ;
//   • `appel` (1 → 0) : l'éclair d'appel part vers le ciel — tout flashe.
// Aplat + encre pour la pierre ; la lumière s'AJOUTE (alpha prémultiplié).

uniform vec2 taille = vec2(140.0, 300.0);
uniform vec2 base = vec2(70.0, 290.0);       // le pied du pilier, au ras du sol, dans le rectangle
uniform float eveil : hint_range(0.0, 1.0) = 0.0;
uniform float charge : hint_range(0.0, 1.0) = 0.0;
uniform float appel : hint_range(0.0, 1.0) = 0.0;
uniform float temps = 0.0;

uniform float largeur_pied = 22.0;           // demi-largeur au pied (px)
uniform float largeur_haut = 15.0;           // demi-largeur en haut du fût
uniform float hauteur_fut = 170.0;
uniform float hauteur_pointe = 22.0;
uniform float hauteur_cristal = 222.0;       // le milieu du cristal, au-dessus du pied
uniform vec2 cristal = vec2(9.0, 16.0);      // ses demi-dimensions (px)
uniform float encre = 1.3;

uniform vec4 pierre : source_color = vec4(0.25, 0.28, 0.35, 1.0);
uniform vec4 pierre_ombre : source_color = vec4(0.17, 0.19, 0.25, 1.0);
uniform vec4 couleur_encre : source_color = vec4(0.06, 0.06, 0.1, 1.0);
uniform vec4 couleur : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 couleur_foudre : source_color = vec4(0.45, 0.72, 1.0, 1.0);


float couvre(float d, float px) {
	return clamp(0.5 - d / px, 0.0, 1.0);
}

float alea(vec2 p) {
	p = fract(p * vec2(443.897, 441.423));
	p += dot(p, p.yx + 19.19);
	return fract((p.x + p.y) * p.x);
}

float segment(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

vec4 sur(vec4 dst, vec4 src) {
	float a = src.a + dst.a * (1.0 - src.a);
	vec3 rgb = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 0.0001);
	return vec4(rgb, a);
}

void fragment() {
	vec2 pix = UV * taille;
	float px = max(fwidth(pix.x), 0.001);
	vec2 q = pix - base;                     // px depuis le pied, +y vers le bas
	float h = -q.y;                          // hauteur au-dessus du sol
	vec4 c = vec4(pierre.rgb, 0.0);
	vec3 ajout = vec3(0.0);
	vec3 bleu = couleur_foudre.rgb;
	vec3 blanc = couleur.rgb;
	float vif = clamp(eveil * 0.3 + charge * 0.7 + appel, 0.0, 1.5);

	// ===================== L'OBÉLISQUE =====================
	// le fût : un trapèze ; la pointe : un triangle
	float t = clamp(h / hauteur_fut, 0.0, 1.0);
	float demi = mix(largeur_pied, largeur_haut, t);
	float d_fut = max(abs(q.x) - demi, max(-h, h - hauteur_fut));
	float tp = clamp((h - hauteur_fut) / hauteur_pointe, 0.0, 1.0);
	float d_pointe = max(abs(q.x) - largeur_haut * (1.0 - tp), max(hauteur_fut - h, h - hauteur_fut - hauteur_pointe));
	// un socle un peu plus large
	float d_socle = max(abs(q.x) - largeur_pied - 5.0, max(-h, h - 12.0));
	float d_pilier = min(min(d_fut, d_pointe), d_socle);
	c = sur(c, vec4(couleur_encre.rgb, couvre(d_pilier - encre, px)));
	c = sur(c, vec4(pierre.rgb, couvre(d_pilier, px)));
	// le flanc droit dans l'ombre (aplat)
	c = sur(c, vec4(pierre_ombre.rgb, couvre(max(d_pilier + 0.5, -(q.x - demi * 0.35)), px)));
	// les joints du socle et du fût
	float joint = min(abs(h - 12.0), abs(h - hauteur_fut)) - 0.6;
	c = sur(c, vec4(couleur_encre.rgb, couvre(max(joint, d_pilier + 0.5), px) * 0.8));

	// ===================== LA RUNE D'ÉCLAIR GRAVÉE =====================
	// un zigzag au milieu de la face, qui se remplit de lumière de bas en haut
	vec2 r0 = vec2(0.0, -26.0);
	vec2 r1 = vec2(7.0, -62.0);
	vec2 r2 = vec2(-6.0, -96.0);
	vec2 r3 = vec2(6.0, -128.0);
	vec2 r4 = vec2(0.0, -158.0);
	float d_rune = min(min(segment(q, r0, r1), segment(q, r1, r2)), min(segment(q, r2, r3), segment(q, r3, r4))) - 1.6;
	float rempli = step((h - 26.0) / 132.0, charge + appel) ;
	float allume = clamp(eveil * 0.25 + rempli * (0.6 + 0.4 * charge) + appel, 0.0, 1.0);
	c = sur(c, vec4(mix(couleur_encre.rgb, mix(bleu, blanc, charge * 0.5 + appel), allume), couvre(d_rune, px)));
	ajout += bleu * exp(-max(d_rune, 0.0) / 4.0) * allume * 0.6 * step(d_pilier, 0.0);

	// ===================== LE CRISTAL QUI FLOTTE =====================
	float flotte = sin(temps * 2.2) * 3.0;
	vec2 qc = q - vec2(0.0, -(hauteur_cristal + flotte));
	float d_cristal = (abs(qc.x) / cristal.x + abs(qc.y) / cristal.y - 1.0) * min(cristal.x, cristal.y) * 0.8;
	vec3 teinte_c = mix(mix(pierre.rgb * 1.3, bleu, clamp(eveil * 0.5 + charge, 0.0, 1.0)), blanc, appel);
	c = sur(c, vec4(couleur_encre.rgb, couvre(d_cristal - encre, px)));
	c = sur(c, vec4(teinte_c, couvre(d_cristal, px)));
	// sa facette claire
	c = sur(c, vec4(mix(teinte_c, blanc, 0.5), couvre(max(d_cristal + 1.0, qc.x), px) * 0.5 * (0.3 + vif * 0.7)));
	float rc = length(qc);
	// une lueur qui retombe VRAIMENT à zéro avant le bord du rectangle (en
	// exp(-r/30), il en restait ~13 % au bord à l'appel : la lueur était CARRÉE)
	ajout += bleu * exp(-pow(rc / (16.0 + 12.0 * charge), 2.0)) * vif * 0.9;
	ajout += blanc * exp(-rc / 6.0) * appel * 1.2;

	// ===================== LES PETITS ARCS (il se charge) =====================
	if (charge > 0.02 || appel > 0.02) {
		float tick = floor(temps * 18.0);
		vec2 a = vec2(0.0, -(hauteur_fut + hauteur_pointe) + 2.0);
		vec2 b = vec2(0.0, -(hauteur_cristal + flotte) + cristal.y - 1.0);
		for (int k = 0; k < 2; k++) {
			float fk = float(k);
			vec2 m1 = mix(a, b, 0.33) + vec2((alea(vec2(tick, fk)) - 0.5) * 16.0, 0.0);
			vec2 m2 = mix(a, b, 0.66) + vec2((alea(vec2(tick + 3.0, fk)) - 0.5) * 16.0, 0.0);
			float d_arc = min(min(segment(q, a, m1), segment(q, m1, m2)), segment(q, m2, b)) - 0.6;
			float force = (charge + appel) * step(0.3, alea(vec2(tick, fk + 9.0)));
			ajout += blanc * couvre(d_arc, px) * force;
			ajout += bleu * exp(-max(d_arc, 0.0) / 5.0) * force * 0.5;
		}
	}

	// filet de sécurité : la lumière s'éteint en approchant des bords du rectangle
	float bord = min(min(pix.x, taille.x - pix.x), min(pix.y, taille.y - pix.y));
	ajout *= smoothstep(0.0, 16.0, bord);
	COLOR = vec4(c.rgb * c.a + ajout, c.a);
}
