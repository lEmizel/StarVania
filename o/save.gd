extends RefCounted

class_name SimpleSave

# Fonction pour nettoyer le chemin
static func clean_path(path: String) -> String:
	# Supprime les doublons de "res://"
	var cleaned_path = path.replace("pathres://", "res://")
	
	# Supprime les erreurs courantes comme "dateres://"
	cleaned_path = cleaned_path.replace("dateres://", "res://")
	
	return cleaned_path.strip_edges()  # Supprime les espaces ou les sauts de ligne autour du chemin

# Fonction pour sauvegarder les données de jeu
static func save_game_data(filename: String) -> int:
	filename = clean_path(filename)  # Nettoie le chemin avant de l'utiliser
	print("Saving to path:", filename)  # Debugging pour vérifier le chemin
	
	var game_data = GameData
	var game_data_dict = game_data.data  # Directement utiliser le dictionnaire de GameData

	var dir_access = DirAccess.open(filename.get_base_dir())
	if dir_access == null:
		print_debug("Directory: " + filename.get_base_dir() + " cannot be opened or created")
		return ERR_CANT_CREATE
	dir_access.make_dir_recursive(filename.get_base_dir())

	if dir_access.file_exists(filename):
		dir_access.remove(filename)

	var file = FileAccess.open(filename, FileAccess.WRITE)
	if file == null:
		print_debug("Failed to open file for writing: " + filename)
		return ERR_CANT_OPEN
	file.store_var(game_data_dict)
	file.close()
	return OK

# Fonction pour charger les données de jeu
static func load_game_data(filename: String) -> int:
	filename = clean_path(filename)  # Nettoie le chemin avant de l'utiliser
	print("Loading from path:", filename)  # Debugging pour vérifier le chemin
	
	var file = FileAccess.open(filename, FileAccess.READ)
	if file == null:
		print_debug("File: " + filename + " doesn't exist")
		return ERR_FILE_NOT_FOUND
	var game_data_dict = file.get_var()
	file.close()

	var game_data = GameData  # Réassignation explicite, normalement pas nécessaire
	game_data.data = game_data_dict
	game_data.reload()
	return OK
