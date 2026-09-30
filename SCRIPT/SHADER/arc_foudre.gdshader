shader_type canvas_item;
render_mode unshaded;
// ARC DE FOUDRE — l'éclair qui bondit d'un ennemi à l'autre (talisman « Lame
// de foudre », 30 sept. 2026). Dessiné dans un rectangle couché de l'ennemi
// touché (à gauche, x = 0) à sa victime (à droite, x = taille.x) ; arc_foudre.gd
// le tend entre les deux et le fait vivre.
//
// Deux brins brisés (un gros, un fin) tendus entre les deux bouts, ancrés aux
// deux extrémités, qui changent `cadence` fois par seconde ; une lueur bleue ;
// un éclat à l'arrivée, plus petit au départ. Sur la fin (`progression` > 0,55)
// l'arc se calme et s'efface.

// --- fournis par arc_foudre.gd ---
uniform vec2 taille = vec2(300.0, 90.0);
uniform float progression : hint_range(0.0, 1.0) = 0.3;
uniform float temps = 0.0;
uniform float graine = 0.0;
// --- l'allure ---
// combien l'arc s'écarte de la ligne droite (part de la longueur, bornée)
uniform float ampleur : hint_range(0.0, 0.5) = 0.2;
// épaisseur du cœur blanc du gros brin (px)
uniform float epaisseur : hint_range(0.5, 5.0) = 2.0;
// combien de fois par seconde l'arc change
uniform float cadence : hint_range(2.0, 60.0) = 30.0;
// rayon de l'éclat à l'arrivée (px)
uniform float eclat : hint_range(0.0, 40.0) = 14.0;
uniform vec4 couleur : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 couleur_foudre : source_color = vec4(0.45, 0.72, 1.0, 1.0);

float alea(vec2 p) {
	p = fract(p * vec2(443.897, 441.423));
	p += dot(p, p.yx + 19.19);
	return fract((p.x + p.y) * p.x);
}

// une ligne brisée au hasard : entre -1 et 1, un sommet à chaque entier
float brisee(float x, float g) {
	float i = floor(x);
	float a = alea(vec2(i, g)) * 2.0 - 1.0;
	float b = alea(vec2(i + 1.0, g)) * 2.0 - 1.0;
	return mix(a, b, x - i);
}

// l'écart du brin à la ligne droite, à `x` px du départ : nul aux deux bouts
float ecart(float x, float L, float amp, float g) {
	float v = x / L;
	float z = brisee(v * 7.0, g) + 0.5 * brisee(v * 15.0 + 4.7, g + 1.3);
	return amp * z * pow(sin(clamp(v, 0.0, 1.0) * PI), 0.6);
}

// distance (px) du point q au brin, qui tient compte de sa pente
float dist_brin(vec2 q, float L, float amp, float g) {
	float x = clamp(q.x, 0.0, L);
	float e = ecart(x, L, amp, g);
	float de = (ecart(min(x + 1.0, L), L, amp, g) - ecart(max(x - 1.0, 0.0), L, amp, g)) * 0.5;
	return abs(q.y - e) / sqrt(1.0 + de * de);
}

vec4 par_dessus(vec4 dessous, vec4 dessus) {
	float a = dessus.a + dessous.a * (1.0 - dessus.a);
	return vec4((dessus.rgb * dessus.a + dessous.rgb * dessous.a * (1.0 - dessus.a)) / max(a, 0.0001), a);
}

void fragment() {
	vec2 q = vec2(UV.x * taille.x, (UV.y - 0.5) * taille.y);
	float L = taille.x;
	float px = max(fwidth(q.x), fwidth(q.y)) * 0.75;
	float tic = floor(temps * cadence + graine * 7.0);
	// sur la fin l'arc se calme (moins d'écart) et s'efface
	float fin = smoothstep(0.55, 1.0, progression);
	float amp = min(ampleur * L, 34.0) * (1.0 - 0.6 * fin);
	float force = 1.0 - fin;

	float coeur = 0.0;
	float lueur = 0.0;
	// le gros brin, et un fin qui le croise
	for (int k = 0; k < 2; k++) {
		float fk = float(k);
		float g = graine + tic * 3.1 + fk * 11.0;
		float d = dist_brin(q, L, amp * (k == 0 ? 1.0 : 0.8), g);
		float w = epaisseur * (k == 0 ? 1.0 : 0.5);
		float f = force * (k == 0 ? 1.0 : 0.7) * (0.75 + 0.25 * alea(vec2(tic, graine + fk)));
		coeur = max(coeur, f * (1.0 - smoothstep(w - px, w + px, d)));
		lueur = max(lueur, f * 0.7 * (1.0 - smoothstep(0.0, w + 7.0, d)));
	}
	// l'éclat à l'arrivée (et un petit au départ), qui grossit puis meurt
	float vie_eclat = sin(clamp(progression / 0.7, 0.0, 1.0) * PI);
	float r_arrivee = length(q - vec2(L, 0.0));
	float r_depart = length(q);
	float re = eclat * vie_eclat;
	coeur = max(coeur, 1.0 - smoothstep(re * 0.55 - px, re * 0.55 + px, r_arrivee));
	lueur = max(lueur, 0.8 * (1.0 - smoothstep(0.0, re * 1.6, r_arrivee)));
	coeur = max(coeur, 1.0 - smoothstep(re * 0.3 - px, re * 0.3 + px, r_depart));
	lueur = max(lueur, 0.6 * (1.0 - smoothstep(0.0, re, r_depart)));

	vec4 c = vec4(couleur_foudre.rgb, lueur * couleur_foudre.a);
	c = par_dessus(c, vec4(couleur.rgb, coeur * couleur.a));
	COLOR = c;
}
