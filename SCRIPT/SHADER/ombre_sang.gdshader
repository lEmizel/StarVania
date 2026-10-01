shader_type canvas_item;
// OMBRE DE SANG (1er oct. 2026) — talisman « Ombre de sang » : le double du
// héros, en sang. Posé sur la copie de son sprite (ombre_sang.tscn, nœud
// Corps) et sur son slash dessiné : chaque pixel du héros devient un rouge, du
// sombre (les ombres du dessin) au vif (ses lumières) — la pose reste lisible,
// mais c'est un double de sang, pas le héros. Pas de blanc.

// opacité d'ensemble (le script la monte quand l'ombre frappe)
uniform float opacite : hint_range(0.0, 1.0) = 0.6;
uniform vec4 couleur_claire : source_color = vec4(1.0, 0.2, 0.24, 1.0);
uniform vec4 couleur_sombre : source_color = vec4(0.36, 0.0, 0.07, 1.0);
// les valeurs du dessin qui donnent le plus sombre et le plus clair
uniform vec2 contraste = vec2(0.08, 0.85);

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float lum = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
	vec3 c = mix(couleur_sombre.rgb, couleur_claire.rgb, smoothstep(contraste.x, contraste.y, lum));
	COLOR = vec4(c, tex.a * opacite);
}
