shader_type canvas_item;
render_mode unshaded;
// DESSIN DU TALISMAN « BOULE CHERCHEUSE » (menu START, 2 oct. 2026) —
// provisoire, en attendant le dessin définitif.
// emplacement_talisman.gd le pose dans le rond et lui fournit `opacite`,
// `eveil` et `temps`.
// TOUT LE ROND est au dessin : un disque de nuit cerné d'un trait d'encre ; au
// fond, les cercles et la croix d'une MIRE ; en haut à droite, la CIBLE (un rond
// sombre, quatre crans autour) ; la BOULE DE SANG part d'en bas à gauche et sa
// traînée S'INCURVE vers la cible, la suite du trajet en pointillés. Aplats
// rouges et encre, reflet rouge clair (pas de blanc). Pointé ou porté
// (`eveil`), la boule refait son vol en boucle et la cible s'allume quand elle
// la touche.
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
uniform vec4 couleur : source_color = vec4(0.78, 0.04, 0.12, 1.0);
uniform vec4 sombre : source_color = vec4(0.3, 0.01, 0.06, 1.0);
uniform vec4 clair : source_color = vec4(1.0, 0.5, 0.5, 1.0);

// le trajet : une courbe de Bézier, du bas à gauche à la cible
const vec2 DEPART = vec2(-0.68, 0.44);
const vec2 APPUI = vec2(0.3, 0.64);
const vec2 CIBLE = vec2(0.4, -0.36);

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

vec2 courbe(float t) {
	float u = 1.0 - t;
	return u * u * DEPART + 2.0 * u * t * APPUI + t * t * CIBLE;
}

// distance au morceau de trajet [t0, t1] (24 segments) et le t le plus proche
vec2 vers_courbe(vec2 p, float t0, float t1) {
	float meilleure = 100.0;
	float tm = t0;
	vec2 avant = courbe(t0);
	for (int i = 1; i <= 24; i++) {
		float t = mix(t0, t1, float(i) / 24.0);
		vec2 ici = courbe(t);
		vec2 pa = p - avant;
		vec2 ba = ici - avant;
		float h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.000001), 0.0, 1.0);
		float d = length(pa - ba * h);
		if (d < meilleure) {
			meilleure = d;
			tm = mix(t - (t1 - t0) / 24.0, t, h);
		}
		avant = ici;
	}
	return vec2(meilleure, tm);
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

	// le vol : au repos la boule est aux deux tiers du trajet ; éveillée, elle
	// le refait en boucle (0 → 0,75 du cycle) et la cible s'allume à l'arrivée
	float cycle = fract(temps * 0.5);
	float t_vol = mix(0.0, 0.93, smoothstep(0.0, 0.75, cycle));
	float t_boule = mix(0.64, t_vol, eveil);
	float touche = eveil * step(0.75, cycle) * (1.0 - smoothstep(0.75, 1.0, cycle));

	// ===================== LA MIRE (au fond) =====================
	vec2 c = p - CIBLE;
	float rc = length(c);
	float cercles = min(abs(rc - 0.34), abs(rc - 0.56)) - 0.012;
	float croix = min(abs(c.x), abs(c.y)) - 0.01;
	par_dessus(f_rgb, f_a, sombre.rgb * 1.7, smoothstep(px, 0.0, min(cercles, croix)) * 0.8);

	// ===================== LA SUITE DU TRAJET, EN POINTILLÉS =====================
	vec2 suite = vers_courbe(p, t_boule, 1.0);
	float pointille = step(0.45, fract(suite.y * 14.0));
	par_dessus(f_rgb, f_a, sombre.rgb * 2.2, smoothstep(px, 0.0, suite.x - 0.022) * pointille * step(t_boule + 0.08, suite.y));

	// ===================== LA CIBLE =====================
	float s_cible = 1.0 + 0.18 * touche;
	forme(f_rgb, f_a, 0.15 * s_cible - rc, mix(sombre.rgb, couleur.rgb, touche), encre_color.rgb, e, px);
	par_dessus(f_rgb, f_a, mix(couleur.rgb, clair.rgb, touche), smoothstep(px, 0.0, rc - 0.05 * s_cible));
	for (int i = 0; i < 4; i++) {
		float th = float(i) * PI * 0.5;
		vec2 dir = vec2(cos(th), sin(th));
		vec2 q = vec2(dot(c, dir), dot(c, vec2(-dir.y, dir.x)));
		float cran = max(abs(q.x - 0.25 * s_cible) - 0.055, abs(q.y) - 0.022);
		forme(f_rgb, f_a, -cran, mix(couleur.rgb, clair.rgb, touche), encre_color.rgb, e * 0.6, px);
	}

	// ===================== LA TRAÎNÉE, QUI S'INCURVE =====================
	float t0 = max(t_boule - 0.42, 0.0);
	if (t_boule > 0.02) {
		vec2 tr = vers_courbe(p, t0, t_boule);
		float k = smoothstep(t0, t_boule, tr.y);
		float largeur = mix(0.012, 0.085, k);
		forme(f_rgb, f_a, largeur - tr.x, couleur.rgb, encre_color.rgb, e * 0.8, px);
		// son cœur plus sombre
		par_dessus(f_rgb, f_a, couleur.rgb * 0.72, smoothstep(px, 0.0, tr.x - largeur * 0.35) * k);
	}

	// ===================== LA BOULE =====================
	vec2 b = courbe(t_boule);
	float db = 0.13 - length(p - b);
	forme(f_rgb, f_a, db, couleur.rgb, encre_color.rgb, e, px);
	// son ombre en bas à droite, son reflet en haut à gauche
	par_dessus(f_rgb, f_a, couleur.rgb * 0.7, smoothstep(0.0, px, min(db, (p.y - b.y) + (p.x - b.x) * 0.6 - 0.03)) * 0.9);
	par_dessus(f_rgb, f_a, clair.rgb, smoothstep(0.0, px, min(0.035 - length((p - b - vec2(-0.045, -0.045)) * vec2(1.0, 1.4)), db - 0.02)) * 0.9);

	rgb = mix(rgb, f_rgb, f_a * champ);
	COLOR = vec4(rgb, a * opacite);
}
