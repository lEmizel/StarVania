# Personality_Skeleton.gd
extends "res://SCRIPT/MONSTER/Personality_Default.gd"

func _init():
	speed = 200
	speed_back = 100
	health = 30
	attack_power = 10
	confort_zone_max = 160
	confort_zone_min = 90
	max_tracking_distance = 800

func generate_desires(ai):
	ai.desires.clear()

	if ai.target != null:
		var distance_to_target = ai.global_position.distance_to(ai.target.global_position)
		
		if distance_to_target > ai.max_tracking_distance:
			ai.approach_initial_position = true
			ai.desires.append({"desire": "approach", "weight": 100})
		elif distance_to_target < ai.confort_zone_min:
			ai.desires.append({"desire": "retreat", "weight": 50})
			ai.desires.append({"desire": "attack", "weight": 70})
		elif distance_to_target > ai.confort_zone_max:
			ai.desires.append({"desire": "retreat", "weight": 0})
			ai.desires.append({"desire": "approach", "weight": 100})
			ai.desires.append({"desire": "movement", "weight": 0})
			#ai.desires.append({"desire": "defend", "weight": 30})
			ai.desires.append({"desire": "sleep", "weight": 0})
			if ai.garde and ai.previous_state != ai.States.DEFEND:
				ai.desires.append({"desire": "undefend", "weight": 0})
		else:
			ai.desires.append({"desire": "retreat", "weight": 0})
			ai.desires.append({"desire": "approach", "weight": 100})
			ai.desires.append({"desire": "movement", "weight": 0})
			ai.desires.append({"desire": "attack", "weight": 90})
			#ai.desires.append({"desire": "defend", "weight": 20})
			ai.desires.append({"desire": "sleep", "weight": 0})
			if ai.garde and ai.previous_state != ai.States.DEFEND:
				ai.desires.append({"desire": "undefend", "weight": 0})
	else:
		ai.sleep()
