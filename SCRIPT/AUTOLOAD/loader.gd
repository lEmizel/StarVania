extends Node

# UID de ta scène de loading (écran vide)
var loading_scene_path: String = "uid://cei7xxsf7frsh"

# Chemin de la scène finale à charger (mémorisé)
var _target_scene_path: String

# ------------------------------------------------------------------
# PRÉCHARGEMENT : scènes chargées en arrière-plan dès l'ouverture du menu
# principal et GARDÉES EN MÉMOIRE toute la partie → bascule instantanée,
# sans écran de chargement. Coût : leurs textures restent résidentes.
# ------------------------------------------------------------------
const SCENES_PRECHARGEES: Array[String] = [
	"res://SCRIPT/SCENE/scene_06.tscn",
	"res://SCRIPT/SCENE/scene_7.tscn",
]
var _prechargees: Dictionary = {}               # chemin res:// → PackedScene (la référence garde la scène en cache)
var _prechargement_en_cours: Array[String] = []


func _ready() -> void:
	set_process(false)
	precharger_scenes.call_deferred()


func precharger_scenes() -> void:
	for chemin in SCENES_PRECHARGEES:
		if _prechargees.has(chemin) or chemin in _prechargement_en_cours:
			continue
		if ResourceLoader.load_threaded_request(chemin) == OK:
			_prechargement_en_cours.append(chemin)
			print("[LOAD] préchargement en arrière-plan : ", chemin)
		else:
			push_error("[LOAD] préchargement impossible : " + chemin)
	set_process(not _prechargement_en_cours.is_empty())


func _process(_delta: float) -> void:
	for chemin in _prechargement_en_cours.duplicate():
		var statut := ResourceLoader.load_threaded_get_status(chemin)
		if statut == ResourceLoader.THREAD_LOAD_LOADED:
			var res := ResourceLoader.load_threaded_get(chemin)
			_prechargement_en_cours.erase(chemin)
			if res is PackedScene:
				_prechargees[chemin] = res
				print("[LOAD] préchargé et gardé en mémoire : ", chemin)
		elif statut != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			_prechargement_en_cours.erase(chemin)
			push_error("[LOAD] échec du préchargement : " + chemin)
	if _prechargement_en_cours.is_empty():
		set_process(false)


## la PackedScene déjà en mémoire pour ce chemin (res:// ou uid://), sinon null
func scene_prechargee(chemin: String) -> PackedScene:
	return _prechargees.get(_chemin_res(chemin))


static func _chemin_res(chemin: String) -> String:
	if chemin.begins_with("uid://"):
		var id := ResourceUID.text_to_id(chemin)
		if ResourceUID.has_id(id):
			return ResourceUID.get_id_path(id)
	return chemin

# ------------------------------------------------------------------
# POINT D’ENTRÉE : appelle cette méthode pour lancer le loading
# ------------------------------------------------------------------
func load_scene_with_loading(final_scene_path: String) -> void:
	_target_scene_path = final_scene_path
	print("[LOAD] démarrage du loading for:", _target_scene_path)

	# 0) Scène déjà en mémoire → bascule immédiate, sans écran de chargement.
	#    Différée : on peut arriver ici depuis un signal physique (passage,
	#    mort), où ajouter des corps à l'arbre est interdit.
	var prete := scene_prechargee(final_scene_path)
	if prete != null:
		print("[LOAD] scène préchargée → bascule instantanée")
		_basculer.call_deferred(prete.instantiate())
		return

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


func _basculer(scene: Node) -> void:
	replace_scene_in_viewport(scene)
	save_scene()


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
