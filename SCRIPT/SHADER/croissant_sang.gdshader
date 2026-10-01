shader_type canvas_item;
render_mode unshaded;
// CROISSANT DE SANG (v2, 1er oct. 2026) — talisman « Croissant de sang » : le
// dernier coup du combo PROJETTE son slash vers l'avant ; il file, traverse les
// ennemis sur une courte distance et s'éteint.
//
// IL NAÎT SUR LE SLASH (Kaoru : « qu'il commence pile sur le slash FX du
// joueur ») : il est dessiné sur le MÊME trajet que le slash du héros
// (`forme`, la courbe mesurée de slash_heros : r(θ) = a0 + a1·cos θ + b1·sin θ
// + a2·cos 2θ + b2·sin 2θ) et, à sa naissance, de la même `queue` à la même
// `tete` que la lame blanche à cet instant — même bord d'attaque, au pixel.
// Puis il s'en détache : son ouverture se centre sur l'avant, il s'épaissit,
// ses pointes prennent du retard (`fleche`), et son bord de fuite pousse des
// LANGUES — des flammèches effilées, inégales, couchées vers l'arrière.
//
// MOINS PLAT (Kaoru : « moins plat, plus stylisé, avec un dégradé ») : un
// DÉGRADÉ du bord d'attaque (rouge vif) au bout des langues (rouge sombre),
// un FIL rouge clair le long du bord d'attaque, une nervure sombre dans son
// épaisseur, des filets de vitesse derrière lui. Toujours aucun blanc. Le
// liseré d'encre est à 0 par défaut (réglage de Kaoru sur la première
// version) : le dégradé suffit à le détacher du fond.
//
// Comme le reste de la famille : rien ne s'estompe, tout MAIGRIT (il finit en
// se ramassant sur son milieu, de plus en plus mince).
// Repère : l'origine est le CENTRE DU TRAJET (pas le milieu du croissant), en
// pixels ; +x = vers l'avant (le nœud est retourné quand le perso regarde à
// gauche), 0 rad = droit devant, les angles positifs vers le bas.

const int NB_LANGUES_MAX = 10;

// --- fournis par croissant_sang.gd -----------------------------------------
// taille du rectangle (px), et où est le centre du trajet dedans (depuis son
// coin haut-gauche)
uniform vec2 taille = vec2(190.0, 270.0);
uniform vec2 origine = vec2(40.0, 135.0);
// la courbe du trajet du slash : (a0, a1, b1, a2) et b2
uniform vec4 forme = vec4(127.59, -10.0, -2.59, 17.62);
uniform float forme_b2 = 4.23;
// d'où à où va le croissant sur ce trajet (rad)
uniform float queue = -1.08;
uniform float tete = 1.08;
// 0 → 1 sur tout son vol ; 0 → 1 pendant qu'il se détache du slash
uniform float progress : hint_range(0.0, 1.0) = 0.3;
uniform float naissance : hint_range(0.0, 1.0) = 1.0;
// 0 → 1 AVANT de se détacher : il « prend » sur la lame, de rien à l'épaisseur
// de sa naissance
uniform float amorce : hint_range(0.0, 1.0) = 1.0;
uniform float temps = 0.0;
uniform float graine = 0.0;
// ----------------------------------------------------------------------------

// épaisseur du croissant en son milieu (px) ; il naît à 60 % (comme la lame)
uniform float epaisseur : hint_range(6.0, 80.0) = 29.0;
// les LANGUES du bord de fuite : combien, jusqu'où elles vont derrière lui
// (px), leur demi-largeur à la base (px), de combien elles se couchent vers
// les pointes (0 = droites), leur frémissement (0 = figées)
uniform int langues : hint_range(0, 10) = 6;
uniform float longueur_langues : hint_range(0.0, 90.0) = 44.0;
uniform float largeur_langues : hint_range(2.0, 30.0) = 12.0;
uniform float couche : hint_range(0.0, 1.5) = 0.55;
uniform float fremit : hint_range(0.0, 1.0) = 0.5;
// de combien ses pointes prennent du retard en vol (px) : il se cambre
uniform float fleche : hint_range(0.0, 60.0) = 22.0;
// 0 = un aplat de `couleur`, 1 = le dégradé complet (vif → sombre)
uniform float degrade : hint_range(0.0, 1.0) = 1.0;
// le fil rouge clair le long du bord d'attaque, et la nervure sombre (0 = sans)
uniform float fil : hint_range(0.0, 1.0) = 0.85;
uniform float nervure : hint_range(0.0, 1.0) = 0.35;
// les filets de vitesse derrière lui (0 = aucun)
uniform float trainees : hint_range(0.0, 1.0) = 1.0;
// épaisseur du liseré d'encre (px ; 0 = sans)
uniform float encre : hint_range(0.0, 6.0) = 0.0;
// le dégradé, du bord d'attaque au bout des langues
uniform vec4 couleur_vive : source_color = vec4(1.0, 0.17, 0.2, 1.0);
uniform vec4 couleur : source_color = vec4(0.78, 0.04, 0.12, 1.0);
uniform vec4 couleur_sombre : source_color = vec4(0.3, 0.0, 0.07, 1.0);
uniform vec4 couleur_fil : source_color = vec4(1.0, 0.5, 0.48, 1.0);
uniform vec4 couleur_encre : source_color = vec4(0.12, 0.0, 0.03, 1.0);

void par_dessus(inout vec3 rgb, inout float a, vec3 teinte, float force) {
	float total = force + a * (1.0 - force);
	rgb = (teinte * force + rgb * a * (1.0 - force)) / max(total, 0.0001);
	a = total;
}

float alea(float n) {
	return fract(sin(n * 12.9898 + 4.1414) * 43758.5453);
}

// la réunion de deux formes (distances positives dedans), raccordées par un
// congé de `k` px : les langues naissent du corps sans angle vif
float reunion(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(a, b, h) + k * h * (1.0 - h);
}

// le trajet du slash à l'angle `th`
float trajet(float th) {
	return forme.x + forme.y * cos(th) + forme.z * sin(th)
			+ forme.w * cos(2.0 * th) + forme_b2 * sin(2.0 * th);
}

// l'épaisseur le long de la lame (0 = queue, 1 = tête) : pleine au milieu,
// effilée en pointe aux deux bouts ; `serre` < 1 la ramasse sur son milieu
float profil(float s, float serre) {
	float x = clamp(0.5 + (s - 0.5) / max(serre, 0.05), 0.0, 1.0);
	return pow(max(sin(PI * x), 0.0), 0.75);
}

void fragment() {
	vec2 p = UV * taille - origine;
	float t = clamp(progress, 0.0, 1.0);
	float ne = clamp(naissance, 0.0, 1.0);
	float aa = max(length(vec2(dFdx(p.x), dFdy(p.x))), 0.35) * 1.2;

	// en vol ses pointes prennent du retard : il se cambre en flèche (rien à la
	// naissance : il est alors exactement sur le slash)
	float demi_arc = max(0.5 * (tete - queue), 0.0001);
	float demi_h = max(forme.x * sin(min(demi_arc, 1.5)), 1.0);
	float yy = p.y / demi_h;
	p.x += fleche * yy * yy * smoothstep(0.0, 0.3, t);

	float r = length(p);
	float theta = atan(p.y, p.x);
	float milieu = 0.5 * (queue + tete);
	float ecart = theta - milieu;
	ecart -= TAU * floor((ecart + PI) / TAU);
	float s = (ecart + demi_arc) / (2.0 * demi_arc);     // 0 à la queue, 1 à la tête
	float sur_lame = step(0.0, s) * step(s, 1.0);
	// distance au trajet, positive vers le centre : c'est l'ARRIÈRE du croissant
	float au_trajet = trajet(theta) - r;
	// px le long de l'arc, comptés depuis son milieu
	float rho_m = trajet(milieu);
	float arc = ecart * rho_m;
	float demi_long = demi_arc * rho_m;

	// il naît mince comme la lame, s'épaissit, puis maigrit en se ramassant
	// sur son milieu
	float corps_vie = mix(0.6, 1.0, smoothstep(0.0, 0.2, t)) * (1.0 - smoothstep(0.62, 1.0, t));
	float serre = mix(1.0, 0.4, smoothstep(0.7, 1.0, t));
	float pr = profil(s, serre);
	float ep = epaisseur * pr * corps_vie * clamp(amorce, 0.0, 1.0);

	// LE CORPS : du trajet (bord d'attaque) vers l'arrière
	float d = min(au_trajet, ep - au_trajet);

	// LES LANGUES : des flammèches effilées qui poussent du bord de fuite vers
	// l'arrière, de longueurs inégales, couchées vers les pointes (celles du
	// milieu partent droit) ; elles poussent en quittant le slash et frémissent
	float pousse = ne * smoothstep(0.0, 0.25, t) * (1.0 - smoothstep(0.75, 1.0, t));
	float long_max = longueur_langues * pousse;
	if (langues > 0 && long_max > 0.5) {
		for (int k = 0; k < NB_LANGUES_MAX; k++) {
			if (k >= langues) {
				break;
			}
			float fk = float(k);
			float h1 = alea(fk * 3.1 + graine);
			float h2 = alea(fk * 5.7 + graine + 9.0);
			float h3 = alea(fk * 8.3 + graine + 21.0);
			// où elle s'attache le long de la lame (0…1), jamais sur les pointes
			float sk = mix(0.12, 0.88, (fk + 0.5 + 0.5 * (h1 - 0.5)) / float(langues));
			float cote = (sk - 0.5) * 2.0;                               // -1 queue … +1 tête
			float ak = cote * demi_long * serre;                           // px depuis le milieu
			float base = epaisseur * profil(sk, 1.0) * corps_vie;        // l'épaisseur du corps là
			float lk = long_max * (0.5 + 0.5 * h2) * (0.6 + 0.4 * profil(sk, 1.0))
					* (1.0 - fremit * 0.25 * (0.5 + 0.5 * sin(temps * 21.0 + fk * 2.3 + graine)));
			float demi = largeur_langues * (0.7 + 0.6 * h3);
			// elle part de l'intérieur du corps (pas de couture) jusqu'à sa pointe
			float u = (au_trajet - base * 0.5) / max(lk + base * 0.5, 1.0);
			float uc = clamp(u, 0.0, 1.0);
			float axe = ak + cote * couche * lk * uc * uc;                // elle se couche vers sa pointe de lame
			float dk = min(demi * pow(1.0 - uc, 1.3) - abs(arc - axe), min(u, 1.0 - u) * (lk + base));
			d = reunion(d, min(dk, au_trajet), 5.0);
		}
	}

	float present = sur_lame * step(0.6, ep);
	float corps = smoothstep(0.0, aa, d) * present;

	// LE DÉGRADÉ : vif au bord d'attaque, sombre au bout des langues ; les
	// pointes un peu plus sombres ; tout vif à l'instant où il quitte le slash
	float fond = clamp(au_trajet / max(ep + long_max * 0.75, 1.0), 0.0, 1.0);
	vec3 col = mix(couleur_vive.rgb, couleur.rgb, smoothstep(0.0, 0.32, fond));
	col = mix(col, couleur_sombre.rgb, smoothstep(0.3, 0.95, fond));
	col = mix(col, couleur_sombre.rgb, 0.25 * (1.0 - pr));
	col = mix(couleur.rgb, col, degrade);
	col = mix(couleur_vive.rgb, col, smoothstep(0.0, 1.0, ne));

	// la nervure : un trait sombre dans l'épaisseur, parallèle au bord d'attaque
	float d_nerv = 1.0 - abs(au_trajet - ep * 0.55);
	float f_nerv = smoothstep(0.0, aa, d_nerv) * smoothstep(0.35, 0.6, pr) * nervure * ne * corps;
	// le fil clair, juste derrière le bord d'attaque
	float d_fil = min(au_trajet - 2.0, 4.6 - au_trajet);
	float f_fil = smoothstep(0.0, aa, d_fil) * smoothstep(0.2, 0.5, pr) * fil * corps;

	vec3 rgb = couleur.rgb;
	float a = 0.0;

	// LES FILETS DE VITESSE : trois traits fins derrière les langues, dans le
	// sens du vol ; ils poussent au décollage et rentrent à la fin
	if (trainees > 0.001) {
		float longueur = 60.0 * smoothstep(0.05, 0.3, t) * (1.0 - smoothstep(0.7, 1.0, t)) * trainees;
		for (int k = 0; k < 3; k++) {
			float fk = (float(k) + 0.5) / 3.0;
			float sk = mix(0.22, 0.78, fk) + 0.06 * sin(graine * 5.0 + fk * 9.0);
			float thk = queue + (tete - queue) * sk;
			float recul = epaisseur * profil(sk, 1.0) * corps_vie + long_max * 0.85 + 6.0;
			vec2 attache = (trajet(thk) - recul) * vec2(cos(thk), sin(thk));
			float lk = longueur * (0.55 + 0.45 * alea(fk * 3.7 + graine));
			float u = (attache.x - p.x) / max(lk, 1.0);                  // 0 à l'attache, 1 au bout
			float demi = 2.0 * (1.0 - u);
			float dk = min(demi - abs(p.y - attache.y), min(u, 1.0 - u) * lk);
			par_dessus(rgb, a, mix(couleur.rgb, couleur_sombre.rgb, 0.6),
				smoothstep(0.0, aa, dk) * step(0.0, u) * step(u, 1.0) * step(1.0, lk));
		}
	}

	// LE CROISSANT : son liseré (s'il en a un), son dégradé, sa nervure, son fil
	float e_px = encre * clamp(ep / 8.0, 0.0, 1.0);
	par_dessus(rgb, a, couleur_encre.rgb, smoothstep(0.0, aa, d + e_px) * present * step(0.01, encre));
	par_dessus(rgb, a, col, corps);
	par_dessus(rgb, a, couleur_sombre.rgb, f_nerv);
	par_dessus(rgb, a, couleur_fil.rgb, f_fil);

	COLOR = vec4(rgb, a);
}
