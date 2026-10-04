extends Node2D
## ============================================================================
## ÉCLAIR ROUGE (4 oct. 2026, piège « tour au cristal rouge ») — l'éclair que le
## cristal tire DROIT SUR SA CIBLE, averti à l'avance (eclair_rouge.gdshader).
## La tour (SCRIPT/INTERACTIBLE/tour_cristal_rouge.gd) en garde un et le pilote,
## en positions du monde :
##     viser(depuis, jusqua)                  la ligne de visée suit sa cible
##                                            (un pointillé discret)
##     verrouiller(depuis, jusqua, normale)   elle se fige. `delai` s
##                                            d'AVERTISSEMENT (le pointillé file,
##                                            devient plein : le temps de sortir de
##                                            la ligne), puis la FRAPPE : tout ce
##                                            qui est dans la bande (`largeur`, du
##                                            cristal au point d'impact) est blessé
##                                            — le joueur perd `damage` cœur(s) et
##                                            est repoussé hors de la ligne, les
##                                            monstres prennent `degats_monstres` ;
##                                            la caméra tremble ; puis la TRACE
##     eteindre()                             plus rien
## `normale` : celle de la surface touchée au bout (le mur, le sol), pour la
## brûlure et les étincelles ; ZERO si le tir se perd dans le vide.
## Il ne suit pas la tour (`top_level`) : verrouillé, il reste où il est.
## Le signal `tire` part à l'instant de la frappe (la tour flashe).
##
## POUR LE JUGER : ouvrir la scène et faire F6 (visée, avertissement, frappe,
## trace, en boucle). Son allure : sur le matériau du nœud Eclair ; ses couleurs
## sont données par la tour.
## ============================================================================

signal tire

## lancé seul (F6) : en boucle
@export var demo_boucle := true

## posés par la tour
var largeur := 46.0          # la bande frappée (px)
var delai := 0.6             # l'avertissement (s)
var damage := 1
var degats_monstres := 999999
var secousse := 5.0
var couleur := Color(1.0, 0.13, 0.16)
var couleur_coeur := Color(1.0, 0.88, 0.84)

const DUREE_FRAPPE := 0.25
const DUREE_TRACE := 0.6
## la place de ses écarts, de ses branches et de sa lueur, de part et d'autre du tir (px)
const DEMI_HAUTEUR := 120.0
## le rectangle commence avant le cristal, et finit après le point d'impact
## (l'éclat, les étincelles)
const AVANT := 50.0
const APRES := 130.0
enum Etat { ETEINT, VISE, VERROUILLE }

@onready var _rect: ColorRect = $Eclair

var _etat := Etat.ETEINT
var _t := 0.0
var _temps := 0.0
var _frappe_faite := false
var _graine := 0.0
var _depuis := Vector2.ZERO
var _jusqua := Vector2.ZERO
var _demo := false
var _demo_t := 0.0


func _ready() -> void:
	top_level = true
	_demo = demo_boucle and get_parent() == get_tree().root
	visible = _demo
	_appliquer()


## la ligne de visée suit sa cible (sans effet une fois verrouillé)
func viser(depuis: Vector2, jusqua: Vector2) -> void:
	if _etat == Etat.VERROUILLE:
		return
	_etat = Etat.VISE
	_tendre(depuis, jusqua, Vector2.ZERO)
	visible = true


## la visée se fige : l'avertissement commence, la frappe suit
func verrouiller(depuis: Vector2, jusqua: Vector2, normale := Vector2.ZERO) -> void:
	_etat = Etat.VERROUILLE
	_t = 0.0
	_frappe_faite = false
	_graine = randf() * 100.0
	_tendre(depuis, jusqua, normale)
	visible = true


func eteindre() -> void:
	_etat = Etat.ETEINT
	visible = false


## vrai tant qu'un tir verrouillé n'a pas fini sa trace
func occupe() -> bool:
	return _etat == Etat.VERROUILLE


func _tendre(depuis: Vector2, jusqua: Vector2, normale: Vector2) -> void:
	_depuis = depuis
	_jusqua = jusqua
	global_position = depuis
	global_rotation = (jusqua - depuis).angle()
	var longueur := maxf(depuis.distance_to(jusqua), 8.0)
	_rect.position = Vector2(-AVANT, -DEMI_HAUTEUR)
	_rect.size = Vector2(longueur + AVANT + APRES, 2.0 * DEMI_HAUTEUR)
	var mat := _rect.material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("taille", _rect.size)
	mat.set_shader_parameter("depart", Vector2(AVANT, DEMI_HAUTEUR))
	mat.set_shader_parameter("longueur", longueur)
	mat.set_shader_parameter("largeur", largeur)
	mat.set_shader_parameter("bas", Vector2.DOWN.rotated(-global_rotation))
	mat.set_shader_parameter("normale", normale.rotated(-global_rotation) if normale != Vector2.ZERO else Vector2.ZERO)


func _physics_process(delta: float) -> void:
	if _demo:
		_demo_tourner(delta)
	if _etat != Etat.VERROUILLE:
		return
	_t += delta
	if not _frappe_faite and _t >= delai:
		_frappe_faite = true
		_frapper()
	if _t >= delai + DUREE_FRAPPE + DUREE_TRACE:
		eteindre()


func _process(delta: float) -> void:
	_temps += delta
	_appliquer()


## la frappe : tout ce qui est dans la bande, du cristal au point d'impact
func _frapper() -> void:
	tire.emit()
	if _demo:
		return
	var axe := (_jusqua - _depuis)
	var longueur := axe.length()
	if longueur < 1.0:
		return
	axe /= longueur
	var forme := RectangleShape2D.new()
	forme.size = Vector2(longueur, largeur)
	var requete := PhysicsShapeQueryParameters2D.new()
	requete.shape = forme
	requete.transform = Transform2D(axe.angle(), (_depuis + _jusqua) * 0.5)
	requete.collision_mask = 0b1011          # joueur et monstres, comme les pièges
	requete.collide_with_areas = false
	var vus := {}
	for resultat in get_world_2d().direct_space_state.intersect_shape(requete, 16):
		var corps = resultat["collider"]
		if vus.has(corps):
			continue
		vus[corps] = true
		if corps.has_method("apply_environment_damage"):
			# repoussé hors de la ligne, du côté où il est, un peu vers le haut
			var centre: Vector2 = corps.centre_corps() if corps.has_method("centre_corps") else (corps as Node2D).global_position
			var travers := axe.orthogonal()
			var cote := signf((centre - _depuis).dot(travers))
			var poussee := (travers * cote + Vector2(0.0, -0.6)) if cote != 0.0 else Vector2.UP
			corps.apply_environment_damage(damage, poussee.normalized())
		elif corps.has_method("apply_damage"):
			corps.apply_damage(degats_monstres, _depuis.x, "foudre")
	if secousse > 0.0:
		var cam := get_tree().get_first_node_in_group("Camera")
		if cam != null and cam.has_method("shake"):
			cam.shake(secousse, 10.0)
	print("[ÉCLAIR ROUGE] f=", Engine.get_physics_frames(), " frappe de ", _depuis.round(), " à ", _jusqua.round(), " (", vus.size(), " corps dans la bande)")


func _appliquer() -> void:
	if _rect == null:
		return
	var mat := _rect.material as ShaderMaterial
	if mat == null:
		return
	var verrou := _etat == Etat.VERROUILLE
	var avert := clampf(_t / maxf(delai, 0.001), 0.0, 1.0) if verrou else 0.0
	var frappe := clampf((_t - delai) / DUREE_FRAPPE, 0.0001, 1.0) if verrou and _t >= delai else 0.0
	var trace := clampf((_t - delai - DUREE_FRAPPE) / DUREE_TRACE, 0.0, 1.0) if verrou and _t >= delai + DUREE_FRAPPE else 0.0
	mat.set_shader_parameter("vise", 1.0 if _etat == Etat.VISE else 0.0)
	mat.set_shader_parameter("avert", avert)
	mat.set_shader_parameter("frappe", frappe)
	mat.set_shader_parameter("trace", trace)
	mat.set_shader_parameter("temps", _temps)
	mat.set_shader_parameter("graine", _graine)
	mat.set_shader_parameter("couleur", couleur_coeur)
	mat.set_shader_parameter("couleur_foudre", couleur)


## F6 : il vise un point qui monte et descend, se verrouille, tire, recommence
func _demo_tourner(delta: float) -> void:
	if _etat == Etat.VERROUILLE:
		return
	_demo_t += delta
	var vue := get_viewport_rect().size
	var depuis := vue * Vector2(0.2, 0.3)
	var jusqua := Vector2(vue.x * 0.82, vue.y * (0.6 + 0.25 * sin(_demo_t * 2.0)))
	if _demo_t < 0.5:
		eteindre()
		visible = true
	elif _demo_t < 1.5:
		viser(depuis, jusqua)
	else:
		_demo_t = 0.0
		verrouiller(depuis, jusqua, Vector2.LEFT)
