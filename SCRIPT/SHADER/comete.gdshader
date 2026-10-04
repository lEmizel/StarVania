shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;
// COMÈTE (2 oct. 2026, piège « pluie d'étoiles ») — une étoile
// filante qui tombe sur un point du sol, AVERTIE. Tout est lumière ajoutée :
//   • l'AVERTISSEMENT (`avert` 0 → 1) : sa trajectoire se déroule du ciel au sol
//     en pointillés qui filent vers l'impact, une ÉTOILE scintille au-dessus du
//     point d'impact et un trait de lumière court sur le sol (vue de côté) ;
//   • le VOL (`vol` 0 → 1, très court) : la tête blanche et or file en
//     accélérant, une traîne or → violet derrière elle, des paillettes ;
//   • l'IMPACT (`explo` 0 → 1) : un éclat en étoile, un dôme de lumière qui
//     s'ouvre au-dessus du sol, des étincelles qui jaillissent et retombent, une
//     braise qui refroidit sur le sol ;
//   • ARRÊTÉE EN VOL (`arretee`, talisman « Gardiennes ») : elle éclate là où
//     elle en était (`arret`), en l'air — l'éclat en étoile, un anneau entier,
//     des étincelles qui tombent ; ni dôme coupé par le sol, ni braise.
// Repère : `impact` et `depart` sont dans le rectangle (px). Piloté par
// SCRIPT/SHADER/comete.gd.

uniform vec2 taille = vec2(600.0, 800.0);
uniform vec2 impact = vec2(450.0, 700.0);
uniform vec2 depart = vec2(150.0, 100.0);
uniform float avert : hint_range(0.0, 1.0) = 0.0;
uniform float vol : hint_range(0.0, 1.0) = 0.0;
uniform float explo : hint_range(0.0, 1.0) = 0.0;
uniform float temps = 0.0;
uniform float graine = 0.0;
// arrêtée en vol : l'impact est dessiné en `arret` (dans le rectangle), en l'air
uniform float arretee : hint_range(0.0, 1.0) = 0.0;
uniform vec2 arret = vec2(0.0);

uniform vec4 couleur_noyau : source_color = vec4(1.0, 0.98, 0.92, 1.0);
uniform vec4 couleur_or : source_color = vec4(1.0, 0.82, 0.4, 1.0);
uniform vec4 couleur_traine : source_color = vec4(0.58, 0.46, 1.0, 1.0);
uniform float longueur_traine = 260.0;
uniform float intensite = 1.0;


float alea(float n) {
	n = fract(n * 0.1031);
	n *= n + 33.33;
	n *= n + n;
	return fract(n);
}

vec2 tourner(vec2 v, float a) {
	return vec2(v.x * cos(a) - v.y * sin(a), v.x * sin(a) + v.y * cos(a));
}

// une étoile à quatre branches : deux bras fins en croix et un cœur
float scintille(vec2 q, float r) {
	float bras = exp(-abs(q.x) / (r * 0.1)) * exp(-abs(q.y) / r)
			+ exp(-abs(q.y) / (r * 0.1)) * exp(-abs(q.x) / r);
	float coeur = exp(-dot(q, q) / (r * r * 0.06));
	return bras + coeur;
}

void fragment() {
	vec2 p = UV * taille;
	vec3 lum = vec3(0.0);
	vec2 trajet = impact - depart;
	float l_trajet = max(length(trajet), 1.0);
	vec2 dir = trajet / l_trajet;
	vec2 nrm = vec2(-dir.y, dir.x);
	vec2 rel = p - depart;
	float le_long = dot(rel, dir);                   // 0 au départ, l_trajet à l'impact
	float travers = dot(rel, nrm);
	vec2 q = p - impact;

	// ===================== L'AVERTISSEMENT =====================
	float montre = avert * (1.0 - smoothstep(0.0, 0.35, vol)) * step(explo, 0.001);
	if (montre > 0.0) {
		// la trajectoire se déroule du ciel au sol, en pointillés qui filent vers l'impact
		float deroule = step(le_long, l_trajet * smoothstep(0.0, 0.45, avert)) * step(0.0, le_long);
		float tiret = step(0.45, fract(le_long / 24.0 - temps * 2.8));
		float trait = exp(-travers * travers / 2.2) * tiret * deroule;
		lum += couleur_or.rgb * trait * (0.3 + 0.7 * avert) * montre * 0.75;
		// l'étoile qui marque le point d'impact, au-dessus du sol
		float bat = 0.8 + 0.2 * sin(temps * 15.0);
		float r_e = mix(8.0, 26.0, smoothstep(0.0, 1.0, avert)) * bat;
		vec2 qe = tourner(q - vec2(0.0, -22.0), temps * 1.2);
		lum += mix(couleur_or.rgb, couleur_noyau.rgb, 0.4) * scintille(qe, r_e) * montre * 1.3;
		// un trait de lumière sur le sol, qui s'étend, et un halo qui monte de lui
		float ligne = exp(-pow(abs(q.y / 3.0), 2.0)) * exp(-pow(abs(q.x / (26.0 + 44.0 * avert)), 2.0));
		lum += couleur_or.rgb * ligne * montre * bat * 1.4;
		float halo = exp(-pow(abs(q.x / 30.0), 2.0)) * exp(min(q.y, 0.0) / 40.0) * step(q.y, 0.5);
		lum += couleur_traine.rgb * halo * montre * 0.35 * bat;
	}

	// ===================== LA COMÈTE =====================
	if (vol > 0.0 && vol < 1.0) {
		float v = vol * vol;                         // elle accélère
		float tete = l_trajet * v;
		float derriere = tete - le_long;             // > 0 : dans la traîne
		float lt = max(min(longueur_traine, tete), 1.0);
		if (derriere > 0.0 && derriere < lt) {
			float k = derriere / lt;
			float epais = mix(7.0, 1.2, k);
			float dans = exp(-pow(abs(travers / epais), 2.0));
			vec3 coul = mix(couleur_or.rgb, couleur_traine.rgb, smoothstep(0.0, 0.7, k));
			lum += coul * dans * pow(abs(1.0 - k), 1.4) * 1.8;
			// des paillettes qui se détachent de la traîne
			float cel = floor(derriere / 14.0);
			float h = alea(cel * 3.7 + graine);
			vec2 pa = vec2((cel + 0.5) * 14.0, (h - 0.5) * 18.0 * k);
			float dp = length(vec2(derriere, travers) - pa);
			lum += couleur_noyau.rgb * exp(-dp * dp / 3.0) * step(0.5, h) * (1.0 - k);
		}
		vec2 pos_tete = depart + dir * tete;
		float dt = length(p - pos_tete);
		lum += couleur_noyau.rgb * exp(-dt * dt / 34.0) * 2.2 + couleur_or.rgb * exp(-dt / 15.0) * 1.0;
	}

	// ===================== L'IMPACT =====================
	if (explo > 0.0) {
		float t = explo;
		bool en_l_air = arretee > 0.5;
		if (en_l_air) {
			q = p - arret;
		}
		float r = length(q);
		float a = atan(q.y, q.x);
		// l'éclat en étoile : huit rais FINS et COURTS qui raccourcissent (ils
		// portaient à près de 400 px, beaucoup trop : bornés à ~100)
		float rais = pow(abs(cos(a * 4.0 + graine)), 40.0);
		float long_rais = mix(40.0, 10.0, smoothstep(0.0, 0.6, t));
		float eclat = rais * exp(-r / long_rais) * 1.8 * (1.0 - t) * (1.0 - smoothstep(60.0, 110.0, r));
		eclat += exp(-r * r / (260.0 * (1.0 + 7.0 * t))) * 2.6 * pow(abs(1.0 - t), 1.5);
		// sous le sol, la lumière ne passe qu'à moitié
		eclat *= (q.y > 0.0 && !en_l_air) ? 0.35 : 1.0;
		lum += mix(couleur_noyau.rgb, couleur_or.rgb, 0.35) * eclat;
		// le dôme de lumière qui s'ouvre au-dessus du sol
		float rd = mix(12.0, 130.0, 1.0 - pow(abs(1.0 - t), 3.0));
		float dome = exp(-pow(abs((r - rd) / 5.0), 2.0)) * (1.0 - t) * (en_l_air ? 1.0 : step(q.y, 0.5));
		lum += couleur_traine.rgb * dome * 1.3;
		// les étincelles : elles jaillissent et retombent
		for (int k = 0; k < 12; k++) {
			float fk = float(k);
			float ang = -1.5708 + (alea(fk * 3.1 + graine) - 0.5) * 2.6;
			float vit = 260.0 + 380.0 * alea(fk * 5.3 + graine);
			float tt = t * 0.7;
			vec2 pos = vec2(cos(ang), sin(ang)) * vit * tt + vec2(0.0, 0.5 * 1800.0 * tt * tt);
			if (pos.y > 4.0 && !en_l_air) {
				continue;
			}
			vec2 vel = normalize(vec2(cos(ang) * vit, sin(ang) * vit + 1800.0 * tt) + vec2(0.0001));
			vec2 d = q - pos;
			float le = dot(d, vel);
			float tr = dot(d, vec2(-vel.y, vel.x));
			float trainee = clamp(-le / 10.0, 0.0, 1.0);
			float e = exp(-tr * tr / 1.4) * exp(-pow(abs(max(le, 0.0) / 2.0), 2.0)) * (le < 0.0 ? exp(le / 10.0) : 1.0);
			lum += mix(couleur_noyau.rgb, couleur_or.rgb, 0.5) * e * (1.0 - t) * 1.4;
		}
		// la braise sur le sol, qui refroidit (du blanc-or au rouge)
		float braise = exp(-pow(abs(q.y / 3.0), 2.0)) * exp(-pow(abs(q.x / 24.0), 2.0)) * (1.0 - t * 0.85) * (en_l_air ? 0.0 : 1.0);
		lum += mix(couleur_or.rgb, vec3(1.0, 0.35, 0.12), t) * braise * 1.2;
	}

	// rien ne touche le bord du rectangle
	float bord = min(min(p.x, taille.x - p.x), min(p.y, taille.y - p.y));
	lum *= smoothstep(0.0, 16.0, bord) * intensite;
	COLOR = vec4(lum, 0.0);
}
