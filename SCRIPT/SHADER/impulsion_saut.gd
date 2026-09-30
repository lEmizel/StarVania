@tool
extends Node2D
## ============================================================================
## IMPULSION DE SAUT — l'air chassé sous les pieds au départ d'un saut simple
## (visuel seul). La sœur du souffle de dash.
##
## USAGE EN JEU : le joueur l'instancie à ses pieds (player.gd,
## `_poser_impulsion_saut`), avec `demo_boucle = false`, le sens et la vitesse
## de son saut. L'effet RESTE où il a été posé — le joueur s'en éloigne — joue
## une fois puis se supprime.
##
## Le sillage ne dépasse jamais le joueur : sa tête avance à `vitesse` dans le
## sens `direction` et s'arrête à `distance`.
##
## POUR LE JUGER : ouvrir la scène et faire F6, `demo_boucle` le rejoue en
## boucle au milieu de l'écran (monter `duree` pour le voir au ralenti). Dans
## l'éditeur, le curseur `progression` montre n'importe quel instant sans rien
## lancer. Les formes se règlent sur le matériau du nœud Impulsion ; la taille,
## c'est celle de son rectangle (le nœud racine marque les pieds).
## ============================================================================

## durée totale
@export var duree := 0.32
## instant affiché, 0 → 1 (aperçu dans l'éditeur ; en jeu c'est le script)
@export_range(0.0, 1.0, 0.01) var progression := 0.0:
	set(v):
		progression = clampf(v, 0.0, 1.0)
		_appliquer()
## en jeu : rejoue en boucle au lieu de se supprimer (pour juger l'effet)
@export var demo_boucle := true
@export var demo_pause := 0.6
## se supprime à la fin (ignoré tant que `demo_boucle` est coché)
@export var auto_detruire := true
## graine : 0 = tirée au hasard, deux impulsions ne se ressemblent pas
@export var graine := 0.0
## sens du saut (posé par le joueur ; vers le haut par défaut)
@export var direction := Vector2.UP:
	set(v):
		direction = v
		_appliquer()
## vitesse du saut (px/s) et hauteur que le sillage ne dépasse pas (px)
@export var vitesse := 1062.0
@export var distance := 110.0

@onready var _impulsion: ColorRect = $Impulsion

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


## (re)lance l'impulsion depuis le début
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
			_graine_effective = randf_range(1.0, 100.0)   # une impulsion différente à chaque tour
			jouer()
		return
	_joue = false
	if auto_detruire:
		queue_free()


func _appliquer() -> void:
	if not is_node_ready():
		return
	var mat := _impulsion.material as ShaderMaterial
	if mat == null:
		return
	var taille := Vector2(maxf(_impulsion.size.x, 1.0), maxf(_impulsion.size.y, 1.0))
	mat.set_shader_parameter("progress", progression)
	mat.set_shader_parameter("graine", _graine_effective)
	# le repère du shader : unité = hauteur du rectangle, origine = ce nœud
	mat.set_shader_parameter("aspect", taille.x / taille.y)
	mat.set_shader_parameter("origine", -_impulsion.position / taille)
	mat.set_shader_parameter("direction", direction)
	mat.set_shader_parameter("parcouru", minf(vitesse * progression * duree, distance) / taille.y)
