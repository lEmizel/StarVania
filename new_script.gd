extends CharacterBody2D
@onready var player = get_node("/root/Player")

@onready var animation_player = $Node2D/AnimatedSprite2D
@onready var POINT = $Node2D
@onready var ray_cast = $Node2D/RayCast2D
@onready var ancre_droite = $ancredroite
@onready var ancre_gauche = $ancregauche

@onready var climbcast_up = $climbcastup
@onready var climbcast_down = $climbcastdown
@onready var climbcast_right = $climbcastright
@onready var climbcast_left = $climbcastleft
@onready var wall_right = $wall_right
@onready var wall_left = $wall_left
@onready var wall_rightup = $wall_right
@onready var wall_leftup = $wall_left

const MAX_SLOPE_ANGLE = 45

enum States { DEAD, IDLE, RUN, JUMP, CHUTE, SUSPENDU, CLIMB, HIT, ATTACK_LIGHT_1, ATTACK_LIGHT_2, ATTACK_LIGHT_3, ROLL, BACK_ROLL, CHUTE_GRIFFE, WALL_JUMP, WALL_GRIFFE, CHECK_POINT,SPAWN }

var current_state = States.SPAWN
var previous_state = States.IDLE

var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")
var last_direction:
	get:
		return player.get_last_direction()
	set(value):
		player.set_last_direction(value)
signal hp_changed(hp)
signal mort
signal checkpoint
signal HIT

var hp:
	get:
		return player.get_hp()
	set(value):
		player.set_hp(value)
var fall_start_height = 0.0
var hauteur_de_chute = 0.0
var no_WJ = false

var hook_point:
	get:
		if last_direction == 1:
			return ancre_gauche
		else:
			return ancre_droite

func _ready():
	#last_direction = player.get_last_direction()
	Player.position_x_actuel = position.x
	Player.position_y_actuel = position.y
	Player.is_dead = false
	add_to_group("Player")
	call_deferred("emit_signal", "hp_changed", hp)
	set_floor_snap_length(6.0)
	self.floor_max_angle = deg_to_rad(MAX_SLOPE_ANGLE)
	POINT.scale.x = -last_direction
	

func _physics_process(delta):
	handle_states(delta)
	move_and_slide()

	
func apply_damage(amount):
	if not Player.is_dead:
		print("Points de vie actuels :", self.hp)
		self.hp -= amount
		emit_signal("hp_changed", hp)
		print("Points de vie actuels :", self.hp)
		if self.hp <= 0:
			Player.is_dead = true
			print('jevais mourire')
			change_state(States.DEAD)
		elif current_state != States.HIT:
			change_state(States.HIT)
			emit_signal("hp_changed", hp)  # Émet le signal avec la nouvelle valeur de hp

			
func degat_de_chute(hauteur_chute):
	var non_lethal_fall = 500  # Hauteur en dessous de laquelle la chute n'est pas mortelle
	var damage_per_10_percent = 1  # Dommages ajoutés pour chaque tranche de 10% au-dessus de la hauteur non mortelle
	print("Hauteur de chute : ", hauteur_chute)
	
	if hauteur_chute > non_lethal_fall:# Si la hauteur de chute est supérieure à la hauteur non mortelle, calculer les dégâts
		var extra_height_percentage = (hauteur_chute - non_lethal_fall) / non_lethal_fall# Calculer le pourcentage supplémentaire au-dessus de la hauteur non mortelle
		var damage_increments = int(extra_height_percentage * 10)# Calculer le nombre de tranches de 10% dans le pourcentage supplémentaire
		var total_damage = damage_increments * damage_per_10_percent # Calculer les dégâts totaux en multipliant les incréments par les dégâts par tranche de 10%
		apply_damage(total_damage) # Appliquer les dégâts
	
	if hauteur_chute <= non_lethal_fall:
		if Input.is_action_just_pressed("jump"):
			change_state(States.JUMP)
		elif Input.get_action_strength("right") > 0 or Input.get_action_strength("left") > 0:
			change_state(States.RUN)
		else:
			change_state(States.IDLE)
	
	
func is_colliding_with_climb(ray_cast):
	if ray_cast.is_colliding():
		var collider = ray_cast.get_collider()
		return collider and collider is Area2D and collider.is_in_group("climb")
	return false
	
func change_state(new_state):
	if new_state != current_state:
		previous_state = current_state  # Stocke l'état actuel comme état précédent
		current_state = new_state
		# Gère la logique de transition ici, comme jouer une animation
	else:
		print("Transition vers l'état %s non autorisée depuis l'état %s" % [new_state, current_state])

func handle_states(delta):
	match current_state:
		States.SPAWN:
			spawn(delta)
		States.IDLE:
			idle(delta)
		States.RUN:
			run(delta)
		States.JUMP:
			jump(delta)
		States.CHUTE:
			chute(delta)
		States.ROLL:
			roll(delta)
		States.BACK_ROLL:
			back_roll(delta)
		States.CHUTE_GRIFFE:
			chute_griffe(delta)
		States.SUSPENDU:
			suspendu(delta)
		States.CLIMB:
			climb(delta)
		States.DEAD:
			dead(delta)
		States.HIT:
			hit(delta)
		States.ATTACK_LIGHT_1:
			attack_light_1(delta)
		States.ATTACK_LIGHT_2:
			attack_light_2(delta)
		States.ATTACK_LIGHT_3:
			attack_light_3(delta)
		States.WALL_JUMP:
			wall_jump(delta)
		States.WALL_GRIFFE:
			wall_griffe(delta)
		States.CHECK_POINT:
			check_point(delta)
		# Ajoute ici la logique pour les autres états...
		
func _input(event: InputEvent):
	if current_state == States.IDLE:
		if Input.is_action_just_pressed("jump"):
			change_state(States.JUMP)
	if current_state == States.RUN:
		if Input.is_action_just_pressed("jump"):
			change_state(States.JUMP)
		
func spawn(delta):
	if animation_player.animation != "sit_reverse":
		animation_player.play("sit_reverse")
		animation_player.connect("animation_finished", Callable(self, "_on_spawn_finished"), CONNECT_ONE_SHOT)
	
		
func idle(delta):
	velocity.x = 0
	animation_player.play("idle")
	if Input.get_action_strength("right") + Input.get_action_strength("left") > 0:
		change_state(States.RUN)
	elif not is_on_floor():
		change_state(States.CHUTE)
	elif Input.is_action_just_pressed("esquive"):
		change_state(States.ROLL)
	elif Input.is_action_just_pressed("light_attack"):
		change_state(States.ATTACK_LIGHT_1)
	elif dans_zone_check_point and Input.is_action_just_pressed("griffe"):
		change_state(States.CHECK_POINT)
		
func run(delta):
	const SPEED = 600.0
	const ACCELERATION_RATE = 0.2  # Plus cette valeur est élevée, plus l'accélération est rapide
	var direction = Input.get_axis("left", "right")
	var target_velocity_x = direction * SPEED
	velocity.x = lerp(velocity.x, target_velocity_x, ACCELERATION_RATE)  # Utilisation de lerp pour une accélération progressive vers la vitesse cible

	animation_player.play("run")
	
	if direction != 0:
		last_direction = sign(direction)
		POINT.scale.x = -last_direction
		#player.set_last_direction(last_direction)

	else:
		change_state(States.IDLE)

	# Condition pour changer d'état
	if not is_on_floor():
		change_state(States.CHUTE)  # Change to CHUTE state if not on the floor
	if Input.is_action_just_pressed("esquive"):
		change_state(States.ROLL)
	if Input.is_action_just_pressed("light_attack"):
		change_state(States.ATTACK_LIGHT_1)
	elif dans_zone_check_point and Input.is_action_just_pressed("griffe"):
		change_state(States.CHECK_POINT)

func chute(delta):
	print('jetombe')
	const DECELERATION_RATE = 0.50
	var direction = Input.get_axis("left", "right")
	var SPEED = 400
	var collider_rebord = ray_cast.get_collider()
	var collider_griffe = $climbcastup.get_collider()
	var collider_wall_griffe = $climbcastright.get_collider()
	var in_wall_jump_area = false

	if direction != 0:
		last_direction = sign(direction)
		POINT.scale.x = -last_direction
	if $climbcastright.is_colliding() and collider_griffe is Area2D and collider_griffe.is_in_group("wall_jump"):
		in_wall_jump_area = true
	
	
	if animation_player.animation != "chute":
		fall_start_height = global_position.y
	
	animation_player.play("chute")
	velocity.y += gravity * delta

	if direction != 0 and previous_state != States.WALL_JUMP and previous_state != States.BACK_ROLL:# Contrôle horizontal pendant la chute avec décélération
		velocity.x = direction * SPEED
	else:
		velocity.x = lerp(velocity.x, 0.0, DECELERATION_RATE * delta)
		
		
	# Condition pour vérifier si la touche 'griffe' est pressée et si le raycast détecte un Area2D dans le groupe 'griffe'
	if Input.is_action_pressed('griffe') and $climbcastup.is_colliding() and collider_griffe is Area2D and collider_griffe.is_in_group("griffe"):
		change_state(States.CHUTE_GRIFFE)
	if Input.is_action_pressed('griffe') and $climbcastright.is_colliding() and collider_wall_griffe is Area2D and collider_wall_griffe.is_in_group("griffewall") and not previous_state == States.WALL_GRIFFE:
		change_state(States.WALL_GRIFFE)
	if ray_cast.is_colliding() and collider_rebord is Area2D and collider_rebord.is_in_group("rebord") and previous_state != States.SUSPENDU: # cette ligne sert a se suspendre
		print('aaaaaaaaaa')
		change_state(States.SUSPENDU)
		
	if Input.is_action_just_pressed('griffe'):
		if is_colliding_with_climb(climbcast_up): # Utilisez la fonction générique pour vérifier la collision vers le haut
			if is_colliding_with_climb(climbcast_right) or is_colliding_with_climb(climbcast_down) or is_colliding_with_climb(climbcast_left): # Maintenant, vérifiez les autres directions
				change_state(States.CLIMB)
				print('je climb')
				
	if in_wall_jump_area:
		if is_on_wall() and not no_WJ and (wall_rightup.is_colliding() or wall_leftup.is_colliding()):
			if wall_left.is_colliding() and not Wall_left:
				Wall_left = true
				Wall_right = false
				change_state(States.WALL_JUMP)
			elif wall_right.is_colliding() and not Wall_right:
				Wall_left = false
				Wall_right = true
				change_state(States.WALL_JUMP)
			
			
	if is_on_floor():
		last_direction = -int(POINT.scale.x)
		Wall_left = false
		Wall_right = false
		no_WJ = false
		hauteur_de_chute = abs(fall_start_height - global_position.y)
		degat_de_chute(hauteur_de_chute)  # Appeler la fonction pour gérer les dégâts

			

		
func chute_griffe(delta):
	const DECELERATION_RATE = 0.50
	var direction = Input.get_axis("left", "right")
	var SPEED = 150
	var collider = $climbcastup.get_collider()
	$climbcastup.force_raycast_update()
	velocity.y = 250
	if direction != 0:
		velocity.x = direction * SPEED
	else:
		velocity.x = lerp(velocity.x, 0.0, DECELERATION_RATE * delta)
	if collider and collider.is_in_group("griffe") and Input.is_action_pressed('griffe'):
		animation_player.play("chute_griffe")
		print("Je chute avec mes griffes")
	else:
		change_state(States.CHUTE)
var Wall_left = false
var Wall_right = false

func wall_jump(delta):
	const WALL_YJUMP = -500
	const WALL_XJUMP = 290
	if animation_player.animation == ("jump"):
		velocity.y += gravity * delta
	if wall_right.is_colliding():
		last_direction = 1  # Mur à droite, donc on change la direction vers la gauche
	elif wall_left.is_colliding():
		last_direction = -1   # Mur à gauche, donc on change la direction vers la droite
	POINT.scale.x = last_direction
	
	if animation_player.animation != ("wall_jump") and animation_player.animation != ("jump"):
		velocity.y = 50
		animation_player.play("wall_jump")
			

		
	if animation_player.animation != ("jump"):
		if last_direction == 1 and Input.is_action_just_pressed("jump"):
			animation_player.play("jump")
			velocity.y = WALL_YJUMP
			velocity.x = -WALL_XJUMP
		if last_direction == -1  and Input.is_action_pressed("jump"):
			animation_player.play("jump")
			velocity.y = WALL_YJUMP
			velocity.x = WALL_XJUMP
		
	if not wall_rightup.is_colliding() and last_direction == 1 and animation_player.animation != ("jump"):
		change_state(States.CHUTE)
	if not wall_leftup.is_colliding() and last_direction == -1 and animation_player.animation != ("jump"):
		change_state(States.CHUTE)
	if animation_player.animation == ("jump") and velocity.y > 0:
		change_state(States.CHUTE)
	if Input.is_action_just_pressed("esquive"):
		change_state(States.CHUTE)
		
	
func wall_griffe(delta):
	print("debug_50")
	var collider_griffe = $climbcastright.get_collider()
	player.set_last_direction(1)
	
	if animation_player.animation != ("wall_griffe"):
		print(last_direction)
		print('jesuisenrunwall')
		animation_player.play("wall_griffe")
		velocity.y = 0
		if velocity.x > 0:
			last_direction = 1
			POINT.scale.x = -last_direction
		elif velocity.x < 0:
			last_direction = -1
			POINT.scale.x = -last_direction
		else:
			change_state(States.CHUTE)
			
			
		if last_direction != 0:
			if last_direction == 1:
				velocity.x = 500
			elif last_direction == -1:
				velocity.x = -500
	if not $climbcastright.is_colliding() and not (collider_griffe is Area2D and collider_griffe.is_in_group("griffewall")):
		change_state(States.CHUTE)

func jump(delta):
	const JUMP_VELOCITY = -500.0
	const AIR_CONTROL = 0.2  # Ce facteur détermine à quel point le joueur peut contrôler le personnage en l'air
	const DECELERATION_RATE = 0.95  # Plus cette valeur est proche de 1, plus la décélération est lente
	var direction = Input.get_axis("left", "right")
	var SPEED = 400
	var collider_griffe = $climbcastup.get_collider()
	var collider_wall_griffe = $climbcastright.get_collider()
	
	if direction != 0:
		last_direction = sign(direction)
		POINT.scale.x = -last_direction
	
	velocity.y += gravity * delta

	if direction != 0:
		velocity.x = lerp(velocity.x, direction * SPEED, AIR_CONTROL)
	else:
	# Si aucune direction n'est pressée, on décélère progressivement vers 0
		velocity.x = lerp(velocity.x, 0.0, DECELERATION_RATE * delta)
			

	if (is_on_floor() or previous_state == States.SUSPENDU or previous_state == States.CLIMB or is_on_wall()) and animation_player.animation != "jump":
		print('ver linfini et laudela ')
		velocity.y = JUMP_VELOCITY
		animation_player.play("jump")
	
		
	if ray_cast.is_colliding() and previous_state != States.SUSPENDU: # cette ligne sert a se suspendre
		var collider = ray_cast.get_collider()
		if collider is Area2D and collider.is_in_group("rebord"):
			change_state(States.SUSPENDU)
			
	if Input.is_action_just_pressed('griffe'):
		if is_colliding_with_climb(climbcast_up): # Utilisez la fonction générique pour vérifier la collision vers le haut
			if is_colliding_with_climb(climbcast_right) or is_colliding_with_climb(climbcast_down) or is_colliding_with_climb(climbcast_left): # Maintenant, vérifiez les autres directions
				change_state(States.CLIMB)
				print('je climb')
				
	if Input.is_action_pressed('griffe') and $climbcastright.is_colliding() and collider_wall_griffe is Area2D and collider_wall_griffe.is_in_group("griffewall") and not previous_state == States.WALL_GRIFFE:
		change_state(States.WALL_GRIFFE)
			
	if velocity.y > 0:# Commence à tomber après avoir atteint le point le plus haut du saut
		change_state(States.CHUTE)
		
func roll(delta):
	
	const SPEED = 600.0
	const ACCELERATION_RATE = 0.2  # Plus cette valeur est élevée, plus l'accélération est rapide
	var direction = Input.get_axis("left", "right")
	velocity.y += gravity * delta
	
	if direction != 0 and animation_player.animation != "roll":
		last_direction = sign(direction)
		POINT.scale.x = -last_direction
		velocity.x = direction * SPEED
		animation_player.connect("animation_finished", Callable(self, "_on_roll_animation_finished"))
		animation_player.play("roll")
	elif direction == 0 and animation_player.animation != "roll":
		change_state(States.BACK_ROLL)

func back_roll(delta):
	const JUMP_VELOCITY = -180.0  # Vitesse initiale du saut
	const DECELERATION_RATE = 0.95  # Plus cette valeur est proche de 1, plus la décélération est lente
	const BACK_JUMP_SPEED = -450.0  # Vitesse horizontale du saut arrière
	velocity.y += gravity * delta
	var backward_direction = -sign(POINT.scale.x)# Détermine la direction arrière en fonction de la dernière direction face du personnage
	velocity.x = backward_direction * BACK_JUMP_SPEED # Applique une impulsion horizontale pour le saut arrière
	if animation_player.animation != "jump":
		print('ver linfini et laudela ')
		velocity.y = JUMP_VELOCITY
		animation_player.play("jump")
	if velocity.y > 0:# Transition vers l'état de chute une fois que le personnage commence à descendre
		change_state(States.CHUTE)

		
		

func _on_roll_animation_finished(): # Fonction de rappel interne pour gérer la fin de l'animation de roulade
	match animation_player.animation:
		"roll":
			print('jai fini ma roll')
			# Se déconnecte du signal pour éviter les appels multiples
			animation_player.disconnect("animation_finished", Callable(self, "_on_roll_animation_finished"))
			if Input.get_action_strength("right") + Input.get_action_strength("left") > 0:
				change_state(States.RUN)
			elif Input.is_action_just_pressed("jump"):
				change_state(States.JUMP)
			else:
				change_state(States.IDLE)
			if not is_on_floor():
				change_state(States.CHUTE)  # Change to CHUTE state if not on the floor

func suspendu(delta):
	var collider = ray_cast.get_collider()
	if ray_cast.is_colliding():
		if collider and collider is Area2D and collider.is_in_group("rebord"):
			var local_hook_pos = hook_point.position
			var target_hook_global_pos = collider.global_position
			global_position = target_hook_global_pos - local_hook_pos
			velocity = Vector2(0, 0)
			animation_player.play("grab")
	else:# Si ray_cast ne détecte rien
		change_state(States.CHUTE)
	if velocity.y > 0:
		change_state(States.CHUTE)# Commence à tomber après avoir atteint le point le plus haut du saut

	if Input.is_action_just_pressed("jump"):
		change_state(States.JUMP)
	if Input.is_action_just_pressed("esquive"):
		change_state(States.CHUTE)

func climb(delta):
	print('je suis en climb')
	const SPEEDCLIMB = 200
	var climb_speed_x = SPEEDCLIMB
	var climb_speed_y = SPEEDCLIMB
	var direction_x = Input.get_axis("left", "right")
	var direction_y = Input.get_axis("up", "down")
	# Déterminer quels inputs sont autorisés en fonction des collisions des raycasts
	# Utilisez la fonction générique pour déterminer les directions d'entrée autorisées
	var allow_input_up = is_colliding_with_climb(climbcast_up)
	var allow_input_down = is_colliding_with_climb(climbcast_down)
	var allow_input_left = is_colliding_with_climb(climbcast_right)
	var allow_input_right = is_colliding_with_climb(climbcast_left)

	# Vérifier si l'un des RayCast2D ne détecte PAS la zone
	var cannot_climb = !climbcast_up.is_colliding() or !climbcast_down.is_colliding() or !climbcast_left.is_colliding() or !climbcast_right.is_colliding()

	# Si au moins un RayCast2D ne détecte pas la zone, limiter les inputs
	if cannot_climb:
		if !allow_input_up:
			direction_y = max(direction_y, 0)  # Empêche le déplacement vers le haut
		if !allow_input_down:
			direction_y = min(direction_y, 0)  # Empêche le déplacement vers le bas
		if !allow_input_left:
			direction_x = max(direction_x, 0)  # Empêche le déplacement vers la gauche
		if !allow_input_right:
			direction_x = min(direction_x, 0)  # Empêche le déplacement vers la droite

	# Mise à jour de la vitesse avec les inputs limités
	velocity.x = climb_speed_x * direction_x
	velocity.y = climb_speed_y * direction_y
	if direction_x != 0:
		POINT.scale.x = -1 if direction_x > 0 else 1
		last_direction = direction_x if direction_x != 0 else last_direction
	

	# Gestion des animations d'escalade
	if direction_x == 0 and direction_y == 0:
		if cannot_climb:
			animation_player.play("climbquit")
		else:
			animation_player.play("climbidle")
	elif direction_y > 0:
		animation_player.play("climbup")
	elif direction_y < 0:
		animation_player.play("climbdown")
	elif direction_x < 0:
		animation_player.play("climbsideleft")
	elif direction_x > 0:
		animation_player.play("climbsideright")
		
	if Input.is_action_just_pressed("esquive"):
		change_state(States.CHUTE)
	if Input.is_action_just_pressed("jump"):
		change_state(States.JUMP)
var knockback_velocity = Vector2.ZERO

var COMBO_EARLY = false

func attack_light_1(delta):
	if animation_player.animation != "attackN" and animation_player.animation != "attackN_reverse":
		velocity.x = 0
		COMBO_EARLY = false
		animation_player.play("attackN")
	if animation_player.animation == "attackN_reverse" and Input.is_action_just_pressed("light_attack"):
		change_state(States.ATTACK_LIGHT_2)
	if animation_player.animation == "attackN" and Input.is_action_just_pressed("light_attack"):
		COMBO_EARLY = true
	if not is_on_floor():
		change_state(States.CHUTE)  # Change to CHUTE state if not on the floor
	if Input.is_action_just_pressed("jump"):
		change_state(States.JUMP)
	if Input.is_action_just_pressed("esquive"):
		change_state(States.ROLL)
		
	
func attack_light_2(delta):
	if animation_player.animation != "attackN2" and animation_player.animation != "attackN2_reverse":
		COMBO_EARLY = false
		animation_player.play("attackN2")
	if animation_player.animation == "attackN2_reverse" and Input.is_action_just_pressed("light_attack"):
		change_state(States.ATTACK_LIGHT_3)
	if animation_player.animation == "attackN2" and Input.is_action_just_pressed("light_attack"):
		COMBO_EARLY = true
	if not is_on_floor():
		change_state(States.CHUTE)  # Change to CHUTE state if not on the floor
	if Input.is_action_just_pressed("jump"):
		change_state(States.JUMP)
	if Input.is_action_just_pressed("esquive"):
		change_state(States.ROLL)
	
func attack_light_3(delta):
	if animation_player.animation != "attackN3" and animation_player.animation != "attackN3_reverse":
		COMBO_EARLY = false
		animation_player.play("attackN3")
	if animation_player.animation == "attackN3_reverse" and Input.is_action_just_pressed("light_attack"):
		change_state(States.ATTACK_LIGHT_1)
	if animation_player.animation == "attackN3" and Input.is_action_just_pressed("light_attack"):
		COMBO_EARLY = true
	if not is_on_floor():
		change_state(States.CHUTE)  # Change to CHUTE state if not on the floor
	if Input.is_action_just_pressed("jump"):
		change_state(States.JUMP)
	if Input.is_action_just_pressed("esquive"):
		change_state(States.ROLL)
	
	
func _on_attack_Light_finished():
	match animation_player.animation:
		"attackN":
			if COMBO_EARLY:
				change_state(States.ATTACK_LIGHT_2)
			else:
				animation_player.play("attackN_reverse")
		"attackN_reverse":
			change_state(States.IDLE)
		"attackN2":
			if COMBO_EARLY:
				change_state(States.ATTACK_LIGHT_3)
			else:
				animation_player.play("attackN2_reverse")
		"attackN2_reverse":
			change_state(States.IDLE)
		"attackN3":
			animation_player.play("attackN3_reverse")
		"attackN3_reverse":
			if COMBO_EARLY:
				change_state(States.ATTACK_LIGHT_1)
			else:
				change_state(States.IDLE)
		"wall_griffe":
			change_state(States.CHUTE)
		"wall_jump":
			no_WJ = true
			change_state(States.CHUTE)

func hit(delta):
	emit_signal("HIT")
	leave = false
	const knockback = -200
	velocity.y += gravity * delta
	if animation_player.animation != "hit":
		velocity.x = 0
		velocity.y = knockback
		animation_player.play("hit")
	if velocity.y > 0:
		change_state(States.CHUTE)# Commence à tomber après avoir atteint le point le plus haut du saut
var leave = false
var dans_zone_check_point = false
var checkpoint_x  # Variable pour stocker la position X du checkpoint


func area_detection(valeur, pos_x):
	match valeur:
		"check_point_true":
			print("2")
			dans_zone_check_point = true
			checkpoint_x = pos_x  # Stocker la position X reçue dans la variable
			# Ici, vous pouvez exécuter des actions supplémentaires quand vous êtes dans la zone du checkpoint
		"check_point_false":
			print("4")
			dans_zone_check_point = false
			# Vous pouvez gérer d'autres valeurs si nécessaire
			pass
	
	
func check_point(delta):
	velocity.x = 0
	velocity.y = 0
	emit_signal("hp_changed", hp)
	Player.position_x_actuel = position.x
	Player.position_y_actuel = position.y
	if leave and animation_player.animation != "sit_reverse":
		animation_player.play("sit_reverse")
		animation_player.connect("animation_finished", Callable(self, "_on_sit_reverse_animation_finished"))
	if animation_player.animation != "sit" and animation_player.animation != "sit_reverse":
		if Player.position_x_actuel < checkpoint_x:
			last_direction = 1
			POINT.scale.x = -last_direction
		elif Player.position_x_actuel > checkpoint_x:
			last_direction = -1
			POINT.scale.x = -last_direction
		velocity.x = 0
		velocity.y = 0
		animation_player.play("sit")
		emit_signal("checkpoint")

func _on_sit_reverse_animation_finished():
	match animation_player.animation:
		"sit_reverse":
			leave = false
			change_state(States.IDLE)

func _on_spawn_finished():
	match animation_player.animation:
		"sit_reverse":
			leave = false
			change_state(States.IDLE)
			
func on_leave():
	leave = true
	
	
var deado = false

func dead(delta):
	velocity.x = 0
	velocity.y = 0
	velocity.y += gravity * delta
	if animation_player.animation != "death_slice":
		animation_player.play("death_slice")
		animation_player.connect("animation_finished", Callable(self, "_on_death_animation_finished"))
	elif Input.is_action_pressed("jump") and deado:
		print('je suis vraiment mort comme sa ?')
		queue_free() # Supprime l'objet de la scène
		emit_signal("mort")
	
func _on_death_animation_finished():
	match animation_player.animation:
		"death_slice":
			deado = true
