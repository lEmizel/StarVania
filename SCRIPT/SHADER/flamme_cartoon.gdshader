shader_type canvas_item;
render_mode unshaded;
// FLAMME CARTOON v2 — moteur de mouvement riche (fbm 5 octaves, double
// bruit, sommet découpé, langues de feu) + rendu STYLISABLE :
//   style_cartoon = 1 → aplats nets façon dessin animé (nb_bandes couleurs)
//   style_cartoon = 0 → dégradé doux classique
// À poser sur un ColorRect (ratio ≈ 1:1.4). Aucune texture requise.

uniform float speed : hint_range(0.0, 5.0) = 1.4;
uniform float distortion : hint_range(0.0, 1.0) = 0.35;
uniform float flame_width : hint_range(0.1, 1.5) = 0.65;
uniform float flame_height : hint_range(0.1, 2.0) = 1.0;
uniform float detail : hint_range(1.0, 10.0) = 4.0;
// 1 = aplats dessin animé, 0 = dégradé doux — mélangeable entre les deux
uniform float style_cartoon : hint_range(0.0, 1.0) = 1.0;
// nombre d'aplats de couleur en mode cartoon
uniform int nb_bandes : hint_range(2, 8) = 4;
// arrondi du pied de la flamme : 0 = base plate pleine largeur,
// plus grand = pied pincé et arrondi (flamme de bougie)
uniform float arrondi_base : hint_range(0.0, 0.6) = 0.25;
// saturation GLOBALE des quatre couleurs : 1 = telles quelles,
// 0 = noir et blanc, > 1 = plus vives (flamme spectrale à 0.2, enfer à 1.6)
uniform float saturation : hint_range(0.0, 2.0) = 1.0;

uniform vec4 outer_color : source_color = vec4(0.9, 0.05, 0.005, 1.0);
uniform vec4 middle_color : source_color = vec4(1.0, 0.32, 0.01, 1.0);
uniform vec4 inner_color : source_color = vec4(1.0, 0.85, 0.15, 1.0);
uniform vec4 core_color : source_color = vec4(1.0, 1.0, 0.75, 1.0);


// -----------------------------------------------------
// BRUIT
// -----------------------------------------------------

// hash SANS sin : le hash sin(dot(...)) classique perd sa précision GPU
// quand les coordonnées grandissent (défilement temporel) → gros carrés
float random(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = random(i);
	float b = random(i + vec2(1.0, 0.0));
	float c = random(i + vec2(0.0, 1.0));
	float d = random(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	// rotation entre octaves : sans elle, les grilles de bruit s'alignent
	// et dessinent des blocs rectangulaires
	const mat2 ROT = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 5; i++) {
		value += noise(p) * amplitude;
		p = ROT * p * 2.03 + vec2(17.1, 9.2);
		amplitude *= 0.5;
	}
	return value;
}


// -----------------------------------------------------
// FLAMME
// -----------------------------------------------------

void fragment() {
	vec2 uv = UV;
	float y = 1.0 - uv.y;   // 0 en bas de la flamme
	float x = uv.x - 0.5;   // centré
	float time = TIME * speed;

	// --- mouvement général vers le haut : deux bruits mélangés ---
	vec2 noise_uv = vec2(x * detail, y * detail - time * 1.8);
	float n1 = fbm(noise_uv);
	float n2 = fbm(noise_uv * 1.8 + vec2(4.7, -time * 0.6));
	float n = mix(n1, n2, 0.35);

	// --- oscillation horizontale (la base reste plantée) ---
	float sway = sin(y * 8.0 - time * 2.2) * 0.045
		+ sin(y * 15.0 + time * 3.1) * 0.018;
	x += sway * y;

	// distorsion par le bruit, croissante avec la hauteur
	x += (n - 0.5) * distortion * y;

	// --- forme principale : goutte au profil bruité ---
	float width = flame_width * pow(max(1.0 - y / flame_height, 0.0), 0.55);
	width += n * 0.11 * (1.0 - y);  // évite une pointe trop mathématique
	// pied arrondi : la largeur se pince en approchant de la base
	width *= smoothstep(0.0, max(arrondi_base, 0.001), y + 0.02);

	float distance_to_center = abs(x);

	// bord : doux en mode dégradé, tranché en mode cartoon
	float bord_interieur = mix(width * 0.6, width * 0.92, style_cartoon);
	float flame = 1.0 - smoothstep(bord_interieur, width, distance_to_center);

	// --- sommet découpé par le bruit ---
	float top_noise = fbm(vec2(uv.x * 5.0, y * 4.0 - time * 1.7));
	float top = 1.0 - smoothstep(0.72 + top_noise * 0.22, 1.08 + top_noise * 0.15, y);
	flame *= top;

	// --- petites langues de feu sur la moitié haute ---
	float tongues = sin(uv.x * 22.0 + n * 8.0 - time * 3.0) * 0.5 + 0.5;
	float tongue_mask = smoothstep(0.15, 0.85, tongues) * smoothstep(0.25, 0.9, y);
	flame *= mix(1.0, 0.7 + tongue_mask * 0.5, y * 0.45);

	// --- chaleur → couleur ---
	float normalized_center = 1.0 - clamp(distance_to_center / max(width, 0.001), 0.0, 1.0);
	float heat = normalized_center * (1.0 - y * 0.55);
	heat += n * 0.18;
	heat = clamp(heat, 0.0, 1.0);

	// CARTOON : quantifie la chaleur en aplats nets (le bruit continue de
	// faire danser les frontières entre bandes — vivant ET stylisé)
	float heat_aplat = (floor(heat * float(nb_bandes)) + 0.5) / float(nb_bandes);
	heat = mix(heat, heat_aplat, style_cartoon);

	vec3 color;
	if (heat < 0.30) {
		color = mix(outer_color.rgb, middle_color.rgb, heat / 0.30);
	} else if (heat < 0.70) {
		color = mix(middle_color.rgb, inner_color.rgb, (heat - 0.30) / 0.40);
	} else {
		color = mix(inner_color.rgb, core_color.rgb, (heat - 0.70) / 0.30);
	}

	// --- scintillement (atténué en mode cartoon : les aplats vivent déjà) ---
	float flicker = 0.92 + sin(time * 12.0 + y * 7.0) * 0.04 + n * 0.08;
	color *= mix(flicker, 1.0, style_cartoon * 0.6);

	// --- saturation globale : pivote autour de la luminance ---
	float gris = dot(color, vec3(0.299, 0.587, 0.114));
	color = clamp(mix(vec3(gris), color, saturation), 0.0, 1.0);

	// --- alpha : contour net en cartoon, fondu en dégradé ---
	float alpha = mix(flame, smoothstep(0.35, 0.62, flame), style_cartoon);
	alpha *= smoothstep(0.0, 0.08, y);  // base légèrement plus solide

	COLOR = vec4(color, alpha);
}
