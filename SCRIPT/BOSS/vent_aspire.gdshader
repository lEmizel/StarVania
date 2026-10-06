shader_type canvas_item;

// ============================================================================
// VENT QUI ASPIRE — le vent du premier boss, qui tire le héros vers elle : des
// filets d'air blancs, effilés aux deux bouts, qui filent vers elle et se
// resserrent sur sa cloche en entonnoir. Même famille que le vent des pièges
// et le souffle du dash : des aplats nets qui maigrissent.
// Visuel seul : c'est le boss qui tire (premier_boss.gd).
// Le rectangle part d'elle (x = 0) et s'étend du côté du héros ; `bouche` est le
// point où tout converge. `force` : 0 = rien, 0.35 = la brise qui prévient,
// 1 = le vent qui tire.
// ============================================================================

uniform vec2 taille = vec2(1700.0, 530.0);
// là où le vent s'engouffre, dans le rectangle (px)
uniform vec2 bouche = vec2(0.0, 260.0);
uniform float temps = 0.0;
uniform float force : hint_range(0.0, 1.0) = 1.0;
uniform float graine = 1.0;
uniform vec4 couleur : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// l'écart entre deux couloirs de vent, loin d'elle (px)
const float COULOIR = 34.0;

varying vec2 local;

void vertex() {
	local = VERTEX;
}

// un hasard ENTIER (le même partout, sur toutes les cartes)
uint va_hacher(uint x) {
	x ^= x >> 16u;
	x *= 0x7feb352du;
	x ^= x >> 15u;
	x *= 0x846ca68bu;
	x ^= x >> 16u;
	return x;
}

float va_alea(int n, int canal) {
	uint h = va_hacher(uint(n + 4096) * 747796405u + uint(canal) * 2891336453u + uint(graine) * 668265263u);
	return float(h & 0xffffffu) / 16777215.0;
}

// ce que le couloir n°`i` dessine au point (x le long du vent, `ecart` px de
// son axe) : un filet effilé qui file vers elle, ou rien
float va_filet(int i, float x, float ecart, float serre) {
	float vitesse = mix(1500.0, 2600.0, va_alea(i, 1));
	float periode = mix(700.0, 1300.0, va_alea(i, 2));
	float longueur = mix(0.22, 0.42, va_alea(i, 3));
	float s = (x + vitesse * temps) / periode + va_alea(i, 4);
	int tour = int(floor(s));
	// un filet sur trois manque : le vent respire ; la brise en a moins encore
	if (va_alea(i * 131 + tour, 5) > 0.3 + 0.5 * force) {
		return 0.0;
	}
	float u = fract(s) / longueur;
	if (u >= 1.0) {
		return 0.0;
	}
	float demi = mix(1.3, 3.1, va_alea(i * 57 + tour, 6)) * (0.55 + 0.45 * force) * pow(sin(3.14159 * u), 0.8);
	return 1.0 - smoothstep(demi * serre - 0.7, demi * serre + 0.7, abs(ecart));
}

void fragment() {
	vec2 p = local;
	float x = p.x;
	if (force < 0.01 || x < 30.0 || x > taille.x) {
		discard;
	}
	// l'entonnoir : loin d'elle les couloirs sont parallèles, près d'elle ils se
	// resserrent sur la bouche
	float serre = mix(0.07, 1.0, pow(smoothstep(0.0, taille.x * 0.5, x), 0.7));
	float hauteur = (p.y - bouche.y) / serre + bouche.y;
	if (hauteur < 6.0 || hauteur > taille.y - 6.0) {
		discard;
	}
	float f = hauteur / COULOIR;
	int i = int(floor(f));
	float a = 0.0;
	for (int di = 0; di <= 1; di++) {
		int couloir = i + di;
		// chaque couloir a son axe, un peu décalé
		float axe = (float(couloir) + 0.2 + 0.6 * va_alea(couloir, 7)) * COULOIR;
		a = max(a, va_filet(couloir, x, (hauteur - axe) * serre, sqrt(serre)));
	}
	// il naît au loin, et disparaît en arrivant sur elle
	a *= smoothstep(taille.x, taille.x - 320.0, x) * smoothstep(30.0, 190.0, x);
	a *= mix(0.55, 0.95, force) * couleur.a;
	if (a < 0.004) {
		discard;
	}
	COLOR = vec4(couleur.rgb, a);
}
