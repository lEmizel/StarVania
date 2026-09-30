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
## POUR LA JUGER : ouvrir la scène et faire F6, `demo_boucle` la rejoue en
## boucle au milieu de l'écran (monter les durées pour la voir au ralenti).
## Dans l'éditeur, le curseur `progression` parcourt tout l'effet sans rien
## lancer. Les formes se règlent sur les matériaux des nœuds Aile et Plumes ;
## la taille, c'est celle de leurs rectangles (le nœud racine marque la racine
## de l'aile, entre les omoplates).
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

@onready var _aile: ColorRect = $Aile
@onready var _envol: Node2D = $Envol
@onready var _plumes: ColorRect = $Envol/Plumes

var _t := 0.0
var _joue := false
var _graine_effective := 0.0


func _ready() -> void:
	_graine_effective = graine if graine != 0.0 else randf_range(1.0, 100.0)
	if Engine.is_editor_hint():
		_appliquer()
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


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not _joue:
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


func _appliquer() -> void:
	if not is_node_ready():
		return
	var temps := progression * _total()
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
