extends Area2D
## Zone de dégâts d'environnement (piques & co) :
## - le joueur perd des cœurs et est renvoyé vers le haut
##   (voir apply_environment_damage dans player.gd)
## - les monstres meurent sur le coup

## Cœurs perdus par le joueur au contact
@export var damage: int = 1


func _ready() -> void:
	# détecte le joueur (couche 1) ET les monstres (couches 2 et 4)
	collision_mask = 0b1011


# Vérification CONTINUE (pas body_entered) : un joueur qui entre invulnérable
# (roulade/dash) doit prendre les dégâts dès que l'invulnérabilité retombe
# s'il est toujours dedans — les gardes d'état du joueur (HIT/ROLL/DASH)
# rendent l'appel répété inoffensif
func _physics_process(_delta: float) -> void:
	for body in get_overlapping_bodies():
		if body.has_method("apply_environment_damage"):
			body.apply_environment_damage(damage)
		elif body.has_method("apply_damage"):
			# squelettes, mobs en tout genre : mort instantanée sur les piques
			body.apply_damage(999999, global_position.x, "piques")
