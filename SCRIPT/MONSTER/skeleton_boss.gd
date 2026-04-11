# skeleton_boss.gd
extends BaseAI

enum States { IDLE, WALK, APPROACH, RETREAT, ATTACK_1, ATTACK_2, ATTACK_3, RETURN, HIT, DEAD }

@export var speed := 200.0
@export var speed_back := 340.0

var _shake_triggered := false


@onready var ancre_fx: Node2D = $POINT/ancreFX_
@onready var detection_vide: RayCast2D = $detection_vide

const FX_SHAKE_SCENE := preload("uid://bk7o3onokhfgt")


func _setup_states() -> void:
	_register_states(States)

func _start() -> void:
	max_hp = 600
	hp = 600
	attack_power = 15
	max_tracking_distance = 2000.0
	confort_zone_max = 200.0
	confort_zone_min = 60.0
	change_state(States.IDLE)

# ============================================================
#  HITBOX HELPERS
# ============================================================
func _disable_all_hitboxes() -> void:
	pass


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
	if current_state in [States.ATTACK_1, States.ATTACK_2]:
		return
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

	# Check si retreat/approach possible (sol derrière/devant)
	var dir_to_target := 1 if target and target.global_position.x > global_position.x else -1
	detection_vide.position.x = absf(detection_vide.position.x) * -dir_to_target
	detection_vide.force_raycast_update()
	var can_retreat := detection_vide.is_colliding()
	detection_vide.position.x = absf(detection_vide.position.x) * dir_to_target
	detection_vide.force_raycast_update()
	var can_approach := detection_vide.is_colliding()

	if dist < confort_zone_min:
		# Très proche → attaques rapides ou recul
		choice = pick_weighted([
			[States.ATTACK_1, 100],
			[States.ATTACK_2, 100],
			[States.RETREAT, 450 if can_retreat else 0],
			[States.IDLE, 20],
		])

	elif dist < confort_zone_max:
		# Zone de confort → mix d'attaques
		choice = pick_weighted([
			[States.ATTACK_1, 180],
			[States.ATTACK_2, 100],
			#[States.ATTACK_3, 80],
			[States.RETREAT, 100 if can_retreat else 0],
			[States.IDLE, 150],
		])

	else:
		# Loin → approche ou grosse attaque
		var in_dead_zone := target and absf(target.global_position.x - global_position.x) < HORIZONTAL_DEAD_ZONE
		if in_dead_zone or not can_approach:
			choice = pick_weighted([
				[States.ATTACK_2, 150],
				[States.RETREAT, 20 if can_retreat else 0],
				[States.IDLE, 100],
			])
		else:
			choice = pick_weighted([
				[States.APPROACH, 250],
				[States.ATTACK_2, 150],
				#[States.ATTACK_3, 40],
				[States.RETREAT, 20 if can_retreat else 0],
				[States.IDLE, 100],
			])

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
	_disable_all_hitboxes()

func idle_execute(delta: float) -> void:
	apply_gravity(delta)
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
	animator.play("walk_back")
	_retreat_timer = 0.0
	_retreat_duration = randf_range(0.5, 2.0)
	if target:
		flip_toward(target.global_position.x)
		detection_vide.position.x = absf(detection_vide.position.x) * -last_direction

func retreat_execute(delta: float) -> void:
	apply_gravity(delta)
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

# --- ATTACK_1 (rapide) ---
func attack_1_enter() -> void:
	animator.play("attack")
	velocity.x = 0.0
	if target:
		flip_toward(target.global_position.x)

func attack_1_execute(delta: float) -> void:
	apply_gravity(delta)

func attack_1_exit() -> void:
	_disable_all_hitboxes()

func attack_1_animation_finished() -> void:
	decide()

# --- ATTACK_2 (moyen) ---
func attack_2_enter() -> void:
	animator.play("attack_02")
	velocity.x = 0.0
	_shake_triggered = false
	if target:
		flip_toward(target.global_position.x)

func attack_2_execute(delta: float) -> void:
	apply_gravity(delta)
	if not _shake_triggered and animator.frame >= 5:
		_shake_triggered = true
		var cam = get_tree().get_first_node_in_group("Camera")
		if cam and cam.has_method("shake"):
			cam.shake(15.0, 4.0)
		# Effet visuel
		var fx = FX_SHAKE_SCENE.instantiate()
		fx.global_position = ancre_fx.global_position
		#fx.damage = attack_power
		get_tree().current_scene.add_child(fx)

func attack_2_exit() -> void:
	_disable_all_hitboxes()

func attack_2_animation_finished() -> void:
	decide()

# --- ATTACK_3 (lourde) ---
func attack_3_enter() -> void:
	animator.play("attack_03")
	velocity.x = 0.0
	if target:
		flip_toward(target.global_position.x)

func attack_3_execute(delta: float) -> void:
	apply_gravity(delta)

func attack_3_exit() -> void:
	_disable_all_hitboxes()

func attack_3_animation_finished() -> void:
	decide()

# --- RETURN ---
func return_enter() -> void:
	animator.play("walk")

func return_execute(delta: float) -> void:
	apply_gravity(delta)
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
	_disable_all_hitboxes()
	if position_x_attacker != null:
		var dir := 1 if (global_position.x - position_x_attacker) > 0 else -1
		velocity.x = dir * HIT_KNOCK_X
	velocity.y = HIT_KNOCK_Y
	position_x_attacker = null

func hit_execute(delta: float) -> void:
	_hit_elapsed += delta
	apply_gravity(delta)
	velocity.x = lerp(velocity.x, 0.0, clamp(HIT_X_DAMP * delta, 0.0, 1.0))
	if _hit_elapsed >= HIT_STUN_TIME:
		decide()

func hit_exit() -> void:
	velocity = Vector2.ZERO

# --- DEAD ---
func dead_enter() -> void:
	animator.play("dead")
	velocity.x = 0.0
	_disable_all_hitboxes()

func dead_execute(delta: float) -> void:
	if not is_on_floor():
		apply_gravity(delta)
	else:
		velocity.y = 0.0
