# larve_pique.gd — copie du cerveau du squelette, à faire diverger librement
# (stats, poids de décision, comportements propres à la larve)
extends BaseAI

enum States { IDLE, PATROL, APPROACH, ATTACK, RETURN, DEAD }

@export var max_hp_export := 120
@export var speed := 240.0
## Temps de réflexion en idle avant la prochaine décision
@export var reaction_time := 0.3
## Ronde quand aucun joueur en vue : marche jusqu'au trou (ou mur) le plus
## proche à gauche, demi-tour, jusqu'à celui de droite, etc.
@export var patrol_enabled := true
@export var patrol_speed := 120.0
## Abandon temporaire : si la cible reste inaccessible (bloqué à un bord…)
## pendant ce temps cumulé d'idle frustré, la larve lâche l'aggro et
## reprend sa ronde — sa vision la re-déclenchera plus tard
@export var abandon_time := 1.5
## Délai de grâce après un abandon avant de pouvoir re-détecter le joueur
## (sinon re-aggro instantané = yo-yo). Un coup reçu réveille toujours.
@export var abandon_cooldown := 2.5
## Distance d'OUBLI : au-delà, la larve lâche sa cible (et son re-scan
## de vision ne peut pas la reprendre). Réglable par instance.
@export var tracking_distance := 900.0
## Vitesse d'alignement du corps sur la pente (plus grand = bascule plus vive)
@export var SLOPE_TILT_SPEED := 12.0
## Frame de l'anim d'attaque à partir de laquelle la larve se roule en
## BOULE DE PIQUES : invulnérable et inébranlable (le joueur qui frappe
## subit le contrecoup, comme contre le boss)
@export var ARMOR_FRAME := 4
var _tilt_prev_sign := 1.0
var _offset_base_y := 0.0  # offset du sprite à plat (capturé au démarrage)
@onready var _collision: CollisionShape2D = $Collision
var _idle_wait := 0.0
var _patrol_dir := 1
var _blocked_time := 0.0
var _abandon_timer := 0.0
@onready var detection_vide: RayCast2D = $detection_vide


func _physics_process(delta: float) -> void:
	super(delta)
	_coller_a_la_pente(delta)


## Décrochage (hors-vue géré par BASE_IA) : on y ajoute le délai de grâce
## anti re-scan, comme pour l'abandon de frustration
func _oublier_cible() -> void:
	_blocked_time = 0.0
	_abandon_timer = abandon_cooldown
	target = null


## La larve épouse visuellement la pente : le sprite s'incline selon la
## normale du sol (les collisions, elles, restent droites). La pente est
## lue par un RAYON sous le corps — is_on_floor() clignote quand on marche
## en descente (micro-sautillements) et faisait retomber l'inclinaison.
func _coller_a_la_pente(delta: float) -> void:
	var cible := 0.0
	var q := PhysicsRayQueryParameters2D.create(
		global_position + Vector2(0.0, -20.0),
		global_position + Vector2(0.0, 70.0),
		collision_mask | 1)
	q.exclude = [get_rid()]
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	if hit:
		cible = (hit.normal as Vector2).angle() + PI * 0.5
	# comble le JOUR laissé par la collision ronde en pente : un cercle ne
	# touche la surface qu'en un point décalé, le ventre flotte de
	# r·(1/cos θ − 1) px — on enfonce le sprite d'exactement autant
	var jour := 0.0
	if _collision.shape is CapsuleShape2D and absf(cible) > 0.01:
		jour = _collision.shape.radius * (1.0 / cos(absf(cible)) - 1.0)
	animator.offset.y = _offset_base_y + jour / animator.scale.y
	# sous un POINT retourné (scale.x = -1), une rotation s'affiche inversée
	var s := signf(point.scale.x)
	if s == 0.0:
		s = _tilt_prev_sign
	if s != _tilt_prev_sign:
		# demi-tour : on convertit la rotation en cours pour que
		# l'inclinaison AFFICHÉE ne saute pas d'un coup
		animator.rotation = -animator.rotation
		_tilt_prev_sign = s
	cible *= s
	animator.rotation = lerp_angle(animator.rotation, cible, SLOPE_TILT_SPEED * delta)


func _setup_states() -> void:
	_register_states(States)

func _start() -> void:
	# en MONTÉE de pente, l'origine du rayon de vide se retrouve DANS la
	# colline : sans hit_from_inside, faux "trou devant" → demi-tour
	detection_vide.hit_from_inside = true
	# ACCROCHE AU SOL : en descente, sans snap, le corps quitte la pente à
	# chaque frame et retombe (sautillement perpétuel = jamais en contact).
	# 48 px de snap le replaquent à la surface même à pleine vitesse.
	floor_snap_length = 48.0
	# vitesse constante le long de la pente (pas d'accélération en descente)
	floor_constant_speed = true
	# pivot d'inclinaison AU SOL : le nœud du sprite descend au niveau des
	# pieds et le dessin remonte d'autant (rendu identique à plat) — la
	# rotation de pente tourne alors autour du point de contact, le corps
	# épouse la pente au lieu de léviter d'un côté
	animator.offset.y += animator.position.y / animator.scale.y
	animator.position.y = 0.0
	_offset_base_y = animator.offset.y
	max_hp = max_hp_export
	hp = max_hp_export
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


## Boule de piques active/inactive : les deux traits de BASE_IA d'un coup
## (invulnérable = zéro dégât/feedback, inébranlable = contrecoup du joueur)
func _set_blindee(on: bool) -> void:
	invulnerable = on
	inebranlable = on


# ============================================================
#  DÉCISION
# ============================================================

func decide() -> void:
	if current_state == States.DEAD:
		return
	if not check_tracking():
		# cible perdue : on reste sur place, l'IDLE relancera la ronde
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
		# idle AVEC cible = frustration : au bout d'abandon_time cumulé,
		# on lâche l'affaire et on reprend la ronde
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
		# re-détection : un joueur DÉJÀ dans la zone de vision ne re-émet
		# jamais body_entered → on re-scanne, passé le délai de grâce
		_abandon_timer = maxf(_abandon_timer - delta, 0.0)
		if _abandon_timer <= 0.0:
			_rescan_vision()
		if patrol_enabled:
			_idle_wait += delta
			if _idle_wait >= reaction_time:
				goto_state(States.PATROL)


## Re-scan de la zone de vision (les corps déjà présents n'émettent pas
## de signal d'entrée) — borné par la distance d'oubli : un joueur trop
## loin ne peut pas être re-verrouillé même s'il reste dans le cône
func _rescan_vision() -> void:
	for b in vision.get_overlapping_bodies():
		if b.is_in_group("Player") \
			and b.global_position.distance_to(global_position) <= max_tracking_distance:
			target = b
			return


# --- PATROL (ronde entre les deux trous/murs les plus proches) ---

func patrol_enter() -> void:
	animator.play("walk")
	_patrol_dir = 1 if point.scale.x >= 0.0 else -1

func patrol_execute(delta: float) -> void:
	velocity.y += gravity * delta
	_abandon_timer = maxf(_abandon_timer - delta, 0.0)
	if target == null and _abandon_timer <= 0.0:
		_rescan_vision()
	if target:
		velocity.x = 0.0
		decide()
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
	velocity.x = _patrol_dir * patrol_speed
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
	_set_blindee(false)
	_blocked_time = 0.0  # on se bat : frustration oubliée
	if target:
		flip_toward(target.global_position.x)

func attack_execute(delta: float) -> void:
	velocity.y += gravity * delta
	# à partir de ARMOR_FRAME, la larve est roulée en boule de piques
	if animator.animation == "attack" and animator.frame >= ARMOR_FRAME:
		_set_blindee(true)

func attack_animation_finished() -> void:
	# l'attaque de la larve se joue en 2 temps : le coup ("attack"), puis
	# le retour ("attack_retour") — le cerveau ne reprend la main qu'après
	# le retour joué en entier. Le déroulage est la fenêtre de punition :
	# la boule de piques s'ouvre à ce moment-là.
	if animator.animation == "attack":
		_set_blindee(false)
		animator.play("attack_retour")
		return
	decide()

func attack_exit() -> void:
	_set_blindee(false)  # sécurité : jamais blindée hors de l'attaque


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
