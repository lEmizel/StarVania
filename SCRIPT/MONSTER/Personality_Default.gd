# BaseAIScript.gd
extends RefCounted

# Variables de configuration pour l'IA
var speed = 0  # Vitesse de déplacement de l'IA
var speed_back = 0  # Vitesse de déplacement en reculant
var health = 0  # Points de vie de l'IA
var attack_power = 0  # Puissance d'attaque de l'IA
var confort_zone_max = 0  # Distance maximale de la zone de confort
var confort_zone_min = 0  # Distance minimale de la zone de confort
var max_tracking_distance = 0  # Distance maximale de suivi de la cible
var vol = false

# Fonction pour générer les désirs de l'IA, neutre par défaut
func generate_desires(ai):
	# Nettoyer la liste des désirs existants
	ai.desires.clear()

	# Vérifier si une cible est présente
	if ai.target != null:
		# Calculer la distance à la cible
		var distance_to_target = ai.global_position.distance_to(ai.target.global_position)
		
		# Si la distance à la cible dépasse la distance de suivi maximale
		if distance_to_target > ai.max_tracking_distance:
			ai.approach_initial_position = true  # Marquer que l'IA doit revenir à sa position initiale
			pass  # Ajouter ici les désirs spécifiques pour ce cas
		
		# Si la distance à la cible est inférieure à la distance minimale de la zone de confort
		elif distance_to_target < ai.confort_zone_min:
			pass  # Ajouter ici les désirs spécifiques pour ce cas
		
		# Si la distance à la cible est supérieure à la distance maximale de la zone de confort
		elif distance_to_target > ai.confort_zone_max:
			pass  # Ajouter ici les désirs spécifiques pour ce cas
			# Si l'IA est en mode garde et que l'état précédent n'est pas "DEFEND"
			if ai.garde and ai.previous_state != ai.States.DEFEND:
				pass  # Ajouter ici les désirs spécifiques pour ce cas
		
		# Si la distance à la cible est dans la zone de confort
		else:
			pass  # Ajouter ici les désirs spécifiques pour ce cas
			# Si l'IA est en mode garde et que l'état précédent n'est pas "DEFEND"
			if ai.garde and ai.previous_state != ai.States.DEFEND:
				pass  # Ajouter ici les désirs spécifiques pour ce cas
	
	# Si aucune cible n'est présente
	else:
		ai.sleep()  # Mettre l'IA en état de repos
