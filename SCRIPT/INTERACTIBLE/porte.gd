extends Area2D

@export var id: int = 0
@export_file("*.tscn") var target_scene: String
@onready var collision_shape_2d: CollisionShape2D = $CollisionShape2D
@onready var marker_2d: Marker2D = $Marker2D


var _player_inside := false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("Player"):
		_player_inside = true

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("Player"):
		_player_inside = false

func _input(event: InputEvent) -> void:
	if not _player_inside:
		return
	if Input.is_action_just_pressed("up"):
		if target_scene.is_empty():
			push_warning("[PORTE] Aucune scène cible définie")
			return
		Player.last_door_id = id
		Loader.load_scene_with_loading(target_scene)
