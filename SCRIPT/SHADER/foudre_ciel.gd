extends Node2D
## ============================================================================
## FOUDRE DU CIEL (2 oct. 2026, piège « pilier de foudre », idée de Kaoru) — un
## éclair qui tombe du ciel sur un point du sol, AVERTI à l'avance
## (foudre_ciel.gdshader). Posé par le pilier (SCRIPT/INTERACTIBLE/pilier_foudre.gd)
## là où se tenait le joueur ; il vit sa vie et se supprime :
##   • `delai` s d'AVERTISSEMENT (marque crépitante au sol, trait de visée qui
##     descend du ciel) : le temps de s'écarter ;
##   • la FRAPPE : ce qui est dans la bande (`largeur`, du sol au ciel) est
##     blessé — le joueur perd `damage` cœur(s) et est repoussé, les monstres
##     prennent `degats_monstres` ; la caméra tremble ;
##   • la TRACE : une brûlure qui refroidit, des étincelles.
## L'origine du nœud est le POINT D'IMPACT, au ras du sol.
##
## POUR LA JUGER : ouvrir la scène et faire F6 (avertissement, frappe, trace, en
## boucle). Son allure : sur le matériau du nœud Foudre.
## ============================================================================

## lancée seule (F6) : en boucle
@export var demo_boucle := true

## posés par le pilier avant l'entrée en scène
var hauteur := 700.0        # du ciel au sol (px)
var largeur := 70.0         # la bande frappée (px)
var delai := 0.9            # l'avertissement (s)
var damage := 1
var degats_monstres := 999999
var secousse := 7.0

const DUREE_FRAPPE := 0.3
const DUREE_TRACE := 0.75

@onready var _rect: ColorRect = $Foudre

var _t := 0.0
var _frappe_faite := false
var _graine := 0.0
var _demo := false


func _ready() -> void:
	_demo = demo_boucle and get_parent() == get_tree().root
	if _demo:
		hauteur = get_viewport_rect().size.y * 0.75
		position = Vector2(get_viewport_rect().size.x * 0.5, get_viewport_rect().size.y * 0.85)
	_graine = randf() * 100.0
	# le rectangle : la bande, ses branches et sa lueur, du ciel jusqu'un peu
	# sous le sol (pour la lueur qui déborde)
	var w := largeur + 320.0
	_rect.position = Vector2(-w * 0.5, -hauteur - 20.0)
	_rect.size = Vector2(w, hauteur + 60.0)
	var mat := _rect.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("taille", _rect.size)
		mat.set_shader_parameter("sol", Vector2(w * 0.5, hauteur + 20.0))
		mat.set_shader_parameter("hauteur", hauteur)
		mat.set_shader_parameter("largeur", largeur)
	_appliquer()


func _physics_process(delta: float) -> void:
	_t += delta
	if not _frappe_faite and _t >= delai:
		_frappe_faite = true
		_frapper()
	if _t >= delai + DUREE_FRAPPE + DUREE_TRACE:
		if _demo:
			_t = -0.6
			_frappe_faite = false
			_graine = randf() * 100.0
		else:
			queue_free()


func _process(_delta: float) -> void:
	_appliquer()


## la frappe : tout ce qui est dans la bande, du sol jusqu'au ciel
func _frapper() -> void:
	if _demo:
		return
	var forme := RectangleShape2D.new()
	forme.size = Vector2(largeur, hauteur)
	var requete := PhysicsShapeQueryParameters2D.new()
	requete.shape = forme
	requete.transform = Transform2D(0.0, global_position + Vector2(0.0, -hauteur * 0.5))
	requete.collision_mask = 0b1011          # joueur et monstres, comme les pièges
	requete.collide_with_areas = false
	var vus := {}
	for resultat in get_world_2d().direct_space_state.intersect_shape(requete, 16):
		var corps = resultat["collider"]
		if vus.has(corps):
			continue
		vus[corps] = true
		if corps.has_method("apply_environment_damage"):
			# repoussé hors de la bande, un peu vers le haut
			var cote := signf((corps as Node2D).global_position.x - global_position.x)
			if cote == 0.0:
				cote = 1.0
			corps.apply_environment_damage(damage, Vector2(cote, -0.7).normalized())
		elif corps.has_method("apply_damage"):
			corps.apply_damage(degats_monstres, global_position.x, "foudre")
	if secousse > 0.0:
		var cam := get_tree().get_first_node_in_group("Camera")
		if cam != null and cam.has_method("shake"):
			cam.shake(secousse, 10.0)
	print("[FOUDRE] f=", Engine.get_physics_frames(), " frappe en ", global_position, " (", vus.size(), " corps dans la bande)")


func _appliquer() -> void:
	var mat := _rect.material as ShaderMaterial
	if mat == null:
		return
	var avert := clampf(_t / maxf(delai, 0.001), 0.0, 1.0) if _t >= 0.0 else 0.0
	var frappe := clampf((_t - delai) / DUREE_FRAPPE, 0.0, 1.0) if _t >= delai else 0.0
	var trace := clampf((_t - delai - DUREE_FRAPPE) / DUREE_TRACE, 0.0, 1.0) if _t >= delai + DUREE_FRAPPE else 0.0
	mat.set_shader_parameter("avert", avert)
	mat.set_shader_parameter("frappe", maxf(frappe, 0.0001) if _t >= delai else 0.0)
	mat.set_shader_parameter("trace", trace)
	mat.set_shader_parameter("temps", maxf(_t, 0.0))
	mat.set_shader_parameter("graine", _graine)
