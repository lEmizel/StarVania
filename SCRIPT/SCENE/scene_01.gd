extends Node2D

func _process(delta: float) -> void:
	if Input.is_action_just_pressed("test1"):
		print("La touche test1 a été pressée")

	if Input.is_action_just_pressed("test2"):
		print("La touche test2 a été pressée")
