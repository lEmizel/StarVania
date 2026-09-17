@tool
extends Node2D
## ============================================================================
## JET DE FLAMMES — PROTOTYPE VISUEL (aucun dégât, aucune collision).
##
## Un seul réglage : `puissance`, de 0 (éteint, rien n'est dessiné) à 1 (plein
## jet). Entre les deux, tout suit : longueur, largeur, vitesse du flux, couleur,
## lumière. Le curseur se règle dans l'inspecteur (aperçu direct dans
## l'éditeur) ou s'anime depuis le code avec `regler()`.
##
## La buse est à l'ORIGINE du nœud, le jet part vers le HAUT : pour l'orienter,
## on tourne le nœud (même convention que les piques).
##
## `demo_cycle` : en jeu seulement (F6 sur cette scène), le jet enchaîne tout
## seul éteint → plein jet → veilleuse → éteint, pour juger les transitions.
## À décocher dès qu'on s'en sert pour de vrai.
## ============================================================================

## 0 = éteint … 1 = plein jet
@export_range(0.0, 1.0, 0.01) var puissance := 1.0:
	set(v):
		puissance = clampf(v, 0.0, 1.0)
		_appliquer()
## démonstration automatique (en jeu uniquement, jamais dans l'éditeur)
@export var demo_cycle := true
## énergie de la lumière à pleine puissance (0 = pas de lumière)
@export var energie_lumiere := 0.9
## graine du bruit : 0 = tirée au hasard au démarrage (chaque jet a sa propre
## flamme). Mettre une valeur pour figer l'allure d'un jet précis.
@export var graine := 0.0

@onready var _jet: ColorRect = $Jet
@onready var _lumiere: PointLight2D = $Lumiere

var _t := 0.0
var _tween: Tween = null
var _graine_effective := 0.0


func _ready() -> void:
	_graine_effective = graine if graine != 0.0 else randf_range(1.0, 100.0)
	_appliquer()


## Amène la puissance à `cible` en `duree` secondes (allumage, extinction…).
func regler(cible: float, duree := 0.2) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if duree <= 0.0:
		puissance = cible
		return
	_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "puissance", clampf(cible, 0.0, 1.0), duree)


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not demo_cycle:
		return
	_t = fmod(_t + delta, 8.0)
	puissance = _puissance_demo(_t)


func _appliquer() -> void:
	if not is_node_ready():
		return
	var mat := _jet.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("puissance", puissance)
		mat.set_shader_parameter("graine", _graine_effective)
		# proportions réelles du rectangle, pour que le bruit du shader ne soit pas déformé
		mat.set_shader_parameter("ratio", _jet.size.y / maxf(_jet.size.x, 1.0))
	if _lumiere != null:
		_lumiere.visible = puissance > 0.01 and energie_lumiere > 0.0
		_lumiere.energy = energie_lumiere * puissance
		# la lumière suit le milieu du jet (même loi de longueur que le shader)
		var longueur := (0.12 + 0.68 * pow(puissance, 0.75)) * _jet.size.y   # même loi de portée que le shader
		_lumiere.position = Vector2(0.0, -longueur * 0.45)


## éteint 1 s → allumage → plein jet 2,2 s → veilleuse 2 s → extinction → éteint
func _puissance_demo(t: float) -> float:
	if t < 1.0:
		return 0.0
	if t < 1.3:
		return (t - 1.0) / 0.3
	if t < 3.5:
		return 1.0
	if t < 4.0:
		return lerpf(1.0, 0.12, (t - 3.5) / 0.5)
	if t < 6.0:
		return 0.12
	if t < 6.4:
		return lerpf(0.12, 0.0, (t - 6.0) / 0.4)
	return 0.0
