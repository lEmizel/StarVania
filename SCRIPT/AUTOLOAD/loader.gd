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
## Depuis le menu on ne précharge que les ENTRÉES des démos (23 sept. 2026,
## demande de Kaoru) : scene_7 (DEMO 1), scene_08 (DEMO 2) et, depuis le
## 30 sept., sc_10 (DEMO 3). Leurs suites (scene_06, scene_09) ne sont pas
## gardées en mémoire au menu.
const SCENES_PRECHARGEES: Array[String] = [
	"res://SCRIPT/SCENE/scene_7.tscn",
	"res://SCRIPT/SCENE/scene_08.tscn",
	"res://SCRIPT/SCENE/sc_10.tscn",
]
## Le menu principal : ses « voisins » sont les entrées des démos ci-dessus
const MENU_SCENE := "uid://dm012xrdmag4v"        # SCRIPT/MENU/menu.tscn
var _prechargees: Dictionary = {}               # chemin res:// → PackedScene (la référence garde la scène en cache)
var _sans_precharge := false                    # `-- --sans-precharge` : rien n'est gardé
var _prechargement_en_cours: Array[String] = []  # au plus UN élément : les charges threadées sont sérialisées
var _file_prechargement: Array[String] = []      # scènes restant à précharger, dans l'ordre
var _chargement_niveau_en_cours := false         # un load_scene_with_loading est en vol

# ------------------------------------------------------------------
# GARDE-FOUS (3 oct. 2026) : chez un ami de Kaoru, le préchargement de scene_08
# n'a jamais rendu la main ; il a choisi DEMO 3, et le chargeur ATTENDAIT SANS
# LIMITE la fin de ce préchargement avant de charger la démo demandée :
# « LOADING » pour toujours, le journal s'arrêtant sur « démarrage du loading ».
# Un confort d'arrière-plan ne doit jamais bloquer le niveau demandé :
#   • un niveau demandé n'attend pas plus de ATTENTE_PRECHARGE_MAX la fin du
#     préchargement d'une AUTRE scène, puis il se charge sans lui ;
#   • un préchargement qui n'avance plus depuis PRECHARGE_BLOQUE est abandonné
#     (il ne retient plus la file) ;
#   • tout chargement qui dure écrit où il en est toutes les SUIVI secondes : le
#     journal dit si ça avance lentement ou si c'est bloqué, et sur quelle scène.
# ------------------------------------------------------------------
const ATTENTE_PRECHARGE_MAX := 1.5
const PRECHARGE_BLOQUE := 15.0
const SUIVI := 2.0
var _suivi: Dictionary = {}                      # chemin → {progres, avance, debut, dit} (ms)


func _ready() -> void:
	# le chargeur ne se fige jamais : un préchargement qui finit pendant une pause
	# doit être relevé (sinon un niveau demandé derrière lui attendrait la reprise)
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	precharger_scenes.call_deferred()


func precharger_scenes() -> void:
	# DEBUG PERF : `-- --sans-precharge` en ligne de commande → rien n'est gardé
	# en mémoire (test de pression mémoire sur Mac)
	if "--sans-precharge" in OS.get_cmdline_user_args():
		_sans_precharge = true
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
		var statut := _suivre(chemin, "préchargement")
		if statut == ResourceLoader.THREAD_LOAD_LOADED:
			var res := ResourceLoader.load_threaded_get(chemin)
			_prechargement_en_cours.erase(chemin)
			_suivi.erase(chemin)
			if res is PackedScene:
				_prechargees[chemin] = res
				print("[LOAD] préchargé et gardé en mémoire : ", chemin)
		elif statut != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			_prechargement_en_cours.erase(chemin)
			_suivi.erase(chemin)
			push_error("[LOAD] échec du préchargement : " + chemin)
		elif _sans_progres_depuis(chemin) >= PRECHARGE_BLOQUE:
			# il n'avance plus : on ne l'attend plus, la file continue sans lui
			push_warning("[LOAD] préchargement BLOQUÉ, abandonné : %s (arrêté à %d %% depuis %.0f s)" % [
				chemin, roundi(float(_suivi[chemin]["progres"]) * 100.0), _sans_progres_depuis(chemin)])
			_prechargement_en_cours.erase(chemin)
			_suivi.erase(chemin)
	if _prechargement_en_cours.is_empty():
		set_process(false)
		_lancer_prochain_prechargement()   # au suivant


## où en est un chargement threadé : rend son statut, note quand il a avancé
## pour la dernière fois, et écrit sa progression toutes les SUIVI secondes
## tant qu'il dure (un chargement normal finit avant et n'écrit rien)
func _suivre(chemin: String, etiquette: String) -> int:
	var progression: Array = []
	var statut := ResourceLoader.load_threaded_get_status(chemin, progression)
	var p: float = progression[0] if progression.size() > 0 else 0.0
	var maintenant := Time.get_ticks_msec()
	if not _suivi.has(chemin):
		_suivi[chemin] = {"progres": p, "avance": maintenant, "debut": maintenant, "dit": maintenant}
	var s: Dictionary = _suivi[chemin]
	if p > float(s["progres"]) + 0.0001:
		s["progres"] = p
		s["avance"] = maintenant
	if statut == ResourceLoader.THREAD_LOAD_IN_PROGRESS and maintenant - int(s["dit"]) >= int(SUIVI * 1000.0):
		s["dit"] = maintenant
		print("[LOAD] %s toujours en cours : %s — %d %% après %.1f s, sans avancer depuis %.1f s" % [
			etiquette, chemin, roundi(p * 100.0), (maintenant - int(s["debut"])) / 1000.0,
			(maintenant - int(s["avance"])) / 1000.0])
	return statut


## depuis combien de secondes ce chargement n'a pas avancé
func _sans_progres_depuis(chemin: String) -> float:
	if not _suivi.has(chemin):
		return 0.0
	return (Time.get_ticks_msec() - int(_suivi[chemin]["avance"])) / 1000.0


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
	# une seule charge threadée à la fois (voir precharger_scenes) : on laisse au
	# préchargement en vol le temps de finir, et la file est suspendue pendant
	# nous. Mais si c'est une AUTRE scène que la nôtre et qu'elle traîne, on ne
	# l'attend pas plus de ATTENTE_PRECHARGE_MAX (voir GARDE-FOUS)
	_chargement_niveau_en_cours = true
	var cible := _chemin_res(_target_scene_path)
	var debut_attente := Time.get_ticks_msec()
	while not _prechargement_en_cours.is_empty():
		var attendu := (Time.get_ticks_msec() - debut_attente) / 1000.0
		if not (cible in _prechargement_en_cours) and attendu >= ATTENTE_PRECHARGE_MAX:
			print("[LOAD] le préchargement de ", _noms(_prechargement_en_cours),
				" traîne : on charge ", cible.get_file(), " sans l'attendre")
			break
		await get_tree().process_frame
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
	# une vérification par image, sans minuterie (elle tourne aussi en pause) ;
	# si le chargement dure, _suivre écrit où il en est
	var status := _suivre(_target_scene_path, "chargement")
	while status == ResourceLoader.ThreadLoadStatus.THREAD_LOAD_IN_PROGRESS:
		await get_tree().process_frame
		status = _suivre(_target_scene_path, "chargement")
	_suivi.erase(_target_scene_path)
	if status == ResourceLoader.ThreadLoadStatus.THREAD_LOAD_LOADED:
		# 4) Récupère et instancie la scène finale
		var res = ResourceLoader.load_threaded_get(_target_scene_path)
		if res is PackedScene:
			# on la GARDE : la mort du joueur recharge ce même niveau, il doit
			# repartir sans écran de chargement
			_prechargees[_chemin_res(_target_scene_path)] = res
			var scene = res.instantiate()
			print("[LOAD] scène finale instanciée, remplacement…")
			replace_scene_in_viewport(scene)
			save_scene()
			Warmup.chauffer_arbre(scene, "niveau")
			_niveau_pose(scene)
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
	_niveau_pose(scene)


# ------------------------------------------------------------------
# VOISINAGE (23 sept. 2026, idée de Kaoru) : à chaque niveau posé, on regarde
# ses PASSAGES et on précharge leurs cibles en arrière-plan pendant que le
# joueur joue — plus d'écran de chargement au passage suivant. Et on LÂCHE ce
# qui n'est plus voisin : la mémoire suit le joueur au lieu de grossir jusqu'à
# la fin de la partie. Reste résident : le niveau courant (sa mort le recharge
# à l'instant) + les cibles de ses passages. Pour le menu, les voisins sont
# les entrées des démos.
# ------------------------------------------------------------------
func _niveau_pose(scene: Node) -> void:
	var courant := _chemin_res(_target_scene_path)
	var voisins: Array[String] = []
	if courant == _chemin_res(MENU_SCENE):
		voisins = SCENES_PRECHARGEES.duplicate()
	else:
		voisins = _cibles_des_passages(scene, courant)

	# 1) lâcher ce qui n'est ni courant ni voisin (les textures partent avec, si
	#    plus rien ne les utilise ; celles partagées avec le niveau courant restent)
	var laches: Array[String] = []
	for chemin in _prechargees.keys():
		if chemin != courant and not voisins.has(chemin):
			laches.append(chemin)
	for chemin in laches:
		_prechargees.erase(chemin)

	# 2) mettre les voisins manquants en file (une charge threadée à la fois)
	_file_prechargement.clear()
	if not _sans_precharge:
		for chemin in voisins:
			if not _prechargees.has(chemin) and not (chemin in _prechargement_en_cours):
				_file_prechargement.append(chemin)

	print("[LOAD] niveau posé : ", courant.get_file(),
		" | voisins : ", _noms(voisins),
		" | lâchés : ", _noms(laches))
	_lancer_prochain_prechargement()


## les scènes visées par les passages/portes de ce niveau (tout nœud portant
## un `target_scene`), en chemins res://, sans doublon ni le niveau lui-même
func _cibles_des_passages(racine: Node, courant: String) -> Array[String]:
	var cibles: Array[String] = []
	var pile: Array[Node] = [racine]
	while not pile.is_empty():
		var n: Node = pile.pop_back()
		if "target_scene" in n:
			var brut := str(n.target_scene)
			if not brut.is_empty():
				var chemin := _chemin_res(brut)
				if chemin != courant and not cibles.has(chemin):
					cibles.append(chemin)
		for enfant in n.get_children():
			pile.append(enfant)
	return cibles


static func _noms(chemins: Array) -> String:
	var noms: PackedStringArray = []
	for c in chemins:
		noms.append(str(c).get_file().get_basename())
	return "[" + ", ".join(noms) + "]"


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
