# skeleton.gd
extends BaseAI

enum States { IDLE, APPROACH, ATTACK, RETURN, DEAD }

@export var speed := 280.0
@onready var detection_vide: RayCast2D = $detection_vide


func _setup_states() -> void:
	_register_states(States)

func _start() -> void:
	max_hp = 180
	hp = 180
	attack_power = 95  # valeur réelle reprise de l'ancien animator (damage = 95)
	max_tracking_distance = 1500.0
	confort_zone_max = 150.0
	confort_zone_min = 30.0
	change_state(States.IDLE)


# ============================================================
#  DÉGÂTS (overrides)
# ============================================================

func _is_dead() -> bool:
	return current_state == States.DEAD

func _on_dead() -> void:
	change_state(States.DEAD)


# ============================================================
#  DÉCISION
# ============================================================

func decide() -> void:
	if current_state == States.DEAD:
		return
	if not check_tracking():
		goto_state(States.RETURN)
		return

	var dist := distance_to_target()
	var choice: int

	# Check si approach possible (sol devant)
	var dir_to_target := 1 if target and target.global_position.x > global_position.x else -1
	detection_vide.position.x = absf(detection_vide.position.x) * dir_to_target
	detection_vide.force_raycast_update()
	var can_approach := detection_vide.is_colliding()

	if dist < confort_zone_min:
		choice = pick_weighted([
			[States.ATTACK, 350],
			[States.IDLE, 10],
		])

	elif dist < confort_zone_max:
		choice = pick_weighted([
			[States.ATTACK, 200],
			[States.IDLE, 10],
		])

	else:
		var in_dead_zone := target and absf(target.global_position.x - global_position.x) < HORIZONTAL_DEAD_ZONE
		if in_dead_zone or not can_approach:
			choice = States.IDLE
		else:
			choice = pick_weighted([
				[States.APPROACH, 250],
				[States.IDLE, 50],
			])

	# nouveau :
	if choice == current_state:
		force_reenter_state()
	else:
		goto_state(choice)

# ============================================================
#  ÉTATS
# ============================================================

# --- IDLE ---

func idle_enter() -> void:
	animator.play("idle")
	velocity.x = 0.0

func idle_execute(delta: float) -> void:
	velocity.y += gravity * delta
	if target:
		flip_toward(target.global_position.x)

func idle_animation_looped() -> void:
	if target:
		decide()


# --- APPROACH ---

func approach_enter() -> void:
	animator.play("walk")

func approach_execute(delta: float) -> void:
	apply_gravity(delta)
	if not target:
		goto_state(States.IDLE)
		return
	if absf(target.global_position.x - global_position.x) < HORIZONTAL_DEAD_ZONE:
		velocity.x = 0.0
		goto_state(States.IDLE)
		return
	if distance_to_target() <= confort_zone_max:
		velocity.x = 0.0
		decide()
		return
	detection_vide.position.x = absf(detection_vide.position.x) * last_direction
	if not detection_vide.is_colliding():
		velocity.x = 0.0
		goto_state(States.IDLE)
		return
	move_toward_target(speed)


# --- ATTACK ---

func attack_enter() -> void:
	animator.play("attack")
	velocity.x = 0.0
	if target:
		flip_toward(target.global_position.x)

func attack_execute(delta: float) -> void:
	velocity.y += gravity * delta

func attack_animation_finished() -> void:
	decide()


# --- RETURN ---

func return_enter() -> void:
	animator.play("walk")

func return_execute(delta: float) -> void:
	velocity.y += gravity * delta
	var dir := 1 if initial_position.x > global_position.x else -1
	velocity.x = dir * speed
	point.scale.x = dir
	if global_position.distance_to(initial_position) < 20.0:
		velocity.x = 0.0
		goto_state(States.IDLE)


# --- DEAD ---

func dead_enter() -> void:
	animator.play("dead")
	velocity.x = 0.0

func dead_execute(delta: float) -> void:
	if not is_on_floor():
		velocity.y += gravity * delta
	else:
		velocity.y = 0.0
