@tool
extends ColorRect
## ============================================================================
## ÉCLABOUSSURE DE SANG — l'impact de la boule de sang (visuel seul : les
## dégâts sont dans bloodball.gd). Anime le `progress` du shader de 0 à 1.
##
## USAGE EN JEU : bloodball.gd l'instancie au point d'impact avec
## `demo_boucle = false`, le sens de vol de la boule (`direction`) et la
## `puissance` de l'impact ; elle joue une fois puis se supprime.
##
## POUR LA JUGER : ouvrir la scène et faire F6, `demo_boucle` la rejoue en
## boucle au milieu de l'écran (monter `duration` pour la voir au ralenti).
## Dans l'éditeur, le curseur `progression` montre n'importe quel instant sans
## rien lancer. Les formes et les couleurs se règlent sur le matériau ; la
## taille, c'est celle du rectangle.
## ============================================================================

@export var duration := 0.4
## instant affiché, 0 → 1 (aperçu dans l'éditeur ; en jeu c'est le script)
@export_range(0.0, 1.0, 0.01) var progression := 0.0:
	set(v):
		progression = clampf(v, 0.0, 1.0)
		_appliquer()
## en jeu : rejoue en boucle au lieu de se supprimer (pour juger l'effet)
@export var demo_boucle := true
@export var demo_pause := 0.6
## sens de vol de la boule à l'impact : le sang rejaillit vers l'arrière
@export var direction := Vector2.RIGHT:
	set(v):
		direction = v
		_appliquer()
## 1 = un vrai impact ; moins = la boule qui s'éteint seule en bout de course
@export_range(0.0, 1.0, 0.01) var puissance := 1.0:
	set(v):
		puissance = v
		_appliquer()

var _t := 0.0
var _graine := 0.0
## la boucle de démo n'existe QUE lancée seule (F6). Avant le 1er oct. 2026 elle
## suivait `demo_boucle` seul : la boule de feu du squelette bleu, qui posait
## cette scène recolorée sans décocher la case, faisait exploser son impact en
## boucle pour toujours.
var _demo := false


func _ready() -> void:
	_graine = randf_range(1.0, 100.0)
	if Engine.is_editor_hint():
		_appliquer()
		return
	# lancée seule (F6) : au milieu de l'écran, pas dans le coin en haut à gauche
	_demo = demo_boucle and get_parent() == get_tree().root
	if _demo:
		position = get_viewport_rect().size * 0.5 - size * 0.5
	progression = 0.0


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_t += delta
	if _t <= duration:
		progression = _t / duration
		return
	progression = 1.0
	if not _demo:
		queue_free()
	elif _t >= duration + demo_pause:
		_graine = randf_range(1.0, 100.0)       # une éclaboussure différente à chaque tour
		_t = 0.0
		progression = 0.0


func _appliquer() -> void:
	if not is_node_ready():
		return
	var mat := material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("progress", progression)
	mat.set_shader_parameter("direction", direction)
	mat.set_shader_parameter("puissance", puissance)
	mat.set_shader_parameter("graine", _graine)
