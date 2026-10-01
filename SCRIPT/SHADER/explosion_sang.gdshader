shader_type canvas_item;
render_mode unshaded;
// EXPLOSION DE SANG BOUILLANT (1er oct. 2026, v4) — talisman « Sang bouillant » :
// au troisième coup (épée ou boule de sang), le sang de l'ennemi qui bout
// explose, et blesse ses voisins (ébullition ; avant, c'était le cadavre d'un
// ennemi tué).
//   v1 : l'éclaboussure de la boule de sang → « manque de punch » ;
//   v2 : jets de sang, gouttes, flaque → « trop goutte de sang, plus explosion
//        tout court » ;
//   v3 : une boule de feu en bandes (famille du kamikaze) → « une trop grosse
//        boule opaque, pas fan, je préfère plus léger et impactant » (Kaoru).
// v4 : LÉGÈRE ET IMPACTANTE — tout se joue en un quart de seconde, et presque
// rien n'est plein :
//   0. L'INSPIRATION (`gonfle`, avant le boum) : une petite boule qui enfle en
//      tremblant sur l'ennemi ;
//   1. L'ÉCLAIR : un disque chaud, déjà là à la première image, parti en
//      quatre images ;
//   2. LES TRAITS DE FORCE : c'est eux le coup — des rayons inégaux, épais au
//      pied, en pointe au bout, qui jaillissent en deux images puis se
//      détachent du centre et maigrissent ;
//   3. L'ANNEAU DE FEU : creux dès le départ (pas de boule pleine), bosselé, il
//      s'élargit en s'amincissant et se déchire en lambeaux ;
//   4. L'ONDE DE CHOC : un anneau fin qui file jusqu'au RAYON DES DÉGÂTS — on
//      voit qui est touché ;
//   5. quelques BRAISES. (La fumée qui montait à la fin est éteinte, `fumee`
//      à 0 : Kaoru n'en voulait pas — remonter le réglage pour la revoir.)
// Même famille que l'explosion du kamikaze (bruit à gradients, aplats en
// bandes, palette de quatre couleurs), en rouge sang ; le plus chaud est un
// corail clair, jamais du blanc.
// Repère : l'origine est le centre de l'explosion (`origine`, en px depuis le
// coin haut-gauche), en px, y vers le bas ; les formes se mesurent en RAYONS
// DES DÉGÂTS (1 = `rayon`).

const int NB_FUMEES = 4;
const int NB_BRAISES = 10;

// --- fournis par bouillon_sang.gd -------------------------------------------
uniform vec2 taille = vec2(720.0, 620.0);
uniform vec2 origine = vec2(360.0, 330.0);
// 0 → 1 : l'inspiration, juste avant le boum
uniform float gonfle : hint_range(0.0, 1.0) = 0.0;
// secondes depuis le boum (< 0 : pas encore)
uniform float t = -1.0;
// le rayon des dégâts (px) : l'onde de choc s'arrête là
uniform float rayon = 180.0;
// px sous le centre jusqu'au sol (< 0 : pas de sol à portée)
uniform float sol = -1.0;
// une valeur par explosion : deux explosions ne se ressemblent pas
uniform float graine = 0.0;
// ----------------------------------------------------------------------------

// --- l'anneau de feu ---
// son rayon au bout de sa course (part du rayon des dégâts), son épaisseur au
// départ (part de son rayon), son bosselage, ses grosses bosses, sa durée (s)
uniform float taille_anneau : hint_range(0.2, 1.0) = 0.55;
uniform float epaisseur_anneau : hint_range(0.1, 1.0) = 0.55;
uniform float bosses : hint_range(0.0, 1.0) = 0.4;
uniform float lobes : hint_range(1.0, 10.0) = 3.2;
uniform float detail : hint_range(1.0, 10.0) = 3.0;
uniform float duree_anneau : hint_range(0.1, 1.0) = 0.32;
// --- les traits de force ---
uniform int nb_traits : hint_range(4, 40) = 13;
// leur longueur (part du rayon des dégâts : le plus long, le plus court)
uniform vec2 longueur_traits = vec2(0.55, 1.1);
// leur demi-épaisseur au pied (px)
uniform float epaisseur_traits : hint_range(1.0, 30.0) = 9.0;
// combien de temps ils vivent (s)
uniform float duree_traits : hint_range(0.05, 0.6) = 0.2;
// --- l'onde de choc (son épaisseur en px) ---
uniform float onde_force : hint_range(0.0, 1.0) = 0.9;
uniform float onde_epaisseur : hint_range(1.0, 30.0) = 6.0;
// --- la fumée, les braises (0 = aucune) ---
uniform float fumee : hint_range(0.0, 1.0) = 0.0;
uniform float braises : hint_range(0.0, 1.0) = 1.0;
// --- le rendu ---
uniform float style_cartoon : hint_range(0.0, 1.0) = 1.0;
uniform int nb_bandes : hint_range(2, 8) = 4;
// palette SANG, du plus froid au plus chaud (pas de blanc)
uniform vec4 outer_color : source_color = vec4(0.24, 0.0, 0.06, 1.0);
uniform vec4 middle_color : source_color = vec4(0.66, 0.03, 0.1, 1.0);
uniform vec4 inner_color : source_color = vec4(1.0, 0.22, 0.22, 1.0);
uniform vec4 core_color : source_color = vec4(1.0, 0.74, 0.62, 1.0);
uniform vec4 couleur_fumee : source_color = vec4(0.3, 0.06, 0.1, 1.0);

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

float alea(float x) {
	x = fract(x * 0.1031);
	x *= x + 33.33;
	return fract(x * (x + x));
}

// part très vite, freine à la fin
float sortie(float x) {
	x = clamp(x, 0.0, 1.0);
	return 1.0 - (1.0 - x) * (1.0 - x) * (1.0 - x);
}

void par_dessus(inout vec3 rgb, inout float a, vec3 teinte, float force) {
	float total = force + a * (1.0 - force);
	rgb = (teinte * force + rgb * a * (1.0 - force)) / max(total, 0.0001);
	a = total;
}

// la chaleur (0 → 1) en couleur, en aplats si `style_cartoon` ; bornée (la
// bande du haut tombait sur 1,125 et débordait vers le crème presque blanc)
vec3 palette(float chaleur) {
	chaleur = clamp(chaleur, 0.0, 0.999);
	float aplat = (floor(chaleur * float(nb_bandes)) + 0.5) / float(nb_bandes);
	chaleur = clamp(mix(chaleur, aplat, style_cartoon), 0.0, 1.0);
	if (chaleur < 0.30) {
		return mix(outer_color.rgb, middle_color.rgb, chaleur / 0.30);
	} else if (chaleur < 0.70) {
		return mix(middle_color.rgb, inner_color.rgb, (chaleur - 0.30) / 0.40);
	}
	return mix(inner_color.rgb, core_color.rgb, (chaleur - 0.70) / 0.30);
}

void fragment() {
	vec2 p = UV * taille - origine;
	float R = max(rayon, 1.0);
	vec3 rgb = outer_color.rgb;
	float a = 0.0;
	float d_px = length(p);
	float ang = atan(p.y, p.x);

	if (t < 0.0) {
		// ================= 0. L'INSPIRATION =================
		float g = clamp(gonfle, 0.0, 1.0);
		float rb = mix(6.0, R * 0.16, g * g) * (1.0 + 0.1 * g * sin(ang * 5.0 + g * 40.0));
		float chaleur = clamp((1.15 - d_px / max(rb, 1.0)) * mix(0.55, 1.0, g), 0.0, 1.0);
		par_dessus(rgb, a, palette(chaleur), smoothstep(-0.5, 0.5, rb - d_px) * step(0.001, g));
		COLOR = vec4(rgb, a);
	} else {
		float T = t;
		float d = d_px / R;
		vec2 cercle = vec2(cos(ang), sin(ang));
		float n1 = fbm(cercle * lobes + vec2(graine, graine * 1.7));

		// ================= 5a. UN PEU DE FUMÉE (derrière) =================
		if (fumee > 0.0) {
			for (int k = 0; k < NB_FUMEES; k++) {
				float fk = float(k);
				float h1 = alea(fk * 3.1 + graine * 7.0 + 1.0);
				float h2 = alea(fk * 5.3 + graine * 3.0 + 2.0);
				float h3 = alea(fk * 7.7 + graine * 5.0 + 3.0);
				float vie = clamp((T - 0.08) / (0.5 + 0.25 * h2), 0.0, 1.0);
				if (vie <= 0.0) {
					continue;
				}
				float ak = -PI * 0.5 + (fk / float(NB_FUMEES - 1) - 0.5) * 2.0 + (h1 - 0.5) * 0.5;
				vec2 ck = vec2(cos(ak), sin(ak)) * R * (0.25 + 0.25 * sortie(vie)) + vec2(0.0, -R * 0.45 * vie);
				float rk = R * (0.1 + 0.14 * sortie(vie)) * (0.8 + 0.4 * h3);
				float n = fbm((p - ck) / R * 3.2 + vec2(fk * 7.0 + graine, -T * 0.9));
				float dk = rk * (0.7 + 0.55 * n) - length(p - ck);
				float force = smoothstep(0.0, 0.15, vie) * (1.0 - smoothstep(0.3, 1.0, vie)) * fumee;
				par_dessus(rgb, a, couleur_fumee.rgb, smoothstep(-0.5, 0.5, dk) * force);
			}
		}

		// ================= 3. L'ANNEAU DE FEU (creux) =================
		float pr = clamp(T / duree_anneau, 0.0, 1.0);
		float n2 = fbm(p / R * detail * 1.35 + vec2(graine * 2.3, graine * 0.9));
		float exterieur = taille_anneau * (0.35 + 0.65 * pow(pr, 0.45));
		exterieur *= 1.0 + bosses * (n1 - 0.5) * 2.0;
		// le trou s'ouvre dès le départ : l'anneau s'amincit en s'élargissant
		float interieur = exterieur * mix(1.0 - epaisseur_anneau, 0.97, pow(pr, 0.7));
		float dans = smoothstep(interieur - 0.01, interieur + 0.015, d) * (1.0 - smoothstep(exterieur - 0.015, exterieur, d));
		// il se déchire en lambeaux
		float matiere = clamp((mix(n2, n1, 0.3) - 0.28) / 0.44, 0.0, 1.0);
		float dechire = smoothstep(0.25, 0.85, pr);
		float anneau = dans * smoothstep(dechire - 0.1, dechire + 0.05, matiere) * (1.0 - smoothstep(0.8, 1.0, pr));
		if (sol >= 0.0) {
			anneau *= 1.0 - smoothstep(sol, sol + 6.0, p.y);          // pas sous le sol
		}
		float ch_anneau = (0.95 - 0.6 * pr) - 0.25 * clamp((d - interieur) / max(exterieur - interieur, 0.001), 0.0, 1.0);
		par_dessus(rgb, a, palette(ch_anneau + (n2 - 0.5) * 0.15), smoothstep(0.35, 0.62, anneau));

		// ================= 2. LES TRAITS DE FORCE =================
		float vt = clamp(T / duree_traits, 0.0, 1.0);
		if (vt < 1.0) {
			float cellule = (ang / TAU + 0.5) * float(nb_traits);
			float idx = floor(cellule);
			float ecart_px = (fract(cellule) - 0.5) * TAU / float(nb_traits) * d_px;   // px en travers
			float a1 = alea(idx + graine * 3.1);
			float a2 = alea(idx * 1.7 + 11.3 + graine);
			float bout = R * mix(longueur_traits.x, longueur_traits.y, a1) * sortie(T / 0.035);
			// le pied se détache du centre et court vers la pointe
			float pied = bout * smoothstep(0.15, 1.0, vt) * 0.85 + R * 0.08;
			float le_long = clamp((d_px - pied) / max(bout - pied, 0.001), 0.0, 1.0);
			float demi = epaisseur_traits * (0.5 + 0.7 * a2) * pow(1.0 - le_long, 1.3) * (1.0 - vt * 0.6);
			float trait = smoothstep(-0.5, 0.5, demi - abs(ecart_px))
					* step(pied, d_px) * step(d_px, bout);
			par_dessus(rgb, a, palette(mix(0.95, 0.6, le_long) - 0.3 * vt), trait);
		}

		// ================= 4. L'ONDE DE CHOC =================
		float r_onde = mix(0.25, 1.0, sortie(T / 0.13)) * (1.0 + 0.05 * (n1 - 0.5));
		float ep_onde = onde_epaisseur * (1.0 - 0.6 * smoothstep(0.0, 0.22, T));
		float onde = smoothstep(-0.5, 0.5, ep_onde * 0.5 - abs(d_px - r_onde * R));
		onde *= (1.0 - smoothstep(0.1, 0.24, T)) * onde_force;
		par_dessus(rgb, a, palette(0.85 - 0.3 * smoothstep(0.0, 0.2, T)), onde);

		// ================= 1. L'ÉCLAIR =================
		float rc = R * 0.26 * (0.85 + 0.15 * sortie(T / 0.02)) * (1.0 - smoothstep(0.02, 0.07, T));
		rc *= 1.0 + 0.1 * sin(ang * 7.0 + graine * 5.0);
		if (rc > 0.5) {
			float ch_c = 1.0 - 0.45 * clamp(d_px / rc, 0.0, 1.0);
			par_dessus(rgb, a, palette(ch_c), smoothstep(-0.5, 0.5, rc - d_px));
		}

		// ================= 5b. LES BRAISES =================
		if (braises > 0.0) {
			for (int k = 0; k < NB_BRAISES; k++) {
				float fk = float(k);
				float h1 = alea(fk * 2.3 + graine * 11.0 + 4.0);
				float h2 = alea(fk * 4.9 + graine * 13.0 + 5.0);
				float h3 = alea(fk * 7.1 + graine * 17.0 + 6.0);
				float vie = clamp(T / (0.35 + 0.2 * h3), 0.0, 1.0);
				if (vie >= 1.0 || T < 0.02) {
					continue;
				}
				float ak = -PI * 0.5 + (h1 * 2.0 - 1.0) * 2.2;
				vec2 dir = vec2(cos(ak), sin(ak));
				float dist = R * (0.3 + (0.75 + 0.55 * h2) * sortie(vie));
				vec2 qb = p - dir * dist;
				vec2 ql = vec2(dot(qb, dir), dot(qb, vec2(-dir.y, dir.x)));
				float taille_b = (2.0 + 2.0 * h3) * (1.0 - vie) * braises;
				if (ql.x < 0.0) {
					ql.x /= 1.0 + 4.0 * (1.0 - vie);
				}
				par_dessus(rgb, a, palette(mix(0.95, 0.55, vie)), smoothstep(-0.5, 0.5, taille_b - length(ql)));
			}
		}
		COLOR = vec4(rgb, a);
	}
}
