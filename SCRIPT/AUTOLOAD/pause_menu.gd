extends Node
## Écoute l'action "start" (bouton START manette / Échap) : en jeu, ouvre
## le menu pause et fige le jeu. Re-appuyer referme. Inactif dans le menu
## principal (aucun joueur présent).

const PAUSE_SCENE := preload("res://SCRIPT/MENU/pause.tscn")
var _menu: Control = null
var _layer: CanvasLayer


func _ready() -> void:
	# l'écoute doit survivre à la pause du SceneTree
	process_mode = Node.PROCESS_MODE_ALWAYS
	# calque écran : sans CanvasLayer, le menu vivrait dans le canvas du
	# MONDE et la caméra du jeu le déporterait hors champ
	_layer = CanvasLayer.new()
	_layer.layer = 100
	add_child(_layer)


func _process(_delta: float) -> void:
	if not Input.is_action_just_pressed("start"):
		return
	# menu déjà ouvert → START le referme
	if _menu != null and is_instance_valid(_menu):
		_menu.fermer()
		_menu = null
		return
	# uniquement en jeu : dans le menu principal il n'y a pas de joueur
	if get_tree().get_first_node_in_group("Player") == null:
		return
	get_tree().paused = true
	_menu = PAUSE_SCENE.instantiate()
	_layer.add_child(_menu)
