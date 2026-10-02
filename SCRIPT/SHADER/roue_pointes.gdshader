shader_type canvas_item;
render_mode unshaded;
// ROUE À POINTES (2 oct. 2026, piège choisi par Kaoru) — la roue seule, dans le
// style du pilon : SANS contour, le volume vient des tons (lumière d'en haut à
// gauche, qui NE tourne PAS avec la roue). Un disque de pierre cerclé de fer,
// un moyeu et quatre rayons de fer qui montrent la rotation, huit pointes de
// fer à deux faces (une claire, une sombre) tout autour.
//   • `angle` : elle tourne ; `flou` = l'angle sur lequel étaler la roue (flou
//     de bougé, le script passe la moitié de ce qu'elle a tourné pendant
//     l'image, comme l'obturateur d'une caméra — sans lui, à pleine vitesse,
//     les pointes semblent tourner à l'envers, comme les roues de charrette au
//     cinéma ; à 4 échantillons on voyait 4 copies des pointes, d'où 8) ;
//   • `vitesse` (0 → 1) : elle patine ou roule — gerbe d'étincelles et
//     poussière au point de contact, vers l'arrière ;
//   • `appui` : d'où vient le sol, depuis son centre (vers le bas d'ordinaire ;
//     quand elle fait le tour d'un îlot : sur le flanc, au-dessus d'elle…) ;
//     elle avance dans le sens `sens` le long de ce sol (+1 : vers la droite
//     sur un sol, dans le sens des aiguilles d'une montre autour d'un îlot) ;
//   • `tremble` : elle tremble pendant qu'elle patine sur place ;
//   • `eclat` (0 → 1, −1 = rien) : elle se BRISE contre le mur devant elle — elle
//     se FEND EN QUATRE QUARTIERS (chacun garde ses deux pointes, son bout de
//     cercle et un rayon) qui rebondissent en arrière en tournoyant, retombent
//     et s'arrêtent au sol, des éclats de pierre, une gerbe de poussière plaquée
//     contre le mur et des bouffées translucides (pas une boule opaque : le 1er
//     essai en était une, il cachait tout ; le 2e, en miettes, était chétif).
// Repère : `centre` = le centre de la roue dans le rectangle (px). Pilotée par
// SCRIPT/INTERACTIBLE/roue_pointes.gd.

uniform vec2 taille = vec2(400.0, 156.0);
uniform vec2 centre = vec2(200.0, 110.0);
uniform float rayon = 32.0;                     // le disque, sans les pointes (px)
uniform float longueur_pointes = 12.0;          // elles dépassent du disque de… (px)
uniform float angle = 0.0;
uniform float flou = 0.0;
uniform float vitesse : hint_range(0.0, 1.0) = 0.0;
uniform float sens = 1.0;                       // elle roule vers… (+1 droite)
uniform vec2 appui = vec2(0.0, 1.0);            // la direction du sol, depuis son centre
uniform float tremble : hint_range(0.0, 1.0) = 0.0;
uniform float eclat = -1.0;
uniform float temps = 0.0;

uniform vec4 pierre : source_color = vec4(0.46, 0.52, 0.63, 1.0);
uniform vec4 pierre_ombre : source_color = vec4(0.29, 0.34, 0.44, 1.0);
uniform vec4 pierre_lumiere : source_color = vec4(0.61, 0.66, 0.76, 1.0);
uniform vec4 fer : source_color = vec4(0.26, 0.28, 0.33, 1.0);
uniform vec4 fer_lumiere : source_color = vec4(0.52, 0.55, 0.61, 1.0);
uniform vec4 couleur_etincelle : source_color = vec4(1.0, 0.82, 0.45, 1.0);
uniform vec4 couleur_poussiere : source_color = vec4(0.78, 0.8, 0.84, 1.0);

const int NB_POINTES = 8;
const int ECHANTILLONS = 8;                     // pour le flou de bougé
const vec2 VERS_LUMIERE = vec2(-0.6247, -0.7809);   // en haut à gauche
const float GRAVITE = 2200.0;                   // des morceaux qui retombent (px/s²)
const float DUREE = 0.9;                        // `eclat` 0 → 1 dure… (s), comme DUREE_ECLAT du script


float alea(float n) {
	n = fract(n * 0.1031);
	n *= n + 33.33;
	n *= n + n;
	return fract(n);
}

float couvre(float d, float px) {
	return clamp(0.5 - d / px, 0.0, 1.0);
}

vec4 sur(vec4 dst, vec4 src) {
	float a = src.a + dst.a * (1.0 - src.a);
	vec3 rgb = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 0.0001);
	return vec4(rgb, a);
}

vec2 tourner(vec2 v, float a) {
	return vec2(v.x * cos(a) - v.y * sin(a), v.x * sin(a) + v.y * cos(a));
}

// l'éclairage du monde (ne tourne pas) : clair en haut à gauche, sombre en bas à droite
float lumiere(vec2 q, float r) {
	vec2 n = q / max(r, 0.001);
	return clamp(0.5 + 0.5 * dot(n, VERS_LUMIERE), 0.0, 1.0);
}

// LA ROUE, pointes et disque, pour UN angle : couleur et couverture.
// `q` = le point depuis le centre, dans le repère du monde (pour la lumière) ;
// `a` = l'angle de la roue.
vec4 roue(vec2 q, float a, float px) {
	float R = rayon;
	float lp = longueur_pointes + 3.0;          // les pointes partent de R − 3
	float r = length(q);
	float l = lumiere(q, r);
	float pas = TAU / float(NB_POINTES);
	vec2 qr = tourner(q, -a);                   // le repère de la roue (il tourne)
	float ang = atan(qr.y, qr.x + 0.000001);

	// ---- la pointe la plus proche ----
	float k = floor(ang / pas + 0.5);
	vec2 dir_k = vec2(cos(k * pas), sin(k * pas));
	vec2 lat_k = vec2(-dir_k.y, dir_k.x);
	float le_long = dot(qr, dir_k) - (R - 3.0);
	float cote = dot(qr, lat_k);
	float d_pointe = max(abs(cote) - 7.0 * (1.0 - clamp(le_long / lp, 0.0, 1.0)), max(-le_long, le_long - lp));
	// deux faces, éclairées par le monde : celle qui regarde la lumière est
	// claire, l'autre sombre ; le bout un peu plus clair
	vec2 lat_monde = tourner(lat_k, a);
	float eclaire = 0.5 + 0.5 * dot(cote > 0.0 ? lat_monde : -lat_monde, VERS_LUMIERE);
	vec3 cp = mix(fer.rgb * 0.75, fer_lumiere.rgb * 1.08, eclaire);
	cp = mix(cp, fer_lumiere.rgb * 1.15, smoothstep(lp * 0.6, lp, le_long) * 0.35);
	float cv_p = couvre(d_pointe, px);

	// ---- le disque de pierre, cerclé de fer ----
	vec3 cd = mix(pierre_ombre.rgb, pierre_lumiere.rgb, l);
	cd = mix(cd, pierre.rgb, 0.35);
	// des taches de pierre (elles tournent avec la roue)
	cd *= 0.94 + 0.08 * alea(floor(qr.x / 6.0) * 7.1 + floor(qr.y / 6.0) * 13.3);
	// le cercle de fer, ses rivets (entre les pointes)
	cd = mix(cd, mix(fer.rgb, fer_lumiere.rgb, l * 0.9), smoothstep(R - 7.0, R - 6.0, r));
	float kr = floor((ang + pas * 0.5) / pas + 0.5);
	vec2 riv = vec2(cos(kr * pas - pas * 0.5), sin(kr * pas - pas * 0.5)) * (R - 3.4);
	cd = mix(cd, fer_lumiere.rgb * 1.15, couvre(length(qr - riv) - 1.8, px));
	// quatre rayons de fer : on voit qu'elle tourne
	for (int b = 0; b < 4; b++) {
		float ab = float(b) * TAU / 4.0;
		vec2 db = vec2(cos(ab), sin(ab));
		float d_rayon = max(abs(dot(qr, vec2(-db.y, db.x))) - 2.6, max(-dot(qr, db), dot(qr, db) - (R - 6.5)));
		cd = mix(cd, mix(fer.rgb, fer_lumiere.rgb, l * 0.8), couvre(d_rayon, px));
	}
	// le moyeu
	cd = mix(cd, mix(fer.rgb, fer_lumiere.rgb * 1.1, l), couvre(r - 8.5, px));
	cd = mix(cd, fer.rgb * 0.7, couvre(r - 3.0, px));
	// une ombre de contact : le côté du sol un peu plus sombre
	cd *= 1.0 - 0.18 * smoothstep(0.0, R, dot(q, appui));
	float cv_d = couvre(r - R, px);

	// le disque par-dessus la base des pointes
	float cov = cv_d + cv_p * (1.0 - cv_d);
	vec3 col = (cd * cv_d + cp * cv_p * (1.0 - cv_d)) / max(cov, 0.0001);
	return vec4(col, cov);
}

// la fente entre deux quartiers (b = 0…3) : un léger zigzag le long du rayon,
// dans la pierre seulement (au-delà, il n'y a que le vide entre deux pointes)
float fente(float r, float b) {
	return 0.07 * sin(r * 0.55 + b * 2.3) * step(r, rayon);
}

void fragment() {
	vec2 pix = UV * taille;
	float px = max(fwidth(pix.x), 0.001);
	vec2 q = pix - centre;
	q.x -= sin(temps * 70.0) * 1.6 * tremble;
	vec4 c = vec4(pierre.rgb, 0.0);
	float R = rayon;
	float lp = longueur_pointes + 3.0;
	float portee = R + lp + 3.0;                // la roue, pointes comprises

	if (eclat < 0.0) {
		if (length(q) < portee) {
			// le flou de bougé : la roue à plusieurs instants de l'image écoulée
			vec3 somme = vec3(0.0);
			float cov = 0.0;
			for (int s = 0; s < ECHANTILLONS; s++) {
				vec4 e = roue(q, angle - flou * float(s) / float(ECHANTILLONS - 1), px);
				somme += e.rgb * e.a;
				cov += e.a;
			}
			c = sur(c, vec4(somme / max(cov, 0.0001), cov / float(ECHANTILLONS)));
		}

		// ===================== LES ÉTINCELLES ET LA POUSSIÈRE (elle patine, elle roule) =====================
		if (vitesse > 0.15) {
			// le sens de la marche, le long du sol
			vec2 tang = sens * vec2(appui.y, -appui.x);
			vec2 contact = appui * (R + 6.0);
			for (int e = 0; e < 9; e++) {
				float fe = float(e);
				float periode = 0.16 + 0.1 * alea(fe * 3.7);
				float ph = temps / periode + alea(fe * 5.1);
				float t = fract(ph);
				float n = floor(ph);
				// vers l'arrière et loin du sol, puis elles retombent (la vraie gravité)
				vec2 v0 = -tang * (160.0 + 220.0 * alea(fe * 7.7 + n)) - appui * (120.0 + 220.0 * alea(fe * 4.4 + n));
				float tt = t * periode * 1.6;
				vec2 pos = contact + v0 * tt + vec2(0.0, 0.5 * 1800.0 * tt * tt);
				vec2 vel = normalize(v0 + vec2(0.0, 1800.0 * tt) + vec2(0.0001));
				vec2 dq = q - pos;
				float le = dot(dq, vel);
				float tr = dot(dq, vec2(-vel.y, vel.x));
				float trait = exp(-tr * tr / 0.8) * (le < 0.0 ? exp(le / 5.0) : exp(-le * le / 2.0));
				c = sur(c, vec4(couleur_etincelle.rgb, clamp(trait * (1.0 - t) * 1.6, 0.0, 1.0) * smoothstep(0.15, 0.5, vitesse)));
			}
			// la poussière soulevée derrière elle : des bouffées douces (qui
			// s'éclaircissent vers le bord), pas des bulles
			float nuage = 0.0;
			for (int b = 0; b < 4; b++) {
				float fb = float(b);
				float t = fract(temps * 2.4 + fb * 0.25);
				vec2 cn = appui * (R + 4.0 - t * 16.0) - tang * (R * 0.6 + t * 50.0);
				float rn = 8.0 + 12.0 * t;
				float k = clamp(1.0 - length(q - cn) / rn, 0.0, 1.0);
				nuage = max(nuage, k * k * (1.0 - t));
			}
			c = sur(c, vec4(couleur_poussiere.rgb, nuage * 0.6 * vitesse));
		}
	} else {
		// ===================== ELLE SE BRISE =====================
		float t = eclat;
		float tt = t * DUREE;                       // en secondes
		float vivant = 1.0 - smoothstep(0.8, 1.0, t);

		// ---- 1. la poussière, derrière tout : une gerbe plaquée contre le mur
		// devant elle, qui s'étale le long du mur, et des bouffées qui gonflent
		// vers l'arrière et le haut ----
		float pouss = 0.0;
		vec2 cm = vec2(sens * (R + 4.0), 0.0);
		vec2 em = vec2(10.0 + 14.0 * (1.0 - exp(-t * 6.0)), 20.0 + 50.0 * (1.0 - exp(-t * 6.0)));
		pouss = max(pouss, smoothstep(0.0, 0.7, 1.0 - length((q - cm) / em)) * (1.0 - smoothstep(0.05, 0.5, t)));
		for (int b = 0; b < 6; b++) {
			float fb = float(b);
			float ang = -1.5708 + (alea(fb * 2.7 + 1.0) - 0.5) * 2.4;
			vec2 dirb = vec2(cos(ang), sin(ang));
			dirb.x = -sens * abs(dirb.x) * 0.8 + dirb.x * 0.2;
			float avance = (24.0 + 36.0 * alea(fb * 5.3)) * (1.0 - exp(-t * 4.0));
			vec2 cb = vec2(sens * R * 0.5, 0.0) + dirb * avance;
			float rb = (14.0 + 10.0 * alea(fb * 1.9)) * (0.6 + 1.0 * (1.0 - exp(-t * 4.0)));
			pouss = max(pouss, smoothstep(0.0, 0.7, 1.0 - length(q - cb) / rb) * (1.0 - smoothstep(0.3, 1.0, t)));
		}
		vec3 col_pouss = mix(couleur_poussiere.rgb, couleur_poussiere.rgb * 0.8, smoothstep(-R, R, q.y));
		c = sur(c, vec4(col_pouss, pouss * 0.5));

		// ---- 2. les quatre quartiers : elle se fend entre ses pointes ----
		float pas_q = TAU / 4.0;
		for (int j = 0; j < 4; j++) {
			float fj = float(j);
			// son axe : entre deux pointes (67,5° + j × 90°, dans le repère de la
			// roue), il garde deux pointes et un rayon ; puis dans le monde
			float phi = 1.1781 + fj * pas_q;
			vec2 axe = vec2(cos(phi + angle), sin(phi + angle));
			vec2 c0 = axe * R * 0.45;               // son centre, au départ
			// sa course : il part le long de son axe, surtout vers l'arrière et le haut
			vec2 v0 = axe * (110.0 + 70.0 * alea(fj * 3.1 + 2.0))
					+ vec2(-sens * (120.0 + 80.0 * alea(fj * 6.7)), -(230.0 + 90.0 * alea(fj * 4.9)));
			// il retombe ; son centre s'arrête à ~16 px du sol, après une courte glissade
			float descente = (R + 6.0 - 16.0) - c0.y;
			float t_sol = (-v0.y + sqrt(max(v0.y * v0.y + 2.0 * GRAVITE * descente, 0.0))) / GRAVITE;
			float t_vol = min(tt, t_sol);
			float glisse = tt > t_sol ? 0.1 * (1.0 - exp(-(tt - t_sol) * 9.0)) : 0.0;
			vec2 depl = vec2(v0.x * (t_vol + glisse), v0.y * t_vol + 0.5 * GRAVITE * t_vol * t_vol);
			float rot = (t_vol + glisse) * (5.0 + 5.0 * alea(fj * 8.3)) * (alea(fj * 1.3 + 0.4) < 0.5 ? -1.0 : 1.0);
			// le point de la roue entière qui se trouve ici : on défait sa course
			// et sa rotation
			vec2 q0 = c0 + tourner(q - c0 - depl, -rot);
			float r0 = length(q0);
			if (r0 < portee) {
				vec2 q0r = tourner(q0, -angle);
				float s_a = mod(atan(q0r.y, q0r.x + 0.000001) - phi + PI, TAU) - PI;
				float de = s_a - (-pas_q * 0.5 + fente(r0, fj));
				float a_droite = (pas_q * 0.5 + fente(r0, mod(fj + 1.0, 4.0))) - s_a;
				float dans = clamp(min(de, a_droite) * max(r0, 1.0) / px + 0.5, 0.0, 1.0);
				if (dans > 0.0) {
					vec4 e = roue(q0, angle, px);
					c = sur(c, vec4(e.rgb, e.a * dans * vivant));
				}
			}
		}

		// ---- 3. des éclats de pierre, plus vifs et plus loin ----
		for (int k = 0; k < 8; k++) {
			float fk = float(k);
			float ang = alea(fk * 3.3) * TAU;
			float v = 200.0 + 260.0 * alea(fk * 5.7);
			vec2 v0 = vec2(-sens * (abs(cos(ang)) - 0.2) * v, -abs(sin(ang)) * v - 160.0);
			float t_sol = (-v0.y + sqrt(v0.y * v0.y + 2.0 * GRAVITE * (R + 6.0))) / GRAVITE;
			float t_vol = min(tt, t_sol);
			float glisse = tt > t_sol ? 0.12 * (1.0 - exp(-(tt - t_sol) * 9.0)) : 0.0;
			vec2 pos = vec2(v0.x * (t_vol + glisse), v0.y * t_vol + 0.5 * GRAVITE * t_vol * t_vol);
			float rot = (t_vol + glisse) * (8.0 + 8.0 * alea(fk * 2.1)) * (alea(fk) < 0.5 ? -1.0 : 1.0);
			vec2 dq = tourner(q - pos, rot);
			// un caillou anguleux, modelé par la lumière du monde
			vec2 e = vec2(4.0 + 4.0 * alea(fk * 4.4), 3.0 + 3.0 * alea(fk * 8.2));
			float d_m = (abs(dq.x) / e.x + abs(dq.y) / e.y - 1.0) * min(e.x, e.y) * 0.8;
			float lum_m = clamp(0.5 + 0.5 * dot((q - pos) / max(e.x, 1.0), VERS_LUMIERE), 0.0, 1.0);
			vec3 col_m = mix(pierre_ombre.rgb * 0.9, pierre_lumiere.rgb, lum_m);
			c = sur(c, vec4(col_m, couvre(d_m, px) * vivant));
		}
	}

	// rien ne touche le bord du rectangle
	float bord = min(min(pix.x, taille.x - pix.x), min(pix.y, taille.y - pix.y));
	c.a *= smoothstep(0.0, 4.0, bord);
	COLOR = c;
}
