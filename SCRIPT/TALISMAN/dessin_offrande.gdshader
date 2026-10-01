shader_type canvas_item;
render_mode unshaded;
// DESSIN DU TALISMAN « OFFRANDE » (menu START, 1er oct. 2026) — provisoire, en
// attendant le dessin de Kaoru.
// emplacement_talisman.gd le pose dans le rond et lui fournit `opacite`,
// `eveil` et `temps`.
// TOUT LE ROND est au dessin : un disque de nuit cerné d'un trait d'encre ; au
// fond, des colonnes de lumière sombre qui montent du sceau ; en bas, le SCEAU
// DE SANG vu de trois quarts — le même qu'en jeu : deux cercles, l'étoile, les
// runes — et la crête de son onde autour de lui ; au-dessus, un CŒUR qui
// flotte (le soin), et des gouttes qui montent du sceau vers lui. Aplats et
// dégradés, reflets rouge clair (pas de blanc). Pointé ou porté (`eveil`) : le
// sceau tourne, les gouttes montent, le cœur bat.
// À dessiner dans un CARRÉ : le disque le remplit.

// --- fournis par emplacement_talisman.gd (les mêmes pour tout dessin de talisman) ---
uniform float opacite : hint_range(0.0, 1.0) = 1.0;
uniform float eveil : hint_range(0.0, 1.0) = 0.0;
uniform float temps = 0.0;
// ----------------------------------------------------------------------------

uniform vec4 encre_color : source_color = vec4(0.1, 0.02, 0.04, 1.0);
uniform vec4 fond_color : source_color = vec4(0.06, 0.02, 0.04, 1.0);
uniform vec4 fond_centre : source_color = vec4(0.17, 0.03, 0.05, 1.0);
uniform float trait : hint_range(0.0, 0.1) = 0.045;
uniform vec4 couleur : source_color = vec4(0.78, 0.04, 0.12, 1.0);
uniform vec4 couleur_vive : source_color = vec4(1.0, 0.17, 0.2, 1.0);
uniform vec4 sombre : source_color = vec4(0.32, 0.01, 0.06, 1.0);
uniform vec4 clair : source_color = vec4(1.0, 0.55, 0.52, 1.0);

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

float segment(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.0001), 0.0, 1.0);
	return length(pa - ba * h);
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

// une distance mesurée sur le sol du sceau (écrasé de `aplat` en hauteur),
// remise en pixels pour un trait de direction `t` — calculée, pas mesurée
// entre pixels voisins (voir sceau_sang.gdshader)
float en_px(float d, vec2 t, float aplat, float px) {
	return d * aplat / max(length(vec2(t.x, aplat * t.y)), 0.0001) / px;
}

vec2 tourne(vec2 v, float a) {
	return vec2(v.x * cos(a) - v.y * sin(a), v.x * sin(a) + v.y * cos(a));
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float px = fwidth(UV.x) * 2.0;
	float e = 0.035;

	vec3 rgb = encre_color.rgb;
	float a = disque(r, 1.0, px);
	float champ = disque(r, 1.0 - trait, px);
	rgb = mix(rgb, mix(fond_centre.rgb, fond_color.rgb, smoothstep(0.0, 0.95, r)), champ);

	vec3 f_rgb = couleur.rgb;
	float f_a = 0.0;

	vec2 cs = vec2(0.0, 0.5);           // le centre du sceau
	float aplat = 0.3;
	float R = 0.62;
	float Ri = R * 0.8;

	// ===================== LES COLONNES DE LUMIÈRE SOMBRE =====================
	for (int k = 0; k < 5; k++) {
		float fk = float(k) - 2.0;
		float xk = fk * 0.22;
		float monte = clamp((cs.y - p.y) / 1.1, 0.0, 1.0);          // 0 au sceau, 1 en haut
		float demi = 0.05 * (1.0 - monte) * (1.0 - 0.3 * abs(fk) / 2.0);
		float d = demi - abs(p.x - xk);
		par_dessus(f_rgb, f_a, sombre.rgb, smoothstep(0.0, px, d) * step(p.y, cs.y) * (1.0 - monte) * 0.55);
	}

	// ===================== LA CRÊTE DE L'ONDE, DERRIÈRE =====================
	float rw = 0.88;
	float hw = 0.11;
	float xr = clamp(p.x / rw, -1.0, 1.0);
	float zf = sqrt(max(1.0 - xr * xr, 0.0));
	float bord = rw - abs(p.x);
	float h = hw * (1.0 + 0.25 * sin(p.x * 14.0 + temps * 6.0 * eveil));
	float y_dos = cs.y - aplat * rw * zf;
	float y_face = cs.y + aplat * rw * zf;
	float d_dos = min(min(p.y - (y_dos - h), y_dos + 0.015 - p.y), bord);
	par_dessus(f_rgb, f_a, mix(sombre.rgb, couleur.rgb * 0.75, clamp((y_dos - p.y) / h, 0.0, 1.0)), smoothstep(0.0, px, d_dos));

	// ===================== LE SCEAU =====================
	vec2 g = vec2(p.x - cs.x, (p.y - cs.y) / aplat);
	float rg = length(g);
	float rot = temps * 0.8 * eveil;
	vec2 gs = vec2(g.x * cos(rot) - g.y * sin(rot), g.x * sin(rot) + g.y * cos(rot));
	float ang = atan(gs.y, gs.x);
	vec2 t_c = rg > 0.0001 ? vec2(-g.y, g.x) / rg : vec2(1.0, 0.0);
	// l'anneau teinté, le disque à peine
	par_dessus(f_rgb, f_a, sombre.rgb, smoothstep(-0.5, 0.5, en_px(min(rg - Ri, R - rg), t_c, aplat, px)) * 0.75);
	par_dessus(f_rgb, f_a, sombre.rgb, smoothstep(-0.5, 0.5, en_px(Ri - rg, t_c, aplat, px)) * 0.35);
	// les cercles
	float w = 0.028;
	float f_c = max(smoothstep(-0.5, 0.5, (w * 0.5) / px - en_px(abs(rg - R), t_c, aplat, px)),
			smoothstep(-0.5, 0.5, (w * 0.35) / px - en_px(abs(rg - Ri), t_c, aplat, px)));
	// l'étoile
	float d_et = 10.0;
	vec2 t_et = vec2(1.0, 0.0);
	for (int k = 0; k < 6; k++) {
		float a0 = float(k) * TAU / 6.0 - PI * 0.5;
		float a1 = float(k + 2) * TAU / 6.0 - PI * 0.5;
		vec2 A = Ri * vec2(cos(a0), sin(a0));
		vec2 B = Ri * vec2(cos(a1), sin(a1));
		float dk = segment(gs, A, B);
		if (dk < d_et) {
			d_et = dk;
			t_et = normalize(B - A);
		}
	}
	float f_e = smoothstep(-0.5, 0.5, (w * 0.32) / px - en_px(d_et, tourne(t_et, -rot), aplat, px));
	// les runes
	float secteur = TAU / 14.0;
	float n = floor(ang / secteur);
	float ak = (n + 0.5) * secteur;
	vec2 dir = vec2(cos(ak), sin(ak));
	float le_long = dot(gs, dir);
	float travers = abs(dot(gs, vec2(-dir.y, dir.x)));
	float m = (R + Ri) * 0.5;
	float d_rune = (mod(n, 2.0) < 0.5)
		? max(travers, abs(le_long - m) - (R - Ri) * 0.28)
		: max(abs(le_long - m) + travers * 1.6 - (R - Ri) * 0.2, 0.0);
	vec2 t_r = (mod(n, 2.0) < 0.5) ? tourne(dir, -rot) : t_c;
	float f_r = smoothstep(-0.5, 0.5, (w * 0.32) / px - en_px(d_rune, t_r, aplat, px));
	float bat = 0.5 + 0.5 * sin(temps * 6.0);
	vec3 c_trait = mix(couleur.rgb, couleur_vive.rgb, 0.35 + 0.4 * bat * eveil);
	par_dessus(f_rgb, f_a, c_trait, max(max(f_c, f_e), f_r));

	// ===================== LES GOUTTES QUI MONTENT =====================
	for (int k = 0; k < 3; k++) {
		float fk = float(k);
		float xk = (fk - 1.0) * 0.26 + 0.04 * sin(fk * 3.0);
		float monte = fract(0.2 + fk * 0.33 + temps * 0.45 * eveil);
		float yk = cs.y - 0.1 - 0.42 * monte;
		vec2 q = p - vec2(xk, yk);
		// une goutte qui monte : la pointe en bas
		float dg = 0.045 * (1.0 - 0.5 * monte) - length(vec2(q.x, q.y > 0.0 ? q.y * 0.5 : q.y));
		par_dessus(f_rgb, f_a, mix(couleur_vive.rgb, couleur.rgb, monte), smoothstep(0.0, px, dg) * (1.0 - smoothstep(0.75, 1.0, monte)));
	}

	// ===================== LE CŒUR QUI FLOTTE =====================
	float bat_coeur = 1.0 + 0.06 * sin(temps * 6.0) * eveil;
	float tc = 0.34 * bat_coeur;
	vec2 qc = (p - vec2(0.0, -0.3 + 0.02 * sin(temps * 2.0) * eveil)) / tc;
	qc.y += 0.1;
	float dc = -sd_coeur(qc) * tc;
	// dégradé : vif en haut, rouge en bas
	vec3 c_coeur = mix(couleur_vive.rgb, couleur.rgb, smoothstep(-0.45, -0.05, p.y));
	forme(f_rgb, f_a, dc, c_coeur, encre_color.rgb, e, px);
	par_dessus(f_rgb, f_a, couleur.rgb * 0.72, smoothstep(0.0, px, min(dc, p.y + 0.22 + p.x * 0.35)) * 0.7);
	// le reflet rouge clair, en haut à gauche
	par_dessus(f_rgb, f_a, clair.rgb, smoothstep(0.0, px, min(0.045 - length((p - vec2(-0.13, -0.41)) * vec2(1.0, 1.4)), dc - 0.02)) * 0.9);

	// ===================== LA CRÊTE DE L'ONDE, DEVANT =====================
	float d_face = min(min(p.y - (y_face - h), y_face + 0.015 - p.y), bord);
	par_dessus(f_rgb, f_a, mix(couleur.rgb, couleur_vive.rgb, clamp((y_face - p.y) / h, 0.0, 1.0)), smoothstep(0.0, px, d_face));

	rgb = mix(rgb, f_rgb, f_a * champ);
	COLOR = vec4(rgb, a * opacite);
}
