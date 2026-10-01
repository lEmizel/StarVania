shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;
// ŒIL DU CANON DE VERRE (v2, 1er oct. 2026) — talisman « Canon de verre » : un
// petit ŒIL DE FEU, l'œil de Sauron (idée de Kaoru), qui flotte au-dessus de la
// tête du héros tant que le talisman est porté.
// v1 : une amande cernée d'encre, un iris en bandes, une couronne de flammes
// pleines → « plus fidèle à Sauron, moins gros, plus vaporeux » (Kaoru).
// v2 : PLUS PETIT, SANS TRAIT D'ENCRE, tout en feu et en vapeur :
//   - une FENTE noire, haute et étroite, effilée aux deux bouts, qui regarde du
//     côté du héros — et tout le feu se RETOURNE avec elle : regardant à
//     droite, l'œil est le miroir exact de l'œil qui regarde à gauche (avec le
//     même feu des deux côtés, son bord rongé et ses flammes penchaient un peu
//     plus à droite en moyenne : le regard à droite paraissait moins marqué,
//     Kaoru) ;
//   - autour d'elle un cœur JAUNE BRÛLANT, qui passe à l'orange puis à la braise
//     vers les coins de l'amande, strié de fibres qui rayonnent de la fente ;
//   - un bord flou, et des VOLUTES de feu translucides qui s'en détachent et
//     montent en se défaisant (des bruits empilés et tordus, comme la brume du
//     sillage de sang) ;
//   - une lueur autour, AJOUTÉE à ce qu'il y a derrière (d'où le mode de fusion
//     prémultiplié : l'œil couvre, sa lueur éclaire) ;
//   - il CLIGNE de temps en temps (Kaoru) : TOUT se referme, l'œil et son feu,
//     comme une flamme qui se ferme sur elle-même — le dessin entier s'écrase
//     vers la ligne de l'œil (et se resserre un peu sur les côtés) jusqu'à
//     n'être qu'un fil de feu, puis se rouvre (`paupiere`). Une 1re version
//     fermait des paupières de braise sur l'œil en laissant brûler le feu
//     autour : Kaoru voulait « tout fermer ».
// Les réglages de la v1 que la scène a gardés (`amande`, `encre_px`, `flammes`,
// `coeur`, `orange`…) ne servent plus : ceux de la v2 portent d'AUTRES NOMS
// exprès, pour que la scène ne leur impose pas les valeurs de la v1.
// Repère : des pixels ; `centre` = le milieu de l'œil, depuis le milieu du
// rectangle.

// --- fournis par oeil_canon.gd -----------------------------------------------
uniform vec2 taille = vec2(90.0, 64.0);
uniform float temps = 0.0;
// 0 = fermé (une ligne), 1 = grand ouvert
uniform float ouvert : hint_range(0.0, 1.0) = 1.0;
// -1 : il regarde à gauche, +1 : à droite
uniform float regard : hint_range(-1.0, 1.0) = 1.0;
// l'œil est posé un peu sous le milieu du rectangle : ses volutes ont la place
// de monter
uniform vec2 centre = vec2(0.0, 6.0);
// 1 = ouvert, 0 = refermé sur lui-même (un clignement)
uniform float paupiere : hint_range(0.0, 1.0) = 1.0;
// refermé, il reste ce fil de feu (part de sa hauteur) ; et il se resserre sur
// les côtés jusqu'à cette part de sa largeur
uniform float fil_ferme : hint_range(0.0, 0.3) = 0.07;
uniform float resserre_ferme : hint_range(0.3, 1.0) = 0.8;
// ----------------------------------------------------------------------------

// --- l'œil ---
// demi-largeur et demi-hauteur de l'amande (px)
uniform vec2 demi_oeil = vec2(15.5, 6.0);
// flou de son bord (px) : pas de trait, il se fond dans ses volutes ; et de
// combien les volutes le rongent (px) : un bord de flamme, pas un ovale net
uniform float flou : hint_range(0.2, 4.0) = 1.6;
uniform float bord_ronge : hint_range(0.0, 6.0) = 2.4;
// demi-largeur de la fente (px) ; de combien elle se décale du côté du regard (px)
uniform float largeur_fente : hint_range(0.5, 5.0) = 1.8;
uniform float decalage_regard = 2.3;
// --- les volutes ---
// jusqu'où elles montent au-dessus de l'œil, et s'étendent sur ses côtés et
// dessous (px)
uniform float montee = 24.0;
uniform float etendue = 7.0;
// leur finesse (plus grand = des volutes plus fines ; à 0,12 elles faisaient
// des flammes hachées, pas de la vapeur), leur vitesse de montée (px/s)
uniform float grain : hint_range(0.03, 0.4) = 0.075;
uniform float vitesse = 18.0;
// leur opacité au plus dense (elles laissent voir le décor)
uniform float opacite_volutes : hint_range(0.0, 1.0) = 0.78;
// force de la lueur autour de l'œil (0 = aucune)
uniform float halo : hint_range(0.0, 1.0) = 0.3;
// --- les couleurs : la fente, le cœur brûlant, le feu, la braise, la fumée ---
uniform vec4 couleur_fente : source_color = vec4(0.04, 0.0, 0.0, 1.0);
uniform vec4 couleur_coeur : source_color = vec4(1.0, 0.93, 0.58, 1.0);
uniform vec4 couleur_feu : source_color = vec4(1.0, 0.5, 0.08, 1.0);
uniform vec4 couleur_braise : source_color = vec4(0.86, 0.13, 0.04, 1.0);
uniform vec4 couleur_fumee : source_color = vec4(0.36, 0.03, 0.03, 1.0);

float hachis(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float bruit(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	return mix(mix(hachis(i), hachis(i + vec2(1.0, 0.0)), u.x),
			mix(hachis(i + vec2(0.0, 1.0)), hachis(i + vec2(1.0, 1.0)), u.x), u.y);
}

// trois bruits empilés (0 → 1, autour de 0,5), chacun TOURNÉ par rapport au
// précédent : alignés, leurs carreaux se voyaient (des volutes en escalier)
float bruits(vec2 p) {
	float s = bruit(p) * 0.55;
	p = vec2(0.8 * p.x - 0.6 * p.y, 0.6 * p.x + 0.8 * p.y) * 2.03 + vec2(17.0, 5.0);
	s += bruit(p) * 0.3;
	p = vec2(0.8 * p.x - 0.6 * p.y, 0.6 * p.x + 0.8 * p.y) * 2.02 + vec2(3.0, 29.0);
	s += bruit(p) * 0.15;
	return s;
}

// le feu lu en p : des bruits empilés, tordus l'un par l'autre, qui montent
// (0 → 1, autour de 0,5)
float feu(vec2 p) {
	vec2 q = p * grain;
	vec2 tord = vec2(bruits(q * 0.9 + vec2(3.1, temps * 0.35)), bruits(q * 0.9 + vec2(8.4, temps * 0.4 + 2.0)));
	return bruits(q * vec2(1.5, 0.75) + (tord - 0.5) * 1.6 + vec2(0.0, temps * vitesse * grain));
}

// l'amande : l'intersection de deux disques (paupières), positive dedans (px)
float en_amande(vec2 p, vec2 demi) {
	float h = max(demi.y, 0.01);
	float R = (demi.x * demi.x + h * h) / (2.0 * h);
	float haut = R - length(p - vec2(0.0, R - h));
	float bas = R - length(p - vec2(0.0, -(R - h)));
	return min(haut, bas);
}

void fragment() {
	vec2 p0 = (UV - 0.5) * taille - centre;
	float o = clamp(ouvert, 0.0, 1.0);
	// LE CLIGNEMENT : tout s'écrase vers la ligne de l'œil et s'y resserre — on
	// lit le dessin dans un repère étiré d'autant (la flamme se ferme sur
	// elle-même ; ses volutes y sont aspirées)
	float pp = clamp(paupiere, 0.0, 1.0);
	float ecrase = max(pp, fil_ferme);
	vec2 p = vec2(p0.x / mix(resserre_ferme, 1.0, pp), p0.y / ecrase);
	// (le flou d'un bord, compté dans ce repère, s'élargit d'autant : sinon les
	// bords deviennent durs pendant qu'il se ferme)
	float flou_e = flou / max(ecrase, 0.25);
	vec2 demi = vec2(demi_oeil.x, max(demi_oeil.y * o, 0.4));
	float d = en_amande(p, demi);                 // px, positive dedans
	float dehors = max(-d, 0.0);
	// fermé (le talisman ôté), ni volutes ni lueur
	float presence = smoothstep(0.0, 0.6, o);
	// LE FEU SE RETOURNE AVEC LE REGARD : à droite, on le lit en miroir (l'œil
	// qui regarde à droite est le reflet exact de celui qui regarde à gauche) ;
	// pendant que le regard passe d'un côté à l'autre, les deux se fondent
	float cote = smoothstep(-0.35, 0.35, regard);    // 0 : à gauche, 1 : à droite

	// ===================== LES VOLUTES =====================
	// elles portent plus loin au-dessus de l'œil (elles montent) que sur ses
	// côtés et dessous
	float vers_le_haut = -p.y / max(length(p), 0.001);
	float portee = mix(etendue, montee, smoothstep(-0.15, 0.85, vers_le_haut));
	float f = clamp(1.0 - dehors / max(portee, 0.001), 0.0, 1.0);
	float n = mix(feu(p), feu(vec2(-p.x, p.y)), cote);
	// près de l'œil elles sont denses ; plus haut il n'en reste que des filets,
	// de plus en plus transparents
	float volute = smoothstep(0.0, 0.7, f - (1.0 - n) * 0.85) * presence;
	float chaleur = volute * f;
	vec3 teinte_v = mix(couleur_fumee.rgb, couleur_braise.rgb, smoothstep(0.05, 0.4, chaleur));
	teinte_v = mix(teinte_v, couleur_feu.rgb, smoothstep(0.4, 0.9, chaleur));
	float a_v = volute * opacite_volutes * mix(0.3, 1.0, f);

	// ===================== L'ŒIL =====================
	// son bord est rongé par les volutes, et flou
	float a_o = smoothstep(-flou_e, flou_e, d + (n - 0.5) * bord_ronge);
	vec2 c0 = vec2(regard * decalage_regard, 0.0);
	vec2 u = (p - c0) / demi;
	float rr = length(u * vec2(1.2, 0.8));        // 0 à la fente → ~1 aux coins
	vec3 teinte_o = mix(couleur_coeur.rgb, couleur_feu.rgb, smoothstep(0.12, 0.62, rr));
	teinte_o = mix(teinte_o, couleur_braise.rgb, smoothstep(0.6, 1.15, rr));
	// des fibres qui rayonnent de la fente et filent vers le bord (l'angle en
	// miroir haut/bas : pas de couture ; et gauche/droite avec le regard)
	float angle = abs(atan(u.y, u.x));
	float fibres = mix(bruit(vec2(angle * 4.5, rr * 2.5 - temps * 1.2)),
			bruit(vec2((PI - angle) * 4.5, rr * 2.5 - temps * 1.2)), cote);
	teinte_o *= mix(0.78, 1.14, fibres);
	// un liseré de feu le long des paupières : c'est de là que partent les volutes
	teinte_o = mix(teinte_o, couleur_feu.rgb, (1.0 - smoothstep(0.0, 2.6, d)) * 0.55);
	// vers les coins il laisse un peu voir le décor (une vapeur, pas un galet)
	a_o *= mix(1.0, 0.86, smoothstep(0.5, 1.1, rr));

	// ===================== LA FENTE =====================
	// haute, étroite, effilée aux deux bouts ; elle bat doucement ; quand il se
	// ferme, elle s'amincit avec lui (écrasée sans s'amincir, elle devenait un
	// rond noir) et s'efface (il en restait un point noir sur le fil)
	float pouls = 0.5 + 0.5 * sin(temps * 1.9);
	vec2 s = (p - c0) / vec2(largeur_fente * mix(0.8, 1.15, pouls) * mix(0.35, 1.0, pp), max(demi.y * 0.97, 0.4));
	float fente = 1.0 - (abs(s.x) + s.y * s.y);
	float a_f = smoothstep(0.0, 0.45, fente) * a_o * smoothstep(0.15, 0.5, pp);

	// ===================== LA LUEUR =====================
	// elle s'éteint AVANT le bord du rectangle (à support borné : une
	// exponentielle y laissait un reste, coupé net par le garde-fou du bord) ;
	// elle baisse quand il se ferme
	float g = clamp(1.0 - dehors / max(portee * 1.1, 0.001), 0.0, 1.0);
	float lueur = halo * g * g * presence * mix(0.45, 1.0, pp);

	// ===================== LE TOUT (couleurs prémultipliées) =====================
	vec3 rgb = teinte_v * a_v;
	float a = a_v;
	rgb = teinte_o * a_o + rgb * (1.0 - a_o);
	a = a_o + a * (1.0 - a_o);
	rgb = couleur_fente.rgb * a_f + rgb * (1.0 - a_f);
	rgb += couleur_braise.rgb * lueur;
	// rien ne touche le bord du rectangle
	vec2 bord = min(UV, 1.0 - UV) * taille;
	float garde = smoothstep(0.0, 6.0, min(bord.x, bord.y));
	COLOR = vec4(rgb * garde, a * garde);
}
