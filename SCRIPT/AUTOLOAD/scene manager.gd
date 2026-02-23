# SceneManager.gd

extends Node

# Initialise la scène actuelle
var current_scene: Node = null

func _ready():
	# Vérifie si la scène actuelle est `second_scene` en utilisant FIND_SCENE
	current_scene = FIND_SCENE.find_scene_in_tree(get_tree().get_root())
	if current_scene and current_scene.name == "second_scene":
		print("La scène actuelle est bien second_scene.")
	else:
		print("La scène actuelle n'est pas second_scene.")
		current_scene = null

# Fonction pour charger une scène en arrière-plan et l'ajouter comme frère de la scène actuelle
func load_scene_as_sibling(scene_name: String):
	# Vérifier si la scène actuelle est définie
	if current_scene == null:
		print("Erreur : La scène actuelle (second_scene) n'est pas trouvée.")
		return
	
	# Obtenir les informations de la scène à charger depuis le dictionnaire d'ID
	var scene_info = ID.get_info("Scene", scene_name)
	if scene_info == null:
		print("Erreur : Scène non trouvée dans l'ID.")
		return
	
	# Récupère le chemin et la position de la scène, s'ils existent
	var scene_path = scene_info.get("path", "")
	var scene_position = scene_info.has("position") ? scene_info["position"] : Vector2.ZERO
	
	# Précharger et instancier la scène à ajouter
	var scene_resource = load(scene_path)
	if scene_resource is PackedScene:
		var scene_instance = scene_resource.instantiate()
		scene_instance.position = scene_position
		current_scene.get_parent().add_child(scene_instance)  # Ajoute la scène comme frère de `second_scene`
		print("Scène", scene_name, "chargée comme frère de second_scene à la position", scene_position)
	else:
		print("Erreur : la scène", scene_name, "n'est pas une PackedScene.")

# Fonction d'input pour gérer le chargement de S_1 comme frère de second_scene
func _input(event):
	if event.is_action_pressed("debug"):
		print("Chargement de S_1 comme frère de second_scene.")
		load_scene_as_sibling("S_1")
