shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;
// TROU NOIR (2 oct. 2026, piège choisi par Kaoru : « simple et spectaculaire »,
// sur le modèle du pilier de foudre). Inspiré de Gargantua (Interstellar) :
//   • l'OMBRE : un disque parfaitement noir ;
//   • la LENTILLE : le décor derrière lui se tord (il lit l'écran) — tout près
//     de l'ombre, il se retourne en anneau (l'anneau d'Einstein) ;
//   • le DISQUE D'ACCRÉTION vu presque par la tranche : une bande qui passe
//     DEVANT l'ombre, du gaz en filaments qui tourne (plus vite au bord
//     intérieur), plus clair du côté qui vient vers nous (à gauche) ;
//   • son IMAGE COURBÉE : l'arrière du disque, dévié par-dessus l'ombre (le
//     grand arc du haut) et par-dessous (l'arc mince du bas) ;
//   • l'ANNEAU DE PHOTONS : un fil de lumière qui épouse l'ombre ;
//   • les POUSSIÈRES qui tombent en spirale : elles montrent jusqu'où il aspire ;
//   • quand il MANGE (`festin` 1 → 0) : éclair, JETS aux pôles, onde dans le décor.
// Piloté par SCRIPT/INTERACTIBLE/trou_noir.gd. Lumière ajoutée (alpha
// prémultiplié) ; l'ombre et le décor tordu sont opaques et se fondent dans
// le vrai décor avant le bord du rectangle (aucun carré visible).

uniform sampler2D ecran : hint_screen_texture, filter_linear;
uniform vec2 taille = vec2(1100.0, 1100.0);
uniform float rayon = 46.0;                       // l'ombre, éveillé (px)
uniform float eveil : hint_range(0.0, 1.0) = 1.0; // 0 endormi (une braise) → 1 ouvert
uniform float festin : hint_range(0.0, 1.0) = 0.0;
uniform float temps = 0.0;
uniform float portee = 520.0;                     // jusqu'où tombent les poussières (px)

uniform float inclinaison : hint_range(0.02, 0.6) = 0.16;  // le disque vu presque par la tranche
uniform float disque_interieur = 1.4;             // en rayons de l'ombre
uniform float disque_exterieur = 5.0;
uniform float lentille = 1.4;                     // l'anneau d'Einstein, en rayons de l'ombre
uniform float vrille_decor = 0.9;                 // le décor tourne autour de lui (radians, au bord de l'ombre)
uniform float vitesse_disque = 0.3;               // tours par seconde au bord intérieur
uniform float intensite = 1.3;
uniform float poussieres : hint_range(0.0, 2.0) = 1.0;

uniform vec4 couleur_blanche : source_color = vec4(1.0, 0.95, 0.85, 1.0);
uniform vec4 couleur_chaude : source_color = vec4(1.0, 0.58, 0.18, 1.0);
uniform vec4 couleur_froide : source_color = vec4(0.72, 0.1, 0.06, 1.0);
uniform vec4 couleur_jets : source_color = vec4(0.62, 0.8, 1.0, 1.0);


// hachage ENTIER (un hachage flottant se décale d'un pixel à l'autre une fois
// compilé : le bruit gagne des coutures)
float alea_i(ivec3 q) {
	uvec3 u = uvec3(q + ivec3(4096));
	uint h = (u.x * 1597334677u) ^ (u.y * 3812015801u) ^ (u.z * 2798796415u);
	h ^= h >> 16u;
	h *= 2246822519u;
	h ^= h >> 13u;
	h *= 3266489917u;
	h ^= h >> 16u;
	return float(h) * (1.0 / 4294967295.0);
}

float bruit(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 s = f * f * (3.0 - 2.0 * f);
	ivec3 q = ivec3(i);
	float a = alea_i(q);
	float b = alea_i(q + ivec3(1, 0, 0));
	float c = alea_i(q + ivec3(0, 1, 0));
	float d = alea_i(q + ivec3(1, 1, 0));
	float e = alea_i(q + ivec3(0, 0, 1));
	float f1 = alea_i(q + ivec3(1, 0, 1));
	float g = alea_i(q + ivec3(0, 1, 1));
	float h = alea_i(q + ivec3(1, 1, 1));
	return mix(mix(mix(a, b, s.x), mix(c, d, s.x), s.y), mix(mix(e, f1, s.x), mix(g, h, s.x), s.y), s.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float amp = 0.55;
	for (int k = 0; k < 3; k++) {
		v += amp * bruit(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		amp *= 0.5;
	}
	return v / 0.9625;
}

// la lumière du disque au point (rho, phi) de SON plan (phi = π/2 : le bord
// tourné vers nous). Pas d'alpha : c'est de la lumière qui s'ajoute.
vec3 disque(float rho, float phi, float ri, float ro) {
	if (rho < ri * 0.92 || rho > ro) {
		return vec3(0.0);
	}
	float x = clamp((rho - ri) / max(ro - ri, 0.001), 0.0, 1.0);
	// très clair au bord intérieur, s'éteint vers l'extérieur
	float profil = smoothstep(-0.03, 0.05, x) * pow(1.0 - x, 1.25) * (0.5 + 0.5 * exp(-x * 3.0));
	// le gaz tourne, plus vite près du centre ; deux phases fondues l'une dans
	// l'autre pour que l'étirement ne devienne jamais des fils infinis
	float omega = vitesse_disque * TAU * pow(ri / max(rho, 1.0), 1.5);
	float periode = 4.0;
	float t1 = mod(temps, periode);
	float t2 = mod(temps + periode * 0.5, periode);
	float w1 = 1.0 - abs(t1 / periode * 2.0 - 1.0);
	float a1 = phi + omega * t1;
	float a2 = phi + omega * t2;
	vec3 c1 = vec3(cos(a1) * 3.2, sin(a1) * 3.2, rho * 0.16);
	vec3 c2 = vec3(cos(a2) * 3.2 + 7.3, sin(a2) * 3.2 + 1.9, rho * 0.16 + 4.1);
	float n = fbm(c1) * w1 + fbm(c2) * (1.0 - w1);
	float gaz = smoothstep(0.3, 0.8, n);
	// le côté qui vient vers nous (à gauche) est plus clair et plus blanc
	float dop = max(1.0 - cos(phi) * 0.6 * sqrt(ri / max(rho, 1.0)), 0.15);
	float lum = profil * (0.35 + gaz) * dop * dop;
	float chaleur = clamp((1.0 - x) * (0.55 + 0.45 * dop), 0.0, 1.0);
	vec3 col = mix(couleur_froide.rgb, couleur_chaude.rgb, smoothstep(0.1, 0.6, chaleur));
	col = mix(col, couleur_blanche.rgb, smoothstep(0.62, 1.0, chaleur));
	return col * lum;
}

// les poussières qui tombent en spirale : une grille en coordonnées
// log-polaires qui glisse vers le centre (chaque grain y suit sa spirale)
vec3 poussiere(vec2 p, float r, float ri) {
	if (r > portee || r < ri * 0.9) {
		return vec3(0.0);
	}
	float lr = log(max(r, 1.0));
	float angle = atan(p.y, p.x);
	vec3 total = vec3(0.0);
	for (int couche = 0; couche < 2; couche++) {
		float fc = float(couche);
		float nu = 9.0 + 5.0 * fc;          // grains par unité de log-rayon
		float na = 26.0 + 14.0 * fc;        // grains sur un tour
		float vit = 0.5 + 0.22 * fc;        // chute (log-rayon par seconde)
		float vrille = 1.1;
		vec2 g = vec2((lr + vit * temps) * nu, (angle + vrille * lr) / TAU * na);
		vec2 cel = floor(g);
		for (int i = -1; i <= 1; i++) {
			for (int j = -1; j <= 1; j++) {
				vec2 cc = cel + vec2(float(i), float(j));
				ivec3 id = ivec3(int(cc.x), int(mod(cc.y, na)), 7 + couche);
				if (alea_i(id) > 0.16 - 0.06 * fc) {
					continue;
				}
				vec2 off = vec2(alea_i(id + ivec3(0, 0, 31)), alea_i(id + ivec3(0, 0, 57))) * 0.7 + 0.15;
				float lrs = (cc.x + off.x) / nu - vit * temps;
				float rs = exp(lrs);
				if (rs > portee || rs < ri * 0.9) {
					continue;
				}
				float a_s = (cc.y + off.y) / na * TAU - vrille * lrs;
				vec2 ps = rs * vec2(cos(a_s), sin(a_s));
				// il file vers le centre en tournant : une traînée derrière lui
				vec2 vel = (-ps + vrille * vec2(-ps.y, ps.x)) * vit;
				float v = length(vel);
				vec2 dir = vel / max(v, 0.001);
				vec2 dp = p - ps;
				float le_long = dot(dp, dir);
				float travers = dot(dp, vec2(-dir.y, dir.x));
				float trainee = clamp(v * 0.05, 2.0, 18.0);
				float d = length(vec2(travers, le_long < 0.0 ? le_long / trainee * 1.4 : le_long / 1.4));
				float grain = exp(-d * d / 1.0);
				// il apparaît au bord de la zone, s'allume en approchant
				float vie = smoothstep(portee, portee * 0.75, rs) * smoothstep(ri * 0.9, ri * 1.6, rs);
				float proche = 1.0 - smoothstep(ri, portee, rs);
				vec3 c = mix(couleur_froide.rgb, couleur_chaude.rgb, proche);
				total += c * grain * vie * (0.2 + 0.6 * proche);
			}
		}
	}
	return total;
}

void fragment() {
	vec2 pix = UV * taille;
	vec2 p = pix - taille * 0.5;
	float px = max(fwidth(pix.x), 0.0001);
	float r = length(p);
	float r_max = min(taille.x, taille.y) * 0.5;
	float vie = smoothstep(0.0, 1.0, eveil);
	float R = rayon * mix(0.16, 1.0, vie);
	float ri = disque_interieur * R;
	float ro = disque_exterieur * R * mix(0.55, 1.0, vie);
	// l'éveil : l'anneau flambe à mi-chemin
	float eclat = pow(sin(3.14159 * vie), 2.0) * (1.0 - step(0.999, vie));
	float age = 1.0 - festin;

	// ===================== LA LENTILLE =====================
	// un point du décor à la distance β du centre se voit à θ, avec
	// β = θ − θE²/θ : on va chercher le décor plus près du centre — sous
	// l'anneau d'Einstein (θ < θE), de l'autre côté : il se retourne
	vec2 dir_r = r > 0.001 ? p / r : vec2(0.0, -1.0);
	float theta_e = lentille * R;
	float devie = theta_e * theta_e / max(r, R * 0.6);
	devie *= 1.0 - smoothstep(r_max * 0.45, r_max * 0.95, r);
	// quand il mange : une onde file dans le décor
	float onde = exp(-pow((r - (R + age * 620.0)) / 24.0, 2.0)) * festin * festin;
	devie += onde * 16.0;
	// et l'espace tourne avec lui : le décor s'enroule autour de l'ombre
	float vrille = vrille_decor * pow(R / max(r, R), 1.5) * (1.0 - smoothstep(r_max * 0.45, r_max * 0.95, r));
	vec2 source = p - dir_r * devie;
	source = vec2(source.x * cos(vrille) - source.y * sin(vrille), source.x * sin(vrille) + source.y * cos(vrille));
	vec2 uv = SCREEN_UV + (source - p) / px * SCREEN_PIXEL_SIZE;
	vec3 fond = texture(ecran, uv).rgb;
	fond *= mix(0.45, 1.0, smoothstep(R, R * 2.6, r));   // la lumière s'y perd, près du bord
	float ombre = 1.0 - smoothstep(R - px, R + px, r);
	float dehors = 1.0 - ombre;
	vec3 col = fond * dehors;

	// ===================== LE DISQUE, vu par la tranche =====================
	vec3 lum = vec3(0.0);
	vec2 q = vec2(p.x, p.y / inclinaison);
	float phi = atan(q.y, q.x);
	vec3 plat = disque(length(q), phi, ri, ro);
	if (phi < 0.0) {
		plat *= 1.0 - ombre;                  // l'arrière du disque passe derrière l'ombre
	} else {
		// devant l'ombre, seul le gaz brillant se voit : le bord extérieur, terne,
		// salissait le bas de l'ombre d'un voile brun
		float eclat_gaz = max(plat.r, max(plat.g, plat.b));
		plat *= mix(1.0, smoothstep(0.12, 0.45, eclat_gaz), ombre);
	}
	lum += plat;

	// ===================== SON IMAGE COURBÉE =====================
	// l'arrière du disque, dévié par-dessus l'ombre : le grand arc du haut…
	float alpha = atan(p.y, p.x);
	float haut = max(-sin(alpha), 0.0);
	float r0 = R * 1.04;
	float r1 = R * (1.05 + 1.15 * pow(haut, 0.55));
	if (haut > 0.0 && r > r0 && r < r1) {
		lum += disque(mix(ri, ro, pow((r - r0) / (r1 - r0), 1.5)), alpha, ri, ro) * 1.5;
	}
	// … et par-dessous : l'arc mince du bas
	float bas = max(sin(alpha), 0.0);
	float r2 = R * (1.03 + 0.42 * pow(bas, 0.8));
	if (bas > 0.0 && r > R * 1.03 && r < r2) {
		lum += disque(mix(ri, ro, pow((r - R * 1.03) / (r2 - R * 1.03), 1.5)), -alpha, ri, ro) * 0.9;
	}

	// ===================== L'ANNEAU DE PHOTONS =====================
	float anneau = exp(-pow((r - R * 1.02) / (0.016 * R + 0.9 * px), 2.0));
	lum += couleur_blanche.rgb * anneau * (1.0 - 0.45 * cos(alpha)) * (1.0 + 2.5 * festin + 2.0 * eclat);

	// ===================== LA LUEUR =====================
	float de = length(vec2(p.x / (ro * 1.1), p.y / (ro * 0.32)));
	lum += couleur_chaude.rgb * exp(-de * de * 2.5) * 0.12 * (1.0 + festin) * dehors;
	lum += couleur_chaude.rgb * exp(-max(r - R, 0.0) / (0.5 * R)) * 0.25 * dehors * (1.0 + festin + eclat);
	lum *= intensite * mix(0.3, 1.0, vie);

	// ===================== LES POUSSIÈRES ASPIRÉES =====================
	lum += poussiere(p, r, ri) * poussieres * smoothstep(0.35, 1.0, vie) * dehors;

	// ===================== LES JETS (quand il mange) =====================
	if (festin > 0.0) {
		float ay = abs(p.y);
		float longueur = R + 400.0 * smoothstep(0.0, 0.3, age);
		float w = 2.5 + 0.05 * ay;
		float coeur = exp(-pow(p.x / w, 2.0));
		float halo_j = exp(-pow(p.x / (w * 4.0), 2.0)) * 0.35;
		float le_long = smoothstep(longueur, longueur * 0.75, ay) * smoothstep(R * 0.8, R * 1.2, ay);
		float vibre = 0.75 + 0.25 * bruit(vec3(ay * 0.04 - temps * 25.0, p.x * 0.1, 3.0));
		lum += (couleur_blanche.rgb * coeur + couleur_jets.rgb * halo_j) * le_long * vibre * pow(festin, 0.6) * 1.6 * dehors;
	}
	// l'onde : un liseré de lumière
	lum += couleur_blanche.rgb * onde * 0.12 * dehors;

	// rien ne touche le bord du rectangle
	lum *= 1.0 - smoothstep(r_max * 0.85, r_max * 0.99, r);
	float a = max(1.0 - smoothstep(r_max * 0.6, r_max * 0.98, r), ombre);
	COLOR = vec4(col * a + lum, a);
}
