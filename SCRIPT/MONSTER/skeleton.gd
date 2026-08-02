# skeleton.gd
extends BaseAI

enum States { IDLE, PATROL, APPROACH, ATTACK, RETURN, DEAD }

@export var speed := 280.0
## Temps de réflexion en idle avant la prochaine décision (indépendant
## de la durée de l'animation d'idle, qui fait 0.75s par boucle)
@export var reaction_time := 0.3
## Ronde quand aucun joueur en vue : marche jusqu'au trou (ou mur) le plus
## proche à gauche, demi-tour, jusqu'à celui de droite, etc.
@export var patrol_enabled := true
@export var patrol_speed := 140.0
var _idle_wait := 0.0
var _patrol_dir := 1
@onready var detection_vide: RayCast2D = $detection_vide


func _setup_states() -> void:
	_register_states(States)

func _start() -> void:
	max_hp = 180
	hp = 180
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
		# cible perdue : on reste sur place (plus de retour au poste),
		# l'IDLE relancera la ronde s'il n'y a personne
		goto_state(States.IDLE)
		return

	var dist := distance_to_target()
	var choice: int

	# Check si approach possible (sol devant)
	var dir_to_target := 1 if target and target.global_position.x > global_position.x else -1
	detection_vide.position.x = absf(detection_vide.position.x) * dir_to_target
	detection_vide.force_raycast_update()
	var can_approach := detection_vide.is_colliding() and not danger_devant(detection_vide)

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
	_idle_wait = 0.0

func idle_execute(delta: float) -> void:
	velocity.y += gravity * delta
	if target:
		flip_toward(target.global_position.x)
		_idle_wait += delta
		if _idle_wait >= reaction_time:
			decide()
	elif patrol_enabled:
		# personne en vue : après le temps de réflexion, on part en ronde
		_idle_wait += delta
		if _idle_wait >= reaction_time:
			goto_state(States.PATROL)


# --- PATROL (ronde entre les deux trous/murs les plus proches) ---

func patrol_enter() -> void:
	animator.play("walk")
	# repart dans la direction du regard actuel
	_patrol_dir = 1 if point.scale.x >= 0.0 else -1

func patrol_execute(delta: float) -> void:
	velocity.y += gravity * delta
	# un joueur apparaît → on rend la main au cerveau de combat
	if target:
		velocity.x = 0.0
		decide()
		return
	# trou devant ? piques devant ? mur devant ? → demi-tour
	detection_vide.position.x = absf(detection_vide.position.x) * _patrol_dir
	detection_vide.force_raycast_update()
	if not detection_vide.is_colliding() or is_on_wall() \
		or danger_devant(detection_vide):
		_patrol_dir = -_patrol_dir
	velocity.x = _patrol_dir * patrol_speed
	last_direction = _patrol_dir
	point.scale.x = _patrol_dir


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
	if not detection_vide.is_colliding() or danger_devant(detection_vide):
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
	# Même garde-fou que APPROACH : pas de sol devant → on s'arrête
	detection_vide.position.x = absf(detection_vide.position.x) * dir
	detection_vide.force_raycast_update()
	if not detection_vide.is_colliding():
		velocity.x = 0.0
		goto_state(States.IDLE)
		return
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
