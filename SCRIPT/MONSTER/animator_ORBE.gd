extends AnimatedSprite2D

@onready var enemi: CharacterBody2D = $"../.."

@onready var collision: Area2D = $"../collision_attack"

@onready var hitbox_1: CollisionPolygon2D = $"../collision_attack/CollisionPolygon2D"


var damage = 95

func _ready() -> void:
	# 1) on connecte une fois les deux signaux
	SignalUtils.connect_signal(self, "frame_changed",    self, "_on_frame_changed")
	SignalUtils.connect_signal(self, "animation_changed", self, "_on_animation_changed")

	SignalUtils.connect_signal(collision, "body_entered", self, "_on_body_entered")

	
func _process(delta):
	pass
# 2) Ce handler est appelé à chaque fois qu'on change d'animation    

func _on_body_entered(body: Node) -> void:
	# 1) Vérifie que c'est bien un Player
	if not body.is_in_group("Player"):
		return

	# 2) Vérifie que l'objet sait recevoir des dégâts
	if not body.has_method("apply_damage"):
		return
	print("je touche le joueur")
	# 3) Applique les dégâts en lui passant aussi la position X du joueur
	body.apply_damage(damage, enemi.global_position.x)
	

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
					enemi.velocity.x = enemi.point.scale.x * 300
				3:
					pass
				4:
					pass
				5:
					hitbox_1.set_deferred("disabled", false)
		"dead":
			match frame:
				0:
					_disable_all_hitboxes()
				
# ─────────────────────────────────────────────
# ANIMATION CHANGÉE  → on coupe tout
# ─────────────────────────────────────────────
func _on_animation_changed() -> void:
	_disable_all_hitboxes()
