shader_type canvas_item;
render_mode unshaded;
// LANCEUR DE BOULES DE FEU — le canon, en DEUX DESSINS
// (MEDIA/INTERACTIBLE/base canon.png et canon.png) pour qu'il puisse reculer
// dans son socle. Le shader pose les deux pièces telles quelles (1 pixel du
// dessin = 1 pixel du jeu, avec le filtre du nœud, celui des autres décors) :
// le CANON d'abord, la BASE par-dessus — le fond du canon est caché dans son
// cylindre. Il tire vers la DROITE de son repère.
//   • `tir` (1 → 0 après un tir) : le canon RECULE d'un coup dans la base
//     (`recul` px) et revient, une bouffée de fumée sort de la bouche ;
//   • `chaleur` (0 → 1) : la charge — le bout du canon rougit, sa bouche
//     s'embrase, un halo monte ; la boule elle-même est le visuel de la boule
//     de feu, posé devant la bouche par le script.
// (Avant ces dessins, le canon était tracé ici : plaque de pierre boulonnée,
// canon de fer à deux bandes, bouche évasée.)
// Repère : `origine` = la surface du mur, sur l'axe du canon, dans le
// rectangle (px). Piloté par SCRIPT/INTERACTIBLE/lanceur_feu.gd.

uniform vec2 taille = vec2(160.0, 112.0);
uniform vec2 origine = vec2(10.0, 56.0);
uniform sampler2D base : repeat_disable;
uniform sampler2D canon : repeat_disable;
uniform float chaleur : hint_range(0.0, 1.0) = 0.0;
uniform float tir : hint_range(0.0, 1.0) = 0.0;
uniform float temps = 0.0;

// le coin haut-gauche de chaque image, depuis l'origine (mesurés sur l'image
// de référence du canon assemblé : la base contre le mur, le canon 9 px plus à
// gauche et 3 px plus bas que le milieu de la base ; sa bouche arrive à 62 px
// du mur)
uniform vec2 coin_base = vec2(-1.0, -39.0);
uniform vec2 coin_canon = vec2(-10.0, -26.0);
uniform float debut_canon = 16.0;                // on ne dessine le canon qu'à partir de cette colonne de son image (avant : deux traces de pinceau perdues)
uniform float recul = 5.0;                       // le canon recule de… au tir (px)
uniform float bouche = 62.0;                     // le bout du canon, depuis le mur (px)

uniform vec4 braise_rouge : source_color = vec4(0.75, 0.1, 0.03, 1.0);
uniform vec4 braise_orange : source_color = vec4(1.0, 0.45, 0.06, 1.0);
uniform vec4 braise_jaune : source_color = vec4(1.0, 0.86, 0.35, 1.0);
uniform vec4 couleur_fumee : source_color = vec4(0.52, 0.54, 0.59, 1.0);


vec4 sur(vec4 dst, vec4 src) {
	float a = src.a + dst.a * (1.0 - src.a);
	vec3 rgb = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 0.0001);
	return vec4(rgb, a);
}

// une de ses images, son coin haut-gauche en `coin` : rien en dehors
vec4 piece(sampler2D image, vec2 p, vec2 coin, float depuis_x) {
	vec2 sz = vec2(textureSize(image, 0));
	vec2 t = p - coin;
	vec4 c = texture(image, t / sz);
	if (t.x < depuis_x || t.y < 0.0 || t.x > sz.x || t.y > sz.y) {
		c = vec4(0.0);
	}
	return c;
}

void fragment() {
	vec2 pix = UV * taille;
	vec2 p = pix - origine;                          // x hors du mur, y vers le bas
	vec4 c = vec4(braise_orange.rgb, 0.0);
	// le recul du canon au tir : d'un coup, puis il revient
	float r = recul * smoothstep(0.72, 1.0, tir);
	vec2 pc = vec2(p.x + r, p.y);                    // le repère du canon (il recule)

	// ===================== LE HALO DE LA CHARGE (derrière tout) =====================
	float d_halo = length((pc - vec2(bouche + 2.0, 0.0)) * vec2(0.85, 1.0));
	float halo = exp(-max(d_halo - 16.0, 0.0) / 13.0) * chaleur * 0.38;
	c = sur(c, vec4(mix(braise_orange.rgb, braise_rouge.rgb, smoothstep(16.0, 50.0, d_halo)), halo));

	// ===================== SON CANON (il recule dans la base) =====================
	vec4 can = piece(canon, pc, coin_canon, debut_canon);
	// la charge : le bout rougit…
	float vers_bouche = smoothstep(bouche - 30.0, bouche - 6.0, pc.x);
	can.rgb = mix(can.rgb, braise_rouge.rgb * 0.9, chaleur * vers_bouche * 0.5);
	// … et sa bouche s'embrase, du rouge au jaune, en vacillant
	float gueule = smoothstep(bouche - 11.0, bouche - 2.0, pc.x) * clamp(1.15 - abs(p.y) / 22.0, 0.0, 1.0);
	float braise = chaleur * gueule * (0.85 + 0.15 * sin(temps * 23.0 + p.y * 0.4));
	can.rgb = mix(can.rgb, braise_rouge.rgb, smoothstep(0.0, 0.3, braise) * 0.75);
	can.rgb = mix(can.rgb, braise_orange.rgb, smoothstep(0.3, 0.65, braise) * 0.8);
	can.rgb = mix(can.rgb, braise_jaune.rgb, smoothstep(0.65, 1.0, braise) * 0.8);
	c = sur(c, can);

	// ===================== SA BASE, par-dessus : le fond du canon est dedans =====================
	c = sur(c, piece(base, p, coin_base, 0.0));

	// ===================== LA FUMÉE DU TIR =====================
	float vie = 1.0 - tir;                           // 0 au tir → 1
	if (tir > 0.0) {
		float fumee = 0.0;
		float clair = 0.0;
		for (int k = 0; k < 4; k++) {
			float fk = float(k);
			vec2 cf = vec2(bouche + 4.0 + vie * (18.0 + 10.0 * fk), (fk - 1.5) * 5.0 - vie * (6.0 + 7.0 * fk));
			float rf = 6.0 + vie * (10.0 + 3.0 * fk);
			float k2 = clamp(1.0 - length(p - cf) / rf, 0.0, 1.0);
			k2 = k2 * (2.0 - k2);                    // une bouffée pleine, au bord doux
			fumee = max(fumee, k2);
			clair = max(clair, k2 * clamp(-(p.y - cf.y) / rf, 0.0, 1.0));
		}
		vec3 col_f = mix(couleur_fumee.rgb * 0.85, couleur_fumee.rgb * 1.2, clair);
		float a_f = fumee * 0.7 * pow(tir, 1.2) * smoothstep(0.0, 0.08, vie);
		c = sur(c, vec4(col_f, a_f));
	}

	// rien ne touche le bord du rectangle
	float bord_r = min(min(pix.x, taille.x - pix.x), min(pix.y, taille.y - pix.y));
	c.a *= smoothstep(0.0, 3.0, bord_r);
	COLOR = c;
}
