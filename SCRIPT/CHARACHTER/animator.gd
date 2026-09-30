extends AnimatedSprite2D

@onready var player: CharacterBody2D = $"../.."
@onready var slash_attack: AnimatedSprite2D = $"../slash_attack"
@onready var collision: Area2D = $"../collision_attack"

@onready var hitbox_1: CollisionPolygon2D = $"../collision_attack/CollisionPolygon2D"
@onready var hitbox_2: CollisionPolygon2D = $"../collision_attack/CollisionPolygon2D2"
@onready var hitbox_3: CollisionPolygon2D = $"../collision_attack/CollisionPolygon2D3"
@onready var hitbox_4: CollisionPolygon2D = $"../collision_attack/CollisionPolygon2D4"


var damage = 70

## l'éclat blanc qui marque un coup qui porte (30 sept. 2026)
const IMPACT := preload("res://SCRIPT/SHADER/impact_blanc.tscn")
## l'éclat reste à cette distance du bord de la zone balayée par la lame
const MARGE_ZONE := 24.0

func _ready() -> void:
	# 1) on connecte une fois les deux signaux
	SignalUtils.connect_signal(self, "frame_changed",    self, "_on_frame_changed")
	SignalUtils.connect_signal(self, "animation_changed", self, "_on_animation_changed")

	SignalUtils.connect_signal(collision, "body_entered", self, "_on_body_entered")
	# le FX de slash ne vit que le temps de son animation : caché au repos
	SignalUtils.connect_signal(slash_attack, "animation_finished", self, "_on_slash_finished")
	slash_attack.visible = false


func _on_slash_finished() -> void:
	slash_attack.visible = false

	
func _process(delta):
	pass
# 2) Ce handler est appelé à chaque fois qu'on change d'animation    

func _on_body_entered(body):
	# on passe en paramètre amount ET la position X du joueur
	if body.has_method("apply_damage"):
		var porte = body.apply_damage(damage, player.global_position.x)
		# coup au corps à corps qui PORTE (pas sur un mort ni un blindé) :
		# la jauge bloodheal se recharge de 20 % d'une barre (sept. 2026 :
		# c'est le coup qui recharge, plus le kill)
		if porte != false:
			Player.changement_de_bloodheal(Player.BLOODHEAL_PAR_COUP)
			_eclat_impact(body)
		# Ennemi inébranlable : le contrecoup annule l'élan du joueur
		# au lieu de faire reculer l'ennemi
		if body is BaseAI and body.inebranlable:
			player.cancel_movement_recoil()


## L'éclat d'impact : posé là où la lame rencontre le corps, tourné dans le sens
## du coup. Seulement quand le coup PORTE (ni sur un mort, ni sur un blindé) :
## c'est la confirmation visuelle que l'épée a mordu. Hébergé par la scène, pas
## par le monstre — il doit finir de jouer même si le monstre meurt du coup, et
## il reste où le coup est tombé pendant que le monstre recule.
func _eclat_impact(body: Node) -> void:
	if not (body is Node2D):
		return
	var centre: Vector2 = body.global_position
	if body is BaseAI and body.collision != null:
		centre = body.collision.global_position      # le milieu du corps, pas ses pieds
	var sens := signf(centre.x - player.global_position.x)
	if sens == 0.0:
		sens = float(player.last_direction)
	# un gros monstre a son milieu hors de portée de l'épée : l'éclat ne sort
	# jamais de la zone que la lame balaie vraiment
	var zone := _zone_du_coup()
	if zone.has_area():
		centre = centre.clamp(zone.position, zone.end)
	var fx := IMPACT.instantiate()
	fx.demo_boucle = false
	fx.z_index = 5                                    # devant le monstre et son flash
	var hote: Node = get_tree().current_scene
	if hote == null:
		hote = player.get_parent()
	hote.add_child(fx)
	# jamais deux fois au même endroit ni sous le même angle
	fx.global_position = centre + Vector2(-sens * 8.0, randf_range(-16.0, 16.0))
	fx.scale = Vector2(sens, 1.0)
	fx.rotation = randf_range(-0.3, 0.3)


## Le rectangle (en coordonnées du monde) que couvrent les hitbox d'attaque
## actives, un peu rentré. Vide si aucune n'est active.
func _zone_du_coup() -> Rect2:
	var zone := Rect2()
	var vide := true
	for hb: CollisionPolygon2D in [hitbox_1, hitbox_2, hitbox_3, hitbox_4]:
		if hb.disabled:
			continue
		for pt in hb.polygon:
			var g: Vector2 = hb.global_transform * pt
			if vide:
				zone = Rect2(g, Vector2.ZERO)
				vide = false
			else:
				zone = zone.expand(g)
	return zone.grow(-MARGE_ZONE) if not vide else zone

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
	# le perso change d'animation = le coup en cours est terminé ou
	# interrompu : son FX de slash disparaît avec lui (un éventuel coup
	# suivant relancera le sien via _play_slash)
	slash_attack.stop()
	slash_attack.visible = false
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
				2:
					_disable_all_hitboxes()
					_play_slash("new_slash_1")
					hitbox_1.set_deferred("disabled", false)
		"attack_02":
			match frame:
				1:
					_play_slash("new_slash_1")
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
				3:
					_play_slash("slash_air")
					hitbox_4.set_deferred("disabled", false)
				6:
					_disable_all_hitboxes()
