@tool
extends Node2D
## ============================================================================
## PINCE DE GRAPPIN (2 oct. 2026, d'après le croquis de Kaoru) — le visuel du
## point d'accroche du grappin : une pince vue de face, un moyeu et trois
## branches (pince_grappin.gdshader).
##   • FERMÉE : on ne peut pas s'y accrocher (trop loin, pas au-dessus, un mur…).
##   • OUVERTE : on peut — les branches s'écartent avec un petit rebond et une
##     LUMIÈRE BLEUE s'allume au centre et bat.
##   • TENUE : le grappin y est accroché — elle se REFERME sur le câble, sec,
##     et garde sa lumière tant que le câble est là.
## C'est l'accroche (accroche_grappin.gd) qui la pose et lui dit, à chaque
## image, si elle est `ouvert` et/ou `tenue`.
##
## POUR LA JUGER : ouvrir la scène et faire F6 (fermée, ouverte, tenue, en
## boucle, grossie). Ses formes et ses couleurs : sur le matériau du nœud Pince.
## ============================================================================

## lancée seule (F6) : fermée, ouverte, tenue, en boucle
@export var demo_boucle := true

## posés par l'accroche : prenable maintenant ? le câble y est-il accroché ?
var ouvert := false
var tenue := false

@onready var _rect: ColorRect = $Pince

var _o := 0.0            # ouverture affichée (ressort : elle rebondit en s'ouvrant)
var _v := 0.0
var _lumiere := 0.0
var _t := 0.0
var _demo := false
var _demo_t := 0.0


func _ready() -> void:
	_demo = demo_boucle and not Engine.is_editor_hint() and get_parent() == get_tree().root
	if _demo:
		position = get_viewport_rect().size * 0.5
		scale = Vector2(4.0, 4.0)
	_appliquer()


func _process(delta: float) -> void:
	_t += delta
	if _demo:
		_demo_tick(delta)
	var veut_ouvrir := ouvert and not tenue
	# un ressort : elle s'ouvre avec un petit rebond, se referme sec
	var raideur := 220.0 if veut_ouvrir else 420.0
	var amorti := 19.0 if veut_ouvrir else 34.0
	_v += ((1.0 if veut_ouvrir else 0.0) - _o) * raideur * delta - _v * amorti * delta
	_o = clampf(_o + _v * delta, -0.15, 1.25)
	var luit := ouvert or tenue
	_lumiere = move_toward(_lumiere, 1.0 if luit else 0.0, delta * (8.0 if luit else 5.0))
	_appliquer()


## F6 : 1 s fermée, 2 s ouverte, 1,2 s tenue (refermée, allumée), en boucle
func _demo_tick(delta: float) -> void:
	_demo_t = fmod(_demo_t + delta, 4.6)
	ouvert = _demo_t >= 1.0 and _demo_t < 3.0
	tenue = _demo_t >= 3.0 and _demo_t < 4.2


func _appliquer() -> void:
	if _rect == null:
		return
	var mat := _rect.material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("taille", _rect.size)
	mat.set_shader_parameter("ouverture", _o)
	mat.set_shader_parameter("lumiere", _lumiere)
	mat.set_shader_parameter("temps", _t)
