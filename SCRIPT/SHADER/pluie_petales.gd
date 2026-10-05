@tool
extends Node2D
## ============================================================================
## PLUIE DE PÉTALES (5 oct. 2026) — attaque de boss. Sous ses ailes, le boss
## fait pleuvoir des rideaux serrés de pétales lumineux, de la hauteur du nœud
## jusqu'au sol (pluie_petales.gdshader). LA RÉPONSE : ne pas être sous lui
## quand ça tombe. Il n'y a pas de place entre les rideaux : on en sort par les
## côtés. Elle ne blesse que le héros.
##
## SANS BOSS (`automatique`, coché) : posée dans un niveau à la hauteur d'où
## tombent les pétales, elle enchaîne ses salves toute seule tant que le héros
## est à portée (à peu près : à l'écran). Dans l'éditeur, un trait rose montre
## la ligne d'où ils tombent, deux traits la largeur de ce qui blesse, et des
## traits pâles la place des rideaux, jusqu'où le sol est cherché.
## AVEC UN BOSS : il met `automatique` à faux, règle `envergure` sur ses ailes
## et appelle `lancer()` ; le nœud se place à la hauteur de ses ailes.
##
## Une salve :
##   • `delai_avertissement` s d'ANNONCE, brève : sous toute l'envergure, des
##     filets de lueur et des paillettes, et le sol s'allume d'un trait. C'est
##     le boss qui prévient vraiment, en se mettant en place : qui est dessous
##     n'attend pas l'annonce pour partir ;
##   • `duree` s de PLUIE, LANCÉE : les premiers pétales partent d'un trait
##     (`impulsion` px de plus que la chute normale, épuisés en
##     `impulsion_duree` s), comme jetés par un coup d'aile, du milieu vers
##     les bords (`balayage`) ; puis ils tombent à leur `vitesse`. Qui est
##     dessous perd `damage` cœur(s) et il est repoussé vers le bord le plus
##     proche, puis de nouveau toutes les `repit` s tant qu'il y reste ;
##   • la braise au sol s'éteint, puis le signal `finie` part.
## La salve reste OÙ ELLE A ÉTÉ LANCÉE : le temps qu'elle dure, le nœud ne suit
## plus les déplacements de son parent (le boss peut bouger pendant que ses
## pétales tombent) ; à la fin il reprend sa place chez lui.
## Chaque rideau tombe sur le premier sol sous lui (couches 1 et 2) ; sans sol
## à moins de `chute` px, il se perd dans le vide.
## LES DÉGÂTS suivent le dessin : toute la largeur de la pluie blesse (à
## BORD_INDULGENT px près), à la hauteur où sont les pétales à cet endroit — du
## dernier parti au premier, arrêtés au sol (`_tombe` : la même loi de chute
## que le shader).
##
## POUR LA JUGER : ouvrir la scène et faire F6 (les salves s'enchaînent).
## L'allure (taille et couleurs des pétales, paillettes, halo) se règle sur le
## matériau du nœud Petales.
## ============================================================================

signal finie

## nombre de rideaux d'une salve (le shader en prend autant)
const MAX_COLONNES := 32
## la braise au sol s'éteint en … s après le dernier pétale
const DUREE_TRACE := 0.6
## en automatique, le héros est « à portée » jusqu'à … px au-delà de la pluie
const PORTEE_MARGE := 500.0
## ce qui blesse s'arrête … px avant le bord de l'envergure (les derniers
## pétales y sont rares)
const BORD_INDULGENT := 20.0
## demi-largeur de la bande de pluie comparée au corps du héros (px)
const DEMI_SONDE := 20.0

## sans boss pour la commander : les salves s'enchaînent toutes seules tant que
## le héros est à portée
@export var automatique := true
## en automatique : le silence entre deux salves (s)
@export var pause := 1.7
@export_group("La pluie")
## demi-largeur de la pluie, de part et d'autre du nœud (px) : les ailes du
## boss. Tout ce qui est dessous blesse.
@export var envergure := 520.0
## durée de la pluie (s)
@export var duree := 4.2
## l'annonce, avant le premier pétale (s)
@export var delai_avertissement := 0.4
## le LANCER : ce que les premiers pétales font de plus que leur chute normale
## (px) — plus c'est grand, plus ils partent vite — et en combien de temps cet
## élan s'épuise (s)
@export var impulsion := 600.0
@export var impulsion_duree := 0.25
@export_group("Réglages fins")
## écart entre deux rideaux (px) ; assez serrés pour qu'on ne tienne pas entre
## eux (ils sont répartis pour remplir juste l'envergure)
@export var espacement := 118.0
## vitesse de chute, une fois l'élan du lancer épuisé (px/s)
@export var vitesse := 700.0
## les rideaux du bord partent … s après ceux du milieu
@export var balayage := 0.2
## jusqu'où l'on cherche le sol sous le nœud (px) ; plus bas, les pétales se
## perdent dans le vide
@export var chute := 1600.0
## écart au hasard de chaque rideau, en part de l'espacement
@export_range(0.0, 0.3) var desordre := 0.08
@export_group("Dégâts")
@export var damage := 1
## après un coup, la pluie ne blesse plus pendant … s : le temps de sortir, même
## en repartant du mauvais côté
@export var repit := 1.5
@export_group("")
## lancée seule (F6) : les salves s'enchaînent
@export var demo_boucle := true

@onready var _rect: ColorRect = $Petales

var _t := 0.0
var _active := false
var _graine := 0
var _colonnes_x := PackedFloat32Array()   # abscisses des rideaux, dans le repère du nœud
var _sols := PackedFloat32Array()         # hauteur du sol sous chacun (> chute : aucun)
var _base_x := 0.0                        # abscisse du premier rideau, sans son écart
var _pas := 118.0                         # l'écart réel entre deux rideaux
var _fin := 0.0                           # l'heure où tout est éteint
var _repit_reste := 0.0                   # après un coup : le temps où elle ne blesse plus
var _ancre := Vector2.ZERO                # sa place chez son parent, le temps d'une salve
var _detache := false                     # il ne suit plus son parent (salve en cours)
var _demo := false
var _attente := 0.0                       # seule : le silence depuis la dernière salve


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_rect.visible = false
	_demo = demo_boucle and get_parent() == get_tree().root
	if _demo:
		var ecran := get_viewport_rect().size
		position = Vector2(ecran.x * 0.5, ecran.y * 0.12)
		envergure = minf(envergure, ecran.x * 0.5 - 60.0)
		lancer()


## une salve, là où est le nœud
func lancer() -> void:
	_graine = randi() % 1000
	_t = 0.0
	_repit_reste = 0.0
	# la salve reste où elle est lancée, même si le parent bouge ensuite
	_rattacher()
	if get_parent() is Node2D:
		var ici := global_position
		_ancre = position
		_detache = true
		top_level = true
		global_position = ici
	_colonnes_x = PackedFloat32Array()
	_sols = PackedFloat32Array()
	var n := _nb_rideaux()
	_pas = 2.0 * envergure / n
	_base_x = -envergure + _pas * 0.5
	var plus_bas := 0.0
	_fin = 0.0
	for rang in n:
		var x := _base_x + rang * _pas + (randf() - 0.5) * 2.0 * desordre * _pas
		var sol := _sol_sous(x)
		_colonnes_x.append(x)
		_sols.append(sol)
		var fond := minf(sol, chute)
		plus_bas = maxf(plus_bas, fond)
		_fin = maxf(_fin, delai_avertissement + _retard(x) + duree + fond / maxf(vitesse, 1.0))
	_fin += DUREE_TRACE
	# le rectangle : toute la largeur de la pluie, de la ligne de départ au sol le plus bas
	_rect.position = Vector2(-envergure - 140.0, -90.0)
	_rect.size = Vector2(2.0 * envergure + 280.0, plus_bas + 90.0 + 70.0)
	_active = true
	_rect.visible = true
	_appliquer()


func en_cours() -> bool:
	return _active


## le nombre de rideaux : de quoi remplir juste l'envergure, à l'espacement près
func _nb_rideaux() -> int:
	return clampi(roundi(2.0 * envergure / maxf(espacement, 20.0)), 1, MAX_COLONNES)


## le nœud reprend sa place chez son parent
func _rattacher() -> void:
	if _detache:
		_detache = false
		top_level = false
		position = _ancre


## le héros est-il assez près pour que la pluie tombe ?
func _heros_a_portee() -> bool:
	for joueur in get_tree().get_nodes_in_group("Player"):
		if joueur is Node2D:
			var p := to_local((joueur as Node2D).global_position)
			if absf(p.x) <= envergure + PORTEE_MARGE and p.y >= -PORTEE_MARGE and p.y <= chute + PORTEE_MARGE:
				return true
	return false


## le chemin fait par un pétale `tau` s après le départ de son rideau : l'élan
## du lancer, vite épuisé, puis la vitesse de croisière (la même loi que le
## shader)
func _tombe(tau: float) -> float:
	return vitesse * tau + impulsion * (1.0 - exp(-tau / maxf(impulsion_duree, 0.01)))


## le retard de la pluie à l'abscisse `x` : les bords partent après le milieu
func _retard(x: float) -> float:
	return balayage * clampf(absf(x) / maxf(envergure, 1.0), 0.0, 1.0)


## la hauteur du premier sol sous la ligne de départ, à l'abscisse `x` (repère
## du nœud) ; plus que `chute` : aucun
func _sol_sous(x: float) -> float:
	if _demo:
		return get_viewport_rect().size.y * 0.86 - position.y
	var depuis := global_position + Vector2(x, 2.0)
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
	return chute + 1000.0


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not _active:
		return
	_t += delta
	_repit_reste = maxf(_repit_reste - delta, 0.0)
	if _repit_reste <= 0.0 and not _demo:
		_blesser()
	if _t >= _fin:
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


## dans l'éditeur seulement : la ligne d'où tombent les pétales, la largeur de
## ce qui blesse, et la place des rideaux (sans leur écart au hasard) jusqu'où
## le sol est cherché
func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var rose := Color(1.0, 0.5, 0.8)
	draw_line(Vector2(-envergure, 0.0), Vector2(envergure, 0.0), Color(rose, 0.9), 3.0)
	draw_line(Vector2(-envergure, 0.0), Vector2(-envergure, chute), Color(rose, 0.8), 3.0)
	draw_line(Vector2(envergure, 0.0), Vector2(envergure, chute), Color(rose, 0.8), 3.0)
	var n := _nb_rideaux()
	var pas := 2.0 * envergure / n
	for rang in n:
		var x := -envergure + (rang + 0.5) * pas
		draw_line(Vector2(x, 0.0), Vector2(x, chute), Color(rose, 0.25), 2.0)


## la hauteur où sont les pétales à l'abscisse `x` (repère du nœud) : du dernier
## parti au premier, arrêtés au sol du rideau le plus proche
func _troncon_en(x: float) -> Vector2:
	var rang := clampi(int(floor((x - _base_x) / maxf(_pas, 1.0) + 0.5)), 0, _colonnes_x.size() - 1)
	var fond := minf(_sols[rang], chute)
	var tau := _t - delai_avertissement - _retard(x)
	if tau <= 0.0:
		return Vector2.ZERO
	var fait := _tombe(tau)
	return Vector2(clampf(fait - _tombe(duree), 0.0, fond), minf(fait, fond))


## qui est sous la pluie perd un cœur et il est repoussé vers le bord le plus
## proche ; puis elle lui laisse `repit` s pour sortir
func _blesser() -> void:
	if _colonnes_x.is_empty():
		return
	var demi := maxf(envergure - BORD_INDULGENT, DEMI_SONDE)
	for joueur in get_tree().get_nodes_in_group("Player"):
		if not (joueur is Node2D) or not joueur.has_method("apply_environment_damage"):
			continue
		var p := to_local((joueur as Node2D).global_position)
		if absf(p.x) > demi + 150.0:
			continue
		# la bande de pluie la plus proche de lui : sous lui, s'il est dessous
		var x := clampf(p.x, -(demi - DEMI_SONDE), demi - DEMI_SONDE)
		var troncon := _troncon_en(x)
		if troncon.y - troncon.x < 6.0 or not _corps_dans(joueur, x, troncon):
			continue
		var cote := signf(p.x)
		if cote == 0.0:
			cote = 1.0 if randf() < 0.5 else -1.0
		if joueur.apply_environment_damage(damage, Vector2(cote, -0.35).normalized()):
			_repit_reste = repit
		return


## le corps de `joueur` touche-t-il ce tronçon de la bande de pluie d'abscisse `x` ?
func _corps_dans(joueur: Node, x: float, troncon: Vector2) -> bool:
	var forme := RectangleShape2D.new()
	forme.size = Vector2(DEMI_SONDE * 2.0, troncon.y - troncon.x)
	var requete := PhysicsShapeQueryParameters2D.new()
	requete.shape = forme
	requete.transform = Transform2D(0.0, global_position + Vector2(x, (troncon.x + troncon.y) * 0.5))
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
	var xs := PackedFloat32Array()
	var sols := PackedFloat32Array()
	xs.resize(MAX_COLONNES)
	sols.resize(MAX_COLONNES)
	for rang in _colonnes_x.size():
		xs[rang] = _colonnes_x[rang]
		sols[rang] = _sols[rang]
	mat.set_shader_parameter("taille", _rect.size)
	mat.set_shader_parameter("origine", _rect.position)
	mat.set_shader_parameter("nb_colonnes", _colonnes_x.size())
	mat.set_shader_parameter("colonnes_x", xs)
	mat.set_shader_parameter("sols", sols)
	mat.set_shader_parameter("base_x", _base_x)
	mat.set_shader_parameter("espacement", maxf(_pas, 1.0))
	mat.set_shader_parameter("chute", chute)
	mat.set_shader_parameter("envergure", envergure)
	mat.set_shader_parameter("temps", _t)
	mat.set_shader_parameter("delai", delai_avertissement)
	mat.set_shader_parameter("duree", duree)
	mat.set_shader_parameter("balayage", balayage)
	mat.set_shader_parameter("vitesse", vitesse)
	mat.set_shader_parameter("impulsion", impulsion)
	mat.set_shader_parameter("impulsion_duree", impulsion_duree)
	mat.set_shader_parameter("graine", float(_graine))
