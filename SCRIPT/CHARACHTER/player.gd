extends CharacterBody2D


enum States { IDLE, RUN, CHUTE, JUMP, WALL_GRIFFE, WALL_JUMP, CLIMB, ROLL, CHUTE_GRIFFE, GRAB, ATTACK_LIGHT_1, ATTACK_LIGHT_2, ATTACK_LIGHT_3, ATTACK_AIR, ATTACK_LOURDE, DEAD, HIT, HEAL }
const STATE_STAMINA_COSTS := {
	States.ROLL:            10,
	States.ATTACK_LIGHT_1:  22,
	States.ATTACK_LIGHT_2:  22,
	States.ATTACK_LIGHT_3:  22,
	States.ATTACK_AIR:      24,
	States.ATTACK_LOURDE:   37,
}

func _get_state_cost(s: States) -> int:
	return int(STATE_STAMINA_COSTS.get(s, 0))



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
var position_x_enemi = null

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
	set_floor_max_angle(deg_to_rad(60))   # 60° → radians
	set_floor_snap_length(6.0)
	print(Player.hp,"hp")
	initialize_states()
	change_state(States.IDLE)


func _physics_process(delta: float) -> void:
	state_functions[current_state]["execute"].call(delta)  # 1) MAJ de velocity
	move_and_slide()                                       # 2) déplacement réel
								   # 2. on bouge réellement
								 # 3. déplace le corps

### GESTION DES INPUTS ###
func _input(event):
	if state_functions[current_state].has("input"):
		state_functions[current_state]["input"].call(event)  # on transmet
		
# 2) Dispatcher central (sans argument !)
func _on_animation_finished() -> void:
	var funcs = state_functions[current_state]
	if funcs.has("animation_finished"):
		# On appelle le callback d'état *sans* argument
		funcs["animation_finished"].call()
# ---------------------------------------------------------
#  UTILITAIRE COMMUN 
# ---------------------------------------------------------



# ------------------------------------------
func apply_damage(amount: int, source_x) -> void:
	#if current_state == States.ROLL or current_state == States.DEAD:
	if current_state in [States.ROLL, States.DEAD]:
		return
	if current_state != States.HIT:
		print("j,ai pris les damage")
		Player.changement_de_vie(-amount)
		print("Player_vie", Player.hp)
		if Player.hp <= 0:
			print("ma vie est a zero ")
			change_state(States.DEAD)
			return
		# on stocke immédiatement la X de l’attaquant
		position_x_enemi = source_x
		change_state(States.HIT)
		#vie.emit_signal("health_request", -amount)
		#vie.apparition_temp()


func goto_state(s: States) -> void:
	# optional guard to avoid pointless transitions
	if current_state == s:
		return
	call_deferred("change_state", s)

func _raycast_hits_group(rc: RayCast2D, group_name: String, body_only := false) -> bool:
	var ignored: Array[RID] = []
	rc.clear_exceptions()

	while rc.is_colliding():
		var col := rc.get_collider()
		var ok := false
		if body_only:
			ok = col is PhysicsBody2D and col.is_in_group(group_name)
		else:
			ok = col is Area2D and col.is_in_group(group_name)

		if ok:
			for rid in ignored:
				rc.remove_exception_rid(rid)
			rc.force_raycast_update()
			return true

		# Ignorer cet objet (body, area ou tile)
		var rid := rc.get_collider_rid()
		rc.add_exception_rid(rid)
		ignored.append(rid)
		rc.force_raycast_update()

	# Rien trouvé : on nettoie quand même
	for rid in ignored:
		rc.remove_exception_rid(rid)
	rc.force_raycast_update()
	return false

func _is_valid_press(action_name: String) -> bool:
	# Input.is_action_just_pressed gère déjà pressed+no echo
	return Input.is_action_just_pressed(action_name)



func calcule_falling_damage() -> int:
	# -------- réglages --------
	const SAFE_HEIGHT: float     = 850.0   # px sans dégâts
	const DAMAGE_PER_STEP: int   = 6       # pts par tranche
	const STEP_PX: float         = 100.0    # taille tranche

	# -------- calcul --------
	var impact_point: float  = global_position.y
	var fall_distance: float = max(0.0, impact_point - FALL_POINT)

	if fall_distance <= SAFE_HEIGHT:
		print("Chute sans dégâts (", fall_distance, " px )")
		return 0

	var excess: float  = fall_distance - SAFE_HEIGHT
	var damage: int    = int(ceil(excess / STEP_PX)) * DAMAGE_PER_STEP
	apply_damage(damage, null)   # ← source_x « neutre »
	print("Dégâts de chute :", damage,
		" | hauteur totale :", fall_distance, " px",
		" | excès :", excess, " px")
	return damage
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
	state_functions[States.HEAL] = {
		"enter": heal_enter,
		"execute": heal_execute,
		"input": heal_input,
		"exit": heal_exit,
		"animation_finished": heal_finished
	}
	state_functions[States.HIT] = {
		"enter": hit_enter,
		"execute": hit_execute,
		"exit": hit_exit,
	}
	state_functions[States.DEAD] = {
		"enter": dead_enter,
		"execute": dead_execute,
		"input": dead_input,
		"exit": dead_exit,
	}

# ----------- Gestion du changement d’état ---------------

var _changing_now := false

func change_state(new_state: States) -> void:
	print("[", Engine.get_physics_frames(), "] ",
		"STATE: ", current_state, " -> ", new_state,
		" | on_floor=", is_on_floor(), " | vel=", velocity)

	# 0) bloque les ré-entrées et les no-op
	if _changing_now or new_state == current_state:
		return

	var cost := _get_state_cost(new_state)
	var skip_check := (new_state == States.ROLL)  # ROLL toujours autorisée
	var force_idle_on_fail := (
		current_state == States.ATTACK_LIGHT_1
		or current_state == States.ATTACK_LIGHT_2
		or current_state == States.ATTACK_LIGHT_3
	)

	# 1) besoin d'au moins 1 d'endu (sauf ROLL) pour les états qui coûtent > 0
	var requires_stamina := (cost > 0) and (not skip_check)
	if requires_stamina and Player.en < 1:
		# On force un retour IDLE pour casser une chaîne d'attaques
		if force_idle_on_fail and current_state != States.IDLE:
			_changing_now = true
			state_functions[current_state]["exit"].call()
			previous_state = current_state
			current_state  = States.IDLE
			state_functions[current_state]["enter"].call()
			_changing_now = false
		return

	# 2) débit d'endurance (on peut tomber à 0)
	if cost > 0:
		Player.changement_d_endurance(-cost)

	# 3) transition standard protégée
	_changing_now = true
	state_functions[current_state]["exit"].call()
	previous_state = current_state
	current_state  = new_state
	state_functions[current_state]["enter"].call()
	_changing_now = false

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


func idle_input(event: InputEvent) -> void:
	if Input.is_action_pressed("right_move") or Input.is_action_pressed("left_move"):
		change_state(States.RUN)
	elif Input.is_action_just_pressed("jump"):
		change_state(States.JUMP)
		return
	elif Input.is_action_just_pressed("heal"):
		change_state(States.HEAL)
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





func run_execute(delta: float) -> void:
	run_frame_counter += 1
	_flip_from_input()
	# ─── 1) Gravité verticale ───
	velocity.y += gravity * delta

	# ─── 2) Si on quitte le sol → CHUTE puis sortie immédiate ───
	if not is_on_floor():
		goto_state(States.CHUTE)
		return

	# ─── Lecture de l’input gauche/droite ───
	var direction := Input.get_axis("left_move", "right_move")

	# ─── 3) Si aucune direction → IDLE puis sortie immédiate ───
	if direction == 0:
		goto_state(States.IDLE)
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



func run_input(event: InputEvent) -> void:
	if Input.is_action_just_pressed("jump"):
		change_state(States.JUMP)
		return
	elif Input.is_action_just_pressed("heal"):
		change_state(States.HEAL)
		return
	elif Input.is_action_just_pressed("esquive"):
		change_state(States.ROLL)
		return
	elif Input.is_action_just_pressed("light_attack"):
		change_state(States.ATTACK_LIGHT_1)
		return
	elif Input.is_action_just_pressed("lourde_attack"):
		change_state(States.ATTACK_LOURDE)
		return

func run_exit() -> void:
	velocity = Vector2.ZERO
	

#region JUMP


# ---- Variable-height jump (tunable) ----
const MIN_JUMP_TIME   := 0.02   # secondes : hauteur minimale garantie
const MAX_JUMP_HOLD   := 0.22   # secondes : fenêtre où tenir "jump" allège la gravité
const GRAVITY_RISE    := 0.55   # gravité quand on MONTE et qu'on tient encore (allège)
const GRAVITY_CUTOFF  := 2.00   # gravité quand on MONTE et qu'on a relâché (écourte doucement)
const GRAVITY_FALL    := 1.35   # gravité quand on TOMBE (descente plus nette)
var _jump_timer := 0.0          # temps écoulé depuis le début du saut

const JUMP_VELOCITY = -700.0
const AIR_CONTROL = 0.2  # Ce facteur détermine à quel point le joueur peut contrôler le personnage en l'air
const DECELERATION_RATE = 0.95  # Plus cette valeur est proche de 1, plus la décélération est lente

func jump_enter():
	animator.play("jump")
	velocity.y = JUMP_VELOCITY
	_jump_timer = 0.0



func jump_execute(delta):
	_jump_timer += delta

	# Contrôle horizontal en l'air (inchangé)
	var direction = Input.get_axis("left_move", "right_move")
	var SPEED = 400
	_flip_from_input()
	if direction != 0:
		velocity.x = lerp(velocity.x, direction * SPEED, AIR_CONTROL)
	else:
		velocity.x = lerp(velocity.x, 0.0, DECELERATION_RATE * delta)

	# Heurt de plafond : stoppe net la montée
	if is_on_ceiling():
		velocity.y = 0.0

	# ---- Gravité variable pendant la montée / descente ----
	var g_mul := 1.0
	if velocity.y < 0.0:
		# On est en montée
		var holding := Input.is_action_pressed("jump")
		var force_min := _jump_timer < MIN_JUMP_TIME
		var within_hold := _jump_timer < MAX_JUMP_HOLD

		if force_min or (holding and within_hold):
			g_mul = GRAVITY_RISE     # on allège pour monter plus haut
		else:
			g_mul = GRAVITY_CUTOFF   # on alourdit pour écourter le saut
	else:
		# On est en descente
		g_mul = GRAVITY_FALL

	# --- 2) GRIFFE (zone collée au mur) ---------------------------
	if _raycast_hits_group(climbcast_right, "GRIFFE") \
		and abs(velocity.x) > 0 \
		and Input.is_action_just_pressed("griffe"):
		print("GRIFFE trouvée")
		change_state(States.WALL_GRIFFE)
		return
		
	velocity.y += gravity * g_mul * delta

	# Passage en CHUTE quand on commence à redescendre
	if velocity.y > 0.0:
		change_state(States.CHUTE)

func jump_input(event: InputEvent) -> void:
	if Input.is_action_just_pressed("light_attack"):
		change_state(States.ATTACK_AIR)
	#if not Input.is_action_pressed("jump"):
		#change_state(States.CHUTE)
	
func jump_exit():
	# Pas de snap brutal : on laisse la descente être gérée par CHUTE
	pass
#endregion



var FALL_POINT: float = 0.0

func chute_enter() -> void:
	if previous_state != States.ATTACK_AIR:
		FALL_POINT = global_position.y     # mémorise la hauteur de départ
	print("enter_CHUTE  |  start y =", FALL_POINT)

	animator.play("chute")              # ou "fall"




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


	# Zone "CHUTE" détectée au-dessus + bouton griffe pressé
	if _raycast_hits_group(climbcast_up, "CHUTE") \
		and Input.is_action_just_pressed("griffe"):
		change_state(States.CHUTE_GRIFFE)
		return


	# Détection d'une zone "GRAB"
	if previous_state != States.GRAB and _raycast_hits_group(grab, "GRAB"):
		var area := grab.get_collider()          # l'Area2D détectée (garantie "GRAB")
		current_grab_area = area
		print("j'ai trouvé le GRAB")
		change_state(States.GRAB)
		return

	#ancien wall jump
	# Mur « forward » appartenant au groupe "wall_jump" ?
	if _raycast_hits_group(wall_right, "wall_jump", true):
		change_state(States.WALL_JUMP)
		return

	# --- 1) CLIMB droite + gauche ---------------------------------
	var hit_r := _raycast_hits_group(climbcast_right, "CLIMB")
	var hit_l := _raycast_hits_group(climbcast_left,  "CLIMB")

	if hit_r and hit_l and Input.is_action_just_pressed("griffe"):
		print("CLIMB gauche + droite")
		change_state(States.CLIMB)
		return           # on quitte : priorité au CLIMB

	# --- 2) GRIFFE (zone collée au mur) ---------------------------
	if _raycast_hits_group(climbcast_right, "GRIFFE") \
		and abs(velocity.x) > 0 \
		and Input.is_action_just_pressed("griffe"):
		print("GRIFFE trouvée")
		change_state(States.WALL_GRIFFE)
		return

		# Détection de l'atterrissage
# -----------------------------------------------------------------
#  Dans le bloc d’atterrissage (chute_execute ou jump_execute, etc.)
# -----------------------------------------------------------------
	if is_on_floor():
		calcule_falling_damage()            # ← peut changer l’état en HIT ou DEAD


		# Effet d’impact visuel
		var land_fx = instantiate_scene(CHUTE_SCENE)
		land_fx.global_position = ANCRE_SOL.global_position
		if land_fx is AnimatedSprite2D:
			land_fx.play()

		# ─── Si l’état a changé, on arrête là ─────────────────────────
		if current_state == States.DEAD or current_state == States.HIT:
			return                          # on ne poursuit pas la logique d’atterrissage
		# -----------------------------------------------------------------

		# Transition normale
		if Input.is_action_pressed("right_move") or Input.is_action_pressed("left_move"):
			goto_state(States.RUN)
		else:
			goto_state(States.IDLE)


func chute_input(event: InputEvent) -> void:
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

func wall_griffe_execute(_delta: float) -> void:
	if _raycast_hits_group(climbcast_right, "GRIFFE"):
		return                       # Toujours accroché → on ne bouge pas
	change_state(States.CHUTE)       # Sinon, on lâche le mur

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
	_flip_facing_on_wall()
	velocity = Vector2.ZERO
	animator.play("wall_jump")
	print("enter_wall_jump | last_direction:", last_direction, " | point.scale.x:", point.scale.x)



func wall_jump_execute(delta: float) -> void:
	# 1) Phase « jump » : gravité + bascule en CHUTE dès qu'on redescend
	if animator.animation == "jump":
		velocity.y += gravity * delta
		if velocity.y > 0:
			change_state(States.CHUTE)
		return                                 # on sort : pas la phase murale

	# 2) Phase accrochée (animation statique)
	# -------- détection des murs --------
	var on_left  := _raycast_hits_group(wall_left,  "wall_jump", true)
	var on_right := _raycast_hits_group(wall_right, "wall_jump", true)

	# --- NOUVEAU : si seul le mur de droite est détecté → CHUTE ---
	if on_right and not on_left:
		change_state(States.CHUTE)
		return

	# Si plus aucun mur → CHUTE
	if not (on_left or on_right):
		change_state(States.CHUTE)
		return

	# -------- glissement contrôlé --------
	var glide_speed := 300.0
	velocity.y = lerp(velocity.y, glide_speed, 0.05)

	# -------- fin si on touche le sol ----
	if is_on_floor():
		change_state(States.IDLE)


func wall_jump_input(event: InputEvent) -> void:
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
	var dir := Input.get_vector("left_move", "right_move",
		"up_move",   "down_move")

	const DEAD_ZONE := 0.3
	if abs(dir.x) < DEAD_ZONE:
		dir.x = 0

	# 2) Prise “avant” (raycast forward)
	var can_climb_forward := _raycast_hits_group(climbcast_right, "CLIMB")

	# 3) Perte de prise → anim CLIMBQUIT (une fois)
	if not can_climb_forward and animator.animation != "climbquit":
		animator.play("climbquit")

	# 4) Retrouve la prise après un quit → anim CLIMBIDLE
	if can_climb_forward and animator.animation == "climbquit":
		animator.play("climbidle")

	# 5) Blocage inputs quand la prise est perdue
	if not can_climb_forward:
		if sign(point.scale.x) > 0:
			dir.x = min(dir.x, 0)
		else:
			dir.x = max(dir.x, 0)
		dir.y = 0

	# ───────────── ANIMATIONS DE MOUVEMENT ─────────────
	if animator.animation != "climbquit":
		if dir == Vector2.ZERO:
			animator.play("climbidle")
		else:
			if abs(dir.x) > abs(dir.y):
				animator.play("climb_move_up")
			elif dir.y < 0:
				animator.play("climb_move_up")
			else:
				animator.play("climb_move_down")
	# ───────────────────────────────────────────────────

	# 6) Application de la vitesse
	velocity = dir * CLIMB_SPEED

	# 7) Flip visuel si on bouge horizontalement
	_flip_from_input()

	# 8) Sorties d’état jump / esquive
	if Input.is_action_just_pressed("esquive"):
		change_state(States.CHUTE)
		return
	elif Input.is_action_just_pressed("jump"):
		change_state(States.JUMP)
		return

	# 9) Sortie CHUTE si ni gauche ni droite ne détectent la zone
	var hit_left  := _raycast_hits_group(climbcast_left,  "CLIMB")
	var hit_right := _raycast_hits_group(climbcast_right, "CLIMB")
	if not (hit_left or hit_right):
		change_state(States.CHUTE)
		return

	# 10) Si UP ne détecte plus la zone → JUMP
	var hit_up := _raycast_hits_group(climbcast_up, "CLIMB")
	if not hit_up:
		change_state(States.JUMP)
		return

func climb_input(event: InputEvent) -> void:
	pass

func climb_exit() -> void:
	pass



func roll_enter() -> void:
	# 1) Direction analogique (entre -1 et 1)
	var dir := Input.get_axis("left_move", "right_move")

	# 2) On déclenche la roulade seulement s’il y a une direction
	if dir != 0.0:
		dir = sign(dir)              # => -1 ou 1
		last_direction = dir
		point.scale.x  = dir
		velocity.x     = dir * ROLL_SPEED   # toujours vitesse max
		animator.play("roll")
	#else:
		# Pas de direction → on retourne directement à BACK_ROLL
		#change_state(States.BACK_ROLL)	

func roll_execute(delta: float) -> void:
	# On applique la gravité pendant la roll
	velocity.y += gravity * delta

func roll_input(event: InputEvent) -> void:
	# Pas d'input additionnel pendant la roll
	pass

func roll_exit() -> void:
	pass
# ------------------------------------------------------------------
# CALLBACK : fin de l'animation
#func _on_roll_animation_finished() -> void:
	#print("je joue cette partie de code ")
	## Selon l’input au moment de la fin, on change d'état
	#var horiz = Input.get_action_strength("right_move") - Input.get_action_strength("left_move")
	#if horiz != 0:
		#change_state(States.RUN)
	#elif Input.is_action_just_pressed("jump"):
		#change_state(States.JUMP)
	#elif not is_on_floor():
		#change_state(States.CHUTE)
	#else:
		#change_state(States.IDLE)

# CALLBACK : fin de l'animation
func _on_roll_animation_finished() -> void:
	var horiz := Input.get_action_strength("right_move") - Input.get_action_strength("left_move")

	if horiz != 0.0:
		goto_state(States.RUN)
	elif Input.is_action_pressed("jump"):
		goto_state(States.JUMP)
	elif not is_on_floor():
		goto_state(States.CHUTE)
	else:
		goto_state(States.IDLE)



func chute_griffe_enter() -> void:
	print("jegriffe")
	animator.play("chute_griffe")
	velocity.y = 250.0

func chute_griffe_execute(delta: float) -> void:
	# 1) ---------------- Paramètres locaux ----------------
	const GLIDE_Y   := 250.0
	const GLIDE_X   := 150.0
	const DECELRATE := 0.50

	# 2) ---------------- Mouvement horizontal -------------
	var dir := Input.get_axis("left_move", "right_move")
	if dir != 0:
		velocity.x = dir * GLIDE_X
	else:
		velocity.x = lerp(velocity.x, 0.0, DECELRATE * delta)

	# 3) ---------------- Descente constante ---------------
	velocity.y = GLIDE_Y

	# 4) ---------------- Vérif du maintien de la prise ----
	var still_holding := _raycast_hits_group(climbcast_up, "CHUTE") \
		and Input.is_action_pressed("griffe")

	if not still_holding:
		change_state(States.CHUTE)

func chute_griffe_input(event: InputEvent) -> void:
	pass

func chute_griffe_exit() -> void:
	pass



#region GRAB


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
func grab_input(event: InputEvent) -> void:
	if Input.is_action_just_pressed("jump"):
		change_state(States.JUMP)
	elif Input.is_action_just_pressed("esquive"):
		change_state(States.CHUTE)

func grab_exit() -> void:
	pass
#endregion

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
		
func attack_light_1_input(event: InputEvent) -> void:
	if event.is_action("light_attack") \
		and event.is_pressed() \
		and not event.is_echo() \
		and animator.animation == "attack":
		combo = true
	if animator.animation == "attack_r":
		if Input.is_action_just_pressed("light_attack"):
			change_state(States.ATTACK_LIGHT_2)
		if Input.is_action_pressed("right_move") or Input.is_action_pressed("left_move"):
			change_state(States.RUN)
		elif Input.is_action_just_pressed("jump"):
			change_state(States.JUMP)
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

func attack_light_2_input(event: InputEvent) -> void:
	if event.is_action("light_attack") \
		and event.is_pressed() \
		and not event.is_echo() \
		and animator.animation == "attack_02":
		combo = true
	if animator.animation == "attack_02_r":
		if Input.is_action_just_pressed("light_attack"):
			change_state(States.ATTACK_LIGHT_3)
		if Input.is_action_pressed("right_move") or Input.is_action_pressed("left_move"):
			change_state(States.RUN)
		elif Input.is_action_just_pressed("jump"):
			change_state(States.JUMP)
	
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
func attack_light_3_input(event: InputEvent) -> void:
	if animator.animation == "attack_03_r":
		if Input.is_action_just_pressed("light_attack"):
			change_state(States.ATTACK_LIGHT_1)
		if Input.is_action_pressed("right_move") or Input.is_action_pressed("left_move"):
			change_state(States.RUN)
		elif Input.is_action_just_pressed("jump"):
			change_state(States.JUMP)
	
	
func attack_light_3_animation_finished() -> void:
	match animator.animation:
		"attack_03":
			animator.play("attack_03_r")
		"attack_03_r":
			if Input.is_action_just_pressed("light_attack"):
				change_state(States.ATTACK_LIGHT_1)
			if Input.is_action_pressed("right_move") or Input.is_action_pressed("left_move"):
				change_state(States.RUN)
				return
			else:
				change_state(States.IDLE)
				return

func attack_light_3_exit() -> void:
	velocity.x = 0
	combo = false




#func attack_light_3_enter() -> void:
	## 1) On lit l’input horizontal une fois
	#_flip_from_input()
	#combo = false
	#print("attack3")
	#animator.play("attack_03")
#
#func attack_light_3_execute(delta: float) -> void:
	#pass
#func attack_light_3_input(event: InputEvent) -> void:
	#if event.is_action("light_attack") \
		#and event.is_pressed() \
		#and not event.is_echo() \
		#and animator.animation == "attack_03":
		#combo = true
	#if animator.animation == "attack_03_r":
		#if Input.is_action_just_pressed("light_attack"):
			#change_state(States.ATTACK_LIGHT_1)
		#if Input.is_action_pressed("right_move") or Input.is_action_pressed("left_move"):
			#change_state(States.RUN)
		#elif Input.is_action_just_pressed("jump"):
			#change_state(States.JUMP)
	#
	#
#func attack_light_3_animation_finished() -> void:
	#match animator.animation:
		#"attack_03":
			#if combo == true:
				#change_state(States.ATTACK_LIGHT_1)
				#return
			#else:
				#animator.play("attack_03_r")
		#"attack_03_r":
			#if Input.is_action_pressed("right_move") or Input.is_action_pressed("left_move"):
				#change_state(States.RUN)
				#return
			#else:
				#change_state(States.IDLE)
				#return
#
#func attack_light_3_exit() -> void:
	#velocity.x = 0
	#combo = false

func attack_lourde_enter() -> void:
	slash_attack.position = Vector2(-32, -92)
	animator.play("attack_lourde")

func attack_lourde_execute(delta: float) -> void:
	pass
func attack_lourde_input(event: InputEvent) -> void:
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
		calcule_falling_damage()
		if Input.is_action_pressed("right_move") or Input.is_action_pressed("left_move"):
			goto_state(States.RUN)
		else:
			change_state(States.IDLE)
	
func attack_air_input(event: InputEvent) -> void:
	pass
	

func attack_air_animation_finished() -> void:
	match animator.animation:
		"attack_air":
			change_state(States.CHUTE)

func attack_air_exit() -> void:
	pass




func heal_enter() -> void:
	animator.play("heal")


func heal_execute(delta: float) -> void:
	pass
func heal_input(event: InputEvent) -> void:
	pass
	
	
func heal_finished() -> void:
	match animator.animation:
		"heal":
			Player.heal_blood()
			if Input.is_action_pressed("right_move") or Input.is_action_pressed("left_move"):
				change_state(States.RUN)
			else:
				change_state(States.IDLE)

func heal_exit() -> void:
	velocity.x = 0



# -------------------------------------------------
# HIT EXECUTE – calcul du knock-back + gravité
# -------------------------------------------------
# ------------------------------------------
# Mettre tout en haut du script
# ------------------------------------------
var HIT_DEBUG := true          # un interrupteur on/off
var _hit_seq  := 0             # numéro de séquence pour repérer chaque HIT
func _dbg(msg:String) -> void:
	if HIT_DEBUG:
		print("[", Engine.get_physics_frames(), "] ", msg)

# ------------------------------------------
# apply_damage  (joueur ET squelette)


# ------------------------------------------
# hit_enter
# ------------------------------------------

# --- Réglages HIT (en haut du script) ---
@export var HIT_STUN_TIME: float = 0.25    # durée du hitstun (en s)
@export var HIT_KNOCK_X:  float = 500.0    # force horizontale initiale
@export var HIT_KNOCK_Y:  float = -180.0   # rebond vertical initial
@export var HIT_X_DAMP:   float = 8.0     # amortissement horizontal (plus grand = s’arrête plus vite)

var _hit_elapsed := 0.0

func hit_enter() -> void:
	velocity = Vector2.ZERO
	animator.play("hit")
	_hit_elapsed = 0.0

	# Knock-back horizontal uniquement si l’attaquant est connu
	if position_x_enemi != null:
		var dir := 1 if (global_position.x - position_x_enemi) > 0 else -1
		velocity.x = dir * HIT_KNOCK_X
	else:
		velocity.x = 0.0

	# Rebond vertical commun
	velocity.y = HIT_KNOCK_Y

	# On réinitialise le pointeur
	position_x_enemi = null


func hit_execute(delta: float) -> void:
	_hit_elapsed += delta

	# Gravité + amortissement horizontal
	velocity.y += gravity * delta
	velocity.x = lerp(velocity.x, 0.0, clamp(HIT_X_DAMP * delta, 0.0, 1.0))

	# Sortie APRÈS un temps fixe, sol ou pas
	if _hit_elapsed >= HIT_STUN_TIME:
		if is_on_floor():
			goto_state(States.IDLE)
		else:
			goto_state(States.CHUTE)

# ------------------------------------------
# hit_exit
# ------------------------------------------
func hit_exit() -> void:
	velocity   = Vector2.ZERO
	
	
func dead_enter() -> void:
	animator.play("death")
	print("enter_DEAD")


func dead_execute(delta: float) -> void:
	pass
	
func dead_input(event: InputEvent) -> void:
	pass
	

func dead_exit() -> void:
	velocity.x = 0
