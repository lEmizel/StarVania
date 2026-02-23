extends Node

# UID de ta scène de loading (écran vide)
var loading_scene_path: String = "uid://cei7xxsf7frsh"

# Chemin de la scène finale à charger (mémorisé)
var _target_scene_path: String

# ------------------------------------------------------------------
# POINT D’ENTRÉE : appelle cette méthode pour lancer le loading
# ------------------------------------------------------------------
func load_scene_with_loading(final_scene_path: String) -> void:
	_target_scene_path = final_scene_path
	print("[LOAD] démarrage du loading for:", _target_scene_path)

	# 1) Instancie et affiche immédiatement l’écran de loading
	var packed = load(loading_scene_path)
	if packed is PackedScene:
		replace_scene_in_viewport(packed.instantiate())
	else:
		push_error("[LOAD] impossible de charger la loading scene → " + str(loading_scene_path))
		return

	# 2) Décale d’une frame pour laisser la loading screen se rendre
	call_deferred("_do_async_load")


# ------------------------------------------------------------------
# Appelé une frame plus tard pour éviter de bloquer le rendu
# ------------------------------------------------------------------
func _do_async_load() -> void:
	# 3) Lance la requête de pré-chargement asynchrone
	var err = ResourceLoader.load_threaded_request(_target_scene_path)
	if err != OK:
		push_error("[LOAD] load_threaded_request a échoué pour " + str(_target_scene_path))
		return
	print("[LOAD] preload async lancé…")
	_continue_preloading()


# ------------------------------------------------------------------
# Boucle de vérification asynchrone
# ------------------------------------------------------------------
func _continue_preloading() -> void:
	var status = ResourceLoader.load_threaded_get_status(_target_scene_path)
	if status == ResourceLoader.ThreadLoadStatus.THREAD_LOAD_IN_PROGRESS:
		# on attend 10ms puis on recommence
		await get_tree().create_timer(0.01).timeout
		_continue_preloading()
	elif status == ResourceLoader.ThreadLoadStatus.THREAD_LOAD_LOADED:
		# 4) Récupère et instancie la scène finale
		var res = ResourceLoader.load_threaded_get(_target_scene_path)
		if res is PackedScene:
			var scene = res.instantiate()
			print("[LOAD] scène finale instanciée, remplacement…")
			replace_scene_in_viewport(scene)
			save_scene()
		else:
			push_error("[LOAD] la ressource chargée n’est pas un PackedScene ! ")
	else:
		push_error("[LOAD] chargement asynchrone échoué, status=" + str(status))


# ------------------------------------------------------------------
# Remplace intégralement le contenu du conteneur MAIN_SCENE
# ------------------------------------------------------------------
func replace_scene_in_viewport(scene: Node) -> void:
	var holder = get_tree().get_first_node_in_group("MAIN_SCENE") as Node
	if not holder:
		push_error("[REPLACE] pas de nœud dans MAIN_SCENE")
		return
	for child in holder.get_children():
		child.queue_free()
	holder.add_child(scene)


# ------------------------------------------------------------------
# À toi de remplir plus tard !
# ------------------------------------------------------------------
func save_scene() -> void:
	pass
