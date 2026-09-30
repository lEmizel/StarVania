extends Area2D
## Boule de sang : file tout droit à vitesse constante, explose au contact
## d'un ennemi (en le blessant) ou d'un mur. L'explosion est une scène
## indépendante instanciée au point d'impact.
##
## Le même script pilote la TORNADE DE SANG (tornade_de_sang.tscn, talisman du
## même nom) : même vol, même zone de touche, mais `recul` y est coché.

const EXPLOSION_SCENE := preload("res://SCRIPT/SPELL/bloodball_explosion.tscn")

@export var speed := 800.0
@export var damage := 60  # sept. 2026 : un peu sous le coup léger au corps à corps (animator.gd : damage = 70)
## Portée maximale (px) avant auto-explosion : courte = outil de proximité,
## pas un sniper (avant sept. 2026 : ~1600 px via une durée de vie de 2 s)
@export var portee := 400.0
## true : l'ennemi touché est repoussé dans le sens du vol, comme par un coup
## d'épée (la boule de sang, elle, pique sans déplacer)
@export var recul := false

## Direction horizontale (+1 droite, -1 gauche) — posée par le player au spawn
var dir := 1

var _parcouru := 0.0
var _eclate := false     # a déjà explosé : un 2e contact dans la même frame ne compte pas


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	scale.x = dir  # oriente la boule, la traînée part derrière


func _physics_process(delta: float) -> void:
	var pas := speed * delta
	position.x += dir * pas
	_parcouru += pas
	if _parcouru >= portee:
		_explode(PUISSANCE_A_VIDE)


func _on_body_entered(body: Node) -> void:
	# ne jamais exploser sur le lanceur
	if _eclate or body.is_in_group("Player"):
		return
	if body.has_method("apply_damage"):
		if recul:
			# source placée juste derrière l'ennemi : il part TOUJOURS dans le
			# sens du vol, même touché à bout portant
			body.apply_damage(damage, (body as Node2D).global_position.x - dir, "tornade", true)
		else:
			# knockback = false : la bloodball pique sans déplacer (l'ennemi
			# se retourne et aggro quand même via la réaction de BASE_IA)
			body.apply_damage(damage, global_position.x, "bloodball", false)
	_explode()


## Force de l'éclaboussure quand la boule s'éteint toute seule en bout de
## course, sans rien toucher (1 = aussi grosse qu'un vrai impact).
const PUISSANCE_A_VIDE := 0.45


## `puissance` : 1 pour un vrai impact (ennemi ou mur). L'éclaboussure connaît
## le sens de vol de la boule : le sang rejaillit vers l'arrière.
func _explode(puissance := 1.0) -> void:
	if _eclate:
		return
	_eclate = true
	var explosion := EXPLOSION_SCENE.instantiate()
	explosion.demo_boucle = false
	explosion.direction = Vector2(float(dir), 0.0)
	explosion.puissance = puissance
	get_tree().current_scene.add_child(explosion)
	# ColorRect : global_position = coin haut-gauche → on recentre le rect
	# sur le point d'impact en retirant la moitié de sa taille
	explosion.global_position = global_position - explosion.size * 0.5
	# Un visuel qui sait se dissiper (la spirale de la tornade, avalée par
	# l'impact) finit de le faire avant que le projectile disparaisse : il ne
	# vole plus, ne touche plus rien, et c'est son visuel qui le supprime. La
	# boule de sang, elle, part tout de suite, comme avant.
	var visuel := get_node_or_null("Visual")
	if visuel != null and visuel.has_method("dissiper"):
		set_physics_process(false)
		set_deferred("monitoring", false)
		visuel.call("dissiper")
		return
	queue_free()
