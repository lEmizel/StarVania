extends CharacterBody2D

enum States { IDLE, RUN, CHUTE, JUMP, WALL_GRIFFE, WALL_JUMP, CLIMB, ROLL, CHUTE_GRIFFE, GRAB, ATTACK_LIGHT_1, ATTACK_LIGHT_2, ATTACK_LIGHT_3, ATTACK_AIR, ATTACK_LOURDE }
@onready var wall_right: RayCast2D = $POINT/wall_right
@onready var wall_left: RayCast2D = $POINT/wall_left
@onready var climbcast_up: RayCast2D = $POINT/climbcast_up
@onready var climbcast_down: RayCast2D = $POINT/climbcast_down
@onready var climbcast_left: RayCast2D = $POINT/climbcast_left
@onready var climbcast_right: RayCast2D = $POINT/climbcast_right
@onready var grab: RayCast2D = $POINT/GRAB
@onready var ancre_grab: Node2D = $POINT/ANCRE_GRAB
@onready var slash_attack: AnimatedSprite2D = $POINT/slash_attack

@onready var ANCRE_SOL_BACK: Node2D = $POINT/ANCRE_SOL_BACK
@onready var ANCRE_SOL: Node2D = $POINT/ANCRE_SOL
@onready var ANCRE_WALL: Node2D = $POINT/ANCRE_WALL

@onready var point: Node2D = $POINT # le node 2d qui sert a flip le personnage
@onready var animator = $POINT/animator
var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")
var current_state : States = States.IDLE
var previous_state : States = States.IDLE
var state_functions: Dictionary = {}

var SPEED = 600
var last_direction := 1  # 1 = droite, -1 = gauche
var no_WJ = false
const CLIMB_SPEED := 200.0
const ROLL_SPEED := 700.0


var grab_target_position: Vector2 = Vector2.ZERO  # à déclarer en haut
var current_grab_area: Area2D = null

const FOOTSTEP_SCENE = preload("uid://bc2iigjdyudgm")  # ou un res://path
const CHUTE_SCENE = preload("uid://bfwic6xtfgc4p")  # ou un res://path
const WALL_JUMP_SCENE = preload("uid://c5a6or75xrx3o")  # ou un res://path

func _ready() -> void:
	animator.connect("animation_finished", Callable(self, "_on_animation_finished"))
	set_floor_max_angle(deg_to_rad(85))   # 60° → radians
	set_floor_snap_length(6.0)
	print(Player.hp,"hp")
	initialize_states()
	change_state(States.IDLE)


func _physics_process(delta: float) -> void:

	state_functions[current_state]["execute"].call(delta) # 2. logique d’état (met à jour velocity / anim)
	move_and_slide()                                     # 3. déplace le corps

### GESTION DES INPUTS ###
func _input(event):
	if state_functions[current_state].has("input"):
		state_functions[current_state]["input"].call()
		
# 2) Dispatcher central (sans argument !)
func _on_animation_finished() -> void:
	var funcs = state_functions[current_state]
	if funcs.has("animation_finished"):
		# On appelle le callback d'état *sans* argument
		funcs["animation_finished"].call()
# ---------------------------------------------------------
#  UTILITAIRE COMMUN 
# ---------------------------------------------------------



func _is_valid_press(action_name: String) -> bool:
	# Input.is_action_just_pressed gère déjà pressed+no echo
	return Input.is_action_just_pressed(action_name)

# Retourne vrai si le RayCast2D touche un StaticBody2D/Area2D du groupe donné

func instantiate_scene(scene_ref, parent_node: Node = null) -> Node:
	var packed: PackedScene
	if scene_ref is PackedScene:
		packed = scene_ref
	elif scene_ref is String:
		packed = load(scene_ref)
	else:
		push_error("instantiate_scene: scene_ref doit être PackedScene ou String")
		return null

	var instance = packed.instantiate()
	# Par défaut on ajoute sous la scène courante, sinon sous parent_node
	var target_parent: Node = parent_node if parent_node != null else get_tree().get_current_scene()
	target_parent.add_child(instance)
	return instance

func _flip_facing_on_wall() -> void: #flip obligatoire sans input
	point.scale.x *= -1                    # inverse immédiatement l’échelle X
	last_direction = -last_direction       # garde cette valeur pour les autres états i


func _flip_from_input() -> void:  #flip avec input
	var dir := Input.get_axis("left_move", "right_move")
	if dir != 0:
		last_direction = sign(dir)
		point.scale.x  = last_direction

# ----------- Initialisation des états -------------------
func initialize_states() -> void:
	state_functions[States.IDLE] = {
		"enter": idle_enter,
		"execute": idle_execute,
		"input": idle_input,
		"exit": idle_exit
	}
	state_functions[States.RUN] = {
		"enter": run_enter,
		"execute": run_execute,
		"input": run_input,
		"exit": run_exit
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
		"exit": chute_exit
	}
	state_functions[States.WALL_GRIFFE] = {
		"enter": wall_griffe_enter,
		"execute": wall_griffe_execute,
		"exit": wall_griffe_exit
	}
	state_functions[States.WALL_JUMP] = {
		"enter": wall_jump_enter,
		"execute": wall_jump_execute,
		"input": wall_jump_input,
		"exit": wall_jump_exit
	}
	state_functions[States.CLIMB] = {
		"enter": climb_enter,
		"execute": climb_execute,
		"input": climb_input,
		"exit": climb_exit
	}
	state_functions[States.ROLL] = {
		"enter": roll_enter,
		"execute": roll_execute,
		"input":  roll_input,
		"exit":   roll_exit,
		"animation_finished": _on_roll_animation_finished
	}
	state_functions[States.CHUTE_GRIFFE] = {
		"enter": chute_griffe_enter,
		"execute": chute_griffe_execute,
		"input": chute_griffe_input,
		"exit": chute_griffe_exit
	}
	state_functions[States.GRAB] = {
		"enter": grab_enter,
		"execute": grab_execute,
		"input": grab_input,
		"exit": grab_exit
	}
	state_functions[States.ATTACK_LIGHT_1] = {
		"enter": attack_light_1_enter,
		"execute": attack_light_1_execute,
		"input": attack_light_1_input,
		"exit": attack_light_1_exit,
		"animation_finished": attack_light_1_animation_finished
	}
	state_functions[States.ATTACK_LIGHT_2] = {
		"enter": attack_light_2_enter,
		"execute": attack_light_2_execute,
		"input": attack_light_2_input,
		"exit": attack_light_2_exit,
		"animation_finished": attack_light_2_animation_finished
	}
	state_functions[States.ATTACK_LIGHT_3] = {
		"enter": attack_light_3_enter,
		"execute": attack_light_3_execute,
		"input": attack_light_3_input,
		"exit": attack_light_3_exit,
		"animation_finished": attack_light_3_animation_finished
	}
	state_functions[States.ATTACK_AIR] = {
		"enter": attack_air_enter,
		"execute": attack_air_execute,
		"input": attack_air_input,
		"exit": attack_air_exit,
		"animation_finished": attack_air_animation_finished
	}
	state_functions[States.ATTACK_LOURDE] = {
		"enter": attack_lourde_enter,
		"execute": attack_lourde_execute,
		"input": attack_lourde_input,
		"exit": attack_lourde_exit,
		"animation_finished": attack_lourde_animation_finished
	}

# ----------- Gestion du changement d’état ---------------
func change_state(new_state: States) -> void:
	state_functions[current_state]["exit"].call()
	previous_state = current_state
	current_state  = new_state
	state_functions[current_state]["enter"].call()

# =====================  IDLE  ===========================
#region IDLE

func idle_enter() -> void:
	animator.play("idle")
	velocity = Vector2.ZERO


# IDLE ----------------------------------------------------
func idle_execute(delta: float) -> void:
	velocity.y += gravity * delta
	if not is_on_floor():
		change_state(States.CHUTE)


func idle_input() -> void:
	if Input.is_action_pressed("right_move") or Input.is_action_pressed("left_move"):
		change_state(States.RUN)
	elif Input.is_action_just_pressed("jump"):
		change_state(States.JUMP)
		return
	elif Input.is_action_just_pressed("light_attack"):
		change_state(States.ATTACK_LIGHT_1)
		return
	elif Input.is_action_just_pressed("lourde_attack"):
		change_state(States.ATTACK_LOURDE)
		return

func idle_exit() -> void:
	pass
#endregion

# =====================  WALK  ===========================

var run_frame_counter : int = 0
var air_ground_instance   # on remplit à la première instanciation



func run_enter() -> void:
	animator.play("run")
	print("jerun")




func run_execute(delta: float) -> void:
	run_frame_counter += 1
	_flip_from_input()
	# ─── 1) Gravité verticale ───
	velocity.y += gravity * delta

	# ─── 2) Si on quitte le sol → CHUTE puis sortie immédiate ───
	if not is_on_floor():
		change_state(States.CHUTE)
		return

	# ─── Lecture de l’input gauche/droite ───
	var direction := Input.get_axis("left_move", "right_move")

	# ─── 3) Si aucune direction → IDLE puis sortie immédiate ───
	if direction == 0:
		change_state(States.IDLE)
		return

	# ─── 4) On est au sol ET on veut courir ───

	# Footstep une frame sur deux (ou 10e, 20e, etc.)
	if animator.animation == "run" and run_frame_counter % 10 == 0:
		var foot = instantiate_scene(FOOTSTEP_SCENE)
		foot.global_position = ANCRE_SOL_BACK.global_position
		foot.scale.x        *= point.scale.x   # flip relatif à ton perso
		foot.play("run_to_ground")
	

	# Lerp sur la vitesse horizontale
	var target_speed: float = float(direction) * SPEED
	velocity.x = lerp(velocity.x, target_speed, 0.15)
		
	# Si aucune direction → retour à idle



func run_input() -> void:
	if Input.is_action_just_pressed("jump"):
		change_state(States.JUMP)
	elif Input.is_action_just_pressed("esquive"):
		change_state(States.ROLL)
	elif Input.is_action_just_pressed("light_attack"):
		change_state(States.ATTACK_LIGHT_1)
	elif Input.is_action_just_pressed("lourde_attack"):
		change_state(States.ATTACK_LOURDE)

func run_exit() -> void:
	velocity = Vector2.ZERO
	

#region JUMP



const JUMP_VELOCITY = -550.0
const AIR_CONTROL = 0.2  # Ce facteur détermine à quel point le joueur peut contrôler le personnage en l'air
const DECELERATION_RATE = 0.95  # Plus cette valeur est proche de 1, plus la décélération est lente

func jump_enter():
	animator.play("jump")
	velocity.y = JUMP_VELOCITY


func jump_execute(delta):
	var direction = Input.get_axis("left_move", "right_move")
	var SPEED = 400
	#var collider_griffe = climbcast_up.get_collider()
	#var collider_wall_griffe = climbcast_right.get_collider()
	_flip_from_input()
		
	velocity.y += gravity * delta
	
	if direction != 0:
		velocity.x = lerp(velocity.x, direction * SPEED, AIR_CONTROL)
	else:# Si aucune direction n'est pressée, on décélère progressivement vers 0
		velocity.x = lerp(velocity.x, 0.0, DECELERATION_RATE * delta)
		
	if climbcast_up.is_colliding():
		var collider_c = climbcast_up.get_collider()
		if collider_c is Area2D and collider_c.is_in_group("CHUTE") \
			and Input.is_action_just_pressed("griffe"):
				change_state(States.CHUTE_GRIFFE)
				return

	if grab.is_colliding():
		var collider_c = grab.get_collider()
		if collider_c is Area2D and collider_c.is_in_group("GRAB") and previous_state != States.GRAB:
			print("j'ai trouvé le GRAB")
			current_grab_area = collider_c
			change_state(States.GRAB)
			return


	var hit_right = climbcast_right.is_colliding() \
		and climbcast_right.get_collider() is Area2D \
		and climbcast_right.get_collider().is_in_group("CLIMB")
	var hit_left  = climbcast_left.is_colliding() \
		and climbcast_left.get_collider()  is Area2D \
		and climbcast_left.get_collider().is_in_group("CLIMB")

	if hit_right and hit_left and Input.is_action_just_pressed("griffe"):
		print("j'ai trouvé le CLIMB sur gauche et droite")
		change_state(States.CLIMB)
		return

	if climbcast_right.is_colliding():
		var collider = climbcast_right.get_collider()
		if collider is Area2D and collider.is_in_group("GRIFFE"):
			# On exige maintenant une vélocité horizontale non nulle
			if abs(velocity.x) > 0 and Input.is_action_just_pressed("griffe"):
				print("j'ai trouvé la GRIFFE")
				change_state(States.WALL_GRIFFE)
				return

	if velocity.y > 0:
		change_state(States.CHUTE)

func jump_exit():
	velocity.y = 0
#endregion

func jump_input() -> void:
	if Input.is_action_just_pressed("light_attack"):
		change_state(States.ATTACK_AIR)
	#if not Input.is_action_pressed("jump"):
		#change_state(States.CHUTE)


func chute_enter() -> void:
	print("enter_CHUTE")
	animator.play("chute")
	# Tu peux mettre une future animation ici genre animator.play("fall")
	pass




func chute_execute(delta: float) -> void:
	var direction := Input.get_axis("left_move", "right_move")
	var SPEED := 400

	# Flip visuel selon la direction
	# 1) Si on veut attaquer en l'air → on y va et on sort
	if Input.is_action_just_pressed("light_attack"):
		print("j'attaque en l'air")
		change_state(States.ATTACK_AIR)
		return

	if direction != 0 and previous_state != States.WALL_JUMP:
		last_direction = sign(direction)
		point.scale.x = last_direction
		
	# Gravité (toujours active)
	velocity.y += gravity * delta
	# ─── Contrôle aérien horizontal ───
	if direction != 0:
		velocity.x = lerp(velocity.x, direction * SPEED, AIR_CONTROL)
	else:
		velocity.x = lerp(velocity.x, 0.0, DECELERATION_RATE * delta)
# else : keep velocity.x as-is, and don’t change flip

	# Détection de wall-jump / griffe inchangée…

	# --- NOUVEAU : CHUTE_GRIFFE depuis CLIMB_RIGHT + bouton GRIFFE ---
	if climbcast_up.is_colliding():
		var collider_c = climbcast_up.get_collider()
		if collider_c is Area2D and collider_c.is_in_group("CHUTE") \
			and Input.is_action_just_pressed("griffe"):
				change_state(States.CHUTE_GRIFFE)
				return


	if grab.is_colliding():
		var collider_c = grab.get_collider()
		if collider_c is Area2D and collider_c.is_in_group("GRAB"):
			print("j'ai trouvé le GRAB")
			current_grab_area = collider_c
			change_state(States.GRAB)
			return

	if wall_right.is_colliding():
		var collider := wall_right.get_collider()
		if collider is StaticBody2D and collider.is_in_group("wall_jump"):
			_flip_facing_on_wall()         # <-- nouveau
			change_state(States.WALL_JUMP)
			return



	var hit_right = climbcast_right.is_colliding() \
		and climbcast_right.get_collider() is Area2D \
		and climbcast_right.get_collider().is_in_group("CLIMB")
	var hit_left  = climbcast_left.is_colliding() \
		and climbcast_left.get_collider()  is Area2D \
		and climbcast_left.get_collider().is_in_group("CLIMB")

	if hit_right and hit_left and Input.is_action_just_pressed("griffe"):
		print("j'ai trouvé le CLIMB sur gauche et droite")
		change_state(States.CLIMB)
		return


	if climbcast_right.is_colliding():
		var collider = climbcast_right.get_collider()
		if collider is Area2D and collider.is_in_group("GRIFFE"):
				# On exige maintenant une vélocité horizontale non nulle
			if abs(velocity.x) > 0 and Input.is_action_just_pressed("griffe"):
				print("j'ai trouvé la GRIFFE")
				change_state(States.WALL_GRIFFE)
				return

		# Détection de l'atterrissage
	if is_on_floor():
	# ① On instancie l’effet d’impact au sol
		var land_fx = instantiate_scene(CHUTE_SCENE)
		land_fx.global_position = ANCRE_SOL.global_position
	# Si c’est une AnimatedSprite2D, tu peux lancer l’anim par défaut :
		if land_fx is AnimatedSprite2D:
			land_fx.play()

	# ② Puis on change d’état
		if Input.is_action_pressed("right_move") or Input.is_action_pressed("left_move"):
			change_state(States.RUN)
		else:
			change_state(States.IDLE)


func chute_input() -> void:
	if Input.is_action_just_pressed("light_attack"):
		print("jattaque en l'aire ")
		change_state(States.ATTACK_AIR)


func chute_exit() -> void:
	pass



#region WALL_GRIFFE
func wall_griffe_enter():
	animator.play("wall_griffe")
	velocity.y = 0
	
	if velocity.x > 0:
		last_direction = 1
		point.scale.x = last_direction
		
	elif velocity.x < 0:
		last_direction = -1
		point.scale.x = last_direction

	if last_direction != 0 and velocity.x != 0:
		if last_direction == 1:
			velocity.x = 500
		if last_direction == -1:
			velocity.x = -500

func wall_griffe_execute(delta):
	if climbcast_right.is_colliding():
		var collider_griffe = climbcast_right.get_collider()
		if collider_griffe is Area2D and collider_griffe.is_in_group("GRIFFE"):
			return  # Tout va bien, on reste agrippé
	# Si on arrive ici → plus en contact ou ce n’est pas une griffe
	change_state(States.CHUTE)

func wall_griffe_input(event: InputEvent):
	if Input.is_action_just_pressed("jump"):
		change_state(States.JUMP)

func wall_griffe_animation_finished():
	change_state(States.CHUTE)

func wall_griffe_exit():
	pass
#endregion




#region wallm jump
func wall_jump_enter():
	velocity = Vector2.ZERO
	animator.play("wall_jump")
	print("enter_wall_jump | last_direction:", last_direction, " | point.scale.x:", point.scale.x)



func wall_jump_execute(delta):
	# Applique la gravité uniquement si on est en train de sauter
	if animator.animation == "jump":
		velocity.y += gravity * delta

		# Si on redescend, on passe à l'état CHUTE
		if velocity.y > 0:
			change_state(States.CHUTE)
	else:
		# Vérifie si le mur n'est plus détecté
		# Si le RayCast ne touche plus rien, on chute
		if not (wall_left.is_colliding() and wall_left.get_collider() is StaticBody2D and wall_left.get_collider().is_in_group("wall_jump")):
			if not (wall_right.is_colliding() and wall_right.get_collider() is StaticBody2D and wall_right.get_collider().is_in_group("wall_jump")):
				change_state(States.CHUTE)


		# Glissement contrôlé vers le bas
		var glide_speed = 300.0  # Vitesse terminale du glissement
		velocity.y = lerp(velocity.y, glide_speed, 0.05)

		# Fin du wall jump si on touche le sol
		if is_on_floor():
			change_state(States.IDLE)


func wall_jump_input() -> void:
	const WALL_YJUMP := -500
	const WALL_XJUMP := 290

	if Input.is_action_just_pressed("jump") and animator.animation != "jump":
		var land_fx = instantiate_scene(WALL_JUMP_SCENE)
		land_fx.global_position = ANCRE_WALL.global_position
		# ─── Flip relatif à l'orientation du perso ───
		land_fx.scale.x *= point.scale.x
		# Si c’est une AnimatedSprite2D, tu peux lancer l’anim par défaut :
		if land_fx is AnimatedSprite2D:
			land_fx.play()
		animator.play("jump")
		velocity.y = WALL_YJUMP
		velocity.x = WALL_XJUMP if last_direction == 1 else -WALL_XJUMP
	if Input.is_action_just_pressed("esquive"):
		change_state(States.CHUTE)


func wall_jump_animation_finished():
	pass

func wall_jump_exit():
	pass
#endregion



func climb_enter() -> void:
	velocity = Vector2.ZERO              # stoppe tout mouvement
	animator.play("climbidle")           # anim de base (placeholder)

func climb_execute(delta: float) -> void:
	# 1) Lecture du stick
	var dir := Input.get_vector("left_move", "right_move", "up_move", "down_move")

	const DEAD_ZONE := 0.3
	if abs(dir.x) < DEAD_ZONE:
		dir.x = 0

	# 2) Vérif “avant”
	var can_climb_forward = climbcast_right.is_colliding() \
		and climbcast_right.get_collider() is Area2D \
		and climbcast_right.get_collider().is_in_group("CLIMB")

	# 3) Si on perd la prise → anim CLIMBQUIT (une fois)
	if not can_climb_forward and animator.animation != "climbquit":
		animator.play("climbquit")

	# 4) Si on retrouve la prise après un quit → anim CLIMBIDLE
	if can_climb_forward and animator.animation == "climbquit":
		animator.play("climbidle")

	# 5) Blocage inputs quand la prise est perdue
	if not can_climb_forward:
		if sign(point.scale.x) > 0:
			dir.x = min(dir.x, 0)
		else:
			dir.x = max(dir.x, 0)
		dir.y = 0

	# ─────────────── ANIMATIONS DE MOUVEMENT ───────────────
	# S'exécute seulement si on n'est pas en climbquit
	if animator.animation != "climbquit":
		if dir == Vector2.ZERO:
			animator.play("climbidle")
		else:
	# on regarde quelle composante domine
			if abs(dir.x) > abs(dir.y):
				animator.play("climb_move_up")
			elif dir.y < 0:
				animator.play("climb_move_up")
			else:
				animator.play("climb_move_down")
	# ────────────────────────────────────────────────────────

	# 6) Application de la vitesse
	velocity = dir * CLIMB_SPEED

	# 7) Flip visuel si on bouge horizontalement
	_flip_from_input()

	# 8) Sorties d’état jump/esquive
	if Input.is_action_just_pressed("esquive"):
		change_state(States.CHUTE)
		return
	elif Input.is_action_just_pressed("jump"):
		change_state(States.JUMP)
		return

	# 9) Sortie chute si ni LEFT ni RIGHT détectent la zone
	var hit_left = climbcast_left.is_colliding() \
		and climbcast_left.get_collider() is Area2D \
		and climbcast_left.get_collider().is_in_group("CLIMB")
	var hit_right = climbcast_right.is_colliding() \
		and climbcast_right.get_collider() is Area2D \
		and climbcast_right.get_collider().is_in_group("CLIMB")
	if not (hit_left or hit_right):
		change_state(States.CHUTE)
		return

	# 10) Si UP ne détecte plus la zone → JUMP
	var hit_up = climbcast_up.is_colliding() \
		and climbcast_up.get_collider() is Area2D \
		and climbcast_up.get_collider().is_in_group("CLIMB")
	if not hit_up:
		change_state(States.JUMP)
		return

func climb_input() -> void:
	pass

func climb_exit() -> void:
	pass



func roll_enter() -> void:
	# 1) On récupère la direction du stick
	var direction := Input.get_axis("left_move", "right_move")
	# 2) Si on a un mouvement horizontal, on déclenche la roulade
	if direction != 0:
		last_direction = sign(direction)
		point.scale.x  = last_direction
		velocity.x     = direction * ROLL_SPEED

		# On se connecte au signal pour savoir quand l’anim se termine

		animator.play("roll")
	#else:
		# Pas de direction → on retourne directement à BACK_ROLL
		#change_state(States.BACK_ROLL)	

func roll_execute(delta: float) -> void:
	# On applique la gravité pendant la roll
	velocity.y += gravity * delta

func roll_input() -> void:
	# Pas d'input additionnel pendant la roll
	pass

func roll_exit() -> void:
	pass
# ------------------------------------------------------------------
# CALLBACK : fin de l'animation
func _on_roll_animation_finished() -> void:
	print("je joue cette partie de code ")
	# Selon l’input au moment de la fin, on change d'état
	var horiz = Input.get_action_strength("right_move") - Input.get_action_strength("left_move")
	if horiz != 0:
		change_state(States.RUN)
	elif Input.is_action_just_pressed("jump"):
		change_state(States.JUMP)
	elif not is_on_floor():
		change_state(States.CHUTE)
	else:
		change_state(States.IDLE)





func chute_griffe_enter() -> void:
	print("jegriffe")
	animator.play("chute_griffe")
	velocity.y = 250.0

func chute_griffe_execute(delta: float) -> void:
	print("jegriffe")
	# Valeurs locales
	var glide_speed_y := 250.0
	var glide_speed_x := 150.0
	var decel_rate   := 0.50

	# Mise à jour du raycast Up
	climbcast_up.force_raycast_update()
	var collider = climbcast_up.get_collider()

	# Mouvement horizontal contrôlé
	var direction := Input.get_axis("left_move", "right_move")
	if direction != 0:
		velocity.x = direction * glide_speed_x
	else:
		velocity.x = lerp(velocity.x, 0.0, decel_rate * delta)

	# Descente constante
	velocity.y = glide_speed_y

	# Sortie si on perd la prise ou qu’on lâche la touche
	if not (collider and collider.is_in_group("CHUTE") and Input.is_action_pressed("griffe")):
		change_state(States.CHUTE)

func chute_griffe_input() -> void:
	pass

func chute_griffe_exit() -> void:
	pass




func grab_enter() -> void:
	velocity = Vector2.ZERO

	if current_grab_area:
		# Calcul de la position cible en tenant compte de l'ancre
		var grab_pos = current_grab_area.global_position
		var offset = ancre_grab.global_position - global_position
		var target_pos = grab_pos - offset

		# Placement initial du joueur (rapide mais non téléporté — cf. execute)
		global_position = target_pos

	animator.play("suspendu")

func grab_execute(delta: float) -> void:
	if current_grab_area:
		var grab_pos = current_grab_area.global_position
		var offset = ancre_grab.global_position - global_position
		var target_pos = grab_pos - offset

		# Interpolation douce vers la position cible
		var lerp_speed = 10.0  # Plus c’est élevé, plus c’est rapide
		global_position = global_position.move_toward(target_pos, lerp_speed * delta)
func grab_input() -> void:
	if Input.is_action_just_pressed("jump"):
		change_state(States.JUMP)
	elif Input.is_action_just_pressed("esquive"):
		change_state(States.CHUTE)

func grab_exit() -> void:
	pass

var combo = false

func attack_light_1_enter() -> void:
	slash_attack.position = Vector2( 57, -92)
	# 1) On lit l’input horizontal une fois
	_flip_from_input()
	# 2) Reset combo et lancement de l’anim
	combo = false
	animator.play("attack")

func attack_light_1_execute(delta: float) -> void:
	pass
		

func attack_light_1_input() -> void:
	if animator.animation == "attack" and Input.is_action_just_pressed("light_attack"):
		print("combo", combo)
		combo = true
	if animator.animation == "attack_r" and Input.is_action_just_pressed("light_attack"):
		change_state(States.ATTACK_LIGHT_2)
		return
	
func attack_light_1_animation_finished() -> void:
	match animator.animation:
		"attack":
			if combo == true:
				change_state(States.ATTACK_LIGHT_2)
				return
			else:
				animator.play("attack_r")
		"attack_r":
			combo = false
			if Input.is_action_pressed("right_move") or Input.is_action_pressed("left_move"):
				change_state(States.RUN)
				return
			else:
				change_state(States.IDLE)


func attack_light_1_exit() -> void:
	combo = false
	velocity.x = 0



func attack_light_2_enter() -> void:
	# 1) On lit l’input horizontal une fois
	_flip_from_input()
	combo = false
	print("attack2")
	animator.play("attack_02")

func attack_light_2_execute(delta: float) -> void:
	pass

func attack_light_2_input() -> void:
	if Input.is_action_just_pressed("light_attack"):
		print("combo", combo)
		combo = true
	if animator.animation == "attack_02_r" and Input.is_action_just_pressed("light_attack"):
		change_state(States.ATTACK_LIGHT_3)
		return
	
func attack_light_2_animation_finished() -> void:
	match animator.animation:
		"attack_02":
			if combo == true:
				change_state(States.ATTACK_LIGHT_3)
				return
			else:
				animator.play("attack_02_r")
		"attack_02_r":
			
			combo = false
			if Input.is_action_pressed("right_move") or Input.is_action_pressed("left_move"):
				change_state(States.RUN)
				return
			else:
				change_state(States.IDLE)

func attack_light_2_exit() -> void:
	combo = false

	velocity.x = 0




func attack_light_3_enter() -> void:
	# 1) On lit l’input horizontal une fois
	_flip_from_input()
	combo = false
	print("attack3")
	animator.play("attack_03")

func attack_light_3_execute(delta: float) -> void:
	pass
func attack_light_3_input() -> void:
	pass
	
	
func attack_light_3_animation_finished() -> void:
	match animator.animation:
		"attack_03":
			animator.play("attack_03_r")
		"attack_03_r":
			if Input.is_action_pressed("right_move") or Input.is_action_pressed("left_move"):
				change_state(States.RUN)
				return
			else:
				change_state(States.IDLE)
				return

func attack_light_3_exit() -> void:
	velocity.x = 0
	combo = false



func attack_lourde_enter() -> void:
	slash_attack.position = Vector2(-32, -92)
	animator.play("attack_lourde")

func attack_lourde_execute(delta: float) -> void:
	pass
func attack_lourde_input() -> void:
	pass
	
	
func attack_lourde_animation_finished() -> void:
	match animator.animation:
		"attack_lourde":
			if Input.is_action_pressed("right_move") or Input.is_action_pressed("left_move"):
				change_state(States.RUN)
			else:
				change_state(States.IDLE)

func attack_lourde_exit() -> void:
	velocity.x = 0

	
	
	
	
func attack_air_enter() -> void:
	animator.play("attack_air")

func attack_air_execute(delta: float) -> void:
	velocity.y += gravity * delta
	
	if is_on_floor():
# atterrissage
		change_state(States.IDLE)
	
func attack_air_input() -> void:
	pass
	

func attack_air_animation_finished() -> void:
	match animator.animation:
		"attack_air":
			change_state(States.CHUTE)

func attack_air_exit() -> void:
	velocity.x = 0
