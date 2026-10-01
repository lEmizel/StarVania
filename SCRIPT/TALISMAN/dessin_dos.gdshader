shader_type canvas_item;
render_mode unshaded;
// DESSIN DU TALISMAN « COUP DANS LE DOS » (menu START, 1er oct. 2026) —
// provisoire, en attendant le dessin de Kaoru.
// emplacement_talisman.gd le pose dans le rond et lui fournit `opacite`,
// `eveil` et `temps`.
// TOUT LE ROND est au dessin : un disque de nuit cerné d'un trait d'encre ;
// dedans, la silhouette sombre d'un ennemi de profil, qui regarde à GAUCHE (son
// œil rouge le dit) ; dans son DOS, à droite, une entaille de sang en
// diagonale et une étoile d'impact rouge. Aplats et trait d'encre, pas de
// blanc. Pointé ou porté (`eveil`), l'étoile bat.
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
// la silhouette de l'ennemi
uniform vec4 silhouette : source_color = vec4(0.27, 0.2, 0.25, 1.0);
uniform vec4 silhouette_clair : source_color = vec4(0.36, 0.28, 0.33, 1.0);
// le sang
uniform vec4 couleur : source_color = vec4(0.78, 0.04, 0.12, 1.0);
uniform vec4 couleur_vive : source_color = vec4(1.0, 0.2, 0.22, 1.0);
uniform vec4 sombre : source_color = vec4(0.32, 0.01, 0.06, 1.0);

float disque(float d, float r, float px) {
	return smoothstep(r + px * 0.5, r - px * 0.5, d);
}

// une forme (positive dedans), cernée d'encre, posée sur le dessin
void forme(inout vec3 rgb, float d, vec3 teinte, float e, float px) {
	rgb = mix(rgb, encre_color.rgb, smoothstep(-px * 0.5, px * 0.5, d + e));
	rgb = mix(rgb, teinte, smoothstep(-px * 0.5, px * 0.5, d));
}

// un rectangle aux coins arrondis, centré en `c`, de demi-taille `h`, rayon `r`
// (positif dedans)
float boite(vec2 p, vec2 c, vec2 h, float r) {
	vec2 q = abs(p - c) - h + r;
	return r - (length(max(q, 0.0)) + min(max(q.x, q.y), 0.0));
}

// une étoile à `n` branches centrée en `c` : rayons intérieur `ri`, extérieur
// `re` (positive dedans, approchée)
float etoile(vec2 p, vec2 c, float n, float ri, float re, float tourne) {
	vec2 q = p - c;
	float ang = atan(q.y, q.x) + tourne;
	float secteur = TAU / n;
	float a = mod(ang, secteur) / secteur;          // 0 → 1 dans un secteur
	float pointe = abs(a - 0.5) * 2.0;              // 0 au bout d'une branche, 1 entre deux
	float rayon = mix(re, ri, pow(pointe, 0.7));
	return rayon - length(q);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;                 // -1 … 1 : le médaillon est le disque de rayon 1
	float r = length(p);
	float px = fwidth(UV.x) * 2.0;             // un pixel d'écran, dans cette unité

	// ===================== LE DISQUE =====================
	vec3 rgb = encre_color.rgb;
	float a = disque(r, 1.0, px);
	rgb = mix(rgb, mix(fond_centre.rgb, fond_color.rgb, smoothstep(0.0, 0.95, r)),
			disque(r, 1.0 - trait, px));

	// ===================== L'ENNEMI, DE PROFIL (il regarde à gauche) =====================
	// le corps (des épaules aux hanches), coupé par le bas du disque
	float corps = boite(p, vec2(-0.08, 0.5), vec2(0.3, 0.42), 0.22);
	// la tête, et son museau qui pointe à gauche
	float tete = 0.21 - length(p - vec2(-0.14, -0.27));
	float museau = boite(p, vec2(-0.3, -0.22), vec2(0.1, 0.07), 0.06);
	float ennemi = max(max(corps, tete), museau);
	ennemi = min(ennemi, (1.0 - trait * 1.6) - r);   // coupé au bord du disque
	forme(rgb, ennemi, silhouette.rgb, trait, px);
	// un reflet sur le haut du dos, du côté du coup
	float reflet = boite(p, vec2(0.08, 0.2), vec2(0.07, 0.16), 0.07);
	rgb = mix(rgb, silhouette_clair.rgb, smoothstep(-px * 0.5, px * 0.5, min(reflet, ennemi)));
	// son œil rouge : c'est lui qui dit où il regarde
	float oeil = 0.045 - length(p - vec2(-0.23, -0.3));
	forme(rgb, oeil, couleur_vive.rgb, trait * 0.5, px);

	// ===================== LE COUP, DANS LE DOS =====================
	// l'entaille : un croissant fin en diagonale sur le dos
	vec2 q = p - vec2(0.3, 0.12);
	float ang = 0.75;
	vec2 qr = vec2(cos(ang) * q.x + sin(ang) * q.y, -sin(ang) * q.x + cos(ang) * q.y);
	float t = clamp(qr.x / 0.36, -1.0, 1.0);
	float entaille = 0.05 * (1.0 - t * t) - abs(qr.y - 0.06 * (1.0 - t * t));
	entaille = min(entaille, 0.36 - abs(qr.x));
	forme(rgb, entaille, couleur.rgb, trait * 0.7, px);
	// l'étoile d'impact, qui bat quand le talisman est éveillé
	float bat = 1.0 + 0.12 * eveil * sin(temps * 6.0);
	float e1 = etoile(p, vec2(0.36, 0.06), 8.0, 0.07 * bat, 0.25 * bat, 0.2);
	forme(rgb, e1, couleur.rgb, trait * 0.8, px);
	float e2 = etoile(p, vec2(0.36, 0.06), 8.0, 0.04 * bat, 0.13 * bat, 0.2);
	rgb = mix(rgb, couleur_vive.rgb, smoothstep(-px * 0.5, px * 0.5, e2));

	COLOR = vec4(rgb, a * opacite);
}
