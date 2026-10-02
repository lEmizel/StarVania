shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;
// PINCE DE GRAPPIN (2 oct. 2026, d'après le croquis de Kaoru « fermé / ouvert »)
// — le point d'accroche du grappin, vu de face : un MOYEU rond et TROIS
// BRANCHES (une en haut, deux en bas) qui s'écartent quand on peut s'y
// accrocher. Piloté par pince_grappin.gd (`ouverture`, `lumiere`, `temps`).
//
// V3 « MAGIQUE » (Kaoru : « moins plastique, plus magique, comme le wall griffe,
// avec un effet sympa ») : plus de reflets en plastique. Le corps est d'un rouge
// SOMBRE, et c'est la LUMIÈRE qui le dessine, dans la famille de la trace de
// griffe (traits nets, blanc chaud → lilas, des étincelles en fuseau qui
// MAIGRISSENT au lieu de s'estomper, une lentille qui vacille) :
//   • FERMÉE, endormie : un liseré rouge clair, à peine.
//   • OUVERTE : le liseré devient blanc-lilas, l'énergie COURT dans les branches
//     vers leurs bouts, des étincelles en jaillissent, un anneau de runes
//     s'allume autour de l'œil BLEU, une lentille croisée vacille au centre.
//   • TENUE (fermée mais allumée : le câble y tient) : l'énergie et les
//     étincelles CONVERGENT vers le moyeu, elle aspire le câble.
// La lumière s'AJOUTE (alpha prémultiplié) : halo bleu et aura lilas débordent
// sur le décor.

uniform vec2 taille = vec2(96.0, 96.0);       // le rectangle (px), la pince au milieu
uniform float ouverture : hint_range(-0.2, 1.3) = 0.0;   // 0 fermée, 1 ouverte (plus pendant le rebond)
uniform float lumiere : hint_range(0.0, 1.0) = 0.0;
uniform float temps = 0.0;

// --- les formes (px) ---
uniform float rayon_moyeu = 10.0;
uniform float branche_r_pied = 3.6;           // rayon du pied d'une branche (côté moyeu)
uniform float branche_r_bout = 5.4;           // rayon de son bout : des lobes ovales, comme le croquis
uniform float branche_longueur_fermee = 8.0;  // fermée : des lobes trapus qui épousent le moyeu
uniform float branche_longueur_ouverte = 15.0;
uniform float branche_depart_fermee = 6.0;    // du centre au pied de la branche, fermée
uniform float branche_depart_ouverte = 12.5;  // … ouverte (le pied sort du moyeu)
uniform float torsion = 0.05;                 // les branches tournent à peine en s'ouvrant (rad)
uniform float encre = 1.3;                    // le trait d'encre autour du corps (px)
uniform float rayon_oeil = 3.2;
uniform float halo = 15.0;                    // rayon de la lueur bleue (px)

uniform vec4 couleur : source_color = vec4(0.74, 0.06, 0.12, 1.0);   // le rouge du corps (assombri par `corps_sombre`)
uniform vec4 sombre : source_color = vec4(0.42, 0.02, 0.07, 1.0);    // le cœur des formes, plus profond
uniform vec4 clair : source_color = vec4(1.0, 0.45, 0.45, 1.0);      // le liseré quand elle dort
uniform vec4 couleur_encre : source_color = vec4(0.1, 0.01, 0.03, 1.0);
uniform vec4 oeil_eteint : source_color = vec4(0.07, 0.06, 0.14, 1.0);
uniform vec4 bleu_coeur : source_color = vec4(0.82, 0.97, 1.0, 1.0);
uniform vec4 bleu : source_color = vec4(0.2, 0.62, 1.0, 1.0);

// --- la magie (v3) ---
uniform float corps_sombre : hint_range(0.2, 1.0) = 0.5;    // le corps assombri : la lumière ressort
uniform vec4 couleur_magie : source_color = vec4(1.0, 1.0, 1.0, 1.0);        // chaud : blanc (comme la griffe)
uniform vec4 couleur_magie_fin : source_color = vec4(0.8, 0.62, 1.0, 1.0);   // froid : lilas (comme la griffe)
uniform float bord : hint_range(0.3, 3.0) = 1.1;            // le liseré de lumière (px)
uniform float veines : hint_range(0.0, 1.0) = 0.9;          // l'énergie qui court dans les branches
uniform float flux = 30.0;                                   // sa vitesse (px/s)
uniform float etincelles : hint_range(0.0, 1.0) = 0.8;      // part des étincelles qui partent
uniform float vie_etincelles = 0.55;                         // (s)
uniform float vitesse_etincelles = 30.0;                     // (px/s)
uniform float taille_etincelles = 1.0;
uniform float aura : hint_range(0.0, 1.0) = 0.35;           // la lueur lilas autour du corps

const int NB_ETINCELLES = 14;


// `src` posé par-dessus `dst` (alpha droit)
vec4 sur(vec4 dst, vec4 src) {
	float a = src.a + dst.a * (1.0 - src.a);
	vec3 rgb = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 0.0001);
	return vec4(rgb, a);
}

// couverture d'une forme dont la distance signée est `d` (négative dedans)
float couvre(float d, float px) {
	return clamp(0.5 - d / px, 0.0, 1.0);
}

// une capsule à rayons inégaux : de l'origine (r1) à (0, h) (r2) ; négative dedans
float capsule(vec2 p, float r1, float r2, float h) {
	p.x = abs(p.x);
	float b = (r1 - r2) / h;
	float a = sqrt(max(1.0 - b * b, 0.0));
	float k = dot(p, vec2(-b, a));
	if (k < 0.0) return length(p) - r1;
	if (k > a * h) return length(p - vec2(0.0, h)) - r2;
	return dot(p, vec2(a, b)) - r1;
}

// hash 1D sans sin : une valeur stable par indice
float alea(float n) {
	n = fract(n * 0.1031);
	n *= n + 33.33;
	n *= n + n;
	return fract(n);
}

// bruit 1D lissé, entre 0 et 1
float bruit(float x) {
	float i = floor(x);
	float f = fract(x);
	return mix(alea(i), alea(i + 1.0), f * f * (3.0 - 2.0 * f));
}

// un FUSEAU couché sur l'axe u, de u0 à u1, pointu aux deux bouts (celui de la
// trace de griffe) ; `demi` = demi-largeur au ventre, placé à la fraction
// `ventre` de sa longueur ; positive dedans
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
	vec2 q = pix - taille * 0.5;
	float o = ouverture;
	float o01 = clamp(o, 0.0, 1.0);
	float m = clamp(lumiere, 0.0, 1.0);                       // éveillée
	float serre = m * (1.0 - smoothstep(0.15, 0.6, o));       // allumée mais fermée : elle tient le câble
	float vacille = 0.84 + 0.16 * bruit(temps * 13.0);
	vec4 c = vec4(couleur.rgb, 0.0);
	vec3 ajout = vec3(0.0);                                   // la lumière ajoutée (prémultipliée)

	float d0 = mix(branche_depart_fermee, branche_depart_ouverte, o);
	float longueur = mix(branche_longueur_fermee, branche_longueur_ouverte, o);
	longueur += sin(temps * 3.0) * 0.4 * o01;                // ouverte, elle respire à peine
	float th0 = -1.5708 + torsion * o;

	// ===================== LE CORPS : TROIS BRANCHES ET LE MOYEU =====================
	float d_corps = 100000.0;
	float veine = 0.0;
	// l'énergie court vers le bout quand elle s'ouvre, vers le moyeu quand elle serre
	float sens = serre > m * 0.5 ? -1.0 : 1.0;
	for (int k = 0; k < 3; k++) {
		float th = th0 + float(k) * 2.0944;
		vec2 u = vec2(cos(th), sin(th));
		vec2 n = vec2(-u.y, u.x);
		vec2 a = q - u * d0;
		vec2 l = vec2(dot(a, n), dot(a, u));
		float db = capsule(l, branche_r_pied, branche_r_bout, longueur);
		d_corps = min(d_corps, db);
		// la VEINE : un fil dans l'axe, que des ondes parcourent
		float onde = 0.5 + 0.5 * sin((l.y - sens * temps * flux) * 0.6 + float(k) * 2.1);
		float fil = couvre(abs(l.x) - 0.42, px) * couvre(db + 1.5, px) * step(-d0 * 0.4, l.y);
		veine = max(veine, fil * (0.3 + 0.7 * pow(onde, 3.0)));
	}
	float r = length(q);
	float dm = r - rayon_moyeu;
	d_corps = min(d_corps, dm);

	// le corps sombre, plus profond au cœur des formes, et son trait d'encre fin
	c = sur(c, vec4(couleur_encre.rgb, couvre(d_corps - encre, px)));
	vec3 corps = mix(couleur.rgb * corps_sombre, sombre.rgb * 0.75, smoothstep(0.0, 5.0, -d_corps) * 0.45);
	c = sur(c, vec4(corps, couvre(d_corps, px)));

	// le LISERÉ de lumière, juste à l'intérieur du bord : rouge clair qui
	// somnole, puis blanc-lilas qui vacille
	float lisere_d = abs(d_corps + bord * 0.5 + 0.25) - bord * 0.5;
	vec3 teinte_bord = mix(clair.rgb, mix(couleur_magie.rgb, couleur_magie_fin.rgb, 0.35), m);
	float force_bord = mix(0.32 + 0.1 * sin(temps * 1.6), vacille, m) * (1.0 + 0.35 * serre);
	c = sur(c, vec4(teinte_bord, couvre(lisere_d, px) * clamp(force_bord, 0.0, 1.0)));

	// les VEINES
	c = sur(c, vec4(mix(couleur_magie_fin.rgb, couleur_magie.rgb, veine), veine * m * veines));

	// ===================== L'ANNEAU DE RUNES AUTOUR DE L'ŒIL =====================
	float r_rune = rayon_oeil + 2.6;
	float ang = atan(q.y, q.x);
	float tiers = fract((ang - th0) / 2.0944 + 0.5) - 0.5;   // 0 face à une branche
	float trou = abs(tiers) * 2.0944 * r_rune - 1.7;          // une brèche face à chaque branche
	float rune = max(abs(r - r_rune) - 0.5, -trou);
	vec3 teinte_rune = mix(couleur_encre.rgb, mix(couleur_magie_fin.rgb, couleur_magie.rgb, 0.4), m);
	c = sur(c, vec4(teinte_rune, couvre(rune, px) * mix(0.8, vacille, m)));

	// ===================== L'ŒIL : ÉTEINT, OU LA LUMIÈRE BLEUE =====================
	float pulse = 0.82 + 0.18 * sin(temps * 4.5);
	vec3 oeil = mix(oeil_eteint.rgb, mix(bleu.rgb, bleu_coeur.rgb, smoothstep(rayon_oeil, 0.0, r)), m);
	c = sur(c, vec4(oeil, couvre(r - rayon_oeil, px)));
	// la LENTILLE croisée qui vacille (comme l'éclat de la griffe)
	float l_h = rayon_oeil * 3.0 * vacille * (1.0 + 0.4 * serre);
	float f_h = fuseau(q.x, q.y, -l_h, l_h, 0.85, 0.5);
	float f_v = fuseau(q.y, q.x, -l_h * 0.55, l_h * 0.55, 0.7, 0.5);
	c = sur(c, vec4(couleur_magie.rgb, couvre(-max(f_h, f_v), px) * m));

	// ===================== LES ÉTINCELLES =====================
	// ouverte : elles jaillissent du bout des branches et filent vers l'extérieur ;
	// tenue : elles viennent de l'extérieur et CONVERGENT vers le moyeu ; elles
	// maigrissent en vieillissant (blanc → lilas)
	float sd_e = -1.0;
	float age_e = 0.0;
	float vivantes = m * max(smoothstep(0.3, 0.8, o), serre);
	if (vivantes > 0.001) {
		for (int j = 0; j < NB_ETINCELLES; j++) {
			float fj = float(j);
			float vie = vie_etincelles * (0.6 + 0.4 * alea(fj * 3.7 + 0.5));
			float t = temps / vie + alea(fj * 1.3 + 0.2);
			float cyc = floor(t);
			float r01 = fract(t);
			float h1 = alea(cyc * 1.7 + fj * 13.1);
			float h2 = alea(cyc * 2.9 + fj * 7.3 + 1.0);
			float h3 = alea(cyc * 4.1 + fj * 5.9 + 2.0);
			if (h3 > etincelles) {
				continue;
			}
			float th = th0 + floor(h1 * 3.0) * 2.0944 + (h2 - 0.5) * 0.9;
			vec2 dir = vec2(cos(th), sin(th));
			float age = r01 * vie;
			vec2 bout = dir * (d0 + longueur + branche_r_bout * 0.5);
			vec2 pos_sort = bout + dir * vitesse_etincelles * (0.6 + 0.8 * h2) * age;
			vec2 pos_entre = mix(dir * (rayon_moyeu + 20.0 + 10.0 * h2), dir * rayon_moyeu, r01);
			vec2 pos = mix(pos_sort, pos_entre, serre / max(m, 0.001));
			vec2 vdir = serre > m * 0.5 ? -dir : dir;
			float lng = taille_etincelles * mix(5.0, 9.0, h2) * (1.0 - 0.5 * r01);
			float demi = taille_etincelles * mix(0.9, 1.5, h1) * (1.0 - r01 * r01) * vivantes;
			vec2 e = q - pos;
			float f = fuseau(dot(e, vdir), e.x * vdir.y - e.y * vdir.x, -lng, 0.0, demi, 0.7);
			if (f > sd_e) {
				sd_e = f;
				age_e = r01;
			}
		}
	}
	float a_e = couvre(-sd_e, px);
	c = sur(c, vec4(mix(couleur_magie.rgb, couleur_magie_fin.rgb, smoothstep(0.2, 0.9, age_e)), a_e));

	// ===================== LA LUMIÈRE QUI S'AJOUTE =====================
	vec3 rgb = c.rgb * c.a;
	float dehors = 1.0 - couvre(d_corps, px);
	// l'aura lilas autour du corps
	rgb += couleur_magie_fin.rgb * exp(-max(d_corps, 0.0) / 5.0) * aura * m * vacille * dehors;
	// le halo bleu de l'œil, et son cœur
	float lueur = exp(-pow(r / halo, 2.0) * 2.6) * m * pulse;
	rgb += bleu.rgb * lueur * 0.85 * (1.0 - couvre(dm, px) * 0.55);
	rgb += bleu_coeur.rgb * exp(-pow(r / (rayon_oeil * 1.4), 2.0)) * m * pulse * 0.6;
	COLOR = vec4(rgb, c.a);
}
