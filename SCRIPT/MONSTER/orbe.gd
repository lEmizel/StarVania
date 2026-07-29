# orbe.gd
extends BaseAI

enum States { IDLE, APPROACH, RETREAT, ATTACK, RETURN, DEAD }

@export var speed := 400.0
@export var speed_back := 100.0

const WAVE_FREQ := 0.5
const WAVE_AMP := 100.0


func _setup_states() -> void:
	_register_states(States)

func _start() -> void:
	max_hp = 230
	hp = 230
	attack_power = 95  # valeur réelle reprise de l'ancien animator (damage = 95)
	max_tracking_distance = 1500.0
	confort_zone_max = 120.0
	confort_zone_min = 20.0
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

	# Trop près — recule en priorité
	if dist < confort_zone_min:
		choice = pick_weighted([
			[States.ATTACK, 100],
			[States.RETREAT, 300],
		])

	# Dans la zone de confort — prudent
	elif dist < confort_zone_max:
		choice = pick_weighted([
			[States.ATTACK, 350],
			[States.RETREAT, 150],
			[States.IDLE, 200],
		])

	# Trop loin — approche
	else:
		choice = pick_weighted([
			[States.APPROACH, 650],
			[States.RETREAT, 80],
		])
		
	if choice == current_state:
		force_reenter_state()
	else:
		goto_state(choice)


# ============================================================
#  ÉTATS
# ============================================================

# --- IDLE (flottement sinusoïdal) ---

func idle_enter() -> void:
	animator.play("idle")
	velocity.x = 0.0

func idle_execute(_delta: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	velocity.y = sin(t * WAVE_FREQ * TAU) * WAVE_AMP
	velocity.x = 0.0
	if target:
		flip_toward(target.global_position.x)

func idle_animation_looped() -> void:
	if target:
		decide()


# --- APPROACH (pleine 2D, pas de gravité) ---

func approach_enter() -> void:
	animator.play("idle")

func approach_execute(_delta: float) -> void:
	if not target:
		goto_state(States.IDLE)
		return
	var dir := (target.global_position - global_position).normalized()
	velocity = dir * speed
	flip_toward(target.global_position.x)
	if distance_to_target() <= confort_zone_max:
		decide()


# --- RETREAT (s'éloigne en 2D avec biais vertical) ---

func retreat_enter() -> void:
	animator.play("idle")

func retreat_execute(_delta: float) -> void:
	if not target:
		goto_state(States.IDLE)
		return
	var dir := (global_position - target.global_position).normalized()
	dir.y -= 0.4
	dir = dir.normalized()
	velocity = dir * speed_back
	flip_toward(target.global_position.x)
	if distance_to_target() >= confort_zone_max:
		decide()


# --- ATTACK ---

func attack_enter() -> void:
	animator.play("attack")
	velocity = Vector2.ZERO
	if target:
		flip_toward(target.global_position.x)

func attack_execute(_delta: float) -> void:
	pass

func attack_animation_finished() -> void:
	decide()


# --- RETURN (retour en 2D) ---

func return_enter() -> void:
	animator.play("idle")

func return_execute(_delta: float) -> void:
	var dist := global_position.distance_to(initial_position)
	if dist < 20.0:
		velocity = Vector2.ZERO
		goto_state(States.IDLE)
		return
	var dir := (initial_position - global_position).normalized()
	velocity = dir * speed
	point.scale.x = sign(dir.x)


# --- DEAD ---

func dead_enter() -> void:
	animator.play("dead")
	velocity = Vector2.ZERO

func dead_execute(delta: float) -> void:
	# Tombe au sol après la mort
	velocity.y += gravity * delta
	velocity.x = 0.0
