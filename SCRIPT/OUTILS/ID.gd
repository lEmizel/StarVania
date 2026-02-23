extends RefCounted
class_name ID

# Dictionnaire centralisé avec des sous-catégories
const IDS = {
	"Scene": {
		"MENU": "uid://dm012xrdmag4v",
		"Demo_scene_one": "res://SCRIPT/SCENE/First_demo_scene.tscn",
		"second_scene": "res://SCRIPT/SCENE/second_scene.tscn",
		"Castle_one": "res://SCRIPT/SCENE/castle_one.tscn",
		"S_1": "res://SCRIPT/SCENE/s_1.tscn",
		"S_2": "res://SCRIPT/SCENE/s_2.tscn",
		"S_3": "res://SCRIPT/SCENE/s_3.tscn",
	},
	"Character": {
		"HERO": "res://SCRIPT/CHARACTER/HERO/Hero_V02.tscn",
		"CAMERA_PLAYER": "res://SCRIPT/SYSTEME/Main_Camera.tscn",
	}
}

# Fonction pour obtenir des informations générales (peut être utilisée aussi pour les autres catégories)
static func get_info(category: String, identifier: String) -> Variant:
	if IDS.has(category) and IDS[category].has(identifier):
		return IDS[category][identifier]
	else:
		print("Erreur : catégorie ou identifiant inconnu -", category, identifier)
		return null

# Fonction pour obtenir une scène par son identifiant
static func get_scene(identifier: String) -> Variant:
	return IDS["Scene"].get(identifier, null)

# Fonction pour obtenir un personnage par son identifiant
static func get_character(identifier: String) -> Variant:
	return IDS["Character"].get(identifier, null)
