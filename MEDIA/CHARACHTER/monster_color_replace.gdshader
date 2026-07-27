shader_type canvas_item;

// Couleur a remplacer : #3CD738
uniform vec4 target_color : source_color = vec4(0.235, 0.843, 0.22, 1.0);
// Tolerance de detection (0 = couleur exacte uniquement)
uniform float tolerance : hint_range(0.0, 1.0) = 0.15;

// Fond bleu fonce
uniform vec4 background_color : source_color = vec4(0.02, 0.04, 0.18, 1.0);
// Couleur du noise par-dessus le fond
uniform vec4 noise_color : source_color = vec4(0.15, 0.3, 0.7, 1.0);

uniform sampler2D noise_texture : repeat_enable, filter_linear;
uniform float noise_scale : hint_range(0.1, 10.0) = 2.0;
// Vitesse de defilement du noise (mettre a 0,0 pour un noise fixe)
uniform vec2 noise_speed = vec2(0.05, 0.03);

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float dist = distance(tex.rgb, target_color.rgb);

	if (dist < tolerance) {
		float n = texture(noise_texture, UV * noise_scale + noise_speed * TIME).r;
		COLOR = vec4(mix(background_color.rgb, noise_color.rgb, n), tex.a);
	} else {
		COLOR = tex;
	}
}
