extends CharacterBody2D


enum States { IDLE, RUN, CHUTE, JUMP, WALL_GRIFFE, WALL_JUMP, CLIMB, ROLL, CHUTE_GRIFFE, GRAB, ATTACK_LIGHT_1, ATTACK_LIGHT_2, ATTACK_LIGHT_3, ATTACK_AIR, ATTACK_LOURDE, DEAD, HIT, HEAL, DROP }
const STATE_STAMINA_COSTS := {
	States.ROLL:            0,
	States.ATTACK_LIGHT_1:  0,
	States.ATTACK_LIGHT_2:  0,
	States.ATTACK_LIGHT_3:  0,
	States.ATTACK_AIR:      0,
	States.ATTACK_LOURDE:   0,
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

const GROUND_SPEED = 600            # FIX: renommé pour clarté
const AIR_SPEED    = 400            # FIX: anciennement var SPEED locale shadowed
var last_direction := 1  # 1 = droite, -1 = gauche
var no_WJ = false
const CLIMB_SPEED := 200.0
const ROLL_SPEED := 700.0


var grab_target_position: Vector2 = Vector2.ZERO
var current_grab_area: Area2D = null

const FOOTSTEP_SCENE = preload("uid://bc2iigjdyudgm")
const CHUTE_SCENE = preload("uid://bfwic6xtfgc4p")
const WALL_JUMP_SCENE = preload("uid://c5a6or75xrx3o")

# AMÉLIORATION: combo_count remplace le bool "combo" — plus clair et extensible
var combo_buffered := false   # true si le joueur a appuyé pendant l'anim en cours





func _ready() -> void:
	animator.connect("animation_finished", Callable(self, "_on_animation_finished"))
	set_floor_max_angle(deg_to_rad(60))
	set_floor_snap_length(6.0)
	print(Player.hp,"hp")
	initialize_states()
	change_state(States.IDLE)


func _physics_process(delta: float) -> void:
	state_functions[current_state]["execute"].call(delta)
	move_and_slide()


### GESTION DES INPUTS ###
func _input(event):
	if state_functions[current_state].has("input"):
		state_functions[current_state]["input"].call(event)

# Dispatcher animation_finished (sans argument)
func _on_animation_finished() -> void:
	var funcs = state_functions[current_state]
	if funcs.has("animation_finished"):
		funcs["animation_finished"].call()


# ---------------------------------------------------------
#  UTILITAIRES
# ---------------------------------------------------------

## goto_state : transition DIFFÉRÉE (call_deferred) — à utiliser depuis execute/physics
## pour éviter de changer d'état pendant qu'on est encore dans le callback.
## change_state : transition IMMÉDIATE — à utiliser depuis input/animation_finished.
# AMÉLIORATION: documentation claire de la distinction

func apply_damage(amount: int, source_x) -> void:
	if current_state in [States.ROLL, States.DEAD]:
		return
	if current_state != States.HIT:
		print("j'ai pris les dégâts")
		Player.changement_de_vie(-amount)
		print("Player_vie", Player.hp)
		if Player.hp <= 0:
			print("ma vie est a zero ")
			change_state(States.DEAD)
			return
		position_x_enemi = source_x
		change_state(States.HIT)


func goto_state(s: States) -> void:
	if current_state == s:
		return
	call_deferred("change_state", s)

func _raycast_hits_group(rc: RayCast2D, group_name: String, body_only := false) -> bool:
	# AMÉLIORATION: note — cette fonction peut faire plusieurs force_raycast_update
	# par appel si des colliders sont empilés. Surveiller les perfs si besoin.
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

		var rid := rc.get_collider_rid()
		rc.add_exception_rid(rid)
		ignored.append(rid)
		rc.force_raycast_update()

	for rid in ignored:
		rc.remove_exception_rid(rid)
	rc.force_raycast_update()
	return false

func _is_valid_press(action_name: String) -> bool:
	return Input.is_action_just_pressed(action_name)


func calcule_falling_damage() -> int:
	const SAFE_HEIGHT: float     = 850.0
	const DAMAGE_PER_STEP: int   = 6
	const STEP_PX: float         = 100.0

	var impact_point: float  = global_position.y
	var fall_distance: float = max(0.0, impact_point - FALL_POINT)

	if fall_distance <= SAFE_HEIGHT:
		print("Chute sans dégâts (", fall_distance, " px )")
		return 0

	var excess: float  = fall_distance - SAFE_HEIGHT
	var damage: int    = int(ceil(excess / STEP_PX)) * DAMAGE_PER_STEP
	apply_damage(damage, null)
	print("Dégâts de chute :", damage,
		" | hauteur totale :", fall_distance, " px",
		" | excès :", excess, " px")
	return damage


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
	var target_parent: Node = parent_node if parent_node != null else get_tree().get_current_scene()
	target_parent.add_child(instance)
	return instance

func _flip_facing_on_wall() -> void:
	point.scale.x *= -1
	last_direction = -last_direction


func _flip_from_input() -> void:
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
		"input": chute_input,      # FIX: les inputs just_pressed sont dans input, plus dans execute
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
	state_functions[States.DROP] = {
		"enter": drop_enter,
		"execute": drop_execute,
		"exit": drop_exit,
	}

# ----------- Gestion du changement d'état ---------------

var _changing_now := false

func change_state(new_state: States) -> void:
	print("[", Engine.get_physics_frames(), "] ",
		"STATE: ", current_state, " -> ", new_state,
		" | on_floor=", is_on_floor(), " | vel=", velocity)

	if _changing_now or new_state == current_state:
		return

	var cost := _get_state_cost(new_state)
	var skip_check := (new_state == States.ROLL)
	var force_idle_on_fail := (
		current_state == States.ATTACK_LIGHT_1
		or current_state == States.ATTACK_LIGHT_2
		or current_state == States.ATTACK_LIGHT_3
	)

	var requires_stamina := (cost > 0) and (not skip_check)
	if requires_stamina and Player.en < 1:
		if force_idle_on_fail and current_state != States.IDLE:
			_changing_now = true
			state_functions[current_state]["exit"].call()
			previous_state = current_state
			current_state  = States.IDLE
			state_functions[current_state]["enter"].call()
			_changing_now = false
		return

	if cost > 0:
		Player.changement_d_endurance(-cost)

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
	elif Input.is_action_just_pressed("down_move") and is_on_floor():
		change_state(States.DROP)
		return

func idle_exit() -> void:
	pass
#endregion

# =====================  RUN  ===========================

var run_frame_counter : int = 0
var air_ground_instance


func run_enter() -> void:
	animator.play("run")


func run_execute(delta: float) -> void:
	run_frame_counter += 1
	_flip_from_input()

	velocity.y += gravity * delta

	if not is_on_floor():
		goto_state(States.CHUTE)
		return

	var direction := Input.get_axis("left_move", "right_move")

	if direction == 0:
		goto_state(States.IDLE)
		return

	if animator.animation == "run" and run_frame_counter % 10 == 0:
		var foot = instantiate_scene(FOOTSTEP_SCENE)
		foot.global_position = ANCRE_SOL_BACK.global_position
		foot.scale.x        *= point.scale.x
		foot.play("run_to_ground")

	# FIX: utilise GROUND_SPEED au lieu de SPEED
	var target_speed: float = float(direction) * GROUND_SPEED
	velocity.x = lerp(velocity.x, target_speed, 0.15)


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
	elif Input.is_action_just_pressed("down_move") and is_on_floor():
		change_state(States.DROP)
		return

func run_exit() -> void:
	pass


#region JUMP

const JUMP_VELOCITY   = -700.0   # retour à l'original
const MIN_JUMP_TIME   := 0.01
const MAX_JUMP_HOLD   := 0.25
const GRAVITY_RISE    := 0.45    # hold long → monte bien haut
const GRAVITY_CUTOFF  := 3.50    # lâche tôt → coupe net
const GRAVITY_FALL    := 1.35

const AIR_CONTROL = 0.2
const DECELERATION_RATE = 0.95
var _jump_timer := 0.0
var _climb_auto_exit := false
const CLIMB_EXIT_VELOCITY := -1000.0  # plus fort que JUMP_VELOCITY (-700)

func jump_enter():
	animator.play("jump")
	_jump_timer = 0.0
	
	if _climb_auto_exit:
		velocity.y = CLIMB_EXIT_VELOCITY
		velocity.x = 0.0
		_climb_auto_exit = false
		_jump_timer = MAX_JUMP_HOLD  # ← désactive le hold, gravité normale immédiate
	else:
		velocity.y = JUMP_VELOCITY


func jump_execute(delta):
	_jump_timer += delta

	# FIX: utilise AIR_SPEED au lieu de redéclarer var SPEED locale
	var direction = Input.get_axis("left_move", "right_move")
	_flip_from_input()
	if direction != 0:
		velocity.x = lerp(velocity.x, direction * AIR_SPEED, AIR_CONTROL)
	else:
		velocity.x = lerp(velocity.x, 0.0, DECELERATION_RATE * delta)

	if is_on_ceiling():
		velocity.y = 0.0

	var g_mul := 1.0
	if velocity.y < 0.0:
		var holding := Input.is_action_pressed("jump")
		var force_min := _jump_timer < MIN_JUMP_TIME
		var within_hold := _jump_timer < MAX_JUMP_HOLD

		if force_min or (holding and within_hold):
			g_mul = GRAVITY_RISE
		else:
			g_mul = GRAVITY_CUTOFF
	else:
		g_mul = GRAVITY_FALL

	# FIX: check GRIFFE déplacé dans jump_input (is_action_just_pressed)
	velocity.y += gravity * g_mul * delta

	if velocity.y > 0.0:
		change_state(States.CHUTE)

func jump_input(event: InputEvent) -> void:
	if Input.is_action_just_pressed("light_attack"):
		change_state(States.ATTACK_AIR)
		return
	# CLIMB
	var hit_r := _raycast_hits_group(climbcast_right, "CLIMB")
	var hit_l := _raycast_hits_group(climbcast_left,  "CLIMB")
	if hit_r and hit_l and Input.is_action_just_pressed("griffe"):
		change_state(States.CLIMB)
		return
	# GRIFFE
	if _raycast_hits_group(climbcast_right, "GRIFFE") \
		and abs(velocity.x) > 0 \
		and Input.is_action_just_pressed("griffe"):
		change_state(States.WALL_GRIFFE)
		return

func jump_exit():
	pass
#endregion



# FIX: FALL_POINT initialisé à -INF pour éviter des faux dégâts si chute_enter
# n'est jamais passé (edge case)
var FALL_POINT: float = -1e9

func chute_enter() -> void:
	if previous_state != States.ATTACK_AIR:
		FALL_POINT = global_position.y
	print("enter_CHUTE  |  start y =", FALL_POINT)
	animator.play("chute")


func chute_execute(delta: float) -> void:
	var direction := Input.get_axis("left_move", "right_move")

	# FIX: supprimé is_action_just_pressed("light_attack") d'ici → déplacé dans chute_input

	if direction != 0 and previous_state != States.WALL_JUMP:
		last_direction = sign(direction)
		point.scale.x = last_direction

	velocity.y += gravity * delta

	# FIX: utilise AIR_SPEED au lieu de var SPEED locale
	if direction != 0:
		velocity.x = lerp(velocity.x, direction * AIR_SPEED, AIR_CONTROL)
	else:
		velocity.x = lerp(velocity.x, 0.0, DECELERATION_RATE * delta)

	# Détection de GRAB
	if previous_state != States.GRAB and _raycast_hits_group(grab, "GRAB"):
		var area := grab.get_collider()
		current_grab_area = area
		print("j'ai trouvé le GRAB")
		change_state(States.GRAB)
		return

	# Mur wall_jump (body_only) — is_colliding ne nécessite pas just_pressed
	if _raycast_hits_group(wall_right, "wall_jump", true):
		change_state(States.WALL_JUMP)
		return

	# Atterrissage
	if is_on_floor():
		calcule_falling_damage()

		var land_fx = instantiate_scene(CHUTE_SCENE)
		land_fx.global_position = ANCRE_SOL.global_position
		if land_fx is AnimatedSprite2D:
			land_fx.play()

		if current_state == States.DEAD or current_state == States.HIT:
			return

		if Input.is_action_pressed("right_move") or Input.is_action_pressed("left_move"):
			goto_state(States.RUN)
		else:
			goto_state(States.IDLE)


func chute_input(event: InputEvent) -> void:
	# FIX: tous les just_pressed sont regroupés ici (fiable dans _input)
	if Input.is_action_just_pressed("light_attack"):
		print("j'attaque en l'air")
		change_state(States.ATTACK_AIR)
		return

	# FIX: déplacé depuis chute_execute
	if _raycast_hits_group(climbcast_up, "CHUTE") \
		and Input.is_action_just_pressed("griffe"):
		change_state(States.CHUTE_GRIFFE)
		return

	# FIX: déplacé depuis chute_execute
	var hit_r := _raycast_hits_group(climbcast_right, "CLIMB")
	var hit_l := _raycast_hits_group(climbcast_left,  "CLIMB")
	if hit_r and hit_l and Input.is_action_just_pressed("griffe"):
		print("CLIMB gauche + droite")
		change_state(States.CLIMB)
		return

	# FIX: déplacé depuis chute_execute
	if _raycast_hits_group(climbcast_right, "GRIFFE") \
		and abs(velocity.x) > 0 \
		and Input.is_action_just_pressed("griffe"):
		print("GRIFFE trouvée")
		change_state(States.WALL_GRIFFE)
		return


func chute_exit() -> void:
	pass



#region WALL_GRIFFE
func wall_griffe_enter():
	animator.play("wall_griffe")
	velocity.y = 0

	# On détermine la direction selon la vélocité d'arrivée
	if velocity.x > 0:
		last_direction = 1
	elif velocity.x < 0:
		last_direction = -1

	point.scale.x = last_direction

	# On pousse le perso DANS le mur pour maintenir le contact raycast
	# Le mur bloque le déplacement réel, mais la vélocité garde le contact
	velocity.x = 500.0 * last_direction

func wall_griffe_execute(_delta: float) -> void:
	if _raycast_hits_group(climbcast_right, "GRIFFE"):
		return
	change_state(States.CHUTE)

func wall_griffe_input(event: InputEvent):
	if Input.is_action_just_pressed("jump"):
		change_state(States.JUMP)

func wall_griffe_animation_finished():
	change_state(States.CHUTE)

func wall_griffe_exit():
	pass
#endregion





#region WALL_JUMP
func wall_jump_enter():
	_flip_facing_on_wall()
	velocity = Vector2.ZERO
	animator.play("wall_jump")
	print("enter_wall_jump | last_direction:", last_direction, " | point.scale.x:", point.scale.x)


func wall_jump_execute(delta: float) -> void:
	# Phase « jump » : gravité + bascule en CHUTE dès qu'on redescend
	if animator.animation == "jump":
		velocity.y += gravity * delta
		if velocity.y > 0:
			change_state(States.CHUTE)
		return

	# Phase accrochée
	var on_left  := _raycast_hits_group(wall_left,  "wall_jump", true)
	var on_right := _raycast_hits_group(wall_right, "wall_jump", true)

	if on_right and not on_left:
		change_state(States.CHUTE)
		return

	if not (on_left or on_right):
		change_state(States.CHUTE)
		return

	var glide_speed := 300.0
	velocity.y = lerp(velocity.y, glide_speed, 0.05)

	if is_on_floor():
		change_state(States.IDLE)


func wall_jump_input(event: InputEvent) -> void:
	const WALL_YJUMP := -500
	const WALL_XJUMP := 290

	if Input.is_action_just_pressed("jump") and animator.animation != "jump":
		var land_fx = instantiate_scene(WALL_JUMP_SCENE)
		land_fx.global_position = ANCRE_WALL.global_position
		land_fx.scale.x *= point.scale.x
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
	velocity = Vector2.ZERO
	animator.play("climbidle")

func climb_execute(delta: float) -> void:
	var dir := Input.get_vector("left_move", "right_move",
		"up_move",   "down_move")

	const DEAD_ZONE := 0.3
	if abs(dir.x) < DEAD_ZONE:
		dir.x = 0

	var can_climb_forward := _raycast_hits_group(climbcast_right, "CLIMB")

	if not can_climb_forward and animator.animation != "climbquit":
		animator.play("climbquit")

	if can_climb_forward and animator.animation == "climbquit":
		animator.play("climbidle")

	if not can_climb_forward:
		if sign(point.scale.x) > 0:
			dir.x = min(dir.x, 0)
		else:
			dir.x = max(dir.x, 0)
		dir.y = 0

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

	velocity = dir * CLIMB_SPEED
	_flip_from_input()

	var hit_left  := _raycast_hits_group(climbcast_left,  "CLIMB")
	var hit_right := _raycast_hits_group(climbcast_right, "CLIMB")
	if not (hit_left or hit_right):
		change_state(States.CHUTE)
		return

	var hit_up := _raycast_hits_group(climbcast_up, "CLIMB")
	if not hit_up:
		_climb_auto_exit = true
		change_state(States.JUMP)
		return

func climb_input(event: InputEvent) -> void:
	# FIX: déplacé depuis climb_execute — just_pressed appartient à _input
	if Input.is_action_just_pressed("esquive"):
		change_state(States.CHUTE)
		return
	elif Input.is_action_just_pressed("jump"):
		change_state(States.JUMP)
		return

func climb_exit() -> void:
	pass



func roll_enter() -> void:
	var dir := Input.get_axis("left_move", "right_move")

	if dir != 0.0:
		dir = sign(dir)
		last_direction = dir
		point.scale.x  = dir
		velocity.x     = dir * ROLL_SPEED
		animator.play("roll")

func roll_execute(delta: float) -> void:
	velocity.y += gravity * delta

func roll_input(event: InputEvent) -> void:
	pass

func roll_exit() -> void:
	pass

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
	const GLIDE_Y   := 250.0
	const GLIDE_X   := 150.0
	const DECELRATE := 0.50

	var dir := Input.get_axis("left_move", "right_move")
	if dir != 0:
		velocity.x = dir * GLIDE_X
	else:
		velocity.x = lerp(velocity.x, 0.0, DECELRATE * delta)

	velocity.y = GLIDE_Y

	# is_action_pressed (pas just_pressed) → OK dans execute
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
		var grab_pos = current_grab_area.global_position
		var offset = ancre_grab.global_position - global_position
		var target_pos = grab_pos - offset
		global_position = target_pos

	animator.play("suspendu")

func grab_execute(delta: float) -> void:
	if current_grab_area:
		var grab_pos = current_grab_area.global_position
		var offset = ancre_grab.global_position - global_position
		var target_pos = grab_pos - offset
		var lerp_speed = 10.0
		global_position = global_position.move_toward(target_pos, lerp_speed * delta)

func grab_input(event: InputEvent) -> void:
	if Input.is_action_just_pressed("jump"):
		change_state(States.JUMP)
	elif Input.is_action_just_pressed("esquive"):
		change_state(States.CHUTE)

func grab_exit() -> void:
	pass
#endregion


# =====================  ATTAQUES  ===========================
# AMÉLIORATION: combo_buffered remplace le bool "combo"
# Chaque état d'attaque l'utilise de la même façon :
# - enter: reset combo_buffered = false
# - input: si le joueur appuie pendant l'anim principale → combo_buffered = true
# - animation_finished: si combo_buffered → chaîne, sinon → recovery (anim _r)

func attack_light_1_enter() -> void:
	slash_attack.position = Vector2(57, -92)
	_flip_from_input()
	combo_buffered = false
	animator.play("attack")

func attack_light_1_execute(delta: float) -> void:
	pass

func attack_light_1_input(event: InputEvent) -> void:
	# Buffer pendant l'anim principale
	if event.is_action("light_attack") \
		and event.is_pressed() \
		and not event.is_echo() \
		and animator.animation == "attack":
		combo_buffered = true
	# Pendant la recovery
	if animator.animation == "attack_r":
		if Input.is_action_just_pressed("light_attack"):
			change_state(States.ATTACK_LIGHT_2)
		elif Input.is_action_pressed("right_move") or Input.is_action_pressed("left_move"):
			change_state(States.RUN)
		elif Input.is_action_just_pressed("jump"):
			change_state(States.JUMP)

func attack_light_1_animation_finished() -> void:
	match animator.animation:
		"attack":
			if combo_buffered:
				change_state(States.ATTACK_LIGHT_2)
				return
			else:
				animator.play("attack_r")
		"attack_r":
			combo_buffered = false
			if Input.is_action_pressed("right_move") or Input.is_action_pressed("left_move"):
				change_state(States.RUN)
				return
			else:
				change_state(States.IDLE)

func attack_light_1_exit() -> void:
	combo_buffered = false
	velocity.x = 0



func attack_light_2_enter() -> void:
	_flip_from_input()
	combo_buffered = false
	print("attack2")
	animator.play("attack_02")

func attack_light_2_execute(delta: float) -> void:
	pass

func attack_light_2_input(event: InputEvent) -> void:
	if event.is_action("light_attack") \
		and event.is_pressed() \
		and not event.is_echo() \
		and animator.animation == "attack_02":
		combo_buffered = true
	if animator.animation == "attack_02_r":
		if Input.is_action_just_pressed("light_attack"):
			change_state(States.ATTACK_LIGHT_3)
		elif Input.is_action_pressed("right_move") or Input.is_action_pressed("left_move"):
			change_state(States.RUN)
		elif Input.is_action_just_pressed("jump"):
			change_state(States.JUMP)

func attack_light_2_animation_finished() -> void:
	match animator.animation:
		"attack_02":
			if combo_buffered:
				change_state(States.ATTACK_LIGHT_3)
				return
			else:
				animator.play("attack_02_r")
		"attack_02_r":
			combo_buffered = false
			if Input.is_action_pressed("right_move") or Input.is_action_pressed("left_move"):
				change_state(States.RUN)
				return
			else:
				change_state(States.IDLE)

func attack_light_2_exit() -> void:
	combo_buffered = false
	velocity.x = 0



func attack_light_3_enter() -> void:
	_flip_from_input()
	combo_buffered = false
	print("attack3")
	animator.play("attack_03")

func attack_light_3_execute(delta: float) -> void:
	pass

func attack_light_3_input(event: InputEvent) -> void:
	if animator.animation == "attack_03_r":
		if Input.is_action_just_pressed("light_attack"):
			change_state(States.ATTACK_LIGHT_1)
		elif Input.is_action_pressed("right_move") or Input.is_action_pressed("left_move"):
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
			elif Input.is_action_pressed("right_move") or Input.is_action_pressed("left_move"):
				change_state(States.RUN)
				return
			else:
				change_state(States.IDLE)
				return

func attack_light_3_exit() -> void:
	velocity.x = 0
	combo_buffered = false



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
# HIT
# -------------------------------------------------
var HIT_DEBUG := true
var _hit_seq  := 0
func _dbg(msg:String) -> void:
	if HIT_DEBUG:
		print("[", Engine.get_physics_frames(), "] ", msg)

@export var HIT_STUN_TIME: float = 0.25
@export var HIT_KNOCK_X:  float = 500.0
@export var HIT_KNOCK_Y:  float = -180.0
@export var HIT_X_DAMP:   float = 8.0

var _hit_elapsed := 0.0

func hit_enter() -> void:
	velocity = Vector2.ZERO
	animator.play("hit")
	_hit_elapsed = 0.0

	if position_x_enemi != null:
		var dir := 1 if (global_position.x - position_x_enemi) > 0 else -1
		velocity.x = dir * HIT_KNOCK_X
	else:
		velocity.x = 0.0

	velocity.y = HIT_KNOCK_Y
	position_x_enemi = null


func hit_execute(delta: float) -> void:
	_hit_elapsed += delta

	velocity.y += gravity * delta
	velocity.x = lerp(velocity.x, 0.0, clamp(HIT_X_DAMP * delta, 0.0, 1.0))

	if _hit_elapsed >= HIT_STUN_TIME:
		if is_on_floor():
			goto_state(States.IDLE)
		else:
			goto_state(States.CHUTE)

func hit_exit() -> void:
	velocity = Vector2.ZERO


# -------------------------------------------------
# DEAD — FIX: ajout de la gravité + blocage propre
# -------------------------------------------------
func dead_enter() -> void:
	animator.play("death")
	velocity.x = 0.0            # FIX: stoppe le mouvement horizontal
	print("enter_DEAD")


func dead_execute(delta: float) -> void:
	# FIX: gravité active pour que le corps tombe au sol
	if not is_on_floor():
		velocity.y += gravity * delta
	else:
		velocity.y = 0.0
	# Le joueur est mort — aucun mouvement horizontal
	velocity.x = 0.0
	# TODO: ici tu pourras ajouter un timer pour afficher un écran de game over
	# ou relancer au checkpoint après X secondes / appui sur un bouton


func dead_input(event: InputEvent) -> void:
	# FIX: placeholder — tu pourras ajouter "appuie sur Start pour recommencer"
	pass

func dead_exit() -> void:
	velocity = Vector2.ZERO

# =====================  DROP (passer à travers one-way)  ===========================
#region DROP
const ONEWAY_LAYER := 2
const DROP_THROUGH_TIME := 0.25
var _drop_timer := 0.0

func drop_enter() -> void:
	_drop_timer = DROP_THROUGH_TIME
	set_collision_mask_value(ONEWAY_LAYER, false)
	animator.play("chute")
	velocity.y = 50.0
	FALL_POINT = global_position.y

func drop_execute(delta: float) -> void:
	_drop_timer -= delta
	velocity.y += gravity * delta

	var direction := Input.get_axis("left_move", "right_move")
	if direction != 0:
		velocity.x = lerp(velocity.x, direction * AIR_SPEED, AIR_CONTROL)
		_flip_from_input()
	else:
		velocity.x = lerp(velocity.x, 0.0, DECELERATION_RATE * delta)

	# Timer expiré → réactive le mask et passe en CHUTE
	if _drop_timer <= 0.0:
		change_state(States.CHUTE)
		return

	# Si on atterrit sur du terrain solide (layer 1) avant la fin du timer
	if is_on_floor():
		calcule_falling_damage()
		if current_state == States.DEAD or current_state == States.HIT:
			return
		if Input.is_action_pressed("right_move") or Input.is_action_pressed("left_move"):
			goto_state(States.RUN)
		else:
			goto_state(States.IDLE)

func drop_exit() -> void:
	set_collision_mask_value(ONEWAY_LAYER, true)
#endregion
