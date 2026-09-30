extends AnimatedSprite2D
## Pilote d'animation du XENO : deux attaques, trois hitboxes.
## - corps à corps en deux temps, "attack" puis "attack_2" : UNE hitbox PAR COUP
##   (`CollisionPolygon2D` pour le premier, `coup_2` pour le second), chacune
##   taillée sur l'arc de sa griffure — la part de tarte que le bras balaie,
##   de l'épaule au bout des griffes
## - "attack_langue" (bouche intérieure, 14 frames) : hitbox langue
##   pendant l'extension, frames 6-10 — à AJUSTER sur tes sprites

@onready var enemi: CharacterBody2D = $"../.."
@onready var collision: Area2D = $"../collision_attack"
@onready var hitbox_cac: CollisionPolygon2D = $"../collision_attack/CollisionPolygon2D"
## second coup ; si le nœud manque dans la scène, on retombe sur la hitbox du premier
@onready var hitbox_cac_2 := get_node_or_null("../collision_attack/coup_2") as CollisionPolygon2D
@onready var hitbox_langue: CollisionPolygon2D = $"../collision_attack/langue"

## La griffure des deux coups au corps à corps (30 sept. 2026) : un shader taillé
## sur l'animation, qui REMPLACERA le FX dessiné dans les images 4 et 8 (en
## attendant que Kaoru l'efface du dessin, les deux se superposent). Une par
## xeno, créée avec lui sous POINT : elle se retourne avec lui, devant le sprite.
const GRIFFURE := preload("res://SCRIPT/SHADER/griffure_xeno.tscn")
var _griffure: Node2D = null


func _ready() -> void:
	SignalUtils.connect_signal(self, "frame_changed", self, "_on_frame_changed")
	SignalUtils.connect_signal(self, "animation_changed", self, "_on_animation_changed")
	SignalUtils.connect_signal(collision, "body_entered", self, "_on_body_entered")
	_disable_all_hitboxes()
	_griffure = GRIFFURE.instantiate() as Node2D
	_griffure.demo_boucle = false
	_griffure.auto_detruire = false
	_griffure.z_index = 1
	# POINT est encore en train d'installer ses enfants : on s'y ajoute après
	get_parent().add_child.call_deferred(_griffure)


func _on_body_entered(body: Node) -> void:
	# CAMPS : c'est le monstre qui décide qui est un ennemi et à quelle échelle
	# il frappe (cœurs pour le joueur, points de vie pour un monstre)
	enemi.infliger(body, enemi.global_position.x, "attaque:" + enemi.name)


func _disable_all_hitboxes() -> void:
	hitbox_cac.set_deferred("disabled", true)
	if hitbox_cac_2 != null:
		hitbox_cac_2.set_deferred("disabled", true)
	hitbox_langue.set_deferred("disabled", true)


func _on_frame_changed() -> void:
	match animation:
		"attack":
			# partie 1 : frappe à partir de la frame 3 (jusqu'à la fin —
			# l'enchaînement vers attack_2 nettoie au changement d'anim)
			match frame:
				0:
					_disable_all_hitboxes()
				3:
					hitbox_cac.set_deferred("disabled", false)
					_griffure.jouer(1)      # premier coup : de haut en bas, devant lui
		"attack_2":
			# partie 2 : frappe à partir de la frame 2
			match frame:
				0:
					_disable_all_hitboxes()
				2:
					var zone := hitbox_cac_2 if hitbox_cac_2 != null else hitbox_cac
					zone.set_deferred("disabled", false)
					_griffure.jouer(2)      # second coup : par-dessus, plus loin devant
		"attack_langue":
			match frame:
				0:
					_disable_all_hitboxes()
				6:
					hitbox_langue.set_deferred("disabled", false)
				10:
					_disable_all_hitboxes()
		"dead":
			match frame:
				0:
					_disable_all_hitboxes()
					_griffure.arreter()     # mort en plein geste : la griffure part avec lui


func _on_animation_changed() -> void:
	_disable_all_hitboxes()
