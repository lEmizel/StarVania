extends Area2D
## Boule de sang : file tout droit à vitesse constante, explose au contact
## d'un ennemi (en le blessant) ou d'un mur. L'explosion est une scène
## indépendante instanciée au point d'impact.

const EXPLOSION_SCENE := preload("res://SCRIPT/SPELL/bloodball_explosion.tscn")

@export var speed := 800.0
@export var damage := 95
@export var max_lifetime := 2.0  # au bout de 2 s sans impact : explose d'elle-même

## Direction horizontale (+1 droite, -1 gauche) — posée par le player au spawn
var dir := 1

var _life := 0.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	scale.x = dir  # oriente la boule, la traînée part derrière


func _physics_process(delta: float) -> void:
	position.x += dir * speed * delta
	_life += delta
	if _life >= max_lifetime:
		_explode()


func _on_body_entered(body: Node) -> void:
	# ne jamais exploser sur le lanceur
	if body.is_in_group("Player"):
		return
	# ennemi : dégâts (source = position de la boule → knockback dans le bon sens)
	if body.has_method("apply_damage"):
		body.apply_damage(damage, global_position.x, "bloodball")
	_explode()


func _explode() -> void:
	var explosion := EXPLOSION_SCENE.instantiate()
	get_tree().current_scene.add_child(explosion)
	# ColorRect : global_position = coin haut-gauche → on recentre le rect
	# sur le point d'impact en retirant la moitié de sa taille
	explosion.global_position = global_position - explosion.size * 0.5
	queue_free()
