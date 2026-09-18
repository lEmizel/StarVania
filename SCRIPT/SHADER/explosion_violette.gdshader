shader_type canvas_item;
render_mode unshaded;
// EXPLOSION VIOLETTE — pour le monstre kamikaze. Même famille que jet_flamme et
// boule_de_feu : bruit à gradients (hash sans sin), aplats cartoon, palette de
// quatre couleurs. À poser sur un ColorRect CARRÉ, l'explosion part du centre.
//
// TOUT est piloté par `progress` 0 → 1, animé par explosion_violette.gd :
//   0.00 → éclair blanc et départ des traits de force
//   0.15 → la boule est à sa taille, les traits sont au plus long
//   0.40 → les traits ont disparu, la boule commence à se déchirer
//   1.00 → plus rien
//
// TROIS COUCHES, c'est ce qui rend le coup violent plutôt que mou :
//   • la BOULE, grasse et bosselée, qui se déchire en morceaux à la fin ;
//   • les TRAITS DE FORCE, des rayons qui jaillissent plus loin qu'elle, de
//     longueurs et d'épaisseurs toutes différentes, et qui s'affinent en pointe ;
//   • l'ONDE DE CHOC, un anneau fin qui double la boule et file vers l'extérieur.

uniform float progress : hint_range(0.0, 1.0) = 0.0;

// rayon ATTEINT À LA FIN : la boule grandit du début à la fin, elle ne se
// rétracte jamais
uniform float rayon_max : hint_range(0.05, 0.5) = 0.32;
// bosselage du contour : 0 = cercle parfait, 1 = patate
uniform float bosses : hint_range(0.0, 1.0) = 0.42;
// nombre de grosses bosses (petit = masses grasses, grand = découpe fine)
uniform float lobes : hint_range(1.0, 10.0) = 3.2;

uniform int nb_traits : hint_range(4, 40) = 15;
// de combien les plus longs dépassent la boule
uniform float longueur_traits : hint_range(0.0, 3.0) = 1.35;
// épaisseur à la base, en fraction de l'écart entre deux traits
uniform float epaisseur_traits : hint_range(0.05, 1.0) = 0.42;

uniform float onde_force : hint_range(0.0, 1.0) = 0.9;
uniform float onde_epaisseur : hint_range(0.005, 0.2) = 0.045;

uniform float detail : hint_range(1.0, 10.0) = 3.0;
uniform float graine = 0.0;
uniform float style_cartoon : hint_range(0.0, 1.0) = 1.0;
uniform int nb_bandes : hint_range(2, 8) = 4;
uniform float saturation : hint_range(0.0, 2.0) = 1.0;

// palette VIOLET / MAUVE, du plus froid au plus chaud
uniform vec4 outer_color : source_color = vec4(0.20, 0.02, 0.34, 1.0);
uniform vec4 middle_color : source_color = vec4(0.52, 0.12, 0.85, 1.0);
uniform vec4 inner_color : source_color = vec4(0.82, 0.45, 1.0, 1.0);
uniform vec4 core_color : source_color = vec4(1.0, 0.94, 1.0, 1.0);

// (TAU est déjà fourni par le langage de shader de Godot)


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

float fbm(vec2 p) {
	const mat2 ROT = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	p = ROT * p;
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 3; i++) {
		value += noise(p) * amplitude;
		p = ROT * p * 2.03 + vec2(17.1, 9.2);
		amplitude *= 0.5;
	}
	return value / 0.875;
}

// tirage par trait : chacun sa longueur et son épaisseur
float alea(float x) {
	x = fract(x * 0.1031);
	x *= x + 33.33;
	return fract(x * (x + x));
}


void fragment() {
	float p = clamp(progress, 0.0, 1.0);
	if (p >= 0.999) {
		COLOR = vec4(0.0);
	} else {
		vec2 uv = UV - 0.5;
		float d = length(uv);
		float ang = atan(uv.y, uv.x);
		// le bruit est échantillonné SUR UN CERCLE : il fait donc le tour sans
		// couture, là où un bruit pris sur l'angle brut casserait à ±π
		vec2 cercle = vec2(cos(ang), sin(ang));

		// --- rythme ---
		float finir = smoothstep(0.32, 0.95, p);
		// disparition franche des tout derniers instants : sans elle, la coquille
		// resterait visible à p = 1
		float evanouir = 1.0 - smoothstep(0.76, 1.0, p);
		float eclair = 1.0 - smoothstep(0.0, 0.09, p);

		// --- LA BOULE : grasse, bosselée, puis déchirée ---
		// n1 : bruit ANGULAIRE, uniquement pour le contour bosselé
		float n1 = fbm(cercle * lobes + vec2(graine, graine * 1.7));
		// n2 : vrai bruit 2D de la POSITION. Il servait à la matière en bruit
		// angulaire : chaque rayon avait alors la même valeur sur toute sa longueur
		// et la dissolution ouvrait des fentes entières convergeant au centre.
		float n2 = fbm(uv * detail * 3.4 + vec2(graine * 2.3, graine * 0.9));
		float matiere = clamp((mix(n2, n1, 0.25) - 0.28) / 0.44, 0.0, 1.0);
		// souffle rapide au départ, puis expansion qui continue jusqu'au bout
		float rayon = rayon_max * (0.24 + 0.80 * pow(p, 0.42));
		float bord = rayon * (1.0 + bosses * (n1 - 0.5) * 2.0);
		float dans = 1.0 - smoothstep(bord * 0.80, bord, d);
		// le seuil monte PLUS VITE AU CENTRE : la boule se creuse et devient une
		// coquille déchiquetée qui continue de s'ouvrir. Rongée par le bord (ce que
		// je faisais avant), elle semblait se rétracter alors qu'elle grandissait.
		float seuil = finir * (1.55 - 1.0 * clamp(d / max(bord, 0.0001), 0.0, 1.0));
		float boule = dans * smoothstep(seuil - 0.14, seuil + 0.02, matiere + 0.02);

		// --- LES TRAITS DE FORCE : des rayons qui jaillissent ---
		float cellule = (ang / TAU + 0.5) * float(nb_traits);
		float idx = floor(cellule);
		float ecart = fract(cellule) - 0.5;          // 0 au milieu du trait
		float a1 = alea(idx + graine * 3.1);
		float a2 = alea(idx * 1.7 + 11.3 + graine);
		float depart = rayon * 0.30;
		float bout = rayon * (1.05 + longueur_traits * a1);
		float le_long = clamp((d - depart) / max(bout - depart, 0.0001), 0.0, 1.0);
		// s'affine jusqu'à la pointe
		// plus épais à la base, en pointe au bout, et chacun le sien
		float ep = epaisseur_traits * (0.35 + 0.85 * a2) * pow(1.0 - le_long, 1.4) * 0.7;
		float trait = 1.0 - smoothstep(ep * 0.35, ep, abs(ecart));
		trait *= smoothstep(depart * 0.4, depart, d);
		trait *= 1.0 - smoothstep(bout * 0.85, bout, d);
		// ils partent avec le coup et se rétractent bien avant la fin
		trait *= smoothstep(0.0, 0.03, p) * (1.0 - smoothstep(0.16, 0.46, p));

		// --- L'ONDE DE CHOC : un anneau fin qui double la boule ---
		float r_onde = rayon_max * (0.45 + 2.1 * p) * (1.0 + 0.10 * (n1 - 0.5));
		float ep_onde = onde_epaisseur * (1.0 - 0.55 * p);
		float onde = (1.0 - smoothstep(0.0, ep_onde, abs(d - r_onde)));
		onde *= (1.0 - smoothstep(0.12, 0.62, p)) * onde_force;

		// --- L'ÉCLAIR du départ ---
		float coeur = eclair * (1.0 - smoothstep(rayon * 0.5, rayon * 1.25, d));

		boule *= evanouir;
		float corps = max(max(boule, trait), max(onde, coeur));

		// --- CHALEUR → COULEUR ---
		// centre le plus clair, bords violet sombre ; les traits et l'onde sont
		// chauds sur toute leur longueur, c'est ce qui les rend nets
		float chaleur = boule * (1.18 - d / max(bord, 0.0001)) * (1.0 - 0.5 * finir);
		chaleur = max(chaleur, trait * 0.92);
		chaleur = max(chaleur, onde * 0.88);
		chaleur = max(chaleur, coeur * 1.4);
		chaleur += (n2 - 0.5) * 0.16;
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

		float alpha = mix(corps, smoothstep(0.35, 0.62, corps), style_cartoon);
		COLOR = vec4(color, alpha);
	}
}
