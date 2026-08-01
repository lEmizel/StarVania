extends GPUParticles2D
## Récolte de sang, en 4 phases :
##   1. WAIT   — s'attarde sur le cadavre
##   2. SEEK   — s'envole vers le joueur en arc naturel (pilotage par vélocité,
##               vitesse max croissante → impossible à semer, rattrapage garanti)
##   3. LINGER — reste collée sur le joueur (le suit s'il bouge)
##   4. FADE   — fondu, crédite le blood, se nettoie

@export var wait_time: float = 1.0        ## temps sur le cadavre avant le départ
@export var linger_time: float = 0.0      ## temps sur le joueur avant le fondu (0 = fondu immédiat)
@export var fade_duration: float = 0.50
@export var target_y_offset: float = -60.0

@export var start_speed: float = 260.0        ## impulsion initiale (direction aléatoire vers le haut)
@export var seek_accel: float = 900.0         ## force de pilotage vers le joueur
@export var max_speed_start: float = 500.0
@export var max_speed_growth: float = 900.0   ## la vitesse max grandit avec le temps de poursuite
@export var catch_distance: float = 24.0

@export var gauge_fill: int = 25   ## points ajoutés à la jauge de sang à l'arrivée
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


func _ready() -> void:
	self_modulate = Color(1, 1, 1, 1)
	for n in get_tree().get_nodes_in_group("Player"):
		if n is CharacterBody2D:
			player = n
			break
	# élan de départ aléatoire vers le haut → chaque envol dessine un arc différent
	_vel = Vector2(randf_range(-1.0, 1.0), randf_range(-1.6, -0.6)).normalized() * start_speed


func _process(delta: float) -> void:
	match _phase:
		Phase.WAIT:
			_t += delta
			if _t >= wait_time:
				_phase = Phase.SEEK

		Phase.SEEK:
			if player == null:
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
			if player != null:
				global_position = player.global_position + Vector2(0.0, target_y_offset)
			if _phase == Phase.LINGER:
				_t += delta
				if _t >= linger_time:
					_start_fade()


func _start_fade() -> void:
	if _phase == Phase.FADE:
		return
	_phase = Phase.FADE
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "self_modulate:a", 0.0, fade_duration)
	tw.finished.connect(func () -> void:
		Player.changement_de_blood(blood_reward)
		Player.changement_d_endurance(gauge_fill)  # remplit la jauge de sang
		var p := get_parent()
		if is_instance_valid(p):
			p.queue_free()  # libère aussi cette particule
		else:
			queue_free()
	)
