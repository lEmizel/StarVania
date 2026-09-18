@tool
extends Node2D
## ============================================================================
## BOULE DE FEU — VISUEL de projectile (aucun dégât, aucune collision).
##
## L'ORIGINE DU NŒUD EST LE CENTRE DE LA BOULE : on pose ce nœud à la position
## du projectile, la traînée s'étire toute seule derrière. La boule vole vers la
## DROITE de son repère ; `scale.x = -1` la fait voler vers la gauche (comme
## bloodball.tscn), et on tourne le nœud pour un tir en diagonale.
##
## Un seul réglage : `puissance`, de 0 (rien n'est dessiné) à 1 (pleine boule).
## Longueur de traînée, taille, chaleur et lumière suivent. `regler(cible,
## duree)` l'anime : allumage au tir, extinction à l'impact.
##
## `demo_vol` : en jeu seulement, la boule fait des allers-retours pour juger la
## traînée en mouvement. À DÉCROCHER dès qu'on s'en sert pour de vrai — le
## script du projectile qui l'utilisera doit le mettre à false, comme
## piege_de_flamme.gd le fait pour ses jets.
## ============================================================================

## 0 = rien … 1 = pleine boule
@export_range(0.0, 1.0, 0.01) var puissance := 1.0:
	set(v):
		puissance = clampf(v, 0.0, 1.0)
		_appliquer()
## démonstration automatique (en jeu uniquement, jamais dans l'éditeur)
@export var demo_vol := true
## énergie de la lumière à pleine puissance (0 = pas de lumière)
@export var energie_lumiere := 0.8
## graine du bruit : 0 = tirée au hasard au démarrage (deux boules tirées
## ensemble ne sont pas jumelles). Mettre une valeur pour figer une allure.
@export var graine := 0.0

@onready var _boule: ColorRect = $Boule
@onready var _lumiere: PointLight2D = $Lumiere

var _t := 0.0
var _depart := Vector2.ZERO
var _tween: Tween = null
var _graine_effective := 0.0


func _ready() -> void:
	_graine_effective = graine if graine != 0.0 else randf_range(1.0, 100.0)
	_depart = position
	_appliquer()


## Amène la puissance à `cible` en `duree` secondes (allumage au tir, extinction
## à l'impact). `duree` = 0 applique tout de suite.
func regler(cible: float, duree := 0.15) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if duree <= 0.0:
		puissance = cible
		return
	_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "puissance", clampf(cible, 0.0, 1.0), duree)


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not demo_vol:
		return
	# aller-retour de 700 px : la traînée se retourne avec la boule
	_t = fmod(_t + delta, 4.0)
	var aller := _t < 2.0
	var avance := (_t if aller else 4.0 - _t) / 2.0
	position.x = _depart.x + (avance - 0.5) * 700.0 * (1.0 if aller else 1.0)
	scale.x = absf(scale.x) * (1.0 if aller else -1.0)


func _appliquer() -> void:
	if not is_node_ready():
		return
	var mat := _boule.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("puissance", puissance)
		mat.set_shader_parameter("graine", _graine_effective)
		# proportions réelles du rectangle, pour que le bruit ne soit pas déformé
		mat.set_shader_parameter("ratio", _boule.size.x / maxf(_boule.size.y, 1.0))
	if _lumiere != null:
		_lumiere.visible = puissance > 0.01 and energie_lumiere > 0.0
		_lumiere.energy = energie_lumiere * puissance
