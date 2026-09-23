# skeleton_blue.gd
## SQUELETTE BLEU — variante plus dangereuse du squelette. Script À LUI (demande
## de Kaoru, sept. 2026 : un monstre = ses propres scripts, même si le
## comportement est pour l'instant celui du squelette). Copie de skeleton.gd au
## 18 sept. 2026 ; ce qui change :
##   • poursuite plus rapide : speed 341 (squelette : 280 ; +30 %, encore +25 %,
##     puis −25 % après essai à la manette) — la ronde reste à 140
##   • deux fois plus de vie : 360 PV (squelette : 180)
##   • 2 cœurs de dégâts par coup : `attack_power = 2`, réglé sur la racine de
##     SKELETON_blue.tscn (c'est un export de BaseAI, visible dans l'inspecteur)
## Un correctif apporté à skeleton.gd est à reporter ici À LA MAIN.
extends BaseAI

enum States { IDLE, PATROL, APPROACH, ATTACK, RETURN, DEAD }

@export var speed := 341.0   # squelette 280 → 364 → 455 → −25 % le 18 sept. 2026 (trop rapide à la manette) = 341
## Temps de réflexion en idle avant la prochaine décision (indépendant
## de la durée de l'animation d'idle, qui fait 0.75s par boucle)
@export var reaction_time := 0.3
## Ronde quand aucun joueur en vue : marche jusqu'au trou (ou mur) le plus
## proche à gauche, demi-tour, jusqu'à celui de droite, etc.
@export var patrol_enabled := true
@export var patrol_speed := 140.0
## Rythme de la ronde : durée moyenne de marche avant une pause, et durée
## moyenne de la pause en idle (chaque phase varie de ±40 % autour de la
## moyenne — deux gardes ne sont jamais synchrones)
@export var patrol_walk_time := 3.5
@export var patrol_pause_time := 1.4
var _patrol_phase_timer := 0.0
var _patrol_pausing := false
## Abandon temporaire : si la cible reste inaccessible (bloqué à un bord…)
## pendant ce temps cumulé d'idle frustré, le squelette lâche l'aggro et
## reprend sa ronde — sa vision le re-déclenchera plus tard
@export var abandon_time := 1.5
## Délai de grâce après un abandon avant de pouvoir re-détecter le joueur
## (sinon re-aggro instantané = yo-yo). Un coup reçu réveille toujours.
@export var abandon_cooldown := 2.5
## Distance d'OUBLI : au-delà, le squelette lâche sa cible (et son re-scan
## de vision ne peut pas la reprendre). Réglable par instance.
@export var tracking_distance := 900.0
var _idle_wait := 0.0
var _patrol_dir := 1
var _blocked_time := 0.0
var _abandon_timer := 0.0
@onready var detection_vide: RayCast2D = $detection_vide


func _setup_states() -> void:
	_register_states(States)


## Décrochage (hors-vue géré par BASE_IA) : on y ajoute le délai de grâce
## anti re-scan, comme pour l'abandon de frustration
func _oublier_cible() -> void:
	_blocked_time = 0.0
	_abandon_timer = abandon_cooldown
	target = null

func _start() -> void:
	# en MONTÉE de pente, l'origine du rayon de vide se retrouve DANS la
	# colline (le sol devant est plus haut) : sans hit_from_inside, le rayon
	# ne voit rien → faux "trou devant" → demi-tour au milieu de la pente
	detection_vide.hit_from_inside = true
	max_hp = 360   # le double du squelette (180)
	hp = 360
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
	if _en_cast():
		velocity.x = 0.0      # il est planté le temps de son geste (voir _en_cast)
		return
	if target:
		flip_toward(target.global_position.x)
		# idle AVEC cible = frustration (cible hors de portée) : au bout
		# d'abandon_time cumulé, on lâche l'affaire et on reprend la ronde.
		# (le compteur est remis à zéro par approach/attack)
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
			# personne en vue : après le temps de réflexion, on part en ronde
			_idle_wait += delta
			if _idle_wait >= reaction_time:
				goto_state(States.PATROL)


# _rescan_vision() : désormais celui de BASE_IA (tout ennemi de camp, le plus
# proche). La copie locale ne cherchait que le joueur.


# --- PATROL (ronde entre les deux trous/murs les plus proches) ---

func patrol_enter() -> void:
	animator.play("walk")
	# repart dans la direction du regard actuel
	_patrol_dir = 1 if point.scale.x >= 0.0 else -1
	_patrol_pausing = false
	_patrol_phase_timer = randf_range(patrol_walk_time * 0.6, patrol_walk_time * 1.4)

func patrol_execute(delta: float) -> void:
	velocity.y += gravity * delta
	if _en_cast():
		velocity.x = 0.0      # il est planté le temps de son geste (voir _en_cast)
		return
	# re-détection en ronde (voir _rescan_vision), passé le délai de grâce
	_abandon_timer = maxf(_abandon_timer - delta, 0.0)
	if target == null and _abandon_timer <= 0.0:
		_rescan_vision()
	# un joueur apparaît → on rend la main au cerveau de combat
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
	# trou devant ? piques devant ? mur devant ? → demi-tour.
	# "Mur" = paroi quasi verticale qui NOUS FAIT FACE : une pente raide ou
	# un contact transitoire en bas de pente classé "wall" par la physique
	# faisait demi-tourner la ronde au milieu de la montée
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
	if _en_cast():
		velocity.x = 0.0      # il est planté le temps de son geste (voir _en_cast)
		return
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
	_blocked_time = 0.0  # on se bat : frustration oubliée
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
	if _en_cast():
		velocity.x = 0.0      # il est planté le temps de son geste (voir _en_cast)
		return
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

#region BOULE DE FEU
# ---------------------------------------------------------------------------
# TIR À DISTANCE (18 sept. 2026, demande de Kaoru) : dès que le joueur est
# REPÉRÉ, le squelette bleu lui envoie une boule de feu, à n'importe quelle
# distance et SANS S'ARRÊTER — il tire aussi bien en marchant sur lui qu'à
# l'arrêt. Seule son attaque au corps à corps l'en empêche : la pose de cast
# couperait son animation d'attaque, donc sa hitbox.
#
# La boule part du Marker2D `POINT/bouledefeu` (sa main). Comme le marqueur est
# sous POINT, il suit le retournement du perso : le tir part du bon côté. Le
# squelette se tourne vers le joueur puis tire À PLAT, droit devant : la boule
# ne vise ni ne suit personne.
#
# ANTICIPATION (18 sept. 2026) : le geste se fait en DEUX temps. Il lève la main
# (pose "cast") en S'ARRÊTANT NET, et la boule ne part que `delai_avant_tir`
# plus tard : le joueur voit le coup venir et a le temps de sauter ou de
# s'écarter. Il repart quand la pose se termine. Le geste est
# interrompu s'il meurt ou s'il passe au corps à corps entre-temps.
#
# L'animation "cast" ne fait qu'UNE image et elle boucle : elle ne se termine
# jamais toute seule. La pose est donc tenue au chrono puis l'animation de
# l'état courant est remise.
# ---------------------------------------------------------------------------

const BOULE_DE_FEU := preload("res://SCRIPT/SPELL/projectile_feu.tscn")
## le VISUEL seul (aucun dégât) : celui qui grossit dans sa main pendant le geste
const VISUEL_CHARGE := preload("res://SCRIPT/SHADER/boule_de_feu.tscn")

@export_group("Boule de feu")
@export var boule_de_feu_activee := true
## cœurs enlevés au joueur
@export var degats_boule_de_feu: int = 1
## temps entre deux tirs
@export var cast_cooldown := 2.5
## délai avant le PREMIER tir après avoir repéré le joueur : laisse réagir
@export var cast_delai_aggro := 0.8
## temps entre le LEVER DE MAIN et le départ de la boule : c'est ce délai qui
## laisse au joueur le temps d'anticiper
@export var delai_avant_tir := 0.65   # réglé à la manette le 18 sept. 2026 (essais : 0,5 puis 0,25 puis 0,40)
## temps pendant lequel la pose "cast" est encore tenue APRÈS le départ de la boule
@export var duree_pose_cast := 0.35
## taille FINALE de la boule qui charge dans sa main, exprimée comme celle du
## projectile (0.77 = exactement la boule qui va partir). L'échelle du marqueur
## est compensée, ce réglage veut donc dire la même chose où qu'on pose la main
@export var taille_charge := 0.77
## traînée de la boule pendant la charge : elle ne vole pas encore, une longue
## traînée partirait dans le corps du squelette
@export var trainee_charge := 0.15
## Le geste est-il en cours ? Tant qu'il l'est, il est PLANTÉ : il peut
## déclencher son sort en marchant, mais pas continuer à avancer pendant la
## pose (18 sept. 2026, demande de Kaoru). Couvre le lever de main, le délai
## d'anticipation et le petit temps de pose après le tir.
func _en_cast() -> bool:
	return _pose_cast > 0.0


@onready var _ancre_boule: Node2D = get_node_or_null("POINT/bouledefeu")
var _cast_timer := 0.0
var _pose_cast := 0.0
var _charge := -1.0      # >= 0 : main levée, compte à rebours avant le tir
var _visuel_charge: Node2D = null
var _avait_cible := false


func _physics_process(delta: float) -> void:
	# AVANT super() : c'est super() qui exécute l'état courant puis déplace. Si le
	# cast démarrait après, l'état aurait déjà donné sa vitesse de marche pour la
	# frame et le squelette avancerait d'un pas au moment du lever de main.
	_tick_boule_de_feu(delta)
	super(delta)


func _tick_boule_de_feu(delta: float) -> void:
	# LE GESTE EN COURS : main levée, puis tir au bout du délai.
	if _pose_cast > 0.0:
		if current_state == States.DEAD or current_state == States.ATTACK:
			# il meurt ou il frappe au corps à corps : le geste n'aboutit pas et on
			# rend la main tout de suite à l'animation de son état
			_charge = -1.0
			_pose_cast = 0.0
			_eteindre_charge()
		else:
			# la pose doit TENIR jusqu'au bout. Tout changement d'état rejoue
			# l'animation de SON état (walk, idle…) par-dessus : sans ce rappel, le
			# squelette repassait en "walk" au milieu de son sort et, le déplacement
			# étant gelé, il marchait sur place en lançant sa boule (vu par Kaoru
			# le 18 sept. 2026).
			if String(animator.animation) != "cast":
				animator.play("cast")
			if _charge >= 0.0:
				_charge -= delta
				_grossir_charge()
				if _charge <= 0.0:
					_charge = -1.0
					_tirer_boule_de_feu()
			_pose_cast -= delta
			if _pose_cast <= 0.0:
				_fin_pose_cast()
	_cast_timer = maxf(_cast_timer - delta, 0.0)

	var a_cible: bool = target != null and is_instance_valid(target)
	if a_cible and not _avait_cible:
		# il vient de le repérer : petit temps de réaction avant le premier tir
		_cast_timer = maxf(_cast_timer, cast_delai_aggro)
	_avait_cible = a_cible

	if not boule_de_feu_activee or not a_cible or _cast_timer > 0.0 or _charge >= 0.0:
		return
	if current_state == States.DEAD or current_state == States.ATTACK:
		return
	_commencer_cast()


## Premier temps : il se tourne vers sa cible et LÈVE LA MAIN. Rien ne part encore.
func _commencer_cast() -> void:
	_cast_timer = cast_cooldown
	flip_toward(target.global_position.x)
	animator.play("cast")
	_charge = delai_avant_tir
	_pose_cast = delai_avant_tir + duree_pose_cast
	_allumer_charge()


## Second temps : la boule part enfin, dans le sens où il regarde MAINTENANT
## (s'il s'est retourné pendant le geste, le tir suit son regard : jamais de
## boule qui part dans son dos).
func _tirer_boule_de_feu() -> void:
	_eteindre_charge()          # elle quitte la main : le projectile prend le relais
	var origine: Vector2 = global_position
	if _ancre_boule != null:
		origine = _ancre_boule.global_position
	# TIR HORIZONTAL, droit devant lui (essayé visé sur le joueur le 18 sept. 2026,
	# REFUSÉ par Kaoru : la boule ne suit ni ne vise personne, elle part à plat)
	var boule := BOULE_DE_FEU.instantiate()
	boule.direction = Vector2(float(last_direction), 0.0)
	boule.damage = degats_boule_de_feu
	boule.faction = faction
	boule.degats_monstres = degats_monstres
	boule.tireur = self
	# même convention que bloodball.gd : la scène courante, pas le niveau
	get_tree().current_scene.add_child(boule)
	boule.global_position = origine


# --- LA BOULE QUI GROSSIT DANS SA MAIN ---------------------------------------
# L'animation "cast" ne fait qu'UNE image (main levée) : sans elle, rien ne dit
# à l'écran ce qu'il fabrique pendant les 0,65 s d'anticipation. La boule qui
# enfle, c'est le compte à rebours rendu visible — le joueur lit le temps qu'il
# lui reste à la taille de la boule.

func _allumer_charge() -> void:
	_eteindre_charge()
	if _ancre_boule == null:
		return
	_visuel_charge = VISUEL_CHARGE.instantiate()
	_visuel_charge.demo_vol = false     # elle charge sur place, elle ne vole pas
	_visuel_charge.puissance = 0.25
	# Le marqueur de la main est placé AVANT l'animator dans la scène : sans
	# z_index, la boule serait dessinée derrière le squelette.
	_visuel_charge.z_index = 1
	_ancre_boule.add_child(_visuel_charge)
	_visuel_charge.position = Vector2.ZERO
	_visuel_charge.scale = Vector2.ONE * _taille_charge_locale(0.12)
	_visuel_charge.regler_trainee(trainee_charge)


func _grossir_charge() -> void:
	if _visuel_charge == null or not is_instance_valid(_visuel_charge):
		return
	var t := 1.0 - clampf(_charge / maxf(delai_avant_tir, 0.001), 0.0, 1.0)
	_visuel_charge.scale = Vector2.ONE * _taille_charge_locale(0.12 + 0.88 * t)
	_visuel_charge.puissance = 0.25 + 0.75 * t


func _eteindre_charge() -> void:
	if _visuel_charge != null and is_instance_valid(_visuel_charge):
		_visuel_charge.queue_free()
	_visuel_charge = null


## Compense l'échelle du marqueur de la main (1,22 dans la scène) : `taille_charge`
## garde le même sens que la taille du projectile, où que la main soit réglée.
func _taille_charge_locale(part: float) -> float:
	var compense := 1.0
	if _ancre_boule != null:
		compense = 1.0 / maxf(absf(_ancre_boule.scale.x), 0.01)
	return taille_charge * part * compense


## remet l'animation de l'état courant après la pose de cast
func _fin_pose_cast() -> void:
	if current_state == States.DEAD or current_state == States.ATTACK:
		return
	match current_state:
		States.PATROL:
			animator.play("idle" if _patrol_pausing else "walk")
		States.APPROACH, States.RETURN:
			animator.play("walk")
		_:
			animator.play("idle")
#endregion
