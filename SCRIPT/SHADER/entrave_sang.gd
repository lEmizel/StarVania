extends Node2D
## ============================================================================
## ENTRAVE DE SANG (v2, 1er oct. 2026) — l'anneau du talisman « Entraves » (id
## "entraves", choisi par Kaoru) : posé sur un ennemi ENTRAVÉ (BASE_IA.gd,
## `entraver`), enfant de lui (il le suit), il l'enserre tant que dure le
## ralenti, à MI-HAUTEUR de son corps (`hauteur` ; d'abord à ses pieds : « sur
## les larves il apparaît trop bas, remonte, n'hésite pas à être à
## mi-hauteur »), au sol comme en vol (« faut que ça marche aussi sur les
## volants »).
## v2 — Kaoru : « fais plutôt un anneau similaire à la couronne, avec un
## décompte, c'est vachement plus joli » : c'est la COURONNE DE LA VENGEANCE
## passée autour de lui (entrave_sang.gdshader) — un anneau de trois quarts qui
## tourne, huit pointes, un dégradé, des gouttes —, et ses pointes rentrent une
## à une avec le temps qui reste (le DÉCOMPTE). Il se POSE d'un coup sec ; un
## nouveau coup qui entrave le fait BATTRE et ses pointes ressortent (le temps
## repart) ; libéré, il s'EFFACE en se desserrant.
## Deux rectangles, un seul matériau (partagé dans la scène, copié pour
## `Derriere` au lancement) : ce qui est derrière l'ennemi sous son sprite, le
## reste par-dessus.
##
## POUR LE JUGER : ouvrir la scène et faire F6 (une silhouette grise, tantôt au
## sol, tantôt en vol, entravée puis frappée de nouveau, en boucle). Son allure
## (les mesures et les couleurs de la couronne, le sens des pointes) : sur le
## matériau.
## ============================================================================

## lancé seul (F6) : une silhouette entravée, au sol puis en vol, en boucle
@export var demo_boucle := true
## où l'anneau l'enserre : 0 = à ses pieds, 0,5 = à mi-hauteur, 1 = en haut
@export_range(0.0, 1.0) var hauteur := 0.5
## l'anneau déborde son corps de… (× sa demi-largeur)
@export var largeur := 1.3

## la demi-largeur de la couronne dans le shader (son échelle 1)
const LARGEUR_COURONNE := 32.0
const DUREE_POSE := 0.12
const DUREE_EFFACE := 0.3
## le battement d'un nouveau coup : sa durée (s), de combien il grossit
const DUREE_POULS := 0.18
const AMPLEUR_POULS := 0.22

## posé par BASE_IA.entraver
var cible: Node2D = null

@onready var _derriere: ColorRect = $Derriere
@onready var _devant: ColorRect = $Devant

var _t := 0.0                  # depuis qu'il s'est posé (s) : la pose, la rotation
var _depuis := 0.0             # depuis le dernier coup qui entrave (s) : le décompte
var _duree := 2.0
var _efface_t := -1.0          # >= 0 : il s'efface
var _pouls := 0.0              # temps restant du battement
var _pose := false
var _y := 0.0                  # sa hauteur (lissée quand il quitte le sol ou s'y pose)
var _place := false
var _demo := false
var _demo_corps: ColorRect = null
var _demo_t := 0.0


func _ready() -> void:
	_demo = demo_boucle and get_parent() == get_tree().root
	if _devant.material != null:
		_derriere.material = _devant.material.duplicate()
		(_devant.material as ShaderMaterial).set_shader_parameter("couche", 1.0)
		(_derriere.material as ShaderMaterial).set_shader_parameter("couche", 0.0)
	if _demo:
		position = get_viewport_rect().size * 0.5
		_demo_corps = ColorRect.new()
		_demo_corps.color = Color(0.42, 0.44, 0.5)
		_demo_corps.size = Vector2(60.0, 150.0)
		add_child(_demo_corps)
		_derriere.z_index = -1
		_devant.z_index = 1
		serrer(2.0)
	else:
		_ranger_autour_de_la_cible()
	_maj(0.0)


## ce qui est derrière lui sous son sprite, le reste par-dessus
func _ranger_autour_de_la_cible() -> void:
	var sprite: CanvasItem = cible
	if cible is BaseAI and cible.animator != null:
		sprite = cible.animator
	var z := 0
	var n: Node = sprite
	while n is CanvasItem:
		z += (n as CanvasItem).z_index
		if not (n as CanvasItem).z_as_relative:
			break
		n = n.get_parent()
	for r in [_derriere, _devant]:
		(r as ColorRect).z_as_relative = false
	_derriere.z_index = z - 1
	_devant.z_index = z + 1


## un coup l'entrave pour `duree` s : l'anneau se pose (ou bat, s'il est déjà
## là) et ses pointes ressortent — le décompte repart
func serrer(duree := 2.0) -> void:
	_duree = maxf(duree, 0.01)
	if not _pose or _efface_t >= 0.0:
		_pose = true
		_t = 0.0
		_pouls = 0.0
	else:
		_pouls = DUREE_POULS
	_depuis = 0.0
	_efface_t = -1.0


## libéré (ou mort) : l'anneau s'efface en se desserrant
func relacher() -> void:
	if _efface_t < 0.0:
		_efface_t = 0.0


func _physics_process(delta: float) -> void:
	_t += delta
	_depuis += delta
	_pouls = maxf(_pouls - delta, 0.0)
	if _demo:
		_demo_tick(delta)
	if _efface_t >= 0.0:
		_efface_t += delta
		if _efface_t >= DUREE_EFFACE:
			if _demo:
				_pose = false
				_efface_t = -1.0
			else:
				queue_free()
				return
	_maj(delta)


## F6 : entravé, frappé de nouveau à mi-temps, libéré ; au sol puis en vol
func _demo_tick(delta: float) -> void:
	var avant := _demo_t
	_demo_t += delta
	var cycle := fmod(_demo_t, 3.4)
	var cycle_avant := fmod(avant, 3.4)
	if cycle < cycle_avant:
		serrer(2.0)
	if cycle_avant < 1.0 and cycle >= 1.0:
		serrer(2.0)                 # un nouveau coup : il bat, le temps repart
	if cycle_avant < 3.0 and cycle >= 3.0:
		relacher()


## son corps (dans le repère de son nœud) : milieu et demi-taille
func _corps() -> Dictionary:
	if _demo:
		var vol := fmod(_demo_t, 6.8) >= 3.4
		_demo_corps.position = Vector2(-30.0, -150.0 - (70.0 if vol else 0.0))
		return {"centre": Vector2(0.0, -75.0 - (70.0 if vol else 0.0)), "demi": Vector2(30.0, 75.0)}
	if cible is BaseAI and cible.collision != null and cible.collision.shape != null:
		var c: CollisionShape2D = cible.collision
		var r: Rect2 = c.shape.get_rect()
		var centre := c.position + r.get_center() * c.scale
		# sa forme de collision ne se retourne pas avec lui : tourné vers la
		# gauche, son corps (le sprite, sous POINT) est en miroir autour de POINT
		# — l'anneau suit le corps (l'orbe, dont la forme est décalée de 12 px,
		# avait son anneau à côté de lui quand on le frappait du mauvais côté)
		if cible.point != null and cible.point.scale.x < 0.0:
			centre.x = 2.0 * cible.point.position.x - centre.x
		return {"centre": centre, "demi": r.size * 0.5 * c.scale.abs()}
	return {"centre": Vector2(0.0, -60.0), "demi": Vector2(30.0, 60.0)}


func _maj(delta: float) -> void:
	var corps := _corps()
	var centre: Vector2 = corps["centre"]
	var demi: Vector2 = corps["demi"]
	var cible_y := lerpf(centre.y + demi.y, centre.y - demi.y, hauteur)
	if not _place:
		_y = cible_y
		_place = true
	else:
		_y = lerpf(_y, cible_y, clampf(delta * 12.0, 0.0, 1.0))
	_derriere.visible = _pose
	_devant.visible = _pose
	if not _pose:
		return
	# sa taille : celle de la couronne, à la largeur de son corps ; il bat d'un coup
	var bat := sin(PI * (1.0 - _pouls / DUREE_POULS)) if _pouls > 0.0 else 0.0
	var echelle := demi.x * largeur / LARGEUR_COURONNE * (1.0 + AMPLEUR_POULS * bat)
	var taille := Vector2(120.0, 170.0) * echelle * 1.4
	var ancre := taille * 0.5
	for rect in [_derriere, _devant]:
		var r := rect as ColorRect
		# le nœud reste sur l'origine de l'ennemi : c'est le dessin qui se place
		r.position = Vector2(centre.x, _y) - ancre
		r.size = taille
		var mat := r.material as ShaderMaterial
		if mat == null:
			continue
		mat.set_shader_parameter("taille", taille)
		mat.set_shader_parameter("ancre", ancre)
		mat.set_shader_parameter("echelle", echelle)
		mat.set_shader_parameter("apparition", clampf(_t / DUREE_POSE, 0.0, 1.0))
		mat.set_shader_parameter("restant", clampf(1.0 - _depuis / _duree, 0.0, 1.0))
		mat.set_shader_parameter("efface", clampf(_efface_t / DUREE_EFFACE, 0.0, 1.0) if _efface_t >= 0.0 else 0.0)
		mat.set_shader_parameter("temps", _t)
		mat.set_shader_parameter("pouls", bat)
