extends Node2D
@onready var sprite_2d: Sprite2D = $Sprite2D
@onready var area: Area2D = $Area2D

@export var active := false
var _shader_material: ShaderMaterial

## Chemin de la scène de NIVEAU qui contient ce checkpoint.
## PAS get_tree().current_scene : le Loader échange les niveaux dans un
## conteneur MAIN_SCENE, donc current_scene reste le conteneur (le menu !)
func _level_path() -> String:
	return owner.scene_file_path if owner != null else ""

func _ready() -> void:
	_shader_material = sprite_2d.material
	# après un respawn, le checkpoint mémorisé se rallume tout seul
	if Player.has_checkpoint \
		and Player.last_checkpoint_scene == _level_path() \
		and global_position.distance_to(Player.last_checkpoint_pos) < 10.0:
		active = true
	if not active:
		sprite_2d.material = null
	area.body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("Player"):
		return
	# TALISMAN « SECOND SOUFFLE » : chaque checkpoint touché le recharge, même
	# un checkpoint déjà allumé (1er oct. 2026)
	Player.second_souffle_attente = 0.0
	# TALISMAN « CŒUR NOIR » : chaque checkpoint touché le rend (s'il manque)
	Player.coeur_noir_attente = 0.0
	# Le DERNIER checkpoint touché est le point de retour, MÊME S'IL ÉTAIT DÉJÀ
	# ALLUMÉ. Avant (jusqu'au 4 oct. 2026), un checkpoint allumé ne se
	# réenregistrait pas : on touchait A, puis B, on revenait sur A, et c'était B
	# qui restait.
	# position + scène : survivent au rechargement, contrairement au NodePath
	Player.last_checkpoint_pos = global_position
	Player.last_checkpoint_scene = _level_path()
	Player.has_checkpoint = true
	if not active:
		active = true
		sprite_2d.material = _shader_material
	# la partie est écrite sur le disque à chaque checkpoint touché
	Player.sauvegarder()
