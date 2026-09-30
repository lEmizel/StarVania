@tool
extends Node2D
## ============================================================================
## PLUME PLANÉE (1er oct. 2026) — une plume que l'aile de PLANÉ perd en route.
## L'aile (aile_double_saut.gd en mode plané) en lâche une de temps en temps :
## posée dans le décor à l'endroit où elle était sur l'aile, elle y reste
## pendant que le joueur file, descend en se balançant, disparaît, puis se
## supprime.
##
## POUR LA JUGER : ouvrir la scène et faire F6 (elle tourne en boucle au milieu
## de l'écran, seulement lancée seule). Dans l'éditeur, le curseur
## `progression` la parcourt. Son allure se règle sur le matériau du nœud
## Plume ; ses couleurs, en jeu, sont celles de l'aile qui la perd.
## ============================================================================

## durée de sa chute, de l'aile jusqu'à rien (s)
@export var duree := 1.1
## instant affiché, 0 → 1 (aperçu dans l'éditeur ; en jeu c'est le script)
@export_range(0.0, 1.0, 0.01) var progression := 0.0:
	set(v):
		progression = clampf(v, 0.0, 1.0)
		_appliquer()
## lancée seule (F6) : rejoue en boucle au lieu de se supprimer
@export var demo_boucle := true
@export var demo_pause := 0.4
## graine : 0 = tirée au hasard
@export var graine := 0.0
## l'angle qu'elle avait sur l'aile (degrés : 0 = vers le haut, 90 = vers
## l'arrière) — fixé par l'aile qui la lâche
@export var angle_depart := 60.0

@onready var _plume: ColorRect = $Plume

var _t := 0.0
var _demo := false
var _graine_effective := 0.0


func _ready() -> void:
	_graine_effective = graine if graine != 0.0 else randf_range(1.0, 100.0)
	if Engine.is_editor_hint():
		_appliquer()
		return
	# la boucle de démo n'existe que lancée seule, jamais posée dans un jeu
	_demo = demo_boucle and get_parent() == get_tree().root
	if _demo:
		position = get_viewport_rect().size * 0.5
	_appliquer()


## les couleurs de l'aile qui la perd
func teindre(couleur, contour) -> void:
	var mat := _plume.material as ShaderMaterial
	if mat == null:
		return
	if couleur is Color:
		mat.set_shader_parameter("couleur", couleur)
	if contour is Color:
		mat.set_shader_parameter("couleur_contour", contour)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_t += delta
	if _t < duree:
		progression = _t / maxf(duree, 0.001)
		return
	if _demo:
		progression = 1.0
		if _t >= duree + demo_pause:
			_t = 0.0
			if graine == 0.0:
				_graine_effective = randf_range(1.0, 100.0)
		return
	queue_free()


func _appliquer() -> void:
	if not is_node_ready():
		return
	var mat := _plume.material as ShaderMaterial
	if mat == null:
		return
	var taille := Vector2(maxf(_plume.size.x, 1.0), maxf(_plume.size.y, 1.0))
	mat.set_shader_parameter("progress", progression)
	mat.set_shader_parameter("graine", _graine_effective)
	mat.set_shader_parameter("aspect", taille.x / taille.y)
	mat.set_shader_parameter("origine", -_plume.position / taille)
	mat.set_shader_parameter("angle_depart", deg_to_rad(angle_depart))
