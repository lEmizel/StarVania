shader_type canvas_item;
render_mode unshaded;
// TROP-PLEIN (2 oct. 2026) — la ROUE du talisman « Trop-plein », comme la jauge
// d'endurance de Zelda : un anneau qui se REMPLIT EN
// TOURNANT, depuis midi dans le sens des aiguilles d'une montre, d'un tiers à
// chaque coup d'épée qui porte (le tiers gagné s'éclaire un instant). Des
// encoches marquent les tiers. PLEINE, son cœur se remplit d'une boule de sang
// qui bat, et une onde fine part à chaque battement. Au lancer de la grosse
// boule, elle CRÈVE (gouttes projetées, anneau).
// Piloté par trop_plein_jauge.gd. Sobre : aplat rouge + encre, aucun blanc.

uniform vec2 taille = vec2(96.0, 96.0);      // le rectangle (px)
uniform vec2 centre = vec2(48.0, 48.0);      // le milieu de la roue dans le rectangle (px)
uniform float rayon = 15.0;                  // rayon extérieur de l'anneau (px)
uniform float epaisseur = 5.5;               // épaisseur de l'anneau (px)
uniform float encre = 1.3;                   // épaisseur du trait (px)
uniform float rempli : hint_range(0.0, 1.0) = 0.34;   // la part remplie de l'anneau
uniform float crans = 3.0;                   // les coups demandés (une encoche par cran)
uniform float plein : hint_range(0.0, 1.0) = 0.0;     // pleine : son cœur se remplit et bat
uniform float gonfle = 1.0;                  // son échelle du moment (le « plop » d'un coup)
uniform float eclat : hint_range(0.0, 1.0) = 0.0;     // elle crève (0 → 1)
uniform float flash : hint_range(0.0, 1.0) = 0.0;     // le tiers qui vient de se remplir s'éclaire
uniform float temps = 0.0;

uniform vec4 couleur_sang : source_color = vec4(0.78, 0.04, 0.12, 1.0);
uniform vec4 couleur_clair : source_color = vec4(1.0, 0.42, 0.42, 1.0);
uniform vec4 couleur_fond : source_color = vec4(0.12, 0.01, 0.03, 0.6);
uniform vec4 couleur_encre : source_color = vec4(0.1, 0.01, 0.03, 1.0);
// battements par seconde × 2π (7 ≈ un battement toutes les 0,9 s)
uniform float vitesse_battement = 7.0;


// `src` posé par-dessus `dst` (alpha droit)
vec4 sur(vec4 dst, vec4 src) {
	float a = src.a + dst.a * (1.0 - src.a);
	vec3 rgb = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 0.0001);
	return vec4(rgb, a);
}

// couverture d'une forme dont la distance signée est `d` (négative dedans)
float couvre(float d, float px) {
	return clamp(0.5 - d / px, 0.0, 1.0);
}

void fragment() {
	vec2 pix = UV * taille;
	float px = max(fwidth(pix.x), 0.001);
	vec4 c = vec4(couleur_sang.rgb, 0.0);

	float bat = pow(0.5 + 0.5 * sin(temps * vitesse_battement), 8.0) * plein;
	float s = gonfle * (1.0 + 0.08 * bat) * (1.0 + 0.5 * eclat);
	vec2 q = (pix - centre) / s;
	float pq = px / s;
	float r = length(q);
	float disparait = 1.0 - smoothstep(0.0, 0.6, eclat);

	// ===================== L'ANNEAU =====================
	float r_mi = rayon - epaisseur * 0.5;
	float d_anneau = abs(r - r_mi) - epaisseur * 0.5;
	float dans_anneau = couvre(d_anneau, pq);
	// le fond de l'anneau, sombre et un peu transparent
	c = sur(c, vec4(couleur_fond.rgb, couleur_fond.a * dans_anneau * disparait));
	// la part remplie : depuis midi, dans le sens des aiguilles d'une montre
	float f = fract(atan(q.x, -q.y) / TAU + 1.0);
	float arc = (rempli - f) * TAU * r_mi;                 // en px le long de l'anneau
	float remplie = couvre(-arc, pq) * step(0.001, rempli) * dans_anneau;
	// le tiers qui vient de se remplir s'éclaire un instant
	float dernier = floor(max(rempli - 0.001, 0.0) * crans) / crans;
	float teinte_flash = flash * step(dernier, f);
	vec3 teinte = mix(couleur_sang.rgb, couleur_clair.rgb, teinte_flash * 0.8);
	c = sur(c, vec4(teinte, remplie * disparait));
	// les encoches des tiers, en travers de l'anneau
	for (int k = 0; k < 8; k++) {
		if (float(k) >= crans) break;
		float a = float(k) / crans * TAU;
		vec2 dir = vec2(sin(a), -cos(a));
		float le_long = dot(q, dir);
		float travers = abs(dot(q, vec2(-dir.y, dir.x)));
		float d_enc = max(travers - 0.6, abs(le_long - r_mi) - epaisseur * 0.5);
		c = sur(c, vec4(couleur_encre.rgb, couvre(d_enc, pq) * disparait));
	}
	// ses deux bords à l'encre
	float bords = min(abs(r - rayon), abs(r - (rayon - epaisseur))) - encre * 0.5;
	c = sur(c, vec4(couleur_encre.rgb, couvre(bords, pq) * disparait));

	// ===================== PLEINE : SON CŒUR SE REMPLIT ET BAT =====================
	float r_coeur = (rayon - epaisseur - 1.6) * smoothstep(0.0, 1.0, plein);
	if (r_coeur > 0.01) {
		float d_coeur = r - r_coeur;
		c = sur(c, vec4(couleur_encre.rgb, couvre(d_coeur - encre * 0.8, pq) * disparait));
		c = sur(c, vec4(couleur_sang.rgb, couvre(d_coeur, pq) * disparait));
	}
	if (plein > 0.001 && eclat < 0.001) {
		// une onde fine à chaque battement
		float ph = fract(temps * vitesse_battement / 6.2832 - 0.25);
		float ra = rayon * (1.05 + 0.7 * ph);
		float da = abs(length(pix - centre) / gonfle - ra) - 0.6;
		c = sur(c, vec4(couleur_sang.rgb, couvre(da, px) * pow(1.0 - ph, 2.0) * 0.85 * plein));
	}

	// ===================== ELLE CRÈVE =====================
	if (eclat > 0.001) {
		vec2 rr = pix - centre;
		float ra = rayon * gonfle * (1.0 + 1.4 * eclat);
		float da = abs(length(rr) - ra) - 0.9 * (1.0 - eclat);
		c = sur(c, vec4(couleur_sang.rgb, couvre(da, px) * (1.0 - eclat)));
		for (int k = 0; k < 6; k++) {
			float a = float(k) * 1.0472 + 0.3;
			vec2 dir = vec2(cos(a), sin(a));
			vec2 pos = dir * rayon * gonfle * (1.0 + 1.9 * eclat) + vec2(0.0, eclat * eclat * 14.0);
			float rg = 2.5 * (1.0 - eclat * 0.8);
			float dg = length(rr - pos) - rg;
			float vis = 1.0 - smoothstep(0.6, 1.0, eclat);
			c = sur(c, vec4(couleur_encre.rgb, couvre(dg - 0.9, px) * vis));
			c = sur(c, vec4(couleur_sang.rgb, couvre(dg, px) * vis));
		}
	}

	COLOR = c;
}
