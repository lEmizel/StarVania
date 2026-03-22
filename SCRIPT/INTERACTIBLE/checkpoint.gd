extends Node2D
@onready var sprite_2d: Sprite2D = $Sprite2D
@onready var area: Area2D = $Area2D

@export var active := false
var _shader_material: ShaderMaterial

func _ready() -> void:
	_shader_material = sprite_2d.material
	if not active:
		sprite_2d.material = null
	area.body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if active:
		return
	if body.is_in_group("Player"):
		active = true
		sprite_2d.material = _shader_material
		Player.last_checkpoint_path = get_path()
