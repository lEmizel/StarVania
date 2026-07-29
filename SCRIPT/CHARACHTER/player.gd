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

const GROUND_SPEED = 550            # FIX: renommé pour clarté
const AIR_SPEED    = 400            # FIX: anciennement var SPEED locale shadowed
@export var GROUND_SPEED_ATTACK: float = 450.0  # vitesse de course pendant les attaques
var last_direction := 1  # 1 = droite, -1 = gauche

const CLIMB_SPEED := 200.0
const ROLL_SPEED := 700.0

const COYOTE_TIME := 0.08
var _coyote_timer := 0.0
const JUMP_BUFFER_TIME := 0.12  # très court — juste un filet de sécurité
var _jump_buffer_timer := 0.0

const GRAB_COOLDOWN := 0.2  # secondes avant de pouvoir re-grab
var _grab_cooldown_timer := 0.0
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


var _facing_prev := 1.0

func _physics_process(delta: float) -> void:
	state_functions[current_state]["execute"].call(delta)
	# Le slash FX est enfant de POINT : si le perso se retourne pendant que
	# la traînée joue, elle partirait en miroir avec lui → on la coupe.
	# Détection centralisée ici pour couvrir tous les flips (run, jump, chute...)
	if signf(point.scale.x) != signf(_facing_prev):
		_cut_slash_fx()
	_facing_prev = point.scale.x
	# Knockback absolu — même principe que les monstres (BASE_IA) : tant qu'il
	# est actif, il remplace le déplacement horizontal, via velocity pour que
	# move_and_slide glisse le long du sol
	if _knock != Vector2.ZERO:
		velocity.x = _knock.x
	move_and_slide()
	_decay_knockback(delta)


var _knock := Vector2.ZERO

func _decay_knockback(delta: float) -> void:
	if _knock == Vector2.ZERO:
		return
	_knock = _knock.lerp(Vector2.ZERO, clamp(HIT_X_DAMP * delta, 0.0, 1.0))
	# Seuil de coupure haut (150 px/s) : dès que la poussée devient faible,
	# le joueur reprend IMMÉDIATEMENT le contrôle — pas de queue de knockback
	# qui écrase sa vitesse de course et donne une sensation de ralenti
	if _knock.length_squared() < 22500.0:
		_knock = Vector2.ZERO
		velocity.x = 0.0


## Contrecoup quand le joueur frappe un ennemi inébranlable (sans knockback) :
## si le joueur est en mouvement, une contre-poussée inverse annule son élan
func cancel_movement_recoil() -> void:
	if absf(velocity.x) < 1.0:
		return
	_knock.x = -velocity.x * 1.56  # contrecoup amplifié : 1.2 × 1.3 (+30%)
	velocity.x = 0.0


func _cut_slash_fx() -> void:
	slash_attack.stop()
	slash_attack.visible = false


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



func _handle_landing() -> void:
	calcule_falling_damage()
	if current_state == States.DEAD or current_state == States.HIT:
		return
	var land_fx = instantiate_scene(CHUTE_SCENE)
	land_fx.global_position = ANCRE_SOL.global_position
	if land_fx is AnimatedSprite2D:
		land_fx.play()
	if _jump_buffer_timer > 0.0:
		_jump_buffer_timer = 0.0
		goto_state(States.JUMP)
		return
	if Input.is_action_pressed("right_move") or Input.is_action_pressed("left_move"):
		goto_state(States.RUN)
	else:
		goto_state(States.IDLE)

func apply_damage(amount: int, source_x) -> void:
	if current_state in [States.ROLL, States.DEAD]:
		return
	if current_state != States.HIT:
		Player.changement_de_vie(-amount)
		if Player.hp <= 0:
			_knock = Vector2.ZERO
			change_state(States.DEAD)
			return
		# Knockback horizontal absolu, l'état HIT gère stun + anim
		var dir := 0
		if source_x != null:
			dir = 1 if (global_position.x - source_x) > 0 else -1
		_knock = Vector2(dir * HIT_KNOCK_X, 0.0)
		change_state(States.HIT)
		# Soulèvement : impulsion verticale one-shot, appliquée APRÈS hit_enter
		# (qui remet velocity à zéro) — la gravité gère la retombée
		velocity.y = HIT_KNOCK_Y


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



func calcule_falling_damage() -> int:
	const SAFE_HEIGHT: float     = 850.0
	const DAMAGE_PER_STEP: int   = 30
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
func _register_states(states_enum: Dictionary) -> void:
	for state_name in states_enum:
		var key: int = states_enum[state_name]
		var name_lower: String = state_name.to_lower()
		var dict := {}
		for suffix in ["enter", "execute", "input", "exit", "animation_finished", "animation_looped"]:
			var func_name: String = name_lower + "_" + suffix
			if has_method(func_name):
				dict[suffix] = Callable(self, func_name)
		state_functions[key] = dict

func initialize_states() -> void:
	_register_states(States)

# ----------- Gestion du changement d'état ---------------

var _changing_now := false

func change_state(new_state: States) -> void:
	#print("[", Engine.get_physics_frames(), "] ",
		#"STATE: ", current_state, " -> ", new_state,
		#" | on_floor=", is_on_floor(), " | vel=", velocity)

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
	_grab_cooldown_timer = max(_grab_cooldown_timer - delta, 0.0)

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

	velocity.y += gravity * g_mul * delta

	if _grab_cooldown_timer <= 0.0 and _raycast_hits_group(grab, "GRAB"):
		current_grab_area = grab.get_collider()
		change_state(States.GRAB)
		return

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




#region CHUTE

# =====================  CHUTE  ===========================
var FALL_POINT: float = -1e9

func chute_enter() -> void:
	if previous_state != States.ATTACK_AIR:
		FALL_POINT = global_position.y
	if previous_state in [States.RUN, States.IDLE]:
		_coyote_timer = COYOTE_TIME
	else:
		_coyote_timer = 0.0
	animator.play("chute")


func chute_execute(delta: float) -> void:
	var direction := Input.get_axis("left_move", "right_move")
	_grab_cooldown_timer = max(_grab_cooldown_timer - delta, 0.0)
	_coyote_timer = max(_coyote_timer - delta, 0.0)
	_jump_buffer_timer = max(_jump_buffer_timer - delta, 0.0)

	if direction != 0:
		if previous_state != States.WALL_JUMP or absf(velocity.x) < 100.0:
			last_direction = sign(direction)
			point.scale.x = last_direction

	velocity.y += gravity * delta

	if direction != 0:
		velocity.x = lerp(velocity.x, direction * AIR_SPEED, AIR_CONTROL)
	else:
		velocity.x = lerp(velocity.x, 0.0, DECELERATION_RATE * delta)

	if _grab_cooldown_timer <= 0.0 and _raycast_hits_group(grab, "GRAB"):
		current_grab_area = grab.get_collider()
		change_state(States.GRAB)
		return

	if _raycast_hits_group(wall_right, "wall_jump", true):
		change_state(States.WALL_JUMP)
		return

	if is_on_floor():
		_handle_landing()


func chute_input(event: InputEvent) -> void:
	if Input.is_action_just_pressed("jump"):
		if _coyote_timer > 0.0:
			_coyote_timer = 0.0
			change_state(States.JUMP)
			return
		else:
			_jump_buffer_timer = JUMP_BUFFER_TIME
		
	if Input.is_action_just_pressed("light_attack"):
		change_state(States.ATTACK_AIR)
		return

	if _raycast_hits_group(climbcast_up, "CHUTE") \
		and Input.is_action_just_pressed("griffe"):
		change_state(States.CHUTE_GRIFFE)
		return

	var hit_r := _raycast_hits_group(climbcast_right, "CLIMB")
	var hit_l := _raycast_hits_group(climbcast_left,  "CLIMB")
	if hit_r and hit_l and Input.is_action_just_pressed("griffe"):
		change_state(States.CLIMB)
		return

	if _raycast_hits_group(climbcast_right, "GRIFFE") \
		and abs(velocity.x) > 0 \
		and Input.is_action_just_pressed("griffe"):
		change_state(States.WALL_GRIFFE)
		return


func chute_exit() -> void:
	pass
#endregion



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
enum WallJumpPhase { SLIDING, JUMPING }
var _wj_phase: WallJumpPhase = WallJumpPhase.SLIDING
const WALL_YJUMP := -500.0
const WALL_XJUMP := 290.0
const WALL_GLIDE_SPEED := 300.0

func wall_jump_enter():
	_flip_facing_on_wall()
	velocity = Vector2.ZERO
	_wj_phase = WallJumpPhase.SLIDING
	animator.play("wall_jump")

func wall_jump_execute(delta: float) -> void:
	match _wj_phase:
		WallJumpPhase.SLIDING:
			# Vérif mur (wall_left = côté mur car on a flippé)
			var on_wall := _raycast_hits_group(wall_left, "wall_jump", true)
			if not on_wall:
				change_state(States.CHUTE)
				return
			# Glissement
			velocity.y = lerp(velocity.y, WALL_GLIDE_SPEED, 0.05)
			if is_on_floor():
				change_state(States.IDLE)

		WallJumpPhase.JUMPING:
			velocity.y += gravity * delta
			if velocity.y > 0:
				change_state(States.CHUTE)

func wall_jump_input(event: InputEvent) -> void:
	if _wj_phase == WallJumpPhase.SLIDING:
		if Input.is_action_just_pressed("jump"):
			_wj_phase = WallJumpPhase.JUMPING
			var land_fx = instantiate_scene(WALL_JUMP_SCENE)
			land_fx.global_position = ANCRE_WALL.global_position
			land_fx.scale.x *= point.scale.x
			if land_fx is AnimatedSprite2D:
				land_fx.play()
			animator.play("jump")
			velocity.y = WALL_YJUMP
			velocity.x = WALL_XJUMP * last_direction
		elif Input.is_action_just_pressed("esquive"):
			change_state(States.CHUTE)

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
	else:
		# Pas de direction → on ne roll pas, retour IDLE
		call_deferred("change_state", States.IDLE)

func roll_execute(delta: float) -> void:
	velocity.y += gravity * delta

func roll_input(event: InputEvent) -> void:
	if Input.is_action_just_pressed("jump"):
		change_state(States.JUMP)

func roll_exit() -> void:
	pass

func roll_animation_finished() -> void:
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
const GRAB_LERP_SPEED := 600.0   # vitesse d'approche en pixels/sec
var _grab_locked := false          # true quand le perso a atteint le point

func grab_enter() -> void:
	velocity = Vector2.ZERO
	_grab_locked = false
	animator.play("chute")  # on garde l'anim de chute pendant l'approche

func grab_execute(delta: float) -> void:
	if not current_grab_area:
		change_state(States.CHUTE)
		return

	var grab_pos = current_grab_area.global_position
	var offset = ancre_grab.global_position - global_position
	var target_pos = grab_pos - offset

	if not _grab_locked:
		# Phase d'approche — le perso glisse vers le point
		global_position = global_position.move_toward(target_pos, GRAB_LERP_SPEED * delta)
		if global_position.distance_to(target_pos) < 2.0:
			global_position = target_pos
			_grab_locked = true
			animator.play("suspendu")  # anim seulement quand on est accroché
	else:
		# Phase accrochée — on reste collé
		global_position = target_pos

func grab_input(event: InputEvent) -> void:
	if Input.is_action_just_pressed("jump"):
		change_state(States.JUMP)
	elif Input.is_action_just_pressed("esquive"):
		change_state(States.CHUTE)

func grab_exit() -> void:
	_grab_locked = false
	current_grab_area = null
	_grab_cooldown_timer = GRAB_COOLDOWN
#endregion


# =====================  ATTAQUES  ===========================
# AMÉLIORATION: combo_buffered remplace le bool "combo"
# Chaque état d'attaque l'utilise de la même façon :
# - enter: reset combo_buffered = false
# - input: si le joueur appuie pendant l'anim principale → combo_buffered = true
# - animation_finished: si combo_buffered → chaîne, sinon → recovery (anim _r)

## Déplacement type RUN pendant les attaques : contrôle au stick, même vitesse
## et même inertie que run_execute. Pas de flip — le perso garde la direction
## de son attaque (il peut donc reculer en marche arrière pendant le coup).
func _attack_run_movement(delta: float) -> void:
	velocity.y += gravity * delta
	if not is_on_floor():
		change_state(States.CHUTE)
		return
	var direction := Input.get_axis("left_move", "right_move")
	var target_speed := float(direction) * GROUND_SPEED_ATTACK
	velocity.x = lerp(velocity.x, target_speed, 0.15)


## Le perso est-il en mouvement pendant une attaque ? (direction maintenue)
## Détermine si le combo peut sauter l'animation de retour (recovery) :
## en mouvement → enchaînement direct ; immobile → recovery obligatoire.
func _attack_is_moving() -> bool:
	return Input.get_axis("left_move", "right_move") != 0.0


func attack_light_1_enter() -> void:
	slash_attack.position = Vector2(98, -88)
	_flip_from_input()
	combo_buffered = false
	animator.play("attack")

func attack_light_1_execute(delta: float) -> void:
	_attack_run_movement(delta)

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
			if _attack_is_moving():
				change_state(States.ATTACK_LIGHT_2)  # en mouvement : cancel direct
			else:
				combo_buffered = true  # immobile : partira à la fin de la recovery
		elif Input.is_action_pressed("right_move") or Input.is_action_pressed("left_move"):
			change_state(States.RUN)
		elif Input.is_action_just_pressed("jump"):
			change_state(States.JUMP)

func attack_light_1_animation_finished() -> void:
	match animator.animation:
		"attack":
			# Skip de la recovery uniquement si le perso est en mouvement
			if combo_buffered and _attack_is_moving():
				change_state(States.ATTACK_LIGHT_2)
				return
			# Immobile : recovery obligatoire (le combo bufferisé reste en attente)
			animator.play("attack_r")
		"attack_r":
			if combo_buffered:
				change_state(States.ATTACK_LIGHT_2)
				return
			if Input.is_action_pressed("right_move") or Input.is_action_pressed("left_move"):
				change_state(States.RUN)
				return
			else:
				change_state(States.IDLE)

func attack_light_1_exit() -> void:
	combo_buffered = false




func attack_light_2_enter() -> void:
	_flip_from_input()
	combo_buffered = false
	animator.play("attack_02")


func attack_light_2_execute(delta: float) -> void:
	_attack_run_movement(delta)

func attack_light_2_input(event: InputEvent) -> void:
	if event.is_action("light_attack") \
		and event.is_pressed() \
		and not event.is_echo() \
		and animator.animation == "attack_02":
		combo_buffered = true
	if animator.animation == "attack_02_r":
		if Input.is_action_just_pressed("light_attack"):
			if _attack_is_moving():
				change_state(States.ATTACK_LIGHT_1)  # en mouvement : cancel direct
			else:
				combo_buffered = true  # immobile : partira à la fin de la recovery
		elif Input.is_action_pressed("right_move") or Input.is_action_pressed("left_move"):
			change_state(States.RUN)
		elif Input.is_action_just_pressed("jump"):
			change_state(States.JUMP)

func attack_light_2_animation_finished() -> void:
	match animator.animation:
		"attack_02":
			# Skip de la recovery uniquement si le perso est en mouvement
			if combo_buffered and _attack_is_moving():
				change_state(States.ATTACK_LIGHT_1)
				return
			# Immobile : recovery obligatoire (le combo bufferisé reste en attente)
			animator.play("attack_02_r")
		"attack_02_r":
			if combo_buffered:
				change_state(States.ATTACK_LIGHT_1)
				return
			if Input.is_action_pressed("right_move") or Input.is_action_pressed("left_move"):
				change_state(States.RUN)
				return
			else:
				change_state(States.IDLE)

func attack_light_2_exit() -> void:
	combo_buffered = false




func attack_light_3_enter() -> void:
	_flip_from_input()
	combo_buffered = false
	animator.play("attack_03")

func attack_light_3_execute(delta: float) -> void:
	velocity.y += gravity * delta
	if not is_on_floor():
		change_state(States.CHUTE)

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
	combo_buffered = false



func attack_lourde_enter() -> void:
	slash_attack.position = Vector2(-32, -92)
	animator.play("attack_lourde")

func attack_lourde_execute(delta: float) -> void:
	velocity.y += gravity * delta
	if not is_on_floor():
		change_state(States.CHUTE)

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
	pass



func attack_air_enter() -> void:
	animator.play("attack_air")
	if velocity.y < 0.0:
		velocity.y = 0.0  # stoppe la montée, la gravité prend le relais

func attack_air_execute(delta: float) -> void:
	velocity.y += gravity * delta

	if is_on_floor():
		_handle_landing()

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
	velocity.y += gravity * delta
	if not is_on_floor():
		change_state(States.CHUTE)

func heal_input(event: InputEvent) -> void:
	pass

func heal_animation_finished() -> void:
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




@export var HIT_STUN_TIME: float = 0.25
@export var HIT_KNOCK_X:  float = 1300.0
@export var HIT_KNOCK_Y:  float = -180.0
@export var HIT_X_DAMP:   float = 8.0

var _hit_elapsed := 0.0

func hit_enter() -> void:
	# Le déplacement est géré par le knockback superposé (_knock) ;
	# l'état HIT ne s'occupe que du stun et de l'animation
	velocity = Vector2.ZERO
	animator.play("hit")
	_hit_elapsed = 0.0


func hit_execute(delta: float) -> void:
	_hit_elapsed += delta
	velocity.y += gravity * delta

	if _hit_elapsed >= HIT_STUN_TIME:
		if is_on_floor():
			goto_state(States.IDLE)
		else:
			goto_state(States.CHUTE)

func hit_exit() -> void:
	velocity = Vector2.ZERO
	_knock = Vector2.ZERO  # fin du stun = contrôle rendu, aucune poussée résiduelle


# -------------------------------------------------
# DEAD — FIX: ajout de la gravité + blocage propre
# -------------------------------------------------
func dead_enter() -> void:
	animator.play("death")
	velocity.x = 0.0            # FIX: stoppe le mouvement horizontal



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
	if Input.is_action_just_pressed("jump"):
		print("okkkkkkkje suis mort")
		Player.hp = Player.MAX_HP
		Player.en = Player.MAX_en
		Loader.load_scene_with_loading(Loader._target_scene_path)

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

	if _drop_timer <= 0.0:
		change_state(States.CHUTE)
		return

	if is_on_floor():
		_handle_landing()

func drop_exit() -> void:
	set_collision_mask_value(ONEWAY_LAYER, true)
#endregion
