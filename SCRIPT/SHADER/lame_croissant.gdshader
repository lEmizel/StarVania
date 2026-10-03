shader_type canvas_item;
render_mode unshaded;
// LAME EN CROISSANT — la grande lame de la LAME À CHAÎNE
// (SCRIPT/INTERACTIBLE/lame_chaine.gd), AU DESSIN DE KAORU (3 oct. 2026 :
// MEDIA/INTERACTIBLE/lame_pendule.png — « finalement pour la lame j'ai refait
// aussi un dessin ») : cornes vers l'anneau, pointe vers l'extérieur.
// (Avant son dessin, la lame était dessinée ici : v1 acier brossé et rouille,
// v2 acier propre et sang en aplat.)
//   • `dessin` : son dessin. En jeu, le script passe une copie réduite, à
//     mipmaps et aux couleurs prémultipliées (`dessin_premultiplie`) : son
//     image fait 1736 px et la lame ~234 à l'écran ; sans mipmaps, elle
//     scintillerait en tournant. Dans l'éditeur, c'est le dessin tel quel ;
//   • `largeur` : la largeur du dessin en jeu (px, d'une corne à l'autre) ;
//     `attache` : la place de l'anneau DANS le dessin (fractions de l'image) —
//     le script le pose au-dessus du milieu du dos, qu'il mesure sur l'image ;
//   • par-dessus : la platine rivetée au dos (`dos` px sous l'anneau), ses
//     rivets et l'anneau où s'accroche la chaîne — du fer en APLAT, deux tons,
//     sans ombrage, comme les maillons (Kaoru n'en voulait pas le « côté 3D »).
//     Les deux tons du fer sont pris dans la palette de son dessin (un gris
//     un peu vert), pour que l'attache ne jure pas avec sa lame.
// Repère : `anneau` = le centre de l'anneau dans le rectangle (px) ; la lame
// pend vers +y (vers l'extérieur du cercle qu'elle décrit).

uniform vec2 taille = vec2(192.0, 84.0);
uniform vec2 anneau = vec2(96.0, 20.0);
uniform sampler2D dessin : filter_linear_mipmap, repeat_disable;
uniform bool dessin_premultiplie = false;
uniform float largeur = 180.0;
uniform vec2 attache = vec2(0.5, 0.199);
uniform float dos = 9.0;
uniform vec4 fer : source_color = vec4(0.29, 0.33, 0.36, 1.0);
uniform vec4 fer_clair : source_color = vec4(0.42, 0.46, 0.49, 1.0);


float couvre(float d, float px) {
	return clamp(0.5 - d / px, 0.0, 1.0);
}

vec4 sur(vec4 dst, vec4 src) {
	float a = src.a + dst.a * (1.0 - src.a);
	vec3 rgb = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 0.0001);
	return vec4(rgb, a);
}

float boite(vec2 p, vec2 c, vec2 b, float r) {
	vec2 d = abs(p - c) - b + r;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - r;
}

void fragment() {
	vec2 pix = UV * taille;
	// la taille d'un pixel d'écran, quel que soit l'angle de la lame
	float px = max(length(vec2(dFdx(pix.x), dFdy(pix.x))), 0.001);
	vec2 p = pix - anneau;                            // y vers l'extérieur

	// ===================== SON DESSIN =====================
	vec2 sz = vec2(textureSize(dessin, 0));
	// combien de pixels du dessin tombent dans un pixel de l'écran
	float lod = log2(max(px * sz.x / largeur, 0.0001)) - 0.3;
	vec2 uv = attache + p / vec2(largeur, largeur * sz.y / max(sz.x, 1.0));
	vec4 c = vec4(0.0);
	if (uv.x > 0.0 && uv.y > 0.0 && uv.x < 1.0 && uv.y < 1.0) {
		c = textureLod(dessin, uv, lod);
		if (dessin_premultiplie) {
			c.rgb /= max(c.a, 0.0001);
		}
	}

	// ===================== LA PLATINE, SES RIVETS, L'ANNEAU : du fer en aplat =====================
	c = sur(c, vec4(fer_clair.rgb, couvre(boite(p, vec2(0.0, dos), vec2(14.0, 6.5), 2.5), px)));
	c = sur(c, vec4(fer.rgb, couvre(length(vec2(abs(p.x) - 8.5, p.y - dos)) - 2.0, px)));
	c = sur(c, vec4(fer.rgb, couvre(abs(length(p) - 8.0) - 2.6, px)));

	// rien ne touche le bord du rectangle
	float bord = min(min(pix.x, taille.x - pix.x), min(pix.y, taille.y - pix.y));
	c.a *= smoothstep(0.0, 2.0, bord);
	COLOR = c;
}
