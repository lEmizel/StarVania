extends Node

# Variables pour la gestion des scènes
var scene_to_load_path = null
var scene_to_load = null
var preload_scene = null
var loading_scene_path = "uid://cei7xxsf7frsh"  # Chemin vers la scène de loading

func pre_load():
	if scene_to_load_path == "uid://cei7xxsf7frsh":
		preload_scene = preload("uid://cei7xxsf7frsh")

# Fonction pour charger une scène avec un écran de loading
func load_scene_with_loading(final_scene_path):
	scene_to_load_path = final_scene_path
	print("Path de la scène finale :", scene_to_load_path)
	
	# Charge la scène de loading et l'instancie immédiatement
	var loading_scene = load(loading_scene_path)
	if loading_scene is PackedScene:
		loading_scene = loading_scene.instantiate()
	replace_scene_in_viewport(loading_scene)
	
	# Commence à précharger la scène finale en arrière-plan
	start_preloading_scene()

func replace_scene_in_viewport(scene):
	var holder := get_tree().get_first_node_in_group("MAIN_SCENE") as Node2D
	if not holder:
		push_error("Aucun nœud dans le groupe MAIN_SCENE.")
		return

	# Supprime les enfants existants
	for child in holder.get_children():
		child.queue_free()
	# Ajoute la nouvelle scène (déjà instanciée)
	holder.add_child(scene)
	

# Fonction pour commencer le préchargement de la scène finale en arrière-plan
func start_preloading_scene():
	var load_error = ResourceLoader.load_threaded_request(scene_to_load_path)
	if load_error != OK:
		print("Erreur lors de la demande de chargement asynchrone.")
	else:
		print("Préchargement de la scène en cours...")
		preload_step()

func preload_step():
	# Vérifie l'état de chargement de la scène
	var status = ResourceLoader.load_threaded_get_status(scene_to_load_path)
	if status == ResourceLoader.ThreadLoadStatus.THREAD_LOAD_LOADED:
		# Charge la ressource préchargée
		scene_to_load = ResourceLoader.load_threaded_get(scene_to_load_path)
		# Instancie la scène finale si nécessaire
		if scene_to_load is PackedScene:
			scene_to_load = scene_to_load.instantiate()
		replace_scene_in_viewport(scene_to_load)  # Affiche la scène finale
		save_scene()
	elif status == ResourceLoader.ThreadLoadStatus.THREAD_LOAD_IN_PROGRESS:
		# Continue le chargement asynchrone
		await get_tree().create_timer(0.01).timeout
		preload_step()
	else:
		print("Erreur : le chargement de la scène a échoué.")

# Sauvegarde le chemin de la scène actuelle
func save_scene():
	#GameData.data["scene_save_path"] = scene_to_load_path
	pass
