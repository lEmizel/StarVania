shader_type canvas_item;
render_mode unshaded;
// BOUILLON DE SANG (1er oct. 2026) — talisman « Sang bouillant » : le cadavre
// d'un ennemi que le joueur vient de tuer BOUT un instant avant d'exploser.
// Des bulles de sang gonflent sur son corps, montent un peu, puis crèvent
// toutes ensemble au moment où il explose (l'explosion elle-même est
// l'éclaboussure de la boule de sang). Sobre comme les autres effets de sang :
// des aplats rouges, un liseré rouge sombre, un reflet rouge clair, aucun
// blanc.
// Repère : l'origine est le MILIEU du rectangle (le milieu du corps), en px.

// --- fournis par bouillon_sang.gd -------------------------------------------
uniform vec2 taille = vec2(120.0, 170.0);
// 0 → 1 : il bout ; 0 → 1 : les bulles crèvent (il explose)
uniform float bout : hint_range(0.0, 1.0) = 0.7;
uniform float creve : hint_range(0.0, 1.0) = 0.0;
// une valeur par cadavre : deux bouillons ne se ressemblent pas
uniform float graine = 0.0;
// ----------------------------------------------------------------------------

// combien de bulles, dans quelle étendue du corps (px : demi-largeur,
// demi-hauteur), de quelle taille (px : min, max)
uniform int nb_bulles : hint_range(1, 12) = 8;
uniform vec2 etendue = vec2(34.0, 58.0);
uniform vec2 grosseur = vec2(5.0, 13.0);
// épaisseur du liseré (px)
uniform float lisere_px : hint_range(0.0, 4.0) = 1.6;
uniform vec4 couleur : source_color = vec4(0.78, 0.04, 0.12, 1.0);
uniform vec4 sombre : source_color = vec4(0.32, 0.01, 0.06, 1.0);
uniform vec4 clair : source_color = vec4(1.0, 0.55, 0.52, 1.0);

const int NB_MAX = 12;

void par_dessus(inout vec3 rgb, inout float a, vec3 teinte, float force) {
	float total = force + a * (1.0 - force);
	rgb = (teinte * force + rgb * a * (1.0 - force)) / max(total, 0.0001);
	a = total;
}

float alea(float n) {
	return fract(sin(n * 12.9898 + 4.1414) * 43758.5453);
}

void fragment() {
	vec2 p = (UV - 0.5) * taille;
	float b = clamp(bout, 0.0, 1.0);
	float c = clamp(creve, 0.0, 1.0);
	vec3 rgb = couleur.rgb;
	float a = 0.0;
	for (int i = 0; i < NB_MAX; i++) {
		if (i >= nb_bulles) {
			break;
		}
		float fi = float(i);
		float h1 = alea(fi * 1.7 + graine);
		float h2 = alea(fi * 3.3 + graine * 1.9 + 7.0);
		float h3 = alea(fi * 5.1 + graine * 0.7 + 13.0);
		float h4 = alea(fi * 7.9 + graine * 2.3 + 29.0);
		// où elle naît sur le corps (plus serrées vers le milieu)
		vec2 ou = vec2((h1 * 2.0 - 1.0) * etendue.x, (h2 * 2.0 - 1.0) * etendue.y);
		ou *= mix(0.55, 1.0, h3);
		// quand elle commence à gonfler, et jusqu'où ; elle monte en gonflant
		float debut = h4 * 0.55;
		float g = smoothstep(debut, debut + 0.4, b);
		float r = mix(grosseur.x, grosseur.y, h3) * g;
		ou.y -= 10.0 * g;
		// elle crève : elle s'élargit un peu et maigrit jusqu'à rien
		r *= mix(1.0, 1.35, c) * (1.0 - smoothstep(0.2, 1.0, c));
		if (r < 0.3) {
			continue;
		}
		vec2 q = p - ou;
		float d = r - length(q);
		par_dessus(rgb, a, sombre.rgb, smoothstep(-0.5, 0.5, d + lisere_px * (1.0 - c)));
		par_dessus(rgb, a, couleur.rgb, smoothstep(-0.5, 0.5, d));
		// un reflet rouge clair en haut à gauche, qui crève avec elle
		float dr = r * 0.32 - length(q - vec2(-r * 0.35, -r * 0.38));
		par_dessus(rgb, a, clair.rgb, smoothstep(-0.5, 0.5, dr) * 0.85 * (1.0 - c));
	}
	COLOR = vec4(rgb, a);
}
