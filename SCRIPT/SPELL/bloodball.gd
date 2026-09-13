extends Area2D
## Boule de sang : file tout droit à vitesse constante, explose au contact
## d'un ennemi (en le blessant) ou d'un mur. L'explosion est une scène
## indépendante instanciée au point d'impact.

const EXPLOSION_SCENE := preload("res://SCRIPT/SPELL/bloodball_explosion.tscn")

@export var speed := 800.0
@export var damage := 60  # sept. 2026 : un peu sous le coup léger au corps à corps (animator.gd : damage = 70)
## Portée maximale (px) avant auto-explosion : courte = outil de proximité,
## pas un sniper (avant sept. 2026 : ~1600 px via une durée de vie de 2 s)
@export var portee := 400.0

## Direction horizontale (+1 droite, -1 gauche) — posée par le player au spawn
var dir := 1

var _parcouru := 0.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	scale.x = dir  # oriente la boule, la traînée part derrière


func _physics_process(delta: float) -> void:
	var pas := speed * delta
	position.x += dir * pas
	_parcouru += pas
	if _parcouru >= portee:
		_explode()


func _on_body_entered(body: Node) -> void:
	# ne jamais exploser sur le lanceur
	if body.is_in_group("Player"):
		return
	# ennemi : dégâts (source = position de la boule → knockback dans le bon sens)
	if body.has_method("apply_damage"):
		# knockback = false : la bloodball pique sans déplacer (l'ennemi
		# se retourne et aggro quand même via la réaction de BASE_IA)
		body.apply_damage(damage, global_position.x, "bloodball", false)
	_explode()


func _explode() -> void:
	var explosion := EXPLOSION_SCENE.instantiate()
	get_tree().current_scene.add_child(explosion)
	# ColorRect : global_position = coin haut-gauche → on recentre le rect
	# sur le point d'impact en retirant la moitié de sa taille
	explosion.global_position = global_position - explosion.size * 0.5
	queue_free()
