var target_position = Vector2()
var random_steps = 0
var max_displacement = 50  # Définir la limite de déplacement maximale

func movement_enter():
	if garde:
		animator.play("walk_back_shield")
	else:
		animator.play("walk_back")
	# Initialiser le nombre de déplacements restants
	random_steps = randi() % 3 + 1  # Choisir un chiffre entre 1 et 3
	set_next_random_position()
	print("Starting random movement with steps:", random_steps)

func set_next_random_position():
	if !is_target_valid():
		wake()
		return

	var target_pos = safe_get_target_global_position()
	var direction = (global_position - target_pos).normalized()
	var distance = confort_zone_min + randi() % (max_tracking_distance - confort_zone_min)
	
	# Calculer la nouvelle position aléatoire uniquement le long de l'axe X
	var new_position = Vector2(global_position.x + direction.x * distance, global_position.y)
	
	# Normaliser la position si elle dépasse max_displacement
	var displacement = new_position - global_position
	if abs(displacement.x) > max_displacement:
		displacement = displacement.normalized() * max_displacement
		new_position = global_position + displacement

	target_position = new_position

func movement_execute(_delta):
	if global_position.distance_to(target_position) < 5:  # Si la position cible est atteinte (avec une marge d'erreur)
		random_steps -= 1
		if random_steps <= 0:
			wake()  # Toutes les positions atteintes, on sort du mouvement
			return
		else:
			set_next_random_position()  # Définir la prochaine position aléatoire
	
	# Se déplacer vers la position cible uniquement le long de l'axe X
	var direction = (target_position - global_position).normalized()
	velocity.x = direction.x * speed_back
	
	if is_target_valid() and global_position.distance_to(safe_get_target_global_position()) < confort_zone_min:
		wake()  # Si on est trop proche de la cible, on sort du mouvement
		return

	if direction.x < 0:
		point.scale.x = -1
	else:
		point.scale.x = 1

func movement_exit():
	# Réinitialiser les variables
	velocity = Vector2.ZERO
	target_position = Vector2.ZERO
	print("Exiting random movement")

# Fonction utilitaire pour vérifier la validité de la target
func is_target_valid() -> bool:
	return is_instance_valid(target) and target != null

# Fonction utilitaire pour obtenir la position globale de la target en toute sécurité
func safe_get_target_global_position() -> Vector2:
	if is_target_valid():
		return target.global_position
	else:
		wake()  # Ou toute autre gestion appropriée
		return global_position  # Valeur de secours
