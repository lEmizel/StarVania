extends ColorRect
## Explosion de la boule de sang : anime le uniform 'progress' du shader
## de 0 à 1 sur sa durée de vie, puis se détruit.
## (ColorRect : ses UV couvrent tout le rect, support idéal d'un shader procédural)

@export var duration := 0.4

var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	var p := clampf(_t / duration, 0.0, 1.0)
	material.set_shader_parameter("progress", p)
	if p >= 1.0:
		queue_free()
