extends Area2D
## ============================================================================
## BOULE DE FEU — projectile d'ENNEMI (le squelette bleu la lance).
##
## Elle file en ligne droite dans `direction`, blesse le joueur et EXPLOSE au
## contact d'un mur comme du joueur. Au bout de sa portée elle ne fait pas
## d'explosion dans le vide : elle s'éteint en douceur, en baissant la
## `puissance` de son visuel.
##
## Le visuel est une instance de `SCRIPT/SHADER/boule_de_feu.tscn`, posée à
## l'origine du projectile (l'origine de ce nœud EST le centre de la boule) ; le
## nœud est tourné vers sa direction, la traînée suit donc toute seule.
##
## POSE PAR LE LANCEUR, avant `add_child` : `direction` (et `damage` au besoin).
##
## Couches : masque 1 = le joueur (couche 1) ET les blocs solides (couche 3,
## donc bit 1) ; les monstres sont couche 8, la boule ne peut donc jamais
## toucher celui qui l'a tirée ni ses congénères.
## ============================================================================

const EXPLOSION := preload("res://SCRIPT/SPELL/explosion_feu.tscn")

## cœurs enlevés au joueur
@export var damage: int = 1
@export var speed := 800.0        # même vitesse que la bloodball du joueur
## portée avant extinction. 2200 px = plus d'une largeur d'écran (1920)
@export var portee := 2200.0
## temps que met la boule à s'éteindre en bout de course
@export var duree_extinction := 0.25

## direction de vol, posée par le lanceur AVANT d'ajouter le nœud à la scène
var direction := Vector2.RIGHT
## CAMPS (23 sept. 2026) : posés par le lanceur. La boule traverse le tireur et
## ses alliés, blesse le joueur en cœurs (`damage`) et les monstres ennemis en
## points de vie (`degats_monstres`), en se déclarant comme venant de `tireur`
## pour que la victime riposte contre lui.
var faction: int = 0
var degats_monstres: int = 70
var tireur: Node = null

var _parcouru := 0.0
var _extinction := -1.0        # >= 0 : compte à rebours avant la disparition

@onready var _visuel: Node2D = $Visuel
@onready var _forme: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	collision_mask |= 8               # les monstres aussi, pas seulement le joueur
	if direction.length_squared() < 0.0001:
		direction = Vector2.RIGHT
	direction = direction.normalized()
	rotation = direction.angle()      # le visuel et sa traînée suivent le tir
	if _visuel != null and "demo_vol" in _visuel:
		_visuel.demo_vol = false      # c'est le projectile qui vole, pas la démo


func _physics_process(delta: float) -> void:
	if _extinction >= 0.0:
		_extinction -= delta
		if _extinction <= 0.0:
			queue_free()
		return
	var pas := speed * delta
	global_position += direction * pas
	_parcouru += pas
	if _parcouru >= portee:
		_s_eteindre()


func _on_body_entered(body: Node) -> void:
	if _extinction >= 0.0:
		return
	var camp := BaseAI.faction_de(body)
	# le tireur et ses alliés (monstres comme joueur) sont traversés sans exploser
	if body == tireur or (camp >= 0 and camp == faction):
		return
	if body.is_in_group("Player") and body.has_method("apply_damage"):
		body.apply_damage(damage, global_position.x, "boule_de_feu")
	elif body is BaseAI:
		body.apply_damage(degats_monstres, global_position.x, "boule_de_feu", true, tireur)
	_exploser()


func _exploser() -> void:
	var ex := EXPLOSION.instantiate()
	get_tree().current_scene.add_child(ex)
	# ColorRect : global_position = coin haut-gauche → on la recentre sur l'impact
	ex.global_position = global_position - ex.size * 0.5
	queue_free()


## Bout de course : pas d'explosion dans le vide, la boule retombe en braise.
func _s_eteindre() -> void:
	_extinction = duree_extinction + 0.05
	_forme.set_deferred("disabled", true)
	if _visuel != null and _visuel.has_method("regler"):
		_visuel.regler(0.0, duree_extinction)
