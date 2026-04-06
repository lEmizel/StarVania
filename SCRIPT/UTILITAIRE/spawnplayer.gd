extends Node

const PLAYER_SCENE := preload("uid://vkm3ut4hytpr")
const CAMERA_SCRIPT := preload("uid://pcqotyxb20op")

func _ready() -> void:
	# Cherche le joueur existant ou l'instancie
	var player_body := get_tree().get_first_node_in_group("Player") as CharacterBody2D
	if not player_body:
		print("[SPAWN] Joueur absent, instanciation...")
		player_body = PLAYER_SCENE.instantiate()
		var parent = get_tree().current_scene
		if not parent:
			parent = get_parent()
		if not parent:
			push_warning("[SPAWN] Aucun parent trouvé, spawn annulé")
			return
		parent.add_child(player_body)

		# Crée la caméra en frère du joueur
		var camera := Camera2D.new()
		camera.set_script(CAMERA_SCRIPT)
		camera.add_to_group("Camera")
		parent.add_child(camera)
		print("[SPAWN] Joueur + caméra instanciés")

	# Attend une frame pour que la scène soit prête
	await get_tree().process_frame
	var spawn_pos = _get_spawn_position()
	print("[SPAWN] spawn_pos: ", spawn_pos)
	if spawn_pos != null:
		player_body.global_position = spawn_pos
		player_body.velocity = Vector2.ZERO
		player_body.apply_floor_snap()
		player_body.change_state(player_body.States.IDLE)
		# Cale la caméra immédiatement sur le joueur
		var cam = get_tree().get_first_node_in_group("Camera")
		if cam:
			cam.current_offset = Vector2(0, -150)
			cam.global_position = (player_body.global_position + cam.current_offset).floor()
		print("[SPAWN] Joueur placé à: ", spawn_pos)
	else:
		print("[SPAWN] Aucune position de spawn trouvée")

func _get_spawn_position():
	# 0) Arrivée depuis une porte
	if Player.last_door_id >= 0:
		var door_id := Player.last_door_id
		Player.last_door_id = -1
		var portes := get_tree().get_nodes_in_group("Porte")
		for p in portes:
			if p.id == door_id:
				print("[SPAWN] porte trouvée id=", door_id)
				if p.has_node("Marker2D"):
					return p.get_node("Marker2D").global_position
				return p.global_position
		print("[SPAWN] aucune porte avec id=", door_id)

	# 1) Dernier checkpoint visité (stocké dans l'autoload)
	print("[SPAWN] last_checkpoint_path: ", Player.last_checkpoint_path)
	if Player.last_checkpoint_path != NodePath():
		var cp := get_node_or_null(Player.last_checkpoint_path)
		print("[SPAWN] checkpoint depuis autoload: ", cp)
		if cp:
			return cp.global_position

	# 2) Sinon, cherche un checkpoint marqué actif dans la scène
	var checkpoints := get_tree().get_nodes_in_group("Checkpoint")
	print("[SPAWN] checkpoints trouvés: ", checkpoints.size())
	for cp in checkpoints:
		print("[SPAWN] - ", cp.name, " active: ", cp.active)
		if cp.active:
			return cp.global_position

	# 3) Fallback : premier checkpoint trouvé
	if checkpoints.size() > 0:
		return checkpoints[0].global_position

	return null
