extends AnimatedSprite2D

@onready var player: CharacterBody2D = $"../.."
@onready var slash_attack: AnimatedSprite2D = $"../slash_attack"
@onready var collision: Area2D = $"../collision_attack"

@onready var hitbox_1: CollisionPolygon2D = $"../collision_attack/CollisionPolygon2D"
@onready var hitbox_2: CollisionPolygon2D = $"../collision_attack/CollisionPolygon2D2"
@onready var hitbox_3: CollisionPolygon2D = $"../collision_attack/CollisionPolygon2D3"
@onready var hitbox_4: CollisionPolygon2D = $"../collision_attack/CollisionPolygon2D4"


var damage = 70

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
		# Ennemi inébranlable (aucun knockback) : le contrecoup annule
		# l'élan du joueur au lieu de faire reculer l'ennemi
		if body is BaseAI and body.HIT_KNOCK_X == 0.0:
			player.cancel_movement_recoil()

# play() ne redémarre pas une anim déjà en cours de lecture —
# on force le stop pour que le slash reparte toujours de la frame 0
func _play_slash(anim_name: String) -> void:
	slash_attack.stop()
	slash_attack.visible = true  # peut avoir été masqué par un retournement du perso
	slash_attack.play(anim_name)

func _disable_all_hitboxes() -> void:
	hitbox_1.set_deferred("disabled", true)
	hitbox_2.set_deferred("disabled", true)
	hitbox_3.set_deferred("disabled", true)
	hitbox_4.set_deferred("disabled", true)

	
func _on_animation_changed() -> void:
	_disable_all_hitboxes()
	# frame_changed n'est pas émis quand on passe d'une anim en frame 0
	# à une nouvelle anim en frame 0 (la valeur ne change pas) —
	# on rattrape donc la frame 0 ici, au changement d'animation
	_process_frame_logic()

func _on_frame_changed():
	_process_frame_logic()

# garde-fou pour ne pas traiter deux fois la même frame de la même anim
var _last_frame_key := ""

func _process_frame_logic() -> void:
	var key := str(animation) + ":" + str(frame)
	if key == _last_frame_key:
		return
	_last_frame_key = key
	var current_animation = animation
	match current_animation:
		"attack":
			match frame:
				0:
					_disable_all_hitboxes()
				1:
					pass
				3:
					_disable_all_hitboxes()
					_play_slash("slash_1")
					hitbox_1.set_deferred("disabled", false)
		"attack_02":
			match frame:
				1:
					_play_slash("slash_2")
				2:
					hitbox_2.set_deferred("disabled", false)
				3:
					_disable_all_hitboxes()

	
		"attack_03":
			match frame:
				0:
					player.velocity.x = player.point.scale.x * 250
				1:
					hitbox_3.set_deferred("disabled", false)
					_play_slash("slash_3")
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
					_play_slash("slash_h")
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
