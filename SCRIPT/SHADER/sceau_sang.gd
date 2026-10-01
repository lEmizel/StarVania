@tool
extends Node2D
## ============================================================================
## SCEAU DE SANG (1er oct. 2026) — talisman « Offrande » (id "offrande") : se
## soigner fait naître ce sceau sous les pieds du joueur (player.gd,
## `_offrande_lancer`, au DÉBUT du soin). Il se DESSINE en `trace` s — deux
## cercles, une étoile à six branches, des runes —, puis lâche une ONDE qui
## court au sol jusqu'à `rayon` px en `onde` s : chaque ennemi qu'elle atteint
## (vivant, du camp d'en face, sans mur entre lui et le joueur) prend `degats`
## et est repoussé. De quoi finir son soin tranquille. Le sceau brille tant que
## dure le soin et s'éteint avec lui (`eteindre()`, soin fini ou interrompu) ;
## l'onde, elle, finit sa course quoi qu'il arrive.
## Vu de trois quarts, posé au sol (comme la couronne de la Vengeance) : le
## nœud est sous les PIEDS du joueur, il ne le suit pas. Un mur arrête l'onde,
## pour les dégâts (rayon de vue vers chaque ennemi) comme pour le dessin
## (`_murs` : la crête est coupée là où un rayon horizontal touche un mur).
##
## POUR LE JUGER : ouvrir la scène et faire F6 (il se dessine, lâche son onde,
## brille, s'éteint, en boucle — seulement lancé seul). L'allure se règle sur
## le matériau du nœud Sceau.
## ============================================================================

## il se dessine en… ; l'onde court en… ; il s'éteint en… (s)
@export var trace := 0.16
@export var onde := 0.34
@export var duree_fin := 0.25
## lancé seul (F6) : se dessine, lâche son onde, brille, s'éteint, en boucle
@export var demo_boucle := true

## posés par le joueur (player.gd, `_offrande_lancer`)
var joueur: CharacterBody2D = null
var rayon := 280.0
var degats := 70

## le rayon du sceau (où l'onde prend son départ) : celui du matériau
const RAYON_SCEAU := 105.0
## le rectangle de dessin doit contenir la crête de l'onde à son départ
const HAUTEUR_ONDE := 36.0
const APLAT := 0.24
const MARGE := 40.0

@onready var _sceau: ColorRect = $Sceau

var _t := 0.0
var _eteint := false
var _t_fin := 0.0
var _touches: Array[Node] = []
var _centre := Vector2.ZERO     # d'où l'onde cherche ses victimes : le milieu du corps du joueur
var _demo := false
var _mur_gauche := 10000.0      # où un mur arrête l'onde (px depuis les pieds)
var _mur_droit := 10000.0


func _ready() -> void:
	_cadrer()
	if Engine.is_editor_hint():
		_appliquer()
		return
	_demo = demo_boucle and get_parent() == get_tree().root
	if _demo:
		position = get_viewport_rect().size * Vector2(0.5, 0.6)
	if joueur != null and is_instance_valid(joueur):
		_centre = joueur.centre_corps()
	else:
		_centre = global_position + Vector2(0.0, -70.0)
	if not _demo:
		_murs()
	_appliquer()


## jusqu'où l'onde peut courir de chaque côté avant de buter sur un mur (un
## rayon horizontal à mi-corps, couche 1, sans le joueur)
func _murs() -> void:
	var espace := get_world_2d().direct_space_state
	for cote in [-1.0, 1.0]:
		var q := PhysicsRayQueryParameters2D.create(_centre, _centre + Vector2(cote * (rayon + MARGE), 0.0), 1)
		if joueur != null and is_instance_valid(joueur):
			q.exclude = [joueur.get_rid()]
		var touche := espace.intersect_ray(q)
		if touche.is_empty():
			continue
		var d := absf(float(touche["position"].x) - global_position.x)
		if cote < 0.0:
			_mur_gauche = d
		else:
			_mur_droit = d


## le soin est fini (ou interrompu) : le sceau s'éteint ; l'onde finit sa course
func eteindre() -> void:
	if _eteint:
		return
	_eteint = true
	_t_fin = 0.0


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_t += delta
	if _demo:
		if not _eteint and _t >= trace + onde + 0.9:
			eteindre()
	else:
		_onde_frapper()
	if _eteint:
		_t_fin += delta
		if _t_fin >= duree_fin and _onde_u() >= 1.0:
			if _demo:
				_t = 0.0
				_eteint = false
				_t_fin = 0.0
			else:
				queue_free()
				return
	_appliquer()


## où en est l'onde : 0 → 1
func _onde_u() -> float:
	return clampf((_t - trace) / maxf(onde, 0.001), 0.0, 1.0)


## l'onde frappe ceux que son front vient d'atteindre (même course que le dessin)
func _onde_frapper() -> void:
	var u := _onde_u()
	if u <= 0.0 or joueur == null or not is_instance_valid(joueur):
		return
	var r := lerpf(RAYON_SCEAU, rayon, 1.0 - (1.0 - u) * (1.0 - u))
	var espace := get_world_2d().direct_space_state
	var cercle := CircleShape2D.new()
	cercle.radius = r
	var requete := PhysicsShapeQueryParameters2D.new()
	requete.shape = cercle
	requete.transform = Transform2D(0.0, _centre)
	requete.collision_mask = 8               # la couche des monstres
	requete.collide_with_areas = false
	for resultat in espace.intersect_shape(requete, 32):
		var c: Node = resultat["collider"]
		if not (c is BaseAI) or _touches.has(c):
			continue
		if c.hp <= 0 or c.invulnerable or not c.est_ennemi(joueur):
			continue
		# un mur entre nous ? (murs solides = couche 1, où est aussi le joueur)
		var la: Vector2 = c.collision.global_position if c.collision != null else (c as Node2D).global_position
		var rayon_vue := PhysicsRayQueryParameters2D.create(_centre, la, 1)
		rayon_vue.exclude = [joueur.get_rid()]
		if not espace.intersect_ray(rayon_vue).is_empty():
			continue
		_touches.append(c)
		c.apply_damage(degats, joueur.global_position.x, "offrande", true, joueur)
		print("[OFFRANDE] f=", Engine.get_physics_frames(), " ", c.name, " : ", degats,
			" dégâts, à ", roundi(absf(la.x - _centre.x)), " px")


## le rectangle de dessin : assez large pour l'onde au bout de sa course, assez
## haut pour sa crête à son départ ; le nœud (les pieds) en est l'origine
func _cadrer() -> void:
	if _sceau == null:
		return
	var haut := APLAT * rayon + HAUTEUR_ONDE + MARGE * 0.6
	var bas := APLAT * rayon + MARGE * 0.6
	_sceau.position = Vector2(-(rayon + MARGE), -haut)
	_sceau.size = Vector2(2.0 * (rayon + MARGE), haut + bas)


func _appliquer() -> void:
	if not is_node_ready():
		return
	var mat := _sceau.material as ShaderMaterial
	if mat == null:
		return
	var editeur := Engine.is_editor_hint()
	mat.set_shader_parameter("taille", _sceau.size)
	mat.set_shader_parameter("origine", -_sceau.position)
	mat.set_shader_parameter("rayon_onde", rayon)
	mat.set_shader_parameter("trace", 1.0 if editeur else clampf(_t / maxf(trace, 0.001), 0.0, 1.0))
	mat.set_shader_parameter("onde", 0.0 if editeur else _onde_u())
	mat.set_shader_parameter("fin", clampf(_t_fin / maxf(duree_fin, 0.001), 0.0, 1.0) if _eteint else 0.0)
	mat.set_shader_parameter("temps", 0.0 if editeur else _t)
	mat.set_shader_parameter("mur_gauche", _mur_gauche)
	mat.set_shader_parameter("mur_droit", _mur_droit)
