extends Camera2D

# Variables pour contrôler le décalage de la caméra
var offset_amount: Vector2 = Vector2(300, 220) # Décalage maximal
var return_speed: float = 5.0 # Vitesse de retour à la position initiale
var current_offset: Vector2 # Offset actuel de la caméra

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
	if target:
		global_position = (target.global_position + current_offset).floor()

# Fonction pour trouver le premier joueur dans le groupe "player"
func _find_first_player():
	var players = get_tree().get_nodes_in_group("Player")
	if players.size() > 0:
		return players[0]
	return null
