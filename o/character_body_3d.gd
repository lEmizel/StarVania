extends CharacterBody3D

enum States { IDLE, WALK, CHUTE, JUMP, LANDING, ATTAQUE, ATTAQUE2 }

var SPEED_AIR = 1.5
const SPEED_RUN = 7.0
const SPEED_WALK = 1.5
const JUMP_HEIGHT = 2.3  # Hauteur max du saut
const JUMP_GRAVITY = 20.0  # Gravité pendant la montée (plus grand = monte plus vite mais retombe plus vite aussi)

# Référence directe à la caméra via la hiérarchie (adapté à ta scène)
@export var main_camera: Camera3D

@onready var animation_player = $Player/AnimationPlayer
@onready var state_functions = {}

var current_direction = Vector3.FORWARD  # Direction de déplacement actuelle
var current_state = States.IDLE
var previous_state = States.IDLE
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready():
	initialize_states()
	change_state(States.IDLE)

#region FUNC EXTERNE OUTILS

#pour gerer les mouvement a l'avant du perssonage
func apply_forward_movement(speed: float) -> void:
	var forward_dir = transform.basis.z
	forward_dir.y = 0
	forward_dir = forward_dir.normalized()

	velocity.x = forward_dir.x * speed
	velocity.z = forward_dir.z * speed
	
	
func apply_air_control(input_dir: Vector2, delta: float, air_speed: float, decel_factor: float):
	const ACCELERATION = 10.0     # Accélération fluide
	if input_dir != Vector2.ZERO:
		var f = main_camera.global_transform.basis.z
		var r = main_camera.global_transform.basis.x
		f.y = 0
		r.y = 0
		var move_dir = (r * input_dir.x + f * input_dir.y).normalized()
		handle_rotation(move_dir, delta)
		velocity.x = move_dir.x * air_speed * 1.5
		velocity.z = move_dir.z * air_speed * 1.5
	else:
		velocity.x = move_toward(velocity.x, 0, ACCELERATION * delta * decel_factor)
		velocity.z = move_toward(velocity.z, 0, ACCELERATION * delta * decel_factor)


func handle_rotation(move_direction: Vector3, delta: float) -> void:
	const ROTATION_THRESHOLD = 0.01  # Seuil minimal pour la rotation
	const ROTATION_SPEED = 10.0   # Vitesse de rotation
	if move_direction.length_squared() > ROTATION_THRESHOLD:
		# Calcul de la rotation cible basée sur la direction du mouvement
		var target_rotation = atan2(move_direction.x, move_direction.z)
		var current_rotation = rotation.y
		# Interpolation fluide vers la rotation cible
		var new_rotation = lerp_angle(current_rotation, target_rotation, ROTATION_SPEED * delta)
		rotation.y = new_rotation
#endregion

################################
### INITIALISATION DES ÉTATS ###
################################

#region INITIALISATION DES ETATS
func initialize_states():
	state_functions[States.IDLE] = {
		"enter": idle_enter,
		"execute": idle_execute,
		"input": idle_input,
		"exit": idle_exit
	}
	state_functions[States.WALK] = {
		"enter": walk_enter,
		"execute": walk_execute,
		"input": walk_input,
		"exit": walk_exit
	}
	state_functions[States.JUMP] = {
		"enter": jump_enter,
		"execute": jump_execute,
		"input": jump_input,
		"exit": jump_exit
	}
	state_functions[States.CHUTE] = {
		"enter": chute_enter,
		"execute": chute_execute,
		"input": chute_input,
		"exit": chute_exit
	}
	state_functions[States.LANDING] = {
		"enter": landing_enter,
		"execute": landing_execute,
		"input": landing_input,
		"exit": landing_exit
	}
	state_functions[States.ATTAQUE] = {
		"enter": attaque_enter,
		"execute": attaque_execute,
		"input": attaque_input,
		"exit": attaque_exit
	}
	state_functions[States.ATTAQUE2] = {
		"enter": attaque2_enter,
		"execute": attaque2_execute,
		"input": attaque2_input,
		"exit": attaque2_exit
	}
#endregion

#######################################
### BOUCLE DE JEU - PHYSICS PROCESS ###
#######################################

#region Func Deleayed
func _physics_process(delta):
	# Appliquer la gravité

	 #Effectue le mouvement et la collision
	move_and_slide()
	# Exécute la fonction propre à l'état courant
	if state_functions.has(current_state) and state_functions[current_state].has("execute"):
		state_functions[current_state]["execute"].call(delta)

### GESTION DES INPUTS ###
func _input(event):
	if state_functions.has(current_state) and state_functions[current_state].has("input"):
		state_functions[current_state]["input"].call(event)

### GESTION DU CHANGEMENT D'ÉTAT ###
func change_state(new_state):
	if state_functions.has(current_state) and state_functions[current_state].has("exit"):
		state_functions[current_state]["exit"].call()
	previous_state = current_state
	current_state = new_state
	if state_functions.has(current_state) and state_functions[current_state].has("enter"):
		state_functions[current_state]["enter"].call()

func play_animation(new_animation, blend_time = 0.2):
	if animation_player.current_animation == new_animation:
		return  # Évite de relancer la même animation
	animation_player.play(new_animation, blend_time)
#endregion

#######################################
##                                   ##
##           MACHINE D'ETATS         ##
##                                   ##
#######################################

#region IDLE
func idle_enter():
	print("playidle")
	play_animation("idle", 0.3)
	velocity.x = 0
	velocity.z = 0

func idle_execute(delta):
	if Input.is_action_pressed("left") or Input.is_action_pressed("right") or Input.is_action_pressed("up") or Input.is_action_pressed("down"):
		change_state(States.WALK)
	if not is_on_floor():
		change_state(States.CHUTE)

func idle_input(event):
	# Si j'appuie sur Jump et que je suis au sol → JUMP
	if Input.is_action_just_pressed("jump") and is_on_floor():
		change_state(States.JUMP)
	if Input.is_action_just_pressed("attaque") and is_on_floor():
		change_state(States.ATTAQUE)

func idle_exit():
	pass
#endregion

#region WALK
func walk_enter():
	print("playwalk")
	play_animation("walk", 0.3)
	animation_player.set_speed_scale(1.3)  # Valeur par défaut en marche

func calculate_move_direction(input_dir: Vector2) -> Vector3:
	if not main_camera:
		return Vector3.ZERO
	var basis = main_camera.global_transform.basis
	var move_dir_3d = basis.x * input_dir.x + basis.z * input_dir.y
	move_dir_3d.y = 0
	return move_dir_3d.normalized()

func walk_execute(delta: float) -> void:
	# On récupère la direction voulue (Input.get_vector est plus simple pour l’axe x,y).
	var input_dir = Input.get_vector("left", "right", "up", "down")

	# Si aucune direction, on repasse en IDLE.
	if input_dir.length() < 0.01:
		change_state(States.IDLE)
		return

	# Calcul de la direction de déplacement en 3D, puis rotation du perso.
	var move_direction = calculate_move_direction(input_dir)
	handle_rotation(move_direction, delta)

	# Seuil et vitesses.
	const THRESHOLD_FULL_PRESS = 0.9

	# Si "shift" ou l'amplitude de l'input est proche de 1, on considère que l’on court.
	var is_running = Input.is_action_pressed("shift") or input_dir.length() >= THRESHOLD_FULL_PRESS
	var speed = SPEED_RUN if is_running else SPEED_WALK
	var anim_speed = 2.5 if is_running else 1.3
	var anim_name = "run" if is_running else "walk"

	# Application de la vitesse calculée.
	velocity.x = move_direction.x * speed
	velocity.z = move_direction.z * speed

	# Réglage et lecture de l’animation.
	animation_player.set_speed_scale(anim_speed)
	play_animation(anim_name, 0.3)

	# Si plus en contact avec le sol → chute.
	if not is_on_floor():
		change_state(States.CHUTE)

func walk_input(event):
	if Input.is_action_just_pressed("jump") and is_on_floor():
		change_state(States.JUMP)
	if Input.is_action_just_pressed("attaque") and is_on_floor():
		change_state(States.ATTAQUE)

func walk_exit():
	animation_player.set_speed_scale(1.0)
	velocity = Vector3.ZERO
#endregion

#region JUMP



func jump_enter():
	print("je saute")
	animation_player.set_speed_scale(2.5)
	play_animation("jump", 0.3)
	# Calcul automatique de la bonne vitesse de départ
	velocity.y = sqrt(2 * JUMP_GRAVITY * JUMP_HEIGHT)

func jump_execute(delta):
	velocity.y -= JUMP_GRAVITY * delta  # Gravité perso pour montée
	apply_air_control(Input.get_vector("left", "right", "up", "down"), delta, SPEED_AIR * 2.0, 0.5) # utilise une fonction externe a l'etat

	# Si je commence à descendre → je passe en chute
	if velocity.y <= 0:
		change_state(States.CHUTE)

func jump_input(event):
	pass  # Ici tu peux ignorer les inputs, sauf si tu veux du contrôle aérien plus tard

func jump_exit():
	animation_player.set_speed_scale(1.0)
#endregion

#region CHUTE

func chute_enter():
	print("je chute")
	play_animation("falling", 0.3)

func chute_execute(delta):
	velocity.y -= gravity * 2.5 * delta
	apply_air_control(Input.get_vector("left", "right", "up", "down"), delta, SPEED_AIR * 2.0, 0.5)# utilise une fonction externe a l'etat
	if is_on_floor():
		change_state(States.LANDING)

func chute_input(event):
	pass  # La chute ne prend pas d'input particulier

func chute_exit():
	# Reset la vélocité verticale pour éviter les bugs de rebond ou stuck
	velocity.y = 0
	


#endregion

#region LANDING
func landing_enter():
	animation_player.set_speed_scale(2.0)
	velocity = Vector3.ZERO
	play_animation("atterissage", 0.3)
	animation_player.animation_finished.connect(Callable(self, "_on_landing_finished"), CONNECT_ONE_SHOT)

func landing_execute(delta):
	pass
	
func landing_input(event):
	pass  # La chute ne prend pas d'input particulier
	
func landing_exit():
	animation_player.set_speed_scale(1.0)

	
func _on_landing_finished(anim_name):
	if anim_name == "atterissage":
		change_state(States.IDLE)
#endregion

#region ATTAQUE

var combo = null
var move = false
#fonc appelées par le Call Method Track
func move_combo():
	move = true

func end_move_combo():
	move = false
	
func attaque_enter():
	play_animation("combo", 0.3)
	animation_player.animation_finished.connect(Callable(self, "_on_combo_finished"), CONNECT_ONE_SHOT)

func attaque_execute(delta):
	# Tant que l'animation "combo" joue, on vérifie la variable 'move'
	if animation_player.current_animation == "combo":
		if move:
			apply_forward_movement(2.5)  # ex: vitesse de 2.0
		else:
			velocity.x = 0
			velocity.z = 0
	else:
		velocity.x = 0
		velocity.z = 0
	if animation_player.current_animation == "combo_R":
		if Input.is_action_just_pressed("attaque"):
			change_state(States.ATTAQUE2)

func attaque_input(event):
	if Input.is_action_just_pressed("attaque"):
		combo = 1

func attaque_exit():
	animation_player.set_speed_scale(1.0)
	move = false  # On coupe le mouvement quand on sort de l'état
	combo = null


func _on_combo_finished(anim_name):
	if anim_name == "combo":
		print("comba", combo)
		if combo == 1:
			change_state(States.ATTAQUE2)
		else:
			play_animation("combo_R", 0.3)
			animation_player.animation_finished.connect(Callable(self, "_on_combo_finished"), CONNECT_ONE_SHOT)
	elif anim_name == "combo_R":
		change_state(States.IDLE)
#endregion


func attaque2_enter():
	play_animation("combo_02", 0.3)
	animation_player.animation_finished.connect(Callable(self, "_on_combo2_finished"), CONNECT_ONE_SHOT)

func attaque2_execute(delta):
	if animation_player.current_animation == "combo_02":# Pendant que l'animation "combo" est en cours, on avance le personnage
		if move:
			apply_forward_movement(3.0)  # ex: vitesse de 2.0
		else:
			velocity.x = 0
			velocity.z = 0
	else:
		velocity.x = 0
		velocity.z = 0

func attaque2_input(event):
	pass  # La chute ne prend pas d'input particulier

func attaque2_exit():
	combo = null
	animation_player.set_speed_scale(1.0)

func _on_combo2_finished(anim_name):
	if anim_name == "combo_02":
		play_animation("combo_02_R", 0.3)
		animation_player.animation_finished.connect(Callable(self, "_on_combo2_finished"), CONNECT_ONE_SHOT)
	elif anim_name == "combo_02_R":
		change_state(States.IDLE)
