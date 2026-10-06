@tool
extends Node2D
## ============================================================================
## LE REGARD (6 oct. 2026) — attaque de boss, phase 2. Ses yeux ouverts VISENT
## le héros : un fil de lumière suit son cœur pendant `suivi` s, puis SE FIGE
## `fige` s — le temps de sortir de la ligne — et un RAYON part des yeux le
## long du fil jusqu'au premier mur ou au sol (regard_rose.gdshader). Qui est
## sur la ligne perd `damage` cœur(s) et il est projeté dans le sens du rayon.
## `tirs` regards à la suite, chacun visé de nouveau. LA RÉPONSE : quand le fil
## se fige, sortir de la ligne — un pas de côté si elle est raide, un saut si
## elle est couchée. Elle ne blesse que le héros.
##
## SANS BOSS (`automatique`, coché) : posée dans un niveau (le nœud = l'œil), elle
## enchaîne ses salves toute seule tant que le héros est à portée. Dans
## l'éditeur, un rond rose marque l'œil et un cercle la portée.
## AVEC UN BOSS : il met `automatique` à faux, place le nœud sur ses yeux et
## appelle `lancer()` (`arreter()` coupe net, s'il meurt). Les signaux `vise(n)`,
## `fil_fige(n)`, `tir(n)` donnent le rythme.
## La salve reste OÙ ELLE A ÉTÉ LANCÉE (le nœud ne suit plus son parent) : les
## yeux du boss doivent donc rester en place le temps d'un regard.
##
## POUR LA JUGER : ouvrir la scène et faire F6 (elle vise une cible d'essai qui
## va et vient). L'allure (couleurs) se règle sur le matériau du nœud Rayon.
## ============================================================================

signal finie
signal vise(numero: int)
signal fil_fige(numero: int)
signal tir(numero: int)

## le rayon s'éteint en … s (le même temps que dans le shader)
const DUREE_TIR := 0.4
## en automatique, le héros est « à portée » jusqu'à … px au-delà de la portée
const PORTEE_MARGE := 300.0
## demi-largeur du corps du héros (px)
const DEMI_HEROS := 23.0

## sans boss pour la commander : les salves s'enchaînent toutes seules
@export var automatique := true
## en automatique : le silence entre deux salves (s)
@export var pause := 1.5
@export_group("Le regard")
## regards par salve
@export var tirs := 3
## le fil suit le héros pendant … s
@export var suivi := 0.7
## puis il se fige … s avant le rayon : le temps de sortir de la ligne
@export var fige := 0.5
## après un rayon, le suivant commence … s plus tard
@export var entre_deux := 0.25
## le rayon porte jusqu'à … px (le premier mur ou le sol l'arrête avant)
@export var portee := 2800.0
## la largeur de ce qui blesse (px)
@export var largeur := 56.0
## secousse de la caméra au tir (0 : aucune)
@export var secousse := 4.0
@export_group("Dégâts")
@export var damage := 1
@export_group("")
## lancée seule (F6) : les salves s'enchaînent sur une cible d'essai
@export var demo_boucle := true

@onready var _rect: ColorRect = $Rayon

enum Phase { SUIVI, FIGE, TIR, RIEN }

var _t := 0.0
var _active := false
var _phase := Phase.RIEN
var _numero := 0
var _dir := Vector2.RIGHT          # la direction du fil (unitaire)
var _longueur := 1000.0            # jusqu'au mur, au sol, ou à la portée
var _touche := false               # ce rayon a déjà pris son cœur
var _ancre := Vector2.ZERO
var _detache := false
var _demo := false
var _demo_t := 0.0
var _attente := 0.0
var _graine := 0.0


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_rect.visible = false
	_demo = demo_boucle and get_parent() == get_tree().root
	if _demo:
		var ecran := get_viewport_rect().size
		position = Vector2(ecran.x * 0.5, ecran.y * 0.3)
		queue_redraw()
		lancer()


## une salve, depuis le nœud (les yeux)
func lancer() -> void:
	_rattacher()
	if get_parent() is Node2D:
		var ici := global_position
		_ancre = position
		_detache = true
		top_level = true
		global_position = ici
	_graine = randf() * 6.28
	_numero = 0
	_active = true
	_rect.position = Vector2(-portee - 100.0, -portee - 100.0)
	_rect.size = Vector2(2.0 * portee + 200.0, 2.0 * portee + 200.0)
	_rect.visible = true
	_commencer_un_regard()


func en_cours() -> bool:
	return _active


## la salve s'arrête net (le boss meurt) : plus de rayon, plus de dégâts, et le
## signal `finie` ne part pas
func arreter() -> void:
	if not _active:
		return
	_active = false
	_phase = Phase.RIEN
	_rect.visible = false
	_rattacher()


func _rattacher() -> void:
	if _detache:
		_detache = false
		top_level = false
		position = _ancre


func _commencer_un_regard() -> void:
	_phase = Phase.SUIVI
	_t = 0.0
	_touche = false
	_viser()
	vise.emit(_numero)


## le héros est-il assez près pour qu'elle regarde ?
func _heros_a_portee() -> bool:
	for joueur in get_tree().get_nodes_in_group("Player"):
		if joueur is Node2D:
			if global_position.distance_to((joueur as Node2D).global_position) <= portee + PORTEE_MARGE:
				return true
	return false


## le cœur de la cible : le héros, ou la cible d'essai
func _cible() -> Vector2:
	if _demo:
		var ecran := get_viewport_rect().size
		return Vector2(ecran.x * (0.5 + 0.38 * sin(_demo_t * 0.7)),
				ecran.y * 0.86 - 63.0 - 180.0 * maxf(0.0, sin(_demo_t * 1.9)))
	for joueur in get_tree().get_nodes_in_group("Player"):
		if joueur.has_method("centre_corps"):
			return joueur.centre_corps()
		if joueur is Node2D:
			return (joueur as Node2D).global_position + Vector2(0.0, -63.0)
	return global_position + Vector2(400.0, 0.0)


## le fil : vers la cible, jusqu'au premier mur ou sol (couche 2), ou à la portée
func _viser() -> void:
	var vers := _cible() - global_position
	if vers.length() < 1.0:
		vers = Vector2.RIGHT
	_dir = vers.normalized()
	_longueur = portee
	if _demo:
		var ecran := get_viewport_rect().size
		var sol := ecran.y * 0.86 - global_position.y
		if _dir.y > 0.001:
			_longueur = minf(_longueur, sol / _dir.y)
		return
	var rayon := PhysicsRayQueryParameters2D.create(global_position, global_position + _dir * portee, 2)
	var touche := get_world_2d().direct_space_state.intersect_ray(rayon)
	if not touche.is_empty():
		_longueur = (touche["position"] as Vector2).distance_to(global_position)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not _active:
		return
	_t += delta
	_demo_t += delta
	match _phase:
		Phase.SUIVI:
			_viser()
			if _t >= suivi:
				_phase = Phase.FIGE
				_t = 0.0
				fil_fige.emit(_numero)
		Phase.FIGE:
			if _t >= fige:
				_phase = Phase.TIR
				_t = 0.0
				_graine = randf() * 6.28
				tir.emit(_numero)
				_secouer()
				if not _demo:
					_blesser()
		Phase.TIR:
			if _t >= DUREE_TIR + entre_deux:
				_numero += 1
				if _numero >= maxi(tirs, 1):
					_active = false
					_phase = Phase.RIEN
					_rect.visible = false
					_rattacher()
					finie.emit()
				else:
					_commencer_un_regard()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		queue_redraw()
		return
	if _active:
		_appliquer()
	elif _demo or (automatique and _heros_a_portee()):
		_attente += delta
		if _attente >= pause:
			_attente = 0.0
			lancer()


## dans l'éditeur, en automatique : l'œil et la portée ; en démo : un fond, un sol
func _draw() -> void:
	if Engine.is_editor_hint():
		if not automatique:
			return
		var rose := Color(1.0, 0.5, 0.8)
		draw_circle(Vector2.ZERO, 10.0, Color(rose, 0.9))
		draw_arc(Vector2.ZERO, portee, 0.0, TAU, 96, Color(rose, 0.4), 2.0)
		return
	if not _demo:
		return
	var ecran := get_viewport_rect().size
	var o := -position
	draw_rect(Rect2(o, ecran), Color(0.16, 0.2, 0.36))
	draw_rect(Rect2(o + Vector2(0.0, ecran.y * 0.86), Vector2(ecran.x, ecran.y * 0.14)), Color(0.09, 0.11, 0.22))
	draw_circle(Vector2.ZERO, 14.0, Color(0.5, 0.2, 0.4))
	var cible := _cible() - global_position
	draw_rect(Rect2(cible + Vector2(-23.0, -63.0), Vector2(46.0, 126.0)), Color(0.9, 0.9, 0.96))


func _secouer() -> void:
	if secousse <= 0.0 or _demo:
		return
	var cam := get_tree().get_first_node_in_group("Camera")
	if cam != null and cam.has_method("shake"):
		cam.shake(secousse, 10.0)


## le rayon part : qui est sur la ligne perd un cœur et il est projeté dans le
## sens du rayon ; une seule fois par rayon
func _blesser() -> void:
	if _touche:
		return
	for joueur in get_tree().get_nodes_in_group("Player"):
		if not (joueur is Node2D) or not joueur.has_method("apply_environment_damage"):
			continue
		var c: Vector2
		if joueur.has_method("centre_corps"):
			c = joueur.centre_corps()
		else:
			c = (joueur as Node2D).global_position + Vector2(0.0, -63.0)
		var v := c - global_position
		var t := clampf(v.dot(_dir), 0.0, _longueur)
		var d := (v - _dir * t).length()
		if d <= largeur * 0.5 + DEMI_HEROS and t > 0.0:
			var sens := signf(_dir.x) if absf(_dir.x) > 0.2 else signf(v.x)
			if sens == 0.0:
				sens = 1.0
			if joueur.apply_environment_damage(damage, Vector2(sens, -0.4).normalized()):
				_touche = true
			return


func _appliquer() -> void:
	var mat := _rect.material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("taille", _rect.size)
	mat.set_shader_parameter("origine_rect", _rect.position)
	mat.set_shader_parameter("direction", _dir)
	mat.set_shader_parameter("longueur", _longueur)
	mat.set_shader_parameter("phase", int(_phase))
	mat.set_shader_parameter("temps", _t)
	mat.set_shader_parameter("largeur", largeur)
	mat.set_shader_parameter("graine", _graine)
	if _demo:
		queue_redraw()
