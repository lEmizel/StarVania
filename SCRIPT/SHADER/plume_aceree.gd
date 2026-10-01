extends Node2D
## ============================================================================
## PLUME ACÉRÉE (1er oct. 2026) — talisman « Plumes acérées » (il faut le
## DOUBLE SAUT) : une plume que l'aile lâche au double saut, devenue lame. Elle
## file dans sa direction (vers le bas, en éventail), retombe un peu (`gravite`),
## et :
##   - touche un ennemi : il prend `degats` (posés par le joueur, sans recul), la
##     plume s'y plante et s'efface vite ;
##   - touche le sol ou un mur : elle s'y plante, la pointe dedans, et s'efface.
## Visuel : nœud Plume (plume_aceree.gdshader), tourné dans le sens de sa course,
## aux couleurs de l'aile. Posée par player.gd (`_plumes_lancer`).
##
## POUR LA JUGER : ouvrir la scène et faire F6 (une plume qui tombe en boucle —
## seulement lancée seule).
## ============================================================================

## lancée seule (F6) : elle retombe en boucle
@export var demo_boucle := true
## sa chute (px/s²) ; plantée, elle s'efface en… (s) — dans le sol, dans un ennemi
@export var gravite := 900.0
@export var duree_plantee := 0.45
@export var duree_plantee_ennemi := 0.18
## au-delà, elle disparaît d'elle-même (s)
@export var duree_max := 1.5

## posés par le joueur (player.gd, `_plumes_lancer`)
var joueur: CharacterBody2D = null
var vitesse := Vector2(0.0, 950.0)
var degats := 25

@onready var _plume: ColorRect = $Plume

var _vie := 0.0
var _plantee := -1.0          # depuis qu'elle est plantée (s ; < 0 : en vol)
var _duree_fin := 0.45
var _demo := false
var _depart_demo := Vector2.ZERO


func _ready() -> void:
	_demo = demo_boucle and get_parent() == get_tree().root
	if _demo:
		_depart_demo = get_viewport_rect().size * Vector2(0.5, 0.2)
		position = _depart_demo
	rotation = vitesse.angle()
	_appliquer()


## les couleurs de l'aile qui la lâche
func teindre(couleur, contour) -> void:
	var mat := _plume.material as ShaderMaterial
	if mat == null:
		return
	if couleur is Color:
		mat.set_shader_parameter("couleur", couleur)
	if contour is Color:
		mat.set_shader_parameter("couleur_contour", contour)


func _physics_process(delta: float) -> void:
	_vie += delta
	if _plantee >= 0.0:
		_plantee += delta
		if _plantee >= _duree_fin:
			if _demo:
				_recommencer()
			else:
				queue_free()
				return
		_appliquer()
		return
	if _vie >= duree_max:
		if _demo:
			_recommencer()
		else:
			queue_free()
		return
	vitesse.y += gravite * delta
	var depart := global_position
	var arrivee := depart + vitesse * delta
	if not _demo:
		var espace := get_world_2d().direct_space_state
		# un ennemi sur sa course ? (les monstres : couche 8)
		var q := PhysicsRayQueryParameters2D.create(depart, arrivee, 8)
		var touche := espace.intersect_ray(q)
		if not touche.is_empty():
			var c: Object = touche["collider"]
			if c is BaseAI and c.hp > 0 and not c.invulnerable and c.est_ennemi(joueur):
				c.apply_damage(degats, global_position.x, "plumes", false, joueur)
				print("[PLUMES] f=", Engine.get_physics_frames(), " une plume touche : ", degats, " dégâts")
				_planter(touche["position"], duree_plantee_ennemi)
				return
		# le sol, un mur (couche 1, où est aussi le joueur : on l'exclut)
		var q2 := PhysicsRayQueryParameters2D.create(depart, arrivee, 1)
		if joueur != null and is_instance_valid(joueur):
			q2.exclude = [joueur.get_rid()]
		var sol := espace.intersect_ray(q2)
		if not sol.is_empty():
			_planter(sol["position"], duree_plantee)
			return
	elif global_position.y > _depart_demo.y + 300.0:
		_planter(global_position, duree_plantee)
		return
	global_position = arrivee
	rotation = vitesse.angle()
	_appliquer()


## plantée là où elle a touché, la pointe dedans (un tiers de sa longueur)
func _planter(ou: Vector2, duree: float) -> void:
	var mat := _plume.material as ShaderMaterial
	var longueur := 46.0
	if mat != null and mat.get_shader_parameter("longueur") != null:
		longueur = float(mat.get_shader_parameter("longueur"))
	global_position = ou - vitesse.normalized() * longueur * 0.2
	_plantee = 0.0
	_duree_fin = duree
	_appliquer()


func _recommencer() -> void:
	position = _depart_demo
	vitesse = Vector2.from_angle(deg_to_rad(randf_range(60.0, 120.0))) * 950.0
	rotation = vitesse.angle()
	_vie = 0.0
	_plantee = -1.0


func _appliquer() -> void:
	var m := _plume.material as ShaderMaterial
	if m == null:
		return
	m.set_shader_parameter("taille", _plume.size)
	if _plantee >= 0.0:
		m.set_shader_parameter("trainee", 0.0)
		m.set_shader_parameter("opacite", 1.0 - clampf(_plantee / maxf(_duree_fin, 0.001), 0.0, 1.0))
	else:
		m.set_shader_parameter("trainee", 1.0)
		m.set_shader_parameter("opacite", 1.0)
