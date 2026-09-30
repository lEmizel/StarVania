shader_type canvas_item;
render_mode unshaded;
// EXPLOSION DE LA BOULE DE SANG — refaite le 30 sept. 2026 (l'ancienne était un
// fondu rond : « mollassonne »). Même famille que impact_blanc : aplats nets,
// liseré sombre, tout piloté par `progress`, des formes qui MAIGRISSENT au lieu
// de s'estomper. À poser sur un ColorRect CARRÉ, l'impact est au centre.
//
// La boule arrive dans le sens `direction`. DEUX COUCHES, l'une sur l'autre :
//
// L'IMPACT — le choc lui-même, plus clair que le sang (`chaleur`), sec, fini en un tiers
// du temps. C'est lui qui fait l'explosion :
//   • la LAME      — un éclair en travers du vol, comme la boule qui s'écrase
//                    à plat sur ce qu'elle touche ;
//   • les AIGUILLES — des traits pointus qui jaillissent en étoile, de presque
//                    rien à leur pleine longueur en trois images, plus longs
//                    vers l'arrière ;
//   • l'ONDE       — l'onde de choc, en quelques ARCS épais qui filent et
//                    s'amincissent (pas un cercle entier : ça ferait « cible »).
//
// LE SANG — ce que le choc projette, plus lent, qui reste après lui :
//   • les BRAS     — une étoile de bras à bout rond (du liquide, pas du verre) ;
//   • le CŒUR      — un disque plein, brûlant au milieu ;
//   • les GOUTTES  — des larmes projetées, qui freinent, RETOMBENT et
//                    s'affinent.
// `puissance` réduit le tout : 1 = un vrai impact, moins = la boule qui
// s'éteint toute seule en bout de course.

uniform float progress : hint_range(0.0, 1.0) = 0.0;

// --- fournis par bloodball_explosion.gd -------------------------------------
// sens de vol de la boule au moment de l'impact
uniform vec2 direction = vec2(1.0, 0.0);
uniform float puissance : hint_range(0.0, 1.0) = 1.0;
// une valeur par impact : deux explosions ne se ressemblent pas
uniform float graine = 0.0;
// ----------------------------------------------------------------------------

// --- l'impact ---
// l'éclair en travers du vol (0 = aucun)
uniform float lame : hint_range(0.0, 1.0) = 1.0;
// nombre d'aiguilles (0 = aucune)
uniform int nb_aiguilles : hint_range(0, 24) = 11;
// l'onde de choc (0 = aucune)
uniform float anneau : hint_range(0.0, 1.0) = 0.6;
// portée de l'impact, aiguilles et onde (0.5 = jusqu'au bord du rectangle)
uniform float portee_impact : hint_range(0.15, 0.5) = 0.4;
// 0 = l'impact est rouge sang, 1 = il est presque blanc
uniform float chaleur : hint_range(0.0, 1.0) = 0.4;
// --- le sang ---
// nombre de bras, et leur portée (0.5 = jusqu'au bord du rectangle)
uniform int nb_pointes : hint_range(3, 20) = 9;
uniform float rayon : hint_range(0.1, 0.5) = 0.33;
// grosseur des boules de sang (la largeur des bras à bout rond et le cœur)
uniform float grosseur_boules : hint_range(0.3, 1.5) = 0.75;
// nombre de gouttes, jusqu'où elles volent, et ce qui les fait retomber
uniform int nb_gouttes : hint_range(0, 20) = 14;
uniform float envol : hint_range(0.1, 0.5) = 0.42;
uniform float pesanteur : hint_range(0.0, 2.0) = 0.9;
// --- l'ensemble ---
// épaisseur de toutes les formes
uniform float epaisseur : hint_range(0.2, 2.0) = 1.0;
// l'éclat clair des toutes premières images (0 = aucun)
uniform float eclat : hint_range(0.0, 1.0) = 0.5;
// liseré sombre autour des formes (0 = aucun)
uniform float contour : hint_range(0.0, 1.0) = 0.5;
uniform vec4 core_color : source_color = vec4(1.0, 0.88, 0.6, 1.0);
uniform vec4 blood_color : source_color = vec4(0.8, 0.05, 0.05, 1.0);
uniform vec4 dark_color : source_color = vec4(0.28, 0.0, 0.05, 1.0);

// (PI et TAU sont fournis par le langage de shader de Godot)

const int MAX_GOUTTES = 20;
// nombre de secteurs de l'onde de choc (un arc au plus par secteur)
const int NB_ARCS = 5;
// part de l'épaisseur d'une forme que son liseré peut ajouter, au plus
const float PART_CONTOUR = 0.6;

// hash 1D sans sin : une valeur stable par bras, par aiguille ou par goutte
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

// Une LARME couchée sur l'axe u : fine en u0 (sa queue), ronde en u1 (sa tête).
// C'est la forme du SANG. Renvoie deux distances, positives dedans : (la
// forme, la forme épaissie de son liseré `c`).
vec2 larme(float u, float v, float u0, float u1, float demi, float c) {
	float s = (u - u0) / max(u1 - u0, 0.0001);
	if (u1 <= u0 || s <= 0.0) {
		return vec2(-length(vec2(u - u0, v)));
	}
	if (s >= 1.0) {
		return vec2(-length(vec2(u - u1, v)));
	}
	float large = demi * min(s / 0.7, sqrt((1.0 - s) / 0.3));
	return vec2(large, large + min(c, large * PART_CONTOUR)) - abs(v);
}

// Un FUSEAU couché sur l'axe u, de u0 à u1, POINTU aux deux bouts, le ventre à
// la fraction `ventre` de sa longueur. C'est la forme du CHOC. Mêmes deux
// distances que `larme`.
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

// pose une couleur par-dessus ce qui est déjà dessiné
void par_dessus(inout vec3 rgb, inout float a, vec3 teinte, float poids) {
	float total = poids + a * (1.0 - poids);
	rgb = (teinte * poids + rgb * a * (1.0 - poids)) / max(total, 0.0001);
	a = total;
}


void fragment() {
	vec2 p = UV - 0.5;
	float d = length(p);
	float ang = atan(p.y, p.x);
	float t = clamp(progress, 0.0, 1.0);
	float force = mix(0.55, 1.0, puissance);    // taille de l'ensemble
	// un pixel d'écran, en unités du rectangle : des bords nets à toute échelle
	float px = (fwidth(UV.x) + fwidth(UV.y)) * 0.75;
	float c = contour * 0.013;
	vec2 vol = normalize(direction + vec2(0.0001, 0.0));
	// le temps du choc : tout l'impact tient dans le premier tiers
	float tc = clamp(t / 0.34, 0.0, 1.0);
	float jaillit = 1.0 - pow(1.0 - tc, 3.0);

	// ===================== LE SANG =====================
	vec2 sang = vec2(-1.0);

	// les BRAS : un par secteur (on regarde aussi les deux voisins, un bras
	// large n'est jamais coupé par la frontière de son secteur)
	float ta = clamp(t / 0.6, 0.0, 1.0);
	float n = float(nb_pointes);
	float secteur = TAU / n;
	float tour = mod(ang + PI + graine * 2.4, TAU) / secteur;
	float idx0 = floor(tour);
	for (int k = -1; k <= 1; k++) {
		float idx = mod(idx0 + float(k), n);
		float h1 = alea(idx * 1.7 + graine);
		float h2 = alea(idx * 3.1 + graine * 1.3 + 5.0);
		float h3 = alea(idx * 5.3 + graine * 0.7 + 9.0);
		float delta = (tour - (idx0 + float(k) + 0.5 + (h3 - 0.5) * 0.5)) * secteur;
		// vers l'avant (dans la surface) le bras est court ; vers l'arrière et
		// les côtés il est long
		float vers_avant = dot(vec2(cos(ang - delta), sin(ang - delta)), vol);
		float r1 = rayon * force * (0.5 + 0.5 * h1) * mix(1.0, 0.5, smoothstep(0.0, 1.0, vers_avant))
				* (0.45 + 0.55 * jaillit);
		float r0 = r1 * 0.85 * ta;              // la base décolle : le bras s'en va
		float demi = epaisseur * grosseur_boules * force * (0.040 + 0.036 * h2) * (1.0 - ta * ta);
		sang = max(sang, larme(d * cos(delta), d * sin(delta), r0, r1, demi, c));
	}

	// le CŒUR : parti avant la moitié
	float r_coeur = 0.125 * mix(1.0, grosseur_boules, 0.6) * force * clamp(1.0 - t * 2.4, 0.0, 1.0);
	sang = max(sang, vec2(r_coeur, r_coeur + min(c, r_coeur * PART_CONTOUR)) - d);

	// les GOUTTES : lancées surtout vers l'arrière, elles freinent et retombent
	float retour = atan(-vol.y, -vol.x);
	for (int i = 0; i < MAX_GOUTTES; i++) {
		if (i >= nb_gouttes) {
			break;
		}
		float fi = float(i);
		float h1 = alea(fi * 1.7 + graine + 40.0);
		float h2 = alea(fi * 3.1 + graine * 1.3 + 45.0);
		float h3 = alea(fi * 5.3 + graine * 0.7 + 49.0);
		float h4 = alea(fi * 7.9 + graine * 2.1 + 43.0);
		float tau = clamp((t - 0.05 * h3) / (1.0 - 0.05 * h3), 0.0, 1.0);
		// éventail large autour du sens du retour, avec un petit coup vers le haut
		float a0 = retour + (h1 - 0.5) * 3.8;
		vec2 v0 = vec2(cos(a0), sin(a0)) * envol * force * (0.45 + 0.55 * h2) + vec2(0.0, -0.10 * force);
		float freine = 1.0 - (1.0 - tau) * (1.0 - tau);
		vec2 chute = vec2(0.0, pesanteur * 0.30 * force);
		vec2 pos = v0 * freine + chute * tau * tau;
		vec2 vit = v0 * 2.0 * (1.0 - tau) + chute * 2.0 * tau;
		vec2 dir = normalize(vit + vec2(0.0, 0.0001));
		// tête ronde en `pos`, queue derrière elle, d'autant plus longue qu'elle va vite
		float l = (0.03 + 0.085 * length(vit)) * (0.7 + 0.6 * h4);
		// le dessin s'arrête au bord du rectangle : une goutte qui s'en approche
		// (`pesanteur` ou `envol` poussés) s'affine avant lui au lieu d'y être
		// coupée net
		float bord = 1.0 - smoothstep(0.40, 0.48, max(abs(pos.x), abs(pos.y)));
		float demi = epaisseur * force * (0.016 + 0.018 * h4) * (1.0 - tau * tau * tau) * step(0.0001, tau) * bord;
		vec2 e = p - pos;
		sang = max(sang, larme(dot(e, dir), e.x * dir.y - e.y * dir.x, -l, 0.014, demi, c));
	}

	// ===================== L'IMPACT =====================
	vec2 choc = vec2(-1.0);

	// la LAME : en travers du vol, elle s'allonge d'un coup et s'amincit aussitôt
	vec2 travers = vec2(-vol.y, vol.x);
	float l_lame = 0.70 * portee_impact * force * (0.5 + 0.5 * jaillit);
	float demi_lame = lame * 0.05 * force * epaisseur * pow(1.0 - tc, 1.3);
	choc = max(choc, fuseau(dot(p, travers), dot(p, vol), -l_lame, l_lame, demi_lame, 0.5, c));

	// les AIGUILLES : même découpe en secteurs que les bras, autre tirage
	float na = float(max(nb_aiguilles, 1));
	float secteur_a = TAU / na;
	float tour_a = mod(ang + PI + graine * 4.1 + 1.3, TAU) / secteur_a;
	float idx_a = floor(tour_a);
	float tq = clamp(t / 0.62, 0.0, 1.0);       // elles survivent un peu au choc
	for (int k = -1; k <= 1; k++) {
		float idx = mod(idx_a + float(k), na);
		float h1 = alea(idx * 2.3 + graine + 70.0);
		float h2 = alea(idx * 4.7 + graine * 1.1 + 75.0);
		float h3 = alea(idx * 6.1 + graine * 0.9 + 79.0);
		float delta = (tour_a - (idx_a + float(k) + 0.5 + (h3 - 0.5) * 0.6)) * secteur_a;
		float vers_avant = dot(vec2(cos(ang - delta), sin(ang - delta)), vol);
		// de presque rien à leur pleine longueur pendant le choc
		float r1 = portee_impact * force * (0.5 + 0.5 * h1) * mix(1.0, 0.45, smoothstep(0.0, 1.0, vers_avant))
				* (0.22 + 0.78 * jaillit);
		float r0 = r1 * 0.92 * smoothstep(0.12, 1.0, tq);
		float demi = epaisseur * force * (0.011 + 0.013 * h2) * (1.0 - tq) * step(0.5, float(nb_aiguilles));
		choc = max(choc, fuseau(d * cos(delta), d * sin(delta), r0, r1, demi, 0.3, c));
	}

	// l'ONDE DE CHOC : pas un cercle (autour d'une étoile, un cercle fait
	// « cible ») mais des ARCS — un par secteur, épais en son milieu, effilé à
	// ses bouts, chacun à son rayon ; certains secteurs restent vides
	float tour_o = mod(ang + PI + graine * 1.7 + 0.6, TAU) / (TAU / float(NB_ARCS));
	float io = floor(tour_o);
	float ho1 = alea(io * 3.3 + graine + 90.0);
	float ho2 = alea(io * 5.9 + graine * 1.2 + 95.0);
	float le_long = abs(fract(tour_o) - 0.5) / (0.27 + 0.18 * ho1);   // 0 au milieu de l'arc, 1 à ses bouts
	float r_onde = portee_impact * force * (0.20 + (0.50 + 0.15 * ho2) * jaillit);
	float demi_o = anneau * 0.026 * force * epaisseur * pow(1.0 - tc, 1.2)
			* max(1.0 - le_long * le_long, 0.0) * step(0.22, ho2);
	float f_o = demi_o - abs(d - r_onde);
	choc = max(choc, vec2(f_o, f_o + min(c, demi_o * PART_CONTOUR)));

	// ===================== LES COULEURS =====================
	// le sang naît presque blanc puis rougit, et garde un cœur brûlant ;
	// le choc est plus clair que le sang de `chaleur`, puis rougit à son tour
	float naissance = eclat * (1.0 - smoothstep(0.0, 0.12, t));
	float coeur_chaud = eclat * (1.0 - smoothstep(0.0,
			0.17 * force * (1.0 - smoothstep(0.0, 0.45, t)) + 0.0001, d));
	vec3 teinte_sang = mix(blood_color.rgb, core_color.rgb, clamp(max(naissance, coeur_chaud), 0.0, 1.0));
	vec3 teinte_choc = mix(blood_color.rgb, core_color.rgb, chaleur * (1.0 - smoothstep(0.1, 0.55, t)));

	vec3 rgb = dark_color.rgb;
	float a = 0.0;
	par_dessus(rgb, a, dark_color.rgb, smoothstep(0.0, px, sang.y));
	par_dessus(rgb, a, teinte_sang, smoothstep(0.0, px, sang.x));
	par_dessus(rgb, a, dark_color.rgb, smoothstep(0.0, px, choc.y));
	par_dessus(rgb, a, teinte_choc, smoothstep(0.0, px, choc.x));
	COLOR = vec4(rgb, blood_color.a * a);
}
