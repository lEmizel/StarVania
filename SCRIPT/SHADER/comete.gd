extends Node2D
## ============================================================================
## COMÈTE (2 oct. 2026, piège « pluie d'étoiles », choisi par Kaoru) — une
## étoile filante qui tombe sur un point du sol, AVERTIE (comete.gdshader).
## Posée par la pluie d'étoiles (SCRIPT/INTERACTIBLE/pluie_etoiles.gd) ; elle
## vit sa vie et se supprime :
##   • `delai` s d'AVERTISSEMENT : sa trajectoire se dessine du ciel au sol, une
##     étoile scintille au-dessus du point d'impact — le temps de s'écarter ;
##   • le VOL : elle file en accélérant (DUREE_VOL) ;
##   • l'IMPACT : ce qui est au-dessus de la marque (`rayon_impact` de chaque
##     côté, jusqu'à HAUTEUR_IMPACT) est blessé — le joueur perd `damage`
##     cœur(s) et il est repoussé, les monstres prennent `degats_monstres` ; la
##     caméra tremble ; une braise refroidit sur le sol.
## L'origine du nœud est le POINT D'IMPACT, au ras du sol ; `depart` est le
## point du ciel d'où elle part, vu depuis l'impact.
##
## POUR LA JUGER : ouvrir la scène et faire F6 (elle tombe en boucle).
## ============================================================================

## lancée seule (F6) : en boucle
@export var demo_boucle := true

## posés par la pluie d'étoiles avant l'entrée en scène
var depart := Vector2(-200.0, -560.0)
var delai := 0.9
var damage := 1
var degats_monstres := 999999
var rayon_impact := 60.0
var secousse := 4.0

const DUREE_VOL := 0.22
const DUREE_EXPLO := 0.7
const HAUTEUR_IMPACT := 130.0     # l'impact blesse jusqu'à cette hauteur au-dessus du sol (px)

@onready var _rect: ColorRect = $Comete

var _t := 0.0
var _frappe_faite := false
var _graine := 0.0
var _demo := false


func _ready() -> void:
	_demo = demo_boucle and get_parent() == get_tree().root
	if _demo:
		position = get_viewport_rect().size * Vector2(0.6, 0.85)
	_graine = randf() * 100.0
	# le rectangle : de l'impact (et son éclat) jusqu'au point de départ
	var mini := Vector2(minf(0.0, depart.x), minf(0.0, depart.y)) - Vector2(170.0, 60.0)
	var maxi := Vector2(maxf(0.0, depart.x), maxf(0.0, depart.y)) + Vector2(170.0, 60.0)
	_rect.position = mini
	_rect.size = maxi - mini
	var mat := _rect.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("taille", _rect.size)
		mat.set_shader_parameter("impact", -mini)
		mat.set_shader_parameter("depart", depart - mini)
	_appliquer()


func _physics_process(delta: float) -> void:
	_t += delta
	if not _frappe_faite and _t >= delai + DUREE_VOL:
		_frappe_faite = true
		_frapper()
	if _t >= delai + DUREE_VOL + DUREE_EXPLO:
		if _demo:
			_t = -0.5
			_frappe_faite = false
			_graine = randf() * 100.0
		else:
			queue_free()


func _process(_delta: float) -> void:
	_appliquer()


## l'impact : tout ce qui est au-dessus de la marque
func _frapper() -> void:
	if _demo:
		return
	var forme := RectangleShape2D.new()
	forme.size = Vector2(rayon_impact * 2.0, HAUTEUR_IMPACT)
	var requete := PhysicsShapeQueryParameters2D.new()
	requete.shape = forme
	requete.transform = Transform2D(0.0, global_position + Vector2(0.0, -HAUTEUR_IMPACT * 0.5))
	requete.collision_mask = 0b1011          # joueur et monstres, comme les pièges
	requete.collide_with_areas = false
	var vus := {}
	for resultat in get_world_2d().direct_space_state.intersect_shape(requete, 16):
		var corps = resultat["collider"]
		if vus.has(corps):
			continue
		vus[corps] = true
		if corps.has_method("apply_environment_damage"):
			# repoussé hors de l'impact, un peu vers le haut
			var cote := signf((corps as Node2D).global_position.x - global_position.x)
			if cote == 0.0:
				cote = 1.0
			corps.apply_environment_damage(damage, Vector2(cote, -0.7).normalized())
		elif corps.has_method("apply_damage"):
			corps.apply_damage(degats_monstres, global_position.x, "etoile")
	if secousse > 0.0:
		var cam := get_tree().get_first_node_in_group("Camera")
		if cam != null and cam.has_method("shake"):
			cam.shake(secousse, 10.0)


func _appliquer() -> void:
	var mat := _rect.material as ShaderMaterial
	if mat == null:
		return
	var avert := clampf(_t / maxf(delai, 0.001), 0.0, 1.0) if _t >= 0.0 else 0.0
	var vol := clampf((_t - delai) / DUREE_VOL, 0.0, 1.0) if _t >= delai else 0.0
	var explo := clampf((_t - delai - DUREE_VOL) / DUREE_EXPLO, 0.0, 1.0) if _t >= delai + DUREE_VOL else 0.0
	mat.set_shader_parameter("avert", avert)
	mat.set_shader_parameter("vol", vol if vol < 1.0 else 0.0)
	mat.set_shader_parameter("explo", maxf(explo, 0.0001) if _t >= delai + DUREE_VOL else 0.0)
	mat.set_shader_parameter("temps", maxf(_t, 0.0))
	mat.set_shader_parameter("graine", _graine)
