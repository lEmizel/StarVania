extends AnimatedSprite2D

var initial_position: Vector2

func _ready():
	initial_position = position

func initialise(value: int):
	match value:
		0:
			reset_position()
			play("slash_attack")
		1:
			reset_position()
			play("slash_attack_1")
		2:
			reset_position()
			play("slash_attack_2")
		3:
			reset_position()
			play("slash_attack_3")
		4:
			position = Vector2(13, -43)  # Position spécifique pour l'attaque 4
			play("slash_sa_1")
		_:
			print("Valeur invalide : ", value)
	
	# Appeler l'animation d'opacité uniquement si la valeur n'est pas 4
	if value != 4:
		_animate_focus_opacity()

func set_position_for_value_4():
	# Remplace cette valeur par la position souhaitée pour l'attaque 4
	position = Vector2(300, 200)  # Exemple de position, à remplacer par la valeur désirée

func reset_position():
	# Remet la position initiale pour toutes les autres attaques
	position = initial_position

func _animate_focus_opacity():
	var tween = get_parent().create_tween()
	var duration = 0.08  # Durée de chaque transition d'opacité
	var start_opacity = 0.0  # Opacité initiale
	var end_opacity = 1.0

	# Animation de l'opacité de départ à la valeur haute
	var tween_opacity_down = tween.tween_property(self, "modulate:a", end_opacity, duration)
	tween_opacity_down.set_trans(Tween.TRANS_LINEAR)
	tween_opacity_down.set_ease(Tween.EASE_IN_OUT)

	# Pause avant de changer l'opacité dans l'autre sens
	tween.tween_interval(0.03)  # Délai de 0.1 seconde

	var tween_opacity_up = tween.tween_property(self, "modulate:a", start_opacity, duration)
	tween_opacity_up.set_trans(Tween.TRANS_LINEAR)
	tween_opacity_up.set_ease(Tween.EASE_IN_OUT)
