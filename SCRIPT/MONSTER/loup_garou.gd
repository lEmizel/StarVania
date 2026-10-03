# loup_garou.gd
extends BaseAI
## ============================================================================
## LOUP-GAROU (3 oct. 2026) — un ÉLITE, pas un vrai boss, bâti sur le modèle du
## skeleton_boss : même cerveau (repos par boucles d'idle, ronde quand personne
## n'est en vue, approche, abandon de frustration), même vie, et INÉBRANLABLE
## (aucun recul : c'est le joueur qui encaisse le contrecoup).
##
## Pour le moment il n'a qu'une attaque, le CRI (animation `attack_cri`) :
##   • il se ramasse (les images d'avant `cri_image_depart` : l'annonce), puis
##     hurle jusqu'à la dernière image de l'animation — allonger l'animation
##     allonge le cri ;
##   • tant qu'il hurle, ses RONDS BLESSENT : de sa gueule jusqu'au front de
##     l'onde qui s'étend, borné par `portee_cri`. Chaque corps n'est touché
##     qu'UNE FOIS par cri (`cri_damage` cœurs pour le joueur, `degats_monstres`
##     pour un monstre d'un autre camp), pas à travers un mur. La roulade et le
##     dash ne sauvent pas si on reste dedans : la réponse, c'est de RECULER
##     quand il se ramasse ;
##   • l'effet (SCRIPT/SHADER/cri_rond.tscn) est posé sur sa gueule : le nœud
##     `POINT/CriRond` s'il est dans la scène, sinon il est créé ici, en
##     `GUEULE`. Ses ronds se règlent sur `portee_cri`.
## Sonné, gelé dans le cristal ou tué en plein cri : il se tait.
## ============================================================================

enum States { IDLE, PATROL, APPROACH, ATTACK_CRI, DEAD }

@export var speed := 200.0
## Points de vie (600 : autant que le skeleton_boss)
@export var points_de_vie := 600
## Nombre de boucles d'idle imposées entre deux actions (tiré entre min et max
## à chaque pause ; 0 = il enchaîne sans pause). Au moins une : avec un seul
## coup, sans pause il hurlerait sans arrêt.
@export var idle_cycles_min := 1
@export var idle_cycles_max := 2
## Abandon de frustration : cible visible mais inaccessible (autre
## plateforme…) pendant ce temps cumulé d'idle → il lâche l'aggro
@export var abandon_time := 3.0
## Délai de grâce après un abandon avant de pouvoir re-détecter
@export var abandon_cooldown := 2.5
## Ronde quand personne en vue : même allure que la poursuite (speed)
@export var patrol_enabled := true
## Rythme de la ronde : durée moyenne de marche / de pause (±40 %)
@export var patrol_walk_time := 4.0
@export var patrol_pause_time := 2.0

@export_group("Cri")
## Cœurs enlevés au joueur par un cri (une seule fois par cri)
@export var cri_damage: int = 1
## Jusqu'où le cri blesse, depuis la gueule (px). Les ronds de l'effet se
## règlent dessus : pleins jusque-là, ils s'effilent au-delà.
@export var portee_cri := 400.0
## Il hurle dès que sa cible est à moins de… (px, de ses pieds aux siens)
@export var cri_declenche := 260.0
## L'image d'`attack_cri` où la gueule s'ouvre : le cri part là, et s'arrête à
## la dernière image de l'animation
@export var cri_image_depart := 3
@export_group("")

const CRI_SCENE := preload("res://SCRIPT/SHADER/cri_rond.tscn")
## la gueule ouverte du hurlement, dans POINT (mesurée sur ses images 4 à 6 du cri)
const GUEULE := Vector2(-25.0, -229.0)
## le rayon des ronds pour une portée de 1 : ils sont encore pleins à la portée
const RAYON_PAR_PORTEE := 1.4

var _blocked_time := 0.0
var _abandon_timer := 0.0
## vrai quand la dernière décision a trouvé la cible hors d'atteinte (ni à pied,
## ni au cri) : c'est seulement là que la frustration monte
var _cible_inaccessible := false
var _patrol_dir := 1
var _patrol_phase_timer := 0.0
var _patrol_pausing := false
var _idle_loops := 0
var _idle_loops_needed := 1

var cri: Node2D
var _cri_lance := false
var _cri_touches: Array = []        # ceux que CE cri a déjà blessés
var _zone_cri := CircleShape2D.new()

@onready var detection_vide: RayCast2D = $detection_vide


func _setup_states() -> void:
	_register_states(States)

func _start() -> void:
	# même correctif que le squelette : en montée de pente, le rayon de vide
	# naît dans la colline et rapportait un faux "trou devant"
	detection_vide.hit_from_inside = true
	max_hp = points_de_vie
	hp = points_de_vie
	max_tracking_distance = 2000.0
	confort_zone_max = cri_declenche
	inebranlable = true  # inébranlable : aucun recul, le joueur subit le contrecoup
	_poser_cri()
	change_state(States.IDLE)


func _physics_process(delta: float) -> void:
	super(delta)
	# gelé dans le cristal en plein cri : son état ne tourne plus, il se tait
	if cri != null and est_cristallise() and cri.en_cours():
		cri.arreter()


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
		# cible perdue : il reste sur place, puis repart en ronde
		goto_state(States.IDLE)
		return

	var choice: int
	_cible_inaccessible = false
	if distance_to_target() < confort_zone_max:
		# à portée : il hurle (ou souffle un instant)
		choice = pick_weighted([
			[States.ATTACK_CRI, 200],
			[States.IDLE, 60],
		])
	else:
		# Check si approach possible (sol devant)
		var dir_to_target := 1 if target.global_position.x > global_position.x else -1
		detection_vide.position.x = absf(detection_vide.position.x) * dir_to_target
		detection_vide.force_raycast_update()
		var can_approach := detection_vide.is_colliding() and not danger_devant(detection_vide)
		var in_dead_zone := absf(target.global_position.x - global_position.x) < HORIZONTAL_DEAD_ZONE
		if in_dead_zone or not can_approach:
			# hors d'atteinte à pied (au-dessus, de l'autre côté d'un trou) : si
			# son cri porte jusque-là, il hurle quand même
			if _cible_a_portee_de_cri():
				choice = pick_weighted([
					[States.ATTACK_CRI, 150],
					[States.IDLE, 100],
				])
			else:
				_cible_inaccessible = true
				choice = States.IDLE
		else:
			choice = pick_weighted([
				[States.APPROACH, 250],
				[States.IDLE, 60],
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
		# idle prolongé avec une cible HORS D'ATTEINTE = frustration ; les vraies
		# actions (approche, cri) remettent le compteur à zéro. Ses pauses de
		# combat ne comptent pas (chez le skeleton_boss elles comptent : avec
		# les boucles d'idle du loup, d'une seconde, il lâchait une cible bien
		# en vue une fois sur cinq — vu au test).
		if _cible_inaccessible:
			_blocked_time += delta
		if _blocked_time >= abandon_time:
			_blocked_time = 0.0
			_abandon_timer = abandon_cooldown
			_cible_inaccessible = false
			target = null
	else:
		# re-détection : un joueur DÉJÀ dans le cône ne ré-émet jamais
		# body_entered → re-scan, passé le délai de grâce
		_abandon_timer = maxf(_abandon_timer - delta, 0.0)
		if _abandon_timer <= 0.0:
			_rescan_vision()


## Décrochage (hors-vue de BASE_IA) : même délai de grâce que la frustration
func _oublier_cible() -> void:
	_blocked_time = 0.0
	_abandon_timer = abandon_cooldown
	_cible_inaccessible = false
	target = null

func idle_animation_looped() -> void:
	_idle_loops += 1
	if target and _idle_loops >= _idle_loops_needed:
		decide()
	elif target == null and patrol_enabled:
		# personne en vue : après une boucle d'idle, il part en ronde
		goto_state(States.PATROL)


# --- PATROL (ronde entre les obstacles) ---

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
	if distance_to_target() <= confort_zone_max:
		velocity.x = 0.0
		# Pas d'idle après une marche : il hurle tout de suite, sinon le joueur
		# peut le kiter (s'éloigner → le frapper pendant sa pause → répéter)
		goto_state(States.ATTACK_CRI)
		return
	detection_vide.position.x = absf(detection_vide.position.x) * last_direction
	if not detection_vide.is_colliding() or danger_devant(detection_vide):
		velocity.x = 0.0
		goto_state(States.IDLE)
		return
	move_toward_target(speed)

# --- ATTACK_CRI (le cri en rond) ---
func attack_cri_enter() -> void:
	attack_power = cri_damage
	# toujours depuis l'annonce : relancé en plein cri (une décision qui retombe
	# sur le cri), `play` seul reprenait l'animation là où elle en était et le
	# cri repartait sans prévenir
	animator.stop()
	animator.play("attack_cri")
	velocity.x = 0.0
	_blocked_time = 0.0  # on se bat : frustration oubliée
	_cri_lance = false
	_cri_touches.clear()
	if target:
		flip_toward(target.global_position.x)

func attack_cri_execute(delta: float) -> void:
	apply_gravity(delta)
	var derniere: int = animator.sprite_frames.get_frame_count("attack_cri") - 1
	if not _cri_lance:
		# la gueule s'ouvre : le cri part
		if animator.frame >= cri_image_depart and animator.frame < derniere:
			_cri_lance = true
			cri.crier()
	elif animator.frame >= derniere:
		# il referme la gueule : plus aucune onde ne part
		cri.arreter()
	if cri.en_cours():
		_cri_frapper()

func attack_cri_exit() -> void:
	# coupé (sonné, tué…) ou fini : il se tait
	cri.arreter()

func attack_cri_animation_finished() -> void:
	goto_state(States.IDLE)  # pause imposée avant la prochaine action

# --- DEAD ---
func dead_enter() -> void:
	animator.play("dead")
	velocity.x = 0.0

func dead_execute(delta: float) -> void:
	if not is_on_floor():
		apply_gravity(delta)
	else:
		velocity.y = 0.0

# ============================================================
#  LE CRI
# ============================================================

## L'effet du cri, sur sa gueule : celui de la scène (`POINT/CriRond`) s'il y
## est, sinon il est créé ici. Ses ronds se règlent sur la portée du coup.
func _poser_cri() -> void:
	cri = point.get_node_or_null("CriRond") as Node2D
	if cri == null:
		cri = CRI_SCENE.instantiate()
		cri.name = "CriRond"
		cri.position = GUEULE
		point.add_child(cri)
	cri.rayon = portee_cri * RAYON_PAR_PORTEE


## Tant qu'il hurle, ses ronds blessent : tout ennemi dont le milieu du corps
## est entre la gueule et le front de l'onde (borné par `portee_cri`), sans mur
## entre les deux. Une seule fois par cri et par corps.
func _cri_frapper() -> void:
	var front: float = minf(cri.couronne().y, portee_cri)
	if front <= 0.0:
		return
	var gueule: Vector2 = cri.global_position
	var j := get_tree().get_first_node_in_group("Player") as PhysicsBody2D
	if j != null and est_ennemi(j) and not _cri_touches.has(j):
		var c: Vector2 = j.centre_corps()
		if c.distance_to(gueule) <= front and _a_vue(gueule, c):
			# le joueur a ses parades (roulade, dash, bouclier, pas de côté…) :
			# tant que le coup n'a pas PORTÉ, il n'est pas compté — s'il reste
			# dans les ronds, il le prendra à la fin de sa parade
			var vie_avant: int = Player.hp
			var etat_avant: int = j.current_state
			infliger(j, global_position.x, "cri:" + name)
			if Player.hp < vie_avant or (j.current_state == j.States.HIT and etat_avant != j.States.HIT):
				_cri_touches.append(j)
	# les monstres d'un autre camp, sur LEUR couche (8)
	_zone_cri.radius = front
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = _zone_cri
	params.transform = Transform2D(0.0, gueule)
	params.collision_mask = 8
	params.collide_with_areas = false
	for hit in get_world_2d().direct_space_state.intersect_shape(params, 32):
		var m = hit.get("collider")
		if m == self or not (m is BaseAI) or not est_ennemi(m) or _cri_touches.has(m):
			continue
		var c: Vector2 = _milieu(m)
		if c.distance_to(gueule) <= front and _a_vue(gueule, c):
			if m.apply_damage(degats_monstres, global_position.x, "cri:" + name, true, self):
				_cri_touches.append(m)


## la cible est-elle là où le cri porte (avec de la marge) et sans mur devant ?
func _cible_a_portee_de_cri() -> bool:
	if target == null or cri == null:
		return false
	var gueule: Vector2 = cri.global_position
	var c := _milieu(target)
	return c.distance_to(gueule) <= portee_cri * 0.8 and _a_vue(gueule, c)


## le milieu du corps de `corps` (là où on mesure si le cri l'atteint)
func _milieu(corps: Node2D) -> Vector2:
	if corps.has_method("centre_corps"):
		return corps.centre_corps()
	if corps is BaseAI and corps.collision != null:
		return corps.collision.global_position
	return corps.global_position


## le cri ne passe pas les murs (couche 2 : les décors solides — ni le joueur
## ni les monstres n'y sont)
func _a_vue(de: Vector2, vers: Vector2) -> bool:
	var requete := PhysicsRayQueryParameters2D.create(de, vers, 2)
	return get_world_2d().direct_space_state.intersect_ray(requete).is_empty()
