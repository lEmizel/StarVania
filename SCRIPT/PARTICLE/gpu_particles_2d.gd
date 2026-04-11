extends GPUParticles2D
## Poussière dans la lumière — attach ce script à un GPUParticles2D
## Ajuste emission_shape_extents pour couvrir ta zone de lumière.

@export var emission_size := Vector2(200, 400)  ## Taille de la zone d'émission
@export var dust_color := Color(1.0, 0.95, 0.8, 0.35)  ## Couleur chaude semi-transparente
@export var dust_count := 80

func _ready() -> void:
	amount = dust_count
	lifetime = 6.0
	speed_scale = 0.4
	randomness = 1.0
	fixed_fps = 30
	
	# --- Process Material ---
	var mat := ParticleProcessMaterial.new()
	
	# Émission en rectangle (la "zone de lumière")
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(emission_size.x * 0.5, emission_size.y * 0.5, 0)
	
	# Direction générale : légère descente + dérive latérale
	mat.direction = Vector3(0.2, 0.3, 0)
	mat.spread = 45.0
	
	# Vitesse lente et variable
	mat.initial_velocity_min = 3.0
	mat.initial_velocity_max = 10.0
	
	# Gravité quasi nulle (poussière flottante)
	mat.gravity = Vector3(0, 2.0, 0)
	
	# Turbulence pour le mouvement organique
	mat.turbulence_enabled = true
	mat.turbulence_noise_strength = 2.5
	mat.turbulence_noise_speed_random = 0.5
	mat.turbulence_noise_scale = 6.0
	mat.turbulence_influence_min = 0.3
	mat.turbulence_influence_max = 0.7
	
	# Taille variable
	mat.scale_min = 0.4
	mat.scale_max = 1.2
	
	# Fade in / fade out via alpha curve
	var alpha_curve := CurveTexture.new()
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.0))   # invisible au spawn
	curve.add_point(Vector2(0.15, 1.0))  # fade in
	curve.add_point(Vector2(0.8, 1.0))   # visible
	curve.add_point(Vector2(1.0, 0.0))   # fade out
	alpha_curve.curve = curve
	mat.alpha_curve = alpha_curve
	
	# Couleur
	mat.color = dust_color
	
	process_material = mat
	
	# --- Draw pass : petit cercle flou ---
	# On utilise un QuadMesh + un shader pour le look "bokeh"
# --- Texture : petit cercle flou généré en code ---
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for x in 32:
		for y in 32:
			var dist := Vector2(x, y).distance_to(Vector2(16, 16)) / 16.0
			var a := clampf(smoothstep(1.0, 0.2, dist), 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	texture = ImageTexture.create_from_image(img)


const DUST_SHADER := "
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled;

void fragment() {
	float dist = length(UV - vec2(0.5));
	float alpha = smoothstep(0.5, 0.15, dist);
	// Léger scintillement
	float shimmer = sin(TIME * 2.0 + UV.x * 40.0) * 0.15 + 0.85;
	ALBEDO = vec3(1.0, 0.97, 0.9);
	ALPHA = alpha * shimmer * COLOR.a;
}
"
