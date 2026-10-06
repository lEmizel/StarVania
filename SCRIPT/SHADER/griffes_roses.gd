@tool
extends Node2D
## ============================================================================
## GRIFFES ROSES (5 oct. 2026) — attaque de boss. Elle lève la main, de grandes
## griffes de lumière s'y forment, puis elle les lance en slash : trois
## CROISSANTS emboîtés, un par griffe, filent en DIAGONALE jusqu'au premier mur
## ou au sol (griffes_roses.gdshader). LA RÉPONSE : sortir de la diagonale
## avant qu'ils partent, ou la traverser en roulade. Elle ne blesse que le
## héros.
##
## Le nœud se pose LÀ OÙ EST SA MAIN LEVÉE.
## SANS BOSS (`automatique`, coché) : posé dans un niveau, en l'air, il enchaîne
## ses coups tout seul tant que le héros est à portée. Dans l'éditeur, deux
## traits roses montrent la diagonale de chaque côté (à `angle`), et des traits
## pâles la largeur de ce qui passe.
## AVEC UN BOSS : il met `automatique` à faux et appelle `lancer()` quand elle
## lève la main (`lancer(-1)` ou `lancer(1)` pour imposer le côté). Le signal
## `lancee` part à l'instant où le slash quitte la main, `finie` à la fin.
## Si l'animation du boss montre déjà les griffes à sa main, décocher
## `griffes_a_la_main` : il ne reste que le passage annoncé et le slash.
##
## Un coup :
##   • `charge` s : les griffes poussent à la main et le PASSAGE s'annonce — un
##     voile de lueur large comme le slash, de la main à la surface visée, où
##     un trait s'allume ;
##   • le LANCER : les trois croissants partent (`vitesse`), bord d'attaque
##     devant. Qui est sur leur passage perd `damage` cœur(s) et il est
##     repoussé dans le sens du coup — une seule fois ;
##   • ils s'enfoncent dans la surface touchée, puis `finie` part.
## LA DIAGONALE est choisie au DÉBUT de la charge et ne bouge plus (on a toute
## la charge pour en sortir). Avec `viser` elle passe par le héros, sans être
## plus plate qu'ANGLE_MIN ni plus raide qu'ANGLE_MAX ; sinon c'est `angle`, du
## côté du héros.
## LES DÉGÂTS suivent le dessin : la bande que balaient les croissants (leur
## envergure, à 15 % près : les pointes pardonnent), là où ils sont à cet
## instant, du bord d'attaque au creux du plus petit.
## Le coup reste OÙ IL A ÉTÉ LANCÉ : le temps qu'il dure, le nœud ne suit plus
## les déplacements de son parent ; à la fin il reprend sa place chez lui.
##
## POUR LE JUGER : ouvrir la scène et faire F6 (les coups s'enchaînent, un côté
## puis l'autre). La forme du slash et des griffes se règle ICI, sur le nœud
## (groupe « Allure » : ce script la donne au shader à chaque image) ; les
## couleurs, le halo et les paillettes sur le matériau du nœud Griffes.
## ============================================================================

signal lancee
signal finie

## la diagonale la plus plate et la plus raide quand on vise (degrés sous
## l'horizontale)
const ANGLE_MIN := 25.0
const ANGLE_MAX := 68.0
## les dernières paillettes s'éteignent en … s après l'impact
const DUREE_TRACE := 0.7
## en automatique, le héros est « à portée » jusqu'à … px du nœud, de côté
const PORTEE_COTE := 1500.0
## le point visé : à cette hauteur au-dessus des pieds du héros (px)
const HAUTEUR_VISEE := 60.0
## la part de l'envergure du slash qui blesse (les pointes pardonnent)
const PART_QUI_BLESSE := 0.85

## sans boss pour le commander : les coups s'enchaînent tout seuls tant que le
## héros est à portée
@export var automatique := true
## en automatique : le silence entre deux coups (s)
@export var pause := 1.6
@export_group("Le coup")
## la diagonale passe par le héros ; sinon elle suit `angle`
@export var viser := true
## la pente de la diagonale quand on ne vise pas (degrés sous l'horizontale)
@export_range(10.0, 80.0) var angle := 45.0
## les griffes se forment … s avant d'être lancées : le temps de sortir de la
## diagonale
@export var charge := 0.8
## les griffes dessinées à la main pendant la charge (à décocher si l'animation
## du boss les montre déjà)
@export var griffes_a_la_main := true
@export_group("Allure")
## le slash : rayon du plus grand des trois croissants (px)
@export var rayon := 170.0
## sa demi-ouverture (degrés) : 90 = un demi-cercle
@export_range(20.0, 85.0) var ouverture := 52.0
## demi-épaisseur d'un croissant en son milieu (px)
@export var epaisseur := 20.0
## écart entre deux croissants (px)
@export var ecart := 46.0
## les griffes à la main : leur longueur et leur demi-épaisseur (px)
@export var taille_main := 340.0
@export var epaisseur_main := 22.0
@export_group("Réglages fins")
## vitesse du slash (px/s)
@export var vitesse := 3000.0
## jusqu'où il va sans rencontrer de mur ni de sol (px)
@export var portee := 1800.0
## secousse de la caméra à l'impact (0 : aucune)
@export var secousse := 4.0
@export_group("Dégâts")
@export var damage := 1
@export_group("")
## lancé seul (F6) : les coups s'enchaînent
@export var demo_boucle := true

@onready var _rect: ColorRect = $Griffes

var _t := 0.0
var _active := false
var _graine := 0
var _dir := Vector2(0.7071, 0.7071)       # la diagonale (unité), dans le repère du monde
var _cote := 1.0
var _longueur := 900.0                    # de la main à la surface touchée (px)
var _normale := Vector2.UP                # la normale de cette surface
var _partie := false                      # le slash a quitté la main
var _touche := false                      # le coup a déjà pris son cœur
var _arrivee := false                     # l'impact a eu lieu
var _ancre := Vector2.ZERO                # sa place chez son parent, le temps d'un coup
var _detache := false                     # il ne suit plus son parent (coup en cours)
var _demo := false
var _demo_n := 0
var _attente := 0.0                       # seul : le silence depuis le dernier coup


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_rect.visible = false
	_demo = demo_boucle and get_parent() == get_tree().root
	if _demo:
		var ecran := get_viewport_rect().size
		position = Vector2(ecran.x * 0.5, ecran.y * 0.3)
		lancer()


## un coup, depuis là où est le nœud ; `cote_impose` : -1 vers la gauche, 1 vers
## la droite, 0 du côté du héros
func lancer(cote_impose := 0) -> void:
	_graine = randi() % 1000
	_t = 0.0
	_partie = false
	_touche = false
	_arrivee = false
	# le coup reste où il est lancé, même si le parent bouge ensuite
	_rattacher()
	if get_parent() is Node2D:
		var ici := global_position
		_ancre = position
		_detache = true
		top_level = true
		global_position = ici
	# la diagonale : son côté, puis sa pente
	var heros := _heros()
	var pente := deg_to_rad(angle)
	_cote = float(signi(cote_impose))
	if _demo:
		_cote = 1.0 if _demo_n % 2 == 0 else -1.0
		pente = deg_to_rad([45.0, 34.0, 58.0][_demo_n % 3])
		_demo_n += 1
	else:
		var vers := Vector2.ZERO
		if heros != null:
			vers = heros.global_position + Vector2(0.0, -HAUTEUR_VISEE) - global_position
		if _cote == 0.0:
			_cote = signf(vers.x)
		if _cote == 0.0:
			_cote = 1.0 if randf() < 0.5 else -1.0
		if viser and heros != null:
			pente = clampf(atan2(vers.y, maxf(vers.x * _cote, 1.0)), deg_to_rad(ANGLE_MIN), deg_to_rad(ANGLE_MAX))
	_dir = Vector2(_cote * cos(pente), sin(pente))
	_chercher_la_surface()
	# le rectangle : de la main à l'impact, plus l'envergure du slash, et la
	# place des griffes au-dessus de la main
	var bout := _dir * _longueur
	var marge := maxf(_demi_bande() + 130.0, 300.0)
	var mini := Vector2(minf(0.0, bout.x), minf(0.0, bout.y)) - Vector2(marge, marge)
	var maxi := Vector2(maxf(0.0, bout.x), maxf(0.0, bout.y)) + Vector2(marge, marge)
	mini.y = minf(mini.y, -(taille_main * 1.3 + 90.0))
	mini.x = minf(mini.x, -(taille_main * 0.8 + 90.0))
	maxi.x = maxf(maxi.x, taille_main * 0.8 + 90.0)
	_rect.position = mini
	_rect.size = maxi - mini
	_active = true
	_rect.visible = true
	_appliquer()


func en_cours() -> bool:
	return _active


## la demi-envergure du slash : ce qu'il balaie de part et d'autre de la diagonale
func _demi_bande() -> float:
	return rayon * sin(deg_to_rad(ouverture))


## sa profondeur : du bord d'attaque du plus grand croissant au creux du plus petit
func _profondeur() -> float:
	return rayon * (1.0 - cos(deg_to_rad(ouverture))) + 2.0 * ecart + epaisseur


## le héros (le premier du groupe "Player")
func _heros() -> Node2D:
	for joueur in get_tree().get_nodes_in_group("Player"):
		if joueur is Node2D:
			return joueur
	return null


## le premier mur ou sol sur la diagonale (couches 1 et 2), à `portee` au plus :
## sa distance à la main et sa normale
func _chercher_la_surface() -> void:
	_longueur = portee
	_normale = -_dir
	if _demo:
		var sol := get_viewport_rect().size.y * 0.86 - position.y
		_longueur = minf(sol / maxf(_dir.y, 0.05), portee)
		_normale = Vector2.UP
		return
	var exclus: Array[RID] = []
	for essai in 6:
		var rayon_q := PhysicsRayQueryParameters2D.create(global_position, global_position + _dir * portee, 0b11)
		rayon_q.exclude = exclus
		var touche := get_world_2d().direct_space_state.intersect_ray(rayon_q)
		if touche.is_empty():
			return
		if touche["collider"] is CharacterBody2D:
			exclus.append(touche["rid"])
			continue
		_longueur = global_position.distance_to(touche["position"])
		var n: Vector2 = touche["normal"]
		if n.length_squared() > 0.01:
			_normale = n.normalized()
		return


## le nœud reprend sa place chez son parent
func _rattacher() -> void:
	if _detache:
		_detache = false
		top_level = false
		position = _ancre


## le héros est-il assez près pour que le coup parte ?
func _heros_a_portee() -> bool:
	var heros := _heros()
	if heros == null:
		return false
	var p := to_local(heros.global_position)
	return absf(p.x) <= PORTEE_COTE and p.y >= -300.0 and p.y <= portee


## le chemin que fait le bord d'attaque avant que tout le slash soit entré dans
## la surface touchée
func _chemin_total() -> float:
	return _longueur + rayon + _demi_bande()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not _active:
		return
	_t += delta
	var tau := _t - charge
	if tau >= 0.0:
		var tete := vitesse * tau
		if not _partie:
			_partie = true
			lancee.emit()
		if not _touche and not _demo and tete <= _chemin_total():
			_blesser(tete)
		if not _arrivee and tete >= _longueur:
			_arrivee = true
			_secouer()
	if _t >= charge + _chemin_total() / maxf(vitesse, 1.0) + DUREE_TRACE:
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
		# seul : un coup, un silence, le suivant
		_attente += delta
		if _attente >= pause:
			_attente = 0.0
			lancer()


## dans l'éditeur seulement : la diagonale de chaque côté (à `angle`), et la
## largeur de ce qui passe
func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var rose := Color(1.0, 0.5, 0.8)
	var pente := deg_to_rad(angle)
	var long := minf(portee, 1000.0)
	var demi := _demi_bande()
	for c: float in [-1.0, 1.0]:
		var d := Vector2(c * cos(pente), sin(pente))
		var n := Vector2(-d.y, d.x)
		draw_line(Vector2.ZERO, d * long, Color(rose, 0.9), 3.0)
		draw_line(n * demi, n * demi + d * long, Color(rose, 0.3), 2.0)
		draw_line(-n * demi, -n * demi + d * long, Color(rose, 0.3), 2.0)
	draw_circle(Vector2.ZERO, 8.0, Color(rose, 0.9))


func _secouer() -> void:
	if secousse <= 0.0 or _demo:
		return
	var cam := get_tree().get_first_node_in_group("Camera")
	if cam != null and cam.has_method("shake"):
		cam.shake(secousse, 10.0)


## qui est sur le passage du slash, dont le bord d'attaque a fait `tete` px,
## perd un cœur et il est repoussé dans le sens du coup ; une seule fois
func _blesser(tete: float) -> void:
	var debut := maxf(tete - _profondeur(), 0.0)
	var fin := minf(tete, _chemin_total())
	if fin - debut < 8.0:
		return
	var forme := RectangleShape2D.new()
	forme.size = Vector2(fin - debut, _demi_bande() * PART_QUI_BLESSE * 2.0)
	var requete := PhysicsShapeQueryParameters2D.new()
	requete.shape = forme
	requete.transform = Transform2D(_dir.angle(), global_position + _dir * (debut + fin) * 0.5)
	requete.collision_mask = 0b1011          # joueur et monstres, comme les pièges
	requete.collide_with_areas = false
	for resultat in get_world_2d().direct_space_state.intersect_shape(requete, 16):
		var corps: Object = resultat["collider"]
		if corps is Node and (corps as Node).is_in_group("Player") and corps.has_method("apply_environment_damage"):
			if corps.apply_environment_damage(damage, Vector2(_cote, -0.4).normalized()):
				_touche = true
			return


func _appliquer() -> void:
	var mat := _rect.material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("taille", _rect.size)
	mat.set_shader_parameter("origine", _rect.position)
	mat.set_shader_parameter("dir", _dir)
	mat.set_shader_parameter("longueur", _longueur)
	mat.set_shader_parameter("normale", _normale)
	mat.set_shader_parameter("cote", _cote)
	mat.set_shader_parameter("temps", _t)
	mat.set_shader_parameter("charge", charge)
	mat.set_shader_parameter("vitesse", vitesse)
	mat.set_shader_parameter("graine", float(_graine))
	mat.set_shader_parameter("griffes_main", 1.0 if griffes_a_la_main else 0.0)
	mat.set_shader_parameter("rayon", rayon)
	mat.set_shader_parameter("ouverture", deg_to_rad(ouverture))
	mat.set_shader_parameter("epaisseur", epaisseur)
	mat.set_shader_parameter("ecart", ecart)
	mat.set_shader_parameter("taille_main", taille_main)
	mat.set_shader_parameter("epaisseur_main", epaisseur_main)
