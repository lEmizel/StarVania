# xeno.gd — cerveau du squelette + ATTAQUE LANGUE à distance (bouche
# intérieure) : sur la bande intermédiaire, il tire la langue au lieu
# d'approcher — impossible de le kiter à mi-distance, et il riposte
# même bloqué au bord d'une plateforme.
extends BaseAI

enum States { IDLE, PATROL, APPROACH, ATTACK, ATTACK_LANGUE, RETURN, DEAD }

@export var speed := 280.0
## Temps de réflexion en idle avant la prochaine décision
@export var reaction_time := 0.3
## Ronde quand aucun joueur en vue
@export var patrol_enabled := true
@export var patrol_speed := 140.0
## Rythme de la ronde : durée moyenne de marche avant une pause, et durée
## moyenne de la pause en idle (chaque phase varie de ±40 % — deux gardes
## ne sont jamais synchrones)
@export var patrol_walk_time := 3.5
@export var patrol_pause_time := 1.4
var _patrol_phase_timer := 0.0
var _patrol_pausing := false
## Abandon temporaire (cible visible mais inaccessible)
@export var abandon_time := 1.5
## Délai de grâce après un abandon avant re-détection
@export var abandon_cooldown := 2.5
## Distance d'OUBLI : au-delà, il lâche sa cible
@export var tracking_distance := 900.0
## Bande de l'ATTAQUE LANGUE : déclenchable quand la cible est entre ces
## deux distances (px). À caler sur la longueur réelle de ta hitbox.
## Bande de tir de la langue. RÈGLES ALIGNÉES SUR LE SQUELETTE (18 sept. 2026) :
## il s'en sert dès qu'il a une cible à portée, sans zone morte.
##   • 160 = juste après `confort_zone_max` (150), donc plus de trou entre le
##     corps à corps et la langue, où il se contentait d'avancer sans rien faire ;
##   • 530 = la VRAIE portée de sa hitbox de langue (le polygone va jusqu'à
##     558 px), au lieu de 700 où il tirait dans le vide.
@export var langue_min := 160.0
@export var langue_max := 530.0
## Temps mort entre deux attaques langue : il ne les enchaîne jamais —
## entre deux tirs il approche ou respire
@export var langue_cooldown := 2.5   # la cadence du sort du squelette
var _langue_cd := 0.0
var _idle_wait := 0.0
var _patrol_dir := 1
var _blocked_time := 0.0
var _abandon_timer := 0.0
@onready var detection_vide: RayCast2D = $detection_vide


func _setup_states() -> void:
	_register_states(States)


func _physics_process(delta: float) -> void:
	super(delta)
	_langue_cd = maxf(_langue_cd - delta, 0.0)

func _start() -> void:
	detection_vide.hit_from_inside = true
	max_hp = 252   # 180 +40 % (320 essaye le 18 sept. 2026 : trop fort)
	hp = 252
	max_tracking_distance = tracking_distance
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


## Décrochage (hors-vue géré par BASE_IA) : délai de grâce anti re-scan
func _oublier_cible() -> void:
	_blocked_time = 0.0
	_abandon_timer = abandon_cooldown
	target = null


# ============================================================
#  DÉCISION
# ============================================================

func decide() -> void:
	if current_state == States.DEAD:
		return
	if not check_tracking():
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

	elif dist >= langue_min and dist <= langue_max:
		# bande de la LANGUE : l'attaque à distance domine quand elle est
		# rechargée — pendant le cooldown, il approche ou respire
		if _langue_cd > 0.0:
			choice = pick_weighted([
				[States.APPROACH, 150 if can_approach else 0],
				[States.IDLE, 150],
			])
		else:
			# rechargée : elle part presque à coup sûr, comme le squelette qui
			# lance son sort dès que son temps mort est écoulé
			choice = pick_weighted([
				[States.ATTACK_LANGUE, 700],
				[States.APPROACH, 60 if can_approach else 0],
				[States.IDLE, 40],
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
		_blocked_time += delta
		if _blocked_time >= abandon_time:
			_blocked_time = 0.0
			_abandon_timer = abandon_cooldown
			target = null
			goto_state(States.PATROL)
			return
		_idle_wait += delta
		if _idle_wait >= reaction_time:
			decide()
	else:
		_abandon_timer = maxf(_abandon_timer - delta, 0.0)
		if _abandon_timer <= 0.0:
			_rescan_vision()
		if patrol_enabled:
			_idle_wait += delta
			if _idle_wait >= reaction_time:
				goto_state(States.PATROL)


# _rescan_vision() : désormais celui de BASE_IA (tout ennemi de camp, le plus
# proche). La copie locale ne cherchait que le joueur.


# --- PATROL (ronde entre les deux trous/murs les plus proches) ---

func patrol_enter() -> void:
	animator.play("walk")
	_patrol_dir = 1 if point.scale.x >= 0.0 else -1
	_patrol_pausing = false
	_patrol_phase_timer = randf_range(patrol_walk_time * 0.6, patrol_walk_time * 1.4)

func patrol_execute(delta: float) -> void:
	velocity.y += gravity * delta
	_abandon_timer = maxf(_abandon_timer - delta, 0.0)
	if target == null and _abandon_timer <= 0.0:
		_rescan_vision()
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
	var mur_devant := false
	if is_on_wall():
		var n := get_wall_normal()
		mur_devant = absf(n.x) > 0.85 and signf(n.x) == -signf(float(_patrol_dir))
	detection_vide.position.x = absf(detection_vide.position.x) * _patrol_dir
	detection_vide.force_raycast_update()
	if not detection_vide.is_colliding() or mur_devant \
		or danger_devant(detection_vide):
		_patrol_dir = -_patrol_dir
	velocity.x = _patrol_dir * patrol_speed
	last_direction = _patrol_dir
	point.scale.x = _patrol_dir


# --- APPROACH ---

func approach_enter() -> void:
	animator.play("walk")
	_blocked_time = 0.0

func approach_execute(delta: float) -> void:
	apply_gravity(delta)
	if not target:
		goto_state(States.IDLE)
		return
	if absf(target.global_position.x - global_position.x) < HORIZONTAL_DEAD_ZONE:
		velocity.x = 0.0
		goto_state(States.IDLE)
		return
	# en pleine approche, la langue part À TOUT MOMENT si la cible est dans
	# la bande autorisée et que le tir est rechargé — l'approche n'est
	# jamais un tunnel jusqu'au corps-à-corps
	var dist := distance_to_target()
	if _langue_cd <= 0.0 and dist >= langue_min and dist <= langue_max:
		velocity.x = 0.0
		goto_state(States.ATTACK_LANGUE)
		return
	if dist <= confort_zone_max:
		velocity.x = 0.0
		decide()
		return
	detection_vide.position.x = absf(detection_vide.position.x) * last_direction
	if not detection_vide.is_colliding() or danger_devant(detection_vide):
		velocity.x = 0.0
		goto_state(States.IDLE)
		return
	move_toward_target(speed)


# --- ATTACK (corps à corps) ---

func attack_enter() -> void:
	animator.play("attack")
	velocity.x = 0.0
	_blocked_time = 0.0
	if target:
		flip_toward(target.global_position.x)

func attack_execute(delta: float) -> void:
	velocity.y += gravity * delta

func attack_animation_finished() -> void:
	# l'attaque cac se joue en 2 temps OBLIGATOIRES : "attack" (préparation)
	# puis "attack_2" (frappe + retour) — le cerveau ne reprend la main
	# qu'après la seconde partie
	if animator.animation == "attack":
		animator.play("attack_2")
		return
	decide()


# --- ATTACK_LANGUE (bouche intérieure, à distance) ---

func attack_langue_enter() -> void:
	animator.play("attack_langue")
	velocity.x = 0.0
	_blocked_time = 0.0
	_langue_cd = langue_cooldown  # pas de re-tir avant le temps mort
	if target:
		flip_toward(target.global_position.x)

func attack_langue_execute(delta: float) -> void:
	velocity.y += gravity * delta

func attack_langue_animation_finished() -> void:
	decide()


# --- RETURN (plus jamais déclenché : conservé pour le contrat d'états) ---

func return_enter() -> void:
	animator.play("walk")

func return_execute(delta: float) -> void:
	velocity.y += gravity * delta
	var dir := 1 if initial_position.x > global_position.x else -1
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
