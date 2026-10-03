extends CharacterBody2D
## ============================================================================
## ROUE À POINTES (2 oct. 2026, piège choisi par Kaoru : « la roue à pointes est
## chouette », puis « une roue seule, qui tient par elle-même, et quand elle nous
## voit elle nous fonce dessus ; elle ne revient que si on meurt »).
##
## DEUX FAÇONS D'ÊTRE (`comportement`) ; en AUTO (par défaut), c'est l'endroit
## où on la pose qui décide : sur un ÎLOT dont elle peut faire le tour sans rien
## heurter, elle TOURNE AUTOUR ; sur le sol d'un niveau, elle FONCE.
##
## FONCER — posée au sol, elle GUETTE (elle se balance doucement). Elle ne part
## que si TOUT est vrai (Kaoru : « qu'elle ne se déclenche pas pour rien ») :
##   • elle est ENTIÈREMENT À L'ÉCRAN (on la voit avant qu'elle parte) ;
##   • on est AU SOL, sur LE MÊME SOL qu'elle : un sol continu de la roue
##     jusqu'à nos pieds (pentes douces permises ; ni trou, ni marche, ni
##     mur) — sur une plateforme au-dessus d'elle, elle ne bouge pas ;
##   • rien ne nous cache d'elle, et on est à moins de `distance_vue`.
## Alors elle PATINE sur place (`duree_elan` : elle tourne de plus en plus vite,
## étincelles, tremblement), puis FONCE vers nous en accélérant, blesse le
## joueur (`damage`) et écrase les monstres sur son passage, et se BRISE contre
## le premier mur. On la SAUTE (ou on la traverse en roulade). Ses pointes
## blessent aussi à l'arrêt. Une roue ne touche qu'UNE fois chacun (piqué à
## l'arrêt, on n'est pas fauché une seconde fois quand elle part).
## Brisée, elle NE REVIENT QUE SI ON MEURT (registre Player.roues_brisees, vidé à
## la réapparition) : sortir du tableau et y revenir ne la ramène pas.
##
## TOURNER AUTOUR (demande de Kaoru : « sur une plateforme îlot, petite, avec du
## vide, elle devrait pouvoir tourner indéfiniment autour ») — elle fait le TOUR
## de l'îlot sans fin : dessus, sur le flanc, DESSOUS, sur l'autre flanc, à
## `vitesse_tour`, dans le sens `sens_horaire`. Elle ne guette pas, ne fonce
## pas, ne se brise jamais. Ses pointes blessent le joueur à chaque passage
## (repoussé loin d'elle, comme par une scie) et écrasent les monstres.
## L'îlot, c'est TOUTES les pièces de collision qui se touchent (souvent plusieurs
## blocs de graybox bord à bord : celui de sc_10 en a quatre) ; son chemin est
## calculé une fois pour toutes depuis leur contour réuni : écarté de son rayon,
## arrondi autour des coins saillants ; si l'îlot bouge, elle suit.
##
## Son ÉCHELLE (`scale` du nœud, Kaoru l'agrandit) est prise en compte partout.
## L'origine du nœud est le SOL sous la roue (on la pose comme le pilon) ; posée
## un peu haut, elle tombe d'elle-même sur le sol.
## Dessin : LE DESSIN DE KAORU (MEDIA/INTERACTIBLE/roue.png, 3 oct. 2026),
## tourné, flouté et fendu en quatre par SCRIPT/SHADER/roue_pointes.gdshader
## (nœud Visuel). En jeu, il reçoit une copie à mipmaps du dessin (faite une
## fois pour toutes les roues) : réduit 8 fois et plus, le dessin brut
## scintillerait en tournant.
##
## POUR LA JUGER : ouvrir la scène et faire F6 (elle fonce en boucle sur un
## sol et contre un mur de démonstration) ; roue_pointes_ilot.tscn (réglée sur
## « tourner autour ») : F6 = elle fait le tour d'un îlot.
## ============================================================================

enum Etat { GUETTE, ELAN, ROULE, BRISEE }
enum Comportement { FONCER, TOURNER_AUTOUR, AUTO }

const DESSIN := preload("res://MEDIA/INTERACTIBLE/roue.png")
const RAYON := 32.0               # le disque de son dessin (px, à l'échelle 1 ; ses pointes vont jusqu'à 43)
const ENFONCE := 6.0              # le corps roule sur un cercle de RAYON + ENFONCE : les pointes mordent le sol
const CENTRE := Vector2(0.0, -(RAYON + ENFONCE))   # le centre de la roue, au-dessus de l'origine (le sol), à l'échelle 1
const PORTEE_POINTES := RAYON * 1.345              # la roue, pointes comprises (comme BOUT_POINTES du shader)
const DUREE_ECLAT := 0.9          # elle vole en éclats pendant… (s), comme DUREE du shader
const PAS_SONDE := 16.0           # le sol est sondé tous les… (px) entre elle et nous
const ECART_SONDE := 14.0         # … et peut monter ou descendre d'autant d'une sonde à l'autre (pente douce)
const REPIT_TOURNE := 1.0         # celle qui tourne épargne celui qu'elle vient de piquer pendant… (s)
const TAILLE_MAX_ILOT := 2400.0   # au-delà (largeur ou hauteur), ce n'est plus un îlot mais le sol du niveau
const PIECES_MAX := 24            # … ou au-delà de tant de pièces de collision réunies

## AUTO : sur un îlot dont elle peut faire le tour, elle tourne autour ; sinon
## elle fonce. FONCER : elle guette et fonce quand elle nous voit. TOURNER
## AUTOUR : posée sur un îlot, elle en fait le tour sans fin
@export var comportement: Comportement = Comportement.AUTO
## Cœurs perdus par le joueur touché
@export var damage: int = 1
## Dégâts aux monstres écrasés (999999 = mort en un coup, comme les pièges)
@export var degats_monstres: int = 999999
## lancée seule (F6) : elle fonce en boucle
@export var demo_boucle := true

@export_group("Vue")
## elle nous voit à moins de… (px, de côté), si on est sur son sol et qu'elle est à l'écran
@export var distance_vue := 700.0
## elle patine sur place pendant… avant de foncer (s) : le temps de réagir
@export var duree_elan := 0.5

@export_group("Course")
## sa vitesse de croisière (px/s) — le héros court à 700
@export var vitesse_max := 650.0
## elle prend sa vitesse à… (px/s²)
@export var acceleration := 1300.0
## au-delà de cette distance, elle se brise d'elle-même (px)
@export var portee_max := 3000.0

@export_group("Tourner autour")
## sa vitesse le long du bord de l'îlot (px/s)
@export var vitesse_tour := 300.0
## dans le sens des aiguilles d'une montre (sur le dessus de l'îlot : vers la droite)
@export var sens_horaire := true

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")

# son dessin prêt pour le jeu, commun à toutes les roues (voir _dessin_jeu)
static var _dessin_filtre: Texture2D = null

@onready var _visuel: ColorRect = $Visuel
@onready var _zone: Area2D = $Zone

var _etat := Etat.GUETTE
var _t := 0.0
var _temps := 0.0
var _sens := 1.0
var _angle := 0.0
var _flou := 0.0
var _balance := 0.0
var _etincelles := 0.0
var _parcouru := 0.0
var _touches: Array = []
var _derniers_coups := {}         # celle qui tourne : corps → heure de sa dernière piqûre
var _depart := Vector2.ZERO
var _cle := ""
var _demo := false
var _k := 1.0                     # son échelle (le `scale` du nœud)
var _decide := false              # le comportement est-il fixé ? (AUTO attend d'être posée)
var _tourne := false              # … et c'est : faire le tour (sinon foncer)
# « tourner autour » : l'îlot, le chemin de son centre autour de lui
var _ile: CollisionObject2D = null          # la pièce sous la roue (elle suit ses déplacements)
var _corps_ile: Array = []                  # toutes les pièces réunies
var _ile_xform0 := Transform2D.IDENTITY     # la place de la pièce quand le chemin a été calculé
var _morceaux: Array = []                   # côtés décalés et arcs autour des coins, dans l'ordre
var _longueur := 0.0
var _r_chemin := RAYON + ENFONCE            # l'écart du chemin au bord (à son échelle)
var _s := 0.0                               # où elle en est sur le chemin (px)
var _appui := Vector2.DOWN                  # d'où vient le sol, depuis son centre


func _ready() -> void:
	_demo = demo_boucle and get_parent() == get_tree().root
	_k = maxf(absf(global_scale.x), 0.01)
	if not _demo and comportement != Comportement.TOURNER_AUTOUR:
		# brisée plus tôt dans cette vie : elle ne revient qu'à la mort du joueur
		_cle = _cle_persistante()
		if Player.roues_brisees.has(_cle):
			set_physics_process(false)
			set_process(false)
			visible = false
			queue_free()
			return
	collision_layer = 0
	collision_mask = 6                 # sols et murs, comme les monstres
	floor_snap_length = 14.0
	_zone.collision_layer = 0
	_zone.collision_mask = 1 | 8       # le joueur et les monstres
	if _demo:
		var ilot := comportement == Comportement.TOURNER_AUTOUR
		position = get_viewport_rect().size * (Vector2(0.5, 0.45) if ilot else Vector2(0.2, 0.8))
	_depart = global_position
	if _demo:
		_poser_decor_de_demo.call_deferred()
	var mat := _visuel.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("rayon_disque", RAYON)
		mat.set_shader_parameter("sol", RAYON + ENFONCE)
		var dessin := _dessin_jeu()
		if dessin != null:
			mat.set_shader_parameter("dessin", dessin)
			mat.set_shader_parameter("dessin_premultiplie", true)
	_appliquer()


## SON DESSIN prêt pour le jeu : une copie réduite (1024 px au plus, par
## moitiés : chaque pixel = la moyenne de quatre), aux couleurs prémultipliées
## (pas de liseré sombre au bord des pointes), avec ses mipmaps (sans elles,
## affiché 8 fois plus petit et plus, ses fines volutes scintilleraient quand
## la roue tourne). Faite UNE fois pour toutes les roues de la partie, depuis
## l'image importée : un nouveau dessin est pris tel quel. Null si l'image
## n'est pas lisible (serveur de rendu factice) : la scène garde le dessin brut.
static func _dessin_jeu() -> Texture2D:
	if _dessin_filtre == null:
		var img := DESSIN.get_image()
		if img == null or img.is_empty():
			return null
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		while img.get_width() > 1024 or img.get_height() > 1024:
			img.resize(maxi(img.get_width() / 2, 1), maxi(img.get_height() / 2, 1), Image.INTERPOLATE_BILINEAR)
		img.premultiply_alpha()
		img.generate_mipmaps()
		_dessin_filtre = ImageTexture.create_from_image(img)
	return _dessin_filtre


## identité stable (comme les cœurs) : scène du niveau + position de départ arrondie
func _cle_persistante() -> String:
	var niveau: String = owner.scene_file_path if owner != null else ""
	if niveau == "" and get_tree().current_scene != null:
		niveau = get_tree().current_scene.scene_file_path
	return "%s|%d,%d" % [niveau, roundi(global_position.x), roundi(global_position.y)]


func _physics_process(delta: float) -> void:
	_t += delta
	var angle_avant := _angle
	if not _decide:
		_decider()
	if _tourne:
		_tourner(delta)
	else:
		_foncer(delta)
	_flou = clampf(_angle - angle_avant, -0.5, 0.5)
	var vise := 0.0
	if _tourne:
		if not _morceaux.is_empty():
			vise = clampf(vitesse_tour / maxf(vitesse_max, 1.0), 0.35, 1.0)
	elif _etat == Etat.ELAN:
		vise = clampf(_t / maxf(duree_elan, 0.01), 0.0, 1.0)
	elif _etat == Etat.ROULE and is_on_floor():
		vise = 1.0
	_etincelles = move_toward(_etincelles, vise, delta * 6.0)
	if _etat != Etat.BRISEE:
		_blesser()


## fixe le comportement. AUTO attend d'être posée, puis regarde sur quoi : un
## îlot dont elle peut faire le tour sans rien heurter → elle tourne autour ;
## un sol trop grand, ou un « îlot » collé au sol ou à un mur → elle fonce
func _decider() -> void:
	match comportement:
		Comportement.FONCER:
			_tourne = false
		Comportement.TOURNER_AUTOUR:
			_tourne = true
		_:
			var trouve := _trouver_ile()
			if trouve == 0:
				return                                   # rien sous elle encore : elle tombe, on redemandera
			_tourne = trouve == 1 and _tour_libre()
			if not _tourne:
				_morceaux.clear()
	_decide = true
	if _tourne:
		_passer(Etat.GUETTE)
		_balance = 0.0
		_sens = 1.0 if sens_horaire else -1.0
		# elle passe aussi SOUS l'îlot : ses étincelles partent vers le bas
		_visuel.position = CENTRE - Vector2(200.0, 200.0)
		_visuel.size = Vector2(400.0, 400.0)


## le comportement d'origine : elle guette, patine, fonce, se brise
func _foncer(delta: float) -> void:
	match _etat:
		Etat.GUETTE:
			_tomber(delta)
			_balance = sin(_temps * 2.6) * 0.06          # elle se balance : elle attend
			if _decide and ((_demo and _t > 1.2) or (not _demo and _voit_le_joueur())):
				_passer(Etat.ELAN)
		Etat.ELAN:
			_tomber(delta)
			_balance = move_toward(_balance, 0.0, delta * 0.5)
			# elle patine sur place, de plus en plus vite, jusqu'à sa vitesse de course
			var k := clampf(_t / maxf(duree_elan, 0.01), 0.0, 1.0)
			_angle += _sens * k * vitesse_max / _r_roule() * delta
			if _t >= duree_elan:
				_passer(Etat.ROULE)
		Etat.ROULE:
			_rouler(delta)
		Etat.BRISEE:
			if _t >= DUREE_ECLAT:
				if not _demo:
					queue_free()
				elif _t >= DUREE_ECLAT + 1.2:
					_reprendre()


func _process(delta: float) -> void:
	_temps += delta
	_appliquer()


func _passer(etat: Etat) -> void:
	_etat = etat
	_t = 0.0


## son centre, dans le monde (à son échelle)
func _centre_monde() -> Vector2:
	return global_position + CENTRE * _k


## le rayon sur lequel elle roule (à son échelle)
func _r_roule() -> float:
	return (RAYON + ENFONCE) * _k


func _tomber(delta: float) -> void:
	velocity.x = 0.0
	velocity.y += gravity * delta
	move_and_slide()


func _rouler(delta: float) -> void:
	velocity.x = move_toward(velocity.x, _sens * vitesse_max, acceleration * delta)
	velocity.y += gravity * delta
	move_and_slide()
	# elle tourne déjà à pleine vitesse (elle patinait) : la course la rattrape
	_angle += _sens * vitesse_max / _r_roule() * delta
	_parcouru += absf(velocity.x) * delta
	var contre_un_mur := is_on_wall() and get_wall_normal().x * _sens < -0.5
	if contre_un_mur or _parcouru > portee_max or global_position.y > _depart.y + 2500.0:
		_briser()


# ---------------------------------------------------------------------------
# TOURNER AUTOUR D'UN ÎLOT
# ---------------------------------------------------------------------------

func _tourner(delta: float) -> void:
	if _morceaux.is_empty() or not is_instance_valid(_ile):
		# pas encore d'îlot (posée un peu haut, ou F6 dont le décor arrive) : on
		# le cherche sous elle, sinon elle tombe dessus
		_morceaux.clear()
		var trouve := _trouver_ile()
		if trouve == 2:
			# demandée « tourner autour » sur le sol d'un niveau : pas d'îlot ici
			push_warning("Roue à pointes %s : pas d'îlot dont faire le tour ici (sol trop grand), elle fonce" % name)
			_tourne = false
			return
		if trouve == 0:
			_tomber(delta)
			return
	_s = fposmod(_s + _sens * vitesse_tour * delta, _longueur)
	var p: Array = _point_du_tour(_s)
	# l'îlot a pu bouger depuis le calcul du chemin : elle suit
	var deplace := _ile.global_transform * _ile_xform0.affine_inverse()
	global_position = deplace * (p[0] as Vector2) - CENTRE * _k
	_appui = -(deplace.basis_xform(p[1] as Vector2)).normalized()
	# elle roule sur le bord (autour d'un coin, elle pivote : même compte)
	_angle += _sens * vitesse_tour * delta / _r_chemin


## l'îlot sous la roue, et le chemin de son centre autour de lui.
## 0 = rien (elle est en l'air), 1 = un îlot (chemin prêt), 2 = un sol trop
## grand pour en faire le tour
func _trouver_ile() -> int:
	var espace := get_world_2d().direct_space_state
	var forme := CircleShape2D.new()
	var requete := PhysicsShapeQueryParameters2D.new()
	requete.shape = forme
	requete.collision_mask = collision_mask
	# d'abord la pièce juste sous elle (son origine est au sol), sinon autour d'elle
	for essai in 2:
		forme.radius = (8.0 if essai == 0 else RAYON + ENFONCE + 16.0) * _k
		requete.transform = Transform2D(0.0, global_position if essai == 0 else _centre_monde())
		for resultat in espace.intersect_shape(requete, 8):
			var corps := resultat["collider"] as CollisionObject2D
			if corps == null or corps is CharacterBody2D:
				continue
			var assemble := _assembler_ile(corps, resultat["shape"])
			var contour: PackedVector2Array = assemble[0]
			if contour.size() < 3:
				return 2
			_construire_tour(contour)
			if _morceaux.is_empty():
				return 2
			_ile = corps
			_corps_ile = assemble[1]
			_ile_xform0 = corps.global_transform
			_s = _abscisse_la_plus_proche(_centre_monde())
			return 1
	return 0


## L'îlot ENTIER : souvent plusieurs pièces de collision posées bord à bord (celui
## de sc_10 : deux blocs 400 × 100 côte à côte, un troisième dessous et une
## pente). On part de la pièce sous la roue et on y ajoute, de proche en proche,
## tout ce qui la touche (chaque pièce gonflée de 2 px : bord à bord, ou à 1 px
## près comme les pentes de graybox, elles se rejoignent). Renvoie [contour,
## pièces] ; contour vide = trop grand pour un îlot.
func _assembler_ile(depart_corps: CollisionObject2D, depart_indice: int) -> Array:
	var corps: Array = [depart_corps]
	var union := _gonfler(_contour(depart_corps, depart_indice), 2.0)
	if union.size() < 3:
		return [PackedVector2Array(), corps]
	var vus := {_proprio(depart_corps, depart_indice): true}
	var espace := get_world_2d().direct_space_state
	var change := true
	while change:
		change = false
		var boite := _boite(union).grow(4.0)
		if boite.size.x > TAILLE_MAX_ILOT or boite.size.y > TAILLE_MAX_ILOT or vus.size() > PIECES_MAX:
			return [PackedVector2Array(), corps]
		var forme := RectangleShape2D.new()
		forme.size = boite.size
		var requete := PhysicsShapeQueryParameters2D.new()
		requete.shape = forme
		requete.transform = Transform2D(0.0, boite.get_center())
		requete.collision_mask = collision_mask
		for resultat in espace.intersect_shape(requete, 64):
			var c := resultat["collider"] as CollisionObject2D
			if c == null or c is CharacterBody2D:
				continue
			var proprio := _proprio(c, resultat["shape"])
			if vus.has(proprio):
				continue
			var piece := _gonfler(_contour(c, resultat["shape"]), 2.0)
			if piece.size() < 3 or Geometry2D.intersect_polygons(piece, union).is_empty():
				continue
			vus[proprio] = true
			if not corps.has(c):
				corps.append(c)
			union = _le_plus_grand(Geometry2D.merge_polygons(union, piece))
			change = true
	return [_simplifier(_gonfler(union, -2.0)), corps]


## le nœud de collision (CollisionShape2D, CollisionPolygon2D) d'une forme touchée
func _proprio(corps: CollisionObject2D, indice: int) -> Object:
	return corps.shape_owner_get_owner(corps.shape_find_owner(indice))


## AUTO : elle peut faire tout le tour sans rien heurter d'autre que l'îlot (sinon
## il est posé sur le sol ou collé à un mur : elle y foncerait)
func _tour_libre() -> bool:
	var exclus: Array[RID] = []
	for c in _corps_ile:
		exclus.append((c as CollisionObject2D).get_rid())
	var forme := CircleShape2D.new()
	forme.radius = RAYON * _k
	var requete := PhysicsShapeQueryParameters2D.new()
	requete.shape = forme
	requete.collision_mask = collision_mask
	requete.exclude = exclus
	var espace := get_world_2d().direct_space_state
	var n := int(_longueur / 24.0) + 1
	for i in n:
		requete.transform = Transform2D(0.0, _point_du_tour(_longueur * i / n)[0])
		if not espace.intersect_shape(requete, 1).is_empty():
			return false
	return true


## le contour de la forme touchée, dans le monde (rectangle, polygone, cercle)
func _contour(corps: CollisionObject2D, indice: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	var noeud := _proprio(corps, indice)
	if noeud is CollisionPolygon2D:
		var xf := (noeud as Node2D).global_transform
		for p in (noeud as CollisionPolygon2D).polygon:
			points.append(xf * p)
	elif noeud is CollisionShape2D:
		var xf := (noeud as Node2D).global_transform
		var forme := (noeud as CollisionShape2D).shape
		if forme is RectangleShape2D:
			var h := (forme as RectangleShape2D).size * 0.5
			for p in [Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y)]:
				points.append(xf * p)
		elif forme is ConvexPolygonShape2D:
			for p in (forme as ConvexPolygonShape2D).points:
				points.append(xf * p)
		elif forme is CircleShape2D:
			for i in 24:
				points.append(xf * (Vector2.RIGHT.rotated(TAU * i / 24.0) * (forme as CircleShape2D).radius))
	return points


## un polygone gonflé (d > 0) ou dégonflé (d < 0), coins vifs gardés
func _gonfler(points: PackedVector2Array, d: float) -> PackedVector2Array:
	if points.size() < 3:
		return PackedVector2Array()
	return _le_plus_grand(Geometry2D.offset_polygon(points, d, Geometry2D.JOIN_MITER))


## le contour extérieur parmi plusieurs (les trous sont plus petits)
func _le_plus_grand(polygones: Array) -> PackedVector2Array:
	var meilleur := PackedVector2Array()
	var aire_max := -1.0
	for poly in polygones:
		var aire := 0.0
		for i in poly.size():
			aire += (poly[i] as Vector2).cross(poly[(i + 1) % poly.size()])
		if absf(aire) > aire_max:
			aire_max = absf(aire)
			meilleur = poly
	return meilleur


func _boite(points: PackedVector2Array) -> Rect2:
	var boite := Rect2(points[0], Vector2.ZERO)
	for p in points:
		boite = boite.expand(p)
	return boite


## sans les points en double ni les points alignés (bords de pièces réunies)
func _simplifier(points: PackedVector2Array) -> PackedVector2Array:
	var nets := PackedVector2Array()
	for p in points:
		if nets.is_empty() or nets[nets.size() - 1].distance_to(p) > 1.0:
			nets.append(p)
	if nets.size() > 1 and nets[0].distance_to(nets[nets.size() - 1]) <= 1.0:
		nets.remove_at(nets.size() - 1)
	var garde := true
	while garde and nets.size() > 3:
		garde = false
		for i in nets.size():
			var a := nets[(i - 1 + nets.size()) % nets.size()]
			var b := nets[i]
			var c := nets[(i + 1) % nets.size()]
			var u := (b - a).normalized()
			var v := (c - b).normalized()
			if absf(u.cross(v)) < 0.01 and u.dot(v) > 0.0:
				nets.remove_at(i)
				garde = true
				break
	return nets


## le chemin de son CENTRE : le contour écarté de son rayon — les côtés décalés
## vers l'extérieur, raccordés par un arc autour de chaque coin saillant et par
## le croisement des côtés à un coin rentrant. Il tourne dans le sens des
## aiguilles d'une montre à l'écran (sur le dessus de l'îlot : vers la droite).
func _construire_tour(points: PackedVector2Array) -> void:
	_morceaux.clear()
	_longueur = 0.0
	_r_chemin = _r_roule()
	var n := points.size()
	# sens des aiguilles d'une montre à l'écran (y vers le bas) = aire signée > 0
	var aire := 0.0
	for i in n:
		aire += points[i].cross(points[(i + 1) % n])
	if aire < 0.0:
		points.reverse()
	var r := _r_chemin
	var normales: Array[Vector2] = []
	for i in n:
		var d := (points[(i + 1) % n] - points[i]).normalized()
		normales.append(Vector2(d.y, -d.x))            # vers l'extérieur
	var saillant: Array[bool] = []
	var onglet: Array[Vector2] = []
	for i in n:
		var n_in := normales[(i - 1 + n) % n]
		var n_out := normales[i]
		var e_in := points[i] - points[(i - 1 + n) % n]
		var e_out := points[(i + 1) % n] - points[i]
		saillant.append(e_in.cross(e_out) >= 0.0)
		onglet.append(points[i] + r * (n_in + n_out) / maxf(1.0 + n_in.dot(n_out), 0.05))
	for i in n:
		var j := (i + 1) % n
		var n_out := normales[i]
		if saillant[i]:
			var n_in := normales[(i - 1 + n) % n]
			var da := maxf(wrapf(n_out.angle() - n_in.angle(), -PI, PI), 0.0)
			if da > 0.0001:
				_morceaux.append({"arc": true, "c": points[i], "a0": n_in.angle(), "da": da, "long": r * da})
		var debut: Vector2 = points[i] + r * n_out if saillant[i] else onglet[i]
		var fin: Vector2 = points[j] + r * n_out if saillant[j] else onglet[j]
		var long := (fin - debut).dot((points[j] - points[i]).normalized())
		if long > 0.0001:
			_morceaux.append({"arc": false, "a": debut, "b": fin, "n": n_out, "long": long})
	for m in _morceaux:
		_longueur += m["long"]
	if _longueur < 1.0:
		_morceaux.clear()


## [position de son centre, direction de l'extérieur] à l'abscisse `s` du chemin
func _point_du_tour(s: float) -> Array:
	for m in _morceaux:
		if s <= m["long"]:
			if m["arc"]:
				var dir := Vector2.RIGHT.rotated(m["a0"] + m["da"] * s / m["long"])
				return [m["c"] + dir * _r_chemin, dir]
			return [(m["a"] as Vector2).lerp(m["b"], s / m["long"]), m["n"]]
		s -= m["long"]
	var dernier: Dictionary = _morceaux[_morceaux.size() - 1]
	if dernier["arc"]:
		var dir := Vector2.RIGHT.rotated(dernier["a0"] + dernier["da"])
		return [dernier["c"] + dir * _r_chemin, dir]
	return [dernier["b"], dernier["n"]]


## où elle commence : le point du chemin le plus proche de son centre
func _abscisse_la_plus_proche(p: Vector2) -> float:
	var meilleur := INF
	var s_meilleur := 0.0
	var s0 := 0.0
	for m in _morceaux:
		var s_local := 0.0
		var q: Vector2
		if m["arc"]:
			var t := clampf(wrapf((p - m["c"]).angle() - m["a0"], -PI, PI), 0.0, m["da"])
			q = m["c"] + Vector2.RIGHT.rotated(m["a0"] + t) * _r_chemin
			s_local = _r_chemin * t
		else:
			var ab: Vector2 = m["b"] - m["a"]
			var k := clampf((p - m["a"]).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
			q = (m["a"] as Vector2).lerp(m["b"], k)
			s_local = k * m["long"]
		if p.distance_to(q) < meilleur:
			meilleur = p.distance_to(q)
			s_meilleur = s0 + s_local
		s0 += m["long"]
	return s_meilleur


# ---------------------------------------------------------------------------
# ELLE NOUS VOIT-ELLE ?
# ---------------------------------------------------------------------------

func _voit_le_joueur() -> bool:
	if not is_on_floor():
		return false
	var j := get_tree().get_first_node_in_group("Player") as CharacterBody2D
	if j == null or Player.hp <= 0 or not j.is_on_floor():
		return false
	var pieds := j.global_position
	var d := pieds - global_position
	# de côté, assez près (la hauteur, c'est le suivi du sol qui en juge : une
	# longue pente est permise, une plateforme au-dessus non)
	if absf(d.x) > distance_vue or absf(d.x) < 1.0 or absf(d.y) > distance_vue:
		return false
	if not _a_l_ecran():
		return false
	var c: Vector2 = j.centre_corps() if j.has_method("centre_corps") else pieds + Vector2(0.0, -60.0)
	if not _a_vue(j, _centre_monde(), c):
		return false
	if not _sol_jusqu_a(pieds):
		return false
	_sens = signf(d.x)
	return true


## entièrement à l'écran, pointes comprises, avec une marge : on la voit avant qu'elle parte
func _a_l_ecran() -> bool:
	var vp := get_viewport()
	var ecran := vp.get_canvas_transform().affine_inverse() * vp.get_visible_rect()
	return ecran.grow(-(PORTEE_POINTES + 24.0) * _k).has_point(_centre_monde())


## rien de solide entre elle et nous (les personnages ne cachent rien)
func _a_vue(corps: PhysicsBody2D, de: Vector2, vers: Vector2) -> bool:
	var exclus: Array[RID] = [corps.get_rid()]
	for essai in 6:
		var rayon_vue := PhysicsRayQueryParameters2D.create(de, vers, 1)
		rayon_vue.exclude = exclus
		var touche := get_world_2d().direct_space_state.intersect_ray(rayon_vue)
		if touche.is_empty():
			return true
		if not (touche["collider"] is CharacterBody2D):
			return false
		exclus.append(touche["rid"])
	return true


## le sol est-il CONTINU de la roue jusqu'à ces pieds ? On le suit pas à pas :
## chaque sonde cherche le sol à ± ECART_SONDE de la précédente (pente douce).
## Rien trouvé = un trou ; une sonde qui part DANS un bloc = une marche ou un
## mur. Au bout, le sol doit être celui des pieds (pas une plateforme au-dessus).
func _sol_jusqu_a(pieds: Vector2) -> bool:
	var espace := get_world_2d().direct_space_state
	var y := global_position.y
	var pas := PAS_SONDE * signf(pieds.x - global_position.x)
	var n := int(absf(pieds.x - global_position.x) / PAS_SONDE)
	for i in range(1, n + 1):
		var x := global_position.x + pas * i
		var sonde := PhysicsRayQueryParameters2D.create(Vector2(x, y - ECART_SONDE), Vector2(x, y + ECART_SONDE), collision_mask)
		sonde.hit_from_inside = true
		var touche := espace.intersect_ray(sonde)
		if touche.is_empty():
			return false
		if (touche["normal"] as Vector2) == Vector2.ZERO:
			return false
		y = (touche["position"] as Vector2).y
	return absf(pieds.y - y) <= ECART_SONDE


# ---------------------------------------------------------------------------
# ELLE BLESSE, ELLE SE BRISE
# ---------------------------------------------------------------------------

func _blesser() -> void:
	for corps in _zone.get_overlapping_bodies():
		if _touches.has(corps):
			continue
		if corps.has_method("apply_environment_damage"):
			# en roulade ou en dash, « pas porté » : on retente tant qu'il est dedans
			var dir: Vector2
			if _tourne:
				# comme une scie : repoussé loin de son centre
				var c: Vector2 = corps.centre_corps() if corps.has_method("centre_corps") else (corps as Node2D).global_position
				dir = c - _centre_monde()
				if dir.length_squared() < 1.0:
					dir = Vector2.UP
			else:
				# renversé dans son sens de course (à l'arrêt : à l'opposé d'elle),
				# un peu vers le haut
				var cote := _sens
				if _etat != Etat.ROULE:
					cote = 1.0 if (corps as Node2D).global_position.x >= global_position.x else -1.0
				dir = Vector2(cote, -0.65)
			# celle qui fonce ne touche qu'une fois. Celle qui tourne pique à
			# chaque passage, mais épargne `REPIT_TOURNE` s celui qu'elle vient de
			# piquer : elle avance dans le sens où elle repousse, et le rattrapait
			# à la fin de son étourdissement (deux cœurs d'un coup, sans recours)
			if _tourne and _temps - float(_derniers_coups.get(corps, -INF)) < REPIT_TOURNE:
				continue
			if corps.apply_environment_damage(damage, dir.normalized()):
				if _tourne:
					_derniers_coups[corps] = _temps
				else:
					_touches.append(corps)
		elif (_etat == Etat.ROULE or _tourne) and corps is BaseAI and corps.hp > 0:
			# les monstres ne se piquent pas à une roue arrêtée : elle les écrase en course
			_touches.append(corps)
			corps.apply_damage(degats_monstres, global_position.x, "roue")


func _briser() -> void:
	_passer(Etat.BRISEE)
	velocity = Vector2.ZERO
	_zone.set_deferred("monitoring", false)
	if not _demo:
		Player.roues_brisees[_cle] = true       # elle ne reviendra qu'à la mort du joueur
	# une petite secousse, seulement si elle se brise près du joueur
	var j := get_tree().get_first_node_in_group("Player") as Node2D
	if j != null and absf(j.global_position.x - global_position.x) < 1100.0 \
			and absf(j.global_position.y - global_position.y) < 700.0:
		var cam := get_tree().get_first_node_in_group("Camera")
		if cam != null and cam.has_method("shake"):
			cam.shake(4.0, 10.0)


## F6 seulement : elle se remet en place pour recommencer
func _reprendre() -> void:
	global_position = _depart
	velocity = Vector2.ZERO
	_parcouru = 0.0
	_touches.clear()
	_zone.monitoring = true
	_passer(Etat.GUETTE)


func _appliquer() -> void:
	var mat := _visuel.material as ShaderMaterial
	if mat == null:
		return
	var eclat := -1.0
	if _etat == Etat.BRISEE:
		eclat = clampf(_t / DUREE_ECLAT, 0.0, 1.0)
	_visuel.visible = eclat < 1.0
	mat.set_shader_parameter("taille", _visuel.size)
	# le balancement la fait rouler un peu sur place (sans glisser)
	mat.set_shader_parameter("centre", CENTRE - _visuel.position + Vector2((RAYON + ENFONCE) * _balance, 0.0))
	mat.set_shader_parameter("angle", _angle + _balance)
	mat.set_shader_parameter("flou", _flou * 0.5)        # un obturateur à 180° : flou, mais les pointes se lisent
	mat.set_shader_parameter("vitesse", _etincelles)
	mat.set_shader_parameter("sens", _sens)
	mat.set_shader_parameter("appui", _appui)
	mat.set_shader_parameter("tremble", 1.0 if _etat == Etat.ELAN and not _tourne else 0.0)
	mat.set_shader_parameter("eclat", eclat)
	mat.set_shader_parameter("temps", _temps)


## F6 : un sol et un mur pour la voir foncer et se briser — ou un îlot dont
## elle fait le tour
func _poser_decor_de_demo() -> void:
	if comportement == Comportement.TOURNER_AUTOUR:
		_bloc_de_demo(_depart - Vector2(180.0, 0.0), Vector2(360.0, 90.0))
		return
	var taille := get_viewport_rect().size
	_bloc_de_demo(Vector2(-taille.x, _depart.y), Vector2(taille.x * 3.0, 60.0))
	_bloc_de_demo(Vector2(_depart.x + taille.x * 0.6, _depart.y - 400.0), Vector2(40.0, 400.0))


func _bloc_de_demo(coin: Vector2, taille: Vector2) -> void:
	var corps := StaticBody2D.new()
	corps.collision_layer = 1 | 2 | 4
	var forme := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = taille
	forme.shape = r
	corps.add_child(forme)
	corps.position = coin + taille * 0.5
	get_parent().add_child(corps)
	var dessin := ColorRect.new()
	dessin.color = Color(0.2, 0.25, 0.33)
	dessin.position = coin
	dessin.size = taille
	dessin.z_index = -1
	get_parent().add_child(dessin)
