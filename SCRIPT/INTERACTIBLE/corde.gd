@tool
extends Node2D
## ============================================================================
## CORDE — une corde suspendue à une boîte, sur laquelle le joueur se balance.
##
## Deux simulations qui se complètent :
##   • la CORDE elle-même est une chaîne de points (Verlet) : elle se balance
##     toute seule, garde son élan quand le joueur la lâche, et le bout libre
##     pend sous la main du joueur quand il grimpe ;
##   • le BALANCIER du joueur est un pendule rigide (angle + vitesse
##     angulaire) : stable, réactif, sans étirement — c'est lui qui fait le
##     gameplay. Le point de la chaîne où le joueur se tient est épinglé sur
##     sa main, le reste de la corde suit.
##
## Accroche : la Zone (Area2D) épouse la corde ; quand le joueur la touche en
## l'air, la corde appelle `saisir_corde()` sur lui (c'est le joueur qui
## décide selon son état). Côté joueur : état CORDE dans player.gd.
##
## Dans l'éditeur (@tool) : la corde s'affiche droite, à la longueur réglée.
## ============================================================================

## longueur de la corde sous le point d'attache (px)
@export var longueur := 300.0:
	set(v):
		longueur = maxf(v, 20.0)
		_apercu()
## nombre de points de la chaîne (plus = plus souple, un peu plus cher)
@export_range(4, 40) var points := 12:
	set(v):
		points = v
		_apercu()
@export var epaisseur := 6.0:
	set(v):
		epaisseur = v
		if is_node_ready():
			$Ligne.width = v
@export var couleur := Color(0.47, 0.30, 0.16):
	set(v):
		couleur = v
		if is_node_ready():
			$Ligne.default_color = v

@export_group("Physique de la corde")
@export var gravite := 1400.0
## frottement de l'air de la chaîne (1 = aucun)
@export_range(0.9, 1.0) var amortissement := 0.985
@export_range(1, 20) var iterations := 6

@export_group("Balancier du joueur")
## poussée du stick (accélération angulaire, rad/s²) : on pompe en rythme
@export var pompage := 2.4
## freinage du balancier par seconde (0 = éternel)
@export var amortissement_balancier := 0.25
## la corde ne dépasse pas cet angle de part et d'autre de la verticale
@export var angle_max_deg := 105.0
## on ne grimpe pas plus près de la boîte que ça
@export var distance_min := 70.0
@export var vitesse_grimpe := 220.0

@onready var _ligne: Line2D = $Ligne
@onready var _zone: Area2D = $Zone
@onready var _attache: Node2D = $Ancre/Attache

var _pts := PackedVector2Array()
var _prev := PackedVector2Array()
var _segments: Array[CollisionShape2D] = []
var _joueur: Node2D = null
var _theta := 0.0     # angle depuis la verticale (0 = pend droit), + vers la droite
var _omega := 0.0     # vitesse angulaire (rad/s)
var _d := 0.0         # distance main ↔ attache le long de la corde
var _k := -1          # index du point de la chaîne épinglé sur la main


func _ready() -> void:
	_ligne.width = epaisseur
	_ligne.default_color = couleur
	_reinitialiser_chaine()
	if Engine.is_editor_hint():
		_redessiner()
		return
	# une forme de collision par segment, mise à jour chaque frame
	for i in points - 1:
		var cs := CollisionShape2D.new()
		cs.shape = SegmentShape2D.new()
		_zone.add_child(cs)
		_segments.append(cs)
	_mettre_a_jour_zone()
	_redessiner()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_simuler_chaine(delta)
	_mettre_a_jour_zone()
	_redessiner()
	if _joueur == null:
		_scruter_joueur()


# ---------------------------------------------------------------------------
# API pour le joueur
# ---------------------------------------------------------------------------

## Le joueur s'accroche : `main` = position globale de sa main, `vitesse` = sa
## vitesse au moment de la prise (transformée en élan de balancier).
func saisir(joueur: Node2D, main: Vector2, vitesse: Vector2) -> void:
	_joueur = joueur
	var rel := to_local(main) - _attache_locale()
	_d = clampf(rel.length(), distance_min, longueur)
	_theta = atan2(rel.x, rel.y)
	_omega = vitesse.dot(_tangente()) / _d
	_k = clampi(int(round(_d / _segment())), 1, points - 1)


## Un pas de balancier. `axe` = stick gauche/droite (−1..1), `grimpe` = +1
## monte, −1 descend. Retourne la position globale de la main.
func simuler_balancier(delta: float, axe: float, grimpe: float) -> Vector2:
	_d = clampf(_d - grimpe * vitesse_grimpe * delta, distance_min, longueur)
	_k = clampi(int(round(_d / _segment())), 1, points - 1)
	var acc := -(gravite / _d) * sin(_theta) + axe * pompage
	_omega += acc * delta
	_omega *= maxf(0.0, 1.0 - amortissement_balancier * delta)
	_theta += _omega * delta
	var lim := deg_to_rad(angle_max_deg)
	if absf(_theta) > lim:
		_theta = clampf(_theta, -lim, lim)
		_omega = 0.0
	return point_main()


## position globale de la main sur la corde
func point_main() -> Vector2:
	return to_global(_attache_locale() + Vector2(sin(_theta), cos(_theta)) * _d)


## vitesse globale de la main (élan à rendre au joueur quand il lâche)
func vitesse_main() -> Vector2:
	if _joueur == null:
		return Vector2.ZERO
	return _tangente() * (_d * _omega)


## Le joueur lâche : la corde garde son élan.
func lacher() -> void:
	if _k > 0 and _k < points:
		var v := vitesse_main()
		_prev[_k] = _pts[_k] - v * (1.0 / 60.0)
	_joueur = null
	_k = -1


# ---------------------------------------------------------------------------
# Chaîne (Verlet)
# ---------------------------------------------------------------------------

func _segment() -> float:
	return longueur / float(points - 1)


func _attache_locale() -> Vector2:
	if _attache == null:
		return Vector2.ZERO
	return to_local(_attache.global_position)


func _tangente() -> Vector2:
	return Vector2(cos(_theta), -sin(_theta))


func _reinitialiser_chaine() -> void:
	_pts.resize(points)
	_prev.resize(points)
	var a := _attache_locale()
	for i in points:
		_pts[i] = a + Vector2(0.0, _segment() * i)
		_prev[i] = _pts[i]


func _simuler_chaine(delta: float) -> void:
	var a := _attache_locale()
	# point épinglé sur la main du joueur (vitesse tuée : c'est le pendule qui commande)
	if _joueur != null and _k > 0:
		var m := to_local(point_main())
		_pts[_k] = m
		_prev[_k] = m
	# intégration
	var g := Vector2(0.0, gravite) * delta * delta
	for i in range(1, points):
		if i == _k:
			continue
		var v := (_pts[i] - _prev[i]) * amortissement
		_prev[i] = _pts[i]
		_pts[i] += v + g
	# contraintes de distance
	var seg := _segment()
	for it in iterations:
		_pts[0] = a
		for i in points - 1:
			var d := _pts[i + 1] - _pts[i]
			var dist := d.length()
			if dist < 0.0001:
				continue
			var corr := d * ((dist - seg) / dist)
			var fixe_a := (i == 0) or (i == _k)
			var fixe_b := (i + 1 == _k)
			if fixe_a and fixe_b:
				continue
			elif fixe_a:
				_pts[i + 1] -= corr
			elif fixe_b:
				_pts[i] += corr
			else:
				_pts[i] += corr * 0.5
				_pts[i + 1] -= corr * 0.5


func _mettre_a_jour_zone() -> void:
	for i in _segments.size():
		var sh := _segments[i].shape as SegmentShape2D
		sh.a = _pts[i]
		sh.b = _pts[i + 1]


func _redessiner() -> void:
	_ligne.points = _pts


func _scruter_joueur() -> void:
	# un corps déjà dans la zone ne ré-émet pas body_entered : on scrute
	for b in _zone.get_overlapping_bodies():
		if b.is_in_group("Player") and b.has_method("saisir_corde"):
			if b.saisir_corde(self):
				return


# aperçu éditeur : corde droite à la longueur réglée
func _apercu() -> void:
	if not is_node_ready():
		return
	_reinitialiser_chaine()
	if Engine.is_editor_hint():
		_redessiner()
