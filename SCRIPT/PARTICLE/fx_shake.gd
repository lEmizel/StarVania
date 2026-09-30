extends Node2D
## ONDE DE CHOC du boss (attaque au sol). FX autonome : le boss l'instancie, elle
## joue, blesse ce qu'elle touche pendant une fenêtre précise, et se supprime.
##
## VISUEL (30 sept. 2026) : l'animation dessinée à la main a été remplacée par
## un shader, `SCRIPT/SHADER/onde_de_choc.tscn` (nœud Visuel). Ce script ne
## garde que le JEU : la zone de dégâts et son déroulé. Le visuel reçoit d'ici la
## vraie largeur de la zone, la hauteur du sol et les instants du coup — il se
## cale dessus, on ne règle rien en double.
##
## CAMPS (23 sept. 2026) : elle porte le camp du boss, posé par lui avant
## `add_child`, comme la boule de feu du squelette bleu. Elle blesse le joueur
## en cœurs (`damage`) et les monstres d'un autre camp en points de vie
## (`degats_monstres`), en se déclarant comme venant de `tireur` pour que la
## victime riposte contre le boss. Les alliés sont traversés.

## Déroulé, en secondes. Ce sont les temps de l'ancienne animation (9 images à
## 14 images/s, zone dangereuse pendant les images 5 et 6) : le rythme du coup
## de pied n'a pas changé.
@export var duree := 0.643
@export var debut_coup := 0.357
@export var fin_coup := 0.5

## sol introuvable sous l'onde : on reprend la hauteur de l'ancre du boss
const SOL_PAR_DEFAUT := 22.0
const PORTEE_SOL := 160.0

@onready var area: Area2D = $Area2D
@onready var collision_shape_2d: CollisionShape2D = $Area2D/CollisionShape2D
@onready var visuel: Node2D = $Visuel

## cœurs enlevés au joueur
var damage: int = 1
## posés par le lanceur
var faction: int = 0
var degats_monstres: int = 70
var tireur: Node = null

var _t := 0.0


func _ready() -> void:
	collision_shape_2d.disabled = true
	area.collision_mask |= 8          # les monstres aussi, pas seulement le joueur
	area.connect("body_entered", _on_body_entered)
	# le visuel se cale sur la VRAIE zone de dégâts, le vrai sol et le vrai déroulé
	var forme := collision_shape_2d.shape as RectangleShape2D
	if forme != null:
		visuel.demi_largeur = forme.size.x * 0.5
	visuel.centre_x = collision_shape_2d.position.x
	visuel.sol = _hauteur_du_sol()
	visuel.duree = duree
	visuel.debut_coup = debut_coup
	visuel.fin_coup = fin_coup
	visuel.jouer()


func _physics_process(delta: float) -> void:
	_t += delta
	var dangereuse := _t >= debut_coup and _t < fin_coup
	if collision_shape_2d.disabled == dangereuse:
		collision_shape_2d.disabled = not dangereuse
	if _t >= duree:
		queue_free()


## Distance entre ce nœud et le sol qu'il surplombe (couche des décors solides,
## pas celle du joueur : il est souvent pile sous le pied du boss).
func _hauteur_du_sol() -> float:
	var requete := PhysicsRayQueryParameters2D.create(
			global_position + Vector2(0.0, -20.0),
			global_position + Vector2(0.0, PORTEE_SOL), 2)
	var touche := get_world_2d().direct_space_state.intersect_ray(requete)
	if touche.is_empty():
		return SOL_PAR_DEFAUT
	var point: Vector2 = touche["position"]
	return point.y - global_position.y


func _on_body_entered(body: Node) -> void:
	if not body.has_method("apply_damage"):
		return
	var camp := BaseAI.faction_de(body)
	# le lanceur et ses alliés (monstres comme joueur) ne sont pas touchés
	if body == tireur or camp < 0 or camp == faction:
		return
	if body.is_in_group("Player"):
		body.apply_damage(damage, global_position.x, "onde_de_choc")
	else:
		body.apply_damage(degats_monstres, global_position.x, "onde_de_choc", true, tireur)
