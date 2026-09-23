# skeleton_boss.gd
extends BaseAI

enum States { IDLE, PATROL, APPROACH, ATTACK_1, ATTACK_2, ATTACK_3, RETURN, DEAD }

@export var speed := 200.0
## Nombre de boucles d'idle imposées entre chaque action du boss
## (tiré aléatoirement entre min et max à chaque pause ; 0 = enchaîne sans pause)
@export var idle_cycles_min := 0
@export var idle_cycles_max := 2
## Temps mort de l'ATTAQUE 2 : tant qu'il court, seule l'attaque 1 sort —
## sans lui, l'attaque 2 (éligible dans toutes les branches de décision)
## sortait beaucoup trop souvent
@export var attack_2_cooldown := 3.0
## Distance sous laquelle la marche peut S'INTERROMPRE pour lancer
## l'attaque 2 (si elle est rechargée)
@export var attack_2_range := 250.0
## Abandon de frustration : cible visible mais inaccessible (autre
## plateforme…) pendant ce temps cumulé d'idle → il lâche l'aggro.
## Plus patient que les squelettes : ses pauses de combat normales
## (cycles d'idle) ne doivent JAMAIS le déclencher.
@export var abandon_time := 3.0
## Délai de grâce après un abandon avant de pouvoir re-détecter
@export var abandon_cooldown := 2.5
## Ronde quand personne en vue : même allure que la poursuite (speed)
@export var patrol_enabled := true
## Rythme de la ronde : durée moyenne de marche / de pause (±40 %)
@export var patrol_walk_time := 4.0
@export var patrol_pause_time := 2.0
var _blocked_time := 0.0
var _abandon_timer := 0.0
var _patrol_dir := 1
var _patrol_phase_timer := 0.0
var _patrol_pausing := false
var _a2_cd := 0.0


func _physics_process(delta: float) -> void:
	super(delta)
	_a2_cd = maxf(_a2_cd - delta, 0.0)


## Poids de l'attaque 2 dans les tirages : 0 pendant son temps mort
func _a2_poids(poids: int) -> int:
	return 0 if _a2_cd > 0.0 else poids

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
	# même correctif que le squelette : en montée de pente, le rayon de vide
	# naît dans la colline et rapportait un faux "trou devant"
	detection_vide.hit_from_inside = true
	max_hp = 600
	hp = 600
	max_tracking_distance = 2000.0
	confort_zone_max = 200.0
	confort_zone_min = 60.0
	inebranlable = true  # inébranlable : aucun recul, le joueur subit le contrecoup
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
		# cible perdue : le boss reste sur place (plus de retour au poste)
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
		# Très proche → attaques rapides
		choice = pick_weighted([
			[States.ATTACK_1, 100],
			[States.ATTACK_2, _a2_poids(100)],
			[States.IDLE, 20],
		])

	elif dist < confort_zone_max:
		# Zone de confort → mix d'attaques
		choice = pick_weighted([
			[States.ATTACK_1, 180],
			[States.ATTACK_2, _a2_poids(100)],
			#[States.ATTACK_3, 80],
			[States.IDLE, 150],
		])

	else:
		# Loin → approche ou grosse attaque
		var in_dead_zone := target and absf(target.global_position.x - global_position.x) < HORIZONTAL_DEAD_ZONE
		if in_dead_zone or not can_approach:
			choice = pick_weighted([
				[States.ATTACK_2, _a2_poids(150)],
				[States.IDLE, 100],
			])
		else:
			choice = pick_weighted([
				[States.APPROACH, 250],
				[States.ATTACK_2, _a2_poids(150)],
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
		# idle prolongé AVEC cible = frustration (cible inaccessible) :
		# les vraies actions (approche, attaques) remettent le compteur à zéro
		_blocked_time += delta
		if _blocked_time >= abandon_time:
			_blocked_time = 0.0
			_abandon_timer = abandon_cooldown
			target = null
	else:
		# re-détection : un joueur DÉJÀ dans le cône ne ré-émet jamais
		# body_entered → re-scan, passé le délai de grâce
		_abandon_timer = maxf(_abandon_timer - delta, 0.0)
		if _abandon_timer <= 0.0:
			_rescan_vision()


# _rescan_vision() : désormais celui de BASE_IA (tout ennemi de camp, le plus
# proche). La copie locale ne cherchait que le joueur.


## Décrochage (hors-vue de BASE_IA) : même délai de grâce que la frustration
func _oublier_cible() -> void:
	_blocked_time = 0.0
	_abandon_timer = abandon_cooldown
	target = null

func idle_animation_looped() -> void:
	_idle_loops += 1
	if target and _idle_loops >= _idle_loops_needed:
		decide()
	elif target == null and patrol_enabled:
		# personne en vue : après une boucle d'idle, il part en ronde
		goto_state(States.PATROL)


# --- PATROL (ronde pesante entre les obstacles) ---

func patrol_enter() -> void:
	animator.play("walk")
	_patrol_dir = 1 if point.scale.x >= 0.0 else -1
	_patrol_pausing = false
	_patrol_phase_timer = randf_range(patrol_walk_time * 0.6, patrol_walk_time * 1.4)

func patrol_execute(delta: float) -> void:
	apply_gravity(delta)
	# re-détection en ronde, passé le délai de grâce
	_abandon_timer = maxf(_abandon_timer - delta, 0.0)
	if target == null and _abandon_timer <= 0.0:
		_rescan_vision()
	# un joueur apparaît → retour au cerveau de combat
	if target:
		velocity.x = 0.0
		decide()
		return
	# respiration de ronde : alternance marche ↔ pause en idle
	_patrol_phase_timer -= delta
	if _patrol_pausing:
		velocity.x = 0.0
		if _patrol_phase_timer <= 0.0:
			_patrol_pausing = false
			_patrol_phase_timer = randf_range(patrol_walk_time * 0.6, patrol_walk_time * 1.4)
			animator.play("walk")
		return
	if _patrol_phase_timer <= 0.0:
		_patrol_pausing = true
		_patrol_phase_timer = randf_range(patrol_pause_time * 0.6, patrol_pause_time * 1.4)
		animator.play("idle")
		velocity.x = 0.0
		return
	# trou devant ? piques devant ? vrai mur de face ? → demi-tour
	var mur_devant := false
	if is_on_wall():
		var n := get_wall_normal()
		mur_devant = absf(n.x) > 0.85 and signf(n.x) == -signf(float(_patrol_dir))
	detection_vide.position.x = absf(detection_vide.position.x) * _patrol_dir
	detection_vide.force_raycast_update()
	if not detection_vide.is_colliding() or mur_devant \
		or danger_devant(detection_vide):
		_patrol_dir = -_patrol_dir
	velocity.x = _patrol_dir * speed  # même allure qu'en poursuite
	last_direction = _patrol_dir
	point.scale.x = _patrol_dir

# --- APPROACH ---
func approach_enter() -> void:
	animator.play("walk")
	_blocked_time = 0.0  # la cible redevient accessible : frustration oubliée

func approach_execute(delta: float) -> void:
	apply_gravity(delta)
	if not target:
		goto_state(States.IDLE)
		return
	# la marche peut S'INTERROMPRE à tout moment pour l'attaque 2 : dès que
	# la cible passe sous attack_2_range et que le temps mort est écoulé
	if _a2_cd <= 0.0 and distance_to_target() <= attack_2_range:
		velocity.x = 0.0
		goto_state(States.ATTACK_2)
		return
	if distance_to_target() <= confort_zone_max:
		velocity.x = 0.0
		# Pas d'idle après une marche : attaque immédiate, sinon le joueur
		# peut kiter le boss (s'éloigner → le frapper pendant sa pause → répéter)
		goto_state(pick_weighted([
			[States.ATTACK_1, 180],
			[States.ATTACK_2, _a2_poids(100)],
		]))
		return
	detection_vide.position.x = absf(detection_vide.position.x) * last_direction
	if not detection_vide.is_colliding() or danger_devant(detection_vide):
		velocity.x = 0.0
		goto_state(States.IDLE)
		return
	move_toward_target(speed)

# --- ATTACK_1 (rapide) ---
func attack_1_enter() -> void:
	attack_power = attack_1_damage
	animator.play("attack")
	velocity.x = 0.0
	_blocked_time = 0.0  # on se bat : frustration oubliée
	if target:
		flip_toward(target.global_position.x)

func attack_1_execute(delta: float) -> void:
	apply_gravity(delta)

func attack_1_animation_finished() -> void:
	goto_state(States.IDLE)  # pause imposée avant la prochaine action

# --- ATTACK_2 (moyen) ---
func attack_2_enter() -> void:
	_a2_cd = attack_2_cooldown  # arme le temps mort de l'attaque 2
	_blocked_time = 0.0  # on se bat : frustration oubliée
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
		# camps : l'onde porte le camp du boss (traverse ses alliés, PV aux ennemis)
		fx.faction = faction
		fx.degats_monstres = degats_monstres
		fx.tireur = self
		get_tree().current_scene.add_child(fx)

func attack_2_animation_finished() -> void:
	goto_state(States.IDLE)  # pause imposée avant la prochaine action

# --- ATTACK_3 (lourde) ---
func attack_3_enter() -> void:
	animator.play("attack_03")
	velocity.x = 0.0
	_blocked_time = 0.0  # on se bat : frustration oubliée
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
