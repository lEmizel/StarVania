
extends Area2D

var damage_sa_1 = 20
var damage = 10
var estoc = false
var grand_parent = null

func _ready():
	connect("body_entered", Callable(self, "_on_body_entered"))
	grand_parent = get_parent().get_parent().get_parent() # on reference ici le main script 

func _on_body_entered(body):
	print("ooooooooooooooooooooo")
	if body.is_in_group("ennemi"):
		print ("garde", body.garde)
		var body_position = body.global_position.x
		var player_position = grand_parent.global_position.x
		var is_facing_player = (body.point.scale.x == 1 and body_position > player_position) or (body.point.scale.x == -1 and body_position < player_position)
		if body.current_state == body.States.DEAD:
			return
		body.ennemi_position(grand_parent.global_position.x)
		
		# Vérifiez si l'Area2D parent est lié à "attack_6"
		if name != "attack_6":
			if body.garde and not estoc and is_facing_player:
				body.knoback_guard()
				grand_parent.position_x_player = body.global_position.x
				détecte_garde()
				print(grand_parent.position_x_player)
			else:
				if body.has_method("apply_damage"):
					estoc = false
					body.apply_damage(damage)
		else:
			if body.has_method("apply_damage"):
				estoc = false
				body.apply_damage(damage)
