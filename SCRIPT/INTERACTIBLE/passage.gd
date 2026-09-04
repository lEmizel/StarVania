extends Area2D
## PASSAGE : comme une porte, mais la téléportation est AUTOMATIQUE au
## contact du joueur — aucun bouton. Reste dans le groupe "Porte" pour que
## le spawnplayer trouve le point d'arrivée (id + Marker2D) à destination.
##
## Anti-boucle : en arrivant par un passage, le joueur apparaît DANS sa
## zone — dans ce cas le passage ne s'arme qu'une fois le joueur sorti,
## sinon aller-retour infini entre les deux scènes.

@export var id: int = 0
@export_file("*.tscn") var target_scene: String

# fenêtre (frames physique) après le chargement pendant laquelle une entrée
# est considérée comme une ARRIVÉE par ce passage, pas une traversée
const FENETRE_ARRIVEE := 30

var _ready_frame := 0
var _bloque_jusqua_sortie := false
var _deja_utilise := false


func _ready() -> void:
	_ready_frame = Engine.get_physics_frames()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("Player"):
		return
	# le joueur vient d'apparaître ici (arrivée par ce passage) :
	# on ne s'arme qu'à sa sortie de la zone
	if Engine.get_physics_frames() - _ready_frame < FENETRE_ARRIVEE:
		_bloque_jusqua_sortie = true
		return
	if _bloque_jusqua_sortie or _deja_utilise:
		return
	if target_scene.is_empty():
		push_warning("[PASSAGE] Aucune scène cible définie")
		return
	_deja_utilise = true  # une seule téléportation par vie de scène
	Player.last_door_id = id
	# l'élan du joueur traverse avec lui : capturé ici, restitué au spawn
	Player.transition_velocity = body.velocity
	Player.transition_direction = body.last_direction
	Player.has_transition_momentum = true
	Loader.load_scene_with_loading(target_scene)


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("Player"):
		_bloque_jusqua_sortie = false
