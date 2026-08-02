extends Camera2D

# Variables pour contrôler le décalage de la caméra
var offset_amount: Vector2 = Vector2(300, 220) # Décalage maximal
var return_speed: float = 5.0 # Vitesse de retour à la position initiale
var current_offset: Vector2 # Offset actuel de la caméra

# Shake
var _shake_intensity := 0.0
var _shake_decay := 5.0

func _ready():
	make_current()
	# On initialise l'offset actuel à la valeur souhaitée au départ
	current_offset = Vector2(0, -100)  # Offset initial vertical

func _process(delta):
	# Détection des inputs de la caméra
	var input_offset = Vector2.ZERO
	if Input.is_action_pressed("camera_right"):
		input_offset.x += 1
	if Input.is_action_pressed("camera_left"):
		input_offset.x -= 1
	if Input.is_action_pressed("camera_down"):
		input_offset.y += 1
	if Input.is_action_pressed("camera_up"):
		input_offset.y -= 1

	# Calcul de la cible d'offset
	var target_offset = input_offset * offset_amount
	# On ajoute l'offset vertical initial
	target_offset.y += -150

	# Interpolation vers le target_offset pour un mouvement lisse
	current_offset = current_offset.lerp(target_offset, delta * return_speed)

	# Mise à jour de la position de la caméra avec le joueur comme centre
	var target = _find_first_player()
	# Shake decay
	if _shake_intensity > 0.0:
		_shake_intensity = lerp(_shake_intensity, 0.0, _shake_decay * delta)
		if _shake_intensity < 0.5:
			_shake_intensity = 0.0

	if target:
		var shake_offset := Vector2.ZERO
		if _shake_intensity > 0.0:
			shake_offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake_intensity
		var pos = target.global_position + current_offset + shake_offset
		global_position = _clamp_to_barriers(pos).floor()


## Applique les barrières LIMITE_CAMERA posées dans le niveau (groupe
## "CAMERA_LIMIT") : chacune empêche un bord de l'écran de la franchir
## quand la caméra est à sa hauteur
func _clamp_to_barriers(pos: Vector2) -> Vector2:
	var half := get_viewport_rect().size * 0.5 / zoom
	for b in get_tree().get_nodes_in_group("CAMERA_LIMIT"):
		if b is Node2D and b.has_method("clamp_camera"):
			pos = b.clamp_camera(pos, half)
	return pos

# Fonction pour trouver le premier joueur dans le groupe "player"
func _find_first_player():
	var players = get_tree().get_nodes_in_group("Player")
	if players.size() > 0:
		return players[0]
	return null

func shake(intensity: float = 10.0, decay: float = 5.0) -> void:
	_shake_intensity = intensity
	_shake_decay = decay
