extends Node2D
## ============================================================================
## CHOC DE PARADE (1er oct. 2026) — talisman « Parade » : le « clang » posé là
## où l'épée du héros pare un coup (nœud Choc, parade_choc.gdshader). Il joue
## une fois en `duree` s puis se supprime. Posé par player.gd (`_parade_choc`).
##
## POUR LE JUGER : ouvrir la scène et faire F6 (en boucle au milieu de
## l'écran — seulement lancé seul ; monter `duree` pour le voir au ralenti).
## ============================================================================

## lancé seul (F6) : il rejoue en boucle
@export var demo_boucle := true
@export var duree := 0.22
@export var demo_pause := 0.5

@onready var _choc: ColorRect = $Choc

var _t := 0.0
var _demo := false
var _graine := 0.0


func _ready() -> void:
	_graine = randf() * 50.0
	_demo = demo_boucle and get_parent() == get_tree().root
	if _demo:
		position = get_viewport_rect().size * 0.5
	_appliquer()


func _process(delta: float) -> void:
	_t += delta
	if _t > duree:
		if not _demo:
			queue_free()
			return
		if _t >= duree + demo_pause:
			_t = 0.0
			_graine = randf() * 50.0
	_appliquer()


func _appliquer() -> void:
	var m := _choc.material as ShaderMaterial
	if m == null:
		return
	m.set_shader_parameter("taille", _choc.size)
	m.set_shader_parameter("progress", clampf(_t / maxf(duree, 0.001), 0.0, 1.0))
	m.set_shader_parameter("graine", _graine)
