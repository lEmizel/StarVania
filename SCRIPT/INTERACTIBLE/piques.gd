extends Area2D
## Zone de dégâts d'environnement (piques, scie & co) :
## - le joueur perd des cœurs et est REPOUSSÉ À L'OPPOSÉ du danger
##   (voir apply_environment_damage dans player.gd)
## - les monstres meurent sur le coup

## Cœurs perdus par le joueur au contact
@export var damage: int = 1

enum Repoussee { ORIENTATION, RADIALE }
## Vers où le joueur est repoussé :
## - ORIENTATION : dans le sens où POINTENT les piques = l'axe "haut" du nœud.
##   Rien à régler : une pique retournée au plafond (scale.y = -1) repousse vers
##   le bas, une pique tournée de 90° sur un mur repousse sur le côté.
## - RADIALE : du centre de la zone vers le joueur — pour la scie circulaire,
##   qu'on peut toucher par n'importe quel côté et qui peut venir à nous.
@export var repoussee: Repoussee = Repoussee.ORIENTATION


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
			body.apply_environment_damage(damage, _direction_repoussee(body))
		elif body.has_method("apply_damage"):
			# squelettes, mobs en tout genre : mort instantanée sur les piques
			body.apply_damage(999999, global_position.x, "piques")


## direction unitaire dans laquelle ce danger repousse `body`
func _direction_repoussee(body: Node2D) -> Vector2:
	if repoussee == Repoussee.RADIALE:
		var centre_joueur: Vector2 = body.global_position
		if body.has_method("centre_corps"):
			centre_joueur = body.centre_corps()
		var v := centre_joueur - _centre_zone()
		if v.length_squared() > 1.0:
			return v.normalized()
	# sens où pointent les piques : l'axe "haut" local, rotations et
	# retournements (scale négatif) compris
	return (-global_transform.y).normalized()


## centre de la zone = moyenne de ses formes de collision (une seule en général)
func _centre_zone() -> Vector2:
	var somme := Vector2.ZERO
	var n := 0
	for c in get_children():
		if c is CollisionShape2D:
			somme += c.global_position
			n += 1
	return somme / n if n > 0 else global_position
