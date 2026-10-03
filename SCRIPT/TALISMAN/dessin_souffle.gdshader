shader_type canvas_item;
render_mode unshaded;
// DESSIN DU TALISMAN « SECOND SOUFFLE » (menu START, 1er oct. 2026) —
// provisoire, en attendant le dessin définitif.
// emplacement_talisman.gd le pose dans le rond et lui fournit `opacite`,
// `eveil` et `temps`.
// TOUT LE ROND est au dessin : un disque de nuit cerné d'un trait d'encre ; un
// TOURBILLON de souffle (trois rubans qui s'enroulent autour du centre, effilés
// au bout) ; au centre un CŒUR fendu en deux mais RECOUSU — trois points de
// couture en travers de la fente. Il a cassé, et il tient. Aplats rouges et
// encre, fil et reflet rouge clair (pas de blanc). Pointé ou porté (`eveil`),
// le tourbillon tourne et le cœur bat de temps en temps.
// À dessiner dans un CARRÉ : le disque le remplit.

// --- fournis par emplacement_talisman.gd (les mêmes pour tout dessin de talisman) ---
uniform float opacite : hint_range(0.0, 1.0) = 1.0;
uniform float eveil : hint_range(0.0, 1.0) = 0.0;
uniform float temps = 0.0;
// ----------------------------------------------------------------------------

uniform vec4 encre_color : source_color = vec4(0.1, 0.02, 0.04, 1.0);
uniform vec4 fond_color : source_color = vec4(0.06, 0.02, 0.04, 1.0);
uniform vec4 fond_centre : source_color = vec4(0.16, 0.03, 0.05, 1.0);
uniform float trait : hint_range(0.0, 0.1) = 0.045;
uniform vec4 couleur : source_color = vec4(0.76, 0.03, 0.11, 1.0);
uniform vec4 sombre : source_color = vec4(0.32, 0.01, 0.06, 1.0);
uniform vec4 clair : source_color = vec4(1.0, 0.55, 0.5, 1.0);
uniform vec4 fil : source_color = vec4(0.96, 0.72, 0.62, 1.0);

float disque(float d, float r, float px) {
	return smoothstep(r + px * 0.5, r - px * 0.5, d);
}

void par_dessus(inout vec3 rgb, inout float a, vec3 teinte, float force) {
	float total = force + a * (1.0 - force);
	rgb = (teinte * force + rgb * a * (1.0 - force)) / max(total, 0.0001);
	a = total;
}

void forme(inout vec3 rgb, inout float a, float d, vec3 teinte, vec3 encre, float e, float px) {
	par_dessus(rgb, a, encre, smoothstep(0.0, px, d + e));
	par_dessus(rgb, a, teinte, smoothstep(0.0, px, d));
}

float sd_coeur(vec2 q) {
	q.x = abs(q.x);
	q.y = -q.y + 0.35;
	if (q.y + q.x > 1.0) {
		return sqrt(dot(q - vec2(0.25, 0.75), q - vec2(0.25, 0.75))) - sqrt(2.0) / 4.0;
	}
	float d1 = dot(q - vec2(0.0, 1.0), q - vec2(0.0, 1.0));
	float m = 0.5 * max(q.x + q.y, 0.0);
	float d2 = dot(q - vec2(m), q - vec2(m));
	return sqrt(min(d1, d2)) * sign(q.x - q.y);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float px = fwidth(UV.x) * 2.0;
	float e = 0.04;

	vec3 rgb = encre_color.rgb;
	float a = disque(r, 1.0, px);
	float champ = disque(r, 1.0 - trait, px);
	rgb = mix(rgb, mix(fond_centre.rgb, fond_color.rgb, smoothstep(0.0, 0.95, r)), champ);

	vec3 f_rgb = couleur.rgb;
	float f_a = 0.0;

	// ===================== LE TOURBILLON DE SOUFFLE =====================
	// trois rubans en spirale : le rayon diminue en tournant, épais au milieu,
	// effilés aux deux bouts ; le premier est clair, les autres sombres
	float tourne = temps * 0.6 * eveil;
	for (int k = 0; k < 3; k++) {
		float fk = float(k);
		float th = atan(p.y, p.x) - tourne - fk * TAU / 3.0;
		float tt = fract(th / TAU);                               // 0 → 1 autour
		float r_ruban = mix(0.9, 0.5, tt);                       // il s'enroule vers le centre
		float long_ruban = smoothstep(0.0, 0.12, tt) * (1.0 - smoothstep(0.62, 0.78, tt));
		float ep = 0.065 * long_ruban;
		float d = ep - abs(r - r_ruban);
		vec3 teinte = fk == 0.0 ? couleur.rgb : sombre.rgb * (1.9 - 0.4 * fk);
		forme(f_rgb, f_a, d, teinte, encre_color.rgb, e * 0.7 * step(0.01, ep), px);
		// un fil clair le long du ruban principal
		if (k == 0) {
			par_dessus(f_rgb, f_a, clair.rgb, smoothstep(0.0, px, min(ep * 0.25 - abs(r - r_ruban + ep * 0.35), d - 0.01)) * 0.8);
		}
	}

	// ===================== LE CŒUR RECOUSU =====================
	float c = fract(temps * 0.5);
	float bat = eveil * exp(-c * 9.0);
	float tc = 0.52 * (1.0 + 0.07 * bat);
	// les deux moitiés, écartées par la fente en zigzag
	float zig = 0.035 * (abs(fract(p.y * 3.5 + 0.25) - 0.5) - 0.25) * 4.0;
	float cote = p.x - zig;
	float ecart = 0.035;
	vec2 qc = (p - vec2(sign(cote) * ecart, 0.0)) / tc;
	qc.y += 0.1;
	float dc = -sd_coeur(qc) * tc;
	float fente = abs(cote) - ecart * 0.5;
	float moitie = min(dc, fente);
	forme(f_rgb, f_a, moitie, couleur.rgb, encre_color.rgb, e, px);
	// l'ombre du bas, le reflet en haut à gauche
	par_dessus(f_rgb, f_a, couleur.rgb * 0.72, smoothstep(0.0, px, min(moitie, p.y + p.x * 0.3 - 0.08)) * 0.9);
	par_dessus(f_rgb, f_a, clair.rgb, smoothstep(0.0, px, min(0.06 - length((p - vec2(-0.24, -0.2)) * vec2(1.0, 1.35)), moitie - 0.02)) * 0.85);
	// les points de couture : trois traits de fil en travers de la fente
	for (int i = 0; i < 3; i++) {
		float yi = -0.2 + float(i) * 0.15;
		vec2 a0 = vec2(-0.09, yi - 0.035);
		vec2 b0 = vec2(0.09, yi + 0.035);
		vec2 pa = p - a0;
		vec2 ba = b0 - a0;
		float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
		float d_fil = 0.02 - length(pa - ba * h);
		forme(f_rgb, f_a, d_fil, fil.rgb, encre_color.rgb, e * 0.5, px);
	}

	rgb = mix(rgb, f_rgb, f_a * champ);
	COLOR = vec4(rgb, a * opacite);
}
