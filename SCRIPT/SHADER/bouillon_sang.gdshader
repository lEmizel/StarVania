shader_type canvas_item;
render_mode unshaded;
// BOUILLON DE SANG (1er oct. 2026) — talisman « Sang bouillant » : le sang
// d'un ennemi que l'épée ou la boule de sang a touché BOUT (ébullition, v2 :
// une charge par coup, il explose à la troisième). Des bulles de sang naissent sur son corps,
// gonflent en montant un peu, crèvent et renaissent ailleurs — plus il est
// chargé (`bout`), plus il y en a et plus elles sont grosses ; elles crèvent
// toutes ensemble quand il explose (`creve`). Sobre comme les autres effets de
// sang : des aplats rouges, un liseré rouge sombre, un reflet rouge clair,
// aucun blanc.
// Repère : l'origine est le MILIEU du rectangle (le milieu du corps), en px.

// --- fournis par bouillon_sang.gd -------------------------------------------
uniform vec2 taille = vec2(120.0, 170.0);
// 0 → 1 : il bout (selon ses charges) ; 0 → 1 : toutes les bulles crèvent
uniform float bout : hint_range(0.0, 1.0) = 0.7;
uniform float creve : hint_range(0.0, 1.0) = 0.0;
// une valeur par ennemi : deux bouillons ne se ressemblent pas
uniform float graine = 0.0;
// l'horloge du bouillonnement (s ; elle va plus vite quand il est chargé)
uniform float temps = 0.0;
// ----------------------------------------------------------------------------

// la vie d'une bulle (s : min, max) : elle naît, gonfle, crève, renaît ailleurs
uniform vec2 cycle = vec2(0.5, 0.9);

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
		// son rang : à partir de quelle charge elle bout (fixe)
		float h4 = alea(fi * 7.9 + graine * 2.3 + 29.0);
		// sa vie en cours (la k-ième) et où elle en est (0 → 1)
		float periode = mix(cycle.x, cycle.y, alea(fi * 2.9 + graine * 1.3 + 41.0));
		float u = temps / max(periode, 0.05) + alea(fi * 4.7 + graine * 0.9 + 53.0);
		float k = floor(u);
		float vie = u - k;
		// chaque vie naît ailleurs, avec une autre taille
		float s = graine + k * 3.71;
		float h1 = alea(fi * 1.7 + s);
		float h2 = alea(fi * 3.3 + s * 1.9 + 7.0);
		float h3 = alea(fi * 5.1 + s * 0.7 + 13.0);
		// où elle naît sur le corps (plus serrées vers le milieu)
		vec2 ou = vec2((h1 * 2.0 - 1.0) * etendue.x, (h2 * 2.0 - 1.0) * etendue.y);
		ou *= mix(0.55, 1.0, h3);
		// à partir de quand elle bout, et jusqu'où ; dans sa vie, elle gonfle
		// en montant (0 → 0,7), puis crève (0,7 → 1)
		float debut = h4 * 0.55;
		float g = smoothstep(debut, debut + 0.4, b) * smoothstep(0.0, 0.7, vie);
		float r = mix(grosseur.x, grosseur.y, h3) * g;
		ou.y -= 10.0 * g;
		// elle crève (sa vie finit, ou il explose) : elle s'élargit un peu et
		// maigrit jusqu'à rien
		float cb = max(c, smoothstep(0.7, 1.0, vie));
		r *= mix(1.0, 1.35, cb) * (1.0 - smoothstep(0.2, 1.0, cb));
		if (r < 0.3) {
			continue;
		}
		vec2 q = p - ou;
		float d = r - length(q);
		par_dessus(rgb, a, sombre.rgb, smoothstep(-0.5, 0.5, d + lisere_px * (1.0 - cb)));
		par_dessus(rgb, a, couleur.rgb, smoothstep(-0.5, 0.5, d));
		// un reflet rouge clair en haut à gauche, qui crève avec elle
		float dr = r * 0.32 - length(q - vec2(-r * 0.35, -r * 0.38));
		par_dessus(rgb, a, clair.rgb, smoothstep(-0.5, 0.5, dr) * 0.85 * (1.0 - cb));
	}
	COLOR = vec4(rgb, a);
}
