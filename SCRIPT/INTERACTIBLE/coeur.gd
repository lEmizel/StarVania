extends Area2D
## Cœur ramassable (goutte de sang) : marcher dessus ajoute 1 cœur MAX
## et soigne toute la vie. Lévite doucement sur place.

## Amplitude (px) de la lévitation verticale
@export var FLOAT_AMPLITUDE: float = 12.0
## Vitesse de la lévitation (radians/s de l'onde)
@export var FLOAT_SPEED: float = 2.0
## Balancement angulaire (degrés de part et d'autre)
@export var SWAY_DEGREES: float = 4.0

var _base_pos: Vector2
var _base_rot: float
var _phase := 0.0
var _t := 0.0
var _persist_key := ""


func _ready() -> void:
	# persistance : déjà ramassé dans cette session → il n'existe plus
	_persist_key = _make_persist_key()
	if Player.coeurs_ramasses.has(_persist_key):
		set_process(false)
		get_parent().queue_free()
		return
	collision_mask = 1  # ne détecte que le joueur
	body_entered.connect(_on_body_entered)
	var p := get_parent() as Node2D
	_base_pos = p.position
	_base_rot = p.rotation
	# déphasage par position : deux cœurs voisins ne lévitent pas en synchro
	_phase = global_position.x * 0.017


## Identité stable du pickup : scène du niveau + position arrondie —
## aucun ID à poser à la main, mais déplacer la goutte dans l'éditeur
## change sa clé (sans conséquence : le registre vit une session)
func _make_persist_key() -> String:
	var racine := get_parent()
	var niveau: String = racine.owner.scene_file_path \
		if racine != null and racine.owner != null else ""
	return "%s|%d,%d" % [niveau, roundi(global_position.x), roundi(global_position.y)]


func _process(delta: float) -> void:
	_t += delta
	var p := get_parent() as Node2D
	p.position.y = _base_pos.y + sin(_t * FLOAT_SPEED + _phase) * FLOAT_AMPLITUDE
	p.rotation = _base_rot + sin(_t * FLOAT_SPEED * 0.6 + _phase) \
		* deg_to_rad(SWAY_DEGREES)


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("Player"):
		return
	Player.coeurs_ramasses[_persist_key] = true  # ne renaîtra pas au respawn
	Player.add_max_hp(1)  # la rangée de cœurs s'agrandit (signal "hp")
	# soin complet : ramasser un cœur restaure TOUTE la vie
	Player.changement_de_vie(Player.MAX_HP - Player.hp)
	# cérémonie visuelle : gros plan + envol en comète vers la rangée du HUD
	var ui := get_tree().get_nodes_in_group("UI_Health")
	if not ui.is_empty() and ui[0].has_method("heart_pickup_fx"):
		ui[0].heart_pickup_fx()
	get_parent().queue_free()    # la racine de la scène coeur disparaît
