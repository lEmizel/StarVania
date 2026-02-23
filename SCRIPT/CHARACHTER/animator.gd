extends AnimatedSprite2D

@onready var player: CharacterBody2D = $"../.."
@onready var slash_attack: AnimatedSprite2D = $"../slash_attack"
@onready var collision: Area2D = $"../collision_attack"

@onready var hitbox_1: CollisionPolygon2D = $"../collision_attack/CollisionPolygon2D"
@onready var hitbox_2: CollisionPolygon2D = $"../collision_attack/CollisionPolygon2D2"
@onready var hitbox_3: CollisionPolygon2D = $"../collision_attack/CollisionPolygon2D3"
@onready var hitbox_4: CollisionPolygon2D = $"../collision_attack/CollisionPolygon2D4"


var damage = 70
@export var HPDega: int = 40  # PV rendus via rally sur coup réussi

func _ready() -> void:
	# 1) on connecte une fois les deux signaux
	SignalUtils.connect_signal(self, "frame_changed",    self, "_on_frame_changed")
	SignalUtils.connect_signal(self, "animation_changed", self, "_on_animation_changed")

	SignalUtils.connect_signal(collision, "body_entered", self, "_on_body_entered")

	
func _process(delta):
	pass
# 2) Ce handler est appelé à chaque fois qu'on change d'animation    

func _on_body_entered(body):
	# on passe en paramètre amount ET la position X du joueur
	if body.has_method("apply_damage"):
		body.apply_damage(damage, player.global_position.x)
		if HPDega > 0:
			Player.demande_rally_heal(HPDega)

func _disable_all_hitboxes() -> void:
	hitbox_1.set_deferred("disabled", true)
	hitbox_2.set_deferred("disabled", true)
	hitbox_3.set_deferred("disabled", true)
	hitbox_4.set_deferred("disabled", true)

	
func _on_animation_changed() -> void:
	_disable_all_hitboxes()

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
					hitbox_1.set_deferred("disabled", false)
					slash_attack.play("slash_1")
					player.velocity.x = player.point.scale.x * 200
				3:
					pass
				4:
					_disable_all_hitboxes()
					player.velocity.x = 0
		"attack_02":
			match frame:
				0:
					player.velocity.x = player.point.scale.x * 200
				1:
					hitbox_2.set_deferred("disabled", false)
					slash_attack.play("slash_2")
				2:
					_disable_all_hitboxes()
					player.velocity.x = 0

	
		"attack_03":
			match frame:
				0:
					player.velocity.x = player.point.scale.x * 250
				1:
					hitbox_3.set_deferred("disabled", false)
					slash_attack.play("slash_3")
				2:
					pass
				3:
					_disable_all_hitboxes()
					pass

		"attack_03_r":
			match frame:
				0:
					pass
				1:
					player.velocity.x = 0
		"attack_lourde":
			match frame:
				0:
					pass
				1:
					pass
				2:
					player.velocity.x = player.point.scale.x * 250
				3:
					slash_attack.play("slash_h")
				4:
					pass
				5:
					player.velocity.x = 0
				6:
					pass
				7:
					pass
		"attack_air":
			match frame:
				0:
					pass
				1:
					pass
				5:
					hitbox_4.set_deferred("disabled", false)
				6:
					_disable_all_hitboxes()
