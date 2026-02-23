extends Node

var data = {
	"count_test": 0,
	"scene_save_id": null,         # ID de la scène actuelle (pas le chemin)
	"Player.hp": 30,
	"player_position": Vector2.ZERO,
	"last_direction": 1,
}

func _input(event: InputEvent):
	if event.is_action_just_pressed("jump"):
		data["count_test"] += 1
		print("Test compteur :", data["count_test"])

# Fonction pour synchroniser les variables importantes (appelée avant save)
func variable_to_save():
	data["player_position"] = Player.position
	data["Player.hp"] = Player.hp
	data["last_direction"] = Player.last_direction

# Fonction appelée pour recharger les données après un chargement
func reload():
	var scene_id = data.get("scene_save_id", null)
	print("Scene ID rechargée :", scene_id)
	
	if scene_id != null:
		SceneManager.load_scene_with_loading("Scene", scene_id)
	else:
		print("Aucune scène sauvegardée.")

	if "player_position" in data:
		Player.position = data["player_position"]
		print("Position restaurée :", Player.position)

	if "Player.hp" in data:
		Player.hp = data["Player.hp"]
		print("HP restauré :", Player.hp)

	if "last_direction" in data:
		Player.last_direction = data["last_direction"]
		print("Direction restaurée :", Player.last_direction)

	if "count_test" in data:
		print("Compteur restauré :", data["count_test"])
