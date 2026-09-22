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
## COÛT MESURÉ (22 sept. 2026, textures résidentes en VRAM) :
##   scene_06 : 795 Mo   scene_7 : 177 Mo   scene_08 : 275 Mo   scene_09 : 81 Mo
##   → 1,35 Go à quatre. scene_06 pèse à elle seule 60 % du total : c'est elle
##   qu'il faudra alléger le jour où la mémoire pose problème, pas les autres.
const SCENES_PRECHARGEES: Array[String] = [
	"res://SCRIPT/SCENE/scene_06.tscn",
	"res://SCRIPT/SCENE/scene_7.tscn",
	"res://SCRIPT/SCENE/scene_08.tscn",
	"res://SCRIPT/SCENE/scene_09.tscn",
]
var _prechargees: Dictionary = {}               # chemin res:// → PackedScene (la référence garde la scène en cache)
var _prechargement_en_cours: Array[String] = []  # au plus UN élément : les charges threadées sont sérialisées
var _file_prechargement: Array[String] = []      # scènes restant à précharger, dans l'ordre
var _chargement_niveau_en_cours := false         # un load_scene_with_loading est en vol


func _ready() -> void:
	set_process(false)
	precharger_scenes.call_deferred()


func precharger_scenes() -> void:
	# DEBUG PERF : `-- --sans-precharge` en ligne de commande → rien n'est gardé
	# en mémoire (test de pression mémoire sur Mac)
	if "--sans-precharge" in OS.get_cmdline_user_args():
		print("[LOAD] préchargement désactivé (--sans-precharge)")
		return
	# UNE charge threadée à la fois : deux threads qui chargent des scènes
	# partageant des ressources (fond, colonne, shader du flou) font échouer le
	# parsing par intermittence → les scènes sont préchargées l'une après l'autre
	for chemin in SCENES_PRECHARGEES:
		if not _prechargees.has(chemin) and not (chemin in _prechargement_en_cours) \
				and not (chemin in _file_prechargement):
			_file_prechargement.append(chemin)
	_lancer_prochain_prechargement()


## démarre le préchargement suivant de la file, si rien d'autre ne charge
func _lancer_prochain_prechargement() -> void:
	if _chargement_niveau_en_cours or not _prechargement_en_cours.is_empty() or _file_prechargement.is_empty():
		return
	var chemin: String = _file_prechargement.pop_front()
	if _prechargees.has(chemin):
		_lancer_prochain_prechargement()
		return
	if ResourceLoader.load_threaded_request(chemin) == OK:
		_prechargement_en_cours.append(chemin)
		set_process(true)
		print("[LOAD] préchargement en arrière-plan : ", chemin)
	else:
		push_error("[LOAD] préchargement impossible : " + chemin)
		_lancer_prochain_prechargement()


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
		_lancer_prochain_prechargement()   # au suivant


## DEBUG PERF (F7) : lâche les scènes préchargées → leurs textures sont libérées
## si plus rien ne les utilise ; les prochains chargements repassent par l'écran
## de chargement
func liberer_prechargement() -> void:
	var avant := Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1e6
	_prechargees.clear()
	_file_prechargement.clear()
	await get_tree().process_frame
	await get_tree().process_frame
	print("[LOAD] préchargement libéré : textures %.0f Mo → %.0f Mo" % [
		avant, Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1e6])


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
		# L'écran de chargement est DÉCORATIF. S'il manque, on continue SANS lui :
		# ce `return` rendait le bouton « retour au menu » complètement mort dans
		# le build (22 sept. 2026 — la scène référençait une capture d'écran
		# supprimée du projet, absente du .pck mais encore dans le cache de
		# l'éditeur). Une décoration ne doit jamais bloquer une navigation.
		push_warning("[LOAD] écran de chargement introuvable (" + str(loading_scene_path)
			+ ") — on bascule sans lui")

	# 2) Décale d’une frame pour laisser la loading screen se rendre
	call_deferred("_do_async_load")


# ------------------------------------------------------------------
# Appelé une frame plus tard pour éviter de bloquer le rendu
# ------------------------------------------------------------------
func _do_async_load() -> void:
	# une seule charge threadée à la fois (voir precharger_scenes) : on attend
	# la fin d'un préchargement en cours, et la file est suspendue pendant nous
	_chargement_niveau_en_cours = true
	while not _prechargement_en_cours.is_empty():
		await get_tree().create_timer(0.01).timeout
	var prete := scene_prechargee(_target_scene_path)
	if prete != null:
		# c'était justement la scène qui finissait de se précharger
		_chargement_niveau_en_cours = false
		_basculer(prete.instantiate())
		_lancer_prochain_prechargement()
		return
	# 3) Lance la requête de pré-chargement asynchrone
	var err = ResourceLoader.load_threaded_request(_target_scene_path)
	if err != OK:
		push_error("[LOAD] load_threaded_request a échoué pour " + str(_target_scene_path))
		_fin_chargement_niveau()
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
			Warmup.chauffer_arbre(scene, "niveau")
			_fin_chargement_niveau()
		else:
			push_error("[LOAD] la ressource chargée n’est pas un PackedScene ! ")
			_fin_chargement_niveau()
	else:
		push_error("[LOAD] chargement asynchrone échoué, status=" + str(status))
		_fin_chargement_niveau()


func _fin_chargement_niveau() -> void:
	_chargement_niveau_en_cours = false
	_lancer_prochain_prechargement()


func _basculer(scene: Node) -> void:
	replace_scene_in_viewport(scene)
	save_scene()
	Warmup.chauffer_arbre(scene, "niveau")


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
