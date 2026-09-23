extends AnimatedSprite2D

@onready var enemi: CharacterBody2D = $"../.."

@onready var collision: Area2D = $"../collision_attack"

@onready var hitbox_1: CollisionPolygon2D = $"../collision_attack/CollisionPolygon2D"



func _ready() -> void:
	# 1) on connecte une fois les deux signaux
	SignalUtils.connect_signal(self, "frame_changed",    self, "_on_frame_changed")
	SignalUtils.connect_signal(self, "animation_changed", self, "_on_animation_changed")

	SignalUtils.connect_signal(collision, "body_entered", self, "_on_body_entered")

	
func _process(delta):
	pass
# 2) Ce handler est appelé à chaque fois qu'on change d'animation    

func _on_body_entered(body: Node) -> void:
	# CAMPS : c'est le monstre qui décide qui est un ennemi et à quelle échelle
	# il frappe (cœurs pour le joueur, points de vie pour un monstre)
	enemi.infliger(body, enemi.global_position.x, "attaque:" + enemi.name)
	

func _disable_all_hitboxes() -> void:
	hitbox_1.set_deferred("disabled", true)


	
func _on_frame_changed():
	var current_animation = animation
	match current_animation:
		"attack":
			match frame:
				0:
					_disable_all_hitboxes()
				1:
					pass
				2:
					pass
				3:
					pass
				4:
					hitbox_1.set_deferred("disabled", false)
				5:
					_disable_all_hitboxes()
		"attack_retour":
			match frame:
				0:
					_disable_all_hitboxes()
		"dead":
			match frame:
				0:
					_disable_all_hitboxes()
				
# ─────────────────────────────────────────────
# ANIMATION CHANGÉE  → on coupe tout
# ─────────────────────────────────────────────
func _on_animation_changed() -> void:
	_disable_all_hitboxes()
