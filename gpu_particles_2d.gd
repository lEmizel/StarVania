extends CPUParticles2D
## Récolte de sang, en 4 phases :
##   1. WAIT   — s'attarde sur le cadavre
##   2. SEEK   — s'envole vers le joueur en arc naturel (pilotage par vélocité,
##               vitesse max croissante → impossible à semer, rattrapage garanti)
##   3. LINGER — reste collée sur le joueur (le suit s'il bouge)
##   4. FADE   — fondu, crédite le blood, RETOURNE AU POOL
##
## CPUParticles2D (et non GPU) et instances RECYCLÉES par l'autoload Pool :
## créer un système de particules coûte 100 à 250 ms sur Metal / Mac (mesuré
## le 13 sept. 2026). On ne crée donc jamais en jeu : `relancer()` réveille une
## instance dormante, `dormir()` la range. (Fichier au nom historique.)

@export var wait_time: float = 1.0        ## temps sur le cadavre avant le départ
@export var linger_time: float = 0.0      ## temps sur le joueur avant le fondu (0 = fondu immédiat)
@export var fade_duration: float = 0.50
@export var target_y_offset: float = -60.0

@export var start_speed: float = 260.0        ## impulsion initiale (direction aléatoire vers le haut)
@export var seek_accel: float = 900.0         ## force de pilotage vers le joueur
@export var max_speed_start: float = 500.0
@export var max_speed_growth: float = 900.0   ## la vitesse max grandit avec le temps de poursuite
@export var catch_distance: float = 24.0

@export var gauge_fill: int = 0    ## bloodheal à l'arrivée — 0 depuis sept. 2026 : c'est le COUP qui recharge, plus le kill
@export var blood_reward: int = 100  ## blood (monnaie) crédité à l'arrivée

enum Phase { WAIT, SEEK, LINGER, FADE }

var player: CharacterBody2D = null
var _phase := Phase.WAIT
var _t := 0.0
var _seek_t := 0.0
var _vel := Vector2.ZERO
# détection de raté : après un premier survol manqué (on se rapprochait puis
# on s'éloigne), l'orbe passe en charge directe, en ligne droite, imparable
var _prev_dist := INF
var _was_closing := false
var _direct := false
var _tween: Tween
# position locale d'origine (sous la racine) : le vol vers le joueur déplace CE
# nœud, il faut le remettre en place à chaque réutilisation, sinon la récolte
# émet à "nouveau cadavre + trajet précédent"
var _position_initiale := Vector2.ZERO


func _ready() -> void:
	_position_initiale = position
	# une instance naît endormie dans le pool : rien ne tourne avant relancer()
	set_process(false)


## Réveil (Pool.sang) : tout à zéro, émission relancée, poursuite armée.
func relancer() -> void:
	player = get_tree().get_first_node_in_group("Player") as CharacterBody2D
	_phase = Phase.WAIT
	_t = 0.0
	_seek_t = 0.0
	_prev_dist = INF
	_was_closing = false
	_direct = false
	if _tween != null and _tween.is_valid():
		_tween.kill()
	self_modulate = Color(1, 1, 1, 1)
	position = _position_initiale   # retour sur le cadavre (la racine y est déjà)
	# élan de départ aléatoire vers le haut → chaque envol dessine un arc différent
	_vel = Vector2(randf_range(-1.0, 1.0), randf_range(-1.6, -0.6)).normalized() * start_speed
	restart()
	set_process(true)


## Mise en sommeil (Pool) : plus d'émission, plus de logique.
func dormir() -> void:
	emitting = false
	set_process(false)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	self_modulate = Color(1, 1, 1, 1)


func _process(delta: float) -> void:
	match _phase:
		Phase.WAIT:
			_t += delta
			if _t >= wait_time:
				_phase = Phase.SEEK

		Phase.SEEK:
			if player == null or not is_instance_valid(player):
				_start_fade()
				return
			_seek_t += delta
			var target := player.global_position + Vector2(0.0, target_y_offset)
			# vitesse max qui grandit : le joueur ne peut pas la semer
			var max_speed := max_speed_start + max_speed_growth * _seek_t
			var dist := global_position.distance_to(target)

			if _direct:
				# charge directe après un premier raté : ligne droite, ne peut pas manquer
				global_position = global_position.move_toward(target, max_speed * delta)
			else:
				var desired := (target - global_position).normalized() * max_speed
				# on TOURNE la vélocité vers la cible au lieu de téléporter la
				# direction → trajectoire courbe et organique, pas une ligne droite
				_vel = _vel.move_toward(desired, seek_accel * (1.0 + _seek_t) * delta)
				global_position += _vel * delta
				# raté détecté : on se rapprochait, on repart en arrière → survol manqué
				if dist < _prev_dist - 1.0:
					_was_closing = true
				elif _was_closing and dist > _prev_dist + 1.0:
					_direct = true
			_prev_dist = dist

			if global_position.distance_to(target) <= catch_distance:
				_phase = Phase.LINGER
				_t = 0.0

		Phase.LINGER, Phase.FADE:
			# collée au joueur, elle le suit dans ses déplacements
			if player != null and is_instance_valid(player):
				global_position = player.global_position + Vector2(0.0, target_y_offset)
			if _phase == Phase.LINGER:
				_t += delta
				if _t >= linger_time:
					_start_fade()


func _start_fade() -> void:
	if _phase == Phase.FADE:
		return
	_phase = Phase.FADE
	_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(self, "self_modulate:a", 0.0, fade_duration)
	_tween.finished.connect(func () -> void:
		Player.changement_de_blood(blood_reward)
		if gauge_fill > 0:
			Player.changement_de_bloodheal(gauge_fill)
		Pool.rendre_sang(get_parent() as Node2D)  # retour au pool, jamais de queue_free
	)
