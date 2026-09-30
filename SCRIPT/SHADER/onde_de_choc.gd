@tool
extends Node2D
## ============================================================================
## ONDE DE CHOC AU SOL — le visuel du coup de pied du boss (visuel seul : les
## dégâts sont dans SCRIPT/PARTICLE/fx_shake.gd, qui héberge cette scène).
##
## USAGE EN JEU : fx_shake.gd lui donne son déroulé (`duree`, `debut_coup`,
## `fin_coup`), la vraie largeur de sa zone de dégâts et la hauteur du sol,
## puis appelle `jouer()`. Le visuel se cale là-dessus : l'anneau atteint les
## bords de la zone quand elle devient dangereuse, la couronne d'éclats est
## dressée exactement pendant qu'elle blesse.
##
## POUR LA JUGER : ouvrir la scène et faire F6, `demo_boucle` la rejoue en
## boucle au milieu de l'écran (monter `duree` pour la voir au ralenti). Dans
## l'éditeur, le curseur `progression` montre n'importe quel instant sans rien
## lancer. Les formes se règlent sur le matériau du nœud Onde.
## ============================================================================

## durée totale
@export var duree := 0.643
## instant affiché, 0 → 1 (aperçu dans l'éditeur ; en jeu c'est le script)
@export_range(0.0, 1.0, 0.01) var progression := 0.0:
	set(v):
		progression = clampf(v, 0.0, 1.0)
		_appliquer()
## en jeu : rejoue en boucle au lieu de se supprimer (pour juger l'effet)
@export var demo_boucle := true
@export var demo_pause := 0.7
## se supprime à la fin (ignoré tant que `demo_boucle` est coché)
@export var auto_detruire := true
## graine : 0 = tirée au hasard, deux ondes ne se ressemblent pas
@export var graine := 0.0

@export_group("Calage sur la zone de dégâts")
## instants (secondes) où la zone devient, puis cesse d'être dangereuse
@export var debut_coup := 0.357:
	set(v):
		debut_coup = v
		_appliquer()
@export var fin_coup := 0.5:
	set(v):
		fin_coup = v
		_appliquer()
## demi-largeur de la zone (px) et décalage de son milieu par rapport à ce nœud
@export var demi_largeur := 555.5:
	set(v):
		demi_largeur = v
		_appliquer()
@export var centre_x := 2.5:
	set(v):
		centre_x = v
		_appliquer()
## hauteur du sol SOUS ce nœud (px) : l'onde est dessinée posée dessus
@export var sol := 22.0:
	set(v):
		sol = v
		_appliquer()

@onready var _onde: ColorRect = $Onde

var _t := 0.0
var _joue := false
var _graine_effective := 0.0


func _ready() -> void:
	_graine_effective = graine if graine != 0.0 else randf_range(1.0, 100.0)
	if Engine.is_editor_hint():
		_appliquer()
		return
	# lancée seule (F6) : au milieu de l'écran, pas dans le coin en haut à gauche
	if demo_boucle and get_parent() == get_tree().root:
		position = get_viewport_rect().size * 0.5
	jouer()


## (re)lance l'onde depuis le début
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
			_graine_effective = randf_range(1.0, 100.0)   # une onde différente à chaque tour
			jouer()
		return
	_joue = false
	if auto_detruire:
		queue_free()


func _appliquer() -> void:
	if not is_node_ready():
		return
	var mat := _onde.material as ShaderMaterial
	if mat == null:
		return
	var taille := Vector2(maxf(_onde.size.x, 1.0), maxf(_onde.size.y, 1.0))
	var d := maxf(duree, 0.001)
	mat.set_shader_parameter("progress", progression)
	mat.set_shader_parameter("graine", _graine_effective)
	# le repère du shader : des pixels, comptés depuis ce nœud
	mat.set_shader_parameter("taille", taille)
	mat.set_shader_parameter("origine", -_onde.position / taille)
	mat.set_shader_parameter("sol", sol)
	mat.set_shader_parameter("centre_x", centre_x)
	mat.set_shader_parameter("demi_largeur", demi_largeur)
	mat.set_shader_parameter("debut_coup", debut_coup / d)
	mat.set_shader_parameter("fin_coup", fin_coup / d)
