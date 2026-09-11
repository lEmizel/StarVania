extends AnimatedSprite2D
## Pilote d'animation du SQUELETTE : hitbox d'attaque aux frames 4-5,
## FX de slash synchronisé avec le coup (caché au repos, coupé si
## l'attaque est interrompue).

@onready var enemi: CharacterBody2D = $"../.."
@onready var collision: Area2D = $"../collision_attack"
@onready var hitbox_1: CollisionPolygon2D = $"../collision_attack/CollisionPolygon2D"
@onready var slash_fx: AnimatedSprite2D = $"../slash_attack"


func _ready() -> void:
	SignalUtils.connect_signal(self, "frame_changed", self, "_on_frame_changed")
	SignalUtils.connect_signal(self, "animation_changed", self, "_on_animation_changed")
	SignalUtils.connect_signal(collision, "body_entered", self, "_on_body_entered")
	SignalUtils.connect_signal(slash_fx, "animation_finished", self, "_on_slash_finished")
	slash_fx.visible = false


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("Player"):
		return
	if not body.has_method("apply_damage"):
		return
	body.apply_damage(enemi.attack_power, enemi.global_position.x, "attaque:" + enemi.name)


func _disable_all_hitboxes() -> void:
	hitbox_1.set_deferred("disabled", true)


# --- FX de slash : même règle de vie que celui du joueur ---

func _on_slash_finished() -> void:
	slash_fx.visible = false


func _play_slash() -> void:
	slash_fx.stop()
	slash_fx.visible = true
	slash_fx.play("slash")


func _stop_slash() -> void:
	slash_fx.stop()
	slash_fx.visible = false


func _on_frame_changed() -> void:
	match animation:
		"attack":
			match frame:
				0:
					_disable_all_hitboxes()
				4:
					hitbox_1.set_deferred("disabled", false)
					_play_slash()  # le FX part avec le coup
				5:
					_disable_all_hitboxes()
		"dead":
			match frame:
				0:
					_disable_all_hitboxes()


func _on_animation_changed() -> void:
	_disable_all_hitboxes()
	# attaque terminée ou interrompue : le FX de slash meurt avec elle
	_stop_slash()
