extends Node

const PLAYER_SCENE := preload("uid://vkm3ut4hytpr")
const CAMERA_SCENE := preload("uid://bcr77cmqqqma4")

func _ready() -> void:
	# Calcule la position de spawn avant d'instancier le joueur
	await get_tree().process_frame
	var spawn_pos = _get_spawn_position()

	var player_body := get_tree().get_first_node_in_group("Player") as CharacterBody2D
	if not player_body:
		player_body = _instantiate_player(spawn_pos)
		if not player_body:
			return
	if spawn_pos == null:
		push_warning("[SPAWN] Aucune position de spawn trouvée")
		return

	player_body.global_position = spawn_pos
	player_body.velocity = Vector2.ZERO
	player_body.apply_floor_snap()
	player_body.change_state(player_body.States.IDLE)
	player_body.animator.play("idle")

	# Cale la caméra immédiatement sur le joueur
	var cam = get_tree().get_first_node_in_group("Camera")
	if cam:
		cam.current_offset = Vector2(0, -150)
		cam.global_position = (player_body.global_position + cam.current_offset).floor()


func _instantiate_player(spawn_pos) -> CharacterBody2D:
	var parent = get_tree().current_scene
	if not parent:
		parent = get_parent()
	if not parent:
		push_warning("[SPAWN] Aucun parent trouvé, spawn annulé")
		return null

	var player_body: CharacterBody2D = PLAYER_SCENE.instantiate()
	# Positionne le joueur AVANT de l'ajouter à la scène
	if spawn_pos != null:
		player_body.global_position = spawn_pos
	parent.add_child(player_body)

	var camera: Camera2D = CAMERA_SCENE.instantiate()
	camera.add_to_group("Camera")
	parent.add_child(camera)

	return player_body


func _get_spawn_position():
	# 1) Arrivée depuis une porte
	if Player.last_door_id >= 0:
		var door_id := Player.last_door_id
		Player.last_door_id = -1
		for p in get_tree().get_nodes_in_group("Porte"):
			if p.id == door_id:
				if p.has_node("Marker2D"):
					return p.get_node("Marker2D").global_position
				return p.global_position
		push_warning("[SPAWN] Aucune porte avec id=", door_id)

	# 2) Dernier checkpoint visité
	if Player.last_checkpoint_path != NodePath():
		var cp := get_node_or_null(Player.last_checkpoint_path)
		if cp:
			return cp.global_position

	# 3) Checkpoint marqué actif dans la scène
	var checkpoints := get_tree().get_nodes_in_group("Checkpoint")
	for cp in checkpoints:
		if cp.active:
			return cp.global_position

	# 4) Fallback : premier checkpoint trouvé
	if checkpoints.size() > 0:
		return checkpoints[0].global_position

	return null
