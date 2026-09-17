shader_type canvas_item;
render_mode unshaded;
// JET DE FLAMMES (prototype) — même famille que flamme_cartoon : bruit sans
// sin, aplats cartoon, même palette. À poser sur un ColorRect ÉTROIT ET HAUT
// (≈ 1:3) : la BUSE est en bas au centre, le jet part vers le haut. Pour
// l'orienter, on tourne le nœud.
//
// UN SEUL RÉGLAGE fait tout : `puissance`
//   0      → éteint, rien n'est dessiné
//   ~0.1   → veilleuse : courte, étroite, orangée, qui crachote
//   1      → plein jet : long, évasé, rapide, cœur blanc
//
// PRINCIPE (v2) : la matière du jet EST le bruit, qui remonte avec le flux. Un
// seuil de dissolution grandit le long du jet et vers ses bords : chaque paquet
// de flammes qui monte le traverse, donc il rétrécit, se détache et disparaît.
// Il n'y a AUCUNE enveloppe fixe : la silhouette du bout n'existe que par les
// paquets qui passent. (v1 : longueur et profil géométriques que le bruit ne
// faisait que grignoter → un bout figé, découpé toujours au même endroit.)

uniform float puissance : hint_range(0.0, 1.0) = 1.0;

// vitesse à laquelle les flammes remontent le jet
uniform float vitesse : hint_range(0.0, 6.0) = 2.4;
// demi-largeur à la sortie de la buse (en fraction de la largeur du rectangle)
uniform float largeur_buse : hint_range(0.02, 0.5) = 0.09;
// demi-largeur du jet vers son extrémité, à pleine puissance
uniform float largeur_bout : hint_range(0.05, 0.5) = 0.36;
// agitation latérale du jet (croît en s'éloignant de la buse)
uniform float turbulence : hint_range(0.0, 1.0) = 0.5;
// à quel point le jet se désintègre tôt : 0 = compact jusqu'au bout,
// 2 = il part en lambeaux presque dès la buse
uniform float dispersion : hint_range(0.0, 2.0) = 1.0;
// taille des paquets de flammes (plus grand = plus fin)
uniform float detail : hint_range(1.0, 10.0) = 4.5;
// hauteur / largeur du ColorRect : renseigné par jet_flamme.gd, pour calculer
// le bruit dans un espace aux VRAIES proportions (sinon il est étiré par la
// forme du rectangle et le seuil y découpe des bandes horizontales)
uniform float ratio = 2.9;
// décale le bruit : renseigné par jet_flamme.gd (une valeur par jet). Sans ça,
// le bruit ne dépend que du temps → trois jets côte à côte sont IDENTIQUES
uniform float graine = 0.0;
// 1 = aplats dessin animé, 0 = dégradé doux
uniform float style_cartoon : hint_range(0.0, 1.0) = 1.0;
uniform int nb_bandes : hint_range(2, 8) = 4;
uniform float saturation : hint_range(0.0, 2.0) = 1.0;

uniform vec4 outer_color : source_color = vec4(0.9, 0.05, 0.005, 1.0);
uniform vec4 middle_color : source_color = vec4(1.0, 0.32, 0.01, 1.0);
uniform vec4 inner_color : source_color = vec4(1.0, 0.85, 0.15, 1.0);
uniform vec4 core_color : source_color = vec4(1.0, 1.0, 0.75, 1.0);


// BRUIT À GRADIENTS (type Perlin), hash SANS sin (le hash sin perd sa précision
// GPU quand le temps défile). Le bruit de VALEURS de flamme_cartoon a une
// structure en grille : ici où tout — silhouette ET couleurs — sort d'un seuil
// sur le bruit, elle donnait des blocs rectangulaires. Le bruit à gradients
// s'annule sur la grille au lieu d'y poser des paliers : pas de blocs.
vec2 gradient(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(vec2(p.x * p.y, p.x + p.y)) * 2.0 - 1.0;
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = dot(gradient(i), f);
	float b = dot(gradient(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
	float c = dot(gradient(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
	float d = dot(gradient(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 0.75 + 0.5;
}

// 4 octaves (5 dans flamme_cartoon) : un jet couvre bien plus de pixels
// qu'une flamme de torche, on ménage le GPU du Mac. La grille est tournée
// DÈS la première octave : aucune arête alignée sur l'écran.
float fbm(vec2 p) {
	const mat2 ROT = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	p = ROT * p;
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 4; i++) {
		value += noise(p) * amplitude;
		p = ROT * p * 2.03 + vec2(17.1, 9.2);
		amplitude *= 0.5;
	}
	return value / 0.9375;      // ramené autour de 0..1
}


void fragment() {
	float p = clamp(puissance, 0.0, 1.0);
	if (p <= 0.002) {
		COLOR = vec4(0.0);      // éteint : rien à calculer, rien à dessiner
	} else {
		float y = 1.0 - UV.y;   // 0 à la buse, 1 en haut du rectangle
		float x = UV.x - 0.5;   // centré

		// faible puissance : le jet CRACHOTE (sa portée tressaute)
		float crachote = mix(0.55 + 0.45 * noise(vec2(TIME * 9.0, 3.7 + graine)), 1.0, smoothstep(0.05, 0.35, p));
		// portée nominale, en fraction du rectangle. 0.8 au maximum : les paquets
		// voyagent encore au-delà (jusqu'à v = 1.25) avant de s'éteindre, et il
		// ne faut pas qu'ils viennent se faire trancher par le haut du rectangle
		float portee = (0.12 + 0.68 * pow(p, 0.75)) * crachote;
		float v = y / max(portee, 0.001);           // 0 à la buse → 1 à la portée nominale
		float vv = clamp(v, 0.0, 1.0);

		// --- LA MATIÈRE : du bruit qui REMONTE le jet -------------------------
		// espace aux vraies proportions (x et y en largeurs de rectangle), qui
		// défile vers le haut à la vitesse du flux
		float flux = ratio * mix(0.35, 0.8, p) * (vitesse / 2.4);
		vec2 q = vec2(x + graine * 7.13, y * ratio - TIME * flux + graine * 3.71);
		float e = detail * 0.7;
		// gros paquets : ce sont eux qu'on voit voyager et se désintégrer
		float gros = fbm(vec2(q.x * e * 1.4, q.y * e * 0.8));
		// détail fin, un peu plus rapide : lèche les bords, fait danser les couleurs
		float fin = fbm(vec2(q.x * e * 3.2 + 5.3, (q.y - TIME * flux * 0.35) * e * 1.9));
		float matiere = clamp((mix(gros, fin, 0.35) - 0.28) / 0.44, 0.0, 1.0);

		// le jet ondule et se tord de plus en plus loin de la buse
		x += (gros - 0.5) * turbulence * 0.35 * vv;
		x += sin(y * 9.0 - TIME * flux * 1.5) * 0.02 * vv;

		// --- LE GABARIT : un cône, qui ne sert qu'à dire où le seuil monte -----
		float veilleuse = 1.0 - smoothstep(0.12, 0.5, p);
		float demi = mix(largeur_buse, largeur_bout * (0.45 + 0.55 * p), pow(vv, 0.8));
		demi *= mix(1.0, 1.0 - 0.6 * smoothstep(0.3, 1.0, v), veilleuse);   // la veilleuse se resserre
		float bord = abs(x) / max(demi, 0.0001);    // 0 dans l'axe, 1 au bord du gabarit

		// --- LA DÉSINTÉGRATION : un seuil que la matière doit dépasser --------
		// il monte le long du jet (front ondulant, pas une ligne droite)…
		float debut = mix(0.9, 0.3, clamp(dispersion * 0.5, 0.0, 1.0));
		debut = mix(debut, debut * 0.6, veilleuse);
		float seuil_bout = smoothstep(debut, 1.25, v + (gros - 0.5) * 0.35);
		// …et vers les bords. Près de la buse le seuil est RAIDE (sortie nette,
		// sous pression), plus loin il est étalé (les bords se dissolvent). Un seul
		// seuil, continu de la buse au bout : le couper près de la buse le rendait
		// plus permissif juste au-dessus → deux ailettes à la jonction
		float loin_buse = smoothstep(0.05, 0.45, v);
		float seuil_bord = mix(smoothstep(0.8, 1.0, bord), smoothstep(0.5, 1.15, bord), loin_buse);
		float seuil = max(seuil_bout, seuil_bord);

		float corps = smoothstep(seuil - 0.12, seuil + 0.02, matiere + 0.02);
		corps *= 1.0 - smoothstep(1.15, 1.4, bord);         // rien loin du gabarit

		// --- CHALEUR → COULEUR ------------------------------------------------
		// maximale dans l'axe, près de la buse, et avec la puissance ; un paquet
		// qui se désintègre REFROIDIT (il rougit avant de disparaître)
		float centre = 1.0 - clamp(bord, 0.0, 1.0);
		float chaleur = centre * (1.0 - vv * 0.65) * (0.5 + 0.5 * p) + (fin - 0.5) * 0.3;
		chaleur *= 0.55 + 0.45 * smoothstep(seuil, seuil + 0.35, matiere);
		chaleur = clamp(chaleur, 0.0, 1.0);

		float aplat = (floor(chaleur * float(nb_bandes)) + 0.5) / float(nb_bandes);
		chaleur = mix(chaleur, aplat, style_cartoon);

		vec3 color;
		if (chaleur < 0.30) {
			color = mix(outer_color.rgb, middle_color.rgb, chaleur / 0.30);
		} else if (chaleur < 0.70) {
			color = mix(middle_color.rgb, inner_color.rgb, (chaleur - 0.30) / 0.40);
		} else {
			color = mix(inner_color.rgb, core_color.rgb, (chaleur - 0.70) / 0.30);
		}

		float gris = dot(color, vec3(0.299, 0.587, 0.114));
		color = clamp(mix(vec3(gris), color, saturation), 0.0, 1.0);

		// contour net en cartoon, fondu en dégradé
		float alpha = mix(corps, smoothstep(0.35, 0.62, corps), style_cartoon);
		COLOR = vec4(color, alpha);
	}
}
