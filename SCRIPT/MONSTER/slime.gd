# slime.gd
extends BaseAI
## ============================================================================
## SLIME (4 oct. 2026) — un monstre simple. Il n'a pas d'images : son corps est
## dessiné par un shader (SCRIPT/MONSTER/slime_corps.gd, slime.gdshader).
##
## IL RAMPE, son corps qui s'allonge et se ramasse (c'est son dessin qui s'en
## charge, à l'allure qu'on lui donne) :
##   • personne en vue : il fait sa ronde, lentement, avec des pauses ; demi-tour
##     devant un trou, un mur ou des piques ;
##   • une cible en vue : il rampe vers elle, plus vite ;
##   • à portée (`bond_portee`) : il BONDIT sur elle — son seul saut. L'annonce
##     d'abord — il se ramasse et tremble pendant `bond_annonce` —, puis il
##     s'élance là où elle est à cet instant, et s'écrase en arrivant : il reste
##     sur place pendant `bond_repos`. La réponse : s'écarter pendant l'annonce,
##     le frapper pendant qu'il récupère.
## Il blesse au contact, comme les autres monstres (`contact_damage`). Un coup
## le repousse, même en l'air.
##
## SA TAILLE (`taille`) : 1 = le slime normal (deux fois le dessin de référence),
## 0.5 = un petit, 2 = un gros… Sa vie, son allure et la portée de son bond
## suivent. Case `se_divise` (décochée) : en mourant, il laisse deux slimes moitié
## moins gros, qui jaillissent de chaque côté — intouchables et inoffensifs le
## temps de retomber — tant que ces petits font au moins la taille 0.5.
##
## Sonné, gelé dans le cristal, entravé, empoisonné, fissuré : comme les autres
## monstres (BASE_IA) — le matériau de son dessin porte les mêmes états.
## ============================================================================

enum States { IDLE, PATROL, APPROACH, ATTACK, DEAD }

## 1 = le slime normal ; 0.5 = un petit ; 2 = un gros
@export_range(0.25, 4.0, 0.05) var taille := 1.0
## Points de vie POUR UNE TAILLE DE 1 (140 = deux coups d'épée) : un slime de
## taille 0.5 en a la moitié
@export var points_de_vie := 140
## En mourant, il se divise en deux slimes moitié moins gros — seulement si
## ces petits font au moins la taille 0.5
@export var se_divise := false
## Temps de réflexion au repos avant la prochaine décision
@export var reaction_time := 0.3
## Distance d'OUBLI : au-delà, il lâche sa cible
@export var tracking_distance := 900.0
## Abandon de frustration : cible en vue mais hors d'atteinte pendant ce temps
## cumulé de repos → il lâche l'affaire et reprend sa ronde
@export var abandon_time := 2.0
## Délai de grâce après un abandon avant de pouvoir la re-détecter
@export var abandon_cooldown := 2.5

@export_group("Déplacement")
## Sa ronde quand il n'y a personne en vue
@export var patrol_enabled := true
## Son allure en ronde et en poursuite (px/s, pour une taille de 1)
@export var vitesse_ronde := 60.0
@export var vitesse_poursuite := 150.0
## Rythme de la ronde : durée moyenne d'avancée / de pause (s, à 40 % près)
@export var ronde_duree := 3.0
@export var ronde_pause := 1.2

@export_group("Bond")
## Il bondit dès que sa cible est à moins de… (px en largeur, pour une taille de 1)
@export var bond_portee := 320.0
## La hauteur du bond (px, pour une taille de 1)
@export var bond_hauteur := 120.0
## L'annonce : il se ramasse et tremble pendant… (s)
@export var bond_annonce := 0.45
## Après le bond, il reste sur place pendant… (s) : le moment de le frapper
@export var bond_repos := 0.7
## Une cible plus haute ou plus basse que ça : pas de bond (px, pour une taille de 1)
@export var bond_denivele := 140.0
@export_group("")

## vitesse d'alignement de son dessin sur la pente (plus grand = plus vif)
const PENTE_VITESSE := 12.0
## la plus petite taille qu'une division peut donner
const TAILLE_MINI := 0.5
## né d'une division : intouchable et inoffensif pendant… (s)
const NAISSANCE := 0.4
## un saut ne se termine pas avant… (s) : le temps de quitter le sol
const VOL_MINI := 0.06
## il regarde s'il y a du sol à cette distance devant son bord (px)
const REGARD_DEVANT := 14.0
## en poursuite, collé à un mur plus longtemps que ça : la cible est hors d'atteinte (s)
const MUR_PATIENCE := 0.3
enum Vol { POSE, EN_VOL, ATTERRI }
enum Phase { ANNONCE, BOND, REPOS }

var _idle_wait := 0.0
var _patrol_dir := 1
var _patrol_phase_timer := 0.0
var _patrol_pausing := false
var _blocked_time := 0.0
var _abandon_timer := 0.0
var _contre_mur := 0.0
## vrai quand la dernière décision a trouvé la cible hors d'atteinte : c'est
## seulement là que la frustration monte
var _cible_inaccessible := false

var _en_vol := false          # il a quitté le sol pour un saut voulu (bond, naissance)
var _air := 0.0               # temps depuis le décollage
var _vx := 0.0                # sa vitesse en largeur pendant le saut
var _force := 0.0             # la force de l'atterrissage à venir (0 à 1)
var _phase := Phase.ANNONCE
var _t := 0.0
var _ne_du_cote := 0          # né d'une division : de quel côté il jaillit (0 : non)
var _naissance := 0.0
var _contact_normal := 1
var _penche_signe := 1.0

@onready var detection_vide: RayCast2D = $detection_vide


func _ready() -> void:
	# AVANT BASE_IA : sa zone de contact copie la forme de collision
	_appliquer_taille()
	super._ready()


## Sa taille règle sa forme de collision, son dessin et la place de sa barre de vie
func _appliquer_taille() -> void:
	var forme: CollisionShape2D = $Collision
	if forme.shape is CircleShape2D:
		var rond: CircleShape2D = forme.shape.duplicate()
		rond.radius *= taille
		forme.shape = rond
		forme.position *= taille
	animator.taille = taille
	animator._poser_rectangle()
	# la barre de vie : au-dessus de lui, plus petite pour un petit slime
	var barre: Node2D = $bare_de_vie
	var e := lerpf(0.26, 0.37, clampf((taille - 0.5) * 2.0, 0.0, 1.0))
	barre.scale = Vector2(e, e)
	barre.position = Vector2(-243.0 * e, -(68.0 * taille * animator.pixel) - 28.0 - 55.0 * e)


func _setup_states() -> void:
	_register_states(States)


func _start() -> void:
	# en montée de pente, le rayon de vide naît dans la colline : sans ça, un
	# faux « trou devant »
	detection_vide.hit_from_inside = true
	# il colle au sol en descente, à allure constante le long de la pente
	floor_snap_length = 32.0
	floor_constant_speed = true
	max_hp = maxi(1, roundi(points_de_vie * taille))
	hp = max_hp
	max_tracking_distance = tracking_distance
	# le matériau de son dessin prend la place de celui de BASE_IA : l'éclair de
	# coup, la teinte, les fissures et le cristal s'y pilotent pareil
	_flash_material = animator.materiau()
	animator.material = null
	if _ne_du_cote != 0:
		_jaillir()
	else:
		change_state(States.IDLE)


func _physics_process(delta: float) -> void:
	super(delta)
	animator.suivre(velocity, is_on_floor())
	_coller_a_la_pente(delta)
	if _naissance > 0.0:
		_naissance -= delta
		if _naissance <= 0.0:
			invulnerable = false
			contact_damage = _contact_normal


## Son allure et la portée de son bond suivent sa taille (et l'échelle posée
## sur le nœud)
func _k() -> float:
	return sqrt(taille) * absf(global_scale.x)


## Le rayon de son corps (px, dans le monde)
func _rayon() -> float:
	if collision.shape is CircleShape2D:
		return (collision.shape as CircleShape2D).radius * absf(global_scale.x)
	return 34.0 * taille * absf(global_scale.x)


## Décrochage (hors-vue de BASE_IA) : même délai de grâce que la frustration
func _oublier_cible() -> void:
	_blocked_time = 0.0
	_abandon_timer = abandon_cooldown
	_cible_inaccessible = false
	target = null


## Son dessin épouse la pente quand il est posé, et se redresse en l'air
func _coller_a_la_pente(delta: float) -> void:
	var cible := 0.0
	var jour := 0.0
	if is_on_floor() and not _is_dead():
		cible = get_floor_normal().angle() + PI * 0.5
		# le rond de sa collision ne touche la pente qu'en un point : son ventre
		# flotterait de r·(1/cos θ − 1), le dessin s'enfonce d'autant
		if collision.shape is CircleShape2D and absf(cible) > 0.01:
			jour = collision.shape.radius * (1.0 / cos(absf(cible)) - 1.0)
	# sous un POINT retourné, une rotation s'affiche à l'envers
	var s := signf(point.scale.x)
	if s == 0.0:
		s = _penche_signe
	if s != _penche_signe:
		animator.rotation = -animator.rotation
		_penche_signe = s
	animator.rotation = lerp_angle(animator.rotation, cible * s, clampf(PENTE_VITESSE * delta, 0.0, 1.0))
	animator.position.y = lerpf(animator.position.y, jour, clampf(PENTE_VITESSE * delta, 0.0, 1.0))


# ============================================================
#  DÉGÂTS (overrides)
# ============================================================

func _is_dead() -> bool:
	return current_state == States.DEAD


func _on_dead() -> void:
	change_state(States.DEAD)


func apply_damage(amount: int, source_x, _source_tag := "?", knockback := true, attaquant: Node = null) -> bool:
	var porte := super(amount, source_x, _source_tag, knockback, attaquant)
	if porte and not _is_dead():
		animator.secouer(1.0)       # il tremblote sous le coup
	return porte


# ============================================================
#  LE SOL DEVANT LUI
# ============================================================

## Y a-t-il du sol sûr (sans piques) à `dx` px de lui ?
func _sol_en(dx: float) -> bool:
	detection_vide.position.x = dx / maxf(absf(global_scale.x), 0.001)
	detection_vide.force_raycast_update()
	return detection_vide.is_colliding() and not danger_devant(detection_vide)


## Peut-il avancer dans la direction `dir` ? (du sol sûr juste devant son bord)
func _sol_devant(dir: int) -> bool:
	return _sol_en(dir * (_rayon() + REGARD_DEVANT))


## Un vrai mur contre lui, du côté `dir` ?
func _mur_devant(dir: int) -> bool:
	if not is_on_wall():
		return false
	var n := get_wall_normal()
	return absf(n.x) > 0.85 and signf(n.x) == -signf(float(dir))


# ============================================================
#  SAUTS (le bond, et le jaillissement à la naissance)
# ============================================================

## Il saute : `dx` px plus loin, en montant de `hauteur` px, pour retomber
## `denivele` px plus bas (négatif : plus haut). `force` : celle de
## l'atterrissage (0 à 1 ; au-delà de 0.6, des gouttes giclent).
func _sauter(dx: float, hauteur: float, force: float, denivele := 0.0) -> void:
	var monte := maxf(hauteur, 4.0) + maxf(-denivele, 0.0)
	var t_monte := sqrt(2.0 * monte / gravity)
	var t_descend := sqrt(2.0 * maxf(monte + denivele, 1.0) / gravity)
	_vx = dx / (t_monte + t_descend)
	velocity.y = -gravity * t_monte
	velocity.x = _vx
	_en_vol = true
	_air = 0.0
	_force = force
	animator.ramper(0.0)


## Pendant un saut : il tient sa vitesse, s'arrête contre un mur, voit
## l'atterrissage. Rend où il en est.
func _voler(delta: float) -> int:
	if not _en_vol:
		return Vol.POSE
	_air += delta
	if _vx != 0.0 and _mur_devant(1 if _vx > 0.0 else -1):
		_vx = 0.0
	velocity.x = _vx
	if _air > VOL_MINI and is_on_floor() and velocity.y >= 0.0:
		_en_vol = false
		velocity.x = 0.0
		animator.atterrir(_force)
		return Vol.ATTERRI
	return Vol.EN_VOL


# ============================================================
#  DÉCISION
# ============================================================

## Sa cible est-elle à portée de bond ? (assez près, à peu près à sa hauteur,
## et du sol sûr là où il retomberait)
func _a_portee_de_bond() -> bool:
	if target == null:
		return false
	var k := _k()
	var dx := target.global_position.x - global_position.x
	var dy := target.global_position.y - global_position.y
	return absf(dx) <= bond_portee * k and absf(dy) <= bond_denivele * k and _sol_en(dx)


func decide() -> void:
	if current_state == States.DEAD:
		return
	# en l'air, il ne décide rien : son état le rappellera une fois posé
	if _en_vol or not is_on_floor():
		return
	if not check_tracking():
		goto_state(States.IDLE)
		return

	var dx := target.global_position.x - global_position.x
	var choice: int
	_cible_inaccessible = false
	if _a_portee_de_bond():
		choice = pick_weighted([
			[States.ATTACK, 300],
			[States.IDLE, 30],
		])
	elif absf(dx) >= HORIZONTAL_DEAD_ZONE and _sol_devant(1 if dx > 0.0 else -1):
		choice = pick_weighted([
			[States.APPROACH, 300],
			[States.IDLE, 20],
		])
	else:
		# au-dessus, en dessous, de l'autre côté d'un trou ou de piques
		_cible_inaccessible = true
		choice = States.IDLE

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
	animator.annoncer(false)
	animator.ramper(0.0)
	velocity.x = 0.0
	_en_vol = false
	_idle_wait = 0.0


func idle_execute(delta: float) -> void:
	apply_gravity(delta)
	if not is_on_floor():
		return          # repoussé ou sonné en l'air : il retombe d'abord
	if target:
		flip_toward(target.global_position.x)
		# au repos avec une cible HORS D'ATTEINTE = frustration ; ses pauses de
		# combat, elles, ne comptent pas
		if _cible_inaccessible:
			_blocked_time += delta
			if _blocked_time >= abandon_time:
				_blocked_time = 0.0
				_abandon_timer = abandon_cooldown
				_cible_inaccessible = false
				target = null
				return
		_idle_wait += delta
		if _idle_wait >= reaction_time:
			_idle_wait = 0.0
			decide()
	else:
		# re-détection : une cible DÉJÀ dans le cône ne ré-émet jamais
		# body_entered → re-scan, passé le délai de grâce
		_abandon_timer = maxf(_abandon_timer - delta, 0.0)
		if _abandon_timer <= 0.0:
			_rescan_vision()
		if patrol_enabled:
			_idle_wait += delta
			if _idle_wait >= reaction_time:
				goto_state(States.PATROL)


# --- PATROL (il rampe entre les trous et les murs, avec des pauses) ---

func patrol_enter() -> void:
	animator.play("walk")
	_patrol_dir = 1 if point.scale.x >= 0.0 else -1
	_patrol_pausing = false
	_patrol_phase_timer = randf_range(ronde_duree * 0.6, ronde_duree * 1.4)


func patrol_execute(delta: float) -> void:
	apply_gravity(delta)
	# né d'une division : il finit d'abord son jaillissement
	if _voler(delta) == Vol.EN_VOL:
		return
	_abandon_timer = maxf(_abandon_timer - delta, 0.0)
	if target == null and _abandon_timer <= 0.0:
		_rescan_vision()
	if target:
		velocity.x = 0.0
		animator.ramper(0.0)
		decide()
		return
	# respiration de ronde : il avance, puis souffle
	_patrol_phase_timer -= delta
	if _patrol_pausing:
		velocity.x = 0.0
		if _patrol_phase_timer <= 0.0:
			_patrol_pausing = false
			_patrol_phase_timer = randf_range(ronde_duree * 0.6, ronde_duree * 1.4)
		return
	if _patrol_phase_timer <= 0.0:
		_patrol_pausing = true
		_patrol_phase_timer = randf_range(ronde_pause * 0.6, ronde_pause * 1.4)
		velocity.x = 0.0
		animator.ramper(0.0)
		return
	# trou devant ? piques devant ? vrai mur de face ? → demi-tour
	if is_on_floor() and (not _sol_devant(_patrol_dir) or _mur_devant(_patrol_dir)):
		_patrol_dir = -_patrol_dir
	var allure := vitesse_ronde * _k()
	velocity.x = _patrol_dir * allure
	last_direction = _patrol_dir
	point.scale.x = _patrol_dir
	animator.ramper(allure if is_on_floor() else 0.0)


func patrol_exit() -> void:
	animator.ramper(0.0)


# --- APPROACH (il rampe vers sa cible, jusqu'à portée de bond) ---

func approach_enter() -> void:
	animator.play("walk")
	_blocked_time = 0.0  # la cible est accessible : frustration oubliée
	_contre_mur = 0.0


func approach_execute(delta: float) -> void:
	apply_gravity(delta)
	if not target:
		goto_state(States.IDLE)
		return
	var dx := target.global_position.x - global_position.x
	if absf(dx) < HORIZONTAL_DEAD_ZONE:
		velocity.x = 0.0
		goto_state(States.IDLE)
		return
	if not is_on_floor():
		return
	if _a_portee_de_bond():
		velocity.x = 0.0
		decide()
		return
	var dir := 1 if dx > 0.0 else -1
	# un mur qui dure : la cible est derrière
	_contre_mur = _contre_mur + delta if _mur_devant(dir) else 0.0
	if not _sol_devant(dir) or _contre_mur >= MUR_PATIENCE:
		velocity.x = 0.0
		_cible_inaccessible = true
		goto_state(States.IDLE)
		return
	var allure := vitesse_poursuite * _k()
	move_toward_target(allure)
	animator.ramper(allure)


func approach_exit() -> void:
	animator.ramper(0.0)


# --- ATTACK (le bond : il se ramasse, s'élance, s'écrase) ---

func attack_enter() -> void:
	animator.play("attack")
	animator.ramper(0.0)
	velocity.x = 0.0
	_blocked_time = 0.0
	_phase = Phase.ANNONCE
	_t = bond_annonce
	animator.annoncer(true)
	if target:
		flip_toward(target.global_position.x)


func attack_execute(delta: float) -> void:
	apply_gravity(delta)
	match _phase:
		Phase.ANNONCE:
			if target:
				flip_toward(target.global_position.x)
			_t -= delta
			if _t <= 0.0 and is_on_floor():
				animator.annoncer(false)
				_bondir()
		Phase.BOND:
			if _voler(delta) != Vol.EN_VOL:
				_phase = Phase.REPOS
				_t = bond_repos
				velocity.x = 0.0
		Phase.REPOS:
			velocity.x = 0.0
			_t -= delta
			if _t <= 0.0 and is_on_floor():
				decide()


## il s'élance là où est sa cible à cet instant (pas plus loin que sa portée) ;
## plus de cible, ou plus de sol là-bas : il renonce
func _bondir() -> void:
	if not check_tracking():
		goto_state(States.IDLE)
		return
	var k := _k()
	var portee := bond_portee * k * 1.15
	var dx := clampf(target.global_position.x - global_position.x, -portee, portee)
	var dy := clampf(target.global_position.y - global_position.y, -bond_denivele * k, bond_denivele * k)
	if not _sol_en(dx):
		_cible_inaccessible = true
		goto_state(States.IDLE)
		return
	if absf(dx) >= HORIZONTAL_DEAD_ZONE:
		last_direction = 1 if dx > 0.0 else -1
		point.scale.x = last_direction
	_phase = Phase.BOND
	_sauter(dx, bond_hauteur * k, 1.0, dy)


func attack_exit() -> void:
	animator.annoncer(false)


# --- DEAD ---

func dead_enter() -> void:
	velocity.x = 0.0
	_en_vol = false
	animator.annoncer(false)
	animator.ramper(0.0)
	animator.mourir()
	_se_diviser()


func dead_execute(delta: float) -> void:
	if not is_on_floor():
		velocity.y += gravity * delta
	else:
		velocity.y = 0.0


## la flaque a disparu : il n'en reste rien
func dead_animation_finished() -> void:
	queue_free()


# ============================================================
#  DIVISION
# ============================================================

## En mourant, il laisse deux slimes moitié moins gros, qui jaillissent de
## chaque côté. Ils gardent ses réglages (ceux de l'instance posée dans le
## niveau) et sa cible.
func _se_diviser() -> void:
	var petite := taille * 0.5
	if not se_divise or petite < TAILLE_MINI or scene_file_path == "" or get_parent() == null:
		return
	var modele := load(scene_file_path) as PackedScene
	if modele == null:
		return
	for cote in [-1, 1]:
		var petit := modele.instantiate()
		_copier_reglages(self, petit)
		_copier_reglages(animator, petit.get_node("POINT/animator"))
		petit.taille = petite
		petit.scale = scale
		petit.position = position + Vector2(cote * 16.0 * taille, -4.0) * scale
		petit._ne_du_cote = cote
		petit.target = target
		get_parent().add_child.call_deferred(petit)


## les valeurs exportées d'un nœud, recopiées sur un autre du même script
static func _copier_reglages(de: Node, vers: Node) -> void:
	for p in de.get_property_list():
		if (p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE) and (p.usage & PROPERTY_USAGE_STORAGE):
			vers.set(p.name, de.get(p.name))


## né d'une division : il jaillit de son côté, intouchable et inoffensif le
## temps de retomber, puis fait sa vie
func _jaillir() -> void:
	_naissance = NAISSANCE
	invulnerable = true
	_contact_normal = contact_damage
	contact_damage = 0
	last_direction = _ne_du_cote
	point.scale.x = _ne_du_cote
	change_state(States.PATROL)
	_patrol_dir = _ne_du_cote
	_sauter(_ne_du_cote * 100.0 * _k(), 65.0 * _k(), 0.5)
	animator.secouer(1.0)
