@tool
extends Node2D
## Barrière de caméra posable dans le niveau (groupe "CAMERA_LIMIT") :
## une ligne d'une certaine longueur qui empêche UN bord de l'écran de la
## franchir — mais seulement quand la caméra est à sa hauteur. Plusieurs
## barrières peuvent cohabiter, chacune ne contraint que sa zone.
##
## Visible uniquement dans l'éditeur (ligne + flèches vers la zone permise).

enum Bord { DROIT, GAUCHE, HAUT, BAS }

## Quel bord de l'écran est bloqué par cette ligne ?
## DROIT = le bord droit de l'écran s'arrête ici (mur à droite d'une salle)
@export var bord_bloque: Bord = Bord.DROIT:
	set(v):
		bord_bloque = v
		queue_redraw()

## Longueur de la ligne : la contrainte ne s'applique que si le champ de la
## caméra chevauche cette étendue
@export var longueur: float = 800.0:
	set(v):
		longueur = v
		queue_redraw()


## Appelé par la caméra : renvoie la position corrigée.
## `half` = demi-taille du champ de vision en coordonnées monde.
func clamp_camera(pos: Vector2, half: Vector2) -> Vector2:
	var demi := longueur * 0.5
	if bord_bloque == Bord.DROIT or bord_bloque == Bord.GAUCHE:
		# ligne verticale : active si le champ VERTICAL de la caméra la chevauche
		if pos.y + half.y < global_position.y - demi \
			or pos.y - half.y > global_position.y + demi:
			return pos
		if bord_bloque == Bord.DROIT:
			pos.x = minf(pos.x, global_position.x - half.x)
		else:
			pos.x = maxf(pos.x, global_position.x + half.x)
	else:
		# ligne horizontale : active si le champ HORIZONTAL la chevauche
		if pos.x + half.x < global_position.x - demi \
			or pos.x - half.x > global_position.x + demi:
			return pos
		if bord_bloque == Bord.BAS:
			pos.y = minf(pos.y, global_position.y - half.y)
		else:
			pos.y = maxf(pos.y, global_position.y + half.y)
	return pos


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var demi := longueur * 0.5
	var couleur := Color(1.0, 0.5, 0.1, 0.8)
	var vertical := bord_bloque == Bord.DROIT or bord_bloque == Bord.GAUCHE
	# la ligne
	if vertical:
		draw_line(Vector2(0, -demi), Vector2(0, demi), couleur, 6.0)
	else:
		draw_line(Vector2(-demi, 0), Vector2(demi, 0), couleur, 6.0)
	# flèches pointant vers la zone PERMISE (là où l'écran a le droit d'être)
	var dir_permise := Vector2.ZERO
	match bord_bloque:
		Bord.DROIT:  dir_permise = Vector2.LEFT
		Bord.GAUCHE: dir_permise = Vector2.RIGHT
		Bord.BAS:    dir_permise = Vector2.UP
		Bord.HAUT:   dir_permise = Vector2.DOWN
	for i in 3:
		var t := (float(i) - 1.0) * demi * 0.6
		var base := Vector2(0, t) if vertical else Vector2(t, 0)
		var pointe := base + dir_permise * 40.0
		draw_line(base, pointe, couleur, 4.0)
		var aile := dir_permise.orthogonal() * 12.0
		draw_line(pointe, pointe - dir_permise * 14.0 + aile, couleur, 4.0)
		draw_line(pointe, pointe - dir_permise * 14.0 - aile, couleur, 4.0)
