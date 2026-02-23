extends Area2D

@onready var remote_transform = $RemoteTransform2D
@onready var point = $POINT  # Assurez-vous que le chemin est correct
var move_speed = 250  # Vitesse de déplacement (unités par seconde)
var return_speed = 10  # Vitesse de retour (peut être différente de move_speed)
var moving_down = false
var moving_up = false
var target_position_y = null
var initial_position_y = null  # Stocker la position initiale
var cible = null
var porte = null
var porte_initial_y = null
var porte_target_y = null  # Position finale pour la porte
# Variable pour suivre si le joueur est dans la zone ou non
var player_in_zone = false

func _ready():
	initial_position_y = position.y  # Initialiser la position initiale
	if point:
		target_position_y = point.global_position.y  # Utiliser la position y globale du point comme cible
	call_deferred("cherche_porte")
	
func cherche_porte():
	print("Début de la recherche...")
	var group_names = get_groups()  # Obtenir tous les groupes auxquels ce noeud appartient
	
	# Vérifier si ce noeud appartient à des groupes spécifiques
	if not group_names:
		print("Ce noeud n'appartient à aucun groupe.")
		return

	# Rechercher dans l'arbre un Node2D qui appartient aux mêmes groupes
	for group_name in group_names:
		print("Recherche dans le groupe: ", group_name)
		var nodes = get_tree().get_nodes_in_group(str(group_name))
		for node in nodes:
			if node is Node2D and node != self:
				print("Node2D trouvé dans le même groupe (", group_name, "): ", node.name)
				porte = node
				porte_initial_y = porte.position.y
				porte_target_y = porte_initial_y - 300  # Définir la position finale en ajoutant 300 à la position initiale
				break  # Optionnel: sortir si un seul match est nécessaire
				

func _on_body_entered(body):
	if body.is_in_group("Player"):
		player_in_zone = true
		cible = body
		body.connect("suspended", Callable(self, "player_suspended"), CONNECT_ONE_SHOT)
		body.connect("not_suspended", Callable(self, "player_not_suspended"), CONNECT_ONE_SHOT)

func player_suspended():
	moving_up = false
	moving_down = true  # Commence à bouger vers le bas quand le signal est reçu
	remote_transform.remote_path = cible.get_path()

	# Appliquer un décalage horizontal basé sur la dernière direction du joueur
	var offset_x = 0
	if cible.last_direction == 1:
		offset_x = -20  # Décalage à gauche si la dernière direction est à droite
	elif cible.last_direction == -1:
		offset_x = 20  # Décalage à droite si la dernière direction est à gauche

	# Mettre à jour la position locale du RemoteTransform2D pour appliquer le décalage
	remote_transform.position.x = offset_x
	
func player_not_suspended():
	moving_up = true  # Commencer le mouvement vers le haut
	moving_down = false  # S'assurer de ne pas continuer à descendre
	remote_transform.remote_path = NodePath()  # Détacher le RemoteTransform2D
	# Déconnecter les signaux pour éviter des connexions multiples ou des signaux persistants
	if cible:
		cible = null  # Réinitialiser la cible pour éviter les références persistantes

func _physics_process(delta):
	if moving_down:
		var step = move_speed * delta
		if position.y < target_position_y:
			position.y += step
			if porte and porte.position.y > porte_target_y:
				porte.position.y -= step  # La porte monte tandis que l'Area2D descend
			if position.y > target_position_y:
				position.y = target_position_y
		else:
			moving_down = false  # Arrêter le mouvement si la cible est atteinte

	elif moving_up and not player_in_zone:
		var step = return_speed * delta
		if position.y > initial_position_y:
			position.y -= step
			if porte and porte.position.y < porte_initial_y:
				porte.position.y += step  # La porte descend tandis que l'Area2D monte
			if position.y < initial_position_y:
				position.y = initial_position_y
		else:
			moving_up = false  # Arrêter le mouvement si revenu à la position initiale

func _on_body_exited(body):
	if body.is_in_group("Player"):
		player_in_zone = false  # Le joueur a quitté la zone
