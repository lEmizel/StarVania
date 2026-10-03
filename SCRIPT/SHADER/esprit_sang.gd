extends Node2D
## ============================================================================
## ESPRIT DE SANG (1er oct. 2026) — LES ÂMES PERDUES À LA MORT : elles sont
## laissées sur place comme dans les Souls, sous la forme d'un petit esprit
## rouge qu'on doit ramasser pour les récupérer.
## Posé par le joueur quand il arrive dans le tableau où il est mort (player.gd,
## `_ames_poser`), à l'endroit gardé par l'autoload (`Player.ames_position`) :
## au-dessus du dernier sol où il a posé le pied — pas au fond d'un trou, pas
## dans des piques. Le héros le TOUCHE : l'esprit file vers lui, s'y fond, et le
## sang qu'il gardait revient au compteur (`Player.reprendre_ames` — sans le
## bonus de la Soif de sang : ce n'est pas une récolte). Si le héros meurt de
## nouveau avant, cet esprit est perdu pour de bon : il s'éteint
## (`Player.ames_id` a changé) et un nouveau attendra là où il est tombé.
## Avec le Reliquaire, on garde la moitié sur soi : l'esprit ne porte que
## l'autre.
##
## POUR LE JUGER : ouvrir la scène et faire F6 (il flotte au milieu de l'écran ;
## toutes les 4 s il est « repris » puis renaît). Ses couleurs, sa lueur : sur
## le matériau du nœud Dessin.
## ============================================================================

## lancé seul (F6) : il flotte, il est repris, il renaît, en boucle
@export var demo_boucle := true
## il flotte : de combien il monte et descend (px), à quelle vitesse (rad/s)
@export var flottement := 5.0
@export var vitesse_flottement := 2.2
## le héros le reprend en passant à moins de… (px, du milieu de son corps)
@export var portee_reprise := 46.0
## repris, il file vers le héros en… (s) ; il apparaît en… (s) ; perdu, il
## s'éteint en… (s)
@export var duree_absorption := 0.32
@export var duree_apparition := 0.6
@export var duree_extinction := 0.5

const GROUPE := "esprit_sang"

@onready var _dessin: ColorRect = $Dessin

var _t := 0.0
var _origine := Vector2.ZERO
var _id := -1                  # l'esprit de quelle mort (Player.ames_id)
var _repris := false
var _absorbe_t := 0.0
var _depart := Vector2.ZERO
var _vers := Vector2.ZERO
var _eteint_t := -1.0          # >= 0 : perdu, il s'éteint
var _demo := false


func _ready() -> void:
	add_to_group(GROUPE)
	_demo = demo_boucle and get_parent() == get_tree().root
	if _demo:
		position = get_viewport_rect().size * 0.5
	_origine = position
	_id = Player.ames_id
	_appliquer(0.0)


func _physics_process(delta: float) -> void:
	_t += delta
	if _eteint_t >= 0.0:
		_eteint_t += delta
		if _eteint_t >= duree_extinction:
			queue_free()
			return
	elif not _demo and not _repris and Player.ames_id != _id:
		# le héros est mort de nouveau avant de le reprendre : perdu pour de bon
		_eteint_t = 0.0
		print("[ÂMES] f=", Engine.get_physics_frames(), " un esprit de sang s'éteint (perdu pour de bon)")
	if _repris:
		_absorber(delta)
		return
	position = _origine + Vector2(0.0, sin(_t * vitesse_flottement) * flottement)
	if _eteint_t >= 0.0:
		_appliquer(0.0)
		return
	if _demo:
		if _t >= 3.0:
			_reprendre(null)
	else:
		var heros := get_tree().get_first_node_in_group("Player")
		if heros != null and Player.hp > 0 and heros.has_method("centre_corps") \
				and heros.centre_corps().distance_to(global_position) <= portee_reprise:
			_reprendre(heros)
	_appliquer(0.0)


## touché : le sang revient, l'esprit file vers le héros et s'y fond
func _reprendre(heros: Node2D) -> void:
	_repris = true
	_absorbe_t = 0.0
	_depart = global_position
	set_meta("heros", heros)
	if _demo:
		return
	var n := Player.reprendre_ames()
	print("[ÂMES] f=", Engine.get_physics_frames(), " ", n, " âmes reprises (il y en a ", Player.blood, ")")


func _absorber(delta: float) -> void:
	_absorbe_t += delta
	var u := clampf(_absorbe_t / maxf(duree_absorption, 0.001), 0.0, 1.0)
	var heros = get_meta("heros", null)
	var but := _depart + Vector2(140.0, -10.0)
	if heros != null and is_instance_valid(heros) and heros.has_method("centre_corps"):
		but = heros.centre_corps()
	var avant := global_position
	global_position = _depart.lerp(but, u * u)
	if global_position.distance_squared_to(avant) > 0.01:
		_vers = (global_position - avant).normalized()
	_appliquer(u)
	if u >= 1.0:
		if _demo:
			# F6 : il renaît à sa place
			_repris = false
			_t = 0.0
			position = _origine
			_vers = Vector2.ZERO
		else:
			queue_free()


func _appliquer(absorbe: float) -> void:
	var mat := _dessin.material as ShaderMaterial
	if mat == null:
		return
	var apparition := clampf(_t / maxf(duree_apparition, 0.001), 0.0, 1.0)
	if _eteint_t >= 0.0:
		apparition *= 1.0 - clampf(_eteint_t / maxf(duree_extinction, 0.001), 0.0, 1.0)
	mat.set_shader_parameter("taille", _dessin.size)
	mat.set_shader_parameter("ancre", -_dessin.position)
	mat.set_shader_parameter("temps", _t)
	mat.set_shader_parameter("absorbe", absorbe)
	mat.set_shader_parameter("vol", _vers)
	mat.set_shader_parameter("apparition", smoothstep(0.0, 1.0, apparition))
