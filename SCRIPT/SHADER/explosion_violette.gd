@tool
extends Node2D
## ============================================================================
## EXPLOSION VIOLETTE — l'effet du monstre kamikaze (visuel seul : aucun dégât,
## aucune zone de contact).
##
## USAGE EN JEU : on l'instancie au point du boum, elle joue une fois puis se
## supprime toute seule (`auto_detruire`). Le script du kamikaze devra mettre
## `demo_boucle = false`, comme piege_de_flamme.gd le fait pour ses jets.
##
## POUR LA JUGER : ouvrir la scène et faire F6. `demo_boucle` la rejoue en
## boucle avec une pause entre deux. Dans l'éditeur, le curseur `progression`
## montre n'importe quel instant de l'explosion sans rien lancer.
## ============================================================================

## durée totale de l'explosion
@export var duree := 0.55
## instant affiché, 0 → 1. Sert à prévisualiser dans l'éditeur ; en jeu c'est le
## script qui le fait avancer.
@export_range(0.0, 1.0, 0.01) var progression := 0.0:
	set(v):
		progression = clampf(v, 0.0, 1.0)
		_appliquer()
## en jeu : rejoue en boucle au lieu de se supprimer (pour juger l'effet)
@export var demo_boucle := true
## pause entre deux passages en démo
@export var demo_pause := 0.45
## se supprime à la fin (ignoré tant que `demo_boucle` est coché)
@export var auto_detruire := true
## énergie de la lumière au plus fort du flash (0 = pas de lumière)
@export var energie_lumiere := 2.6
## graine : 0 = tirée au hasard, deux explosions ne se ressemblent pas
@export var graine := 0.0

@onready var _feu: ColorRect = $Feu
@onready var _lumiere: PointLight2D = $Lumiere

var _t := 0.0
var _joue := false
var _graine_effective := 0.0


func _ready() -> void:
	_graine_effective = graine if graine != 0.0 else randf_range(1.0, 100.0)
	if Engine.is_editor_hint():
		_appliquer()
		return
	jouer()


## (re)lance l'explosion depuis le début
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
			jouer()
		return
	_joue = false
	if auto_detruire:
		queue_free()


func _appliquer() -> void:
	if not is_node_ready():
		return
	var mat := _feu.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("progress", progression)
		mat.set_shader_parameter("graine", _graine_effective)
	if _lumiere != null:
		# la lumière claque au départ puis retombe vite : c'est elle qui fait
		# « sentir » le souffle sur le décor autour
		var force := (1.0 - progression) * (1.0 - progression)
		_lumiere.visible = progression < 0.999 and energie_lumiere > 0.0
		_lumiere.energy = energie_lumiere * force
		var etendue := 0.5 + 1.3 * progression
		_lumiere.texture_scale = etendue
