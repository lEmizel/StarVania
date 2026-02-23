extends CharacterBody2D

@onready var vie: Node2D = $bare_de_vie
@onready var collision = $Collision #collisionshape2d qui sert de hitbox
@onready var point = $POINT #node2d qui sert flip l'entité
@onready var animator =  $POINT/animator # principal animator du personnage pour les mouvements. hors effet speciaux
@onready var vision: Area2D = $POINT/vision


# Variable exportée pour définir le type d'IA
@export var ai_type: String = "Default"

#variable commune indispensable au script
var approach_initial_position: bool = false
var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")
var current_state = States.IDLE
var previous_state = States.IDLE
var state_functions = {}
var stimuli = false
var initial_position :  Vector2
var position_x_player = null
var garde = false
var target: Node2D = null
var return_position = null
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
	set_floor_max_angle(deg_to_rad(85))   # 60° → radians
	set_floor_snap_length(6.0)
	vie.max_health = health
	print("coucou")
	print("vie", vie.max_health)
	vie.call_deferred("init_vie")   # ← appel différé, même effet visuel
	

func _physics_process(delta):
	if target:
		# Calcule la distance réelle en pixels
		var dist = global_position.distance_to(target.global_position)
		# Affiche la distance et la limite configurée
		# Si la cible est hors de portée, on la perd et on planifie le retour au spawn
		if dist > max_tracking_distance:
			target = null
			return_position = initial_position
			stimuli = false
			wake()

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


# ─── Utility ────────────────────────────────────────────────────


	
func _move_towards(pos: Vector2, spd: float) -> void:
	# Calcule le vecteur de pos cible vers global_position
	var delta = pos - global_position
	if delta.length() < 1.0:
		# On est déjà assez près → on stoppe l’horizontale
		velocity.x = 0
	else:
		# Normalise et applique la vitesse
		var dir = delta.normalized()
		velocity.x = dir.x * spd
		# Flip visuel selon la direction
		point.scale.x = sign(dir.x)

func _on_vision_body_entered(body):
	if body.is_in_group("Player"):
		print("jevoi le joueur")
		target = body
		stimuli = true
		wake()

# Nouveau apply_damage qui prend un float
func apply_damage(amount: int, source_x: float) -> void:
	if current_state == States.DEAD:
		return
	if current_state != States.HIT:
		health -= amount
		vie.emit_signal("health_request", -amount)
		vie.apparition_temp()
		if vie.health <= 0:
			desires.clear()
			print("je suis mort")
			change_state(States.DEAD)
		else:
			desires.clear()
			# on stocke immédiatement la X de l’attaquant
			position_x_player = source_x
			change_state(States.HIT)




func ennemi_position(x_pos):
	position_x_player = x_pos

	
	
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
		print("→ Après apply : max_tracking_distance =", max_tracking_distance)
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
	# on réveille si on a une cible OU un retour à faire
	if stimuli or target or return_position != null:
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
		## Section de conditions spécifiques
		#if selected_desire["desire"] == "defend" and garde:
			#selected_desire["desire"] = "sleep"
		#
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
		"approach_vol":
			print("Executing desire: approach-vol")
			change_state(States.APPROACH_VOL)
		"attack":
			change_state(States.ATTACK)
		"defend":
			print("Executing desire: DEFEND")
			change_state(States.DEFEND)
		"return":
			print("Executing desire: RETURN")
			change_state(States.RETURN)
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
enum States { DEAD, IDLE, ATTACK, DEFEND, APPROACH, APPROACH_VOL, RETREAT, HIT, RETURN }

func initialize_states():
	state_functions[States.DEAD] = {
		"enter": dead_enter,
		"execute": dead_execute,
		"animation_finished": dead_finished,
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
	state_functions[States.APPROACH_VOL] = {
		"enter":  approach_vol_enter,
		"execute": approach_vol_execute,
		"exit":   approach_vol_exit
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
	state_functions[States.RETURN] = {
		"enter": return_enter,
		"execute": return_execute,
		"exit":   return_exit
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

# ----------  IDLE  ----------
func idle_enter() -> void:
	animator.play("idle")       # même anim pour vol ou non-vol
	velocity = Vector2.ZERO     # on efface tout


func idle_execute(delta: float) -> void:
	const WAVE_FREQ_HZ := 0.5      # vitesse : 2 oscillations / seconde
	const WAVE_AMP_PX  := 100.0     # amplitude : ±20 px/s sur la vitesse Y
	if vol:
		# IA VOLANTE : on donne simplement une vitesse sinusoïdale
		var t := Time.get_ticks_msec() * 0.001       # en secondes
		velocity.y = sin(t * WAVE_FREQ_HZ * TAU) * WAVE_AMP_PX
		velocity.x = 0
	else:
		# IA SOL : comportement existant (si tu en avais un)
		pass    # rien à faire ici : le reste du script gère la gravité


func idle_animation_looped() -> void:
	if target != null:
		wake()


func idle_exit() -> void:
	pass

#endregion

#region DEAD STATE
func dead_enter():
	velocity = Vector2.ZERO
	animator.play("dead")
	target = null
	vision.set_deferred("monitoring",   false)
	vision.set_deferred("monitorable", false)
	stimuli = false

func dead_execute(_delta):
	pass
const BLOOD_PARTICLE_SCENE := preload("uid://c283fbr082sr")

func dead_finished() -> void:
	if animator.animation == "dead":
		var p := BLOOD_PARTICLE_SCENE.instantiate()
		add_child(p)                     # enfant direct de ce node

		if p is Node2D:
			p.position = Vector2.ZERO   # position locale = origine du mob

		if p is GPUParticles2D:
			p.emitting = true           # au cas où la scène est sauvegardée off


func dead_exit():
	pass
	

#endregion

#region ATTACK STATE
func attack_enter():
	animator.play("attack")

func attack_execute(_delta):
	if animator.animation != "attack":
		var direction = (target.global_position - global_position).normalized()
		if direction.x < 0:
			point.scale.x = -1
		else:
			point.scale.x = 1

	
func attack_animation_finished():
	match animator.animation:
		"attack":
			print("attack_finie")
			wake()

func attack_exit():
	pass
#endregion

#region DEFEND STATE
func defend_enter():
	pass

func defend_execute(_delta):
	pass

func defend_animation_finished():
	pass

func defend_exit():
	pass

#endregion

#region APROACHE STATE
func approach_enter():
	if not vol:
		animator.play("walk")
	else:
		animator.play("idle")
		


func approach_execute(delta):
	# 1) Si on n’a plus de cible
	if target == null:
		print("→ approach exit : plus de target, dist = N/A")
		wake()
		return

	# 2) On calcule la distance réelle
	var tpos = target.global_position
	var dist = global_position.distance_to(tpos)

	# 3) Si on est dans la zone de confort
	if dist >= confort_zone_min and dist <= confort_zone_max:
		print("→ approach exit : dist=", dist,
			"  min=", confort_zone_min,
			"  max=", confort_zone_max)
		wake()
		return
	# 4) Sinon on continue d’approcher
	_move_towards(tpos, speed)

func approach_exit():
	velocity.x = 0
#endregion


func approach_vol_enter() -> void:
	animator.play("idle")    # ou "idle" si pas d’anim de vol


func approach_vol_execute(delta: float) -> void:
	# 1) Perte de cible ?
	if target == null:
		wake()
		return

	# 2) Distance au joueur
	var delta_vec := target.global_position - global_position
	var dist      := delta_vec.length()

	# 3) Zone de confort ⇒ on s’arrête
	if dist >= confort_zone_min and dist <= confort_zone_max:
		wake()
		return

	# 4) Déplacement pleine 2D (pas de gravité)
	var dir := delta_vec.normalized()
	velocity = dir * speed

	# 5) Flip horizontal du sprite
	point.scale.x = sign(dir.x)


func approach_vol_exit() -> void:
	velocity = Vector2.ZERO




# ─────────────────────────────────────────
#  RETURN  – sol + vol
# ─────────────────────────────────────────
func return_enter() -> void:
	animator.play("idle" if vol else "walk")   # "idle" = battement d’ailes

func return_execute(delta: float) -> void:
	# 1) Plus de position cible ? → on dort
	if return_position == null:
		wake()
		return

	# 2) Arrivé près du point d’origine ?
	var dist = global_position.distance_to(return_position)
	if dist <= 50.0:          # tolérance
		return_position = null
		wake()
		return

	# 3) Déplacement
	if vol:
		# --- IA volante : pleine 2D ---------------------------------
		var dir = (return_position - global_position).normalized()
		velocity        = dir * speed           # X et Y
		point.scale.x   = sign(dir.x)           # flip visuel
	else:
		# --- IA au sol : déplacement horizontal + gravité ----------
		_move_towards(return_position, speed)
		if not is_on_floor():
			velocity.y += gravity * delta

func return_exit() -> void:
	velocity.x = 0
	if vol:
		velocity.y = 0        # on stoppe aussi la composante verticale



#region RETREAT STATE

# En haut du script
var retreat_timer: SceneTreeTimer = null

func retreat_enter() -> void:
	if not vol:
		animator.play("walk_back")
	else:
		animator.play("idle")
	animator.set_speed_scale(-1.0)
	# Crée un timer de durée aléatoire entre 1 et 3 secondes
	var duration = randf_range(0.3, 1.0)
	retreat_timer = get_tree().create_timer(duration)
	retreat_timer.connect("timeout", Callable(self, "_on_retreat_timer_timeout"))
	print("▶ RETREAT: timer démarré pour %s secondes" % duration)

func retreat_execute(_delta: float) -> void:
	if target != null:
		var dir := (global_position - target.global_position).normalized()

		if vol:
			# ─── BIAIS VERTICAL ───
			# on soulève légèrement : y négatif = monter
			dir.y -= 0.4                 # ← facteur à ajuster (0 = neutre)
			dir = dir.normalized()       # on renormalise après le biais
			velocity = dir * speed
		else:
			# recule au sol uniquement
			velocity.x = dir.x * speed
			velocity.y = 0

		point.scale.x = 1 if dir.x < 0 else -1
	else:
		wake()

func _on_retreat_timer_timeout() -> void:
	# Une fois le timer arrivé à zéro, on « réveille » la machine d’états
	print("▶ RETREAT: timer terminé → wake()")
	wake()

func retreat_exit() -> void:
	velocity.x = 0
	animator.set_speed_scale(1.0)
	# Nettoyage éventuel
	if retreat_timer and retreat_timer.timeout.is_connected(_on_retreat_timer_timeout):
		retreat_timer.timeout.disconnect(_on_retreat_timer_timeout)

	retreat_timer = null

#endregion

#region HIT STATE


# --- Réglages HIT (en haut du script) ---
@export var HIT_STUN_TIME: float = 0.25    # durée du hitstun (en s)
@export var HIT_KNOCK_X:  float = 500.0    # force horizontale initiale
@export var HIT_KNOCK_Y:  float = -180.0   # rebond vertical initial
@export var HIT_X_DAMP:   float = 8.0     # amortissement horizontal (plus grand = s’arrête plus vite)

var _hit_elapsed := 0.0

func hit_enter() -> void:
	# 1) annule toute vélocité résiduelle
	velocity.x = 0.0
	velocity.y = 0.0

	# 2) anim
	animator.play("hit")
	_hit_elapsed = 0.0

	# 3) direction du knockback
	var dir := 0
	if position_x_player != null:
		# si on est à droite de l’attaquant → on part à droite, sinon à gauche
		dir = 1 if (global_position.x - position_x_player) > 0 else -1
	else:
		# fallback : opposé au regard
		dir = -1 if point.scale.x > 0 else 1

	velocity.x = dir * HIT_KNOCK_X
	velocity.y = HIT_KNOCK_Y

	# reset du pointeur
	position_x_player = null

func hit_execute(delta: float) -> void:
	_hit_elapsed += delta

	# gravité + amortissement horizontal
	velocity.y += gravity * delta
	velocity.x = lerp(velocity.x, 0.0, clamp(HIT_X_DAMP * delta, 0.0, 1.0))

	# sortie APRÈS un temps fixe, sol ou pas → on délègue à wake()
	if _hit_elapsed >= HIT_STUN_TIME:
		wake()

func hit_exit() -> void:
	velocity = Vector2.ZERO

#endregion 
