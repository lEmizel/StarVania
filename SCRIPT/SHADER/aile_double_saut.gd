@tool
extends Node2D
## ============================================================================
## AILE DE DOUBLE SAUT — l'aile rouge sang qui surgit dans le dos du joueur au
## second saut, donne un coup vers le bas et se défait (visuel seul).
##
## DEUX MORCEAUX, un seul script :
##   • Aile  — accrochée au joueur : elle le suit et se retourne avec lui ;
##   • Envol — ce que le coup laisse SUR PLACE (le souffle d'air chassé vers le
##     bas et quelques plumes arrachées). Ce nœud est détaché (top_level) : posé
##     à l'endroit du coup au moment de `jouer()`, il n'en bouge plus pendant
##     que le joueur s'en va.
##
## USAGE EN JEU : le joueur en garde UNE, créée à son apparition comme enfant de
## son POINT (player.gd, `_aile_preparer`). Chaque double saut appelle
## `jouer()` ; à la fin tout se cache, prêt pour le suivant
## (`auto_detruire = false`).
##
## LE PLANÉ (1er oct. 2026, `mode_plane`) : la même scène sert aussi d'aile de
## PLANÉ. Le joueur en garde une SECONDE instance, en mode plané : `ouvrir()`
## quand il se met à planer (l'aile surgit et accroche l'air), elle reste tenue
## ouverte en houlant et perd une plume de temps en temps (plume_planee.tscn,
## laissée dans le décor), puis `fermer()` quand il arrête (elle se replie en
## se défaisant). L'Envol ne sert pas en plané. Sa pose se règle avec les
## « plane_* » du matériau de l'Aile — le même matériau que le coup, donc les
## mêmes couleurs.
##
## POUR LA JUGER : ouvrir la scène et faire F6, `demo_boucle` la rejoue en
## boucle au milieu de l'écran (monter les durées pour la voir au ralenti ;
## cocher `mode_plane` pour voir le plané). Dans l'éditeur, le curseur
## `progression` parcourt tout l'effet sans rien lancer (en mode plané : l'aile
## tenue ouverte). Les formes se règlent sur les matériaux des nœuds Aile et
## Plumes ; la taille, c'est celle de leurs rectangles (le nœud racine marque
## la racine de l'aile, entre les omoplates).
## ============================================================================

## durée de l'aile elle-même
@export var duree := 0.42
## durée de ce qu'elle laisse sur place (souffle et plumes)
@export var duree_envol := 0.85
## instant affiché, 0 → 1 sur l'effet ENTIER (aperçu dans l'éditeur ; en jeu
## c'est le script)
@export_range(0.0, 1.0, 0.01) var progression := 0.0:
	set(v):
		progression = clampf(v, 0.0, 1.0)
		_appliquer()
## en jeu : rejoue en boucle au lieu de s'arrêter (pour juger l'effet)
@export var demo_boucle := true
@export var demo_pause := 0.6
## se supprime à la fin ; sinon elle se cache et attend le prochain `jouer()`
## (ignoré tant que `demo_boucle` est coché)
@export var auto_detruire := true
## graine : 0 = tirée au hasard à chaque fois
@export var graine := 0.0

@export_group("Plané")
## cette instance est l'aile de PLANÉ (tenue ouverte) et pas le coup du
## double saut
@export var mode_plane := false:
	set(v):
		mode_plane = v
		_appliquer()
## LA POSE (réglée ici et pas sur le matériau : c'est ce script qui la donne
## au shader à chaque image). Angle de la plus grande plume, celle du haut,
## une fois l'aile ouverte (degrés : 0 = vers le haut, 90 = vers l'arrière)
@export_range(-30.0, 90.0) var plane_angle := 40.0:
	set(v):
		plane_angle = v
		_appliquer()
## écartement de l'éventail (1 = celui du coup du double saut)
@export_range(0.5, 1.6) var plane_eventail := 1.0:
	set(v):
		plane_eventail = v
		_appliquer()
## taille de l'aile (1 = celle du coup du double saut)
@export_range(0.5, 1.6) var plane_taille := 1.1:
	set(v):
		plane_taille = v
		_appliquer()
## la houle lente de toute l'aile : amplitude (degrés) et vitesse
@export_range(0.0, 15.0) var plane_houle := 3.0
@export_range(0.0, 15.0) var plane_houle_vitesse := 4.8
## de combien l'air plie les pointes des plumes vers le haut (0 = pas du tout)
@export_range(0.0, 1.0) var plane_portance := 1.0:
	set(v):
		plane_portance = v
		_appliquer()
## durée de la fermeture quand on arrête de planer (s)
@export var duree_fermeture := 0.2
## une plume se détache au hasard entre ces deux délais (s) ; y = 0 : aucune
@export var plumes_intervalle := Vector2(0.45, 0.9)
## F6 en mode plané : l'aile reste ouverte ce temps-là avant de se refermer (s)
@export var demo_tenue := 1.6

const PLUME_PLANEE := preload("res://SCRIPT/SHADER/plume_planee.tscn")

@onready var _aile: ColorRect = $Aile
@onready var _envol: Node2D = $Envol
@onready var _plumes: ColorRect = $Envol/Plumes

var _t := 0.0
var _joue := false
var _graine_effective := 0.0

# --- le plané ---
var _plane_t := 0.0           # secondes depuis l'ouverture
var _plane_ouverte := false
var _fermeture_t := -1.0      # < 0 : pas en train de se refermer
var _prochaine_plume := 0.0
var _demo_plane := false      # F6 en mode plané (lancée seule)
var _demo_attente := 0.0


func _ready() -> void:
	_graine_effective = graine if graine != 0.0 else randf_range(1.0, 100.0)
	if Engine.is_editor_hint():
		_appliquer()
		return
	if mode_plane:
		_envol.visible = false
		visible = false
		# la démo ne tourne que lancée seule (F6), jamais posée dans un jeu
		_demo_plane = demo_boucle and get_parent() == get_tree().root
		if _demo_plane:
			position = get_viewport_rect().size * 0.5
			ouvrir()
		return
	if demo_boucle:
		# lancée seule (F6) : au milieu de l'écran, pas dans le coin en haut à gauche
		if get_parent() == get_tree().root:
			position = get_viewport_rect().size * 0.5
		jouer()
	else:
		visible = false


## durée de l'effet entier
func _total() -> float:
	return maxf(maxf(duree, duree_envol), 0.001)


## (re)lance l'aile depuis le début, là où se trouve ce nœud à cet instant
func jouer() -> void:
	if graine == 0.0:
		_graine_effective = randf_range(1.0, 100.0)
	# ce qui reste sur place se pose ICI, tourné comme le joueur l'est maintenant
	_envol.global_position = global_position
	_envol.scale = Vector2(-1.0 if global_transform.x.x < 0.0 else 1.0, 1.0)
	_t = 0.0
	_joue = true
	visible = true
	progression = 0.0


## LE PLANÉ : l'aile surgit et reste ouverte (relancée depuis le début même si
## elle était en train de se refermer : elle ré-accroche l'air)
func ouvrir() -> void:
	if graine == 0.0:
		_graine_effective = randf_range(1.0, 100.0)
	_plane_t = 0.0
	_fermeture_t = -1.0
	_plane_ouverte = true
	_prochaine_plume = _delai_plume()
	visible = true
	_appliquer()


## LE PLANÉ : elle se replie en se défaisant, puis se cache
func fermer() -> void:
	if not _plane_ouverte:
		return
	_plane_ouverte = false
	_fermeture_t = 0.0


## l'aile de plané est-elle ouverte (et pas en train de se refermer) ?
func ouverte() -> bool:
	return _plane_ouverte


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if mode_plane:
		_plane_avancer(delta)
		return
	if not _joue:
		return
	_t += delta
	var total := _total()
	if _t <= total:
		progression = _t / total
		return
	progression = 1.0
	if demo_boucle:
		if _t >= total + demo_pause:
			jouer()
		return
	_joue = false
	if auto_detruire:
		queue_free()
	else:
		visible = false


func _plane_avancer(delta: float) -> void:
	if not visible:
		# F6 : entre deux démonstrations
		if _demo_plane:
			_demo_attente -= delta
			if _demo_attente <= 0.0:
				ouvrir()
		return
	_plane_t += delta
	if _fermeture_t >= 0.0:
		_fermeture_t += delta
		if _fermeture_t >= duree_fermeture:
			_fermeture_t = -1.0
			visible = false
			_demo_attente = demo_pause
			return
	else:
		if plumes_intervalle.y > 0.0:
			_prochaine_plume -= delta
			if _prochaine_plume <= 0.0:
				_lacher_plume()
				_prochaine_plume = _delai_plume()
		if _demo_plane and _plane_t >= demo_tenue:
			fermer()
	_appliquer()


func _delai_plume() -> float:
	return randf_range(plumes_intervalle.x, maxf(plumes_intervalle.y, plumes_intervalle.x))


## 0 → 1 pendant la fermeture
func _fin_plane() -> float:
	if _fermeture_t < 0.0:
		return 0.0
	return clampf(_fermeture_t / maxf(duree_fermeture, 0.001), 0.0, 1.0)


## une plume se détache d'un point de l'aile au hasard, dans son sens : elle
## est posée dans le décor (elle y reste pendant que le joueur file), derrière
## le joueur comme l'aile, et prend les couleurs de l'aile
func _lacher_plume() -> void:
	var mat := _aile.material as ShaderMaterial
	if mat == null:
		return
	# sur l'éventail (entre la plume du haut et celle du bas), entre le milieu
	# et le bout des plumes
	var angle := plane_angle + randf_range(0.15, 0.95) * _parametre(mat, "ouverture", 95.0) * plane_eventail
	var longueur := _aile.size.y * _parametre(mat, "envergure", 0.43) * plane_taille
	var a := deg_to_rad(angle)
	var ou := Vector2(-sin(a), -cos(a)) * randf_range(0.35, 0.75) * longueur
	var plume := PLUME_PLANEE.instantiate()
	plume.demo_boucle = false
	plume.angle_depart = angle
	var hote: Node = get_tree().current_scene
	if hote == null or _demo_plane:
		hote = get_tree().root
	hote.add_child(plume)
	plume.global_position = to_global(ou)
	plume.scale = Vector2(-1.0 if global_transform.x.x < 0.0 else 1.0, 1.0)
	plume.z_as_relative = false
	plume.z_index = _z_absolu()
	plume.teindre(mat.get_shader_parameter("couleur"), mat.get_shader_parameter("couleur_contour"))


## le z_index réel de l'aile (celui qu'elle a derrière le joueur)
func _z_absolu() -> int:
	var z := 0
	var n: Node = self
	while n is CanvasItem:
		z += (n as CanvasItem).z_index
		if not (n as CanvasItem).z_as_relative:
			break
		n = n.get_parent()
	return z


func _parametre(mat: ShaderMaterial, nom: String, defaut: float) -> float:
	var v = mat.get_shader_parameter(nom)
	return float(v) if v != null else defaut


func _appliquer() -> void:
	if not is_node_ready():
		return
	if mode_plane:
		_regler(_aile, 0.0)
		var mat := _aile.material as ShaderMaterial
		if mat != null:
			mat.set_shader_parameter("plane", 1.0)
			# dans l'éditeur : l'aile tenue ouverte, une fois l'ouverture passée
			mat.set_shader_parameter("plane_temps", 1.0 if Engine.is_editor_hint() else _plane_t)
			mat.set_shader_parameter("plane_fin", _fin_plane())
			mat.set_shader_parameter("plane_angle", plane_angle)
			mat.set_shader_parameter("plane_eventail", plane_eventail)
			mat.set_shader_parameter("plane_taille", plane_taille)
			mat.set_shader_parameter("plane_houle", plane_houle)
			mat.set_shader_parameter("plane_houle_vitesse", plane_houle_vitesse)
			mat.set_shader_parameter("plane_portance", plane_portance)
		return
	var temps := progression * _total()
	var mat_aile := _aile.material as ShaderMaterial
	if mat_aile != null:
		mat_aile.set_shader_parameter("plane", 0.0)
	_regler(_aile, clampf(temps / maxf(duree, 0.001), 0.0, 1.0))
	_regler(_plumes, clampf(temps / maxf(duree_envol, 0.001), 0.0, 1.0))


## donne à un rectangle son instant et son repère (unité = sa hauteur, origine
## = le nœud qui le porte)
func _regler(rect: ColorRect, instant: float) -> void:
	var mat := rect.material as ShaderMaterial
	if mat == null:
		return
	var taille := Vector2(maxf(rect.size.x, 1.0), maxf(rect.size.y, 1.0))
	mat.set_shader_parameter("progress", instant)
	mat.set_shader_parameter("graine", _graine_effective)
	mat.set_shader_parameter("aspect", taille.x / taille.y)
	mat.set_shader_parameter("origine", -rect.position / taille)
