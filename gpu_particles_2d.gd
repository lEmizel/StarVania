extends GPUParticles2D

@export var seek_speed: float = 280.0
@export var stop_distance: float = 10.0
@export var target_y_offset: float = -20.0
@export var linger_time: float = 0.40      # temps à rester “sur” le joueur
@export var fade_duration: float = 0.50    # durée du fondu (alpha)

var player: CharacterBody2D = null
var _arrived := false
var _linger_t := 0.0
var _fade_tw: Tween = null

func _ready() -> void:
	self_modulate = Color(1, 1, 1, 1)
	for n in get_tree().get_nodes_in_group("Player"):
		if n is CharacterBody2D:
			player = n
			break

func _process(delta: float) -> void:
	if player == null:
		return

	# si on est déjà en fondu, on laisse le tween faire
	if _fade_tw and _fade_tw.is_running():
		return

	if _arrived:
		_linger_t += delta
		if _linger_t >= linger_time:
			_start_fade()
		return

	# déplacement vers le joueur
	var target := player.global_position + Vector2(0.0, target_y_offset)
	global_position = global_position.move_toward(target, seek_speed * delta)

	# arrivée → on commence la phase "linger"
	if global_position.distance_to(target) <= stop_distance:
		_arrived = true
		_linger_t = 0.0

func _start_fade() -> void:
	_fade_tw = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_fade_tw.tween_property(self, "self_modulate:a", 0.0, fade_duration)
	_fade_tw.finished.connect(func ():
		var p := get_parent()
		Player.changement_de_blood(100)
		if is_instance_valid(p):
			p.queue_free()  # libère aussi cette particule
		else:
			queue_free()
	)
