@tool
extends Node2D
## ============================================================================
## TRACE DE GRIFFE — sillons et étincelles que la griffe du joueur laisse sur le
## mur pendant le wall run (visuel seul).
##
## USAGE EN JEU : le joueur en garde deux, créées une fois pour toutes à son
## apparition (player.gd, `_griffe_tracer`) — jamais de création en plein jeu.
## Un TRAIT = un contact continu de la griffe :
##   • `poser(point, sens)` quand la griffe touche le mur ;
##   • `suivre(point)` à chaque pas de physique tant qu'elle racle ;
##   • `lacher()` quand elle décolle : ce qui est sur le mur finit de s'éteindre
##     sur place, puis le nœud se cache et redevient `libre()`.
## `point` est le bout des doigts, en coordonnées du monde.
##
## POUR LA JUGER : ouvrir la scène et faire F6, `demo_boucle` fait courir une
## griffe d'un bord à l'autre de l'écran, en boucle. Dans l'éditeur, le curseur
## `progression` montre un instant : les deux premiers tiers la griffe racle,
## le dernier tiers elle a lâché. Les formes se règlent sur le matériau du nœud
## Trace.
## ============================================================================

## aperçu dans l'éditeur, 0 → 1 (sans effet en jeu)
@export_range(0.0, 1.0, 0.01) var progression := 0.5:
	set(v):
		progression = clampf(v, 0.0, 1.0)
		if Engine.is_editor_hint():
			_apercu()
## lancée seule (F6) : une griffe traverse l'écran en boucle
@export var demo_boucle := true
## vitesse de la course (px/s) — posée par le joueur, sert aussi à la démo
@export var vitesse := 700.0
## durée d'une course de démonstration (s)
@export var demo_course := 1.2

enum Etat { LIBRE, RACLE, LACHE }

@onready var _trace: ColorRect = $Trace

var _etat := Etat.LIBRE
var _parcouru := 0.0
var _lache := 0.0
var _contact := 0.0
var _graine := 0.0
var _demo := false
var _demo_t := 0.0
var _demo_depart := Vector2.ZERO


func _ready() -> void:
	if Engine.is_editor_hint():
		_apercu()
		return
	if demo_boucle and get_parent() == get_tree().root:
		_demo = true
		_demo_depart = get_viewport_rect().size * 0.5 - Vector2(vitesse * demo_course * 0.5, 0.0)
		poser(_demo_depart, 1)
		return
	visible = false


## La griffe vient de toucher le mur en `point` (monde) ; `sens` = 1 vers la
## droite, -1 vers la gauche.
func poser(point: Vector2, sens: int) -> void:
	global_position = point
	scale = Vector2(-1.0 if sens < 0 else 1.0, 1.0)
	_parcouru = 0.0
	_lache = 0.0
	_contact = 1.0
	_graine = randf_range(1.0, 100.0)
	_etat = Etat.RACLE
	visible = true
	_appliquer()


## La griffe racle toujours : elle est maintenant en `point` (monde).
func suivre(point: Vector2) -> void:
	if _etat != Etat.RACLE:
		return
	_parcouru += absf(point.x - global_position.x)
	global_position = point
	_appliquer()


## La griffe a quitté le mur : la trace reste où elle est et s'éteint.
func lacher() -> void:
	if _etat == Etat.RACLE:
		_etat = Etat.LACHE
		_contact = 0.0          # plus de griffe : l'éclat du contact part avec elle
		_appliquer()


func libre() -> bool:
	return _etat == Etat.LIBRE


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _demo:
		_demo_avancer(delta)
	if _etat != Etat.LACHE:
		return
	_lache += delta
	if _lache >= _duree_d_extinction():
		_etat = Etat.LIBRE
		visible = false
		return
	_appliquer()


## temps qu'il faut à tout ce qui est sur le mur pour avoir disparu
func _duree_d_extinction() -> float:
	var mat := _trace.material as ShaderMaterial
	if mat == null:
		return 0.5
	var v: Variant = mat.get_shader_parameter("vie")
	var ve: Variant = mat.get_shader_parameter("vie_etincelles")
	return maxf(float(v) if v != null else 0.42, float(ve) if ve != null else 0.36) + 0.05


func _demo_avancer(delta: float) -> void:
	_demo_t += delta
	if _etat == Etat.RACLE:
		suivre(_demo_depart + Vector2(vitesse * _demo_t, 0.0))
		if _demo_t >= demo_course:
			lacher()
	elif _etat == Etat.LIBRE and _demo_t >= demo_course + _duree_d_extinction() + 0.4:
		_demo_t = 0.0
		poser(_demo_depart, 1)


## aperçu figé dans l'éditeur : deux tiers de course, puis la griffe lâche
func _apercu() -> void:
	if not is_node_ready():
		return
	if progression <= 0.667:
		_parcouru = vitesse * demo_course * progression / 0.667
		_lache = 0.0
		_contact = 1.0
	else:
		_parcouru = vitesse * demo_course
		_lache = (progression - 0.667) / 0.333 * 0.5
		_contact = 0.0
	_graine = 7.0
	_appliquer()


func _appliquer() -> void:
	if not is_node_ready():
		return
	var mat := _trace.material as ShaderMaterial
	if mat == null:
		return
	var taille := Vector2(maxf(_trace.size.x, 1.0), maxf(_trace.size.y, 1.0))
	# le repère du shader : des pixels, comptés depuis ce nœud (le bout des doigts)
	mat.set_shader_parameter("taille", taille)
	mat.set_shader_parameter("origine", -_trace.position / taille)
	mat.set_shader_parameter("parcouru", _parcouru)
	mat.set_shader_parameter("vitesse", vitesse)
	mat.set_shader_parameter("temps_lache", _lache)
	mat.set_shader_parameter("contact", _contact)
	mat.set_shader_parameter("graine", _graine)
