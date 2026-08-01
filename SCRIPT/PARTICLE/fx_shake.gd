extends AnimatedSprite2D

@onready var area: Area2D = $Area2D
@onready var collision_shape_2d: CollisionShape2D = $Area2D/CollisionShape2D

var damage: int = 150

func _ready() -> void:
	collision_shape_2d.disabled = true
	animation_finished.connect(queue_free)
	frame_changed.connect(_on_frame_changed)
	area.connect("body_entered", _on_body_entered)
	play("shake_fx")

func _on_frame_changed() -> void:
	if frame >= 5:
		collision_shape_2d.disabled = false
	if frame >= 7:
		collision_shape_2d.disabled = true

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("Player"):
		return
	if not body.has_method("apply_damage"):
		return
	body.apply_damage(damage, global_position.x, "onde_de_choc")
