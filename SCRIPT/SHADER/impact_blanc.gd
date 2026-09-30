@tool
extends Node2D
## ============================================================================
## IMPACT BLANC — l'éclat d'un coup d'épée qui porte (visuel seul).
##
## USAGE EN JEU : le joueur l'instancie sur le point d'impact (animator.gd,
## `_eclat_impact`), avec `demo_boucle = false`. Il joue une fois — un sixième
## de seconde — puis se supprime. `scale.x = -1` pour un coup vers la gauche.
##
## Ce script pilote aussi `impact_sang.tscn`, le même éclat en ROUGE SANG et
## plus petit : le coup que le joueur REÇOIT (player.gd, `_eclat_sang`).
##
## POUR LE JUGER : ouvrir la scène et faire F6, `demo_boucle` le rejoue en
## boucle au milieu de l'écran (monter `duree` pour le voir au ralenti). Dans
## l'éditeur, le curseur `progression` montre n'importe quel instant sans rien
## lancer. Les formes se règlent sur le matériau du nœud Eclat.
## ============================================================================

## durée totale : court, c'est ce qui fait « claquer »
@export var duree := 0.16
## instant affiché, 0 → 1 (aperçu dans l'éditeur ; en jeu c'est le script)
@export_range(0.0, 1.0, 0.01) var progression := 0.0:
	set(v):
		progression = clampf(v, 0.0, 1.0)
		_appliquer()
## en jeu : rejoue en boucle au lieu de se supprimer (pour juger l'effet)
@export var demo_boucle := true
@export var demo_pause := 0.5
## se supprime à la fin (ignoré tant que `demo_boucle` est coché)
@export var auto_detruire := true
## graine : 0 = tirée au hasard, deux éclats ne se ressemblent pas
@export var graine := 0.0

@onready var _eclat: ColorRect = $Eclat

var _t := 0.0
var _joue := false
var _graine_effective := 0.0


func _ready() -> void:
	_graine_effective = graine if graine != 0.0 else randf_range(1.0, 100.0)
	if Engine.is_editor_hint():
		_appliquer()
		return
	# lancé seul (F6) : au milieu de l'écran, pas dans le coin en haut à gauche
	if demo_boucle and get_parent() == get_tree().root:
		position = get_viewport_rect().size * 0.5
	jouer()


## (re)lance l'éclat depuis le début
func jouer() -> void:
	_t = 0.0
	_joue = true
	progression = 0.0


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not _joue:
		return
	_t += delta
	if _t <= duree:
		progression = _t / duree
		return
	progression = 1.0
	if demo_boucle:
		if _t >= duree + demo_pause:
			_graine_effective = randf_range(1.0, 100.0)   # un éclat différent à chaque tour
			jouer()
		return
	_joue = false
	if auto_detruire:
		queue_free()


func _appliquer() -> void:
	if not is_node_ready():
		return
	var mat := _eclat.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("progress", progression)
		mat.set_shader_parameter("graine", _graine_effective)
