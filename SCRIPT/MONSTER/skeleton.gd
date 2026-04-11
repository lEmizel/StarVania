# skeleton.gd
extends BaseAI

enum States { IDLE, WALK, APPROACH, RETREAT, ATTACK, RETURN, HIT, DEAD }

@export var speed := 280.0
@export var speed_back := 200.0
@onready var detection_vide: RayCast2D = $detection_vide


func _setup_states() -> void:
	_register_states(States)

func _start() -> void:
	max_hp = 180
	hp = 180
	attack_power = 7
	max_tracking_distance = 1500.0
	confort_zone_max = 150.0
	confort_zone_min = 30.0
	change_state(States.IDLE)


# ============================================================
#  DÉGÂTS (overrides)
# ============================================================

func _is_dead() -> bool:
	return current_state == States.DEAD

func _is_hit() -> bool:
	return current_state == States.HIT

func _on_dead() -> void:
	change_state(States.DEAD)

func _on_hit() -> void:
	change_state(States.HIT)


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

	# Check si retreat possible (sol derrière)
	var dir_to_target := 1 if target and target.global_position.x > global_position.x else -1
	detection_vide.position.x = absf(detection_vide.position.x) * -dir_to_target
	detection_vide.force_raycast_update()
	var can_retreat := detection_vide.is_colliding()
	# Check si approach possible (sol devant)
	detection_vide.position.x = absf(detection_vide.position.x) * dir_to_target
	detection_vide.force_raycast_update()
	var can_approach := detection_vide.is_colliding()

	if dist < confort_zone_min:
		choice = pick_weighted([
			[States.ATTACK, 350],
			[States.RETREAT, 30 if can_retreat else 0],
			[States.IDLE, 10],
		])

	elif dist < confort_zone_max:
		choice = pick_weighted([
			[States.ATTACK, 200],
			[States.RETREAT, 20 if can_retreat else 0],
			[States.IDLE, 10],
		])

	else:
		var in_dead_zone := target and absf(target.global_position.x - global_position.x) < HORIZONTAL_DEAD_ZONE
		if in_dead_zone or not can_approach:
			choice = pick_weighted([
				[States.RETREAT, 20 if can_retreat else 0],
				[States.IDLE, 50],
			])
		else:
			choice = pick_weighted([
				[States.APPROACH, 250],
				[States.RETREAT, 20 if can_retreat else 0],
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


# --- RETREAT ---
var _retreat_timer := 0.0
var _retreat_duration := 0.0

func retreat_enter() -> void:
	animator.play("walk")
	_retreat_timer = 0.0
	_retreat_duration = randf_range(0.5, 2.0)
	if target:
		flip_toward(target.global_position.x)
		detection_vide.position.x = absf(detection_vide.position.x) * -last_direction

func retreat_execute(delta: float) -> void:
	velocity.y += gravity * delta
	_retreat_timer += delta
	if not target or _retreat_timer >= _retreat_duration:
		decide()
		return
	detection_vide.position.x = absf(detection_vide.position.x) * -last_direction
	if not detection_vide.is_colliding():
		velocity.x = 0.0
		goto_state(States.IDLE)
		return
	velocity.x = -last_direction * speed_back


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


# --- HIT ---

func hit_enter() -> void:
	animator.play("hit")
	velocity = Vector2.ZERO
	_hit_elapsed = 0.0

	if position_x_attacker != null:
		var dir := 1 if (global_position.x - position_x_attacker) > 0 else -1
		velocity.x = dir * HIT_KNOCK_X
	velocity.y = HIT_KNOCK_Y
	position_x_attacker = null

func hit_execute(delta: float) -> void:
	_hit_elapsed += delta
	velocity.y += gravity * delta
	velocity.x = lerp(velocity.x, 0.0, clamp(HIT_X_DAMP * delta, 0.0, 1.0))

	if _hit_elapsed >= HIT_STUN_TIME:
		decide()

func hit_exit() -> void:
	velocity = Vector2.ZERO


# --- DEAD ---

func dead_enter() -> void:
	animator.play("dead")
	velocity.x = 0.0

func dead_execute(delta: float) -> void:
	if not is_on_floor():
		velocity.y += gravity * delta
	else:
		velocity.y = 0.0
