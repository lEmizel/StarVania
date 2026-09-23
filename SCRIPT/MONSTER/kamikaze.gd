# kamikaze.gd
extends BaseAI
## ============================================================================
## KAMIKAZE — une bombe volante. Il flotte à son poste en ondulant, FONCE sur
## le joueur dès qu'il le repère, s'AMORCE quand il arrive au contact
## (animation "gonfle"), puis EXPLOSE : dégâts en cercle + l'explosion violette
## en shader par-dessus son animation.
##
## Deux règles qui font tout son sel :
##   • une fois amorcé, il part QUOI QU'IL ARRIVE — la mèche est la fenêtre
##     laissée au joueur pour dégager, comme les piques rétractables ;
##   • TOUTE mort le fait exploser. L'abattre au corps à corps se paie ; la
##     bonne réponse, c'est la distance (ou le laisser se vider sur un piège :
##     couche 8, les zones DEGATS le détectent comme les autres monstres).
##
## Trois animations, toutes dans la scène :
##   "idle"      bouclée — c'est aussi son animation de déplacement
##   "gonfle"    la mèche : sa DURÉE fait le délai avant le boum. Pour
##               l'allonger ou la raccourcir, c'est la vitesse de l'animation
##               dans l'éditeur, rien à toucher ici
##   "explosion" le corps qui éclate
##
## Pas de script d'animator : il n'a aucune hitbox d'attaque, le souffle est
## une requête physique circulaire tirée sur une image précise de l'explosion.
## ============================================================================

enum States { IDLE, CHASE, GONFLE, BOOM }

const EXPLOSION_VIOLETTE := preload("res://SCRIPT/SHADER/explosion_violette.tscn")

## rayon que fait le visuel de explosion_violette.tscn à sa taille d'origine
## (rayon_max 0.384 sur un ColorRect de 360 px). Sert à mettre le visuel à
## l'échelle du rayon de dégâts : les deux ne peuvent pas se contredire.
const RAYON_VISUEL_BASE := 144.0

@export_group("Vol")
## vitesse de la charge sur le joueur
@export var speed := 560.0
## vitesse du retour à son poste quand il n'a plus de cible
@export var speed_retour := 180.0
## interrupteur de secours : la convention du projet veut un dessin tourné à
## DROITE. À cocher si un jour le skin est redessiné dans l'autre sens, sinon
## il poursuivrait le joueur à reculons dans les deux sens
@export var dessin_regarde_a_gauche := false
## amplitude du flottement sur place, en pixels
@export var repos_amplitude := 26.0
## flottements par seconde sur place
@export var repos_frequence := 0.6
## distance d'OUBLI : au-delà, il lâche sa cible et rentre au poste
@export var tracking_distance := 1400.0

@export_group("Explosion")
## distance (centre à centre) à laquelle il s'amorce et lance "gonfle"
@export var distance_amorce := 120.0
## rayon du souffle, en pixels. Le visuel est mis à cette échelle
@export var rayon_explosion := 150.0
## cœurs enlevés au joueur par le souffle (le contact du corps, lui,
## se règle avec `contact_damage`, plus haut dans l'inspecteur)
@export var degats_explosion := 1
## image de l'anim "explosion" à partir de laquelle le souffle porte
@export var frame_souffle := 1
## tremblement pendant le gonflement, en pixels (0 = aucun)
@export var tremblement_px := 3.0
## ajoute l'explosion violette en shader par-dessus l'animation
@export var explosion_shader := true

var _phase := 0.0            # position dans l'ondulation, en tours
var _t := 0.0                # chrono de l'état courant
var _offset_base := Vector2.ZERO
var _duree_gonfle := 0.35
var _mort := false
var _souffle_fait := false


func _setup_states() -> void:
	_register_states(States)


func _start() -> void:
	# fragile : deux coups d'épée (70 de dégâts) et il saute
	max_hp = 140
	hp = 140
	max_tracking_distance = tracking_distance
	confort_zone_max = distance_amorce
	confort_zone_min = 0.0
	_offset_base = animator.offset
	_duree_gonfle = _duree_anim(&"gonfle")
	_phase = randf()          # deux kamikazes côte à côte n'ondulent pas ensemble
	_orienter()               # le miroir de départ posé dans l'éditeur compris
	change_state(States.IDLE)


# ============================================================
#  MORT — elle passe par la même mèche qu'un amorçage normal
# ============================================================

func _is_dead() -> bool:
	return _mort or current_state == States.BOOM


func _on_dead() -> void:
	_mort = true
	# Volontairement PAS d'explosion instantanée : abattu au corps à corps, il
	# gonfle d'abord. Le joueur garde la même fenêtre de fuite que d'habitude,
	# et le signal reste le même à l'écran. (Explosion immédiate = un coup
	# d'épée = un cœur perdu sans aucune parade possible.)
	goto_state(States.GONFLE)


# ============================================================
#  DÉCISION (appelée par BaseAI quand il est frappé de dos)
# ============================================================

func decide() -> void:
	if _is_dead() or current_state == States.GONFLE:
		return
	if _cible_valide():
		goto_state(States.CHASE)


# ============================================================
#  ÉTATS
# ============================================================

# --- IDLE : il flotte à son poste en ondulant ---

func idle_enter() -> void:
	animator.play(&"idle")


func idle_execute(delta: float) -> void:
	_phase += repos_frequence * delta
	var v := Vector2.ZERO
	if virevolte:
		# vol libre (BASE_IA) : il virevolte autour du poste ; entre deux points
		# il garde son flottement
		v = virevolter(delta)
		if v == Vector2.ZERO:
			v.y = _ondulation(repos_amplitude, repos_frequence)
	else:
		var vers_poste := initial_position - global_position
		if vers_poste.length() > 30.0:
			v = vers_poste.normalized() * speed_retour
		v.y += _ondulation(repos_amplitude, repos_frequence)
	velocity = v
	if target == null:
		_rescan_vision()        # un ennemi déjà dans le champ (sa cible vient de mourir…)
	if target != null:
		flip_toward(target.global_position.x)
	if _cible_valide():
		goto_state(States.CHASE)


# --- CHASE : il fonce droit dessus ---

func chase_enter() -> void:
	animator.play(&"idle")       # l'idle EST son animation de déplacement


## Droit sur lui, sans ondulation : la charge doit se lire comme une menace
## qui fonce, pas comme un vol de papillon (l'ondulation reste au repos)
func chase_execute(_delta: float) -> void:
	if not _cible_valide():
		goto_state(States.IDLE)
		return
	var vers := _vers_cible()
	velocity = vers.normalized() * speed
	flip_toward(target.global_position.x)
	if vers.length() <= distance_amorce:
		goto_state(States.GONFLE)


# --- GONFLE : la mèche. Il se fige et tremble, puis ça part ---

func gonfle_enter() -> void:
	animator.play(&"gonfle")
	velocity = Vector2.ZERO
	_t = 0.0


func gonfle_execute(delta: float) -> void:
	_t += delta
	velocity = Vector2.ZERO
	if tremblement_px > 0.0:
		animator.offset = _offset_base + Vector2(
			randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * tremblement_px
	# filet : si l'animation ne signale rien (une seule image, boucle…), le
	# boum part quand même à la durée de "gonfle"
	if _t >= _duree_gonfle + 0.1:
		goto_state(States.BOOM)


func gonfle_animation_finished() -> void:
	goto_state(States.BOOM)


# --- BOOM ---

func boom_enter() -> void:
	velocity = Vector2.ZERO
	animator.offset = _offset_base
	_souffle_fait = false
	# ses éclats (anim "explosion", anneau de ~115 px) passent DEVANT la boule
	# violette (~144 px) : sinon le shader les avalerait entièrement. Traits
	# noirs sur boule claire = le dessin reste lisible
	point.z_index = 1
	animator.play(&"explosion")
	if explosion_shader:
		_poser_explosion_violette()


func boom_execute(_delta: float) -> void:
	velocity = Vector2.ZERO
	# lecture par IMAGE et non par chrono : le souffle reste calé sur le dessin
	# même si la vitesse de l'animation change dans l'éditeur
	if not _souffle_fait and animator.frame >= frame_souffle:
		_souffler()


func boom_animation_finished() -> void:
	queue_free()


# ============================================================
#  LE SOUFFLE
# ============================================================

## Cercle de dégâts posé sur le centre du corps. Requête de forme plutôt que
## distance au centre du joueur : c'est sa capsule réelle qui compte, donc ce
## qu'on voit brûler brûle vraiment.
func _souffler() -> void:
	_souffle_fait = true
	var params := PhysicsShapeQueryParameters2D.new()
	var cercle := CircleShape2D.new()
	cercle.radius = rayon_explosion
	params.shape = cercle
	params.transform = Transform2D(0.0, _centre())
	params.collision_mask = 1 | 8      # le joueur (couche 1) et les monstres (8)
	params.collide_with_areas = false
	params.collide_with_bodies = true
	for hit in get_world_2d().direct_space_state.intersect_shape(params, 8):
		var corps = hit.get("collider")
		if corps == null or not est_ennemi(corps) or not corps.has_method("apply_damage"):
			continue
		if corps.is_in_group("Player"):
			# dernier argument : le souffle passe outre le stun de 0,25 s. Il ne
			# part qu'un coup par bombe, alors que quatre bombes qui sautent
			# ensemble ne doivent pas coûter un seul cœur
			corps.apply_damage(degats_explosion, global_position.x, "kamikaze:" + name, true)
		else:
			# un monstre d'un autre camp : en points de vie
			corps.apply_damage(degats_monstres, global_position.x, "kamikaze:" + name, true, self)


func _poser_explosion_violette() -> void:
	var ex := EXPLOSION_VIOLETTE.instantiate()
	# réglages posés AVANT l'ajout : en jeu elle joue une fois et se supprime
	ex.demo_boucle = false
	ex.auto_detruire = true
	ex.scale = Vector2.ONE * (rayon_explosion / RAYON_VISUEL_BASE)
	# hébergée par la scène, pas par le kamikaze : lui disparaît au bout de son
	# animation, le souffle doit finir de jouer
	var hote: Node = get_tree().current_scene
	if hote == null:
		hote = get_parent()
	hote.add_child(ex)
	ex.global_position = _centre()


# ============================================================
#  UTILITAIRES
# ============================================================

## Le retournement de BaseAI suppose un dessin qui regarde à DROITE. On garde
## son `last_direction` (1 = cible à droite, lu par le reste du code) et on
## inverse seulement le miroir du POINT.
func flip_toward(target_x: float) -> void:
	super(target_x)
	_orienter()


func _orienter() -> void:
	if dessin_regarde_a_gauche:
		point.scale.x = -last_direction
	else:
		point.scale.x = last_direction


## centre du corps (la capsule), pas l'origine du nœud qui est sous lui
func _centre() -> Vector2:
	return collision.global_position


## vecteur centre à centre vers le joueur
func _vers_cible() -> Vector2:
	if target == null:
		return Vector2.ZERO
	var but: Vector2 = target.global_position
	if target.has_method("centre_corps"):
		but = target.centre_corps()
	return but - _centre()


func _cible_valide() -> bool:
	return check_tracking() and is_instance_valid(target)


## vitesse latérale de l'ondulation : dérivée de A·sin(2π·f·t), pour que
## l'amplitude se règle en PIXELS et non en vitesse
func _ondulation(amplitude: float, frequence: float) -> float:
	return amplitude * TAU * frequence * cos(_phase * TAU)


func _duree_anim(nom: StringName) -> float:
	if animator.sprite_frames == null or not animator.sprite_frames.has_animation(nom):
		return 0.35
	var fps := maxf(animator.sprite_frames.get_animation_speed(nom), 0.001)
	var total := 0.0
	for i in animator.sprite_frames.get_frame_count(nom):
		total += animator.sprite_frames.get_frame_duration(nom, i) / fps
	return maxf(total, 0.01)
