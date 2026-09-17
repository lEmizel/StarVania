@tool
extends "res://SCRIPT/INTERACTIBLE/accroche_grappin.gd"
## ============================================================================
## ACCROCHE PENDULAIRE — la cousine BLEUE de l'accroche de grappin.
##
## Même détection, même touche (R1), même câble qui file vers le point. Mais
## au lieu de hisser puis catapulter, le grappin RESTE accroché : le joueur est
## suspendu au câble et joue exactement comme à la corde (état CORDE de
## player.gd) — stick gauche/droite = on pompe en rythme, haut/bas = on
## remonte/descend le long du câble, saut = on se lâche avec l'élan, esquive =
## on se laisse tomber.
##
## Ce script fournit donc DEUX API :
##   • celle d'une accroche (héritée : point, surligner, cable_montrer/cacher) ;
##   • celle d'une corde (saisir, simuler_balancier, point_main, vitesse_main,
##     lacher) : un pendule rigide autour du point, sans chaîne à simuler.
##
## Différences avec la corde :
##   • TREUIL : on peut s'accrocher de loin (portée du grappin), or un pendule
##     très long est lent et racle le sol → le câble se raccourcit tout seul
##     jusqu'à `longueur_confort` (et décolle les pieds si on part du sol) ;
##   • COLLISIONS : le joueur se déplace avec collisions (player.gd) et nous
##     signale un blocage → le pendule repart de la position réelle, sans élan.
##
## Dans l'éditeur : anneau bleu + petit pendule dessous, cercle de portée, et
## l'arc que décrira la main à la longueur de confort.
## ============================================================================

@export_group("Balancier")
## mêmes valeurs par défaut que corde.gd : le maniement est celui de la corde
@export var gravite := 1400.0
## poussée du stick (accélération angulaire, rad/s²) : on pompe en rythme
@export var pompage := 2.4
## freinage du balancier par seconde (0 = éternel)
@export var amortissement_balancier := 0.25
## le câble ne dépasse pas cet angle de part et d'autre de la verticale
@export var angle_max_deg := 105.0
@export var vitesse_grimpe := 220.0

@export_group("Câble")
## on ne remonte pas plus près du point que ça
@export var longueur_min := 90.0
## longueur maxi en descendant (≥ portée du grappin, sinon la prise téléporte)
@export var longueur_max := 560.0
## le treuil raccourcit le câble jusqu'à cette longueur après la prise
## (mettre la même valeur que longueur_max pour couper le treuil)
@export var longueur_confort := 260.0:
	set(v):
		longueur_confort = v
		queue_redraw()
## vitesse du treuil (px/s)
@export var vitesse_treuil := 500.0
## prise depuis le SOL : le treuil remonte au moins d'autant, pour décoller les pieds
@export var degagement_sol := 60.0

var _joueur: Node2D = null
var _theta := 0.0      # angle depuis la verticale (0 = pend droit), + vers la droite
var _omega := 0.0      # vitesse angulaire (rad/s)
var _d := 0.0          # longueur de câble entre le point et la main
var _d_cible := 0.0    # longueur visée par le treuil
var _treuil := false


# ---------------------------------------------------------------------------
# API « corde » pour l'état CORDE du joueur
# ---------------------------------------------------------------------------

## Le grappin vient de se planter : `main` = position globale de la main,
## `vitesse` = vitesse du joueur à cet instant (devient l'élan du balancier).
func saisir(joueur: Node2D, main: Vector2, vitesse: Vector2) -> void:
	_joueur = joueur
	var rel := main - point()
	_d = clampf(rel.length(), longueur_min, longueur_max)
	_theta = atan2(rel.x, rel.y)
	_omega = vitesse.dot(_tangente()) / _d
	_d_cible = minf(_d, longueur_confort)
	if joueur is CharacterBody2D and (joueur as CharacterBody2D).is_on_floor():
		_d_cible = minf(_d_cible, _d - degagement_sol)
	_d_cible = maxf(_d_cible, longueur_min)
	_treuil = _d > _d_cible


## Un pas de balancier. `axe` = stick gauche/droite (−1..1), `grimpe` = +1
## monte, −1 descend. Retourne la position globale VISÉE pour la main.
func simuler_balancier(delta: float, axe: float, grimpe: float) -> Vector2:
	if grimpe < -0.5:
		_treuil = false            # le joueur veut descendre : le treuil lâche l'affaire
	if _treuil:
		var d_avant := _d
		_d = maxf(_d_cible, _d - vitesse_treuil * delta)
		_omega *= d_avant / _d     # vitesse le long de l'arc conservée : le balancier s'anime
		if _d <= _d_cible:
			_treuil = false
	_d = clampf(_d - grimpe * vitesse_grimpe * delta, longueur_min, longueur_max)
	var acc := -(gravite / _d) * sin(_theta) + axe * pompage
	_omega += acc * delta
	_omega *= maxf(0.0, 1.0 - amortissement_balancier * delta)
	_theta += _omega * delta
	var lim := deg_to_rad(angle_max_deg)
	if absf(_theta) > lim:
		_theta = clampf(_theta, -lim, lim)
		_omega = 0.0
	return point_main()


## Le joueur n'a pas pu atteindre la position visée (sol, mur, plafond) : le
## pendule repart de la position RÉELLE de la main, sans élan. Bloqué par le
## sol, le treuil remonte un peu : on ne reste pas « suspendu » debout.
func signaler_blocage(main_reelle: Vector2, normale: Vector2, delta: float) -> void:
	var rel := main_reelle - point()
	_d = clampf(rel.length(), longueur_min, longueur_max)
	_theta = atan2(rel.x, rel.y)
	_omega = 0.0
	if normale.y < -0.5:
		_d = maxf(longueur_min, _d - vitesse_treuil * delta)


## position globale visée pour la main, au bout du câble
func point_main() -> Vector2:
	return point() + Vector2(sin(_theta), cos(_theta)) * _d


## vitesse globale de la main (élan rendu au joueur quand il se lâche)
func vitesse_main() -> Vector2:
	if _joueur == null:
		return Vector2.ZERO
	return _tangente() * (_d * _omega)


func lacher() -> void:
	_joueur = null
	_treuil = false
	cable_cacher()


func _tangente() -> Vector2:
	return Vector2(cos(_theta), -sin(_theta))


# ---------------------------------------------------------------------------

func _draw() -> void:
	super()
	var c := couleur_active if _actif else couleur_anneau
	# le petit pendule sous l'anneau : on reconnaît le type à la FORME aussi
	draw_arc(Vector2.ZERO, 25.0, deg_to_rad(40.0), deg_to_rad(140.0), 14, c, 2.0)
	draw_circle(Vector2(0.0, 25.0), 4.0, c)
	if Engine.is_editor_hint():
		# l'arc que décrira la main une fois le câble à sa longueur de confort
		draw_arc(Vector2.ZERO, longueur_confort, deg_to_rad(30.0), deg_to_rad(150.0), 40,
			Color(couleur_anneau, 0.4), 1.5)
