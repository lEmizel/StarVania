@tool
extends Node2D
## ============================================================================
## ARC DE FOUDRE — l'éclair qui bondit d'un ennemi à l'autre (visuel seul :
## les dégâts sont dans SCRIPT/CHARACHTER/animator.gd, talisman « Lame de
## foudre », 30 sept. 2026).
##
## USAGE EN JEU : l'instancier dans la scène, puis `tendre(depuis, jusqua)`
## (coordonnées monde) : il se pose sur `depuis`, se tourne vers `jusqua`, joue
## `duree` secondes et se supprime. Il ne dépend de personne : si l'ennemi
## touché meurt ou recule, l'arc reste là où la foudre a sauté.
##
## POUR LE JUGER : ouvrir la scène et faire F6, `demo_boucle` le rejoue en
## boucle au milieu de l'écran sur `demo_longueur` px. Dans l'éditeur, le
## curseur `progression` montre n'importe quel instant. L'allure (ampleur,
## épaisseur, cadence, éclat, couleurs) se règle sur le matériau du nœud Trait.
## ============================================================================

## durée de l'arc (s)
@export var duree := 0.18
## hauteur du rectangle de dessin (px) : l'arc s'écarte de la ligne droite
## d'au plus 34 px, le reste est la place de sa lueur
@export var hauteur := 100.0
## instant affiché, 0 → 1 (aperçu dans l'éditeur ; en jeu c'est le script)
@export_range(0.0, 1.0, 0.01) var progression := 0.3:
	set(v):
		progression = clampf(v, 0.0, 1.0)
		_appliquer()
## lancé seul (F6) : rejoue en boucle au milieu de l'écran
@export var demo_boucle := true
@export var demo_pause := 0.6
@export var demo_longueur := 320.0

@onready var _trait: ColorRect = $Trait

var _t := 0.0
var _joue := false
var _demo := false
var _graine := 0.0


func _ready() -> void:
	if Engine.is_editor_hint():
		_tendre_local(demo_longueur)
		_appliquer()
		return
	_demo = demo_boucle and get_parent() == get_tree().root
	if _demo:
		var milieu := get_viewport_rect().size * 0.5
		tendre(milieu - Vector2(demo_longueur * 0.5, 0.0), milieu + Vector2(demo_longueur * 0.5, 0.0))
	else:
		visible = false


## Tend l'arc de `depuis` à `jusqua` (coordonnées monde) et le joue.
func tendre(depuis: Vector2, jusqua: Vector2) -> void:
	global_position = depuis
	rotation = (jusqua - depuis).angle()
	_tendre_local(maxf(depuis.distance_to(jusqua), 8.0))
	_t = 0.0
	_joue = true
	_graine = randf() * 100.0
	visible = true
	progression = 0.0


func _tendre_local(longueur: float) -> void:
	if _trait == null:
		return
	_trait.position = Vector2(0.0, -hauteur * 0.5)
	_trait.size = Vector2(longueur, hauteur)
	var mat := _trait.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("taille", _trait.size)


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not _joue:
		return
	_t += delta
	if _t < duree:
		progression = _t / duree
		return
	progression = 1.0
	if not _demo:
		queue_free()
	elif _t >= duree + demo_pause:
		var milieu := get_viewport_rect().size * 0.5
		tendre(milieu - Vector2(demo_longueur * 0.5, 0.0), milieu + Vector2(demo_longueur * 0.5, 0.0))


func _appliquer() -> void:
	if _trait == null:
		return
	var mat := _trait.material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("progression", progression)
	mat.set_shader_parameter("temps", _t if not Engine.is_editor_hint() else progression * duree)
	mat.set_shader_parameter("graine", _graine)
