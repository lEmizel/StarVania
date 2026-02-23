# Personality_Skeleton.gd
extends "res://SCRIPT/MONSTER/Personality_Default.gd"

func _init():
	speed = 280
	speed_back = 200
	health = 180
	attack_power = 7
	confort_zone_max = 150
	confort_zone_min = 30
	max_tracking_distance = 1500

func generate_desires(ai):
	ai.desires.clear()

	# 1) Priorité au retour au point initial
	if ai.return_position != null:
		ai.desires.append({
			"desire": "return",
			"weight": 100
		})
		return

	# 2) Si on poursuit un target (Node2D)
	if ai.target != null:
		var dist = ai.global_position.distance_to(ai.target.global_position)

		# 2.a) Trop loin → on abandonne la cible et on revient
		if dist > ai.max_tracking_distance:
			ai.target = null
			ai.return_position = ai.initial_position
			ai.desires.append({
				"desire": "return",
				"weight": 100
			})
			return

		# 2.b) Trop proche → on approche, on recule puis on attaque
		elif dist < ai.confort_zone_min:
			ai.desires.append({ "desire": "sleep", "weight": 10 })
			ai.desires.append({ "desire": "retreat",  "weight":   30 })
			ai.desires.append({ "desire": "attack",   "weight":   350 })
			return

		# 2.c) Trop loin de la zone de confort → on approche
		elif dist > ai.confort_zone_max:
			ai.desires.append({ "desire": "approach", "weight": 250 })
			ai.desires.append({ "desire": "retreat",  "weight":   20 })
			ai.desires.append({ "desire": "sleep",  "weight": 50 })
			return

		# 2.d) Dans la zone de confort → on attaque ou on dort
		else:
			ai.desires.append({ "desire": "attack",   "weight":   200 })
			ai.desires.append({ "desire": "retreat",  "weight":   20 })
			ai.desires.append({ "desire": "sleep",  "weight": 10 })
			return

	# 3) Pas de cible et pas de retour → on dort
	ai.desires.append({
		"desire": "sleep",
		"weight": 1
	})
