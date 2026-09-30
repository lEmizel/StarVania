extends AnimatedSprite2D

@onready var player: CharacterBody2D = $"../.."
@onready var slash_attack: AnimatedSprite2D = $"../slash_attack"
@onready var collision: Area2D = $"../collision_attack"

@onready var hitbox_1: CollisionPolygon2D = $"../collision_attack/CollisionPolygon2D"
@onready var hitbox_2: CollisionPolygon2D = $"../collision_attack/CollisionPolygon2D2"
@onready var hitbox_3: CollisionPolygon2D = $"../collision_attack/CollisionPolygon2D3"
@onready var hitbox_4: CollisionPolygon2D = $"../collision_attack/CollisionPolygon2D4"


## dégâts DE BASE d'un coup d'épée ; le coup réel les multiplie par les bonus
## des talismans portés (`Player.multiplicateur_degats()`, un pourcentage),
## voir `degats_du_coup()`
var damage = 70

## l'éclat blanc qui marque un coup qui porte (30 sept. 2026)
const IMPACT := preload("res://SCRIPT/SHADER/impact_blanc.tscn")
## l'éclat reste à cette distance du bord de la zone balayée par la lame
const MARGE_ZONE := 24.0

## LE SLASH EN SHADER (30 sept. 2026) : le même croissant que les dessins, mais
## à chaque image d'écran. Il remplace les dessins qu'il sait refaire
## (`new_slash_1`, `slash_air`) tant que `slash_en_shader` est coché sur le
## joueur ; les autres slashs, et tous si la case est décochée, restent dessinés.
const SLASH_SHADER := preload("res://SCRIPT/SHADER/slash_heros.tscn")
var _slash_shader: Node2D

## TALISMAN « LAME DE FOUDRE » (30 sept. 2026) : porté, le slash est fait de
## foudre et, quand le coup PORTE, l'éclair bondit de l'ennemi touché sur
## l'ennemi le plus proche (`player.foudre_portee`), sans recul, pour
## `player.foudre_degats` — et ainsi de suite `player.foudre_sauts` fois, en
## divisant les dégâts par deux à chaque bond. Le bond ne recharge pas le
## bloodheal (seul le coup d'épée le fait). Un même ennemi n'est frappé qu'une
## fois par coup, directement ou par l'éclair.
const TALISMAN_FOUDRE := "foudre"
const ARC_FOUDRE := preload("res://SCRIPT/SHADER/arc_foudre.tscn")
var _foudre_touches: Array[Node] = []

func _ready() -> void:
	# 1) on connecte une fois les deux signaux
	SignalUtils.connect_signal(self, "frame_changed",    self, "_on_frame_changed")
	SignalUtils.connect_signal(self, "animation_changed", self, "_on_animation_changed")

	SignalUtils.connect_signal(collision, "body_entered", self, "_on_body_entered")
	# le FX de slash ne vit que le temps de son animation : caché au repos
	SignalUtils.connect_signal(slash_attack, "animation_finished", self, "_on_slash_finished")
	slash_attack.visible = false
	# le slash en shader : frère du slash dessiné, sous POINT (il se retourne
	# avec le perso), posé après lui pour se dessiner au même rang
	_slash_shader = SLASH_SHADER.instantiate()
	_slash_shader.demo_boucle = false
	slash_attack.add_sibling.call_deferred(_slash_shader)


func _on_slash_finished() -> void:
	slash_attack.visible = false

	
func _process(delta):
	pass
# 2) Ce handler est appelé à chaque fois qu'on change d'animation    

## les dégâts d'un coup d'épée, bonus des talismans compris (70 → 77 avec la
## lame de foudre, +10 %)
func degats_du_coup() -> int:
	return roundi(damage * Player.multiplicateur_degats())


func _on_body_entered(body):
	# on passe en paramètre amount ET la position X du joueur
	if body.has_method("apply_damage"):
		var coup := degats_du_coup()
		var porte = body.apply_damage(coup, player.global_position.x)
		# coup au corps à corps qui PORTE (pas sur un mort ni un blindé) :
		# la jauge bloodheal se recharge de 20 % d'une barre (sept. 2026 :
		# c'est le coup qui recharge, plus le kill)
		if porte != false:
			Player.changement_de_bloodheal(Player.BLOODHEAL_PAR_COUP)
			_eclat_impact(body)
			_foudre_touches.append(body)
			if Player.talisman_equipe(TALISMAN_FOUDRE):
				_foudre_bondir(body, coup)
		# Ennemi inébranlable : le contrecoup annule l'élan du joueur
		# au lieu de faire reculer l'ennemi
		if body is BaseAI and body.inebranlable:
			player.cancel_movement_recoil()


## Le bond de la lame de foudre : depuis l'ennemi touché par un coup de `coup`
## dégâts, l'éclair saute sur le voisin le plus proche encore indemne (pour
## `foudre_part` du coup), puis du voisin au suivant (moitié à chaque bond).
## L'arc est posé dans la scène (comme l'éclat d'impact) : il finit de jouer
## même si l'ennemi meurt du coup.
func _foudre_bondir(depuis: Node, coup: int) -> void:
	var source: Node = depuis
	var degats: int = maxi(roundi(coup * player.foudre_part), 1)
	for _saut in player.foudre_sauts:
		var cible := _foudre_cible(source)
		if cible == null:
			return
		_foudre_touches.append(cible)
		var arc := ARC_FOUDRE.instantiate()
		arc.demo_boucle = false
		var hote: Node = get_tree().current_scene
		if hote == null:
			hote = player.get_parent()
		hote.add_child(arc)
		arc.tendre(_centre_du_corps(source), _centre_du_corps(cible))
		# la foudre se retourne contre le joueur, pas contre l'ennemi d'où elle
		# a sauté : c'est lui l'attaquant (pas de recul : l'éclair pique)
		var porte = cible.apply_damage(degats, player.global_position.x, "foudre", false, player)
		if porte == false:
			return
		source = cible
		degats = maxi(roundi(degats * 0.5), 1)


## L'ennemi le plus proche de `depuis` à portée de l'éclair, vivant, vulnérable,
## du camp d'en face, pas encore frappé par ce coup, et sans mur entre les deux.
func _foudre_cible(depuis: Node) -> Node:
	var espace := player.get_world_2d().direct_space_state
	var origine := _centre_du_corps(depuis)
	var cercle := CircleShape2D.new()
	cercle.radius = player.foudre_portee
	var requete := PhysicsShapeQueryParameters2D.new()
	requete.shape = cercle
	requete.transform = Transform2D(0.0, origine)
	requete.collision_mask = 8           # la couche des monstres
	requete.collide_with_areas = false
	var meilleur: Node = null
	var meilleure_distance := INF
	for resultat in espace.intersect_shape(requete, 16):
		var c: Node = resultat["collider"]
		if c == depuis or not (c is BaseAI) or _foudre_touches.has(c):
			continue
		if c.hp <= 0 or c.invulnerable or not c.est_ennemi(player):
			continue
		var la := _centre_du_corps(c)
		var distance := origine.distance_to(la)
		if distance >= meilleure_distance:
			continue
		# un mur entre les deux ? (murs solides = couche 1, comme le rayon du
		# grappin ; le JOUEUR est aussi sur la couche 1 : on l'exclut, sinon
		# l'éclair refuse tout voisin de l'autre côté de lui — les volants qui
		# tournent autour de lui en faisaient les frais)
		var rayon := PhysicsRayQueryParameters2D.create(origine, la, 1)
		rayon.exclude = [player.get_rid()]
		if not espace.intersect_ray(rayon).is_empty():
			continue
		meilleur = c
		meilleure_distance = distance
	return meilleur


## le milieu du corps d'un monstre (pas ses pieds)
func _centre_du_corps(n: Node) -> Vector2:
	if n is BaseAI and n.collision != null:
		return n.collision.global_position
	return (n as Node2D).global_position


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
	couper_slash()
	_foudre_touches.clear()      # un nouveau coup : tout le monde est de nouveau frappable
	# en shader si on sait le refaire : à la place exacte du dessin (player.gd
	# la pose sur slash_attack à chaque attaque)
	if player.slash_en_shader and _slash_shader.is_inside_tree() and _slash_shader.connait(anim_name):
		_slash_shader.position = slash_attack.position
		_slash_shader.effet = "foudre" if Player.talisman_equipe(TALISMAN_FOUDRE) else "aucun"
		_slash_shader.jouer(anim_name)
		return
	slash_attack.visible = true  # peut avoir été masqué par un retournement du perso
	slash_attack.play(anim_name)


## Le coup en cours est terminé ou interrompu : son slash disparaît, qu'il soit
## dessiné ou en shader.
func couper_slash() -> void:
	slash_attack.stop()
	slash_attack.visible = false
	if _slash_shader != null:
		_slash_shader.couper()

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
	couper_slash()
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
