shader_type canvas_item;
// FLOU DE FOND (économe) — remplace le flou gaussien 11×11 qui était écrit en
// dur dans scene_06 / scene_7 : 121 lectures d'écran PAR PIXEL à chaque frame,
// un M1 tombait à 40 fps rien qu'avec ça (un 4070 ne le sent pas).
//
// Astuce : Godot génère de toute façon la pyramide de mipmaps de la copie
// d'écran (filter_linear_mipmap). Lire l'écran à un niveau de détail réduit
// EST déjà un flou large et doux → 5 lectures au lieu de 121, même rendu.
// blur_amount garde l'échelle d'avant (≈ rayon du flou / 3, en pixels).

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;
uniform float blur_amount : hint_range(0.0, 10.0) = 3.0;

void fragment() {
	// niveau de mipmap lu : blur 1 → ~2 px, blur 2.25 → ~5 px, blur 3 → ~6 px
	// (+1.1 : calé à l'œil par Kaoru, 30 % plus doux que le premier réglage)
	float lod = log2(max(blur_amount, 0.35)) + 1.1;
	// centre + 4 lectures décalées d'un demi-texel du niveau lu : gomme les
	// marches d'escalier des mipmaps sans coûter plus
	vec2 d = SCREEN_PIXEL_SIZE * exp2(lod) * 0.5;
	vec4 c = textureLod(SCREEN_TEXTURE, SCREEN_UV, lod) * 2.0;
	c += textureLod(SCREEN_TEXTURE, SCREEN_UV + vec2( d.x,  d.y), lod);
	c += textureLod(SCREEN_TEXTURE, SCREEN_UV + vec2(-d.x,  d.y), lod);
	c += textureLod(SCREEN_TEXTURE, SCREEN_UV + vec2( d.x, -d.y), lod);
	c += textureLod(SCREEN_TEXTURE, SCREEN_UV + vec2(-d.x, -d.y), lod);
	COLOR = c / 6.0;
}
