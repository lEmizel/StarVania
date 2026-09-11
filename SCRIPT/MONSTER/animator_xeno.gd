extends AnimatedSprite2D
## Pilote d'animation du XENO : deux attaques, deux hitboxes.
## - "attack" (corps à corps, 10 frames) : hitbox cac frames 4-5
## - "attack_langue" (bouche intérieure, 14 frames) : hitbox langue
##   pendant l'extension, frames 6-10 — à AJUSTER sur tes sprites

@onready var enemi: CharacterBody2D = $"../.."
@onready var collision: Area2D = $"../collision_attack"
@onready var hitbox_cac: CollisionPolygon2D = $"../collision_attack/CollisionPolygon2D"
@onready var hitbox_langue: CollisionPolygon2D = $"../collision_attack/langue"


func _ready() -> void:
	SignalUtils.connect_signal(self, "frame_changed", self, "_on_frame_changed")
	SignalUtils.connect_signal(self, "animation_changed", self, "_on_animation_changed")
	SignalUtils.connect_signal(collision, "body_entered", self, "_on_body_entered")
	_disable_all_hitboxes()


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("Player"):
		return
	if not body.has_method("apply_damage"):
		return
	body.apply_damage(enemi.attack_power, enemi.global_position.x, "attaque:" + enemi.name)


func _disable_all_hitboxes() -> void:
	hitbox_cac.set_deferred("disabled", true)
	hitbox_langue.set_deferred("disabled", true)


func _on_frame_changed() -> void:
	match animation:
		"attack":
			# partie 1 : frappe à partir de la frame 3 (jusqu'à la fin —
			# l'enchaînement vers attack_2 nettoie au changement d'anim)
			match frame:
				0:
					_disable_all_hitboxes()
				3:
					hitbox_cac.set_deferred("disabled", false)
		"attack_2":
			# partie 2 : frappe à partir de la frame 2
			match frame:
				0:
					_disable_all_hitboxes()
				2:
					hitbox_cac.set_deferred("disabled", false)
		"attack_langue":
			match frame:
				0:
					_disable_all_hitboxes()
				6:
					hitbox_langue.set_deferred("disabled", false)
				10:
					_disable_all_hitboxes()
		"dead":
			match frame:
				0:
					_disable_all_hitboxes()


func _on_animation_changed() -> void:
	_disable_all_hitboxes()
