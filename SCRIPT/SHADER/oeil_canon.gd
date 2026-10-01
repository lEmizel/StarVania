extends Node2D
## ============================================================================
## ŒIL DU CANON DE VERRE (1er oct. 2026) — talisman « Canon de verre » (des
## stats jusque-là, sans rien à l'écran) : tant qu'il est porté, un petit ŒIL
## DE FEU — l'œil de Sauron, idée de Kaoru — flotte au-dessus de la tête du
## héros (nœud Oeil, oeil_canon.gdshader) : tout fait double, ses coups comme
## ceux qu'il encaisse. Il s'ouvre quand on le porte, se ferme quand on l'ôte,
## et regarde du côté où regarde le héros.
## v2 (le même jour, « plus fidèle à Sauron, moins gros, plus vaporeux » —
## Kaoru) : plus petit, sans trait d'encre, une fente noire dans un cœur jaune
## brûlant, des volutes de feu qui montent (voir le shader).
## Il CLIGNE de temps en temps (Kaoru) : une fois toutes les `clignement_min` à
## `clignement_max` s, parfois deux fois de suite — TOUT se referme, l'œil et son
## feu, comme une flamme qui se ferme sur elle-même, jusqu'à un fil de feu, et se
## rouvre en `duree_clignement` s (`paupiere` du shader).
## Avec la COURONNE de la Vengeance (au même endroit, au-dessus de la tête), il
## ne la chevauche pas : tant qu'elle est levée, il glisse au-dessus d'elle
## (`hauteur_couronne`), puis redescend.
## Enfant du joueur (player.gd, `_oeil_preparer`), créé une fois.
##
## POUR LE JUGER : ouvrir la scène et faire F6 (l'œil seul, ouvert). Sa taille,
## ses volutes et ses couleurs se règlent sur le matériau du nœud Oeil (les
## réglages de la v2 ; ceux de la v1 restés dans la scène ne servent plus).
## ============================================================================

## lancé seul (F6) : l'œil ouvert au milieu de l'écran
@export var demo_boucle := true
## où flotte le MILIEU DE L'ŒIL (repère du joueur : ses pieds à 0) — sans la
## couronne (le haut des cheveux est vers −170 au plus haut), et au-dessus de la
## couronne (le haut de ses pointes vers −218)
@export var hauteur := -190.0
@export var hauteur_couronne := -240.0
## vivacité de la glissade d'une hauteur à l'autre (par seconde)
@export var vitesse_glisse := 10.0
## il s'ouvre, ou se ferme, en… (s)
@export var duree_ouverture := 0.25
## il cligne une fois toutes les… (s, au hasard entre les deux) ; un clignement
## dure… (s) ; la chance qu'il en enchaîne un second juste après
@export var clignement_min := 2.5
@export var clignement_max := 6.0
@export var duree_clignement := 0.22
@export_range(0.0, 1.0) var chance_double := 0.25

const TALISMAN_CANON := "canon"
## l'œil est dessiné un peu SOUS le milieu de son rectangle (ses volutes ont la
## place de monter) : le nœud est remonté d'autant
const CENTRE := Vector2(0.0, 6.0)

## posé par le joueur
var joueur: CharacterBody2D = null

@onready var _oeil: ColorRect = $Oeil

var _ouvert := 0.0
var _temps := 0.0
var _regard := 1.0
var _demo := false
var _prochain_clin := 2.0     # avant le prochain clignement (s)
var _clin := -1.0             # depuis le début du clignement en cours (s ; < 0 : aucun)
var _double := false          # celui-ci sera suivi d'un second
var _suite := false           # le prochain est le second d'un double (pas de troisième)


func _ready() -> void:
	_demo = demo_boucle and get_parent() == get_tree().root
	if _demo:
		position = get_viewport_rect().size * 0.5 - CENTRE
		_ouvert = 1.0
	else:
		position = Vector2(0.0, hauteur) - CENTRE
	_appliquer()


func _process(delta: float) -> void:
	var porte := _demo or Player.talisman_equipe(TALISMAN_CANON)
	_ouvert = move_toward(_ouvert, 1.0 if porte else 0.0, delta / maxf(duree_ouverture, 0.001))
	visible = _ouvert > 0.0
	if not visible:
		return
	_temps += delta
	# il ne cligne que grand ouvert (pas pendant qu'il s'ouvre ou se ferme)
	if _ouvert >= 1.0:
		_cligner_tick(delta)
	else:
		_clin = -1.0
	if not _demo and is_instance_valid(joueur):
		var cible := (hauteur_couronne if joueur.vengeance_active() else hauteur) - CENTRE.y
		position.y = lerpf(position.y, cible, clampf(delta * vitesse_glisse, 0.0, 1.0))
		_regard = lerpf(_regard, float(joueur.last_direction), clampf(delta * 12.0, 0.0, 1.0))
	_appliquer()


## le rythme des clignements : au hasard, parfois deux de suite
func _cligner_tick(delta: float) -> void:
	if _clin >= 0.0:
		_clin += delta
		if _clin >= duree_clignement:
			_clin = -1.0
			if _double:
				_double = false
				_suite = true
				_prochain_clin = 0.09                # le second suit presque aussitôt
			else:
				_prochain_clin = randf_range(clignement_min, clignement_max)
		return
	_prochain_clin -= delta
	if _prochain_clin <= 0.0:
		var double := not _suite and randf() < chance_double
		_suite = false
		cligner(double)


## un clignement maintenant (`double` : un second le suivra)
func cligner(double := false) -> void:
	_clin = 0.0
	_double = double


## son ouverture pendant un clignement : il se referme (40 % du temps), reste
## clos un instant, puis se rouvre un peu plus lentement
func _paupiere() -> float:
	if _clin < 0.0:
		return 1.0
	var t := clampf(_clin / maxf(duree_clignement, 0.001), 0.0, 1.0)
	if t < 0.4:
		return 1.0 - smoothstep(0.0, 0.4, t)
	if t < 0.52:
		return 0.0
	return smoothstep(0.52, 1.0, t)


func _appliquer() -> void:
	var m := _oeil.material as ShaderMaterial
	if m == null:
		return
	m.set_shader_parameter("taille", _oeil.size)
	m.set_shader_parameter("centre", CENTRE)
	m.set_shader_parameter("temps", _temps)
	m.set_shader_parameter("ouvert", smoothstep(0.0, 1.0, _ouvert))
	m.set_shader_parameter("regard", _regard)
	m.set_shader_parameter("paupiere", _paupiere())
