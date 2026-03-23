extends Node

const PLAYER_SCENE := preload("uid://vkm3ut4hytpr")
const CAMERA_SCRIPT := preload("uid://pcqotyxb20op")

func _ready() -> void:
	# Cherche le joueur existant ou l'instancie
	var player_body := get_tree().get_first_node_in_group("Player") as CharacterBody2D
	if not player_body:
		print("[SPAWN] Joueur absent, instanciation...")
		player_body = PLAYER_SCENE.instantiate()
		get_tree().current_scene.add_child(player_body)

		# Crée la caméra en frère du joueur
		var camera := Camera2D.new()
		camera.set_script(CAMERA_SCRIPT)
		camera.add_to_group("Camera")
		player_body.get_parent().add_child(camera)
		print("[SPAWN] Joueur + caméra instanciés")

	var spawn_pos = _get_spawn_position()
	print("[SPAWN] spawn_pos: ", spawn_pos)
	if spawn_pos != null:
		player_body.global_position = spawn_pos
		print("[SPAWN] Joueur placé à: ", spawn_pos)
	else:
		print("[SPAWN] Aucune position de spawn trouvée")

func _get_spawn_position():
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
