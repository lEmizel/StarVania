extends Node



#region grab ring

func grab_ring_enter():
	pass
	
func grab_ring_execute(delta):
	var offset_x = 0
	var offset_y = 115
	
	if last_direction == 1:
		offset_x = -20  # Offset positif si la dernière direction est 1
	elif last_direction == -1:
		offset_x = 20  # Offset négatif si la dernière direction est -1
	var adjusted_target_position = target_position + Vector2(offset_x, offset_y)
	var direction = adjusted_target_position - global_position
	if direction.length() > 1 and grab:  # Si la distance est supérieure à 1 unités
		var speed = 200
		if direction.length() < 4:
			speed = lerp(4, 100, direction.length() / 5)
		if animation_player.animation != "grab_ring_begin":
			animation_player.play("grab_ring_begin")
		velocity = direction.normalized() * speed
	if direction.length() <= 1:
		if animation_player.animation != "grab_ring":
			emit_signal("suspended")
			grab = false
			animation_player.play("grab_ring")
		velocity = Vector2.ZERO  # Arrêt du mouvement
		if direction.length() > 1:
			var speed = 200
			speed = lerp(4, 100, direction.length() / 5)	# Logique spécifique à l'état idle
	global_position += velocity * delta  # Mise à jour de la position
	
	if Input.is_action_just_pressed("jump"):
		grab = true
		emit_signal("not_suspended")
		change_state(States.JUMP)
	if Input.is_action_just_pressed("esquive"):
		grab = true
		emit_signal("not_suspended")
		change_state(States.CHUTE)

func grab_ring_input(event: InputEvent):
	pass

func grab_ring_exit():
	previous_state = current_state
#endregion



#region wallm jump

func wall_jump_enter():
	pass
	
func wall_jump_execute(delta):
	const WALL_YJUMP = -500
	const WALL_XJUMP = 290
	var collider_griffe = $climbcastdown.get_collider()
	
	# Applique la gravité lorsque l'animation de saut est en cours
	if animation_player.animation == "jump":
		velocity.y += gravity * delta

	# Détecte le mur et change la direction en conséquence
	if wall_right.is_colliding():
		last_direction = 1  # Mur à droite, donc on change la direction vers la gauche
	elif wall_left.is_colliding():
		last_direction = -1  # Mur à gauche, donc on change la direction vers la droite

	POINT.scale.x = last_direction

	# Si l'animation n'est pas déjà "wall_jump" ou "jump", on commence la descente
	if animation_player.animation != "wall_jump" and animation_player.animation != "jump":
		animation_player.play("wall_jump")
	
	# Applique le lerp si l'animation "wall_jump" est en cours
	if animation_player.animation == "wall_jump":
		velocity.y = lerp(velocity.y, 400.0, 0.2)  # Réduit progressivement la vitesse verticale vers 400 avec un facteur de transition de 0.2
		print("Velocity Y after lerp: ", velocity.y)

	# Si le collider détecté n'est pas une Area2D du groupe "wall_jump", change d'état
	if not (collider_griffe is Area2D and collider_griffe.is_in_group("wall_jump")):
		no_WJ = true  # Interdit de pouvoir faire un wall jump quand on chute d'un wall jump
		change_state(States.CHUTE)

	# Gestion du saut lors de la détection d'une touche
	if animation_player.animation != "jump":
		if last_direction == 1 and Input.is_action_just_pressed("jump"):
			animation_player.play("jump")
			velocity.y = WALL_YJUMP
			velocity.x = -WALL_XJUMP
			instantiate_animsprite_ground()
			air_ground_instance.scale.x = -abs(air_ground_instance.scale.x)
			air_ground_instance.scale *= 1.8
			air_ground_instance.global_position = ANCRE_WALL_BACK.global_position
			air_ground_instance.play("wall_jump")
		elif last_direction == -1  and Input.is_action_pressed("jump"):
			animation_player.play("jump")
			velocity.y = WALL_YJUMP
			velocity.x = WALL_XJUMP
			instantiate_animsprite_ground()
			air_ground_instance.scale.x = abs(air_ground_instance.scale.x)
			air_ground_instance.scale *= 1.8
			air_ground_instance.global_position = ANCRE_WALL_BACK.global_position
			air_ground_instance.play("wall_jump")

	# Conditions de chute
	if not wall_rightup.is_colliding() and last_direction == 1 and animation_player.animation != "jump":
		change_state(States.CHUTE)
	if not wall_leftup.is_colliding() and last_direction == -1 and animation_player.animation != "jump":
		change_state(States.CHUTE)
	if animation_player.animation == "jump" and velocity.y > 0:
		change_state(States.CHUTE)
		
func wall_jump_input(event: InputEvent):
	if Input.is_action_just_pressed("esquive"):
		change_state(States.CHUTE)

func wall_jump_animation_finished():
	match animation_player.animation:
		"wall_jump":
			no_WJ = true  # Interdit de pouvoir faire un wall jump après un autre wall jump
			change_state(States.CHUTE)

func wall_jump_exit():
	previous_state = current_state

#endregion


func instantiate_animsprite_ground():
	var air_ground = load("res://SCRIPT/CHARACTER/HERO/anim_sprite_ground.tscn")
	air_ground_instance = air_ground.instantiate()
	get_parent().add_child(air_ground_instance)

func run_frame_changed():
	run_frame_counter += 1
	match animation_player.animation:
		"run":
			if run_frame_counter % 2 == 0:  # Exécute le bloc de code une frame sur deux
				instantiate_animsprite_ground()
				air_ground_instance.global_position = ANCRE_SOL_BACK.global_position
				air_ground_instance.play("run_to_ground")
				
				
				
#region WALL_GRIFFE
func wall_griffe_enter():
	animation_player.play("wall_griffe")
	velocity.y = 0
	if velocity.x > 0:
		last_direction = 1
		POINT.scale.x = -last_direction
	elif velocity.x < 0:
		last_direction = -1
		POINT.scale.x = -last_direction
	if last_direction != 0 and velocity.x != 0:
		if last_direction == 1:
			velocity.x = 500
		if last_direction == -1:
			velocity.x = -500

func wall_griffe_execute(delta):
	var collider_griffe = climbcast_right.get_collider()
	Player.set_last_direction(1)
	if not climbcast_right.is_colliding() and not (collider_griffe is Area2D and collider_griffe.is_in_group("griffewall")):
		change_state(States.CHUTE)

func wall_griffe_input(event: InputEvent):
	pass

func wall_griffe_animation_finished():
	change_state(States.CHUTE)

func wall_griffe_exit():
	previous_state = current_state
#endregion
#region JUMP



const JUMP_VELOCITY = -500.0
const AIR_CONTROL = 0.2  # Ce facteur détermine à quel point le joueur peut contrôler le personnage en l'air
const DECELERATION_RATE = 0.95  # Plus cette valeur est proche de 1, plus la décélération est lente

func jump_enter():
	if (is_on_floor() or previous_state == States.SUSPENDU or previous_state == States.CLIMB or previous_state ==  States.GRAB_RING or is_on_wall()):
		velocity.y = JUMP_VELOCITY
		if transformation:
			animation_player.play("jump_shadow")
		else:
			animation_player.play("jump")

func jump_execute(delta):
	var direction = Input.get_axis("left", "right")
	var SPEED = 400
	#var collider_griffe = climbcast_up.get_collider()
	#var collider_wall_griffe = climbcast_right.get_collider()
	
	
	if direction != 0:
		last_direction = sign(direction)
		POINT.scale.x = -last_direction
	velocity.y += gravity * delta
	
	if direction != 0:
		velocity.x = lerp(velocity.x, direction * SPEED, AIR_CONTROL)
	else:# Si aucune direction n'est pressée, on décélère progressivement vers 0
		velocity.x = lerp(velocity.x, 0.0, DECELERATION_RATE * delta)
		
	if ray_cast.is_colliding() and previous_state != States.SUSPENDU: # cette ligne sert a se suspendre
		var collider = ray_cast.get_collider()
		if collider is Area2D and collider.is_in_group("rebord") and not transformation:
			target_position = collider.global_position
			change_state(States.SUSPENDU)
			
	if ray_cast_ring.is_colliding() and previous_state != States.GRAB_RING: # cette ligne sert a se suspendre
		var collider = ray_cast_ring.get_collider()
		if collider is Area2D and collider.is_in_group("ring") and not transformation:
			target_position = collider.global_position
			change_state(States.GRAB_RING)
			
			
	if velocity.y > 0 and current_state != States.WALL_GRIFFE:# Commence à tomber après avoir atteint le point le plus haut du saut
		change_state(States.CHUTE)

func jump_exit():
	previous_state = current_state
#endregion




change_state(States.WALL_JUMP)



var resources = {
	"Blood_jauge": "res://SCRIPT/MENU/Blood_jauge.tscn",
	"SHORCUT_SPELL": "res://SCRIPT/MENU/shorcut_spell.tscn",
	"SHORCUT_ITEM": "res://SCRIPT/MENU/shorcut_item.tscn",
	"HealthBarScene": "res://SCRIPT/MENU/healtbar.tscn"
}
var loaded_resources = {}
var loading = false

func start_loading_resources():
	for key in resources:
		var load_path = resources[key]
		ResourceLoader.load_threaded_request(load_path)
	loading = true

func _process(delta):
	if loading:
		var all_loaded = true
		for key in resources:
			var status = ResourceLoader.load_threaded_get_status(resources[key])
			if status == ResourceLoader.ThreadLoadStatus.THREAD_LOAD_LOADED:
				loaded_resources[key] = ResourceLoader.load_threaded_get(resources[key])
			elif status == ResourceLoader.ThreadLoadStatus.THREAD_LOAD_IN_PROGRESS:
				all_loaded = false
		if all_loaded:
			loading = false  # Fin du chargement
			print("Toutes les ressources sont chargées !")
			spawn_child_ui()

func spawn_child_ui():
	if interface_layer != null:
		interface_layer.add_child(loaded_resources["Blood_jauge"].instantiate())
		interface_layer.add_child(loaded_resources["SHORCUT_SPELL"].instantiate())
		interface_layer.add_child(loaded_resources["SHORCUT_ITEM"].instantiate())
		interface_layer.add_child(loaded_resources["HealthBarScene"].instantiate())
	else:
		print("Erreur : interface_layer n'est pas initialisé.")
