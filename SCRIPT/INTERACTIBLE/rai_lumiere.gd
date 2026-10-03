@tool
extends Node2D
## ============================================================================
## RAI DE LUMIÈRE d'un PASSAGE (3 oct. 2026, d'après une image de référence de
## Kaoru : la lumière qui entre par une porte, ses poussières, sa brume) —
## enfant de SCRIPT/INTERACTIBLE/passage.tscn.
## Il se RÈGLE SUR LE PASSAGE lui-même (groupe « Rai de lumière » de
## passage.gd) : chaque passage posé se règle dans l'inspecteur, sans « enfants
## modifiables ».
##   • DE CÔTÉ (passage horizontal) : il part vers la SALLE, du côté du Marker2D
##     (le point d'arrivée), passage retourné compris ;
##   • en VERTICAL (Kaoru : « faudrait en faire un pour les passages en mode
##     vertical, à cocher pour expliciter le mode ») : une colonne qui TOMBE du
##     trou du plafond jusqu'au sol, ou qui MONTE du trou du sol. `rai_mode`
##     AUTO suit le passage : horizontal → de côté ; vertical → selon son rôle
##     (haut du tableau = elle tombe, bas = elle monte), déduit comme le fait
##     passage.gd quand le rôle est en AUTO ;
##   • @tool : visible dans l'éditeur, il suit les réglages en direct (et la
##     place du passage, dont dépend son rôle déduit). Son rectangle est
##     fabriqué par le script (enfant interne) : rien n'est enregistré dans les
##     scènes.
## Dessin : SCRIPT/SHADER/rai_lumiere.gdshader.
## ============================================================================

const SHADER := preload("res://SCRIPT/SHADER/rai_lumiere.gdshader")
const META := "genere_par_rai_lumiere"
const MARGE := 40.0                 # autour du rai : poussières, lueur du liseré
const LARGEUR_OUVERTURE := 22.0     # l'ouverture blanche, derrière le départ du rai (comme le shader)
const HALO_OUVERTURE := 60.0        # sa lueur déborde d'autant
# en vertical, la colonne reste DROITE (Kaoru : « plus vertical droit plutôt qu'en
# oblique, sinon il rentre dans les murs » — à 0,35 elle s'évasait sur les murs du puits)
const EVASEMENT := 0.0

# les valeurs de passage.gd (ModeRai, Role)
const MODE_AUTO := 0
const MODE_DE_COTE := 1
const MODE_TOMBE := 2
const MODE_MONTE := 3
const ROLE_AUTO := 0
const ROLE_HAUT := 1

var _signature := ""


func _ready() -> void:
	set_process(Engine.is_editor_hint())     # en jeu, rien à suivre : le shader s'anime seul
	_construire()


## ÉDITEUR : on suit les réglages du passage en direct
func _process(_delta: float) -> void:
	if _calculer_signature() != _signature:
		_construire()


func _reglage(nom: String, defaut: Variant) -> Variant:
	var p := get_parent()
	if p == null:
		return defaut
	var v: Variant = p.get(nom)
	return defaut if v == null else v


## +1 : la salle est vers la droite du passage (repère du passage) ; −1 : à gauche
func _sens_salle() -> float:
	var p := get_parent()
	var m: Node2D = p.get_node_or_null("Marker2D") as Node2D if p != null else null
	if m != null and absf(m.position.x) > 0.5:
		return signf(m.position.x)
	return 1.0


## le mode réellement dessiné (AUTO résolu)
func _mode() -> int:
	var m: int = int(_reglage("rai_mode", MODE_AUTO))
	if m != MODE_AUTO:
		return m
	if not _reglage("vertical", false):
		return MODE_DE_COTE
	return MODE_TOMBE if _role_haut() else MODE_MONTE


## le passage est-il en HAUT de son tableau ? (son rôle, ou déduit comme
## passage.gd le fait : au-dessus du milieu du décor solide du niveau)
func _role_haut() -> bool:
	var role: int = int(_reglage("role", ROLE_AUTO))
	if role != ROLE_AUTO:
		return role == ROLE_HAUT
	var p := get_parent() as Node2D
	if p == null:
		return true
	var racine: Node = p.owner if p.owner != null else p.get_parent()
	if racine == null:
		return true
	var haut := INF
	var bas := -INF
	for corps in racine.find_children("*", "StaticBody2D", true, false):
		for f in corps.get_children():
			var pts := PackedVector2Array()
			if f is CollisionShape2D and f.shape != null:
				var r: Rect2 = f.shape.get_rect()
				pts = PackedVector2Array([r.position, r.position + Vector2(r.size.x, 0.0),
					r.position + r.size, r.position + Vector2(0.0, r.size.y)])
			elif f is CollisionPolygon2D:
				pts = f.polygon
			for q in pts:
				var y: float = (f.global_transform * q).y
				haut = minf(haut, y)
				bas = maxf(bas, y)
	if haut > bas:
		return true
	return p.global_position.y < (haut + bas) * 0.5


func _calculer_signature() -> String:
	var p := get_parent() as Node2D
	var m: Node2D = p.get_node_or_null("Marker2D") as Node2D if p != null else null
	return str([_reglage("vertical", false), _reglage("role", ROLE_AUTO), _reglage("rai_mode", MODE_AUTO),
		_reglage("rai_de_lumiere", true), _reglage("rai_depart", 0.0),
		_reglage("rai_hauteur", 300.0), _reglage("rai_longueur", 420.0), _reglage("rai_intensite", 1.0),
		_reglage("rai_couleur", Color(1.0, 0.96, 0.88)), _reglage("rai_ouverture", 0.8),
		_reglage("rai_vitesse_ondulation", 0.6),
		m.position if m != null else Vector2.ZERO, p.global_position.round() if p != null else Vector2.ZERO])


func _construire() -> void:
	_signature = _calculer_signature()
	for enfant in get_children(true):
		if enfant.has_meta(META):
			remove_child(enfant)
			enfant.queue_free()
	if not _reglage("rai_de_lumiere", true):
		return
	var mode := _mode()
	var depart: float = _reglage("rai_depart", 0.0)
	var taille_ouv: float = maxf(_reglage("rai_hauteur", 300.0), 10.0)
	var long: float = maxf(_reglage("rai_longueur", 420.0), 10.0)
	var rect := ColorRect.new()
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	rect.material = mat
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_meta(META, true)
	var arriere := LARGEUR_OUVERTURE + HALO_OUVERTURE
	if mode == MODE_DE_COTE:
		# tourné vers la salle : de l'ouverture (et sa lueur) au point où le rai
		# touche le sol ; retourné (scale.x = −1) si la salle est à gauche
		var sens := _sens_salle()
		var dessus := taille_ouv + MARGE + HALO_OUVERTURE * 0.5
		rect.size = Vector2(arriere + long + MARGE, dessus + MARGE * 0.5)
		rect.scale = Vector2(sens, 1.0)
		rect.position = Vector2(depart * sens - arriere * sens, -dessus)
		mat.set_shader_parameter("mode", 0.0)
		mat.set_shader_parameter("source", Vector2(arriere, dessus))
	else:
		# une colonne centrée sur le passage, qui part du trou : vers le bas
		# (elle tombe), ou retournée (scale.y = −1) vers le haut (elle monte)
		var sens_y := 1.0 if mode == MODE_TOMBE else -1.0
		var large := taille_ouv * (1.0 + EVASEMENT) + MARGE * 2.0
		rect.size = Vector2(large, arriere + long + MARGE)
		rect.scale = Vector2(1.0, sens_y)
		rect.position = Vector2(-large * 0.5, depart * sens_y - arriere * sens_y)
		mat.set_shader_parameter("mode", 1.0)
		mat.set_shader_parameter("source", Vector2(large * 0.5, arriere))
		mat.set_shader_parameter("evasement", EVASEMENT)
	add_child(rect, false, Node.INTERNAL_MODE_FRONT)
	mat.set_shader_parameter("taille", rect.size)
	mat.set_shader_parameter("hauteur", taille_ouv)
	mat.set_shader_parameter("longueur", long)
	mat.set_shader_parameter("intensite", float(_reglage("rai_intensite", 1.0)))
	mat.set_shader_parameter("couleur", _reglage("rai_couleur", Color(1.0, 0.96, 0.88)))
	mat.set_shader_parameter("ouverture", float(_reglage("rai_ouverture", 0.8)))
	mat.set_shader_parameter("vitesse_ondulation", float(_reglage("rai_vitesse_ondulation", 0.6)))
	# un hasard propre à chaque passage (poussières, brume, tracé du liseré)
	var gp := global_position
	mat.set_shader_parameter("graine", fposmod(gp.x * 0.0131 + gp.y * 0.0071, 1.0))
