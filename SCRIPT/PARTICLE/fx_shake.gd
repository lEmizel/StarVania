extends AnimatedSprite2D
## ONDE DE CHOC du boss (attaque au sol). FX autonome : le boss l'instancie, elle
## joue, blesse ce qu'elle touche entre deux images, et se supprime.
##
## CAMPS (23 sept. 2026) : elle porte le camp du boss, posé par lui avant
## `add_child`, comme la boule de feu du squelette bleu. Elle blesse le joueur
## en cœurs (`damage`) et les monstres d'un autre camp en points de vie
## (`degats_monstres`), en se déclarant comme venant de `tireur` pour que la
## victime riposte contre le boss. Les alliés sont traversés.

@onready var area: Area2D = $Area2D
@onready var collision_shape_2d: CollisionShape2D = $Area2D/CollisionShape2D

## cœurs enlevés au joueur
var damage: int = 1
## posés par le lanceur
var faction: int = 0
var degats_monstres: int = 70
var tireur: Node = null


func _ready() -> void:
	collision_shape_2d.disabled = true
	area.collision_mask |= 8          # les monstres aussi, pas seulement le joueur
	animation_finished.connect(queue_free)
	frame_changed.connect(_on_frame_changed)
	area.connect("body_entered", _on_body_entered)
	play("shake_fx")


func _on_frame_changed() -> void:
	if frame >= 5:
		collision_shape_2d.disabled = false
	if frame >= 7:
		collision_shape_2d.disabled = true


func _on_body_entered(body: Node) -> void:
	if not body.has_method("apply_damage"):
		return
	var camp := BaseAI.faction_de(body)
	# le lanceur et ses alliés (monstres comme joueur) ne sont pas touchés
	if body == tireur or camp < 0 or camp == faction:
		return
	if body.is_in_group("Player"):
		body.apply_damage(damage, global_position.x, "onde_de_choc")
	else:
		body.apply_damage(degats_monstres, global_position.x, "onde_de_choc", true, tireur)
