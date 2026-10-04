extends Node2D
## ============================================================================
## COMÈTE (2 oct. 2026, piège « pluie d'étoiles ») — une
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
## TALISMAN « GARDIENNES » (4 oct. 2026) : elle est trop rapide pour qu'une
## goutte la poursuive, mais elle est annoncée. Un peu avant de partir, si
## quelqu'un que des Gardiennes protègent se tient sous l'impact, elle les
## prévient (`garder_passage`) : une goutte va se poster sur sa trajectoire,
## au-dessus de sa tête. Quand la comète y passe et que la goutte y est
## (`tir_arrive`), elle éclate là, en l'air : ni dégât, ni secousse, ni braise.
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
const GROUPE_GARDIENNES := "gardiennes"
## les Gardiennes sont prévenues… avant le départ (s) : le temps qu'une goutte se poste
const GARDE_AVANCE := 0.12
## le poste de la goutte : sur la trajectoire, à cette hauteur au-dessus des
## pieds de celui qu'elle garde (sa tête, et un peu d'air), et jamais plus bas
## que GARDE_MINI au-dessus du sol (px)
const GARDE_HAUTEUR := 195.0
const GARDE_MINI := 90.0

@onready var _rect: ColorRect = $Comete

var _t := 0.0
var _frappe_faite := false
var _graine := 0.0
var _demo := false
var _coin := Vector2.ZERO          # le coin du rectangle, depuis l'impact
var _garde: Node = null            # les Gardiennes dont une goutte attend sur la trajectoire
var _garde_tentee := false         # elle a déjà été attendue à son poste (une seule fois)
var _garde_vol := 0.0              # la part du vol (0 → 1) où la tête passe à ce poste
var _arret := Vector2.ZERO         # ce poste, depuis l'impact
var _arret_t := -1.0               # l'instant où elle y a été arrêtée (s ; < 0 : elle ne l'a pas été)


func _ready() -> void:
	_demo = demo_boucle and get_parent() == get_tree().root
	if _demo:
		position = get_viewport_rect().size * Vector2(0.6, 0.85)
	_graine = randf() * 100.0
	# le rectangle : de l'impact (et son éclat) jusqu'au point de départ
	var mini := Vector2(minf(0.0, depart.x), minf(0.0, depart.y)) - Vector2(170.0, 60.0)
	var maxi := Vector2(maxf(0.0, depart.x), maxf(0.0, depart.y)) + Vector2(170.0, 60.0)
	_coin = mini
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
	if _arret_t >= 0.0:
		# arrêtée en vol : son éclat, puis plus rien
		if _t >= _arret_t + DUREE_EXPLO:
			queue_free()
		return
	if not _frappe_faite and not _demo:
		_voir_les_gardiennes()
	if _arret_t < 0.0 and not _frappe_faite and _t >= delai + DUREE_VOL:
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


## ce qui se tient au-dessus de la marque : les corps que l'impact blesse
func _corps_sous_l_impact() -> Array:
	var forme := RectangleShape2D.new()
	forme.size = Vector2(rayon_impact * 2.0, HAUTEUR_IMPACT)
	var requete := PhysicsShapeQueryParameters2D.new()
	requete.shape = forme
	requete.transform = Transform2D(0.0, global_position + Vector2(0.0, -HAUTEUR_IMPACT * 0.5))
	requete.collision_mask = 0b1011          # joueur et monstres, comme les pièges
	requete.collide_with_areas = false
	var corps := []
	for resultat in get_world_2d().direct_space_state.intersect_shape(requete, 16):
		if not corps.has(resultat["collider"]):
			corps.append(resultat["collider"])
	return corps


## l'impact : tout ce qui est au-dessus de la marque
func _frapper() -> void:
	if _demo:
		return
	for corps in _corps_sous_l_impact():
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


## TALISMAN « GARDIENNES » : prévenir celles de quiconque se tient sous
## l'impact, puis, en passant à leur poste, voir si la goutte y est
func _voir_les_gardiennes() -> void:
	if _garde != null:
		if _t >= delai + _garde_vol * DUREE_VOL:
			var gardiennes := _garde
			_garde = null
			_garde_tentee = true
			if is_instance_valid(gardiennes) and gardiennes.tir_arrive(self):
				_arret_t = _t
				_frappe_faite = true
		return
	if _garde_tentee or _t < delai - GARDE_AVANCE or _t >= delai + DUREE_VOL:
		return
	var menaces := []
	var cherche := false
	for gardiennes in get_tree().get_nodes_in_group(GROUPE_GARDIENNES):
		# (le nœud existe même sans le talisman : il est alors caché)
		if not (gardiennes as CanvasItem).visible:
			continue
		if not cherche:
			cherche = true
			menaces = _corps_sous_l_impact()
		var porteur = gardiennes.get("joueur")
		if not (porteur is Node2D) or not menaces.has(porteur):
			continue
		# le poste : sur la trajectoire, au-dessus de sa tête
		var chute := maxf(-depart.y, 1.0)
		var hauteur := clampf(global_position.y - (porteur as Node2D).global_position.y + GARDE_HAUTEUR, GARDE_MINI, chute * 0.9)
		var part := clampf(1.0 - hauteur / chute, 0.02, 0.98)       # la part du trajet déjà faite à ce poste
		var vol_poste := sqrt(part)                                    # elle accélère : trajet = vol²
		var poste := depart * (1.0 - part)
		var dans := delai + vol_poste * DUREE_VOL - _t
		if dans > 0.0 and gardiennes.garder_passage(self, global_position + poste, dans):
			_garde = gardiennes
			_garde_vol = vol_poste
			_arret = poste
			return


func _appliquer() -> void:
	var mat := _rect.material as ShaderMaterial
	if mat == null:
		return
	if _arret_t >= 0.0:
		# arrêtée en vol : plus de tête ni de traîne, son éclat là où elle en était
		mat.set_shader_parameter("vol", 0.0)
		mat.set_shader_parameter("explo", clampf((_t - _arret_t) / DUREE_EXPLO, 0.0001, 1.0))
		mat.set_shader_parameter("arretee", 1.0)
		mat.set_shader_parameter("arret", _arret - _coin)
		mat.set_shader_parameter("temps", maxf(_t, 0.0))
		return
	var avert := clampf(_t / maxf(delai, 0.001), 0.0, 1.0) if _t >= 0.0 else 0.0
	var vol := clampf((_t - delai) / DUREE_VOL, 0.0, 1.0) if _t >= delai else 0.0
	var explo := clampf((_t - delai - DUREE_VOL) / DUREE_EXPLO, 0.0, 1.0) if _t >= delai + DUREE_VOL else 0.0
	mat.set_shader_parameter("avert", avert)
	mat.set_shader_parameter("vol", vol if vol < 1.0 else 0.0)
	mat.set_shader_parameter("explo", maxf(explo, 0.0001) if _t >= delai + DUREE_VOL else 0.0)
	mat.set_shader_parameter("arretee", 0.0)
	mat.set_shader_parameter("temps", maxf(_t, 0.0))
	mat.set_shader_parameter("graine", _graine)
