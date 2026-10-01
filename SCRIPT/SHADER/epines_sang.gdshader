shader_type canvas_item;
render_mode unshaded;
// ÉPINES DE SANG (1er oct. 2026) — le talisman : quand le joueur ENCAISSE un
// coup, des pics de SANG CRISTALLISÉ sont projetés hors de son corps jusqu'à
// la portée des dégâts, puis leurs pointes cassent net et le reste rentre dans
// le corps. Même famille que les autres effets : aplats nets, liseré d'encre,
// tout piloté par `progress`.
//
// SOBRES (Kaoru, 1er oct. 2026 : « on les rend plus sobres, on retire
// l'ombrage sur la pique, ça rend pas bien, on retire l'éclat de lumière blanc
// aussi et on les rend plus fines ») : un pic = UN aplat de rouge sang cerné
// d'encre, fin comme une aiguille ; plus de face à l'ombre, d'arête claire, de
// reflet, d'étincelle ni de flash blanc (la v3 les avait : sauvegardée hors du
// projet si on veut y revenir).
//
// LES PICS : trois tailles mêlées (des grands qui atteignent la portée, des
// moyens, des petits), un peu COURBÉS comme des épines. AU SOL, ils ne
// jaillissent que vers le haut et les côtés (rien ne traverse le sol) ; EN
// L'AIR, en étoile complète.
//
// QUATRE TEMPS :
//   1. la PROJECTION : une giclée de sang au milieu du corps et les pics sont
//      projetés hors de lui (les grands d'abord), déjà à mi-course dès la
//      première image, avec un léger dépassement qui claque ;
//   2. la TENUE : ils restent plantés en frémissant ;
//   3. la FÊLURE : un trait d'encre EN BIAIS traverse chaque pic près de sa
//      pointe (2-3 images) ;
//   4. la CASSE : la pointe casse net le long de la fêlure, part en tournant et
//      RETOMBE (vraie gravité) en fondant ; le reste du pic, coupé en biais,
//      RENTRE dans le corps ; une goutte de sang étirée s'échappe des moyens et
//      des grands.
//
// Repère : l'origine est le MILIEU du rectangle (le milieu du corps du
// joueur), y vers le bas ; tout se compte en pixels et en secondes.

uniform float progress : hint_range(0.0, 1.0) = 0.0;

// --- fournis par epines_sang.gd ---------------------------------------------
// le rectangle, en px
uniform vec2 taille = vec2(720.0, 720.0);
// la portée des grands pics (= celle des dégâts), en px depuis le milieu du corps
uniform float rayon = 200.0;
// une valeur par éruption : deux coups encaissés ne donnent pas la même
uniform float graine = 0.0;
// durée de l'effet (s) : la chute des pointes est en vraies unités
uniform float duree = 0.5;
// où est le sol, en px sous le milieu du corps (très grand = en l'air)
uniform float sol = 100000.0;
// ----------------------------------------------------------------------------

// nombre de pics
uniform int nb_epines : hint_range(4, 24) = 16;
// d'où ils sortent : le bord du corps (px depuis le milieu)
uniform float depart : hint_range(0.0, 80.0) = 22.0;
// largeur d'un pic à sa base (part de sa longueur)
uniform float largeur : hint_range(0.02, 0.3) = 0.065;
// de combien ils se courbent (0 = droits)
uniform float courbure : hint_range(0.0, 0.4) = 0.14;
// au sol : de combien de degrés les pics des côtés descendent sous l'horizontale
uniform float ecart_sol : hint_range(0.0, 60.0) = 6.0;
// la giclée de sang au milieu du corps, à la projection (0 = aucune)
uniform float giclee : hint_range(0.0, 1.0) = 1.0;
// épaisseur du liseré d'encre (px)
uniform float encre : hint_range(0.0, 6.0) = 2.0;
// quand ils cassent (part de l'effet)
uniform float casse_debut : hint_range(0.2, 0.9) = 0.42;
// où la pointe casse (part de la longueur du pic, 1 = la pointe)
uniform float coupe : hint_range(0.4, 0.95) = 0.6;
// de combien la cassure est en biais (0 = droite)
uniform float biais : hint_range(0.0, 3.0) = 1.2;
// vitesse des pointes cassées vers l'extérieur (px/s) et leur chute (px/s²)
uniform float envol : hint_range(0.0, 800.0) = 300.0;
uniform float gravite : hint_range(0.0, 5000.0) = 2200.0;
// le rouge des pics et des gouttes, et l'encre
uniform vec4 couleur : source_color = vec4(0.76, 0.03, 0.11, 1.0);
uniform vec4 couleur_encre : source_color = vec4(0.12, 0.0, 0.03, 1.0);

// (PI et TAU sont fournis par le langage de shader de Godot)
const int MAX_PICS = 24;

// hash 1D sans sin : une valeur stable par pic
float alea(float n) {
	n = fract(n * 0.1031);
	n *= n + 33.33;
	n *= n + n;
	return fract(n);
}

// pose une couleur par-dessus ce qui est déjà dessiné
void par_dessus(inout vec3 rgb, inout float a, vec3 teinte, float force) {
	float total = force + a * (1.0 - force);
	rgb = (teinte * force + rgb * a * (1.0 - force)) / max(total, 0.0001);
	a = total;
}

// LA FORME D'UN PIC : base en `o`, axe `dir`, longueur `l`, demi-largeur `w0`
// à la base (bords droits : une aiguille), axe courbé de `courbe` × l × s² sur
// le côté ; seulement entre les coupes `s0` et `s1` (0 = base, 1 = pointe),
// toutes deux penchées de `pente` (une coupe en biais). Renvoie (distance
// dedans en px — positive dedans —, position en travers, position le long).
vec3 forme_pic(vec2 p, vec2 o, vec2 dir, float l, float w0, float courbe,
		float s0, float s1, float pente) {
	vec2 cote = vec2(-dir.y, dir.x);
	vec2 q = p - o;
	float s = dot(q, dir) / max(l, 0.001);
	float v = dot(q, cote) - courbe * l * s * s;
	float w = w0 * clamp(1.0 - s, 0.0, 1.0);
	float penche = pente * v / max(l, 0.001);
	float d = min(min(w - abs(v), (s - s0 - penche) * l), (s1 + penche - s) * l);
	return vec3(d, v, s);
}

// LES RÉGLAGES D'UN PIC : direction, longueur, demi-largeur à la base,
// courbure, retard de sortie (s), classe (1 = grand, 0,6 = moyen, 0,3 = petit)
void reglages_pic(int i, bool au_sol, out vec2 dir, out float l, out float w0,
		out float courbe, out float retard, out float classe) {
	float fi = float(i);
	float n = float(nb_epines);
	float h1 = alea(fi * 1.37 + graine * 3.1 + 1.0);
	float h2 = alea(fi * 2.91 + graine * 1.7 + 5.0);
	float h3 = alea(fi * 4.13 + graine * 0.9 + 9.0);
	// trois tailles mêlées tout autour : la suite du nombre d'or les répartit,
	// un peu de hasard par pic casse sa symétrie (sans lui, 16 pics donnaient
	// une rose des vents : les grands en croix)
	float g = fract(fi * 0.618 + graine * 0.13 + 0.3 * (alea(fi * 5.1 + graine * 2.3 + 7.0) - 0.5));
	classe = g < 0.3 ? 1.0 : (g < 0.6 ? 0.6 : 0.3);
	float portee = classe > 0.9 ? mix(0.84, 1.0, h2) : (classe > 0.5 ? mix(0.58, 0.74, h2) : mix(0.34, 0.5, h2));
	// au sol : un éventail du côté gauche au côté droit en passant par le haut
	float ouvert = au_sol ? PI + 2.0 * radians(ecart_sol) : TAU;
	float debut = au_sol ? -PI * 0.5 - ouvert * 0.5 : -PI * 0.5 + graine * 0.37;
	float theta = debut + (fi + 0.5 + 0.85 * (h1 - 0.5)) * ouvert / n;
	dir = vec2(cos(theta), sin(theta));
	l = max(rayon * portee - depart, 1.0);
	w0 = largeur * rayon * portee * mix(0.85, 1.15, h3);
	courbe = courbure * (h3 * 2.0 - 1.0);
	retard = (1.0 - classe) * 0.035;
}


void fragment() {
	vec2 p = (UV - 0.5) * taille;
	float t = clamp(progress, 0.0, 1.0);
	float ts = t * duree;
	// un pixel d'écran, en px du rectangle : des bords nets à toute échelle
	float aa = max(length(vec2(dFdx(p.x), dFdy(p.x))), 0.35) * 1.2;
	float r = length(p);
	bool au_sol = sol < 50000.0;

	vec3 rgb = couleur.rgb;
	float a = 0.0;

	// 1. LA GICLÉE DE SANG au milieu du corps : une tache déchiquetée qui gicle
	// et se résorbe (surtout cachée par le perso : on en voit les bords)
	if (giclee > 0.001 && ts < 0.16) {
		float ang = atan(p.y, p.x);
		float gicle = 1.0 - pow(1.0 - clamp(ts / 0.05, 0.0, 1.0), 3.0);
		float resorbe = 1.0 - smoothstep(0.06, 0.16, ts);
		float bord = (depart + 30.0) * giclee * gicle * resorbe
				* (1.0 + 0.28 * sin(ang * 5.0 + graine) + 0.16 * sin(ang * 9.0 - graine * 2.0));
		par_dessus(rgb, a, couleur_encre.rgb, smoothstep(0.0, aa, bord + encre - r) * step(0.5, bord));
		par_dessus(rgb, a, couleur.rgb, smoothstep(0.0, aa, bord - r));
	}

	// 2. LES PICS (et après la casse, ce qu'il en reste et qui rentre), des
	// petits aux grands : les grands passent devant
	for (int passe = 0; passe < 3; passe++) {
		float voulu = passe == 0 ? 0.3 : (passe == 1 ? 0.6 : 1.0);
		for (int i = 0; i < MAX_PICS; i++) {
			if (i >= nb_epines) {
				break;
			}
			vec2 dir = vec2(1.0, 0.0);
			float l = 1.0;
			float w0 = 1.0;
			float courbe = 0.0;
			float retard = 0.0;
			float classe = 0.0;
			reglages_pic(i, au_sol, dir, l, w0, courbe, retard, classe);
			if (abs(classe - voulu) > 0.01) {
				continue;
			}
			float fi = float(i);
			float ts_casse = (casse_debut + 0.06 * alea(fi * 6.7 + graine)) * duree;
			float tau = ts - ts_casse;
			float pente = biais * (alea(fi * 9.1 + graine) > 0.5 ? 1.0 : -1.0) * mix(0.6, 1.0, alea(fi * 3.9 + graine));
			// la projection : il sort du corps, vite, dépasse un peu et revient
			float te = (ts - retard) / 0.07;
			if (te <= 0.0) {
				continue;
			}
			float sortie = 1.0 - pow(1.0 - min(te, 1.0), 3.0);
			float depasse = 0.1 * sin(PI * clamp((te - 0.7) / 1.4, 0.0, 1.0)) * step(0.7, te);
			float avance = sortie + depasse;
			// après la casse, le reste rentre dans le corps, de plus en plus vite
			float rentre = tau > 0.0 ? pow(clamp(tau / 0.09, 0.0, 1.0), 2.0) : 0.0;
			if (rentre >= 1.0) {
				continue;
			}
			// c'est le pic entier qui glisse : la base part de l'intérieur du corps
			vec2 o = dir * (depart - l * (1.0 - avance) - l * rentre);
			vec2 cote = vec2(-dir.y, dir.x);
			// le frémissement pendant la tenue
			o += cote * 0.9 * sin(ts * 70.0 + fi * 2.1) * smoothstep(0.07, 0.12, ts) * step(tau, 0.0);
			// hors de portée de ce pic : rien à faire (et ça coûte moins cher)
			float u = dot(p, dir);
			if (u < depart * 0.5 || dot(p - o, dir) > l + encre + 3.0
					|| abs(dot(p - o, cote)) > w0 + abs(courbe) * l + encre + 3.0) {
				continue;
			}
			// intact, ou coupé en biais à la fêlure une fois la pointe partie
			float s1 = tau > 0.0 ? coupe : 2.0;
			vec3 f = forme_pic(p, o, dir, l, w0, courbe, -1.0, s1, pente);
			// on ne dessine pas ce qui est encore dans le corps
			float visible = smoothstep(depart * 0.5, depart * 0.5 + aa, u);
			par_dessus(rgb, a, couleur_encre.rgb, smoothstep(0.0, aa, f.x + encre) * visible);
			par_dessus(rgb, a, couleur.rgb, smoothstep(0.0, aa, f.x) * visible);
			// 3. LA FÊLURE, juste avant de casser : un trait d'encre en biais, là
			// où la pointe va partir
			float fel = smoothstep(ts_casse - 0.05, ts_casse - 0.025, ts) * step(tau, 0.0);
			if (fel > 0.0) {
				float trait = 1.2 - abs((f.z - coupe - pente * f.y / l) * l);
				par_dessus(rgb, a, couleur_encre.rgb, smoothstep(0.0, aa, min(trait, f.x)) * fel * visible);
			}
		}
	}

	// 4. LA CASSE : les pointes qui partent en tournant et retombent, et les
	// gouttes
	if (t > casse_debut - 0.001) {
		for (int i = 0; i < MAX_PICS; i++) {
			if (i >= nb_epines) {
				break;
			}
			vec2 dir = vec2(1.0, 0.0);
			float l = 1.0;
			float w0 = 1.0;
			float courbe = 0.0;
			float retard = 0.0;
			float classe = 0.0;
			reglages_pic(i, au_sol, dir, l, w0, courbe, retard, classe);
			float fi = float(i);
			float ts_casse = (casse_debut + 0.06 * alea(fi * 6.7 + graine)) * duree;
			float tau = ts - ts_casse;
			if (tau < 0.0) {
				continue;
			}
			float pente = biais * (alea(fi * 9.1 + graine) > 0.5 ? 1.0 : -1.0) * mix(0.6, 1.0, alea(fi * 3.9 + graine));
			float fin = clamp(tau / max(duree - ts_casse, 0.001), 0.0, 1.0);
			float h = alea(fi * 7.3 + graine * 1.1 + 2.0);
			float h2 = alea(fi * 8.3 + graine * 1.9 + 6.0);
			vec2 cote = vec2(-dir.y, dir.x);
			vec2 o = dir * depart;
			float sm = (coupe + 1.0) * 0.5;
			vec2 centre = o + dir * sm * l + cote * courbe * l * sm * sm;
			vec2 point_casse = o + dir * coupe * l + cote * courbe * l * coupe * coupe;

			// la pointe : elle part vers l'extérieur (un peu vers le haut), tourne,
			// retombe et fond
			vec2 vitesse = dir * envol * (0.75 + 0.5 * h) + cote * (h2 - 0.5) * 140.0 + vec2(0.0, -110.0);
			vec2 c = centre + vitesse * tau + vec2(0.0, 0.5 * gravite * tau * tau);
			float rot = (h - 0.5) * 22.0 * tau;
			float k = pow(1.0 - fin, 1.3);
			float portee_pointe = (1.0 - coupe) * l * 0.6 + w0 + encre + 4.0;
			if (k > 0.02 && length(p - c) < portee_pointe) {
				vec2 dp = (p - c) / k;
				float cr = cos(-rot);
				float sr = sin(-rot);
				vec2 q = vec2(dp.x * cr - dp.y * sr, dp.x * sr + dp.y * cr) + centre;
				vec3 f = forme_pic(q, o, dir, l, w0, courbe, coupe, 2.0, pente);
				float d = f.x * k;
				par_dessus(rgb, a, couleur_encre.rgb, smoothstep(0.0, aa, d + encre * mix(0.6, 1.0, k)));
				par_dessus(rgb, a, couleur.rgb, smoothstep(0.0, aa, d));
			}
			// la goutte : une larme de sang, étirée dans le sens où elle file
			if (classe > 0.5) {
				vec2 v0 = normalize(dir + cote * (h2 - 0.5) * 0.8 + vec2(0.0, -0.4)) * envol * (0.8 + 0.5 * h2);
				vec2 vg = v0 + vec2(0.0, gravite * tau);
				vec2 cg = point_casse + v0 * tau + vec2(0.0, 0.5 * gravite * tau * tau);
				float rg = mix(2.4, 3.6, classe) * (1.0 - fin * fin);
				if (rg > 0.4 && length(p - cg) < rg * 3.0 + encre + 2.0) {
					vec2 dv = normalize(vg + vec2(0.0001, 0.0));
					vec2 rel = p - cg;
					float uu = dot(rel, dv);
					float vv = dot(rel, vec2(-dv.y, dv.x));
					// la tête devant, ronde ; la traîne derrière, étirée
					float dg = length(vec2(uu > 0.0 ? uu : uu * 0.4, vv));
					par_dessus(rgb, a, couleur_encre.rgb, smoothstep(0.0, aa, rg + encre * 0.6 - dg));
					par_dessus(rgb, a, couleur.rgb, smoothstep(0.0, aa, rg - dg));
				}
			}
		}
	}

	// rien sous le sol
	a *= smoothstep(sol + aa, sol - aa, p.y);
	COLOR = vec4(rgb, a);
}
