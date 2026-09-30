@tool
extends Node2D
## ============================================================================
## EXPLOSION DE FEU — l'impact de la boule de feu du squelette bleu (visuel
## seul : les dégâts sont dans projectile_feu.gd). 1er oct. 2026 : remplace
## l'éclaboussure de la bloodball recolorée qu'elle utilisait avant.
##
## USAGE EN JEU : projectile_feu.gd l'instancie au point d'impact (le nœud est
## CENTRÉ sur l'impact) ; elle joue une fois, `duree` secondes, puis se
## supprime. La boucle de démo n'existe QUE lancée seule (F6) : posée par le
## jeu, elle ne peut pas tourner en boucle, même si `demo_boucle` est resté
## coché (c'est ce qui arrivait avec l'éclaboussure de la bloodball).
##
## POUR LA JUGER : ouvrir la scène et faire F6, `demo_boucle` la rejoue en
## boucle au milieu de l'écran (monter `duree` pour la voir au ralenti). Dans
## l'éditeur, le curseur `progression` montre n'importe quel instant. Formes et
## couleurs se règlent sur le matériau du nœud Feu ; la taille, c'est celle du
## rectangle (ou l'échelle du nœud).
## ============================================================================

## durée de l'explosion (s)
@export var duree := 0.42
## instant affiché, 0 → 1 (aperçu dans l'éditeur ; en jeu c'est le script)
@export_range(0.0, 1.0, 0.01) var progression := 0.3:
	set(v):
		progression = clampf(v, 0.0, 1.0)
		_appliquer()
## lancée seule (F6) : rejoue en boucle au milieu de l'écran
@export var demo_boucle := true
@export var demo_pause := 0.5
## 1 = un vrai impact ; moins = plus petit, moins chaud
@export_range(0.0, 1.0, 0.01) var puissance := 1.0:
	set(v):
		puissance = v
		_appliquer()

@onready var _feu: ColorRect = $Feu

var _t := 0.0
var _joue := false
var _demo := false
var _graine := 0.0


func _ready() -> void:
	if Engine.is_editor_hint():
		_appliquer()
		return
	_demo = demo_boucle and get_parent() == get_tree().root
	if _demo:
		position = get_viewport_rect().size * 0.5
	jouer()


## (re)lance l'explosion depuis le début, avec un feu différent à chaque fois
func jouer() -> void:
	_t = 0.0
	_joue = true
	_graine = randf() * 100.0
	progression = 0.0


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not _joue:
		return
	_t += delta
	if _t < duree:
		progression = _t / duree
		return
	progression = 1.0
	if not _demo:
		queue_free()
	elif _t >= duree + demo_pause:
		jouer()


func _appliquer() -> void:
	if _feu == null:
		return
	var mat := _feu.material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("progress", progression)
	mat.set_shader_parameter("puissance", puissance)
	mat.set_shader_parameter("graine", _graine)
