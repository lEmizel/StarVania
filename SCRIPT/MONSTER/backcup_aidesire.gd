extends CharacterBody2D

@onready var vie: Node2D = $bare_de_vie
@onready var collision = $Collision #collisionshape2d qui sert de hitbox
@onready var point = $POINT #node2d qui sert flip l'entité
@onready var animator =  $POINT/animator # principal animator du personnage pour les mouvements. hors effet speciaux
@onready var vision = $POINT/vision


# Variable exportée pour définir le type d'IA
@export var ai_type: String = "Default"

#variable commune indispensable au script
var approach_initial_position: bool = false
var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")
var current_state = States.IDLE
var previous_state = States.IDLE
var state_functions = {}
var stimuli = false
var target = null
var initial_position :  Vector2
var position_x_player = null
var garde = false
# Déclaration des variables à synchroniser
var speed: float = 0.0
var health: int = 0
var attack_power: int = 0
var confort_zone_max: int = 0
var confort_zone_min: int = 0
var max_tracking_distance: int = 0
var vol = false

# Instance du script de configuration chargé
var config_instance: RefCounted = null

func _ready():
	SignalUtils.connect_signal(animator, "animation_finished", self, "_on_animation_finished")
	SignalUtils.connect_signal(animator, "animation_looped",    self, "_on_animation_looped")
	SignalUtils.connect_signal(animator, "frame_changed",       self, "_on_frame_changed")
	SignalUtils.connect_signal(vision, "body_entered", self, "_on_vision_body_entered")
	call_deferred("set", "initial_position", global_position)
	initialize_states()
	var config_script_path = "res://SCRIPT/MONSTER/Personality_%s.gd" % ai_type
	load_config_script(config_script_path)
	apply_properties()
	vie.max_health = health
	print("coucou")
	print("vie", vie.max_health)
	vie.call_deferred("init_vie")   # ← appel différé, même effet visuel
	
func deferred_set_initial_position():
	initial_position = global_position

func _physics_process(delta):
	move_and_slide()
	if not is_on_floor() and not vol:
		velocity.y += gravity * delta
	if state_functions[current_state].has("execute"):
		state_functions[current_state]["execute"].call(delta)
	
func _on_animation_finished():
	if current_state in state_functions and "animation_finished" in state_functions[current_state]:
		state_functions[current_state]["animation_finished"].call()
	
func _on_animation_looped():
	if current_state in state_functions and "animation_looped" in state_functions[current_state]:
		state_functions[current_state]["animation_looped"].call()

func _on_frame_changed():
	if current_state in state_functions and "frame_changed" in state_functions[current_state]:
		state_functions[current_state]["frame_changed"].call()
	
################################################
#----------------------------------------------#
#----------------------------------------------#
#----------------PARTIE SPECIAL ---------------#
#----------------------------------------------#
#----------------------------------------------#
#----------------------------------------------#
################################################

func _on_vision_body_entered(body):
	if body.is_in_group("Player"):
		print("jevoi le joueur")
		target = body
		stimuli = true
		wake()

func apply_damage(amount):
	if current_state != States.DEAD and not garde:
		desires.clear()
		change_state(States.HIT)
		health -= amount
		vie.emit_signal("health_request", -amount)
		vie.apparition_temp()
		if vie.health <= 0:
			change_state(States.DEAD)
			return

func ennemi_position(x_pos):
	position_x_player = x_pos

func engage_shield():
	pass
	
	
################################################
#----------------------------------------------#
#----------------------------------------------#
#----------PARTIE 1 INITIALISATION-------------#
#----------------------------------------------#
#----------------------------------------------#
#----------------------------------------------#
################################################
#region lecteur du Personality_Ai_type

func load_config_script(file_path: String):
	var script_resource = load(file_path)
	if script_resource and script_resource is GDScript:
		config_instance = script_resource.new()
		print("Configuration loaded successfully for AI type: %s" % ai_type)
		print(ai_type)
	else:
		print("Failed to load configuration script from %s" % file_path)

func apply_properties():
	if config_instance:
		var property_list = config_instance.get_property_list()
		for property in property_list:
			var property_name = property.name
			if has_variable(property_name):
				self.set(property_name, config_instance.get(property_name))

		print("Properties applied successfully.")
		print("Speed:", speed)
		print("Health:", health)
		print("Attack Power:", attack_power)
		wake()

func has_variable(variable_name: String) -> bool:
	return variable_name in ["speed", "health", "attack_power", "confort_zone_min", "confort_zone_max", "max_tracking_distance", "vol"]

#endregion

################################################
#----------------------------------------------#
#----------------------------------------------#
#----------PARTIE 2 CYCLE DE REFLEXION---------#
#----------------------------------------------#
#----------------------------------------------#
#----------------------------------------------#
################################################
var desires = []

func wake():
	if stimuli or target != null:
		generate_desires()
	else:
		sleep()

func sleep():
	desires.clear()
	desires.append({"desire": "sleep", "weight": 1})
	process_desires()

func generate_desires():
	if config_instance and config_instance.has_method("generate_desires"):
		config_instance.generate_desires(self)
	else:
		desires.clear()
		sleep()
	if desires.size() > 0:
		process_desires()



################################################
#----------------------------------------------#
#----------------------------------------------#
#----------PARTIE 3 TRAITEMENT DES ENVIES------#
#----------------------------------------------#
#----------------------------------------------#
#----------------------------------------------#
################################################

func process_desires():
	if desires.size() > 0:
		print("Processing desires")

		# Calculer la somme des poids
		var total_weight = 0
		for desire in desires:
			total_weight += desire["weight"]

	# Si aucun désir n'a de poids, on peut soit retourner à l'état idle,
	# soit forcer un désir par défaut.
		if total_weight == 0:
			print("All desires have zero weight, defaulting to sleep")
			execute_desire({"desire": "sleep", "weight": 1})
			desires.clear()
			return
		# Générer un nombre aléatoire entre 0 et la somme des poids
		var random_choice = randi() % total_weight
		
		# Sélectionner un désir basé sur la roue de la fortune
		var cumulative_weight = 0
		var selected_desire = null
		for desire in desires:
			cumulative_weight += desire["weight"]
			if random_choice < cumulative_weight:
				selected_desire = desire
				break
				
		# Section de conditions spécifiques
		if selected_desire["desire"] == "defend" and garde:
			selected_desire["desire"] = "sleep"
		
		execute_desire(selected_desire)
		desires.clear()
	else:
		print("No desires to process")

func execute_desire(desire):
	match desire["desire"]:
		"sleep":
			print("Executing desire: IDLE")
			change_state(States.IDLE)
		"retreat":
			print("Executing desire: RETREAT")
			change_state(States.RETREAT)
		"approach":
			print("Executing desire: approach")
			change_state(States.APPROACH)
		"attack":
			change_state(States.ATTACK)
		"defend":
			print("Executing desire: DEFEND")
			change_state(States.DEFEND)

		# Ajouter d'autres envies et leurs transitions ici

################################################
#----------------------------------------------#
#----------------------------------------------#
#----------PARTIE 4 TRANSITION D'ETAT----------#
#----------------------------------------------#
#----------------------------------------------#
#----------------------------------------------#
################################################

#region transition d'etat partie 1
enum States { DEAD, IDLE, ATTACK, DEFEND, APPROACH, RETREAT, HIT }

func initialize_states():
	state_functions[States.DEAD] = {
		"enter": dead_enter,
		"execute": dead_execute,
		"exit": dead_exit
	}
	state_functions[States.IDLE] = {
		"enter": idle_enter,
		"execute": idle_execute,
		"animation_looped": idle_animation_looped,
		"exit": idle_exit
	}
	state_functions[States.ATTACK] = {
		"enter": attack_enter,
		"execute": attack_execute,
		"animation_finished": attack_animation_finished,
		"exit": attack_exit
	}
	state_functions[States.DEFEND] = {
		"enter": defend_enter,
		"execute": defend_execute,
		"animation_finished": defend_animation_finished,
		"exit": defend_exit
	}
	state_functions[States.APPROACH] = {
		"enter": approach_enter,
		"execute": approach_execute,
		"exit": approach_exit
	}
	state_functions[States.RETREAT] = {
		"enter": retreat_enter,
		"execute": retreat_execute,
		"exit": retreat_exit
	}
	state_functions[States.HIT] = {
		"enter": hit_enter,
		"execute": hit_execute,
		"exit": hit_exit
	}
	
func change_state(new_state):
	previous_state = current_state
	print("previous_state", previous_state)
	if state_functions[current_state].has("exit"):
		state_functions[current_state]["exit"].call()
	current_state = new_state
	if state_functions[current_state].has("enter"):
		state_functions[current_state]["enter"].call()

#endregion

#region IDLE STATE

func idle_enter():
	print("jesuisenidle")
	if garde:
		animator.play("idle_shield")
	else:
		animator.play("idle")

func idle_execute(_delta):
	pass

func idle_animation_looped():
	print("stimul", stimuli)
	if target != null:
		wake()
	
func idle_exit():
	pass

#endregion

#region DEAD STATE
func dead_enter():
	vision.monitoring = false
	vision.monitorable = false
	stimuli = false
	animator.play("dead")

func dead_execute(_delta):
	pass

func dead_exit():
	pass
#endregion

#region ATTACK STATE
func attack_enter():
	if garde:
		garde = false
		animator.play("down_shield")
	else:
		animator.play("attack")
	var direction = (target.global_position - global_position).normalized()
	if direction.x < 0:
		point.scale.x = -1
	else:
		point.scale.x = 1

func attack_execute(_delta):
	pass
	
func attack_animation_finished():
	match animator.animation:
		"down_shield":
			animator.play("attack")
		"attack":
			print("attack_finie")
			wake()

func attack_exit():
	pass
#endregion

#region DEFEND STATE
func defend_enter():
	garde = true
	velocity.x = 0
	animator.play("up_shield")
	var direction = (target.global_position - global_position).normalized()
	if direction.x < 0:
		point.scale.x = 1
	else:
		point.scale.x = -1

func defend_execute(_delta):
	pass

func defend_animation_finished():
	match animator.animation:
		"up_shield":
			wake()
		"idle_shield":
			animator.play("down_shield")
		"down_shield":
			wake()

func defend_exit():
	pass

#endregion

#region APROACHE STATE
func approach_enter():
	if garde:
		animator.play("walk_shield")
	else:
		animator.play("walk")

func approach_execute(_delta):
	var margin = 50  # Définir une marge pour la position initiale
	
	if target is Vector2:
		var distance_to_initial = global_position.distance_to(target)
		if distance_to_initial <= margin:
			print("Reached initial position")
			target = null
			wake()
			return
		var direction = (target - global_position).normalized()
		velocity.x = direction.x * speed
		if direction.x < 0:
			point.scale.x = -1
		else:
			point.scale.x = 1
	elif target != null:
		var distance_to_target = global_position.distance_to(target.global_position)
		if distance_to_target >= confort_zone_min and distance_to_target <= confort_zone_max:
			print("lacibleestdanslazone")
			wake()
			return
		var direction = (target.global_position - global_position).normalized()
		velocity.x = direction.x * speed
		if direction.x < 0:
			point.scale.x = -1
		else:
			point.scale.x = 1
	else:
		wake()

func approach_exit():
	velocity.x = 0
#endregion

#region RETREAT STATE

func retreat_enter():
	animator.play("walk_back")
	animator.set_speed_scale(-1.0)

func retreat_execute(_delta):
	if target != null:
		var direction
		var distance_to_target
		if target is Node2D:
			distance_to_target = global_position.distance_to(target.global_position)
			direction = (global_position - target.global_position).normalized()
		else:
			distance_to_target = global_position.distance_to(target)
			direction = (global_position - target).normalized()
		
		# Si la distance à la cible dépasse confort_zone_max, appeler wake()
		if distance_to_target > confort_zone_max:
			wake()
			return
		
		velocity.x = direction.x * speed
		velocity.y = 0  # Assurer que la composante y est toujours zéro
		if direction.x < 0:
			point.scale.x = 1
		else:
			point.scale.x = -1
	else:
		wake()

func retreat_exit():
	velocity.x = 0
	animator.set_speed_scale(1.0)

#endregion

#region HIT STATE

func hit_enter():
	velocity.x = 0

func hit_execute(delta):
	const knockback = -120
	var speed = 80
	
	velocity.y += gravity * delta
	if animator.animation != "hit":
		if position_x_player != null:
			var direction = round(global_position.x - position_x_player)
			if direction != 0:	# Créer un vecteur de knockback dans la direction opposée
				var knockback_speed = direction * speed  # Vitesse dans la direction opposée
				velocity.x = knockback_speed * delta  # Appliquer cette vitesse à la propriété velocity.x si c'est un KinematicBody2D
			velocity.y = knockback
			animator.play("hit")
			position_x_player = null
		elif position_x_player == null:
			velocity.x = 0
			velocity.y = knockback
			animator.play("hit")
			position_x_player = null
	if velocity.y > 0:
		wake()

func hit_exit():
	velocity.x = 0

#endregion 
