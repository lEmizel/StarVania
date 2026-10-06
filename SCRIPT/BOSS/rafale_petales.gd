@tool
extends Node2D
## ============================================================================
## RAFALE DE PÉTALES (6 oct. 2026) — attaque de boss. D'un battement d'ailes,
## elle envoie des pétales à l'HORIZONTALE, des deux côtés à la fois, jusqu'aux
## murs (rafale_petales.gdshader). Chaque rafale passe à l'une de deux
## hauteurs, tirée au hasard et ANNONCÉE : BASSE (du sol à `basse_haut`) ou
## HAUTE (de `haute_bas` à `haute_haut`). LA RÉPONSE : sauter la basse, rester
## au sol sous la haute. Elle ne blesse que le héros.
##
## SANS BOSS (`automatique`, coché) : posée dans un niveau, elle enchaîne ses
## salves toute seule tant que le héros est à portée. Dans l'éditeur, deux
## cadres roses montrent les deux hauteurs, de chaque côté, jusqu'où le sol est
## cherché.
## AVEC UN BOSS : il met `automatique` à faux et appelle `lancer()` (`arreter()`
## coupe la salve net, s'il meurt), ou `lancer_seule(haute)` pour une seule
## rafale de la hauteur voulue. Les signaux `rafale_annoncee(n, haute)` et
## `rafale_partie(n, haute)` donnent le rythme (le battement d'ailes tombe sur
## `rafale_partie`).
##
## Une salve = `rafales` rafales, une toutes les `rythme` s. Une rafale :
##   • `annonce` s : la bande où elle va passer s'allume d'un bout à l'autre de
##     l'arène (ses bords en traits de lumière) ;
##   • elle part du nœud et file à `vitesse` px/s des deux côtés, un train de
##     pétales de `longueur` px, jusqu'au premier mur (au plus `portee`) : qui
##     est dans la bande quand le train passe perd `damage` cœur(s) et il est
##     emporté dans le sens du vent — une seule fois par rafale.
## LE TIRAGE : haute ou basse au hasard (`part_hautes`), jamais plus de
## `suite_max` fois la même de suite.
## Le sol est celui qui est sous le nœud (couches 1 et 2, cherché jusqu'à
## `chute` px) : les rafales le suivent à plat, comme dans une arène.
## La salve reste OÙ ELLE A ÉTÉ LANCÉE : le temps qu'elle dure, le nœud ne suit
## plus les déplacements de son parent ; à la fin il reprend sa place chez lui.
##
## POUR LA JUGER : ouvrir la scène et faire F6 (les salves s'enchaînent ; un
## repère de la taille du héros est posé au sol).
## L'allure (pétales, couleurs, paillettes, halo) se règle sur le matériau du
## nœud Petales.
## ============================================================================

signal finie
## une rafale s'annonce (sa bande s'allume) ; puis elle part
signal rafale_annoncee(numero: int, haute: bool)
signal rafale_partie(numero: int, haute: bool)

## nombre de rafales visibles à la fois, au plus (le shader en prend autant)
const MAX_VUES := 4
## les dernières traînées s'éteignent en … s
const DUREE_TRACE := 0.5
## en automatique, le héros est « à portée » jusqu'à … px au-dessus du sol
const PORTEE_HAUT := 900.0
## demi-largeur du corps du héros comparée au train de pétales (px)
const DEMI_SONDE := 20.0

## sans boss pour la commander : les salves s'enchaînent toutes seules tant que
## le héros est à portée
@export var automatique := true
## en automatique : le silence entre deux salves (s)
@export var pause := 1.6
@export_group("Les rafales")
## nombre de rafales d'une salve
@export var rafales := 4
## une rafale toutes les … s
@export var rythme := 0.9
## sa bande s'allume … s avant qu'elle parte : court, c'est un test de réflexe
## (le boss qui monte ou descend prévient déjà)
@export var annonce := 0.35
## sa vitesse (px/s) : à 2200, elle traverse la moitié de l'arène en 0,9 s
@export var vitesse := 2200.0
## la longueur du train de pétales (px) : plus il est long, plus le saut doit durer
@export var longueur := 280.0
## jusqu'où elle va de chaque côté, au plus (px) ; le premier mur l'arrête avant
@export var portee := 2600.0
@export_group("Les deux hauteurs")
## la rafale BASSE va du sol jusqu'à … px de haut (on la saute)
@export var basse_haut := 90.0
## la rafale HAUTE va de … px à … px au-dessus du sol (le héros debout, 126 px,
## reste dessous)
@export var haute_bas := 170.0
@export var haute_haut := 430.0
## la part des rafales hautes
@export_range(0.0, 1.0) var part_hautes := 0.5
## jamais plus de … fois la même hauteur de suite
@export var suite_max := 2
@export_group("Réglages fins")
## jusqu'où l'on cherche le sol sous le nœud (px)
@export var chute := 1600.0
## ce qui blesse est rogné de … px du côté où le héros passe (le haut de la
## basse, le bas de la haute) : les derniers pétales pardonnent
@export var indulgence := 20.0
@export_group("Dégâts")
@export var damage := 1
@export_group("")
## lancée seule (F6) : les salves s'enchaînent
@export var demo_boucle := true

@onready var _rect: ColorRect = $Petales

var _t := 0.0
var _active := false
var _graine := 0
var _sol := 300.0                         # la hauteur du sol sous le nœud (repère du nœud)
var _portee_g := 2600.0                   # jusqu'où va la rafale, à gauche et à droite
var _portee_d := 2600.0
var _hautes := PackedByteArray()          # par rafale : 1 = haute, 0 = basse
var _annoncees := PackedByteArray()
var _parties := PackedByteArray()
var _touche := PackedByteArray()          # par rafale : elle a déjà pris son cœur
var _ancre := Vector2.ZERO                # sa place chez son parent, le temps d'une salve
var _detache := false
var _demo := false
var _attente := 0.0


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_rect.visible = false
	_demo = demo_boucle and get_parent() == get_tree().root
	if _demo:
		var ecran := get_viewport_rect().size
		position = Vector2(ecran.x * 0.5, ecran.y * 0.3)
		_poser_la_demo()
		lancer()


## une salve, là où est le nœud : `rafales` rafales, hautes ou basses au hasard
func lancer() -> void:
	var hauteurs := PackedByteArray()
	var suite := 0
	for k in maxi(rafales, 1):
		var haute := 1 if randf() < part_hautes else 0
		if k > 0 and haute == hauteurs[k - 1]:
			suite += 1
			if suite >= maxi(suite_max, 1):
				haute = 1 - haute
				suite = 0
		else:
			suite = 0
		hauteurs.append(haute)
	_lancer_salve(hauteurs)


## une seule rafale, haute ou basse, là où est le nœud (un boss qui la combine à
## une autre attaque)
func lancer_seule(haute: bool) -> void:
	var hauteurs := PackedByteArray()
	hauteurs.append(1 if haute else 0)
	_lancer_salve(hauteurs)


func _lancer_salve(hauteurs: PackedByteArray) -> void:
	_graine = randi() % 1000
	_t = 0.0
	# la salve reste où elle est lancée, même si le parent bouge ensuite
	_rattacher()
	if get_parent() is Node2D:
		var ici := global_position
		_ancre = position
		_detache = true
		top_level = true
		global_position = ici
	_sol = _sol_sous()
	_portee_g = _mur_vers(-1.0)
	_portee_d = _mur_vers(1.0)
	_hautes = hauteurs
	_annoncees = PackedByteArray()
	_annoncees.resize(_hautes.size())
	_parties = PackedByteArray()
	_parties.resize(_hautes.size())
	_touche = PackedByteArray()
	_touche.resize(_hautes.size())
	# le rectangle : d'un mur à l'autre, du dessus de la rafale haute au sol
	_rect.position = Vector2(-_portee_g - 40.0, _sol - haute_haut - 90.0)
	_rect.size = Vector2(_portee_g + _portee_d + 80.0, haute_haut + 90.0 + 60.0)
	_active = true
	_rect.visible = true
	_appliquer()


func en_cours() -> bool:
	return _active


## la salve s'arrête net (le boss meurt) : plus de pétales, plus de dégâts, et le
## signal `finie` ne part pas
func arreter() -> void:
	if not _active:
		return
	_active = false
	_rect.visible = false
	_rattacher()


## le nœud reprend sa place chez son parent
func _rattacher() -> void:
	if _detache:
		_detache = false
		top_level = false
		position = _ancre


## l'heure où la rafale n°`k` part, et celle où sa queue a fini de passer
func _depart(k: int) -> float:
	return k * rythme + annonce


func _fin(k: int) -> float:
	return _depart(k) + (maxf(_portee_g, _portee_d) + longueur) / maxf(vitesse, 1.0)


## le héros est-il assez près pour que les rafales partent ?
func _heros_a_portee() -> bool:
	for joueur in get_tree().get_nodes_in_group("Player"):
		if joueur is Node2D:
			var p := to_local((joueur as Node2D).global_position)
			if absf(p.x) <= portee and p.y >= -PORTEE_HAUT and p.y <= chute + 200.0:
				return true
	return false


## la hauteur du premier sol sous le nœud (repère du nœud) ; sans sol : `chute`
func _sol_sous() -> float:
	if _demo:
		return get_viewport_rect().size.y * 0.86 - position.y
	var depuis := global_position
	var jusque := depuis + Vector2(0.0, chute)
	var exclus: Array[RID] = []
	for essai in 6:
		var rayon := PhysicsRayQueryParameters2D.create(depuis, jusque, 0b11)
		rayon.exclude = exclus
		var touche := get_world_2d().direct_space_state.intersect_ray(rayon)
		if touche.is_empty():
			break
		if touche["collider"] is CharacterBody2D:
			exclus.append(touche["rid"])
			continue
		return (touche["position"] as Vector2).y - global_position.y
	return chute


## la distance du premier mur du côté `sens` (−1 : à gauche, 1 : à droite),
## cherché à mi-hauteur de héros au-dessus du sol (couche 2 : les décors) ; sans
## mur : `portee`
func _mur_vers(sens: float) -> float:
	if _demo:
		return minf(portee, get_viewport_rect().size.x * 0.5 - 40.0)
	var depuis := global_position + Vector2(0.0, _sol - 60.0)
	var rayon := PhysicsRayQueryParameters2D.create(depuis, depuis + Vector2(sens * portee, 0.0), 2)
	var touche := get_world_2d().direct_space_state.intersect_ray(rayon)
	if touche.is_empty():
		return portee
	return absf((touche["position"] as Vector2).x - depuis.x)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not _active:
		return
	_t += delta
	var fini := true
	for k in _hautes.size():
		var tau := _t - k * rythme
		if tau < 0.0:
			fini = false
			break
		if _annoncees[k] == 0:
			_annoncees[k] = 1
			rafale_annoncee.emit(k, _hautes[k] == 1)
		if tau < annonce:
			fini = false
			continue
		if _parties[k] == 0:
			_parties[k] = 1
			rafale_partie.emit(k, _hautes[k] == 1)
		if _t < _fin(k):
			fini = false
			if not _demo and _touche[k] == 0:
				_blesser(k, _t - _depart(k))
		elif _t < _fin(k) + DUREE_TRACE:
			fini = false
	if fini:
		_active = false
		_rect.visible = false
		_rattacher()
		finie.emit()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		queue_redraw()       # le repère suit les réglages
		return
	if _active:
		_appliquer()
	elif _demo or (automatique and _heros_a_portee()):
		# seule : une salve, un silence, la suivante
		_attente += delta
		if _attente >= pause:
			_attente = 0.0
			lancer()


## dans l'éditeur seulement, et en automatique (commandée par un boss, c'est lui
## qui la place) : d'où partent les rafales, et les deux hauteurs de chaque côté,
## à `chute` px sous le nœud faute de connaître le sol
func _draw() -> void:
	if Engine.is_editor_hint():
		if not automatique:
			return
		var rose := Color(1.0, 0.5, 0.8)
		draw_line(Vector2(0.0, 0.0), Vector2(0.0, chute), Color(rose, 0.8), 3.0)
		draw_rect(Rect2(-portee, chute - basse_haut, 2.0 * portee, basse_haut), Color(rose, 0.5), false, 2.0)
		draw_rect(Rect2(-portee, chute - haute_haut, 2.0 * portee, haute_haut - haute_bas), Color(rose, 0.5), false, 2.0)
		return
	if not _demo:
		return
	# la démo : un fond, un sol, un repère de la taille du héros
	var ecran := get_viewport_rect().size
	var o := -position
	draw_rect(Rect2(o, ecran), Color(0.16, 0.2, 0.36))
	draw_rect(Rect2(o + Vector2(0.0, ecran.y * 0.86), Vector2(ecran.x, ecran.y * 0.14)), Color(0.09, 0.11, 0.22))
	draw_rect(Rect2(Vector2(ecran.x * 0.22 - 23.0, ecran.y * 0.86 - 126.0) + o, Vector2(46.0, 126.0)), Color(0.9, 0.9, 0.96))


## (la démo dessine son fond dans `_draw` : il faut le redessiner une fois placée)
func _poser_la_demo() -> void:
	queue_redraw()


## qui est dans la bande de la rafale n°`k` quand son train passe perd un cœur
## et il est emporté dans le sens du vent ; une seule fois par rafale
func _blesser(k: int, tau: float) -> void:
	var front := vitesse * tau
	var haute := _hautes[k] == 1
	# la bande qui blesse, en px au-dessus du sol
	var bas := haute_bas + indulgence if haute else 0.0
	var haut := haute_haut if haute else basse_haut - indulgence
	if haut - bas < 4.0:
		return
	for joueur in get_tree().get_nodes_in_group("Player"):
		if not (joueur is Node2D) or not joueur.has_method("apply_environment_damage"):
			continue
		var p := to_local((joueur as Node2D).global_position)
		var d := absf(p.x)
		var limite := _portee_g if p.x < 0.0 else _portee_d
		# le train : du front à sa queue, arrêté par le mur
		if d - DEMI_SONDE > minf(front, limite) or d + DEMI_SONDE < front - longueur:
			continue
		if not _corps_dans(joueur, p.x, bas, haut):
			continue
		var sens := signf(p.x)
		if sens == 0.0:
			sens = 1.0 if randf() < 0.5 else -1.0
		if joueur.apply_environment_damage(damage, Vector2(sens, -0.3).normalized()):
			_touche[k] = 1
		return


## le corps de `joueur` touche-t-il la bande, de `bas` à `haut` px au-dessus du
## sol, à l'abscisse `x` (repère du nœud) ?
func _corps_dans(joueur: Node, x: float, bas: float, haut: float) -> bool:
	var forme := RectangleShape2D.new()
	forme.size = Vector2(DEMI_SONDE * 2.0, haut - bas)
	var requete := PhysicsShapeQueryParameters2D.new()
	requete.shape = forme
	requete.transform = Transform2D(0.0, global_position + Vector2(x, _sol - (bas + haut) * 0.5))
	requete.collision_mask = 0b1011          # joueur et monstres, comme les pièges
	requete.collide_with_areas = false
	for resultat in get_world_2d().direct_space_state.intersect_shape(requete, 16):
		if resultat["collider"] == joueur:
			return true
	return false


func _appliquer() -> void:
	var mat := _rect.material as ShaderMaterial
	if mat == null:
		return
	# les rafales en route : de leur annonce à la fin de leurs traînées
	var vues: Array[int] = []
	for k in _hautes.size():
		if _t >= k * rythme and _t < _fin(k) + DUREE_TRACE:
			vues.append(k)
	while vues.size() > MAX_VUES:
		vues.pop_front()
	var departs := PackedFloat32Array()
	var hautes := PackedFloat32Array()
	var graines := PackedFloat32Array()
	departs.resize(MAX_VUES)
	hautes.resize(MAX_VUES)
	graines.resize(MAX_VUES)
	for i in vues.size():
		departs[i] = _depart(vues[i])
		hautes[i] = float(_hautes[vues[i]])
		graines[i] = float(_graine + vues[i] * 17)
	mat.set_shader_parameter("taille", _rect.size)
	mat.set_shader_parameter("origine", _rect.position)
	mat.set_shader_parameter("sol", _sol)
	mat.set_shader_parameter("portee_g", _portee_g)
	mat.set_shader_parameter("portee_d", _portee_d)
	mat.set_shader_parameter("temps", _t)
	mat.set_shader_parameter("annonce", annonce)
	mat.set_shader_parameter("vitesse", vitesse)
	mat.set_shader_parameter("longueur", longueur)
	mat.set_shader_parameter("basse_haut", basse_haut)
	mat.set_shader_parameter("haute_bas", haute_bas)
	mat.set_shader_parameter("haute_haut", haute_haut)
	mat.set_shader_parameter("nb", vues.size())
	mat.set_shader_parameter("depart", departs)
	mat.set_shader_parameter("haute", hautes)
	mat.set_shader_parameter("graines", graines)
