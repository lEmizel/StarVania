# skeleton_boss.gd
extends BaseAI

enum States { IDLE, APPROACH, ATTACK_1, ATTACK_2, ATTACK_3, RETURN, DEAD }

@export var speed := 200.0
## Nombre de boucles d'idle imposées entre chaque action du boss
## (tiré aléatoirement entre min et max à chaque pause ; 0 = enchaîne sans pause)
@export var idle_cycles_min := 0
@export var idle_cycles_max := 2

## Dégâts par attaque (chaque enter charge sa valeur dans attack_power,
## que l'animator applique au moment du coup)
@export var attack_1_damage: int = 1
@export var attack_2_damage: int = 1  # le slam / onde de choc

var _shake_triggered := false
var _idle_loops := 0
var _idle_loops_needed := 1


@onready var ancre_fx: Node2D = $POINT/ancreFX_
@onready var detection_vide: RayCast2D = $detection_vide

const FX_SHAKE_SCENE := preload("uid://bk7o3onokhfgt")


func _setup_states() -> void:
	_register_states(States)

func _start() -> void:
	max_hp = 600
	hp = 600
	max_tracking_distance = 2000.0
	confort_zone_max = 200.0
	confort_zone_min = 60.0
	HIT_KNOCK_X = 0.0  # le boss est inébranlable : aucun recul quand il est touché
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
		# Très proche → attaques rapides
		choice = pick_weighted([
			[States.ATTACK_1, 100],
			[States.ATTACK_2, 100],
			[States.IDLE, 20],
		])

	elif dist < confort_zone_max:
		# Zone de confort → mix d'attaques
		choice = pick_weighted([
			[States.ATTACK_1, 180],
			[States.ATTACK_2, 100],
			#[States.ATTACK_3, 80],
			[States.IDLE, 150],
		])

	else:
		# Loin → approche ou grosse attaque
		var in_dead_zone := target and absf(target.global_position.x - global_position.x) < HORIZONTAL_DEAD_ZONE
		if in_dead_zone or not can_approach:
			choice = pick_weighted([
				[States.ATTACK_2, 150],
				[States.IDLE, 100],
			])
		else:
			choice = pick_weighted([
				[States.APPROACH, 250],
				[States.ATTACK_2, 150],
				#[States.ATTACK_3, 40],
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
	_idle_loops = 0
	_idle_loops_needed = randi_range(idle_cycles_min, idle_cycles_max)
	# Tirage à 0 : pas de pause du tout — on décide dès la fin de la
	# transition (deferred, car on est encore en plein change_state)
	if _idle_loops_needed == 0 and target:
		call_deferred("decide")

func idle_execute(delta: float) -> void:
	apply_gravity(delta)
	if target:
		flip_toward(target.global_position.x)

func idle_animation_looped() -> void:
	_idle_loops += 1
	if target and _idle_loops >= _idle_loops_needed:
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
		# Pas d'idle après une marche : attaque immédiate, sinon le joueur
		# peut kiter le boss (s'éloigner → le frapper pendant sa pause → répéter)
		goto_state(pick_weighted([
			[States.ATTACK_1, 180],
			[States.ATTACK_2, 100],
		]))
		return
	detection_vide.position.x = absf(detection_vide.position.x) * last_direction
	if not detection_vide.is_colliding():
		velocity.x = 0.0
		goto_state(States.IDLE)
		return
	move_toward_target(speed)

# --- ATTACK_1 (rapide) ---
func attack_1_enter() -> void:
	attack_power = attack_1_damage
	animator.play("attack")
	velocity.x = 0.0
	if target:
		flip_toward(target.global_position.x)

func attack_1_execute(delta: float) -> void:
	apply_gravity(delta)

func attack_1_animation_finished() -> void:
	goto_state(States.IDLE)  # pause imposée avant la prochaine action

# --- ATTACK_2 (moyen) ---
func attack_2_enter() -> void:
	attack_power = attack_2_damage
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
		# Effet visuel + dégâts de l'onde de choc
		var fx = FX_SHAKE_SCENE.instantiate()
		fx.global_position = ancre_fx.global_position
		fx.damage = attack_2_damage
		get_tree().current_scene.add_child(fx)

func attack_2_animation_finished() -> void:
	goto_state(States.IDLE)  # pause imposée avant la prochaine action

# --- ATTACK_3 (lourde) ---
func attack_3_enter() -> void:
	animator.play("attack_03")
	velocity.x = 0.0
	if target:
		flip_toward(target.global_position.x)

func attack_3_execute(delta: float) -> void:
	apply_gravity(delta)

func attack_3_animation_finished() -> void:
	goto_state(States.IDLE)  # pause imposée avant la prochaine action

# --- RETURN ---
func return_enter() -> void:
	animator.play("walk")

func return_execute(delta: float) -> void:
	apply_gravity(delta)
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
		apply_gravity(delta)
	else:
		velocity.y = 0.0
