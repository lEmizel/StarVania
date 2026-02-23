extends AnimatedSprite2D

@onready var character = get_parent().get_parent()
@onready var attack = $zone_attaque/attack
@onready var slash_attack = $slash_attack

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass

func _on_frame_changed():
	var current_animation = animation
	match current_animation:
		"attack":
			match frame:
				0:
					pass
				1:
					pass
				2:
					slash_attack.initialise(0)
					attack.call_deferred("set_disabled", false)
					print("zoneattack", attack)
					character.velocity.x = -character.point.scale.x * 100
					character.velocity.y = 0
				3:
					attack.call_deferred("set_disabled", true)
					print("zoneattack", attack)
				4:
					character.velocity.x = 0

func _on_animation_finished():
	attack.call_deferred("set_disabled", true)

func _on_animation_changed():
	attack.call_deferred("set_disabled", true)
	slash_attack.cancel()
